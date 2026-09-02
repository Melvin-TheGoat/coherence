# Reply to Guideline 2.1, Information Needed (first submission)

Apple sends this to every developer account with no review history. It is a
request for information, not a rejection: **no app change is required.** Paste
the numbered answers below into the App Store Connect reply, and also into the
App Review Information **Notes** field so future submissions carry them.

Item 1 is a screen recording only Melvin can make. Its spec is at the bottom.

---

## 2. Purpose and target audience

```
808 measures meditation and scores it, using the Apple Watch the user already owns.

The problem it solves: meditation is the only common health habit that gives no feedback. A runner sees pace and distance; someone who meditates for ten minutes opens their eyes with no idea whether anything happened. That absence is a well-documented reason people stop practising.

How it works: the user starts a session on the iPhone or on the Watch and meditates in whatever way they already meditate, including playing audio from any other app. The Watch runs a .mindAndBody workout and records heart rate along with CoreMotion data. At the end, an on-device algorithm produces three signals (how still the body became, how far heart rate settled, and breathing rate read from small wrist tilt) and combines them into one practice score out of 100, with the curves behind it and a plain-language summary.

Target audience: adults who already own an Apple Watch and either meditate already or have tried and stopped. It is a general wellness app for a general audience, rated 4+. It is not aimed at any clinical population and makes no medical claims.
```

## 3. Setting up and accessing the main features

```
No account and no credentials are required. Sign in with Apple is offered but is entirely optional, and every feature works without it, so there is no demo account to provide.

Full flow with an Apple Watch:
1. Launch the app and complete onboarding (a short questionnaire, then a guided walkthrough).
2. On the home screen, tap "Begin session". A five second countdown runs, then the Watch starts measuring.
3. Meditate. Optionally play audio from any other app; the Watch keeps measuring.
4. Tap End on the Watch. The session is scored and the results screen opens with the score, the written summary, and the heart rate, stillness and breathing curves.

Reviewing WITHOUT an Apple Watch (recommended if no paired Watch is available):
1. At the onboarding question "Do you have an Apple Watch?", answer YES. Answering no routes to a waitlist and deliberately never shows the paywall, because we do not sell to someone the app cannot measure for.
2. At the "Put your Watch on" screen, tap "Check again" three times. A "My Watch isn't with me. Continue" option then appears and the two-minute practice is skipped. It is never simulated and no fake data is ever produced.
3. Everything except live measurement is then reachable: the paywall and all purchase flows, the sound library, the written meditation guide, history, awards, and settings.

Account deletion: Settings (gear icon, top right of the home screen) > Delete account. This is available to every signed-in user, and the account plus all associated rows are hard-deleted after a 30 day grace period.
```

## 4. External services, tools and platforms

```
Apple frameworks only, plus one analytics SDK. There is no server of ours, no backend, and no AI or machine-learning service anywhere in the app.

- HealthKit (Apple): reads heart rate and heart rate variability on the Watch, and records the .mindAndBody workout. Results are computed and stored on device and are never transmitted to us or to any third party.
- CoreMotion (Apple): accelerometer and device-motion data on the Watch, used for stillness and breathing. Never leaves the device.
- WatchConnectivity (Apple): carries the finished session from the Watch to the iPhone.
- CloudKit (Apple): syncs the user's own account, session log and streak to their PRIVATE iCloud database, which we cannot read. Health results are deliberately excluded from sync and stay on device, per guideline 5.1.3(ii).
- Sign in with Apple: the only sign-in method, and optional.
- StoreKit 2 (Apple): all purchases and entitlements.
- PostHog (posthog.com), US Cloud: product analytics only. Named behavioural events such as screens completed and paywall viewed. It never receives biometric data, health data, scores, or free text. The identifier is an anonymous per-install UUID. This is the only third party the app contacts, and it is declared in the privacy manifest and the App Privacy labels as Product Interaction, User ID and Purchases, none linked to identity and none used for tracking.

The score, the written summary, and every measurement are produced by our own deterministic algorithm running on the device. No large language model or AI service is involved in generating any of it.
```

## 5. Regional differences

```
There are none. The app behaves identically in every region and every storefront. All content is English only, there is no region-gated content, no regional pricing beyond Apple's standard territory conversion of the same price tiers, and no feature is enabled or disabled by location. The app does not request or use location data.
```

## 6. Regulated industry and third-party material

```
808 is a general wellness app, not a medical device and not a regulated service. It does not diagnose, treat, cure or prevent any condition, and it makes no medical claims. This is stated in the App Store description, in the bundled Science page inside the app, and in the Terms of Service.

The app displays heart rate and motion data that the user's own Apple Watch records, under HealthKit permission the user grants explicitly, and it presents that data only back to the user on their own device.

All audio in the app is ours to ship:
- The 25 minute guided narration was commissioned from a voice artist with a commercial licence covering commercial distribution.
- The frequency tones are synthesised at runtime by our own code. There are no audio files for them.
- The ambient beds and the nature recordings were generated under commercial licence.

No third-party copyrighted music, audio, or text appears in the app. Research findings referenced in the app's Science page are cited to their published sources and are described as research about meditation generally, explicitly not as claims about 808.
```

## 7. What can be bought with In-App Purchase, and how to reach it

```
808 is free to download and free to use. The practice score, the written summary, the streak, the practised-days calendar, the full session history, and all seventeen awards are free forever. A membership unlocks the evidence behind the score: the heart rate, stillness and breathing curves, the 25 minute guided journey, and the additional share card layouts.

Three products, in one subscription group plus one non-consumable:
- 808 Monthly, com.lockout.meditate808.monthly, auto-renewable, 1 month, USD 7.99, with a 7 day free trial.
- 808 Yearly, com.lockout.meditate808.yearly, auto-renewable, 1 year, USD 29.99, with a 7 day free trial.
- 808 Lifetime, com.lockout.meditate808.lifetime, non-consumable, USD 99.99, one payment, nothing renews, no introductory offer.

How to reach the purchase flow, two ways:
1. During onboarding: the offer appears near the end of the flow, after the walkthrough. If no Apple Watch is present, use the three "Check again" taps described in item 3 to continue past the Watch step, and the offer follows.
2. After onboarding: open any completed session from the home screen or from Journey. The locked curves show an unlock control that opens the same offer screen.

The offer screen displays, for every product, the title, the duration, the price, and the renewal terms in words, along with functional links to the Privacy Policy and the Terms of Use, and a Restore Purchase control. Declining leads to a downsell offer and then to the free tier, which remains fully usable.
```

---

## Item 1: the screen recording

Record on a **physical iPhone**, latest iOS, with the paired Apple Watch. One
continuous take is best. Apple asks for launch first and the typical flow, and
names three things that must appear.

Order to record:

1. **Launch from the home screen.** Show the icon being tapped.
2. **Onboarding**, moving briskly. It is long, so tap through rather than
   reading. Make sure the Watch question and the walkthrough are visible.
3. **The subscription flow, slowly.** This is the part Apple is strictest
   about, and they name exactly what must be legible: the **title, length and
   price of each** product, and the **Terms of Use and Privacy Policy links**.
   Our offer screen shows all of it on one screen; hold on it for several
   seconds so it is readable in the video, and tap one of the legal links to
   show it opens.
4. **Decline the offer** ("Not right now") to show the downsell and the free
   tier, then continue.
5. **A real session**: tap Begin session, show the countdown, show the Watch
   measuring on the wrist, end it on the Watch, and land on the real results
   screen with the score and curves. This is the core functionality and the
   thing a reviewer without a Watch cannot see for themselves.
6. **Settings > Delete account.** Apple explicitly requires the deletion flow
   to be shown for any app supporting account creation. Show the confirmation
   dialog. You do not have to complete it.

Do NOT need to show: user-generated content, content reporting, or blocking.
The app has none, and item 3 of the reply says so.

Upload the video in the App Store Connect reply. If it will not accept the file
size, put it on an unlisted link and include the URL in the reply text.
