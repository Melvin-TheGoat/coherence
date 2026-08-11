#!/bin/bash
# Builds a TestFlight-ready archive of 808.
#
# Two things differ from a normal Xcode build, and both of them are silent
# failures if you forget:
#
#   Build number. App Store Connect rejects a build whose number it has seen
#   before, and project.yml hardcodes 1. This stamps a UTC timestamp instead,
#   which is monotonic by construction and needs no state to be kept anywhere.
#
#   Push environment. The committed entitlements say aps-environment
#   development, which is right for the builds you install over a cable and
#   wrong for a distribution build. Rather than keep a second entitlements file
#   that drifts out of sync with the first, this derives one at build time.
#   CloudKit is the only thing 808 uses push for.
#
# Both are passed as build-setting overrides, so nothing tracked is edited and
# nothing local is committed. project.yml carries per-developer signing under
# skip-worktree; leave it that way.
#
#   ./tools/archive.sh
#
# Then open Xcode → Window → Organizer, pick the archive, Distribute App →
# App Store Connect. Uploading is left to Xcode on purpose: it holds the
# credentials and it is the part worth having a human watch the first time.
#
# NOTE the ONE thing this cannot check for you: CloudKit in TestFlight talks to
# the PRODUCTION container, and the schema only exists in Development until you
# promote it in the CloudKit Dashboard. Sync will silently do nothing until you
# do. Deploy the schema before you wonder why nothing roams.

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD="$(date -u +%Y%m%d%H%M)"
ARCHIVE="build/808-${BUILD}.xcarchive"
ENTITLEMENTS="$(mktemp -d)/Coherence-release.entitlements"

cp Coherence/Coherence.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :aps-environment production" "$ENTITLEMENTS"

echo "Archiving 808, build ${BUILD}"
echo "  entitlements: aps-environment = production"
echo

xcodebuild archive \
  -scheme Coherence \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  | grep -E 'error:|warning: .*(sign|entitle)|ARCHIVE SUCCEEDED|ARCHIVE FAILED' || true

if [ -d "$ARCHIVE" ]; then
  echo
  echo "Archive at ${ARCHIVE}"
  echo "Marketing version $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist" 2>/dev/null || echo '?'), build ${BUILD}"
  echo "Open Organizer to upload:  open -a Xcode; xed ."
else
  echo "No archive produced. The signing errors above are the place to look:"
  echo "distribution needs an App Store profile, not the development one."
  exit 1
fi
