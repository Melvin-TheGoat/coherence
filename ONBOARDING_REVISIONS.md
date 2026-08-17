# Onboarding revisions, round 2

Melvin's pass through the flow on the simulator, 2026-08-17. **Nothing is built
yet.** This is the record and the plan.

**Why the whole thing needs revisiting, not just these 26 items.** The flow was
written when the mission was one promise: *we measure what happened*. The
mission is now three, and two of them have no representation in the onboarding
at all:

| Mission | Onboarding says it? |
|---|---|
| **Measurable** — biofeedback and a rating tell you what worked | Yes, this is the whole flow |
| **Habitual** — streaks, awards, history make consistency visible | Barely. Streaks appear once |
| **Universal / social** — sharing your proof, community, challenges | Not once |

Several items below (11, 15, 25) are really this gap surfacing. Awards shipped
yesterday and the onboarding has never heard of them.

---

## The flow as it stands: 34 screens

`Step` in `Coherence/Onboarding/OnboardingView.swift`, indices are the
`ONBOARDING_STEP` values.

| # | Screen | Who sees it |
|---|---|---|
| 0 | relief | everyone |
| 1 | breath | everyone |
| 2 | **baseline** | everyone — *decides the persona* |
| 3 | **motivation** | everyone |
| 4 | **stress** | everyone |
| 5 | **aloneWithThoughts** | newcomer, restarter |
| 6 | **doingNothing** | newcomer, restarter |
| 7 | **restarts** | restarter |
| 8 | **intendedFor** | newcomer |
| 9 | **causes** | restarter |
| 10 | **blindSpot** | regular |
| 11 | **watchGate** | everyone |
| 12 | waitlist | no-Watch only |
| 13 | **anchor** | everyone |
| 14 | **you** | everyone |
| 15 | **referral** | everyone |
| 16 | calculating | everyone |
| 17 | result | everyone |
| 18 | cost | everyone |
| 19 | proofBody | everyone |
| 20 | sampleStart | everyone |
| 21 | sampleBuild | everyone |
| 22 | proofYourWay | everyone |
| 23 | wall | everyone |
| 24 | profile | everyone |
| 25 | commitment | everyone |
| 26 | projection | everyone |
| 27 | how | everyone |
| 28 | permission | everyone |
| 29 | week | everyone |
| 30 | rating | everyone |
| 31 | health | everyone |
| 32 | paywall | everyone except no-Watch |
| 33 | signIn | everyone |

**Bold** = interview question, branched by persona. The other 21 screens are the
same for everybody.

### The three user stories

Set by screen 2 alone (`OnboardingAnswers.persona`).

| Persona | Chosen by | Extra questions | Skips |
|---|---|---|---|
| **Newcomer** | "Never. This would be the start" | intendedFor | restarts, causes, blindSpot |
| **Restarter** | "I've tried, it never stuck", "A few times a month" | restarts, causes | intendedFor, blindSpot |
| **Regular** | "Most weeks", "Almost every day" | blindSpot | intendedFor, restarts, causes, aloneWithThoughts, doingNothing |

Question counts: newcomer 11, restarter 12, regular 9.

**Every persona sees all 21 non-interview screens.** That is where the
personalisation gap lives: the questions branch, the payoff mostly does not.

---

## The 26 revisions

### Confirmed good, no change
**12** cost · **19** promise · **20** lands · **22** first week · **23** sounds
like it'd work · **24** health data · **26** sign in with Apple

### A. Copy and options (small, mechanical)

| # | Screen | Change |
|---|---|---|
| 2 | baseline (2) | Options become "a few times a month", "a few times a week", "daily" |
| 3 | motivation (3) | Add **Manifest goals**, **Change identity**, **Other** |
| 5 | aloneWithThoughts (5) | Retitle "Can you be alone with your thoughts?", framed *compared to a few years ago* |
| 6 | doingNothing (6) | Subtext "standing in a line", not "queue". We are not British |
| 7 | restarts (7) | Last option becomes "It sticks. I'm here for the stats and community" |
| 8 | causes (9) | Add **No one kept me accountable** |
| 9 | anchor (13) | Add **Before my sport, activity, or hobby** |
| 10 | you (14) | Add age brackets **Under 18**, **18-21**, **21-25** |
| 16 | proofYourWay (22) | Make explicit that "YouTube" means *a guided meditation or frequency track*, not any video and not your music |

### B. Motion

**1 · breath (1).** Drop the shrink animation. The line holds one size and
position, waits **2 seconds**, then the orb and "Breathe in" appear.

### C. Structure and order

**17 · Move "You'd be in reasonable company" (the celebrity wall, 23) much
earlier**, before the theta screen.

**13 · Delete the theta screen** and replace it. Testers said theta is
confusing because they do not know what it is. New content: meditation moves
you out of fight-or-flight (sympathetic) into rest-and-digest
(parasympathetic). **Lead with the celebrity wall**, then this.

> Note for whoever writes it: parasympathetic framing is defensible and
> already cited in `SCIENCE.md` (Zaccaro 2018 on slow breathing). Keep it to
> what slow breathing and settling do. Do not claim 808 measures nervous-system
> state; it measures motion and averaged heart rate.

**8 · The "It sticks" contradiction.** Melvin picked "It sticks" on screen 7 and
was still asked "What made you stop meditating?" on screen 9. **This is a real
bug, not intentional.** The persona is decided by screen 2 alone, so answering
"I've tried, it never stuck" there makes you a restarter permanently, and
`restarts == .sticks` is an escape hatch that nothing reads. `CLAUDE.md`
already lists `RestartCount.sticks` as redundant. Fix: `.causes` is skipped when
`restarts == .sticks`. Revision 7 makes this urgent, because the new wording
invites the answer.

### D. Personalisation (the real work)

**11 · result (17), "here's what you just told us".** Reflect back *every* pain
point they named, each paired with the part of 808 that answers it. Mapping to
build:

| They said | We answer with | Mission pillar |
|---|---|---|
| Lower stress | The measured settle: heart down, body still | Measurable |
| Sharper focus | Same, plus session history over weeks | Measurable |
| Better sleep | Evening anchor + reminder | Habitual |
| More discipline | Streaks, awards, the calendar | Habitual |
| Manifest goals *(new)* | The guide's manifestation method | Measurable |
| Change identity *(new)* | Same, plus the long arc of history | Measurable |
| **No one kept me accountable** *(new)* | Daily reminder, streak, **community challenges and group meditations on [@808meditate](https://instagram.com/808meditate)** | Habitual + Universal |
| Forgot / no time | Anchor, reminder, two minutes still counts | Habitual |
| Too many choices | Bring your own audio, or the guide | Universal |
| Couldn't tell if it worked | The score and the curves | Measurable |
| Got boring | Awards, streak, technique variety | Habitual |
| Felt wrong / doing it wrong | The guide, and the verdict in words | Measurable |

**15 · sampleBuild (21), "where you can build to".** After "still body", append
their own motivations as outcomes. "Still body. Lowered stress, sharper focus."
One clause per motivation selected, all of them if they picked all.

**18 · profile (24)** and **21 · how (27).** Already decent, personalise further
where it is cheap.

### E. Charts

**14 · sampleStart (20)** and **15 · sampleBuild (21).** Redraw so they match
the real results screen: same colour grammar (gold = achieved, teal = the
body's signals), same fixed magnification, same smoothing. Right now they are
their own thing and they teach a reading the app then contradicts.

### F. Paywall, for launch (25)

Not for the beta. Wanted at go-live, which is close (inc approved, D-U-N-S
applied for).

**Prices with anchors:** $4.99 not $5, with a struck-through $7.99 beside it.
Yearly $59.99 struck. Lifetime anchored near $199.

> ⚠️ **Legal check before this ships.** A struck-through "was" price that was
> never actually charged is a fake reference price. The FTC and several state
> laws treat that as deceptive, and Apple's own guidelines require offer terms
> to be accurate. If 808 has never sold at $7.99, do not print $7.99 as a former
> price. Safe alternatives that keep the anchor: "$7.99 after launch" if that is
> genuinely the plan, or anchor against the yearly-vs-monthly maths, which is
> real. Worth one question to the attorney already holding the four documents.

**A pass control**, then a downsell ladder. Melvin's proposal plus what the
research supports:

1. **Pass / X** on the paywall.
2. **7-day free trial, cancel anytime.** Correct first rung: onboarding placement
   accounts for roughly half of all trial starts because the trial removes the
   risk rather than arguing about price.
3. **First month half off.** Standard second rung: shrink the commitment before
   shrinking the price.
4. **Final rung, Melvin asked for a better idea than "first year half off".**
   Two candidates, both better supported:
   - **Reframe, don't discount.** Restate the annual as its weekly cost ("about
     $1.15 a week"). The literature puts the reframe *before* the discount
     because it converts without giving margin away.
   - **Weekly plan with a 3-day trial**, which one benchmark set found returns
     about 1.5× the one-year LTV of any other configuration.

   Recommendation: rung 4 = the weekly reframe, and keep a real discount as a
   fifth rung only if rung 4 measurably fails. Do not label anything "BEST
   VALUE" unless it is: that label on the deepest discount trains people to wait
   for the ladder.

Sources: [RevenueCat paywall guide](https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps),
[Adapty 2026 paywalls](https://adapty.io/blog/high-performing-paywall-2026/),
[Apphud paywall design](https://apphud.com/blog/design-high-converting-subscription-app-paywalls),
[Stormy AI on paywall psychology](https://stormy.ai/blog/app-paywall-psychology-subscription-revenue-triggers).

---

## Build order

Each stage builds, tests and installs to the simulator for review before the
next begins.

**Stage 1 · Copy and options** (A, items 2/3/5/6/7/8/9/10/16)
Almost all of it is `Shared/Onboarding/OnboardingModel.swift` enum cases plus
their screen titles. New enum cases are additive, so nothing stored breaks.
Touches: `OnboardingModel.swift`, `OnboardingInterview.swift`.

**Stage 2 · The "It sticks" branch fix** (item 8)
`asks(.causes)` gains `&& restarts != .sticks`. Extend
`OnboardingBranchTests` so the permutation walk covers it. Small and
load-bearing; worth being its own commit.

**Stage 3 · Breath screen timing** (item 1)
One animation removed, one 2-second delay added. `OnboardingView.swift`.

**Stage 4 · Reorder, and replace theta** (items 13, 17)
Move the wall before the science screen, rewrite the science screen around
sympathetic → parasympathetic. Copy needs a review pass before it is built.

**Stage 5 · Charts** (item 14)
Rebuild the two sample charts on the results screen's rules.

**Stage 6 · Personalisation** (items 11, 15, 18, 21)
The largest piece. A pure, testable mapping from answers to claims, in
`Shared/Onboarding/`, so every branch is checkable without a simulator. This is
also where habitual and universal finally enter the flow.

**Stage 7 · Paywall** (item 25) — **launch, not beta**
Blocked on the pricing-legality question and on StoreKit products existing.
Build the ladder as a flow that reads its rungs from config, so prices and
copy move without a new build.

---

## Open questions for Melvin

1. **Baseline options (item 2).** "A few times a month / a few times a week /
   daily" drops the two answers that currently create the newcomer and restarter
   personas. Do "Never" and "I've tried, it never stuck" stay as options above
   these three? If they go, all three user stories collapse into one and the
   branching has nothing to branch on.
2. **"Other" on motivation (item 3).** Free text, or just an untyped option? Free
   text means a card could later show something we did not write.
3. **Age brackets (item 10).** Current top bracket is 25-34, and yours overlap at
   21. Suggest Under 18 / 18-20 / 21-24 / 25-34 / 35-44 / 45+.
4. **Under 18.** Collecting an under-18 bracket has App Review and privacy
   consequences (age rating, and the kids-category rules). Worth confirming we
   want to know rather than simply not ask.
5. **Community (item 11).** Naming @808meditate in onboarding promises something
   that lives outside the app today. Fine if the copy says where it is. Flagging
   so it is a decision.
