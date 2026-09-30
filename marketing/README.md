# Marketing assets

## `appstore/`

The eight iPhone 6.9" screenshots (1320x2868) for the App Store listing, in
upload order: `01-otto` ... `08-awards`. Real screens captured on the iPhone 17
Pro Max simulator with a 9:41 status bar, then framed by
`tools/store_shots.swift`: the valley's daytime sky easing into cream, the far
ridges behind the phone, SF Pro Rounded captions in the sky's ink, one warm sun
haze as the only accent, and a drawn generic dark bezel. Captions and order
live in `APP_STORE_PASTE.md` > Screenshots. Re-shot for 1.1 on 2026-09-29.

To regenerate after a UI change (every hook below is DEBUG only):

1. Make your OWN simulator and give it the status bar:
   `xcrun simctl create "808-store-shots" "iPhone 17 Pro Max"`, boot it, then
   `xcrun simctl status_bar <udid> override --time "9:41" --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi`
   (`discharging` at 100: `charged` draws a green battery with a bolt).
2. Build Debug for it (`xcodebuild -scheme Coherence -configuration Debug
   -destination 'id=<udid>' -derivedDataPath /tmp/808-shots build`) and
   install. On a FRESH install, before the first launch, mark the invite award
   as seen so its unlock screen does not cover every shot, and push the rating
   prompt's cooldown so it does not open over the results screen:
   `xcrun simctl spawn <udid> defaults write <data container>/Library/Preferences/com.lockout.meditate808 awardsAnnounced.v1 -array friendBrought`
   and the same for `reviewPrompt.lastAskedAt -date "<today> 12:00:00 +0000"`
   (`xcrun simctl get_app_container <udid> com.lockout.meditate808 data`
   gives the container).
3. Every launch carries `SIMCTL_CHILD_` versions of: `SKIP_ONBOARDING=1`,
   `DEMO_NAME=Maya`, `DEMO_USERNAME=maya` (never a founder's name),
   `VALLEY_HOUR=9.7` (a morning sky and "Good Morning" to match 9:41),
   `PREVIEW_PAID=1` (the curves unlocked) and `STORE_SHOTS=1` (hides the Block
   and Friends test-mode cards, switches Otto's chat off as Release has it, and
   seeds non-founder friends). Add `PREVIEW_HISTORY=1` for everything except
   the Block shot.
4. Per shot, in this order (the Block shot needs a day with no session, and
   `PREVIEW_RESULTS` inserts a session every launch, so it goes last):
   - 02 Block, FIRST, without `PREVIEW_HISTORY`: `PREVIEW_BLOCK=full PREVIEW_TAB=block`
     (Mindful day holding, plus Wind down and Weekend unplug, whose "Waiting"
     agrees with a weekday 9:41). The first launch of a fresh install shows
     the invite-reward sheet once; launch again.
   - 01 Otto: `OTTO_AURA=100`
   - 03 Shop: `PREVIEW_TAB=shop PREVIEW_HAT=sunhat` (the hat is on him AND its
     card is selected, so the button reads "Buy for 60 points")
   - 04 Sounds: `PREVIEW_SETUP=sound` (the Ready screen opened on its sound list)
   - 05 Profile: `PREVIEW_TAB=profile`
   - 07 Friends: `PREVIEW_TAB=friends` (the cover Home's Friends circle opens)
   - 08 Awards: `PREVIEW_TAB=profile PREVIEW_AWARDS=1`
   - 06 Watch results, LAST: `PREVIEW_RESULTS=1`
5. Wait about ten seconds, then `xcrun simctl io <udid> screenshot raw.png`.
   **The clouds drift on the wall clock and birds fly through at random**, so
   take a burst (a frame every 4 to 6 seconds for two minutes) and keep a
   frame with nothing crossing the status bar or the headline.
6. `swiftc -O -o /tmp/store_shots tools/store_shots.swift`, then
   `/tmp/store_shots raw.png out.png "Headline|second line" "Subhead"`.
   A `|` forces a line break in either caption; without one the subhead wraps
   evenly. It refuses a caption carrying an em or en dash, and writes RGB with
   no alpha channel.

Captions must name their subject: a store screenshot is met with no context at
all, which is the same rule the onboarding screens follow.

**Uploading to App Store Connect, learned 2026-09-12:** Media Manager keeps
screenshots in the order they FINISH uploading, not the order they were
chosen, so a multi-file upload lands shuffled and the strip cannot be
reordered by a scripted drag. Upload ONE file at a time, waiting for each to
process, in the listing order (01, 02, 07, 04, 05, 08, 06 as of 1.0.1). The
6.9" slot is the one to fill; the 6.5" slot below it rejects these masters
on dimensions and then shows the 6.9" set anyway. `PREVIEW_TAB=profile` and
`DEMO_USERNAME=<handle>` (DEBUG) set up the Profile shot.

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

## `appstore/watch/`

The two Apple Watch screenshots, **422 x 514**, the Apple Watch Ultra 3 size
(the largest App Store Connect takes): `01-begin` (start screen) and
`02-measuring` (a live session). No frame. Captured from a watchOS simulator
(`xcrun simctl create ... "Apple Watch Ultra 3 (49mm)"`), standalone, with the
Watch app built Debug and launched with `SIMCTL_CHILD_PREVIEW_WATCH_SCREEN=start`
or `=live`: that hook skips the HealthKit prompt and the phone's onboarding flag
(neither can be answered without a tap), and `live` shows the live screen at
7:12 with no workout running. The watchOS simulator refuses a status-bar
override, so the corner clock is the real time. The simulator writes RGBA;
flatten onto black before uploading.

## `appstore/iap/`

`paywall-review.png`, **640 x 920**, the review screenshot every in-app purchase
requires. That is a different spec from App Store screenshots, and Connect
rejects the 1320 x 2868 masters with the same "dimensions are wrong" message.

It shows the **paywall**, not a results screen: a reviewer needs to see where
the purchase happens, with all three products, their prices, and the trial
disclosure visible.

Regenerate by capturing the paywall (`ONBOARDING_STEP=37` on a fresh install,
since the hook only applies before onboarding completes) and top-cropping.
`sips --cropToHeightWidth` crops CENTRED, which cuts the headline that
documents the introductory offer, so use a top crop instead.
