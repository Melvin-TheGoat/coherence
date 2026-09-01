# App Store Connect paste sheet

Values only, in the order the forms ask for them. Reasoning lives in
`APP_STORE.md`; this file exists to be copied from without reading.

Rewritten 2026-09-01 against the shipping build. Verified: 17 awards, the 25
minute guided track, 4 nature sounds, 3 brainwave tones, 4 tunings, and the
onboarding walkthrough that ends in a real measured session.

---

## App Information (set once, not per version)

**Name**

```
808 Meditate
```

**Subtitle**

```
Score your meditation
```

**Category** — Primary `Health & Fitness` · Secondary `Lifestyle`

**Content Rights** — No third-party content. Narration commissioned with a
commercial licence, tones synthesised at runtime, beds and nature recordings
generated under commercial licence.

**Age rating questionnaire** — User-Generated Content **No**. Social Media
**No**. Health or Wellness Topics **Yes**. Medical or Treatment Information
**None**. Result: 4+ globally.

**Digital Services Act (trader details, PUBLISHED on the EU listing)** — use
the registered address, never the Brooklyn one:

```
Lock Out Inc.
8 The Green, Ste A
Dover, DE 19901
United States
```

**App Encryption** — nothing to upload. Both targets declare
`ITSAppUsesNonExemptEncryption = false`; the app uses only Apple's standard
HTTPS and CloudKit encryption.

**Accessibility Nutrition Labels** — deliberately left EMPTY. See
`App_ROADMAP_v2.md` 8a.2: Dynamic Type and VoiceOver are not yet supported, and
these labels are a public claim.

---

## Version 1.0

**Promotional Text** (editable later without a new review)

```
Your first score arrives before setup is finished. Two minutes of slow breathing, measured on your Apple Watch, and you see exactly what your body did.
```

**Description**

```
Most people meditate blind. You sit, you follow your breath, and afterwards you have no idea whether anything actually happened.

808 answers that. Wear your Apple Watch, meditate however you like, and when you finish you get one number out of 100, built from what your body actually did while you were there.

YOUR FIRST SCORE ARRIVES BEFORE SETUP IS FINISHED
808 ends its setup by measuring you. Two minutes of slow breathing, read from your wrist, then your real result. Not a demo and not a sample. Your body, your number, in the first few minutes you own the app.

WHAT IT MEASURES
Three signals, all from the Watch already on your wrist. How still your body became. How far your heart rate settled across the session. And your breathing rate, read from the small tilt of your wrist when you slow your breath down. No chest strap, no special posture, no setup.

ONE SCORE, NOT A GUESS
The score is how deep you got and how long you held it. Thirty restless minutes will never beat five settled ones. Nothing is shown while you practise, because a live number is just one more thing to chase. The evidence comes after.

BRING YOUR OWN MEDITATION
Already have a teacher you like on YouTube or Spotify? Start a session and play whatever you want in any other app. The Watch keeps measuring. There is nothing to switch to and nothing to give up.

OR USE OURS
A 25 minute guided journey, professionally narrated. Brainwave paced tones for delta, theta and alpha. Traditional tunings at 432, 528, 852 and 963 Hz, each over an ambient bed. Rain, ocean, forest and campfire.

LEARN HOW TO ACTUALLY MEDITATE
A written guide to the techniques themselves, easiest first, from your first ever sit through to visualisation practice. It grows over time.

A HABIT YOU CAN SEE
Streaks, a calendar of practised days, your full session history, and seventeen awards. Earned awards are yours for good, even if a streak breaks.

SHARE THE PROOF
Turn any session into a card carrying your real graphs, ready for your story.

WHAT IS FREE
Your score, the verdict in plain words, your streak, the calendar, your full history and every award are free. A membership unlocks the evidence underneath the score: the heart rate, stillness and breathing graphs, the guided journey, and the rest of the share cards.

PRIVATE BY DESIGN
Your heart rate, your breathing and your scores are computed on your devices and stay on your device. They are never uploaded, and we cannot see them. We use basic anonymous analytics to learn which screens people use, and no biometric data is ever part of it. No ads. No data sales. Sign in with Apple is the only sign-in and it is optional.

HONEST SCIENCE
The stillness and breathing measurements are grounded in peer-reviewed research on wrist-worn motion sensing. Traditional frequencies are labelled as tradition, not sold as proven. 808 is a wellness app, not a medical device, and does not diagnose, treat or prevent any condition.

Requires a paired Apple Watch to measure a session.

SUBSCRIPTION INFORMATION
808 Monthly: $7.99 per month, after a 7-day free trial.
808 Yearly: $29.99 per year, after a 7-day free trial.
Both renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account settings.
808 Lifetime: $99.99, one payment, nothing renews.

Terms of Use: https://meditate808.com/terms.html
Privacy Policy: https://meditate808.com/privacy.html
```

**Keywords** (no spaces after the commas, they cost characters)

```
breathwork,binaural,frequency,528hz,solfeggio,theta,stillness,calm,guided,tracker,streak,mindful
```

**Support URL**

```
https://meditate808.com/#support
```

**Marketing URL**

```
https://meditate808.com
```

**Privacy Policy URL**

```
https://meditate808.com/privacy
```

**Version**

```
1.0
```

**Copyright**

```
2026 Lock Out Inc.
```

**What's New** — leave empty. Apple only asks on updates.

---

## Screenshots

**iPhone 6.9 inch (required)**, from `marketing/appstore/`, in this order. The
first three appear in search results, so they carry the argument: proof, then
the evidence behind it, then the habit.

```
01-score.png
02-evidence.png
03-habit.png
04-audio.png
05-awards.png
06-journey.png
07-guide.png
08-share.png
```

**Apple Watch (required, we ship a Watch app)**, from
`marketing/appstore/watch/`:

```
01-begin.png
02-measuring.png
```

No iPad set: the app is iPhone and Watch only (`TARGETED_DEVICE_FAMILY: 1`).

---

## App Review Information

**Sign-in required?** No. Sign in with Apple is the only sign-in and it is
optional, so no demo account exists or is needed.

**Contact** — Melvin Van Cleave, 818-422-1140, and an email on the
meditate808.com domain. **Not a personal Gmail.**

**Notes**

```
808 measures meditation sessions using Apple Watch (heart rate and motion via a .mindAndBody workout). A paired physical Apple Watch is required to record a session; everything else (onboarding, sounds, guide, history, settings, and all three in-app purchases) is fully reviewable on iPhone alone. Sign in with Apple is the only sign-in and it is optional, so no demo account exists or is needed.

Reviewing without an Apple Watch: at the onboarding question "Do you have an Apple Watch?", answer YES (answering no honestly routes to a waitlist and deliberately never shows the paywall, since the app will not sell to someone it cannot measure for). At the "Put your Watch on" screen, tap "Check again" three times; a "My Watch isn't with me. Continue" option appears and the two-minute practice is skipped, never simulated. The paywall, the free tier, and every purchase flow are reachable from there with no hardware.

Health data: session results are computed on-device and stored only on-device, in a store excluded from CloudKit sync, per guideline 5.1.3(ii).

Audio licensing: the guided narration was commissioned with a commercial licence; the tones are synthesised at runtime; the ambient beds and nature recordings were generated under commercial licence.
```

---

## App Privacy — THREE types, do not answer from memory

Answer **Yes, we collect data from this app**, then declare exactly these,
each with purpose **Analytics** only, **not linked** to identity, **not** used
for tracking:

| Data type | Why |
|---|---|
| **Identifiers → User ID** | The analytics SDK transmits a persistent install-scoped UUID with every event as its `distinct_id`. Random UUID v7 in its own storage, never the IDFA or identifierForVendor. Anonymous, which is why it is not linked, but it is collected. |
| **Purchases** | The monetization events name the plan bought (purchase, trial started, restore, entitlement lost). No payment details ever travel this path, so Financial Info stays off. |
| **Usage Data → Product Interaction** | Session started and completed, onboarding steps, paywall views, locked-feature taps, app launches. |

Tracking question at the end: **No.** No IDFA, no ad networks, no data brokers,
nothing linked across apps or websites.

**Nothing else is ticked**, and two will tempt you:

- **Not Health & Fitness.** Heart rate, breathing, stillness and scores are
  computed and stored on device. The analytics rules forbid biometrics even
  banded, because HealthKit data may not be disclosed to third parties under
  5.1.3.
- **Not Contact Info.** Name and email from Sign in with Apple go only to the
  user's own private CloudKit database, which we cannot read. Apple's
  definition of "collect" turns on whether the developer can access it.

`PrivacyInfo.xcprivacy` declares these same three. **If the labels and the
manifest disagree, that is a rejection.** Change them together, always.

---

## Pricing

The app is **free** to download. Revenue is the three in-app purchases in
`APP_STORE.md`, which cannot be created until the Paid Applications agreement
is active (gated on the Mercury account, see `LEGAL_ACTION_ITEMS.md`).
