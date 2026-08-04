# 808 — Stage 2 Roadmap

Everything after the v1 launch push. `App_ROADMAP_v2.md` carries Phases 0–9 (the
build); this carries what comes next. Same rules: numbered phases, explicit
steps, and **a human verification checkpoint between every phase** — someone has
to see it work before the next one starts.

**Owners:** Melvin (product, design, marketing, business, legal) · Aziz (signal
engineering, on-device, the measurement stack) · LLM (a separate Claude instance
handed a self-contained brief).

**Reading order for anyone picking this up cold:** `CLAUDE.md` → `SCIENCE.md` →
this file. The architecture decisions marked "do not relitigate" in CLAUDE.md
still bind. Where a workstream collides with one, it's flagged **⚠ CONFLICT**
rather than quietly routed around.

---

## Phase 0 — Reconcile before anything ✅ DONE 2026-08-03

Two documents disagreed about whether the flagship feature existed:
`App_ROADMAP_v2.md` carried a "Phase 9 (PARKED — not started)" section written
the same day Aziz shipped 9a/9b/9c.

1. ✅ Deleted the duplicate PARKED section (67 lines). One Phase 9 record now,
   the real one: **camera PPG SHIPS in v1.**
2. ✅ Folded its two surviving contributions into both `App_ROADMAP_v2.md` and
   `CLAUDE.md`:
   - **Camera PPG yields true beat-to-beat intervals** — HRV is reachable on
     this path in a way the Watch workout stream never can be. A different and
     in one respect better instrument, not a consolation prize. It's also the
     only RR source we have short of an external BLE strap, which links it to
     Phase 6.
   - **Skin tone + lighting is an untested open question.** PPG is optical;
     melanin absorbs green/red light and published pulse-oximetry work shows
     worse performance on darker skin. Validated on two people so far.
     Correctness *and* equity risk. **Blocks external TestFlight (Phase 4).**
3. ✅ The scoring caution became Phase 1 below.

> **Checkpoint 0 — met.** `grep "^## Phase 9" App_ROADMAP_v2.md` returns one
> section, headed *IN PROGRESS*, not *PARKED*.

---

## Phase 1 — The scoring question (2–3 weeks, Aziz builds / Melvin decides)

**The problem is real.** The Watch path and the camera path measure different
things with different instruments. A single cross-user "practice score" silently
compares a wrist accelerometer to a phone camera. Melvin is right that it stops
being meaningful.

**The proposed fix cannot ship as worded.** "Probability you entered theta state
to edit your subconscious" fails on four counts, each independently fatal:

- `SCIENCE.md`'s citation-integrity note forbids exactly this upgrade. Refs 1–3
  show *meditation raises theta*. **None** show our signals *measure* theta.
- A probability is a **stronger** claim than the score it replaces. It asserts a
  model calibrated against ground truth. We have zero EEG data. Any percentage
  would be invented, and inventing one is the thing this codebase has refused to
  do everywhere else (`nil` over invention, the weak-signal fallback, the
  refusal to upgrade correlates).
- "Edit your subconscious" states a mechanism as fact. That's PURPOSE.md's
  thesis, not a finding. Attaching it to a *number* converts a belief into a
  claimed measurement.
- App Review treats a quantified brain-state readout differently from "here's
  how still you were." It invites a health-claim conversation we'd lose.

### The four honest options

| Option | What it gives | What it costs | Verdict |
|---|---|---|---|
| **A. Within-user relative** — score this session against the user's own baseline ("your 3rd calmest of 30") | Kills the comparability problem completely. Hardware-neutral by construction. Needs no new science. | New users have no baseline — needs a cold-start story (first ~5 sessions show raw signals only). | **Recommended, core** |
| **B. Hardware-labelled absolute** — keep a number, stamp it "measured on Apple Watch" / "measured by camera" | Cheap. Honest about provenance. | Doesn't actually make the numbers comparable; just discloses that they aren't. | **Recommended, supporting** |
| **C. Qualitative verdict** — lean on `VerdictEngine`, lead with language not digits | Already shipped and working. Language degrades gracefully across instruments where a number can't. Every claim is backed by a number on the same screen. | Harder to trend over time. Some users want a digit. | **Recommended, primary display** |
| **D. Real EEG validation** — earn the right to say theta | Would make the claim Melvin actually wants *true* | 20–30 subjects, simultaneous consumer EEG + our signals, a defensible protocol, IRB if published, months and real money. Needs hardware (see Phase 5). | **Parked — revisit only with Phase 5** |

### Recommendation

**Ship C as the headline, A as the trend, B as the footnote. Not D, not yet.**

Concretely: the evidence screen leads with the spoken verdict (already there),
supported by a *relative* standing ("calmer than 8 of your last 10"), with the
instrument named quietly. The word "theta" appears only where SCIENCE.md already
allows it — describing the state the body's calm rides on, never as something we
detected.

**This preserves what Melvin actually wants.** The user gets "did I get there?"
answered in plain language. What they don't get is a fabricated percentage.

### Steps

1. **Aziz** — extend `VerdictEngine.Inputs` with the user's rolling baseline
   (mean + SD of last N `overallScore`). Pure Foundation, no SwiftData. (2 days)
2. **Aziz** — add relative phrasing to the phrase bank: "calmer than 8 of your
   last 10", "your stillest session yet". Threshold-driven, same as today. Every
   phrase must be true from the numbers on screen. (2 days)
3. **Aziz** — `MeditationStats` gains a `measurementSource` string
   (`"watch"` / `"camera"`), defaulted, CloudKit-safe. Display it as a `MetaChip`.
   (1 day)
4. **Aziz** — cold-start: under 5 sessions, suppress relative claims entirely
   rather than comparing against noise. (0.5 day)
5. **Melvin** — copy pass on the whole phrase bank. Nothing may imply we
   measured a brain state. (1 day)
6. **Both** — decide whether the numeric score stays visible at all, or becomes
   a detail behind the verdict. *Needs a decision from you two.*

> **Checkpoint 1:** Run five real sessions across both paths. Melvin reads every
> verdict aloud and confirms each sentence is literally true given the numbers
> beside it. No sentence claims a brain state.

---

## Phase 2 — Guided structure for unguided sessions (1–2 weeks, Aziz + Melvin)

Today: Guided = a 25-minute narrated track; everything else = silence or tone
with no structure. The gap is a user who wants guidance without a voice actor.

1. **Melvin** — write a **session script format**: timed cues as text, not audio.
   e.g. `0:00 settle` → `1:00 lengthen the exhale` → `3:00 picture it done` →
   `18:00 return`. Author 3 scripts: Settle (5 min), Resonance (10 min),
   Manifestation (15 min, the on-thesis one). (3 days)
2. **Aziz** — `Shared/Session/GuidedScript.swift`: pure Foundation, a Codable
   list of `(offsetSec, text)`. Trivially testable. (1 day)
3. **Aziz** — the mid-session screen shows the current cue under the breathing
   orb, crossfading on change. `SessionActiveView` already owns the session
   clock and re-anchors to the Watch's started-ack — the cue timeline hangs off
   that same clock, so it can't drift. (2 days)
4. **Aziz** — optional Watch haptic on cue change, gated on `hapticsEnabled`.
   (1 day)
5. **Melvin** — the Begin sheet gains a "Structured" practice card alongside
   Guided. (1 day)

> **Checkpoint 2:** Melvin runs a 10-minute Structured session end to end and
> confirms every cue arrives at the right moment against a stopwatch, and that
> the last cue lands before the Watch ends the session.

---

## Phase 3 — Retention: why does anyone open this tomorrow? (3–4 weeks)

This is product design, not a feature list. Answer the loop first, build second.

### The loop as it stands

| Stage | What exists | Honest assessment |
|---|---|---|
| **Trigger** | Daily reminder notification (`NotificationScheduler`) | Weak. A generic time-based ping. Nothing about *this* user. |
| **Action** | Begin → Watch session | Good. Two taps. |
| **Reward** | Verdict, score ring, curves, streak, share card | **The strongest part of the product.** Nothing else in meditation gives biometric proof. |
| **Investment** | Streak, reflection notes, history | Real but thin. Notes are the sleeper asset — they're the only user-authored content. |

**The gap is the trigger.** Reward and investment are strong; nothing earns the
open. That's where the work goes — not into a feed.

### Where the dopamine actually comes from — and the trap

⚠ **CONFLICT — read before designing anything social.** CLAUDE.md states the
product stance in the first paragraph: **"evidence, not a training score,"** and
the mid-session screen deliberately shows no live biometrics because we refuse
to give users a number to chase. **A leaderboard is that number, socialised.**
It would directly reverse a documented decision.

There's a deeper version of the problem: **meditation is the one activity where
trying to win makes you worse at it.** Performance anxiety raises arousal, which
raises HR and reduces stillness — the exact signals we measure. A competitive
layer would measurably degrade the thing it's ranking, and users would feel it.

**So the social layer must be witness, not competition.**

- **Ship:** a private practice circle (5–10 people you chose). You see *that*
  they practised and what they wrote — never who scored higher.
- **Ship:** reactions to reflections. The notes are already the most human thing
  in the app, and the note UI was just rebuilt to read like a post.
- **Ship:** shared streaks / "3 of your circle practised today" — presence, not
  ranking.
- **Don't ship:** global leaderboards, score comparison, public profiles.

### Steps

1. **Melvin** — write the retention thesis as a one-pager before any code. What
   is the *emotional* reason to open 808 on day 14? Candidate, and it's the
   on-thesis one: **identity reinforcement.** The app's entire premise is that
   you become the person who does this. The streak isn't a game mechanic, it's
   evidence of identity change. That framing is honest, differentiated, and
   already what the product believes. (2 days, **research/decision — blocks the rest**)
2. **Aziz** — make the trigger earn its open: notification copy drawn from the
   user's own data ("you've settled 4 days running"), and suppress the ping
   entirely on days they've already practised. Requires nothing new server-side.
   (3 days)
3. **Melvin + Aziz** — design the practice circle. **This is the first feature
   requiring a backend.** Everything today is device-local + per-user private
   CloudKit. Sharing between users needs either a CloudKit **shared** database or
   a real server. *Needs a decision from you two — it is the largest
   architectural change in this roadmap.* (1 week research)
4. **Aziz** — prototype circles on CloudKit shared DB, 2 people, one shared
   record type. Prove the sync model before building UI. (1 week)
5. **Melvin** — decide what a circle member can see. Default: day practised,
   duration, reflection note if shared. **Never the score.** (2 days)

> **Checkpoint 3:** Melvin and Aziz are in a circle across two devices. Each sees
> the other's practice appear within a minute. Neither can see the other's score
> anywhere in the UI.

---

## Phase 4 — TestFlight (2–3 weeks, Melvin owns)

### Gates before a single external tester

- [ ] Paired-device end-to-end pass on **both** founders' hardware. CLAUDE.md
      lists Aziz's Watch install as still pending — that blocks everything here.
- [ ] Camera PPG tested across **more than two skin tones** (Phase 0's open
      question). Shipping an optical sensor validated on two people is not
      defensible.
- [ ] Crash-free across a full session on both paths.
- [ ] Account deletion works (already built — verify it still does).
- [ ] Privacy policy covers the camera (9d, **not yet done**).
- [ ] `SCIENCE.md` cites the PPG work (9d, **not yet done**).
- [ ] Every user-visible string says 808, never Coherence.

### Steps

1. **Melvin** — internal TestFlight, just the two of you, one week of daily real
   use. Not a demo — actually meditate with it. (1 week)
2. **Melvin** — recruit from the existing survey/waitlist on the site. Target
   **20–30** external testers, not hundreds; you need conversations, not
   telemetry. (3 days)
3. **Melvin** — write the tester brief: what to try, what you're unsure about,
   how to report. Ask three questions only — *Did you believe the evidence? Did
   you come back? What made you stop?* (1 day)
4. **Melvin** — in-app feedback route (a mail link is fine; don't build a
   system). (1 day)
5. **Both** — two rounds, ~10 days each, a fix window between. (3 weeks)
6. **Melvin** — App Store submission only when round two produces no new
   crash-class bugs.

> **Checkpoint 4:** 10+ external testers have completed 3+ sessions each, and you
> can name the single most common complaint. If you can't, you don't have enough
> testers yet.

---

## Phase 5 — Instagram outreach (1 week, LLM instance + Melvin)

### ⚠ The requested feature cannot be built compliantly. Read this first.

**Auto-DMing new followers is not available through Meta's official API, and
"following" is not an event third-party tools can trigger on.** Follow-based
outreach was deprecated; the follow trigger exists only in a restricted private
beta. Meta's rules are: message only users who **initiated contact** (comment,
story reply, or DM), within a **24-hour window** that their message opens, at
most **200 messages/hour**, through a tool in Meta's Partner Directory.

Unsolicited promotional DMs to people who merely followed you are exactly the
pattern spam-detection targets. Any tool advertising it is using unofficial
automation and puts the account at risk of restriction or ban — which for a
pre-launch app means losing the audience you're building.

**Sources:** [Meta's allowed vs banned DM automation](https://creatorflow.so/blog/instagram-dm-compliance-meta-rules/) ·
[Instagram DM automation policy 2026](https://appbrewers.com/blog/instagram-dm-automation-policy-2026) ·
[Automation rules and rate limits](https://www.spurnow.com/en/blogs/instagram-dm-automation-rules)

### What to do instead — this is the standard growth pattern, and it works better

**Comment-to-DM.** A post says "comment BETA and I'll send you the link." The
comment is user-initiated, which legitimately opens the 24-hour window, and an
automated DM with the TestFlight link is fully compliant. It converts better than
cold DMs because the person asked, and it doubles as engagement on the post.

Also legitimate: story-reply triggers, Instagram's native welcome message /
instant replies for business accounts, and the link in bio.

### Steps

1. **Melvin** — convert the account to a Business or Creator account. Required
   for any messaging automation. (30 min)
2. **LLM instance** — hand it this brief:
   > Set up compliant Instagram comment-to-DM automation for 808, a meditation
   > app. Constraints: use only a tool from Meta's official Partner Directory;
   > message only users who initiated contact; respect the 24-hour window and
   > the 200 msg/hour limit. Do NOT implement or recommend follow-triggered
   > DMs — Meta does not expose that trigger and it risks the account. Deliver:
   > a tool comparison with pricing, the setup steps, the keyword→message flows
   > for a TestFlight campaign, and the exact DM copy. Flag anything that would
   > require a workaround, and stop rather than working around it.
3. **Melvin** — write the campaign posts driving the comment keyword. The promo
   squares in `~/Desktop/808-promo/` are the creative. (2 days)
4. **Melvin** — measure: comments → DMs → TestFlight installs. If it doesn't
   convert, the copy is wrong, not the mechanism.

> **Checkpoint 5:** A test comment from a second account triggers the DM within
> a minute, and the account has no policy warnings after a week of live use.

---

## Phase 6 — Hardware (research now, decide post-launch, Melvin + LLM)

CLAUDE.md already parks this: **an external BLE HRV sensor (Polar H10-style, RR
over CoreBluetooth) is the only route to true heart coherence**, ruled out for v1
but never rejected on merit. Stage 2 is where it gets a real answer.

### The three routes

| Route | Cost | Time | Risk |
|---|---|---|---|
| **Support existing hardware** — read a Polar H10 over CoreBluetooth. No hardware business. | Weeks of dev | Fast | Near zero. Reversible. |
| **White-label** — rebrand an existing device | $10–50k MOQ | 6–12 months | Inventory, support, returns |
| **Build our own** | $100k+ | 18+ months | Regulatory, manufacturing, capital |

### What EEG would unlock — and why it's not just a revenue idea

**An EEG headband is the only thing that makes the Phase 1 scoring claim
defensible.** It is the ground truth. If 808 could correlate its motion/HR
signals against real EEG theta on even 20 subjects, "likelihood you reached the
state" stops being invented and becomes measured. Hardware and the scoring
question are the same question.

Note the cost honestly: consumer EEG (Muse-class) is itself noisy, and validating
against it is weaker than clinical EEG. This buys credibility, not certainty.

### Regulatory line — get this right early

**Wellness** ("relaxation", "mindfulness") stays outside FDA device regulation.
**Medical** claims ("treats anxiety", "diagnoses") do not. 808's current copy is
carefully on the wellness side and `SCIENCE.md` keeps it there. Selling hardware
raises scrutiny — the same sentence is read more harshly attached to a device.
**Any hardware decision needs a lawyer before a manufacturer.**

### Steps

1. **LLM instance** — research brief: BLE HRV market (Polar, Movesense,
   Frontier X), consumer EEG (Muse, Neurosity, Emotiv), COGS, MOQs, white-label
   partners, and FDA wellness-vs-device precedent for meditation hardware.
   *Research — answers: what would we sell, at what margin, and what does it
   legally let us claim?* (1 week)
2. **Aziz** — spike CoreBluetooth RR ingestion from a borrowed Polar H10. This
   is the cheap experiment that de-risks everything: it proves the "Pro tier"
   path with no inventory. *Buy one strap before deciding anything.* (1 week)
3. **Melvin** — decide build vs. partner vs. support-only **after** launch data
   exists. Do not commit capital before knowing whether anyone retains.
4. **Both** — if EEG proceeds, it starts as a *validation study*, not a product.

> **Checkpoint 6:** Aziz reads live RR intervals from a real chest strap into the
> existing analyzer, and you can see whether true coherence differs from what the
> camera reports. That single experiment decides the tier.

---

## Running list — features & upgrades

Append here; don't create new files. Move items up as they're scheduled.

### Next
- Relative scoring + verdict language (Phase 1)
- Structured non-narrated sessions (Phase 2)
- Notification copy from the user's own data (Phase 3)
- 9d: privacy-policy camera wording + PPG citations in SCIENCE.md ⚠ *blocks TestFlight*
- Skin-tone/lighting validation for camera PPG ⚠ *blocks TestFlight*
- True phone-only sessions (no-Watch timer path) — 9c left this undone

### Parked, with reason
- **Seated belly mode** — CLAUDE.md: postural sway masquerades as breathing when
  seated. Needs its own gating, not a toggle.
- **Meta App ID → direct Instagram Stories handoff** — code is finished and
  auto-upgrades the moment the ID is set. Melvin blocked on Meta registration.
- **The geometry duplication** — logo params live in both `LogoMark.swift` and
  `tools/logo_lab.swift`. Hand-synced repeatedly; will drift.
- **EEG validation study** — only with Phase 6 hardware.
- **Leaderboards** — deliberately refused, see Phase 3.

---

## Decisions blocking work

1. **Does a numeric score stay visible, or does the verdict lead?** (Phase 1)
2. **CloudKit shared database, or a real backend?** The social layer forces this,
   and it's the biggest architectural change here. (Phase 3)
3. **What can a circle member see?** (Phase 3)
4. **Hardware: support-only, white-label, or build?** — after launch data. (Phase 6)

---

## Start here

**Phase 0, then Phase 1 step 1.**

Reconciling the duplicate Phase 9 takes an hour and stops two documents
disagreeing about whether your flagship feature exists. Then settle the scoring
question — because it decides what the evidence screen says, which decides what
the App Store listing can claim, which decides what the TestFlight testers are
even evaluating. Everything downstream inherits that answer.

The single highest-leverage thing: **get the honest version of "did I get there?"
in front of 20 real testers.** Not the biggest feature — the one that tells you
whether the core promise lands on anyone who isn't you.
