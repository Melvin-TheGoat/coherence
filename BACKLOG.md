# 808 backlog

One list, so nothing said in a session is lost between sessions (Melvin,
2026-09-12: "I am saying a lot and not finishing much"). Order: work that
is finished but sitting on a branch, then features not built, then small
fixes, then open threads, standing notes, and a one-line record of what
shipped. When something ships it becomes one line under Done; the detail
lives in CLAUDE.md and in git.

**Swept 2026-11-06 against the code on `block`** (a1e7c1b), not against the
notes. Every entry below was checked: "not built" means no code for it was
found. Things that turned out to be built, decided against or superseded
were taken out; the list of those is at the bottom of this sweep's commit.

## Finished or half-finished, but not merged into `block`

Nothing on these branches ships until it is merged. Check each with Melvin
before merging: they predate the 1.4.1 work.

- **The friends feed comes back** (branch `social-feed`, 3 commits, Melvin
  2026-10-23). Posts with photos, video, how it felt, a note and the 🙏
  reaction; a friend's page with their sessions; "Who can see this?" with
  Friends as the default; Friends gets its tab back and the Shop moves to a
  corner circle on Home. Never the score. On `block` the feed is dead code
  (`CommunityModel.postInBackground` has no caller, `CommunityStore.feed()`
  is never called) and `clearMyPostsIfNeeded` deletes old posts. Before it
  ships: delete `clearMyPostsIfNeeded`, report and block on a post, the
  `Post` media fields and the new `rating` field promoted in CloudKit
  Production, and the privacy policy and App Privacy labels.
- **Ask Otto: a fresh notification every time** (branch
  `ask-otto-fresh-banner`, fce0838, 2026-10-08). A bug fix: every ask still
  reuses one identifier (`BlockAsk.notificationID = "808.block.ask"`,
  BlockKit/BlockStore.swift:206), so a second ask can replace the first
  instead of showing a new banner. Small; merge it.
- **Camera-verified sessions** (branch `camera-verify`, 29315be, and the
  untracked `mockups/camera-verify.html`, Melvin 2026-10-08). The front
  camera checks you are there and still, and only verified sessions count
  for the streak, the glow and Block. Mockup only, with an open "To decide"
  list. No code.

## Decided, waiting to be built

- **Companions evolve: Otto, then red panda, tiger, phoenix, dragon**
  (Melvin, 2026-11-09). Everyone starts as Otto; points unlock the next
  creature. Each creature keeps its own seven glow states (consistency),
  separate from evolution. Animated in Rive with their light, like Otto;
  every hat refitted per creature. Done: dragon redrawn (less fluffy, more
  epic), clean defringed cuts (`mockups/companions/master/`). In flight:
  the Rive rigs (`Coherence/Otto/Companion<Name>.riv`, built in the Dragon
  Rive file, art swapped per creature, because the MCP cannot switch
  tabs), pasting the existing hats onto each form, the level-up mockup
  (`mockups/level-up.html`).
  **Decided 2026-11-10 (Melvin):**
  - It is always OTTO, reincarnated into a new form, never a new friend.
  - The moment: Pokémon-style evolution (silhouette flicker, flash) with
    Duolingo's confetti, ending on a Finch-style card.
  - LIFETIME points earned (spending on hats never slows it): red panda
    300, tiger 800, phoenix 2,200, dragon 5,500 (about a year at 15
    minutes a day).
  - Every unlocked form can be chosen again, any time.
  - A new form starts at 50% glow (Steady).
  - Hats carry over to every form.
  - Existing members with the points see each unlock in order.
  - The widget and the Watch follow the chosen form.
  - The app icon stays Otto; it never changes with the form (2026-11-12).
  - Switching forms keeps today's glow: the glow belongs to the practice,
    not the form (2026-11-12).

- **Show their real top apps on the Block pick screen** (decided "next
  build", 2026-10-13). "Your top apps this week", with icons and minutes,
  above "Choose apps" in onboarding and in Home's one-time ask. Apple lets
  808 show this but never read it: it is drawn by a DeviceActivityReport
  extension, which cannot write to the App Group or pass a token back, so
  people still tap the app themselves. Needs: a fourth Block extension
  (`com.lockout.meditate808.report`, and `.dev.report` for the beta) with
  the App Group; a Family Controls (Distribution) request for that App ID,
  made by Melvin as Account Holder; a test on a real phone. Mockup:
  `mockups/retention-v1.html`, fourth phone.
- **Mind profile in Settings, for 1.5** (Melvin, 2026-10-19). The type
  (`MindProfile.of`) is worked out once in onboarding and never saved. (1)
  Save it from now on: a `Preferences` field follows the person to a new
  phone but needs a private-schema field in Production; UserDefaults needs
  none. (2) "Find your mind profile" in Settings for everyone onboarded
  earlier: ask the four questions again and show the result screen. Reading
  PostHog back into the app is not a route (the privacy policy says what
  analytics is for).
- **What's-new screens for free 1.0 users who update** (Aziz 2026-10-07,
  option 2 chosen by Melvin 2026-10-13). "Welcome back!" with Otto glowing,
  "I hold your apps until you've meditated", "Every minute earns points for
  my hats", then the paywall. Once, only for someone whose 808 predates
  1.1 (`Preferences.createdAt` before `OttoAura.glowStart()`) with no
  membership. **Mockup `mockups/whats-new-v1.html` awaits approval**
  (https://claude.ai/artifact/Psppdu6UpowTiM7kN1yHwm).

## Proposed, needs a decision

- **Zen mode and Monk mode** (APPROVED, Melvin 2026-11-06, from
  `mockups/zen-monk.html`). Zen is the default: lock the phone or switch
  apps and the timer keeps going, "I was still meditating" stays, recorded
  sessions count. Monk is opt-in and keeps today's strict rules (leaving
  for 10 s ends it, recorded sessions are saved but do not count); the rest
  day stays in both. Settings uses design **2B**, a Zen / Monk segmented
  control. Otto offers Monk once after a 7-day streak. Still open: a cap for
  open-ended Zen sessions with a locked phone, and whether time in other
  apps counts toward Block's minute (recommended: no). Test the
  lock-versus-app-switch signal on a phone first. Build notes in CLAUDE.md,
  "OPEN TASK: LOCK THE PHONE".
- **Guided meditations with an AI voice** (Melvin, 2026-11-06, after
  ElevenLabs released Eleven v4 on 2026-09-28). Replaces the "AI coach voice
  library" that was on hold because ElevenLabs "is not there yet". The
  tester ask it answers: 10, 15 and 20 minute versions and a choice of
  voice (2026-09-12). Rules if it goes ahead: every track generated ahead
  of time and shipped, never generated at run time (keeps "no AI service,
  no server" true and sessions offline); generated sentence by sentence with
  silences placed by us; mixed over the existing beds; paid ElevenLabs plan
  only; a "Voice made with AI" credit; more tracks delivered as Apple-hosted
  Background Assets rather than in the app download. Open: a stock voice or
  a clone of Donny (needs his written consent and likely a fee); whether
  Otto ever speaks (keep the narrator separate at first); who writes the
  scripts. Next step proposed: one 10 minute pilot script in two or three
  voices, judged blind against Donny's track on a phone. Donny's 25 minute
  journey stays the flagship. Commissioning Donny for shorter cuts is the
  non-AI alternative.

## Not built yet

### Friends

- **Meditate first, then see your friends' day** (BeReal style, Melvin
  2026-09-23), perhaps with a weekly mode where one session opens the week.
  Waits on the feed. Open: whether a phone session counts, what the locked
  tab shows, whether a rest day opens it. The gate must read 808's own
  sessions, never Screen Time.
- **Streak duels**, and **meditating together at the same moment**
  (both timers start together) (Melvin and Aziz, 2026-10-12). Compete on
  showing up, never on the score. The live version needs SharePlay
  (GroupActivities) or a backend. The weekly shared goals that shipped in
  1.4 cover the accountability-pair shape.
- **A daily shared streak, and Friends Quests** (Aziz, 2026-10-14). Left
  out of Meditating together on purpose; the weekly streak shipped first.
- **Change a shared goal's number.** Today you end the goal and start a new
  one (each person owns their own half).
- **An accountability friend who sees when your Otto is low**
  (CONSISTENCY.md, 2026-09-21). Partly met by goal nudges and the practice
  stats. A shared glow level must come from sessions alone: Apple's Family
  Controls terms forbid sharing anything from Screen Time.
- **Friends drawn as their own Otto** at their own aura stage, so friends
  without a photo are not all one silhouette (CLAUDE.md, 2026-09-21). Needs
  a glow level on the public Profile, sessions only.
- **A friends topic in the reminders.** The planner's topics are streak,
  glow, apps, goal, gentle, shop, comeback and farewell; nothing about
  friends yet.
- **A push for an ordinary friend request.** Goal invites, answers,
  nudges, cheers, finished weeks and code joins all push; a plain friend
  request only shows on Home's badge.
- **A universal link that opens a friend's profile.** The invite page is
  live; opening the app straight to the person needs the Associated Domains
  entitlement, an apple-app-site-association file and a fresh review.
- **Video in feed posts.** The old feed posted only a video's first frame.
  Matters again once `social-feed` lands; check what that branch does.
- **Instagram Stories without the Photos detour.** Code is done and turns on
  once `InstagramShare.metaAppID` is set. Waits on someone registering a
  Meta app (it was geo-blocked for Aziz).
- **Share card skins with real artwork.** `CardSkin` has no art. A skin must
  never change what data a card shows.
- **Friends without iCloud.** Needs a backend. Founders' call (Melvin,
  2026-09-15).

### Otto

- **A weekly letter from Otto**: the week, in his voice, rule-written like
  his Home lines (CONSISTENCY.md).
- **The valley matches his state** (Melvin, 2026-09-23): flowers wilting,
  greyer sky or rain, crows instead of songbirds, uglier bugs as he gets
  sadder, the reverse as he glows. The scene is all code, so most of it is
  palette and counts keyed to the stage; crows need sprites. Marked "not to
  be built yet".
- **A Lock Screen widget.** The widget ships small and medium Home Screen
  sizes only.
- **More animation**: a tail flick, reactions, moving leaves, an arm that
  bends (bones must be weighted by hand in the Rive editor).
- **Hats inside the aura rig**, so bugs stop passing under the hat. Blocked:
  the editor's copy of `OttoAura.riv` is older than the shipped file, which
  must be rebuilt in the editor first.
- **A hat award.** Left out while the Shop was off in Release; the Shop
  ships now and there is still no award for a first hat.
- **Otto's chat in Release.** Built and off (`ottoInRelease = false`). Waits
  on Melvin and Aziz reading a dozen answers on a phone, then the
  RELEASE_CHECKLIST items for that flag. A cloud model only if on-device
  is not good enough.

### Block

- **A Live Activity** during a hold or a session (Lock Screen and Dynamic
  Island). Also the visible half of the Monk Mode idea.
- **A wind-down window that follows iOS Sleep.** Unverified whether a
  third-party app can read the sleep schedule at all.
- **"Your apps are open" on the sit screen** once a session opens them. The
  sit says "Your apps open when you end"; nothing says it after they open.

### Sessions and sound

- **Headphones (binaural) mode.** The engine supports it
  (`ToneEngine.Method.binaural`), but every call site passes
  `headphones: false`, so it is unreachable.
- **A nature sound layered under a tone.** `playNature` stops whatever was
  playing; one sound at a time.
- **Try a breath inside the guide** instead of reading about it (the
  "show, don't tell" rule, 2026-09-22).
- **"Your best technique"**: your own average score by technique, within one
  person only (METHODS.md). Needs measured sessions, so Watch users only.
- **Compression pass on the two quiet beds**, Manifest and Awaken, about
  2 dB under the rest. Likely never done (the files predate the note).

### Onboarding and paywall

- **Use the onboarding answers in the app.** Reminders use the goals and
  obstacles; Home and Otto's lines never refer to them.
- **Sell membership better in onboarding** (Melvin and Aziz, 2026-09-23).
  A design thread, not a feature yet.

### Watch and measurement

- **A camera session with no Watch** (branches `camera-vision` and
  `camera-vision-work`, paused). Waits on the ground-truth sits in
  `CAMERA_VISION_PLAN.md`. Different from camera-verified sessions above.
- **An AirPods heart-rate session** (branch `airpods`, a DEBUG probe in
  Settings). Waits on someone owning AirPods Pro 3 or Powerbeats Pro 2.
- **Other wearables**: Bluetooth heart-rate straps (about a week, heart
  only), Polar H10 or Verity Sense (beat-to-beat, so real HRV), Garmin
  (a `GarminWatch/` folder exists). Cheap first move: ask people without a
  Watch what they own.
- **The camera finger check (PPG)** on `full-feature-set`. Waits on testing
  across skin tones and lighting.
- **Heartbeat from wrist motion (BCG)**, research only; **an HRV trend**,
  parked; **a verified-session mark**; **EEG validation**, parked.
- **Credit for how long the breath doorway was held.** Stored
  (`breathDoorwayHeldSec`), never scored. Waits on long counted sessions;
  do not guess a curve (the last one wrecked verified sessions).

### Engine and score

- **Retune the VerdictEngine thresholds** (0.75 / 0.55 / 0.35, tuned to the
  v2 score in August and never retuned). Do it against real v5 sessions.

### Website and marketing

- **Test icons and screenshots with Product Page Optimization.** Every test
  icon must ship as an alternate icon in a build first; none do. Waits on
  Melvin's art (`mockups/icon-flat.html` is in progress).
- **Meta app-install campaigns.** Gated: need an SDK or MMP in the app and
  install to trial at 5 percent first.
- **Instagram comment-to-DM.** Unverified whether it was ever set up.

### Other

- **Accessibility.** 439 fixed-size fonts, no `@ScaledMetric`, 74
  VoiceOver labels. Dynamic Type, labels on the custom drawing and a
  contrast check. App Store accessibility labels stay empty until verified.
- **Sign in with Google or email.** Deferred since v1.
- **DIN Next Rounded or SF Pro Rounded.** DIN needs an app licence from
  Monotype; the swap is in CLAUDE.md "ONE ROUNDED FONT EVERYWHERE".
- **Tab bar art.** Ink, Lifted, Meadow and Sloths bars exist; check whether
  Melvin still wants new icons.

## Small fixes noted and never made

- **Onboarding saves answers to the wrong Preferences row** when a phone has
  several: `persistAnswers` (OnboardingView.swift:1323) takes the row
  matching `userID` before the oldest, against the "oldest row" rule.
- **The Ask Otto notification identifier**, fixed only on
  `ask-otto-fresh-banner` (above).
- **No analytics event when a week together finishes.** The push and the
  points exist; PostHog never hears about it.

## Open threads

- **Watch 1.4.1 through review.** Submitted 2026-11-06 (build
  202610271827). Once it is live, deploy the website if anything on it
  changed, and watch PostHog for the paywall banner's `offer_viewed`
  against the Oct 1 to 26 baseline (13 buyers from 110 installs).
- **Copy for the pivot.** PURPOSE.md, SCIENCE.md (still says breath counts
  most, untrue since score v5.0.0), the website footer and its "first app
  that scores your meditation" line, and marketing/CAROUSEL_BRIEF.md still
  sell a Watch measurement app.
- **Website redeploy** whenever the site changes (manual drag of `website/`
  into Cloudflare Pages, or the `deploy-website` skill). After the next one,
  Melvin clicks the Google preferred-source badge while signed in to see
  whether meditate808.com is listed.
- **Watch `onboarding_completed`** against the rate before the onboarding
  cuts; if it drops, the cuts are the first suspect.
- **Launch plan items with no record of being done**: Apple Search Ads, the
  featuring nomination, press tips, promo codes, Reddit, the weekly review.
  Confirm or strike.
- **Ask people what "808" means to them** in the next tester conversations.
- **Music**: Home may want a quick mute beside Settings > Music; the haptics
  can only be judged on a phone.

## Standing notes

- **TestFlight replaces the App Store app on a phone.** One bundle ID, one
  app. `MeditationStats` is device-local, so deleting the app deletes every
  curve recorded on that phone. Side by side is the `.dev` beta
  (`tools/beta_install.sh`).
- **Where Friends can be tested.** A plain beta names a container that does
  not exist; `WITH_ICLOUD=1` pins it to the real container's Development
  environment. TestFlight talks to Production. On a simulator,
  `CommunityModel.testMode` runs Friends against the in-memory fake. Look
  for the Test mode banner on both phones before trusting a two-phone test.
- **Health permission is asked on the phone**, and only when a Watch is
  paired. HealthKit never says whether a read was denied.

## Done

One line per release or day; the detail is in CLAUDE.md and git.

- **1.4.1 (built 2026-10-26/27, submitted 2026-11-06):** paywall rebuilt
  (Yearly first, half price as a one-tap banner, 7-day trials); Block opens
  for the rest of the day after 1 minute; the 11:30 pm streak saver; Friends
  awards and weeks finished together (10 points, push, history); goals count
  from a minute; a session across midnight keeps the streak; five new hats
  and the glow fix on six; the founders' note; Marker Felt notes; new Watch
  screenshots.
- **1.4 (live):** Meditating together (weekly shared goals, nudges, pushes);
  invite codes and `meditate808.com/invite`; profile pictures with 21
  presets; the onboarding science screens and one progress bar; the
  analytics for all of it.
- **1.3.1 (live):** the rating ask moved to Home after a session.
- **1.3:** planned reminders (up to three a day, tapering, then a farewell);
  the required Block app pick; music and sound effects; the Watch in the
  valley with length and sound on the wrist; onboarding answers in PostHog;
  the session's page opens after the reward.
- **1.2:** the home screen widget; the new Block shield; Otto's replies on
  every "Not now"; the session bell.
- **1.1:** premium only; Block; the Shop and hats; Friends (profiles,
  requests, practice stats); the valley everywhere; Otto's aura rig.
- **2026-09-12 to 09-22:** see the git history and CLAUDE.md; the first
  version of this list recorded them day by day.
