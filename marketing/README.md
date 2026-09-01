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

## `decks/` and `tools/carousel.swift`

Social carousels are rendered, not designed one at a time. A deck is a JSON
file of copy; `tools/carousel.swift` lays it out on the brand ground and writes
one PNG per slide in every size asked for.

```bash
swift tools/carousel.swift marketing/decks/meditate-blind.json out all
```

Sizes: `ig` 1080x1350 (Instagram carousel, the default), `vertical` 1080x1920
(TikTok, Stories, and the frames a reel gets cut from), `square` 1080x1080.
One deck renders all three, so there is never a second write-up per platform.

**The copy comes from somewhere else.** Either written by hand or by the
carousel generator, which is given `CAROUSEL_BRIEF.md` as its whole brief and
hands back a deck in the shape section 14 of that file specifies. The split is
deliberate: a model is good at hooks and bad at consistency, and 808's whole
position is that it looks deliberate. Nothing about layout, colour or type is
ever decided per post.

**It refuses rather than warns.** An em dash, a banned phrase, a screenshot
path that does not exist, a slide with no gold element or with two, or copy
that overruns the safe area all fail the render and name the slide. The checks
a machine cannot make are still section 13 of the brief, read by a person
before publishing.

## `fonts/`

Manrope, Hanken Grotesk and DM Mono, the three faces the website already uses,
downloaded from Google Fonts and committed because neither cofounder has them
installed. All three are OFL licensed. Without them the renderer would fall
back to SF Pro and quietly ship a carousel that does not match the site, so it
exits instead.


## `appstore/65/`

The same eight slides at **1284 x 2778**, the 6.5 inch legacy size (iPhone 11
Pro Max through 13 Pro Max). Generated from the 6.9 inch masters by scaling to
width and centre-cropping twelve pixels of height, which the design absorbs
because the phone already bleeds off the bottom edge.

**Prefer the 6.9 inch set.** Apple requires 6.9 inch (1320 x 2868) and scales it
down for smaller devices; 6.5 inch is optional. If App Store Connect rejects an
upload with "dimensions should be 1242 x 2688, 2688 x 1242, 1284 x 2778 or
2778 x 1284", the device-size selector above the upload area is on the 6.5 inch
slot, not the 6.9 inch one. Switching slots is the fix; this folder is the
fallback.

Regenerate after any change to the masters:

```
for f in marketing/appstore/*.png; do
  n=$(basename "$f"); cp "$f" "marketing/appstore/65/$n"
  sips --resampleWidth 1284 "marketing/appstore/65/$n" >/dev/null
  sips --cropToHeightWidth 2778 1284 "marketing/appstore/65/$n" >/dev/null
done
```
