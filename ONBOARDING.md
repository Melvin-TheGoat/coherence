# 808 Onboarding — design spec

Modelled on QUITTR's flow (teardown from three screen recordings, 2026-08-05).
Nothing here is built yet. Design and copy only — no Swift written.

**One-line product promise for the MVP:** your Watch tracks your meditation and
scores it. Onboarding may motivate *why* someone meditates, but must not
re-introduce anything cut in the MVP pass (belly breathing, camera PPG, The
Method, guided steps, length picker).

---

## Decisions locked (Melvin, 2026-08-05)

| | |
|---|---|
| First emotion | **Relief, then curiosity.** Blame removed before any ask. |
| The pain | **Inconsistency** — you keep starting and stopping. |
| The score | A number to beat, framed as proof. **Post-session only** (see below). |
| Audience | Disciplined achiever **+** anxious/stressed, bridged by "bring your own audio". |
| The offer | "See it work, so you keep doing it." |
| No Apple Watch | **Waitlist**, offered honestly at Q5. Never funnel them to a paywall. |
| Pricing | 7-day free trial · **$5/mo · $30/yr · $50 lifetime** |
| Sign in with Apple | **After** the paywall. |
| Haptics | Every tap. Spec below. |
| Colour | **Stay gold-on-near-black.** Add a per-section colour arc, not a new hue. |

### ⚠️ The score: gamified history, silent session

Melvin chose "a number to beat". Onboarding and history lean into that hard —
beat yesterday, beat your average, keep the streak.

**But the number stays out of the live session.** Mid-session remains the orb
and the clock only. The reason is physiological, not philosophical: chasing a
number raises arousal, arousal raises heart rate and kills stillness, and those
are the two signals the score is computed from. A user watching their score
climb would measurably lower it. This is also consistent with CLAUDE.md's
"evidence, not a training score".

**Aziz: if you disagree, this is the one to argue about before building.**

---

## The flow — 26 screens

Grounds shift by section: **warm amber** (relief) → **teal** (the body enters) →
**deep red** (cost) → **gold** (the win). Gradient grounds and gradient buttons
throughout — the old flat-gold mock read as dull, and the fix was motion through
the palette, not a different palette.

**Every primary button is bottom-anchored in the thumb zone.**

1. **Relief** — "You're not bad at this." / *You just never got told whether it worked.* CTA: **Show me my number**
2. **Regulate** — a 3-second breath before any personal question. The only meditation onboarding that opens by actually doing it.
3. **Q1 · Why** — multi-select: less stressed / sharper focus / more discipline / better sleep / less anxious / deeper prayer or practice
4. **Q2 · Slider** — "How stressed have you been lately?" Fine → Fried. *Varies the input type; six tap-lists in a row causes drop-off.*
5. **Q3 · The admission** — "How many times have you started and stopped?" Ground turns red here.
6. **Q4 · The cause** — "What makes you stop?" Every option is one 808 answers.
7. **Q5 · The gate** — "Do you have an Apple Watch?" Plain language, no spin.
   - **7b · No Watch** → waitlist + email capture. *"We're not going to take your money for an app that can't do its one job."*
8. **Q6 · The anchor** — "When will you actually do it?" *Right after something you already do daily.* Doubles as the reminder time.
9. **You** — first name + age bracket.
10. **Calculating** — ~4 seconds. Subtitles must name things we actually do.
11. **The result** — their own answers reflected back and connected. Footnote: *"Your own answers, alongside published research on meditation-app dropout. Not a diagnosis."*
12. **The cost** — "What's it costing you?" Mind / Discipline / Spirit. Self-report only; we never assign a condition.
13. **Proof 1** — "Your body already keeps score."
14. **Proof 2** — "Then you get a number." The competitive hook, after the mechanism that makes it honest.
15. **Proof 3** — "Meditate however you like." YouTube, Spotify, prayer, silence. Leave the app; the Watch keeps measuring. **This is the bridge between our two audiences and our sharpest difference from Calm.**
16. **The wall** — vertical scroll of everyone who practises (see roster). Real quotes white; paraphrases greyed and labelled.
17. **16b · Your practice profile** — four cards, each a direct echo of an answer: what you're chasing, your pattern, your anchor, your blind spot.
18. **16c · Projection** — rising 4-week chart + *"Your 30-day streak lands Sept 4."* **Real arithmetic from their stated schedule**, with a footnote saying so.
19. **16d · How you'll get there** — features mapped to *their own words*:
    - A score after every session → *"I couldn't tell it was working"*
    - One tap, no length, no picking → *"Too many choices every time"*
    - A nudge after your coffee → *"I forgot"*
    - Your own audio, still measured → *"I felt like I was doing it wrong"*
20. **Commitment** — days/week, assembled into their own sentence.
21. **Permission** — notifications, asked *after* the commitment, phrased in their anchor. Pre-prompt so a "no" doesn't burn the system dialog.
22. **Your week** — Day 1 / 2 / 3 / 7 preview.
23. **Paywall** — 7 days free, then $5/mo · $30/yr · $50 lifetime. Trial terms on the button's own line.
24. **Exit offer** — **30 days free instead**, not a fake discount.
25. **Sign in with Apple** — framed as saving the streak they just built.

---

## Haptics

`.sensoryFeedback(_:trigger:)` throughout, gated on the existing
`hapticsEnabled` preference so it stays one switch in Settings.

| Moment | Feedback |
|---|---|
| Selecting a quiz option | `.selection` |
| Advancing a screen | `.impact(.soft)` |
| The restart-count answer | `.impact(.rigid)` — deliberately heavier |
| Slider crossing a notch | `.selection` |
| Result reveal / commit / trial start | `.success` |
| The breath screen | **none** — silence is the point |

This is most of why QUITTR's flow feels like a game rather than a form.

---

## Research behind the design

- Attrition in mindfulness-app RCTs runs **21–54%** — [Behaviour Research and Therapy (2023)](https://www.sciencedirect.com/science/article/pii/S0005796723001699). Peer-reviewed.
- **Greatest dropout is in the first two weeks** — [Mindfulness (2023)](https://link.springer.com/article/10.1007/s12671-023-02125-4). Peer-reviewed.
- **Meditating right after an existing routine lowered abandonment risk** — same study. This is why Q6 exists.
- **Decision fatigue** is repeatedly named as a dropout driver. The MVP's zero-decision Begin screen is therefore a *retention feature*, not just a simplification.
- The widely-quoted "Headspace 4.7% / Calm 5.2% 30-day retention" figures come from an industry blog, **not research**. Do not put them in the app.

---

## The quote roster

**Tier 1 — verified, safe to print in quotation marks**

| Who | Quote |
|---|---|
| Ray Dalio | "Transcendental Meditation has probably been the single most important reason for whatever success I've had." |
| Ray Dalio | "It helps slow things down so that I can act calmly, even in the face of chaos, like a ninja in a street fight." |
| Oprah Winfrey | "Meditation reorders the natural flow of life… Decisions come easily, things fall into place, and there's no conflict." |
| Kobe Bryant | "It's like having an anchor. If I don't do it, it feels like I'm constantly chasing the day." |

**Tier 2 — practice documented, no clean quote. Say "practises" / "credits", never quote.**

- **Athletes:** LeBron James, Novak Djokovic, Derek Jeter, Misty Copeland
- **Teams:** Seattle Seahawks (Pete Carroll, since 2011, under Michael Gervais); Chicago Bulls and LA Lakers (Phil Jackson, via George Mumford)
- **Founders/CEOs:** Bill Gates, Jeff Bezos, Marc Benioff, Jack Dorsey, Jeff Weiner, Russell Simmons
- **Entertainment:** Jerry Seinfeld (~40 yrs TM), Howard Stern, Hugh Jackman, David Lynch, Russell Brand, Arnold Schwarzenegger, Paul McCartney, Clint Eastwood, Katy Perry
- **Michael Jordan** — credited "that Zen Buddhist stuff". Paraphrase, not a quotation.

**Tier 3 — do not use**

- **Tony Robbins** — on record distinguishing his "priming" *from* meditation. Using him is a misattribution.
- **Jim Carrey** — TM-associated, but no verifiable quotable sentence found.
- **Steve Jobs** — real Zen influence, but he's dead and can't endorse an app.

> The strongest asset isn't a celebrity — it's **the teams**. "Phil Jackson ran
> mindfulness for the Jordan Bulls and the Kobe Lakers; Pete Carroll has had the
> Seahawks doing it since 2011" is a *pattern among people whose job is
> measurable performance*. That reads as evidence, not endorsement, and lands
> harder on the achiever audience than any single quote.

---

## What we deliberately do NOT copy from QUITTR

- **Fabricated scarcity** — "9 spots remaining", "94% DISCOUNT", "You will never see this again", a live 5:00 countdown. A meditation app manufacturing panic contradicts what it sells, and it's App-Review-adjacent.
- **Social proof we don't have** — they open with "over 2,000,000 users" plus Forbes and LA Weekly logos. **We have zero users and no press.** Leave the slot empty until it's true.
- **The invented goal date** — "You should quit porn by Nov 3, 2026" has no stated basis. Ours is arithmetic from the user's own schedule, with a footnote.
- **The invented comparison chart** — their 64%-vs-40% bars have no visible source.
- **The diagnosis voice** — "We've got some news to break to you" works on someone who typed "quit porn" into the App Store. Meditation buyers arrive aspirational; it misfires.

**Worth copying wholesale:** the **sticky CTA** that never leaves the screen
during their long sales page, one question per screen, tap-to-advance with no
confirm button, a visible-but-quiet "Skip", showing the streak card before
asking for anything, and treating the loading screen as a feature.

---

## Open — needs a decision before building

1. **Does the paywall block the first session, or come after it?** My instinct: after. The value isn't obvious until you've seen one measured session, but it costs trial starts.
2. **What does the anxious/stressed user see on day one**, given we have no content? "Bring your own audio" is the answer, but it has to be visible immediately, not discovered.
3. **Testimonials.** All five of QUITTR's benefit blocks are anchored by ★★★★★ and a quoted user. We have none. Either ship the blocks bare and add them post-TestFlight, or let the celebrity wall carry that weight — I'd do the second.

---

## Not started

Onboarding, `PURPOSE.md` and `SCIENCE.md` all still describe the pre-MVP feature
set. They need a pass before TestFlight. Also still open from the MVP cut:
whether sound survives at all (our audio conflicts with the user's own Spotify,
which is an argument for cutting it).
