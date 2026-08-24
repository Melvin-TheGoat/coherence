# Marketing assets

## `appstore/`

The eight iPhone 6.9" screenshots (1320x2868) for the App Store listing. Real
screens captured on the iPhone 17 Pro Max simulator in dark theme with a 9:41
status bar, then framed by `tools/store_shots.swift`.

To regenerate after a UI change:

1. Build and install on the Pro Max simulator, seeding demo data with
   `SIMCTL_CHILD_SKIP_ONBOARDING=1` plus `PREVIEW_HISTORY=1` (three weeks of
   history) and `PREVIEW_RESULTS=1` (the scored session the hero shot uses).
2. `xcrun simctl io <udid> screenshot raw.png` on each screen.
3. `swiftc -O -o /tmp/store_shots tools/store_shots.swift`
4. `/tmp/store_shots raw.png out.png "Headline|second line" "Subhead"`

Captions live in `APP_STORE.md` and must name their subject: a store screenshot
is met with no context at all, which is the same rule the onboarding screens
follow.

**The device frame is drawn, not photographed.** Apple's marketing guidelines
forbid depicting Apple hardware inaccurately, and a generic dark bezel avoids
claiming to be a specific model.
