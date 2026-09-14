# 808 backlog

One list, so nothing said in a session is lost between sessions. Newest at
the top of each section. Move a line, never delete it: DONE lines are the
record. (Melvin, 2026-09-12: "I am saying a lot and not finishing much.")

## Launch plan items with no record of being done (checked 2026-09-14)

From `marketing/LAUNCH_PLAN.md` section 4, live day and weeks 1 to 2. Each
is cheap and each sends Watch owners to a first session on 1.0.1, which is
the test the product is waiting for (zero strangers have completed a session
yet; every completion so far is a founder, family or friend).

- **Apple Search Ads not started.** $15 a day, Advanced, exact match on
  "meditation apple watch" and its siblings. The one always-on paid line.
- **Featuring nomination not submitted** (App Store Connect, aim three weeks
  out).
- **Press tips not sent** (9to5Mac, MacRumors, AppleInsider, iMore, Cult of
  Mac; the Watch angle, never "first"; `ct=press` link).
- **Promo codes not generated** (App Store Connect > Promo Codes, 100 per
  version; gift to Watch YouTubers with no ask).
- **Website is one deploy behind.** The live site has the plain App Store
  link; the `website` campaign link, the branded short links
  (`meditate808.com/reddit` returns the home page, no redirect) and the
  updated privacy page are in the repo and not deployed. Drag `website/`
  into Cloudflare Pages.
- **Reels and carousels:** no record in the repo either way. If they are
  going out, log the format and the day somewhere the Friday review can read.
- **Reddit:** r/SideProject from Melvin's account today; r/QuantifiedSelf
  Monday megathread; the rest per `marketing/REDDIT.md`.
- **Friday review** (this Friday, 2026-09-18): the sheet's Overview tab
  against the scorecard in the launch plan, section 6.

## Onboarding feedback, round 2 (one tester, no Watch, 2026-09-14)

**Status 2026-09-14 evening: every "small fix" and copy item below is
BUILT on `mvp`, plus three of the decisions Melvin took the same day
(the $400 screen moved into the paywall ladder as its first rung, the
Watch gate has three answers, "How did you find us?" opens the interview).
Not taken, still open: "needs an Apple Watch" before the interview; the
"Last thing" split; moving the proof screens into the tour; animation;
real design. One finding the tester could not have named: onboarding
rendered in the SYSTEM colour scheme because no Preferences row exists
until it finishes, so on a light-mode phone the whole flow was light and
the app went dark afterwards. That was the "black text", "whiter cards",
"colours bleeding" and the blue caret. The default theme now applies from
the first frame. For Aziz's sheet: the Watch gate now emits a third
outcome, `notYet`, beside `hasWatch` and `waitlist`; the Installs tab's
gate column will show it raw until the script maps it.**

Walked the whole interview on a phone with no Watch paired. Grouped by what
it costs. The sheet's Screens tab agrees with the big one: nobody leaves on
the proof screens (0% each), people leave on screen 1 (19%), at the Watch
gate (35%) and in the tour after onboarding (33%, 25%, 67%, 100%).

Small fixes, one build:
- Going BACK to an answered single-select shows the tick but no Continue;
  the "tap an answer" hint is easy to miss. Show Continue whenever an answer
  is already selected.
- Hide the scroll indicator on every onboarding screen; it overlaps the UI.
- Option rows blend into the background; raise the contrast.
- Haptic on every option tap, consistently (some screens have it, some do
  not, and the missing ones read as broken).
- Multi-select ("what do you already track") uses circles; multi-select is
  squares by convention. Its Continue also sits differently from every
  other screen.
- The no-Watch waitlist email field renders in blue, which reads as a link.
  Grey placeholder, lowercase "email", standard field.
- "Where most people start": the circle clips at the edge.
- "Here's what you told us": some cards have black text and whiter
  backgrounds, others grey. Unify.
- The star-rating screen ("Does this sound like it'd work?") does not say
  what the stars mean. Label it.

Copy:
- "Fried" on the stress screen; reconsider the word.
- "You'd be in reasonable company" reads oddly; re-read the wall screen and
  the surrounding copy aloud.
- "How long have you been meaning to start" needs a "I haven't, really"
  option, and its ranges overlap ("a year or so" against "years"; "3+"
  against "3 to 5"). Dedupe.

Decisions (Melvin + Aziz):
- **Say "needs an Apple Watch" before the interview starts**, not at screen
  12. The tester reached the $400 hardware screen assuming the app was for
  them. The App Store page says it, the flow does not.
- The hardware screen ("Seeing your body meditate used to cost $400") read
  as presumptuous and as an upsell mid-interview. Options: cut it, or move
  it after the Watch gate so only Watch owners see it.
- Watch gate as three answers (Yes / No / Not yet), or a modal that states
  the requirement and offers the waitlist.
- Split the "Last thing" screen: age on one, username on its own at the end.
- "How did you find us?" earlier. Only 42% finish onboarding, so 58% of
  installs never answer it where it sits now (screen 15). Screen 2 or 3
  would capture nearly everyone, at the cost of one more early screen where
  the first drop already happens.
- Too much reading before the first session: move the sample-session and
  proof screens (18 to 22) into the tour after the first Begin. The data
  says those screens lose nobody, so the case is length, not drop-off.
- Animation on the minimal screens (the tester named Duolingo's tool, which
  is Rive). Later, and only for a moment or two.
- Real design and photography instead of code-drawn screens. Later.
- Customer discovery question: "what does 808 mean to you when you first
  see it?" The tester did not know.

Already true:
- Per-screen churn analytics exist (the sheet's Screens tab).

Refused:
- "Force sign-in, don't let them skip." No. Guideline 5.1.1(v) makes
  sign-in optional for an app that works without an account, and it was a
  documented rejection reason in the audit. Stays optional.

## Cut the fat out of onboarding (Melvin + Aziz, 2026-09-14, direction)

"We think the onboarding is too crowded, so we want to lean towards cutting
the fat down." A newcomer today sees about 33 screens from Relief to sign
in. The Screens tab says the proof screens (17 to 22) and the plan screens
(23 to 26) lose almost nobody, so the case is length and attention, not a
drop-off cliff; the cliffs are screen 1 (19%), the Watch gate (35%) and the
tour's two-minute demo (67%, then 100%). Proposal, awaiting the founders'
list: cut the wall (18), proof: the body is visible (19), proof: your way
(22), your first week (25) and the star rating (26, internal signal only);
fold the second escalation question (06b) into the first and the second
body question (08b) into the first; keep the sample-session pair (20, 21)
as the one demonstration. That is 33 to about 24 for a newcomer. Separately,
make the tour's two-minute demo skippable, since it is where the most people
leave after finishing the interview.

## Decided, not started

- **AirPods as the heart-rate source** (Melvin's friend, 2026-09-12). AirPods
  Pro 3 and Powerbeats Pro 2 carry an optical heart-rate sensor and iOS 26
  exposes it to apps through HealthKit during a workout. Paired with head
  motion from `CMHeadphoneMotionManager` (stillness, maybe breathing), that
  is a second no-Watch path beside camera vision. Investigate: what a
  phone-only `HKWorkoutSession` receives from the buds, and whether head
  motion carries a breath. Owner: unassigned.

- **Otto, the data interpreter** (Melvin, 2026-09-12). A chat you can ask
  about your own sessions: heart rate, stillness, breathing, the score, and
  meditation knowledge generally. Speaks in "the data suggests", never a
  medical claim, never a diagnosis. Named Otto (the name hiding in 8-0-8).
  Architecture decision recorded in CLAUDE.md: **on-device first** (Apple's
  Foundation Models framework, iOS 26, Apple Intelligence devices), because
  sending heart-rate data to a third-party model is the exact thing
  guideline 5.1.3 forbids without explicit consent and changed privacy labels,
  and because we told App Review there is no AI service in the app. Knowledge
  comes from our own bundled sources (SCIENCE.md, the guide, the score sheet)
  fed as context, not from training. Older devices get an honest "Otto needs
  iOS 26" card. Needs: a mockup first (Aziz's rule), the guardrail prompt,
  the disclaimer copy, a review of App Privacy answers even for on-device.
- **Guided sessions in more lengths** (tester feedback, 2026-09-12). 10, 15
  and 20 minutes beside the 25. Cheapest honest path: commission Donny for
  cuts of the same script; then a length picker on the Guided card.
- **AI coach voice library** (Melvin's wedge). ON HOLD: ElevenLabs was tried
  and "is not there yet". When it is, the first version is a pre-generated
  library by length and voice, offline, no runtime generation. Not before.
- **Friends** (Search tab placeholder). Needs a backend; the username is
  cosmetic until then and must not be presented as reserved.
- **Camera-vision sessions** (branch `camera-vision`): the answer to no-Watch
  churn. Ground truth is the bottleneck; the in-app collector exists.
- **Rating prompt is in 1.0.1.** Watch the ratings count in the launch
  scorecard.
- **Handle for the coach's name** (the narrated guide, not Otto): open.
  Candidates offered: Eight, Cadence, Tempo, Coach 808.

## Bugs found in the live data (Aziz + Claude, 2026-09-12 evening)

- DONE 2026-09-12, in the build after 1.0.1: `heartRateUnavailable` (4 of the
  10). The Watch asked HealthKit for authorization inside `begin()`, and the
  system can only present the Health sheet on the IPHONE, so the prompt landed
  on a screen nobody was looking at while the workout ran unauthorized; the
  30-second watchdog then aborted the user's first session. Authorization is
  shared between an iOS app and its companion Watch app, so the phone now asks
  for the whole scope one screen after the health-consent screen, and only for
  people who said they have a Watch. `HealthScope` (Shared) is the one
  definition of that scope; `HealthScopeTests` scans the iOS sources to keep
  reading Watch-only.
- PARTLY DONE 2026-09-12, in the build after 1.0.1: the two Watch reasons.
  The setup screen (12a) told people 808 "should already be waiting" on their
  Watch and let them continue without ever checking; the failures then landed
  a minute later, after the paywall, out of context. `WatchProbe` is now the
  one reader of paired/installed, shared by the setup screen, the walkthrough
  connect screen and the failure screen; the setup screen shows both live and
  says "Continue anyway" when they are not met; the failure screen watches
  the problem clear; the preflight waits for WCSession activation before
  reading `isPaired`, so a phone with no Watch is no longer told to bring its
  Watch closer. (An earlier version of this line called `heartRateUnavailable`
  still open; the bullet above supersedes it.) **What remains open on heart
  rate:** HealthKit never reveals whether a READ permission was denied, so if
  someone taps Don't Allow on the phone prompt the app cannot know, and their
  first session still ends at the 30-second watchdog with the "We can't read
  your heart rate" screen. Nothing to build until the next week of data says
  how many people that is.
- **10 of 13 sessions never started.** `session_start_failed` fires 10 times
  against 3 completions, by far the worst ratio on the dashboard, and the
  Watch gate is NOT the cause: 9 of 11 people said they own a Watch. Reasons
  over 7 days: `heartRateUnavailable` 4, `watchNotPaired` 3,
  `watchUnreachable` 2, `watchAppNotInstalled` 1. **This is the single
  biggest thing wrong with the product right now** and it is worth a session
  of its own: four people denied or could not deliver heart rate, three had
  no Watch paired despite saying they had one, one never installed the Watch
  app. Each of those is a different fix (permission copy, a real pairing
  check at the gate, the Watch-install screen landing late).
- **Two people who finished onboarding never pressed Begin, and a third of
  everyone quits on screen one.** 16 reach "Relief: you're not bad at
  meditation", 12 leave it. Everyone who reaches the payoff screens finishes.
  So the leaks are the very first screen and the gap between onboarding and
  the first session, not the interview.
- DONE, in the build after 1.0.1: repeat taps on the paywall's buy button
  logged repeat `purchase` events (one person, four in eighteen seconds),
  because StoreKit returns `.bought` instantly for a product the Apple ID
  already owns. `advance()` now guards on `started` and `buying`.
- DONE, in the build after 1.0.1: a Lifetime purchase logged a
  `trial_started` it never had.

## In flight

- **No-Watch waitlist emails now reach us (next build).** The in-app
  waitlist screen saved the typed email on the person's own phone only, so
  its "we'll write to you" was unkeepable and every address from 1.0 and
  1.0.1 is lost. `WaitlistClient` now posts it to the "808 no watch
  waitlist" sheet (shared Drive folder) through the Apps Script web app in
  `tools/nowatch-waitlist.gs`, verified end to end 2026-09-14. **Owed at the
  submission that ships it:** App Privacy label in App Store Connect adds
  Email Address (linked, Developer's Advertising or Marketing, not
  tracking) to match `PrivacyInfo.xcprivacy`; redeploy `website/` for the
  updated privacy page. If the script is ever edited, redeploy as a NEW
  VERSION of the existing deployment; a new deployment changes the URL and
  strands every shipped build.

- **Reddit, first post REMOVED by Reddit's filters** (r/SideProject,
  posted 2026-09-13 1:50 PM EDT from u/No_Shelter5464, Aziz's new account;
  removal seen 2026-09-14). Cause is the account, not the post: no karma
  plus an outbound link trips the site-wide spam filter. Next: modmail
  r/SideProject to approve it (text in `marketing/REDDIT.md`), earn comment
  karma on the account before any further link post, never repost the same
  thing from the same account. The rest of the plan stands: r/apple waits
  for five organic comments (next Sunday at the earliest), r/iosapps for
  ten local karma; r/AppleWatch, r/iOS and r/iphone need a modmail first.

- **Launch email to the waitlist + survey list: SENT 2026-09-13, 1:16 PM
  EDT**, from Aziz's Outlook, 33 people in BCC, campaign `ct=waitlist`
  (draft and rules in `marketing/LAUNCH_EMAIL.md`). Aziz chose to send
  while 1.0.1 (the Watch-start fixes) was still Waiting for Review, knowing
  the live 1.0 fails most first sessions; the email asks for a reply after
  the first session, so failures come back as replies. Read the `waitlist`
  campaign in App Store Connect against this timestamp; it shows only after
  five distinct installs.

- **1.0.1 is LIVE (approved and released 2026-09-14, about 4 AM EDT;
  first App Store installs on it the same morning: Ireland 4:07, Oslo 7:05).**
  Resubmitted with everything by Aziz 2026-09-12, 11:24 PM, build
  202609130259. Pulled once more at 11:20
  to swap store screenshots 3 and 6 for the five-tab layout (Profile tab
  and Guide tab); screenshots are locked while a version is in review and
  cannot change after release without a new version, so it had to happen
  before this one went through.
  Melvin's build 202609121757 (five tabs, reflections, average HR, mindful
  minutes, feedback link, airplane-mode fix, rating prompt) was pulled from
  review and replaced by build **202609130259**, archived from Aziz's Mac
  on the org team, which adds tonight's work: the three Watch start-failure
  fixes, the Health prompt on the phone during onboarding, the purchase
  double-count guard, readable analytics screen names, and the team-device
  switch. Reasoning: two sequential reviews would have put the Watch fixes
  in users' hands around the 16th; one submission costs a day of queue
  position. Melvin's beta test of the evening changes was skipped on Aziz's
  call ("push out the newest version"); the simulator checks in the commits
  stand in for it. There is no separate 1.0.2 any more.

## Done (2026-09-12)

- "Give us feedback" in Settings: opens Mail to support@meditate808.com with
  the version and build already in the body.
- "Heart Rate" in title case on the results graph and its mirrors.
- 808 Beta crash at launch: the DEBUG CloudKit probe guessed a container it
  was not entitled to; it now reads the embedded profile. Beta 202609121726.
- Average heart rate on the heart panel ("79 → 54 bpm · avg 62").

- Reflections save themselves; gold Save button.
- "How is this scored?" link under the ring.
- "Guided meditation" as a technique; guided sessions pre-tagged.
- "First time meditating" lost its question mark.
- Do Not Disturb tip on the setup screen (no API exists to switch it on).
- Share sheet leads with the system sheet; Instagram is secondary.
- Mindful minutes written to Health per session; policy updated.
- Five-tab layout, username in onboarding, Membership section in Settings.
- Airplane-mode premium hole closed; 1.0.1 archived.
- Launch plan, PDF, website switched to the App Store, offer codes explained.
- CloudKit Production schema promoted (Aziz).
