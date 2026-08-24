# App Store metadata — 808 (v1.0)

Everything App Store Connect asks for, pre-written, with character limits
checked. Rewritten 2026-08-24 for launch: the Aug 11 draft predated awards, the
guide, the track rename, and PostHog going live, and its privacy label was
factually wrong as a result.

Em dashes are out of every user-facing block per the standing copy rule. This
header is internal and exempt, like code comments.

**Structure follows what works on comparable pages** (QUITTR, 33K ratings at
4.7, was the reference Melvin brought): a hook that names the pain, ALL-CAPS
section headers each carrying one idea, real quotes, then the boilerplate. What
we do NOT copy from it: invented user counts, em dashes, and outcome claims we
cannot measure.

---

## Subtitle (30 max)

**Score your meditation** *(21 chars)*

Decided by Melvin 2026-08-24: the listing leads with the scoring angle, the
same pitch as the website ("the first app that scores your meditation from your
own body"). Manifestation survives as a feature in the description and as a
keyword, so nothing is lost by not leading with it. Alternatives considered and
rejected: "Proof your meditation worked" (28), "Meditation for manifestation"
(28, the old draft's lead).

## Name (30 max)

**808**

The App Store Connect record is **"808: Meditate"** because bare "808" is
taken. `CFBundleDisplayName` stays 808, so the icon reads 808 either way.

## Category

Primary **Health & Fitness** · Secondary **Lifestyle**

## Promo text (170 max, editable without review)

> Meditate however you like. Your Apple Watch measures how far your body
> settled, and 808 scores it out of 100 when you finish.

*(139 chars)*

## Description (4000 max)

> Most people meditate blind. You sit, you follow your breath, and afterwards
> you have no idea whether anything actually happened. 808 answers that.
>
> Wear your Apple Watch and meditate however you like. When you finish, 808
> shows you what your body did while you were there, and gives you one score
> out of 100.
>
> **WHAT 808 MEASURES**
> Three signals, all from the Watch already on your wrist. How still your body
> became. How far your heart rate settled across the session. And your
> breathing rate, read from the small tilt of your wrist when you slow your
> breath down. No chest strap, no special posture, no setup.
>
> **ONE SCORE, NOT A GUESS**
> Every session ends with a practice score built from how deep you got and how
> long you held it. Thirty restless minutes will never beat five settled ones.
> Nothing is shown while you practise, because a live number is just one more
> thing to chase. The evidence comes after.
>
> **BRING YOUR OWN MEDITATION**
> Already have a teacher you like on YouTube or Spotify? Start a session and
> play whatever you want in any other app. The Watch keeps measuring. There is
> nothing to switch to and nothing to give up.
>
> **OR USE OURS**
> A 25 minute guided journey, professionally narrated. Brainwave paced tones
> for delta, theta and alpha. Traditional tunings at 432, 528, 852 and 963 Hz,
> each over an ambient bed. Rain, ocean, forest and campfire.
>
> **LEARN HOW TO ACTUALLY MEDITATE**
> Eight techniques written in plain language, easiest first, from your first
> ever sit through to visualisation practice.
>
> **A HABIT YOU CAN SEE**
> Streaks, a calendar of practised days, your full session history, and
> seventeen awards. Earned awards are yours for good, even if a streak breaks.
>
> **SHARE THE PROOF**
> Turn any session into a card carrying your real graphs, ready for your story.
>
> **PRIVATE BY DESIGN**
> Your heart rate, your breathing and your scores are computed on your devices
> and stay on your device. They are never uploaded, and we cannot see them. We
> use basic anonymous analytics to learn which screens people use, and no
> biometric data is ever part of it. No ads. No data sales. Sign in with Apple
> is the only sign-in and it is optional.
>
> **HONEST SCIENCE**
> The stillness and breathing measurements are grounded in peer-reviewed
> research on wrist-worn motion sensing. Traditional frequencies are labelled
> as tradition, not sold as proven. 808 is a wellness app, not a medical
> device, and does not diagnose, treat or prevent any condition.
>
> Requires a paired Apple Watch to measure a session.

*(~2,300 chars, leaving room for the testimonial block below if used.)*

### Optional testimonial block

Only if we are comfortable running beta-tester quotes at launch. These are
**real, verbatim, from the survey**, and are the same six on the website. If
used, add above SUBSCRIPTION INFORMATION and label them honestly as early
testers, never as "millions of users".

> **FROM EARLY TESTERS**
>
> "I've started and quit meditating probably six times. The thing that always
> got me was having no idea if anything was happening. First session with this
> showed my heart rate dropped 14 beats when i slowed my breathing down and it
> showed me where on the graph."
>
> "Big one for me is I already have meditations I like on YouTube. This just
> runs in the background on my watch and measures. Don't have to switch to
> their library or listen to some voice I don't like."
>
> "Skeptical it could pick up breathing from a wrist but it caught me slowing
> down at the start of a session and then speeding up later on, surprisingly
> accurate"

## Keywords (100 max, comma-separated, never repeat name/subtitle words)

`breathwork,binaural,frequency,528hz,solfeggio,theta,stillness,calm,guided,tracker,streak,mindful`

*(96 chars.)* Do not add HRV or coherence: we do not ship either, and keywords
promising absent features invite a 2.3.7 look.

## Screenshots (6.9" required, 1320x2868)

Generated and committed at `marketing/appstore/`. Real screens from the iPhone
17 Pro Max simulator, dark theme, 9:41 status bar, composed by
`tools/store_shots.swift`. Captions name their subject per the standing rule.

| # | File | Headline | Subhead |
|---|---|---|---|
| 1 | 01-score | Proof your meditation landed | A score out of 100, measured on your wrist |
| 2 | 02-evidence | See what your body actually did | Heart rate, stillness and breath, minute by minute |
| 3 | 03-habit | Every session, on one calendar | Your streak, your history, your practice score |
| 4 | 04-audio | Bring your own meditation | Or use the guided journey, tones and nature sounds |
| 5 | 05-awards | Awards you keep for good | A broken streak never takes one back |
| 6 | 06-journey | Watch the habit take hold | Streaks, hours practised and awards earned |
| 7 | 07-guide | Learn how to actually meditate | Eight techniques explained plainly, easiest first |
| 8 | 08-share | Share the proof, not a caption | A card built from your own session |

The first three are what appear in search results, so they carry the argument:
proof, then the evidence behind it, then the habit.

### Apple Watch (separate required set, we ship a Watch app)

Captured at `marketing/appstore/watch/`, 416x496 (Series 11 46mm, an accepted
size). Uploaded **raw, no caption frame**: the watch canvas is too small to
carry text above the device the way the iPhone set does, and plain screenshots
are the norm on watch listings.

| # | File | Screen |
|---|---|---|
| 1 | 01-begin | Start: the mark, the gold Begin orb, the chosen sound |
| 2 | 02-measuring | Live: elapsed time inside the teal orb, End |

Two gotchas worth keeping, both cost time:

- **watchOS ignores `simctl status_bar override`**, so the real clock shows.
  Apple does not require 9:41 on watch screenshots.
- **An unpaired watch simulator draws a red disconnected-phone glyph in the
  status bar**, which reads as an error state in a listing. Fix by pairing the
  watch and phone simulators (`xcrun simctl pair <watch> <phone>`) and waiting
  for the pair to report `connected`, not just `active`.

## Age rating

Apple's 2025 questionnaire is answered at submission. Honest answers: wellness
content without medical advice, no unrestricted web, no user-generated content,
no gambling. Expect the lowest tier. The questionnaire cross-references the
metadata, so nothing above may claim a health outcome.

## App Privacy (nutrition labels) — CHANGED, do not copy the old answer

**Product Interaction must now be declared, linked to nothing, not used for
tracking.** PostHog went live 2026-08-17, so the previous "Data Not Collected"
answer is no longer true. Declare:

- **Usage Data → Product Interaction**: collected, NOT linked to identity, NOT
  used for tracking.
- Nothing else. Health results never leave the device (device-local store,
  excluded from CloudKit per 5.1.3(ii)); the account and session log sync only
  to the user's private CloudKit database, which we cannot read.

`PrivacyInfo.xcprivacy` in both targets already declares
ProductInteraction/Analytics/not-linked/not-tracking, so the manifest and the
labels agree. If they ever disagree, that is the rejection.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is in the Info.plist, so Connect should
not ask. If it does: standard Apple encryption only, exempt.

## Review notes (paste into the App Review notes field)

> 808 measures meditation sessions using Apple Watch (heart rate and motion via
> a .mindAndBody workout). A paired physical Apple Watch is required to record
> a session; everything else (onboarding, sounds, guide, history, settings) is
> fully reviewable on iPhone alone. Sign in with Apple is the only sign-in and
> it is optional, so no demo account exists or is needed.
>
> Health data: session results are computed on-device and stored only
> on-device, in a store excluded from CloudKit sync, per guideline 5.1.3(ii).
>
> Audio licensing: the guided narration was commissioned with a commercial
> licence; the tones are synthesised at runtime; the ambient beds and nature
> recordings were generated under commercial licence.

## What's New (v1.0)

> Welcome to 808. Meditate however you like, wearing your Apple Watch, and see
> what your body actually did afterwards: stillness, heart rate settling, and
> your breathing, scored out of 100. A guided journey, frequency and nature
> sounds, eight techniques explained plainly, streaks, awards and a session
> card you can share.

---

## What still has to happen before this can go live

Ordered by what blocks what. Items 1 to 4 are gates; nothing else matters until
they clear.

1. **Organization account active.** See the walkthrough below. Every remaining
   item hangs off this, because the shipping bundle IDs
   (`com.lockout.meditate808*`) must be registered there and never on a
   personal account. The TestFlight beta runs under Aziz's personal
   `com.azizmahmud.808`, which cannot become the store build.
2. **StoreKit products created** under the Org account with the exact IDs in
   `Store.ProductID` (`.monthly`, `.yearly`, `.lifetime`), prices per the
   agreed ladder. Until products load, `RootView` leaves the app unlocked, so a
   store build with no products is a free app. Verify buy, expire and re-lock
   against `808.storekit` before submitting.
3. **The iCloud promise has to become true or come out of the copy.** The
   privacy policy and the sign-in screen both tell users their sessions survive
   a new phone via private iCloud sync, and sync has never demonstrably run
   once. Shipping that sentence to paying strangers is the one genuinely
   dishonest thing left in the product. Either fix sync (the diagnostic panel
   built for exactly this has still never been read) or soften both strings.
   The iCloud freeze was for the beta and lifts when we move to the Org
   account, since that build re-enters review anyway.
4. **Legal entity swap, now unblocked.** The C-corp exists, has its EIN, and is
   the entity the approved D-U-N-S was issued to (confirmed 2026-08-24), so it
   is the entity that enrols and therefore the seller name on the App Store.
   The policy, terms and website footer all still name **LockOut LLC**. Change
   every mention to the corporation's exact registered name in one pass, and
   ask the attorney about assigning the app and the user data from the LLC to
   the corp (the ToS assignment clause and the policy's material-change notice
   both bear on it). **The name in those documents must match the name on the
   Apple enrolment**, or the listing contradicts its own legal pages.

Then, in Connect:

5. Age-rating questionnaire (new format, answered honestly).
6. App Privacy labels set to Product Interaction, per the section above.
7. Screenshots uploaded: the eight iPhone images in `marketing/appstore/` and
   the two Apple Watch images in `marketing/appstore/watch/`. Both sets are
   done and committed.
8. Support URL `https://meditate808.com/#support` (the anchor exists), marketing
   URL, privacy URL. The website is a **manual** Cloudflare Pages upload, so any
   copy change there has to be dragged in by hand; pushing to git deploys
   nothing.
9. Capabilities on the shipping App ID: HealthKit, Sign in with Apple, CloudKit,
   Push.
10. Internal TestFlight on the Org build, then external, then submit.

## Enrolling the Organization (the current blocker)

$99/year, at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/).
Enrol **on the web, not in the Apple Developer app**: the app route sets the
membership up as an auto-renewable subscription tied to a personal Apple
Account, which is the wrong shape for a company.

**Have ready before starting:**

| Field | Value | Watch out |
|---|---|---|
| Legal entity name | The C-corp's exact registered name | Must match D&B **character for character**, including "Inc." or "Corporation". A DBA or trade name is rejected outright, and this string becomes the **seller name shown on the App Store**. |
| D-U-N-S Number | The approved number | Allow up to 2 business days after D&B approval for Apple to receive the record. If enrolment says it cannot find you, that lag is usually why. |
| Work email | An address **on the company domain** | A gmail address is rejected. `melvin@meditate808.com` or similar via Cloudflare Email Routing, which already runs `support@`. |
| Website | `https://meditate808.com` | Must be live, functional, and on a domain tied to the entity. Ours qualifies. A social profile or a placeholder page does not. |
| Apple Account | **Two-factor enabled**, person of legal age | Use a NEW Apple Account owned by the company, never a personal one. The account holder controls the whole team forever, and moving it later is painful. |
| Legal authority | Owner, founder, or executive | Whoever enrols must be able to bind the corporation. If it is not an owner, Apple asks for a reference to confirm authority. |

**Then, in order:**

1. Enrol on the web with the fields above, and complete identity verification.
2. Wait for Apple to verify. They may phone the number on the D&B record, so
   make sure it reaches someone; some regions also require notarised documents.
3. Accept the Program License Agreement and pay the $99.
4. In App Store Connect, accept the **Paid Applications Agreement** and fill in
   banking and tax (the corp's EIN, and the US tax forms). **This is the step
   people forget**, and without it no paid app or subscription can sell, which
   would block the whole paywall.
5. Register the App ID `com.lockout.meditate808` with HealthKit, Sign in with
   Apple, CloudKit and Push, then the Watch App ID, then create the app record.
6. Add both cofounders as Admins, and set `DEVELOPMENT_TEAM` locally per the
   signing note in `CLAUDE.md`. The committed `project.yml` keeps
   `DEVELOPMENT_TEAM: ""`, so nothing personal lands in a commit.

**Do not register the production bundle IDs anywhere else while waiting.** An
App ID consumed by an App Store Connect record can never be reused, on any
team, which is exactly why the beta ships under a personal identifier.

## Things deliberately not in the listing

- **No "first app to" claim.** Apple's own Mindfulness app already logs heart
  rate during sessions, so "first to measure meditation" is unverifiable. The
  website's narrower claim (first to *score* a meditation from body signals) is
  defensible, but it is not worth spending review goodwill on. Left out for the
  third time on purpose.
- **No user counts, no press logos, no awards.** We have none of them yet.
- **No health outcomes.** No sleep, anxiety, focus or blood-pressure claims,
  even in the softest form, and no theta or brainwave-state claim about the
  user.
