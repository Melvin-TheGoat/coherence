# The How-To Guide — content spec

Melvin's brain dump, 2026-08-09, structured. **Not built yet.** This captures the
methods, the ordering, the honesty tiering, and the logging design.

**Why this isn't the thing we cut.** "The Method" was *prescriptive* — timed cues
telling you what to do mid-session, which fought the MVP promise of "meditate
however you like". This is *reference*: a roadmap you read beforehand, then you
practise however you want and we measure it. It also needs no audio, which is why
it's the cheapest content we can ship.

**The friction it solves:** every beginner asks "ok, what do I actually do?" and
808 currently has no answer. That is the single most common question Melvin gets
when he talks about meditation.

---

## The roadmap

Presented as a path you work through, not a menu. Each method gets its own page.

### 1. Blue Sky — *beginner, start here*

You're lying on a field of grass, looking up at the sky. Thoughts will come —
that's not a failure, that's the point. Every thought that arrives is a cloud.
Some are pretty and light. Some are dark and stormy. Either way they're just
clouds, and they're far away, and you're down here on the field.

Sometimes you'll notice you've been pulled up into the clouds, caught in the
storm. When you notice, come back to the field. Calmly, no judgement, no "I'm
doing this wrong."

**The returning IS the practice.** That's the rep. You're not training to have no
thoughts — you're training the return.

*What it teaches:* you are not your thoughts, you are the observer of them. Which
is what lets you step back from the alarm bells, whatever they are.

### 2. Body Scan — *beginner*

Start at the top of your head and walk your attention down: skull, eyebrows,
eyes, nose, tongue, cheeks, jaw. Neck, shoulders, biceps, triceps, elbows,
forearms, hands. Chest, abdomen, lower abdomen. Hips, buttocks, thighs, knees,
calves, ankles, feet. Every toe, even the little one.

Just noticing a part is often enough to release it.

*What it's for:* relaxation, sleep, stress. **And it's the precursor to
manifestation** — a relaxed body is a more suggestible state, so this is what you
do first before attempting method 3.

### 3. Manifestation — *advanced*

> Manifestation, defined: **embedding intentions into your subconscious.**
> — Doty JR (2024), *Mind Magic: The Neuroscience of Manifestation*, Avery

Begin with the body scan (method 2) to get relaxed and suggestible. Bring
intentions you prepared **ahead of time** — this doesn't work improvised. Then
wrap those intentions in an immense amount of love, gratitude and joy.

Two sub-methods:

**3a. Inner conversation** *(Neville Goddard)* — Imagine you're telling someone
who genuinely wants you to win: a close friend, family member, anyone who'd be
truly happy for you. Tell them, in the present tense, that you've achieved it.
Hear them react. Hear them cry, freak out, say they're proud of you. Feel what
you'd feel. Not what you'll feel someday — what you feel now, because it's done.

**3b. Mental movie** — Imagine an ordinary day in the life where it's already
accomplished. You wake up. Everything you set out to do is done. You look around
and feel relaxed, grateful, in love with your life. Play it like a film.

Keep going with one of these until you've genuinely felt it. Then **let it go**
and return to the present. Completely forget about it.

### 4. Blessing the Energy Centers — *intermediate*

From Joe Dispenza, *Becoming Supernatural*.

Place your attention in the first energy center. Open your awareness to the space
around it. Once you can sense that space, bless the center. Then connect to an
elevated emotion — love, gratitude, joy. Move through all seven centers in the
body.

The eighth center sits about 16 inches above your head. Bless that one with
gratitude, because **gratitude is the ultimate state of receivership.**

### 5. Counting Down From Ten — *beginner*

Count down from ten. With each number, imagine yourself sinking deeper. And
deeper. A simple way into a relaxed state, and a good on-ramp before any of the
others.

---

## ⚠️ Honesty tiering — read before writing final copy

Same two-tier rule as the old Method guide: **what's been measured** stays apart
from **where the technique comes from.** Several claims in the source dump don't
survive as stated:

| Claim as dumped | Problem | Ship as |
|---|---|---|
| "oxytocin increases neuroplasticity so we can edit our subconscious identity better" | A chain of inference presented as established mechanism. Oxytocin has documented plasticity effects in specific contexts; "therefore you can edit your subconscious identity" is not a finding. | Cut the mechanism. Say emotion aids consolidation and cite McGaugh 2004, which genuinely supports it. |
| "it's proven that counting down from ten relaxes you" | This is a hypnotic induction. There's clinical hypnosis literature, but "proven" overstates it. | "A standard induction — it works for a lot of people." Technique, not evidence. |
| Chakras / energy centers | Not a scientific framework. | Label as practice tradition, Dispenza attribution, exactly like the solfeggio tones. |
| "Manifestation = embedding intentions into your subconscious" | Doty's framing from a **trade book**, not a paper. | Quote it and attribute it. Never present as a research finding. |
| Body scan → "closer to theta" | We can't measure theta and SCIENCE.md forbids implying we do. | Body scan is a core component of the 8-week programme where gray-matter change was recorded (Hölzel 2011). That's real and enough. |

**The methods themselves need no defending.** Describe them faithfully as
practices. It's only the *why it works* sentences that need discipline.

---

## Logging: which method did you use?

After every session, alongside the existing rating and note:

- **Unreported** (default — never force it)
- Blue Sky
- Body Scan
- Manifestation → Inner conversation
- Manifestation → Mental movie
- Energy Centers
- Counting Down
- **Something else** → free-text description

Schema: a new optional `technique: String?` on `Session` (CloudKit-safe, nil =
unreported), plus `techniqueNote: String?` for the free-text case. Same pattern
as the existing reflection.

---

## The data idea — and how to make it defensible

Melvin's insight: with enough users self-reporting technique alongside measured
biometrics, 808 could rank which meditations actually work.

**This is a genuine moat.** No other app can do it, because no other app measures
the body against a labelled technique. Worth taking seriously.

**But population ranking is the weaker version and it's a trap.** "Body scan
scores 8% higher than blue sky across our users" is confounded to uselessness:
people who choose manifestation differ systematically from people who choose body
scan, in experience, intent, time of day, session length and stress level. That's
observational data with self-selected treatment — the classic way to publish a
finding that isn't true.

**The stronger version is within-user, and it's better in every way:**

> "Your body settles more on body-scan days. Across 11 sessions, your score
> averages 74 with body scan and 61 with blue sky."

- It's an **n-of-1 crossover** — the same person, same body, same baseline. The
  confounds mostly cancel.
- It works from **~10 sessions**, not 10,000 users. Useful on day one of having
  the feature.
- It's **more valuable to the user** — nobody cares what works on average, they
  care what works for *them*.
- It's on-thesis: 808's whole argument is evidence about *you*, not a population.

Population ranking becomes available later, as an aggregate of many within-user
comparisons — which is a far more defensible statistic than pooling raw scores.

**Sequence:** ship the guide + logging first. Let per-user data accumulate. Add
"your best technique" once a user has enough labelled sessions. Only consider
public rankings after that, with the methodology stated.

---

## Build order

1. `MeditationMethod` catalog — pure Foundation, the five methods above. Testable, no UI.
2. The guide UI — roadmap/path, one page per method. Reachable from home and from the sound sheet.
3. `Session.technique` + the post-session picker.
4. "Your best technique" insight, gated on enough labelled sessions.

Steps 1–3 are the feature. Step 4 is the moat.

---

## Open

- **Does this go in the launch MVP or Stage 2?** It's cheap (text, no audio) and
  answers the most common beginner question, which argues for launch. It also
  widens scope on an MVP we just deliberately narrowed.
- **Where does it live?** Home tab, Settings, or surfaced contextually before a
  first session.
- **Does logging the technique appear in the post-session flow, or only in
  history?** Post-session gets far higher completion; history keeps the results
  screen clean.
