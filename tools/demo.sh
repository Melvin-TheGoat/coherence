#!/bin/bash
# Demo 808 on this Mac, in the iOS Simulator, with every feature of the
# development build on (Block in its test mode, the Shop, Friends in its
# test mode). For showing the app without a phone.
#
#   ./tools/demo.sh          Home, with a few weeks of sessions already in it
#   ./tools/demo.sh fresh    a new install: onboarding from the first screen
#
# Click to tap, drag to scroll. The Simulator has no haptics, no camera and
# no paired Watch, and Screen Time's real shields only appear on a phone.
set -e
cd "$(dirname "$0")/.."

NAME="808 Demo"
UDID=$(xcrun simctl list devices | grep "$NAME (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
if [ -z "$UDID" ]; then
    UDID=$(xcrun simctl create "$NAME" "iPhone 17 Pro")
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"

if command -v xcodegen >/dev/null; then xcodegen generate >/dev/null; fi
echo "Building (a few minutes the first time)..."
xcodebuild -scheme Coherence -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath /tmp/808-demo build -quiet

APP=/tmp/808-demo/Build/Products/Debug-iphonesimulator/Coherence.app
BUNDLE=com.lockout.meditate808
if [ "$1" = "fresh" ]; then
    xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
fi
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
if [ "$1" = "fresh" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
else
    SIMCTL_CHILD_SKIP_ONBOARDING=1 SIMCTL_CHILD_PREVIEW_HISTORY=1 \
        xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
fi
echo "808 is open in the Simulator."
