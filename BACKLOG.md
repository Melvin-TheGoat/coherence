# 808 backlog

One list, so nothing said in a session is lost between sessions. Newest at
the top of each section. Move a line, never delete it: DONE lines are the
record. (Melvin, 2026-09-12: "I am saying a lot and not finishing much.")

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

- PARTLY DONE 2026-09-12, in the build after 1.0.1: the two Watch reasons.
  The setup screen (12a) told people 808 "should already be waiting" on their
  Watch and let them continue without ever checking; the failures then landed
  a minute later, after the paywall, out of context. `WatchProbe` is now the
  one reader of paired/installed, shared by the setup screen, the walkthrough
  connect screen and the failure screen; the setup screen shows both live and
  says "Continue anyway" when they are not met; the failure screen watches
  the problem clear; the preflight waits for WCSession activation before
  reading `isPaired`, so a phone with no Watch is no longer told to bring its
  Watch closer. **STILL OPEN: `heartRateUnavailable` (4 of the 10).** That is
  a Health permission the phone cannot read back, so the app cannot tell
  whether it is denied until a session fails. Worth investigating whether the
  Watch can ask for it earlier, at the setup screen, instead of at first use.
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

- **1.0.1** (airplane-mode hole closed, rating prompt): SUBMITTED, "Waiting
  for Review" as of 2026-09-12. Note it does NOT contain the purchase
  double-count fix, the screen names, or the team-device switch; those
  landed after it was archived.
- **1.0.2** (five tabs, username, Restore + Redeem, first-feedback fixes,
  mindful minutes, purchase guard, readable analytics screen names,
  team-device switch): on `mvp`, on the beta, waiting on Melvin's test.
  **Aziz, 2026-09-12: hold the submission until the session-start failures
  above are understood.**

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
