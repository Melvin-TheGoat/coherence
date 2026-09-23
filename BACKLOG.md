# 808 backlog

One list, so nothing said in a session is lost between sessions (Melvin,
2026-09-12: "I am saying a lot and not finishing much"). Potential features
come first, then open threads, then standing notes, then a one-line record
of what shipped. When something ships it becomes one line under Done; the
detail lives in CLAUDE.md and in git. Swept 2026-09-23: finished,
superseded and decided-against items were taken out (git history has them).

## Potential features (not built yet)

Every feature idea in the repo's docs that is not in the product, checked
against the code on `block` on 2026-09-23. "(unverified)" means the code
could not settle it. Each entry says what it is, where it came from, and
what it waits on.

Not listed, because they are built and waiting on a release: Otto's
on-device chat (`FeatureFlags.ottoInRelease` is off), Block
(`blockInRelease` is off) and Friends (1.1). Otto's seven aura states
animated in Rive shipped to `block` on 2026-09-23 (`OttoAura.riv`).

### Friends and social

- **Meditate first, then see your friends' day (BeReal style).** Melvin,
  2026-09-23: "you can only see your friends meditations for the day (in the
  social tab) if you meditate first, just like BeReal. Maybe you can see a
  Weekly view for those who just like to meditate a few times a week." So
  today's posts stay hidden until you have a session today, and perhaps a
  weekly mode where one session this week opens the week, for people who
  sit a few times a week. Waits on Friends (1.1). Open: whether a
  phone-timed session counts (every other rule counts it), what the locked
  tab shows (the meadow already lights up friends who posted today, which
  could stay visible as the pull), whether a rest day opens it, and whether
  weekly is a setting or the default. The public database runs no server
  logic, so the app enforces the gate the way it enforces blocks, and the
  gate must read 808's own sessions, never Block or Screen Time data.
- **An accountability friend.** Opt in, and a friend sees when your Otto is
  low and can nudge you. CONSISTENCY.md, 2026-09-21. The glow a friend sees
  must come from sessions alone: skipped Block windows come from Screen
  Time, and Apple's Family Controls terms forbid sharing that.
- **Friends shown as their own Otto.** A friend with no photo appears as
  Otto at their own aura stage, so a feed is not six identical sloths.
  CLAUDE.md "PROFILE IS THE VALLEY TOO", 2026-09-21. Needs a glow level on
  the public Profile, under the same sessions-only rule.
- **Shared streaks, and "3 friends meditated today".** Presence, never
  ranking. STAGE2_ROADMAP.md, Phase 3 (August). The meadow's glow for
  friends who posted today already covers part of it.
- **Challenges and group meditations.** Suggested in the August onboarding
  revisions (in git history); an onboarding screen once promised
  "challenges and group sits" that did not exist and was fixed in review
  (CLAUDE.md, pass 14, 2026-09-01). Needs a design.
- **Show my scores to friends, as a profile preference.** A post's score has
  been optional since 2026-09-22 (`mockups/post-score.html`). The
  recommendation on record: no per-post switch, because the posts that keep
  their score give away the hidden ones; if real posts show people choosing
  Only you on low days, one profile preference, on by default. Aziz asked,
  2026-09-15; decide after the first weeks of real posts.
- **Video in feed posts.** A session can hold a video since 2026-09-22, but
  the feed posts only its first frame ("a video in a post is its own piece
  of work"). CLAUDE.md, 2026-09-22.
- **A share card for a phone session.** The share image is built from
  measurements and lives on the results screen, so a sit the phone timed
  has no card. Posting it to Friends already works without a score.
  CLAUDE.md "THE SIT IS THE PRODUCT", 2026-09-21.
- **An invite page and a universal link.** `meditate808.com/f/<username>`
  says who invited you and links to the App Store (`ct=invite`); a
  universal link (the Associated Domains entitlement plus an
  apple-app-site-association file on Cloudflare Pages) would open straight
  to the friend's profile. COMMUNITY.md, 2026-09-14. A new entitlement
  means a fresh review.
- **Instagram Stories without the Photos detour.** The code is done and
  turns itself on once `InstagramShare.metaAppID` is set. Waits on a Meta
  app ID: registration was geo-blocked for Aziz, so the plan is that Melvin
  or a friend registers it and adds both founders. CLAUDE.md, 2026-07-28.
- **Share card skins with real artwork.** A paid cosmetic line, and the
  "Circle" skin once proposed as the reward for paid inviters. `CardSkin`
  exists with nothing drawn; today the paid "skins" are the four locked
  card layouts. A skin must never change what data a card shows.
  ENTITLEMENTS.md (2026-08-24), COMMUNITY.md (2026-09-14).
- **Friends without iCloud.** Needs a backend: accounts, a database,
  hosting, a privacy policy that names it and a new App Review answer.
  Today the iCloud account is both the identity and the storage. Melvin,
  2026-09-15. Founders' call: stay serverless, or fund a backend.
- **A badge for friend requests.** Push was left out of Friends v1 ("a
  badge is enough"), and there is no tab badge yet; the requests pill sits
  inside the tab. COMMUNITY.md, 2026-09-14.
- Left out of Friends v1 on purpose, so they come back only with a reason:
  comments, clubs, leaderboards (a score to beat raises heart rate, the
  very thing being measured), contact-list matching and a public feed of
  strangers. COMMUNITY.md, STAGE2_ROADMAP.md. Follower and following
  counts were on that list too and were added on 2026-09-18.

### Otto

- **Customize Otto with points earned by the habit.** Aziz, 2026-09-21:
  points come from meditating habitually and are spent on the sloth. The
  currency is consistency, never the score. Points would be the first
  stored, synced progress, so a CloudKit schema change and a release step.
  A customized Otto still has to draw at all seven aura stages. Open:
  spendable points or unlocks; visible to friends or not; awards as the
  unlock rather than a second ladder beside them.
- **Otto on the Home Screen and Lock Screen (widgets).** "his mood where
  you look eighty times a day. The strongest tamagotchi move there is."
  CONSISTENCY.md, 2026-09-21. Needs a widget extension and the glow shared
  through the App Group.
- **A weekly letter from Otto.** What the week looked like, in his voice.
  CONSISTENCY.md, 2026-09-21. Rule-written like his Home lines, unless his
  on-device chat ships first.
- **More animation.** A tail flick, a reaction when an answer is tapped,
  leaves that move when he waves, a generated branch in place of the vector
  one, and an arm that bends (bones have to be weighted by hand in the Rive
  editor; the MCP cannot do it). Melvin's second Otto pass, 2026-09-20;
  CLAUDE.md's Rive sections.
- **Otto's chat on a cloud model.** Only if Apple's on-device model is not
  good enough. It would send session data off the phone, so consent, the
  privacy policy, the labels and the "no AI service" answer to App Review
  would all change. 2026-09-15.

### Block and consistency

- **Block setup inside onboarding.** Ask when you want to meditate and which
  apps to hold, then meet Otto. Today Mindful day waits on the Block tab,
  and onboarding's explain-only Block screen was cut on 2026-09-22.
  CONSISTENCY.md. Waits on Block shipping.
- **Longer sessions earn more open time.** For example, a long session
  opens the apps until the window ends and a short one for an hour. Today
  any session of five minutes or more opens the rest of the window.
  CONSISTENCY.md, 2026-09-21.
- **A Live Activity during a hold.** "A five minute session opens your
  apps" on the Lock Screen and in the Dynamic Island. CONSISTENCY.md,
  2026-09-21.
- **A wind-down window that follows iOS Sleep.** The bedtime window takes
  the Sleep schedule instead of a typed time. CONSISTENCY.md, 2026-09-21.
  (unverified: whether a third-party app can read that schedule.)
- **Smarter reminders.** Words drawn from the person's own practice, no
  reminder on a day already practiced, and a time that follows when they
  usually first unlock the phone. Today one fixed daily reminder fires
  regardless. STAGE2_ROADMAP.md (August), CONSISTENCY.md (2026-09-21).
- **"Your apps are open" on the sit screen.** Aziz's valley sit left room
  for a chip ("Instagram is open again") for when a session releases held
  apps; only the Block tab says it today. CLAUDE.md, 2026-09-21.
- Related, and kept outside 808 on purpose: "Unlock", an app that keeps
  chosen apps locked each morning until you say your affirmations out loud
  (Aziz, 2026-09-18; BACKLOG on `origin/camera-vision`, `UNLOCK.md` outside
  this repo).

### Sessions and sound

- **Guided sessions in more lengths and voices.** 10, 15 and 20 minute
  versions beside the 25 minute journey, and a man's or a woman's voice
  (tester feedback, 2026-09-12). The cheapest honest path: commission Donny
  for cuts of the same script, then a length picker on the Guided card.
  The narrated coach still has no name (offered: Eight, Cadence, Tempo,
  Coach 808).
- **An AI coach voice library.** Melvin's wedge, on hold: ElevenLabs "is not
  there yet". When it is, the first version is a pre-generated library by
  length and voice, offline, with nothing generated at run time, which
  keeps the "no AI service, no server" answers true. 2026-09-12.
- **Log a session after the fact.** "I did one", for a sit done without the
  app, shown as logged rather than timed or measured. 2026-09-15. Open:
  whether it counts toward the streak, the glow, awards and Block releases,
  and how the feed marks it. Needs a mockup.
- **Show, don't tell, in the guide.** A method page lets you try a breath
  rather than read about it (the rule that replaced the explainer screens,
  CLAUDE.md, 2026-09-22). The same note asks for a three-second taste of
  each sound; the Ready screen already plays a sound when it is tapped.
- **A headphones (binaural) mode.** The tone engine and the session code
  support binaural playback, but nothing offers it: every session has
  played the speaker version since the sound picker was redesigned.
  CLAUDE.md, Phase 5 audio. (unverified whether it was dropped on purpose.)
- **A nature sound layered with a tone.** Deferred in the v1 plan; a
  session has one sound. App_ROADMAP_v2.md, "After Phase 7".
- **"Your best technique".** Once someone has enough sessions labeled with
  a technique, compare their own: "across 11 sessions, your score averages
  74 with body scan and 61 with blue sky". Within one person only, because
  pooling people is confounded. The same idea covers how-it-felt ratings
  against the measurements over time. METHODS.md (2026-08-09),
  App_ROADMAP_v2.md. It needs measured sessions, so today it reaches only
  Watch users.

### Onboarding and paywall

- **Use the onboarding answers in the app.** Only the reminder time is
  used; what people said they were chasing is read once and dropped, the
  "decorative questions" failure. The cheap fix is Home and Otto's lines
  referring to it. CLAUDE.md "STILL TO DO", 2026-08-06.
- **A weekly plan with a three-day trial.** One benchmark found it returns
  about 1.5 times the first-year value of any other setup. Never adopted;
  the ladder is two rungs now (the free week, then half off the first
  year). It would need its own permanent product ID. August onboarding
  revisions, 2026-08-17 (in git history).

### Watch and measurement

- **A camera session, no Watch.** A propped phone reads stillness and
  breathing (never heart rate). The engine, its harness and the framing
  outline are built on branch `camera-vision` (Melvin still to check the
  outline on a phone); the session flow is designed in
  `CAMERA_VISION_PLAN.md` there and not built. Waits on the ground-truth
  sits in section 5 of that plan (paced breathing at 6, 8 and 12 a minute
  from two people, then counted natural breathing, distance and light);
  the first capture's results are in the plan. MARKET.md calls it the
  largest lever on market size. Paused 2026-08-24, resumed 2026-09-14.
- **An AirPods heart-rate session, no Watch.** On iOS 26 an iPhone workout
  receives heart rate from AirPods Pro 3 or Powerbeats Pro 2; head motion
  gives stillness; breathing from head motion is unproven. A DEBUG-only
  capture probe is built (Settings > AirPods (debug)). Waits on a first
  capture with a pair, which nobody on the team owns. Shipping it changes
  Info.plist, the Health strings and the privacy policy. AIRPODS_PLAN.md,
  2026-09-14.
- **Other wearables.** Aziz ranked them on 2026-09-18 (BACKLOG on
  `origin/camera-vision`): any watch or strap that broadcasts standard
  Bluetooth heart rate (about a week of work, heart only); a Polar H10 or
  Verity Sense through the Polar SDK (real beat-to-beat intervals, so true
  HRV and coherence, the "Pro" tier parked in CLAUDE.md's coherence note);
  Garmin through Connect IQ (in progress on `origin/camera-vision`, see
  `GARMIN.md` there; Garmin also gives beat-to-beat intervals); Wear OS and
  Fitbit only with an Android 808; Oura and Whoop cloud summaries cannot
  measure a sit. Cheap first move: ask people without a Watch which
  wearable they own. The privacy policy and labels move with any of them.
- **The camera finger check (PPG).** A 45 second finger-on-lens read before
  and after a session; real beat-to-beat intervals, so HRV and coherence
  are reachable. Built and verified, then cut in the MVP on 2026-08-05; the
  code is on `full-feature-set`. Waits on testing across skin tones and
  lighting (validated on two people). CLAUDE.md Phase 9.
- **Heartbeat from wrist motion (BCG).** In two still sessions the 100 Hz
  accelerometer's cardiac band matched heart rate; if it holds, beat-to-beat
  intervals with no camera and no strap. Research, not a feature yet: next
  is a three-minute maximum-stillness capture and offline beat
  segmentation. CLAUDE.md "MOTION EXPERIMENTS", 2026-08-07.
- **A heart rate variability (SDNN) trend.** Parked. The Watch pipeline is
  built and dormant. Apple writes SDNN about every two hours and never
  during a session, so nobody can build per-session HRV this way, and a
  real baseline needs the phone to read HealthKit, which is an
  architecture, privacy and App Review decision. The per-person trend is
  weak science: never a causal claim. CLAUDE.md, 2026-08-07.
- **A verified-session mark.** Good stillness plus heart rate sensed for the
  whole session defeats the take-the-watch-off cheat. Worth having if
  Friends ever marks a session as verified. CLAUDE.md, Phase 4.
- **EEG validation, and hardware of our own.** A consumer EEG headband is
  the only way to earn any claim about the brain state; it starts as a
  study of 20 to 30 people, not a product. White-label or our own device
  only after launch data, and a lawyer before a manufacturer.
  STAGE2_ROADMAP.md, Phases 1 and 6. Parked.

### Website and marketing

- **Test the mascot and the pitch in the App Store.** Product Page
  Optimization (icon and screenshots per variant) answers "which one do
  people pick" in days; a PostHog experiment on onboarding cannot reach
  significance on retention at about 20 installs a week. 2026-09-21.
- **Meta app-install campaigns.** They need the Meta SDK or an MMP in the
  app (a build, a review, new App Privacy labels), 8 to 10 creatives at a
  time and about 50 installs per ad set per week. Gated: only after a
  format holds organically and install to trial reaches 5 percent.
  marketing/LAUNCH_PLAN.md, 2026-09-11.
- **Instagram comment-to-DM.** A post says "comment a word and I'll send
  you the link"; the comment opens Meta's 24-hour window, so an automated
  reply is allowed (DMs triggered by a follow are not). Needs a Business or
  Creator account and a tool from Meta's Partner Directory.
  STAGE2_ROADMAP.md, Phase 5. (unverified whether it was ever set up.)

### Other

- **Tab bar icons, drawn by Melvin.** He will generate new ones himself
  (2026-09-23): none of the three directions in `mockups/tabbar-icons.html`
  (Meadow, Line, Otto) were taken. The bar keeps its SF Symbols until the
  art lands; the icons already sit 6pt lower in a bar of unchanged height.
- **Accessibility.** Dynamic Type (282 fixed-size fonts and no
  `@ScaledMetric`, counted 2026-09-23), VoiceOver labels on the custom
  drawing (29 labels today) and a contrast check. The App Store
  accessibility labels stay empty until each one is verified on a device.
  App_ROADMAP_v2.md 8a.2, 2026-09-01.
- **Product emails.** Settings has a "Product emails" opt-in
  (`User.marketingOptIn`), but no list export was ever built, so turning it
  on sends nothing anywhere. Build the export (the privacy policy and label
  move with it) or take the switch out. App_ROADMAP_v2.md, Phase 7.
- **Sign in with Google or email.** Deferred in the v1 plan, which kept
  Sign in with Apple only. App_ROADMAP_v2.md.

## Open threads

- **The real time of day on every valley screen.** Home follows the clock
  since 2026-09-23 (`ValleyScene(clock: true)`, `DayLight.clockProgress`,
  `VALLEY_HOUR` in DEBUG). Onboarding, Block, Friends, Profile, the Guide,
  the Ready screen and the interventions still draw the top of the day,
  because their type on the sky uses daytime ink (`ValleyGround.ink`,
  `DayLight.at(0)`) and would vanish against a night sky. Turning them on
  means checking each one's text for night. The status bar also stays dark
  over a night sky; it needs a light style after dusk.
- **Block: see it work on a phone.** Built and checked on the simulator
  (`block`, behind `FeatureFlags.block`), but only a phone shows a shield,
  Ask Otto's notification, a pass closing the apps on time (the fifteen
  minute DeviceActivity floor and the start-in-the-past trick) and a daily
  limit's threshold. Install 808 Beta with `tools/beta_install.sh` and walk
  RELEASE_CHECKLIST.md's Block list. The breathing screen's haptic
  (`BreathHaptics`) also needs a phone.
- **1.1 (Friends): the real round trip.** The CloudKit Console setup is done
  (CLOUDKIT_SETUP.md). Still owed: one round trip on two phones through
  TestFlight (claim a username, add each other, post, see it land, react,
  report, block), then RELEASE_CHECKLIST.md "OPEN for 1.1", which since
  2026-09-23 includes promoting the private schema for `SessionPhoto` and
  `Session.source`. What's New has to say that past scores were rescored
  (v5.3).
- **Copy for the pivot.** PURPOSE.md, SCIENCE.md, the website (its title and
  footer still read "Meditation, measured on your Apple Watch", beside the
  "first app that scores your meditation" claim), the App Store
  description, keywords and screenshots, and marketing/CAROUSEL_BRIEF.md
  (still pre-launch: a waitlist call to action, a dark palette, the Watch
  pitch) all still sell a Watch measurement app. SCIENCE.md also says
  breath counts for more of the score than anything else, which has been
  untrue since score v5.0.0 (2026-08-14; breath is the smallest weight).
  The release that ships Block has to lead with it (Apple's purpose 2 for
  Family Controls). CONSISTENCY.md.
- **Website redeploy.** Cloudflare Pages is a manual drag of `website/`.
  Waiting in the repo: the branded short links (`_redirects`), the privacy
  page updates and the Google preferred-source badge. After deploying,
  Melvin clicks the badge while signed in to Google to see whether
  meditate808.com is listed.
- **Decide: DIN Next Rounded or SF Pro Rounded.** DIN Next Rounded needs an
  app license from Monotype; the swap is written up in CLAUDE.md "ONE
  ROUNDED FONT EVERYWHERE".
- **Watch `onboarding_completed`.** The payoff screens were cut and
  onboarding was removed and restored within two days; compare completion
  with the rate before the cut, and if it drops, the cut is the first
  suspect.
- **Launch plan items with no record of being done** (checked 2026-09-14;
  confirm or strike): Apple Search Ads ($15 a day, exact match); the
  featuring nomination; press tips; promo codes; Reddit per
  `marketing/REDDIT.md`; reels and carousels logged somewhere the weekly
  review can read; the weekly review against section 6 of
  `marketing/LAUNCH_PLAN.md`. The plan pitched the Watch, and the pivot
  changes that.
- **Ask what "808" means to people.** The no-Watch tester of 2026-09-14 did
  not know what the name meant on first sight; worth one question in the
  next tester conversations or the survey.

## Standing notes

- **TestFlight replaces the App Store app on a phone.** One bundle ID, one
  app: it is never a second copy. Do not delete it to get 1.0.1 back.
  `MeditationStats` is device-local, so deleting the app deletes every
  curve recorded on that phone, and CloudKit brings back the sessions but
  not those. Side by side is the `.dev` beta (`tools/beta_install.sh`).
  2026-09-19.
- **Where Friends can be tested.** A plain beta install names
  `iCloud.com.lockout.meditate808.dev`, a container that does not exist, so
  Friends has no schema there. `WITH_ICLOUD=1` pins the beta to the real
  container's Development environment. TestFlight talks to Production, so
  the two never see each other's friends or posts, and TestFlight is the
  release test. On a simulator, `CommunityModel.testMode` runs Friends
  against the in-memory fake. 2026-09-19 and 09-22.
- **Health permission is asked on the phone.** The Watch cannot show the
  Health sheet itself (it appears on the iPhone, where nobody is looking),
  and authorization is shared between the app and its Watch app, so the
  phone asks for the whole scope (`HealthScope`, in Shared), and only when
  a Watch is paired. HealthKit never says whether a read was denied, so
  someone who taps Don't Allow still meets the 30-second heart-rate
  watchdog on a first Watch session. 2026-09-12.

## Done

One line per day; the detail is in CLAUDE.md and git.

- **2026-09-22:** Block built on `block` (the tab, the editor, Otto's twenty
  screens, "Not now" passes, the glow rule, three extensions, the Ask Otto
  notification), then strictness and pass limits removed; Family Controls
  approved on all four App IDs; onboarding back without the Watch question,
  in the valley, with the stress question answered on Otto; Otto's seven
  states; Friends, the Guide and the blocker editor in the valley; the
  Profile log as a week; a timer tape on the Ready screen and a
  notification when a timed session ends; Otto's glow after a session, then
  the session's own page; Friends and Block testable on a simulator; the
  paywall ladder cut to two rungs.
- **2026-09-21:** the valley sit and Ready screen, with Begin never asking
  about a Watch; Home and Profile in the valley; Otto's aura; question
  screens, bubble and font after Duolingo; the website's Google
  preferred-source badge (deploy pending).
- **2026-09-20:** Otto rigged in Rive (breathing, blinking, waving, on a
  branch); onboarding in Headspace's shape.
- **2026-09-19:** the friendly redesign; onboarding round 3; the Friends
  CloudKit Console setup (CLOUDKIT_SETUP.md).
- **2026-09-18:** the 1.1 social branch (`social-1.1`): followers and
  following, one technique list; the Friends feed given Strava's spacing.
- **2026-09-16:** score v5.3 (stillness cubed) with history rescored; one
  rest day per seven for the streak; Otto's chat quotes the score's working
  and keeps its chats.
- **2026-09-15:** the paywall after the first session; onboarding cut by
  seven screens; Save session rebuilt with an in-app camera and a photo per
  session; delete a session; a five-second countdown on the wrist; Otto's
  chat v1 (on-device, off in Release); the invite reward set to 3 sessions,
  capped at 15; the beta's launch crash fixed with `CloudEntitlement`.
- **2026-09-14:** 1.0.1 live (the Watch start-failure fixes, Health asked on
  the phone, the purchase double-count guard); Friends v1 and v2 built
  behind a flag; no sign-in before onboarding ends, and onboarding resumes;
  no-Watch waitlist emails reach their sheet; the too-short screen; the
  round 2 onboarding fixes.
- **2026-09-13:** the launch email to 33 people (marketing/LAUNCH_EMAIL.md);
  the first Reddit post, removed by Reddit's filters (marketing/REDDIT.md).
- **2026-09-12:** five tabs and usernames; "Give us feedback"; average heart
  rate on the heart panel; reflections that save themselves; "How is this
  scored?"; mindful minutes to Health; the airplane-mode premium hole
  closed; the CloudKit Production schema promoted; the PostHog dashboard and
  its sheet.
