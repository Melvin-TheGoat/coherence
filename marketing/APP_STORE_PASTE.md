# App Store Connect paste sheet

Values only, in the order the forms ask for them. Reasoning for any of these
lives in `APP_STORE.md`; this file exists to be copied from without reading.

Verified against the built app on 2026-09-01: 17 awards, 8 guide techniques,
the 25 minute guided track, 4 nature sounds, 3 brainwave tones, 4 tunings.

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

**Content Rights** — No third-party content. The narration was commissioned
with a commercial licence, the tones are synthesised at runtime, and the beds
and nature recordings were generated under commercial licence. All of it is
ours to ship.

**Age Rating** — answer the questionnaire honestly: wellness content, no
medical advice or treatment claims, no unrestricted web access, no
user-generated content, no gambling, no contests. Expect the lowest tier.

---

## Version 1.0

**Promotional Text** (editable later without review)

```
Meditate however you like. Your Apple Watch measures how far your body settled, and 808 scores it out of 100 when you finish.
```

**Description**

```
Most people meditate blind. You sit, you follow your breath, and afterwards you have no idea whether anything actually happened. 808 answers that.

Wear your Apple Watch and meditate however you like. When you finish, 808 shows you what your body did while you were there, and gives you one score out of 100.

WHAT 808 MEASURES
Three signals, all from the Watch already on your wrist. How still your body became. How far your heart rate settled across the session. And your breathing rate, read from the small tilt of your wrist when you slow your breath down. No chest strap, no special posture, no setup.

ONE SCORE, NOT A GUESS
Every session ends with a practice score built from how deep you got and how long you held it. Thirty restless minutes will never beat five settled ones. Nothing is shown while you practise, because a live number is just one more thing to chase. The evidence comes after.

BRING YOUR OWN MEDITATION
Already have a teacher you like on YouTube or Spotify? Start a session and play whatever you want in any other app. The Watch keeps measuring. There is nothing to switch to and nothing to give up.

OR USE OURS
A 25 minute guided journey, professionally narrated. Brainwave paced tones for delta, theta and alpha. Traditional tunings at 432, 528, 852 and 963 Hz, each over an ambient bed. Rain, ocean, forest and campfire.

LEARN HOW TO ACTUALLY MEDITATE
Eight techniques written in plain language, easiest first, from your first ever sit through to visualisation practice.

A HABIT YOU CAN SEE
Streaks, a calendar of practised days, your full session history, and seventeen awards. Earned awards are yours for good, even if a streak breaks.

SHARE THE PROOF
Turn any session into a card carrying your real graphs, ready for your story.

PRIVATE BY DESIGN
Your heart rate, your breathing and your scores are computed on your devices and stay on your device. They are never uploaded, and we cannot see them. We use basic anonymous analytics to learn which screens people use, and no biometric data is ever part of it. No ads. No data sales. Sign in with Apple is the only sign-in and it is optional.

HONEST SCIENCE
The stillness and breathing measurements are grounded in peer-reviewed research on wrist-worn motion sensing. Traditional frequencies are labelled as tradition, not sold as proven. 808 is a wellness app, not a medical device, and does not diagnose, treat or prevent any condition.

Requires a paired Apple Watch to measure a session.
```

**Keywords** (100 max, no spaces after commas)

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

**What's New** — leave empty for a first release. App Store Connect only asks
for it on updates.

---

## Screenshots

**iPhone 6.9 inch (required)** — upload all eight in this order, from
`marketing/appstore/`:

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

**Apple Watch (required, we ship a Watch app)** — from
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

**Contact** — Melvin Van Cleave, the phone number on the D-U-N-S record
(818-422-1140), and an email on the meditate808.com domain.

**Notes**

```
808 measures meditation sessions using Apple Watch (heart rate and motion via a .mindAndBody workout). A paired physical Apple Watch is required to record a session; everything else (onboarding, sounds, guide, history, settings) is fully reviewable on iPhone alone. Sign in with Apple is the only sign-in and it is optional, so no demo account exists or is needed.

Health data: session results are computed on-device and stored only on-device, in a store excluded from CloudKit sync, per guideline 5.1.3(ii).

Audio licensing: the guided narration was commissioned with a commercial licence; the tones are synthesised at runtime; the ambient beds and nature recordings were generated under commercial licence.
```

---

## App Privacy — CHANGED, do not answer from memory

Declare exactly one thing:

- **Usage Data → Product Interaction**
  - Collected: **Yes**
  - Linked to the user's identity: **No** (the analytics ID is an anonymous
    install-scoped UUID)
  - Used for tracking: **No**

Nothing else. No health, no fitness, no contact info, no identifiers.

This changed when PostHog went live on 2026-08-17. The old "Data Not
Collected" answer is no longer true, and `PrivacyInfo.xcprivacy` in the binary
already declares Product Interaction. **If the labels and the manifest
disagree, that is a rejection.**

Health and fitness are deliberately absent: heart rate, breathing, stillness
and scores never leave the device, and Apple's definition of "collect" is data
transmitted off device where the developer can read it. The account and session
log sync only to the user's own private CloudKit database, which we cannot
read.

---

## Pricing

The app itself is **free**. Revenue comes from the three in-app purchases in
`APP_STORE.md`, which cannot be created until the Paid Applications agreement
is active.
