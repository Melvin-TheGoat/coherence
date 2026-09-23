# 808 backlog

## Otto is customizable, and points come from the habit (Aziz, 2026-09-21)

Told to me as knowledge rather than a task, so it is recorded rather than
started. **People earn points by meditating habitually and spend them on
customizing their sloth.**

Why it matters for what is being built now:

- **Otto's head is already the avatar** on Profile and on a friend's page,
  which is the surface a customization would show up on, so nothing there
  has to change shape when it lands.
- **The currency should be the habit, not the score.** Aziz said habitually,
  and the baseline has no score anyway. `StreakCalculator` and `OttoAura`
  already derive consistency from session dates without storing anything,
  and points are the first thing that would have to be STORED and synced,
  which makes them a CloudKit schema change and therefore a release step.
- **It collides with the aura idea in a good way.** `OttoAura` already draws
  Otto at six stages; a customized Otto has to survive being drawn at all
  six, and both want the same thing: one figure whose appearance carries
  meaning.
- Not decided: whether points are spendable currency or unlocks, whether a
  customized Otto is visible to friends, and whether awards become the
  unlock mechanism rather than a parallel one. Eighteen awards and a points
  economy doing the same job would be two ladders.

One list, so nothing said in a session is lost between sessions. Newest at
the top of each section. Move a line, never delete it: DONE lines are the
record. (Melvin, 2026-09-12: "I am saying a lot and not finishing much.")

## 808 is a consistency app: Block, and the guide moves to Home (2026-09-21, Melvin)

The pivot and the whole Block design are in `CONSISTENCY.md`. **DONE:** the
guide is a circle under the streak on Home (opens "How to meditate");
`CONSISTENCY.md` written; `mockups/block-v1.html` drawn (the Block tab, a
blocker's settings, shield to notification to Otto to the two doors, and the
twenty interventions). **APPROVED 2026-09-22** ("they all look fire"), with
the five answers now in `CONSISTENCY.md` > Decided: meditating releases the
apps for the rest of the window; "Not now" costs glow only if the window
then passes with no meditation; Strict in v1; Block is paid; the default is
**Mindful day** (the picked apps held all day until you meditate, one switch
off). **DECIDED 2026-09-22:** a skipped window costs 20 × hours / 24
(Melvin's formula), built into `OttoAura` with tests; a free person finds
Mindful day waiting on the Block tab and switching it on opens the free-week
offer. **DONE 2026-09-22:** Family Controls (Distribution) approved on all
four App IDs (`com.lockout.meditate808` plus `.monitor`, `.shield`,
`.shieldaction`), within minutes. **OPEN, founders' call:** onboarding was
cut by Aziz in `d4ddbfc` (2026-09-21) and Melvin did not know; whether it
returns, and whether it asks the Block questions, decides where a new person
meets Mindful day. **Then:** Block in Swift on its own `block` branch: the Guide tab becomes
Block; FamilyControls, ManagedSettings, DeviceActivity, three extensions,
App Group; the notification into the interventions; the "Not now" input to
`OttoAura`; tested on a phone, since the simulator cannot show shields.
**Also owed by the pivot:** PURPOSE.md, SCIENCE.md, the website hero, App
Store copy.

## Home in Aziz's valley, Otto centred, the bar lowered (2026-09-21, Melvin)

**DONE:** merged Aziz's `mvp` (the valley sit, the Ready screen, no
onboarding) into `friendly-ui`; Home rebuilt in the same valley with Otto in
the middle at his aura stage, the streak in the corner, the aura card and
Brainrot's three tiles on the grass; the tab bar 16pt lower. **Next, if
wanted:** Guide, Friends and Profile in the same theme. Home is still
Melvin's to critique.

## Otto's aura follows your practice, and how to A/B it (2026-09-21, Melvin)

**BUILT on Home (2026-09-21):** the rule (`OttoAura`, 12 tests), the three
new poses from Melvin's sheet, and `OttoAuraFigure` with the glow, orbits,
sparks and lift drawn in SwiftUI. **Next, not started:** the onboarding "See
for yourself" slider screen from the mockup, and Melvin's critique of how the
stages look on a phone. (Decided the same day: he gets sad, and he lives on
Home.)
**MOCKUP BUILT: `mockups/otto-aura.html`.** Melvin kept
the sloth ("you know what I like the sloth") and sent the same six-stage
progression drawn with him. The mockup is Brainrot's "See for yourself!"
slider screen with Otto (stages cut from the sheet; 80 and 100 draw the aura
over the 60 sloth, as Rive would), plus a proposed rule: start at 40, +10 per
day meditated, -20 per missed day with the streak's one rest day a week free,
derived from session dates, consistency only. The calls: does he get sad,
where he lives (Home is frozen), and three new transparent poses of today's
Otto (lying, frustrated, curious). Earlier the same day the idea arrived as a
soul character instead: Melvin and Aziz were considering replacing Otto with
a glowing "soul" character that grows brighter and gains aura with
consistent practice and shrinks and looks sad when neglected (six stages,
0 to 100 percent; Brainrot's melting brain is the reference, including its
onboarding "See for yourself!" slider). Open questions: the drive should be
consistency (derived from sessions like the streak, with rest days), never
the measured score, or it collides with "the gold ring means a measured
score"; a sad mascot is a guilt mechanic, which sits awkwardly beside the
never-tell-the-reader-what-they-lack rule, so it is a founders' call; the
concept art is on a dark ground and the app is one cream appearance.
**A/B:** PostHog's iOS SDK is already in, so a feature flag plus a PostHog
Experiment can split onboarding by mascot; at about 20 installs a week an
in-app test cannot reach significance on retention for months. App Store
Product Page Optimization (icon and screenshots per mascot) and small paid
creative tests answer "which mascot do people pick" in days.

## The breaths start on I'm ready, and there are three (2026-09-21, Melvin)

**DONE:** the invitation and the breaths are one screen, so I'm ready swaps
the words in a single frame with no slide and no fade; Continue appears only
after the third breath (30 s), not after the first; Otto holds still on the
invitation and the words follow his own chest once released. Verified from a
screen recording at 0.1 s per frame. Same day, second ask ("he still barely
looks like hes breathing"): Otto sits about 28 pt lower and the old sage
breathing circle is back above his head, 90 to 180 pt, swelling on each inhale
on the same clock as the words. **Not judgeable on the simulator:** the
breath haptic, which needs a phone.

## Breathing that works, Back that goes back, and a website badge (2026-09-21, Melvin)

**DONE:** the sitting Otto breathes through a mesh (chest widens, shoulders
rise, lap still); the breathing screen advances through all three breaths
(its timer was being reset by redraws); the invitation fades into the
breathing with Otto in place (SUPERSEDED the same day: no fade at all, see
above); Back slides the other way; Back from What's
waiting works again; What's waiting is centred with bigger rows; the website
footer has Google's preferred-source badge.

**OWED BY MELVIN:** redeploy `website/` to Cloudflare Pages for the badge to go
live, and click it while signed in to Google to see whether meditate808.com is
listed. **Worth a look next:** the website footer still says "Meditation,
measured on your Apple Watch" beside the retired flower mark, which the pivot
makes stale.

## Question screens rebuilt to Duolingo's, and the pivot (2026-09-21, Melvin)

**DONE:** no pause before Otto speaks; the breath moves only his chest (the
floating came from a whole-body stretch, a branch bob, and a layout jump when
Continue appeared); his head no longer clips; the count screen is just the
bubble and Otto; the background wave is gone; question screens are Duo's
layout (arrow + progress bar, Otto under the arrow, the question in his
bubble, no "1 of 8", no subtitle); answers look like the profile screen's
fields; every onboarding button is the lifted gold one.

**THE PIVOT, standing:** 808 is a meditation app with many features, social
first, camera session coming. Not a Watch data app. Copy touched today no
longer leans on the Watch. **Still Watch-first and worth his call:** the
Watch gate question and its no-Watch waitlist, the health-consent screen,
and the tour.

## Duolingo's bubble and font (2026-09-21, Melvin)

**DONE:** Otto's onboarding lines type about ten times faster (300 characters
a second), in a see-through outlined bubble whose tail is part of the same
line; the whole app is on one rounded family (SF Pro Rounded) through the root
`fontDesign`, with Baloo 2 retired from the display sizes.

**DECISION FOR MELVIN: buy DIN Next Rounded or keep SF Pro Rounded.** DIN Next
Rounded is Monotype's and needs an APP licence to ship inside 808 (MyFonts /
Monotype sell them per app; a desktop or Adobe Fonts licence does not cover
it). If bought, the swap is recorded in CLAUDE.md "ONE ROUNDED FONT
EVERYWHERE". Also open: whether Home's filled bubble should become the
outlined one, which waits for his Home critique.

## Otto's second pass, and the revamp is parked (2026-09-20, Melvin)

His list, in his words: "The sloth isnt breathing in the onboarding, make it
seem like hes breathing naturally from his chest using rive, and is off center
in that screen. and he also isnt even talking... And in the onboarding hes a
bit too small... make a screen that declares how many questions its going to
be like duolingo did. Hes also not waving. in the start. I also want him on a
branch somehow. some kind of greenery."

**DONE, all of it, on `friendly-ui`:** the breath is a feathered chest patch
that swells while the body barely moves; he blinks every five seconds; the
Talk timeline opens a mouth and his lines are typed into a bubble while it
moves; the wave fires (it never did: the data binding had not landed when the
trigger was sent); he is drawn the full width of the screen on a branch with
leaves running off both edges; and a new screen before the interview declares
"Eight at most, about a minute", with the ceiling derived from the model so a
cut question moves the copy. Detail in CLAUDE.md, "OTTO BREATHES FROM THE
CHEST".

**PARKED by the same message:** "Keep it as it was before and ill critique it.
Slow down with this UI revamp. Keep it to 5 tabs." So `mockups/ui-v4.html`
stays a drawing, Guide keeps its tab, and Home is untouched. Its three
questions (Guide's tab, Home's Recent list, Save session merging into results)
wait for Melvin.

**Still open on Otto:** more animations if he wants them (a tail flick, a
reaction when an answer is tapped, leaves that move when he waves); the branch
is vector drawn in Rive, so a generated branch asset could replace it; and the
breath haptic (`BreathHaptics`) is built and still unused on the breathing
screen.

## TestFlight REPLACES the App Store app, and deleting it costs the curves (2026-09-19)

Melvin: "the TestFlight build seems to have overwrote the live App Store
version". It did, and it always will: one bundle id, one app per device.
TestFlight is not a second copy, it is the same app updated.

**Do not delete it to get 1.0.1 back.** `MeditationStats` is device-local by
the 5.1.3 split, so deleting the app deletes every curve, heart trace and
stillness series ever recorded on that phone. CloudKit brings the sessions
back and cannot bring those back, and the results screen would show the
missing-stats card forever.

Side by side is the `.dev` beta: a different bundle id, so it installs
BESIDE whatever is under `com.lockout.meditate808`, and with `WITH_ICLOUD=1`
its Friends work against the real container's Development environment.

## "It overrode my history" was the v5.3 rescore (2026-09-19): NOT A BUG

Melvin's first TestFlight launch moved a sit from 85 to 92. Diagnosed, not
guessed: his App Store 1.0.1 was score v5.2 (floored stillness); 1.1 is
v5.3 (cubed) and runs `scoreBackfillDone.v8` on first launch. The migration
writes `overallScore`, the three doorway fields and `algorithmVersion` and
touches no measurement, and every `DemoData.seed` call sits inside
`#if DEBUG`, so a Release build cannot have invented sessions. Verified
against the real engine: the cube lifts a typical settled sit by +2 to +17.

Consequence for the release, now on RELEASE_CHECKLIST.md: **every existing
user's history jumps when 1.1 lands**, so What's New has to say so.

## Friends "not working" on the beta, and how it actually gets tested (2026-09-19)

The beta's DEFAULT entitlement is `iCloud.$(CFBundleIdentifier)`, which for
the `.dev` bundle names `iCloud.com.lockout.meditate808.dev`, a container
that does not exist in the Lock Out Inc. Console at all (the picker lists
only `iCloud.com.lockout.coherence` and `iCloud.com.lockout.meditate808`).
So a plain beta install has no schema and no indexes to query.
**`WITH_ICLOUD=1` pins it to the real `iCloud.com.lockout.meditate808`
instead**, which since 2026-09-19 has the full Friends schema in
Development, so the side-by-side beta CAN do Friends. It talks to
DEVELOPMENT while TestFlight talks to PRODUCTION, so the two never see each
other's friends or posts. Aziz's dev builds hit `iCloud.com.azizmahmud.808`, a third one.
**Nobody's cable build talks to the container that was set up.**

The main container is done: Development has the 14 fields, 7 indexes and
roles (Melvin, 2026-09-19), and Production shows all seven Friends types.

**Therefore the Friends test is TestFlight, not the beta.** A TestFlight build
is the production bundle id, talks to Production, and reaches both phones
with no signing gymnastics. It is also the checklist's own gate. Archive
from `friendly-ui` (which now carries the social branch merged in), upload,
internal testers Melvin + Aziz, run the round trip in CLOUDKIT_SETUP.md.
Walk RELEASE_CHECKLIST.md's ALWAYS list before the archive (it is the same
archive that would go to review if the round trip passes).

## Otto rig RUNS, on the redesigned art (2026-09-20)

Done: `Coherence/Otto/Otto.riv` breathes, waves and talks, RiveRuntime
linked, Home runs it, tapping Otto waves, and the PNG pulse still stands in
if the file ever fails to load. The furry redesign is the art inside it.
The export bug that kept it from ever running is diagnosed and fixed in
CLAUDE.md "THE RIVE EXPORT ONLY EVER EMITTED THE FIRST ARTBOARD"; the short
version is that a runtime Rive file should hold exactly one artboard.

Bones cannot be made from the MCP, so the wave is a body rock rather than a
bending arm. Three hand-drawn bones in the editor would upgrade it and the
MCP can bind and weight them.

Open, in order:
1. **Onboarding v3 is BUILT** (2026-09-20): the Headspace shape, the payoff
   block cut, Otto breathing at six a minute through the rig on the breath
   screen. What is left is watching `onboarding_completed` against the
   pre-cut rate, since that block was not losing anyone before it went.
2. Breath haptics on the breathing screen (`BreathHaptics`, built, unused).
3. A second pose if Otto should ever do something other than wave. The
   redesign made `OttoTalk` and `OttoWave` the same image, so the rig's
   pose swap currently swaps like for like.

## Home v3 and Onboarding v3 mockups, Otto in a tree (Melvin, 2026-09-20): HOME B BUILT, ONBOARDING AWAITING A PICK, RIVE CHOSEN

Melvin, later that day: "Go with B for home, build it. And ok lets go with
rive." Home B is on `friendly-ui` (Otto beside you with a rule-written
speech bubble, tap to cycle, a 5 s breathing pulse). Rive waits on the
desktop editor being installed and signed in on this Mac; then the rig
(breathing, wave, talk), `RiveRuntime` in project.yml, and the pulse
modifier swapped for a `RiveViewModel`. The haptic pattern rides the same
state machine. The onboarding mockup still needs Melvin's yes.

Melvin: Home's photo placement is weird; he wants Otto like Duolingo's owl,
"hanging out on a tree and calmly talks to you"; and the onboarding rebuilt
in Headspace's shape with Otto animated on top, cream, question count
shown, Otto breathing top-left with haptics.

- `mockups/home-v3.html`: four directions, same palette and cards, Otto in
  a different place in each. A on the branch (the literal ask; needs a
  branch pose), B beside you (Duolingo's shape, ships with today's art), C
  the tree down the left edge (cards lose 70pt), D Otto's clearing
  (character first, Finch). The decision is one question: is Home a
  greeting or a dashboard.
- `mockups/onboarding-v3.html`: Headspace's nine screens in 808's words:
  welcome with a wave, "three breaths together", breathe in and out with
  Otto's head rising, the question template with "N of M" and a breathing
  Otto top-left, the Watch gate, "here's what's waiting", reminders with
  Otto holding the clock, the trial timeline. Two repo rules kept: no
  sign-in on screen one, and the trial screen is drawn as the
  after-first-session paywall's face, not an onboarding step.
- Serve `mockups/` with the "mockups" launch config (port 8991); opening
  the files as data: URLs drops the relative Otto images.

**Otto animation, researched (agent, 2026-09-20):** Rive, not Lottie, not
hand-coded. Duolingo animates its characters with Rive (their blog,
2022-11). Rive rigs the existing PNGs through a mesh with bones (no new
art), and Swift drives a state machine (`breathing`, `wave`, `talk`) so the
haptic can fire on the same clock. Cadet plan $9/month for one seat to
export; runtime MIT, about 4.7 MB. Official Rive MCP served by the desktop
editor at 127.0.0.1:9791, plus a CLI with a text format, so the rig can be
built from Claude Code. Headspace uses Lottie. The Substack article's
Duolingo and Headspace case studies are behind its paywall; the free part
is principles only. Fallback that ships this week: a SwiftUI scale pulse on
the PNG head with a CoreHaptics pattern (transient at inhale, softer at
exhale, engine prepared before the screen and after each cycle).

## Onboarding round 3 and the bar (Melvin, 2026-09-19): DONE, on social-1.1

Cut "Can you be alone with your thoughts?" and the name-and-age screen (the
name is asked on Create your profile); the tour ends the tutorial with no
"put your Watch on" screen; the plus spotlight now frames the whole circle;
the tab bar and the feed lost their extra bottom air. 359 tests. CLAUDE.md
"ONBOARDING, ROUND 3".

## 1.1 IS THE SOCIAL RELEASE, AND IT WAITS FOR AZIZ (Melvin, 2026-09-18)

Melvin: "push the social media aspect ASAP, because that seems most
desirable by users right now", and Otto and camera vision would delay it
over privacy-policy work. So branch **`social-1.1`** carries Friends ON for
Release, Otto OFF, camera vision absent, version 1.1, plus the three asks
(follower and following counts, one technique list for both pickers, Silence
and Breath work). 359 tests green; Release compiles; beta 202609182145 is on
Melvin's phone.

**DECIDED: the CloudKit Console work and the first real iCloud round trip
happen with Aziz, not before.** Nothing is submitted until both are done.
The full list is RELEASE_CHECKLIST.md "OPEN for 1.1"; the two that matter
most, because they break Friends on day one rather than fail review:

1. The six public record types in PRODUCTION **with their queryable
   indexes**. Indexes are never created lazily the way fields are, so
   without them every feed, search and request fails on a real install while
   the simulator's fake works perfectly. This is the 1.0 failure exactly.
2. One real round trip on two phones: claim a username, add each other,
   post a session, see it land, report and block. Friends has never run
   against real iCloud beyond the username claim.

Then: age rating (UGC and Social to Yes), privacy labels matching the
manifest, the website redeploy so the live policy and terms carry the new
sections, the report endpoint deployed so a report reaches a person, and
store screenshots showing the Friends tab.

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

## Cut the fat out of onboarding: DONE 2026-09-15 (Melvin's list)

Cut: doing nothing (06b), how do you know it worked (08b), the anchor (13,
"people don't want to be forced to commit to what time they are going to
meditate"), proof: the body is visible (19), proof: your way (22), your
first week (25), the star rating (26). Kept and MOVED: the celebrity wall,
now the last screen before the paywall, after the walkthrough. The reminder
time is picked on the notification screen (8 AM default, editable in
Settings) since the anchor no longer sets it. Every cut screen keeps its
Step case and answer field, so resume records and readers keep working;
they are simply never routed to. A newcomer now sees about 23 screens.
NOT done, still open: ending the tour after "put your Watch on" and
deleting the two-minute demo (the biggest leak after the gate); Melvin has
not said yes to that one.

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

## Friends without iCloud? (Melvin, 2026-09-15, needs a founders' call)

Melvin: "It should be possible without iCloud in my opinion." Where it
stands: friends have no server by Aziz's decision (CloudKit public database
of our own container, "no Supabase, no server"), so the user's iCloud
account IS the identity and the storage. Without iCloud there is nothing to
post to and nobody to be. Making friends work with no iCloud means a
backend: accounts, a database, hosting, a privacy policy that names it, and
a new App Review posture (today we tell Apple there is no server). Nearly
every iPhone is signed in to iCloud already; the card appears on the beta
only because the beta build carried no iCloud entitlement, not because of
Melvin's phone. Done today instead: the card now says why and gives the four
steps to sign in, with Open Settings and Check again; and the beta build
keeps iCloud pinned to the real container (CloudKit Development
environment), so Friends can be tested side by side. Decide: keep no-server,
or fund a backend.

## Hide the score on a friends post? (Aziz asked, 2026-09-15; decide later)

Aziz: "should we make an option to hide the score by having a little eye
icon or some other intuitive way?" Claude's recommendation, given the same
day: **not as a per-post control.** A hidden score tells every friend what
the score was (Strava's hidden pace has this exact tell); it adds a
decision at the moment right after a sit when the screen should ask the
least; and the score is what makes an 808 post an 808 post, the way Strava
never lets you hide distance or time. If real posts show people choosing
Only you on low days, the right shape is one profile preference, "Show my
scores to friends", set once, default on, so it applies to every post and
carries no tell. Strava's own model: a privacy default, not a ritual. Note
for later: short sits score low by design (time is a ceiling), so if
anything drives a hide request it will be that, and the fix may be how the
feed card presents a short sit. Cannot be measured in PostHog: score bands
are biometric under our rule. Decide after the first weeks of real posts.

## A real user scored 1 (2026-09-16): the formula worked, and it reads as broken

**RESOLVED 2026-09-16 (Melvin's call): stillness is cubed instead of
floored.** Higher still matters more, nothing cuts off. That session
rescores to about 18. Engine 5.3.0, migration v8. Aziz to note.

The card: 10 min, stillness 75%, heart 74 → 79 (rose), breathing 6.2/min,
score 1. By the v5 formula that is exact: stillness below 0.80 floors at
zero (`spreadStillness` maps 0.80 to 0.98 onto 0 to 1, calibrated on eight
of Aziz's sits at 0.84 to 0.97); a heart that climbs and never returns
scores about 0.03; the 6.2/min read had no doorway that qualified (started
after 90 s without 0.85 clarity, or after 5 min), so breath added nothing.
Three zeros stacked. **Bug found beside it, fixed:** the "HR settled" tile
on the card and the results screen negated the sign, so a six-beat RISE
read "+6 HR settled". **Open for Aziz (engine calibration, not retuned by
feel):** the 0.80 stillness floor gives a 0.75 sit nothing at all; a floor
of 0.60 would have put this session at about 16 (with the same heart and
breath), and 0.75 is the territory real users with ordinary movement land
in. Decide with data from the captures, not this one card.

## Two start failures for a real user (Tulsa, 2026-09-15 22:26, PostHog be74c019)

iPhone 13 Pro on iOS 18.7.8, 1.0.1, finished onboarding, said they have a
Watch, declined the whole ladder (the first "settled on free"), pressed
Begin, two start failures, gone 90 minutes later with no session. The
per-person reasons are not in the sheet; the Failures tab moved by exactly
+2 `watchNotPaired` and +1 person overnight, so that is almost certainly
them: WCSession activated and reported no Apple Watch paired, twice. The
app cannot tell "no Watch" from "a Watch paired to another iPhone" or "a
watch that is not an Apple Watch"; the person said yes at the gate. Nothing
to fix from here without asking them. Same night, Lawrenceville (no Watch
at the gate) pressed Begin three times and hit `watchAppNotInstalled`, so
they DO have a paired Watch without 808 on it: the install screen after
that failure is doing its job or not; worth watching whether they return.

## Camera framing before Begin (Melvin, 2026-09-16): BUILT on `camera-vision`

Done the same day: mockup `mockups/camera-framing.html`; the Begin sheet
shows the front camera at 3:4, full width, with a white seated-figure
outline (`SeatedFigureOutline`) that turns teal with "You're in frame"
once a person is detected three times in four seconds; the live screen
keeps a thumbnail; one recorder owned by the coordinator serves the
preview and the session, and the preview's detected box becomes the
session ROI from t = 0 when you were framed before Begin. 366 tests.
Melvin to check on the phone: the outline goes teal within about 3 s of
sitting down, and the next capture's header reads `roi_fixed_at_sec=0.0`.

The camera preview moves to the setup sheet ("Ready when you are") so
people place themselves before the session starts; it gets bigger (the
width of the sheet); and a thin white outline of a seated person is laid
over it to fit yourself into, turning teal with "You're in frame" once the
torso is detected. Mockup first (`mockups/camera-framing.html`), then the
Swift on the camera branch behind the DEBUG collector toggle for now; the
live screen keeps a modest preview. Begin stays the only gold object.

## Otto understands the score, and remembers (Melvin, 2026-09-16): DONE

Otto's breakdown of a real sit did not make sense ("still for 0.76
seconds", percentages summed to 100, an invented opening rate), and a
regenerate gave a different answer. Done: the app now writes the score's
working in points and the model quotes it (CLAUDE.md, OTTO v1); a lab
tool on the Mac reads answers without a phone; chats persist per session
and reopen where they were left, with "Start a new chat" in the menu.
Read a dozen answers on the phone before the flag flips; the lab found
the voice plain and consistent, occasionally repetitive on long answers.

## Otto is drawn, and two screens got their air back (2026-09-18): DONE

Melvin: "can we generate Otto?" plus two UI notes. All three shipped.

- **Otto is drawn in Swift** (`Coherence/Otto/OttoArt.swift`), not generated
  and not commissioned. The path data is the approved mockup's, character
  for character, so what ships is what was reviewed. `OttoMark` is now the
  head badge and the locked and unavailable screens carry the sitting
  figure. Still open if the founders want more character than a glyph: the
  Fiverr brief in `mockups/otto-sloth.md` is written and still valid.
- **The Friends feed has padding** (Melvin: "too crowded/dense, look at
  Strava"). The post card was full bleed with the photo running wall to
  wall; it is now an inset rounded card, one 18pt inset for every child,
  the photo inset and rounded, 16pt between cards.
- **The profile lost Otto and the "Next: <award>" bar** (Melvin: "too
  crowded, i dont think otto should be in there"). Otto's door is the
  results screen, where the question has a subject in front of it.

## Otto is a sloth (Melvin, 2026-09-16): direction chosen

Melvin picked board 1 (Otto sitting cross-legged, eyes closed) for the big
placements and the head badge for the chat rows and header. Colour still
to confirm (teal recommended). Next: finish the two drawings (Figma pass
in-house or a line-art illustrator briefed with `mockups/otto-sloth.md`),
then replace `OttoMark` with the badge and put the sitting figure on the
locked and empty states.


Otto gets a mascot: a sloth. Melvin's favourite animal, slow and peaceful,
on brand. Needs: an illustration (the `OttoMark` placeholder "O" becomes
the sloth on the results row, the Profile row and the chat header), a
one-line voice note in the brief so Otto's tone matches (unhurried, warm,
never breathless), and the App Store copy for the paid tier once Otto
ships. Design first: a mockup with the sloth before any Swift. Not a
photo; drawn, in the app's line-art language like the 808 mark. IN FLIGHT
2026-09-16: concept page `mockups/otto-sloth.html` on branch `sloth`
(four artboards, three colour treatments, a voice line) plus
`mockups/otto-sloth.md` on how to finish it (in-house in Figma or
Illustrator, or a line-art illustrator briefed with the SVGs).

**Otto's facts, for the founders (2026-09-16):** it runs on Apple's own
on-device language model (the Foundation Models framework, part of Apple
Intelligence on iOS 26). Apple's model, not ours, not a third party. It
costs nothing per question and needs no key or server. Nothing leaves the
phone. Before `ottoInRelease` flips: one sentence in the privacy policy
(both copies) saying Otto answers on the device with Apple's model and
sends nothing anywhere, and the paid tier's store description names it.
Works on iPhone 15 Pro and newer with Apple Intelligence turned on.

## Decided 2026-09-15 (Melvin), being built now

- DONE 2026-09-16: **streak forgiveness.** One missed day is forgiven when
  the days either side were practised and no other rest day was taken in
  the previous seven; two missed days in a row still break it. A rest day
  bridges the run without counting as a practised day, so the number on
  Home is days actually sat. The awards read the same runs. Home's nudge on
  the day after a rest day: "Yesterday was your rest day. Sit today and
  your N-day streak carries on." `StreakCalculator.runs`, tested.
- **Camera capture #1 is in** (Melvin, 2026-09-16, session 14EDEB30, 6.6
  min, paced 6/min then natural): the camera read 74% of windows, median
  5.7/min, doorway 5.7/min opening at 90 s, clarity 0.89 median; against
  the wrist's own curve, median error 1.0/min with 74% of windows within
  1.5. Stillness read low (mean 0.75, spikes to 30x the floor: adjusting
  in frame) so the camera score was 15 where the wrist would score higher;
  that is the placement and motion-gate question the plan's sits 3 and 5
  exist for. Nineteen sits to go per `CAMERA_VISION_PLAN.md`. **They are
  not training data.** The camera engine is rules, not a trained model;
  the sits are ground truth to measure it against and to set its few
  constants from measurement (the plan's five questions: paced accuracy
  at 6, 8 and 12/min; counted natural breathing; distance 0.5, 1 and 2 m
  on lap, desk and bed, plus one dim-lamp sit; no-breathing controls;
  stillness against the wrist). Different distances and lighting are
  exactly what sits 3 and 5 ask for. Two people for some of them.

- DONE 2026-09-15: **the tour ends at "put your Watch on" with a Begin.**
  No practice sit, no demo results. Begin finishes onboarding and Home
  opens the setup sheet.
- DONE 2026-09-15: **THE PAYWALL IS AFTER THE FIRST MEDITATION.** First
  results fully unlocked with a one-line chip; leaving them opens the
  paywall; after that the free tier applies everywhere, including that
  session. Onboarding contains no paywall; sign in comes after the wall,
  before the tour. No-Watch users never see a paywall.
- BUILT 2026-09-15 (v1, on `mvp`, DEBUG only until `FeatureFlags.
  ottoInRelease`): **Otto, the premium on-device chat.** Mockup
  `mockups/otto.html`. Entry rows on the results screen (under the verdict)
  and the Profile tab; locked with the paywall route for free users; an
  honest card on phones without Apple Intelligence. Apple's on-device model
  (iOS 26), no network, fed our own score rules, the guide and the last ten
  sessions as a table; a medical question gets one decline line; "the data
  suggests" voice. Analytics `otto_opened` / `otto_asked`, name only.
  **Next:** Melvin reads its answers on his iPhone 17 Pro (Apple
  Intelligence on, paid or `PREVIEW_PAID=1`), then the founders decide the
  release: the paid tier's description, App Privacy answers and the review
  notes must name it. A cloud model remains a separate decision (sends
  session data off the phone).
- **Camera vision: Melvin records a sit today** on the camera-vision build.
- **All three instruments ship eventually: Watch, AirPods, camera.** The
  frame is "a social media for meditation": as many people as possible
  should be able to take part, with the meditation verified by one of the
  three. **Plus a manual log** ("I did one") for people with none of them,
  shown as logged rather than measured. Open: whether a logged sit counts
  toward streak and awards, and how the feed marks it. Needs a mockup.

## Decided, not started


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
- **Friends** (Search tab placeholder). DESIGNED 2026-09-14 (Aziz asked to
  start): `COMMUNITY.md` is the decision record, `mockups/friends.html` the
  six screens awaiting review before any Swift. Mutual friends, a feed of
  posted sessions (photo + score + minutes + streak + technique + caption,
  never a heart or breath number), one reaction, no comments, report and
  block, CloudKit public database with no server. Invite reward: free users
  get 10 sessions of full evidence per friend who accepts and sits once;
  paid users get an award and the Circle skin. Ships as 1.1, after 1.0.2;
  flips the UGC and Social age-rating answers to Yes.
  BUILT 2026-09-14: data layer, Friends tab, Post to friends, invite reward
  (features 1 to 4). WAITING on Aziz's review of `mockups/friends-v2.html`
  (separate username + photo, existing-user prompt, Save session with
  Friends / Only you). Then moderation (feature 5). Status in CLAUDE.md.
  UPDATE, same evening: v2 and moderation BUILT (Save session, Create your
  profile, existing-user prompt, Strava cards, content filter, photo
  screening, report emails), all behind the Friends switch. Remaining work is
  the 1.1 checklist (iCloud schema, entitlement, report script, legal and
  labels, TestFlight on two phones). Details in COMMUNITY.md.
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

- **Onboarding: no sign-in until the end, and progress resumes** (Aziz,
  2026-09-14, from the PostHog finding that everyone who skipped the paywall
  used the screen-one sign-in link). Built and verified on the simulator,
  ships in the next build. Details in CLAUDE.md.

- **Camera vision RESUMED** (2026-09-14, branch `camera-vision`, plan in
  `CAMERA_VISION_PLAN.md` there). `mvp` merged in with no conflicts (five
  tabs plus the DEBUG collector); 253 tests green. The probe's pipeline is
  now a pure engine module, `Shared/Engine/CameraSignal.swift`, shaped for
  `SignalEngine` (30/5 grid, no heart series), with an offline harness
  (`tools/camera_harness.swift`) and 20 tests. Score with no heart term:
  breath .20 / stillness .80 when a doorway opens, stillness alone when
  not; camera rows are tagged `camera-` and skipped by the Watch's score
  migration. Accuracy against the wrist on the two existing videos: about
  1.2/min on one, 2.2/min on the other (the unresolved fast-episode
  minutes). **Next, a human:** with a DEBUG build and Settings > Camera
  capture on, record six paced sits at 6, 8 and 12 breaths/min (two
  people, three minutes paced then five natural), pull with
  `tools/camera_pull.sh`, run the harness. Add nothing to the engine until
  those exist.

- **AirPods heart rate: FEASIBLE on iOS 26, spike built** (2026-09-14,
  branch `airpods`, `AIRPODS_PLAN.md` on that branch). Sources: WWDC25
  session 322 (`HKWorkoutSession` runs on iPhone from iOS 26 and HealthKit
  pulls heart rate from paired buds), Apple's AirPods Pro 3 support page
  (third-party workout apps receive it, no Watch needed), Apple DTS on the
  forums (heart-rate samples only, no HRV, so "no coherence" still stands).
  Path: iPhone-side `.mindAndBody` workout session, HR as system-written
  samples, head motion from `CMHeadphoneMotionManager` (~25 Hz). Breathing
  from head motion is a hypothesis (two papers, still head, ~2/min error),
  not a promise. Score split: the engine's existing 0.60/0.40 heart/still.
  Spike: DEBUG-only probe at Settings > AirPods (debug), writes HR and
  motion CSVs to Documents/AirPodsCaptures; Release binary carries none of
  it; committed Info.plist unchanged. Shipping it changes Info.plist, the
  Health strings and the policy's Watch-only wording (a review pass).
  **Next: a first capture on AirPods Pro 3 or Powerbeats Pro 2** (steps in
  the plan). Melvin does not own a pair (2026-09-15); the probe is on his
  beta anyway. Needs Aziz or a friend with the buds, or a pair bought for
  the purpose. Parked until then.

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

## Done (2026-09-16)

- **Save session rebuilt, 808's own camera, and a photo for every sit**
  (Aziz, 2026-09-15/16). Five asks in one thread, all shipped. Mockups
  `mockups/save-session-v3..v7.html`; v6 (the bare skin he picked over
  Strava's boxed one) and v7 (photos) are what was built.
  - The screen: one big gold score, **who can see this first** because it
    decides whether the description and selfie exist, bold unboxed title,
    bare rows on hairlines, private notes inline, Only you hides the
    sharing fields, Skip, and a button that is never dead ("Take your
    selfie" opens the camera, then reads "Save session").
  - `SelfieCamera`: black, one unfilled white ring, **no flip** (front
    only, always). Melvin then fixed its rotation, mirroring, focus and a
    tap-swallowing review image on 2026-09-16.
  - `SessionPhoto` in the synced store, optional when private and still
    required for Friends; the calendar draws the day's photo where the dot
    was, rows carry a thumbnail, results shows it above the reflection.
    Verified end to end on the simulator; the today ring was re-anchored to
    the date after it collided with a photo.
  - Also: `PendingSave` reopens the screen when the phone is picked up
    after a sit, "Silence / my own practice" is a technique, the keyboard
    has a Done key, and the invite reward went 10 sessions to 3 (cap 50 to
    15).
  - **Owed at 1.1:** `SessionPhoto` is a new record type, so the CloudKit
    Development → Production promotion covers it (RELEASE_CHECKLIST.md).
    The privacy policy already names the photo in both copies; the website
    needs its manual redeploy.
  - Still to do: **rebuild 808 Dev on Aziz's phone**, which he asked to be
    one rebuild once everything landed.

## Done (2026-09-15)

- **808 Beta crashed on open** after the friends merge: the friends store
  called `CKContainer.default()` on a build that carries no iCloud
  entitlement (the beta strips it on purpose). Crash log confirmed SIGTRAP
  in `CoherenceApp.init`. Fixed with one shared entitlement reader
  (`CloudEntitlement`) in front of every CKContainer; friends show the
  iCloud-unavailable card on the beta instead. Beta reinstalled.

- **Delete a session** (Melvin: "sometimes we create ones and immediately
  end them"). Results screen: the circled-ellipsis menu beside Share, then
  "Delete session". Home's recent rows and the Profile log: long-press a
  row. One confirmation everywhere, stating what it does not touch (the
  workout the Watch wrote into Health). Removes the session, its stats and
  its reflection; if it was posted to friends the post comes down too.
  Streak, awards and the sparkline recompute by themselves. Analytics:
  `session_deleted`, name only. `SessionStore.deleteSession`, tested.
- **Five-second countdown before a wrist-started session**, matching the
  phone's ("Get comfortable."), with Cancel. Numbers only; the Watch still
  plays no haptics. A start arriving from the phone cancels a countdown
  still ticking on the wrist.

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
