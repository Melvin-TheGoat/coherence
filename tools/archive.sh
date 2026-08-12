#!/bin/bash
# Builds a TestFlight-ready .ipa of 808.
#
#   ./tools/archive.sh
#
# Then upload it: Xcode → Window → Organizer → Distribute App, or drag the
# .ipa into Transporter. Uploading is left to a human on purpose, because it
# is the step that needs the App Store Connect record to exist and is worth
# watching the first time.
#
# WHAT THIS ADDS over Product → Archive in Xcode:
#
#   Build number. App Store Connect rejects a build number it has seen before,
#   and project.yml hardcodes 1, so the second upload would bounce. This stamps
#   a UTC timestamp: monotonic by construction, no state to keep anywhere.
#
#   The export. Archiving alone leaves you a development-signed archive; the
#   distribution signature is applied on export, which is also where
#   aps-environment becomes production and get-task-allow becomes false. Doing
#   both here means the thing you upload is the thing this script tested.
#
# WHAT IT DELIBERATELY DOES NOT DO, learned by trying it:
#
#   An earlier version overrode CODE_SIGN_ENTITLEMENTS to force
#   aps-environment=production, on the theory that the committed entitlements
#   say development. Two things were wrong with that. A setting passed on the
#   xcodebuild command line applies to EVERY target, so it forced the iPhone's
#   entitlements onto the Watch and the build died on a Watch profile that
#   quite rightly has no push, no iCloud and no Sign in with Apple. And it was
#   unnecessary anyway: export rewrites aps-environment to production by
#   itself. Verified on a real export, 2026-08-11.
#
# NOTE the one thing this cannot check for you: TestFlight talks to the
# PRODUCTION CloudKit container (the exported build asks for exactly that, in
# com.apple.developer.icloud-container-environment). Your schema only exists in
# Development until you promote it in the CloudKit Dashboard, and until you do,
# sync will silently do nothing.

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD="$(date -u +%Y%m%d%H%M)"
# Archive into Xcode's own folder, not into build/. Organizer only lists what
# lives here, and an archive it cannot see is an archive you cannot upload
# through the GUI, which is how the first one nearly got missed.
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/808-${BUILD}.xcarchive"
EXPORT="build/808-${BUILD}"
mkdir -p "$(dirname "$ARCHIVE")"

# The team is per-developer and lives in an uncommitted project.yml, so read it
# from the project rather than hardcoding anyone's here.
TEAM="$(xcodebuild -scheme Coherence -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ DEVELOPMENT_TEAM = /{print $2; exit}' | tr -d ' ')"
if [ -z "$TEAM" ]; then
  echo "No DEVELOPMENT_TEAM in the project. Set it in project.yml and re-run."
  exit 1
fi

echo "Archiving 808, build ${BUILD}, team ${TEAM}"

xcodebuild archive \
  -scheme Coherence \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | grep -E 'error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED' || true

[ -d "$ARCHIVE" ] || { echo "No archive produced. See the errors above."; exit 1; }

OPTIONS="$(mktemp -d)/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "Exporting for App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates \
  | grep -E 'error:|EXPORT SUCCEEDED|EXPORT FAILED' || true

IPA="$(find "$EXPORT" -name '*.ipa' -maxdepth 1 2>/dev/null | head -1)"
[ -n "$IPA" ] || { echo "No .ipa produced. See the errors above."; exit 1; }

echo
echo "Build ${BUILD}, version $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist" 2>/dev/null || echo '?')"
echo "  ${IPA}"

# Look inside the thing before uploading it. A development signature is the
# one failure that gets all the way to App Store Connect before anyone
# notices, and it costs a round trip through processing to find out.
UNPACKED="$(mktemp -d)"
if unzip -q "$IPA" -d "$UNPACKED" 2>/dev/null; then
  APP="$(find "$UNPACKED/Payload" -maxdepth 1 -name '*.app' | head -1)"
  ENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true)"
  echo
  for check in "get-task-allow.*(false|0):distribution signature" \
               "aps-environment.*production:push set to production" \
               "icloud-container-environment.*Production:CloudKit pointed at production"; do
    pattern="${check%%:*}"; label="${check##*:}"
    if echo "$ENTS" | grep -qE "$pattern"; then
      echo "  ok    ${label}"
    else
      echo "  WRONG ${label}"
    fi
  done
  if [ -d "$APP/Watch" ]; then
    echo "  ok    Watch app embedded ($(basename "$APP/Watch"/*.app))"
  else
    echo "  WRONG no Watch app embedded, so testers get no measuring"
  fi
  if [ -f "$APP/PrivacyInfo.xcprivacy" ]; then
    echo "  ok    privacy manifest present"
  else
    echo "  WRONG no privacy manifest (ITMS-91053 territory at upload)"
  fi
  rm -rf "$UNPACKED"
fi

echo
echo "Upload: Xcode → Window → Organizer → Distribute App, or drop the .ipa"
echo "into Transporter. Both want the App Store Connect record to exist first."
