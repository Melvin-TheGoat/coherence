# App Store Connect paste sheet

Values only, in the order the forms ask for them. Reasoning lives in
`APP_STORE.md`; this file exists to be copied from without reading.

Rewritten 2026-09-01 against the shipping build. Verified: 17 awards, the 25
minute guided track, 4 nature sounds, 3 brainwave tones, 4 tunings.

**The description opens on the problem, never on the score** (Melvin, 2026-09-01:
"a user might ask what score, why do I care about that above all other
things"). Checked against how comparable apps actually open: Athlytic
"transforms Apple Watch data into actionable fitness insights", Gentler Streak
"guidance that adapts to your daily capabilities", Balance "a personal
meditation coach", and Muse, which scores meditation from EEG and still leads
with "track and improve your brain health". None of them opens with its metric.
The score is the mechanism, and it only earns attention after the reader has
been reminded of the question it answers.

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
Your Watch already tracks your runs, your sleep and your steps. 808 makes it track the ten minutes you spend meditating, and shows you what your body actually did.
```

**Description**

```
You sit for ten minutes, open your eyes, and have no idea whether anything happened. Meditation is the one habit that never tells you how it went.

Your Apple Watch already tracks your runs, your sleep and your steps. 808 makes it track this too. Wear it while you meditate, in whatever way you already meditate, and afterwards 808 shows you what your body actually did.

MEDITATE HOWEVER YOU LIKE
Keep the teacher you like on YouTube or Spotify. Start a session, play whatever you want in any other app, and the Watch keeps measuring. Nothing to switch to, nothing to give up. Silence works too.

SEE WHAT YOUR BODY DID
Three signals, all from the Watch already on your wrist. How far your heart rate came down. How still you became, and when you settled. And your breathing rate, read from the small tilt of your wrist when you slow your breath. Every one of them drawn as a curve you can scrub through, minute by minute.

ONE NUMBER, SO YOU CAN COMPARE
Every session ends with a practice score out of 100, so today means something next to last Tuesday. It is built from how deep you got and how long you held it, so a short settled sit can score every bit as well as a long one. Underneath it, a plain sentence telling you what happened, in words rather than numbers.

THE HABIT, NOT JUST THE SESSION
A streak, a calendar that fills in as you show up, your full history, and seventeen awards to work towards.

IF YOU ARE NEW TO THIS
A written guide to the techniques themselves, easiest first, starting with what to actually do the very first time you sit down.

OR USE OUR SOUNDS
A 25 minute guided journey, professionally narrated. Brainwave paced tones for delta, theta and alpha. Traditional tunings at 432, 528, 852 and 963 Hz, each over an ambient bed. Rain, ocean, forest and campfire.

SHARE IT WITH YOUR FRIENDS
Turn any session into a card carrying your real graphs and your streak, compatible with any app.

WHAT IS FREE
Your score, the written verdict, your streak, the calendar, your full history and every award are free. A membership unlocks the evidence underneath the score: the heart rate, stillness and breathing curves, the guided journey, and the rest of the share cards.

PRIVATE BY DESIGN
Your heart rate, your breathing and your scores are computed on your devices and stay on your device. They are never uploaded, and we cannot see them. We use basic anonymous analytics to learn which screens people use, and no biometric data is ever part of it. No ads. No data sales. Sign in with Apple is the only sign-in, and it is optional.

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
