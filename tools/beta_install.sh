#!/bin/bash
# Installs the CURRENT tree on a phone as "808 Beta", side by side with the
# App Store app, under com.lockout.meditate808.dev (+ .dev.watchkitapp).
#
#   ./tools/beta_install.sh [device-udid]
#
# Needs Xcode signed into the Lock Out Inc. Apple ID (Xcode > Settings >
# Accounts): the .dev bundle IDs get their development profiles minted on
# the fly, and xcodebuild reports "No Accounts" without that sign-in.
#
# The identity swap is temporary and local: project.yml and both Info.plists
# are backed up, edited, and restored whatever happens (trap). The install
# step refuses anything that is not the .dev bundle, so a failed build can
# never overwrite the App Store app (that happened once, 2026-09-12).
set -uo pipefail
cd "$(dirname "$0")/.."
DEV="${1:-045D4391-3289-5F58-B71D-DE2C314BF6F6}"
TEAM="${TEAM:-WLZQLLHUB3}"
BAK="$(mktemp -d)"
ENT="$(grep -m1 'CODE_SIGN_ENTITLEMENTS' project.yml | awk '{print $2}')"
[ -f "$ENT" ] || { echo "entitlements not found at '$ENT'"; exit 1; }
cp project.yml "$BAK/project.yml"; cp Coherence/Info.plist "$BAK/ios.plist"; cp CoherenceWatch/Info.plist "$BAK/watch.plist"; cp "$ENT" "$BAK/ents.plist"
restore() {
  cp "$BAK/project.yml" project.yml; cp "$BAK/ios.plist" Coherence/Info.plist; cp "$BAK/watch.plist" CoherenceWatch/Info.plist; cp "$BAK/ents.plist" "$ENT"
  "$(command -v xcodegen)" generate >/dev/null 2>&1 || true
  echo "tracked files restored"
}
trap restore EXIT

python3 - <<'PY'
import re
p='project.yml'; s=open(p).read()
s=re.sub(r'PRODUCT_BUNDLE_IDENTIFIER: com\.lockout\.meditate808\n','PRODUCT_BUNDLE_IDENTIFIER: com.lockout.meditate808.dev\n',s,count=1)
s=s.replace('PRODUCT_BUNDLE_IDENTIFIER: com.lockout.meditate808.watchkitapp','PRODUCT_BUNDLE_IDENTIFIER: com.lockout.meditate808.dev.watchkitapp',1)
assert s.count('meditate808.dev')==2; open(p,'w').write(s)
for p,companion in [('Coherence/Info.plist',False),('CoherenceWatch/Info.plist',True)]:
    s=open(p).read()
    s=re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)808(</string>)', r'\g<1>808 Beta\2', s, count=1)
    if companion:
        s=re.sub(r'(<key>WKCompanionAppBundleIdentifier</key>\s*<string>)com\.lockout\.meditate808(</string>)', r'\g<1>com.lockout.meditate808.dev\2', s, count=1)
    open(p,'w').write(s)
PY
# No iCloud on the beta by default: the entitlement is written
# iCloud.$(CFBundleIdentifier), which for the .dev bundle names a container
# that does not exist, so the keys are stripped and the beta keeps its own
# local data (Friends then show the "this build can't reach iCloud" card).
#
# WITH_ICLOUD=1 pins the entitlement to the real container instead, so
# Friends can be tested side by side (a Debug build talks to CloudKit's
# DEVELOPMENT environment, never to App Store users' data). Tried
# 2026-09-15: signing refused ("profile doesn't match the entitlements",
# plus "No Accounts"), because the .dev App ID has no iCloud capability.
# Before using it: Xcode > Settings > Accounts signed in, and in the
# developer portal, Identifiers > com.lockout.meditate808.dev > iCloud >
# Configure > tick iCloud.com.lockout.meditate808 > Save.
if [ "${WITH_ICLOUD:-0}" = "1" ]; then
  /usr/libexec/PlistBuddy -c "Set :com.apple.developer.icloud-container-identifiers:0 iCloud.com.lockout.meditate808" "$ENT"
else
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.icloud-container-identifiers" "$ENT" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.icloud-services" "$ENT" 2>/dev/null || true
fi
"$(command -v xcodegen)" generate >/dev/null 2>&1 || { echo "xcodegen failed"; exit 1; }

B="$(date -u +%Y%m%d%H%M)"
echo "building 808 Beta, build $B"
LOG="$(mktemp)"
xcodebuild -scheme Coherence -configuration Debug -destination "id=$DEV" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$B" build >"$LOG" 2>&1
if ! grep -q "BUILD SUCCEEDED" "$LOG"; then
  grep -E "error:" "$LOG" | head -6
  echo "BUILD FAILED; nothing installed"
  exit 1
fi
APP="$(ls -dt ~/Library/Developer/Xcode/DerivedData/Coherence-*/Build/Products/Debug-iphoneos/Coherence.app | head -1)"
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"
if [ "$ID" != "com.lockout.meditate808.dev" ] || [ "$VER" != "$B" ]; then
  echo "refusing to install $ID build $VER: not this run's beta"
  exit 1
fi
xcrun devicectl device install app --device "$DEV" "$APP" 2>&1 | grep -E "bundleID|rror" | head -2
echo "808 Beta $B installed. The Watch companion installs itself; if not, iPhone > Watch app > 808 Beta > Install."
