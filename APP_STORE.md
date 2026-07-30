# App Store metadata — 808 (v1.0 DRAFT)

Everything App Store Connect asks for, pre-written. Character limits noted;
all counts verified under limit. Fill the `[BRACKET]` URLs after the website
is hosted. Positioning per roadmap 8b: **"Meditation for manifestation"**,
defined as *implanting intentions into your subconscious* — paired with the
evidence angle (the thing nobody else has). All claims wellness-grade, never
medical (matches SCIENCE.md).

---

## Name (30 max)

**808**

## Subtitle (30 max)

**Meditation for manifestation**  *(28 chars)*

## Category

Primary: **Health & Fitness** · Secondary: **Lifestyle**

## Promo text (170 max — editable anytime without review)

> Meditate with intention. Your Apple Watch measures how deeply your body
> settled — evidence your practice landed, shown after every session.

*(150 chars)*

## Description (4000 max)

> **Most people meditate blind.** They close their eyes, follow their breath,
> and afterward wonder: was that even working? 808 answers the question.
>
> Meditate with your Apple Watch on, and when you finish, 808 shows you what
> your body did: how still you became, how your heart rate settled, and — in
> belly-breathing sessions — your actual breathing rhythm, recovered from the
> gentle rise and fall of your wrist on your belly. No live scores to chase
> during practice. Just quiet, and then evidence.
>
> **MEDITATION FOR MANIFESTATION**
> Manifestation is implanting intentions into your subconscious. 808's guided
> identity-shift journey walks you into deep relaxation, then has you live a
> future memory — courage, gratitude, awe — until who you are and who you're
> becoming point in the same direction.
>
> **WHAT YOU GET**
> • Practice score after every session — stillness, heart-rate settling, and
>   breathing combined into one number
> • Guided identity-shift meditation (25 min), professionally narrated
> • Frequency sounds — brainwave-paced tones (theta, alpha, delta) and
>   traditional tunings (432, 528, 852, 963 Hz), each over a lush ambient bed
> • Nature sounds — rain, ocean, forest, campfire
> • Belly breathing mode — lie down, rest your wrist on your belly, and 808
>   reads your breath and matches it against the ~6 breaths/min resonance pace
> • Streaks, calendar, session history, and post-session reflections
> • Share your practice — a beautiful session card for your story
>
> **PRIVATE BY DESIGN**
> Your session results are computed on your devices and stay there — never
> uploaded, not to us, not even to iCloud. No ads, no data sales. Sign in with
> Apple only.
>
> **HONEST SCIENCE**
> Stillness and breathing measurement are grounded in peer-reviewed research
> on wrist-worn motion sensing. Traditional frequencies are labeled as
> tradition, not overclaimed. 808 is a wellness app, not a medical device, and
> does not diagnose, treat, or prevent any condition.
>
> Requires Apple Watch for session measurement.

## Keywords (100 max, comma-separated — don't repeat name/subtitle words)

`breathwork,binaural,frequency,528hz,solfeggio,theta,intention,subconscious,stillness,calm,guided`

*(98 chars)*

## URLs

- Support URL: `[https://…/support — REQUIRED, reviewers visit it]`
- Marketing URL: `[https://… — the landing page]`
- Privacy Policy URL: `[https://…/privacy — REQUIRED for HealthKit apps]`

## Age rating

All questionnaire answers "No" → **4+**. (No medical/treatment info claims —
we present wellness measurements only; no unrestricted web, no UGC in v1.)

## App Privacy (nutrition labels)

Declare honestly — the story is unusually clean:

- **Health & Fitness** (heart rate, motion-derived results): collected,
  **not linked to identity, not used for tracking — stored on-device only,
  never leaves the user's devices.** (If Connect's flow treats "on-device
  only" as *not collected*, prefer that — verify the current definitions at
  submission; Apple's "collected" means transmitted off device.)
- **Name, Email** (Sign in with Apple): linked to identity, used only for
  app functionality (account). Optional marketing-email opt-in.
- **No tracking. No third-party ads. No data brokers/SDKs.**

## Export compliance

Uses only standard Apple-provided encryption (HTTPS/CloudKit) → exempt.
Answer: uses encryption YES → exempt under the standard exemption.

## Review notes (paste into App Review notes field)

> 808 measures meditation sessions with Apple Watch (heart rate + motion via
> a .mindAndBody workout). A paired physical Apple Watch is required to
> record a session; the rest of the app (onboarding, sounds, history,
> settings) is fully reviewable on iPhone alone. No demo account is needed —
> Sign in with Apple creates the account. Health data note: session results
> are computed on-device and stored only on-device (device-local store,
> excluded from CloudKit), per guideline 5.1.3(ii). Audio is licensed:
> narration commissioned with commercial license; tones synthesized at
> runtime; ambient beds generated under commercial license.

## What's New (v1.0)

> Welcome to 808 — meditation for manifestation, with evidence your practice
> landed. Guided identity-shift journey, frequency and nature sounds, belly
> breathing, streaks, and a shareable session card.

## Screenshots (6.9" required — 1320×2868; optional 6.5")

Suggested order (story arc: payoff first):
1. **Results screen** — "Evidence your practice landed" (hero shot)
2. **Home** — streak + calendar ("A practice that compounds")
3. **Session setup** — sounds + belly breathing ("Set your intention")
4. **Share card** — ("Proof, beautiful enough to share")
5. **Onboarding/Purpose** — ("Rewrite the identity underneath")

Dark theme for all (brand). Captions above devices, set in the store's
screenshot frames or a simple template later.

## Launch checklist tie-ins (from roadmap 8c — not metadata, don't forget)

- Flip `aps-environment` → `production`; deploy CloudKit schema to Production.
- Enable HealthKit / SiwA / CloudKit / Push on the App ID in the developer
  portal for the SHIPPING bundle ID (`com.lockout.coherence` on Melvin's
  account).
- TestFlight first: internal → external; verify CloudKit sync cross-device.
