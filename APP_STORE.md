# App Store metadata — 808 (v1.0 DRAFT)

Everything App Store Connect asks for, pre-written. Character limits noted;
all counts verified under limit. Positioning per roadmap 8b: **"Meditation
for manifestation"**, defined as *implanting intentions into your
subconscious* — paired with the evidence angle (the thing nobody else has).
All claims wellness-grade, never medical (matches SCIENCE.md).

Rewritten 2026-08-11 for the MVP: belly breathing and the camera check are
gone from the copy because they are gone from the app, and metadata that
promises features the binary lacks is a 2.3.7 rejection. Em dashes are out of
every user-facing block per the standing copy rule; this header is internal
and exempt, like code comments.

---

## Name (30 max)

**808**

*(The App Store Connect record is "808: Meditate" because bare "808" was
taken. What ships under the icon is `CFBundleDisplayName` = 808 either way.)*

## Subtitle (30 max)

**Meditation for manifestation**  *(28 chars)*

## Category

Primary: **Health & Fitness** · Secondary: **Lifestyle**

## Promo text (170 max — editable anytime without review)

> Meditate with intention. Your Apple Watch measures how deeply your body
> settled. Evidence your practice landed, shown after every session.

*(148 chars)*

## Description (4000 max)

> **Most people meditate blind.** They close their eyes, follow their breath,
> and afterward wonder: was that even working? 808 answers the question.
>
> Meditate with your Apple Watch on. When you finish, 808 shows you what your
> body did: how still you became, how your heart rate settled, and, when you
> breathe slowly, your breathing rate, read from the tiny movement of your
> wrist. No chest strap, no posture, no setup. No live scores to chase during
> practice. Just quiet, and then evidence.
>
> **MEDITATION FOR MANIFESTATION**
> Manifestation is implanting intentions into your subconscious. 808's guided
> identity-shift journey walks you into deep relaxation, then has you live a
> future memory (courage, gratitude, awe) until who you are and who you're
> becoming point in the same direction.
>
> **BRING YOUR OWN MEDITATION**
> Start a session and play anything you like in any other app. The Watch
> keeps measuring. Use our guided journey, our sounds, or your own library.
>
> **WHAT YOU GET**
> • A practice score after every session, built from stillness, heart-rate
>   settling, and your breathing when it can be read
> • Guided identity-shift meditation (25 min), professionally narrated
> • Frequency sounds: brainwave-paced tones (theta, alpha, delta) and
>   traditional tunings (432, 528, 852, 963 Hz), each over an ambient bed
> • Nature sounds: rain, ocean, forest, campfire
> • Slow-breathing readout: around six breaths a minute is what it reads
>   best, which is also the pace worth practising
> • Streaks, calendar, session history, and post-session reflections
> • Share your practice: a session card for your story
>
> **PRIVATE BY DESIGN**
> Your session results are computed on your devices and stay there. Never
> uploaded, not to us, not even to iCloud. No ads, no data sales. Sign in
> with Apple only, and you can use the app without signing in at all.
>
> **HONEST SCIENCE**
> Stillness and breathing measurement are grounded in peer-reviewed research
> on wrist-worn motion sensing. Traditional frequencies are labeled as
> tradition, not overclaimed. 808 is a wellness app, not a medical device,
> and does not diagnose, treat, or prevent any condition.
>
> Requires an Apple Watch to measure sessions.

## Keywords (100 max, comma-separated — don't repeat name/subtitle words)

`breathwork,binaural,frequency,528hz,solfeggio,theta,intention,subconscious,stillness,calm,guided`

*(98 chars)*

## URLs (live — Cloudflare Pages on meditate808.com)

- Support URL: `https://meditate808.com/#support`
- Marketing URL: `https://meditate808.com`
- Privacy Policy URL: `https://meditate808.com/privacy`
- Terms: `https://meditate808.com/terms` · Waitlist survey: `https://meditate808.com/survey`
- Contact: `support@meditate808.com` (Cloudflare Email Routing → Aziz's inbox)

## Age rating

Apple's UPDATED questionnaire (2025 rework: in-app controls, capabilities,
medical/wellness topics) is answered at submission in App Store Connect.
Expected honest answers: wellness content without medical advice, no
unrestricted web, no UGC, no gambling → lowest tier (4+). Do not claim
health outcomes anywhere in metadata; the questionnaire cross-references it.

## App Privacy (nutrition labels)

**Declare "Data Not Collected", and mean it.** Apple defines "collect" as
transmitting data off device where the developer or a third party can read
it. 808 transmits nothing we can read: health results never leave the device
(device-local store, excluded from CloudKit per 5.1.3(ii)); the account and
session log sync only to the user's PRIVATE CloudKit database, which we
cannot access; there is no analytics, no ads, no server of ours. The privacy
manifests (`PrivacyInfo.xcprivacy`, both targets) declare the same thing and
are the standing record of the reasoning. If we ever add analytics or a
backend, labels and manifests change together.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is already in the Info.plist, so App
Store Connect should not ask. If it does: only standard Apple-provided
encryption (HTTPS/CloudKit) → exempt.

## Review notes (paste into App Review notes field)

> 808 measures meditation sessions with Apple Watch (heart rate + motion via
> a .mindAndBody workout). A paired physical Apple Watch is required to
> record a session; the rest of the app (onboarding, sounds, history,
> settings) is fully reviewable on iPhone alone. Sign in with Apple is the
> only sign-in and it is optional; no demo account exists or is needed.
> Health data: session results are computed on-device and stored only
> on-device (device-local store, excluded from CloudKit), per guideline
> 5.1.3(ii). Audio is licensed: narration commissioned with commercial
> license; tones synthesized at runtime; ambient beds generated under
> commercial license.

## What's New (v1.0)

> Welcome to 808: meditation for manifestation, with evidence your practice
> landed. A guided identity-shift journey, frequency and nature sounds, a
> breathing readout from your wrist, streaks, and a shareable session card.

## Screenshots (6.9" required — 1320×2868; optional 6.5")

Suggested order (story arc: payoff first):
1. **Results screen** — "Evidence your practice landed" (hero shot)
2. **Home** — streak + calendar ("A practice that compounds")
3. **Session setup** — sound worlds ("Set your intention")
4. **Share card** — ("Proof, beautiful enough to share")
5. **Onboarding/Purpose** — ("Rewrite the identity underneath")

Dark theme for all (brand). Captions above devices, set in the store's
screenshot frames or a simple template later. Screenshot captions must name
their subject (standing copy rule) and show only current features.

## Launch checklist tie-ins (from roadmap 8c — not metadata, don't forget)

- Deploy the CloudKit schema to Production — and FIX SYNC FIRST: as of
  2026-08-11 CloudKit has never synced at all (empty Development schema).
- StoreKit must be live (products in App Store Connect under the same IDs as
  `Store.ProductID`) or the paywall's selling state never activates. The
  "Free while we're testing" copy must never reach an App Store build.
- Capabilities (HealthKit / SIWA / CloudKit / Push) on the App ID for the
  SHIPPING bundle ID `com.lockout.meditate808` — registered on the
  ORGANIZATION account when it exists, never on either personal account.
- TestFlight first: internal → external; verify CloudKit sync cross-device.
