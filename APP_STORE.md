# App Store metadata: 808 Meditate (1.1)

Everything App Store Connect asks for, with the reasoning behind each answer.
**Rewritten 2026-09-29 for 1.1**, against the Release build on branch `block`:

- Sessions run on the iPhone with or without a Watch; an Apple Watch adds
  heart, stillness and breathing readings and a score.
- **Premium only** (`Monetization.premiumOnly`): no free tier, nothing past the
  paywall without buying or restoring. **No trial on Monthly or Yearly**
  (`Monetization.freeTrial = false`); the two ladder plans carry the trials.
- **Friends is ON, as profiles only**: name, @username, optional photo and a
  practice summary. No posts, reactions, feed or comments.
- **Block, the Shop (hats and points) and Otto's chat are OFF** in Release
  (`FeatureFlags`). Block's three extensions and the Family Controls
  entitlement ship in the binary regardless; whether that stays is a founder
  decision in `RELEASE_CHECKLIST.md`.

The paste-ready values (description, promotional text, keywords, What's New,
review notes, age-rating answers) live in **`marketing/APP_STORE_PASTE.md` and
nowhere else**. This file holds the reasoning, the product setup and the
privacy label.

Em dashes are out of every user-facing block per the standing copy rule. This
header is internal and exempt, like code comments.

**Structure follows what works on comparable pages** (QUITTR, 33K ratings at
4.7, was the reference Melvin brought): a hook that names the pain, ALL-CAPS
section headers each carrying one idea, then the boilerplate. What we do NOT
copy from it: invented user counts, em dashes, and outcome claims we cannot
measure.

---

## Subtitle (30 max)

**A meditation habit that sticks** *(30 chars)*, 1.1.

Matches the website's headline ("The meditation app that makes it stick") and
what the app now is: a habit app that happens to measure, not a measuring app.
It names the subject and states the positive.

**Superseded 2026-09-29:** "Score your meditation" (1.0, decided by Melvin
2026-08-24). A session started on the iPhone produces no score, and most 1.1
sessions will be phone sessions, so leading with the score would describe the
optional path as the main one.

## Name (30 max)

**`808 Meditate`**, REGISTERED 2026-08-30: this is the live App Store Connect
record. No colon: **`808: Meditate` was rejected as already in use**, and
dropping the colon cleared it, because Apple checks the exact string.

`CFBundleDisplayName` stays `808`, so the icon on the home screen reads 808
regardless. The store listing name and the springboard name are separate
fields and are meant to differ here.

**Why not the bare "808".** Three reasons, none of which depends on
availability:

1. **The name field is the heaviest ASO signal there is**, and "808" alone is a
   keyword we can never rank for. The 808 space on the App Store belongs to
   drum machines and bass synths. Nobody searching that string wants
   meditation.
2. **A searcher who sees "808" alone learns nothing.** Same rule the screenshot
   captions follow: the listing is met with no context.
3. **Trademark distance.** Roland's TR-808 is a live mark in music hardware;
   "808 Meditate" lands the name unambiguously in wellness.

Do not spend the name on words already carried elsewhere. Apple counts each
token once across name, subtitle and keywords.

## Seller / parent company

**Lock Out Inc.**, a Delaware corporation, D-U-N-S 149914479. This exact string
is the App Store seller name, the party named in the privacy policy and terms,
and the attribution shown in the app's Settings screen. It must match the Apple
Developer enrolment character for character.

## Category

Primary **Health & Fitness** · Secondary **Lifestyle**

## Promo text and description

**Both live in `marketing/APP_STORE_PASTE.md` and nowhere else.** One source,
because copies drift and the drifted copy is the one that gets pasted.

**The 1.1 rewrite is done (2026-09-29).** What it follows:

- It opens on the reader's own problem in their words ("easy to start and hard
  to keep doing"), then Otto, then the practice. Not on a score.
- **An Apple Watch is described as something that adds evidence, never as a
  requirement.** No "requires a paired Apple Watch" line anywhere.
- **Friends is described as it is**: profiles, usernames, practice summaries,
  visible to anyone who looks up the username. Never posts or a feed.
- **Bring-your-own-audio is stated honestly.** A phone session asks the person
  to keep 808 open (more than 10 seconds away and it will not count), so the
  copy says to start the other app's audio first, then begin in 808.
- **"More than fifty awards"**, not a count: the catalog holds 58, three score
  awards stay hidden until earned, and a fixed number caps a growing list.
- **Privacy is stated accurately**: body readings stay on the iPhone; analytics
  are pseudonymous and never carry a body measurement. It no longer says
  "anonymous", because the analytics install ID and the IP-derived coarse
  location are collected (see the label below).
- **The subscription block is REQUIRED** for auto-renewables (title, length,
  price, renewal statement, and functional Terms of Use and Privacy links in
  the metadata itself). It is one of the most-rejected 3.1.2 items. The prices
  there must match App Store Connect exactly; change both or neither.

**If Block ships in a later version, lead with it.** Its App Review purpose
(Apple's purpose 2 for Family Controls, individuals managing their own device
use) requires the listing to describe device-usage management as a real part
of the app, not a footnote. Draft opening for that version:

> Meditation is easy to start and hard to keep doing. 808 helps you build the
> habit: Otto, your companion in the app, keeps you company and holds your
> most distracting apps until you've meditated. Pick your apps, pick your
> window, and get on with your day the moment you're done.

Never describe Block as parental control anywhere in the listing; it is
self-management, and the wrong word is the kind of thing App Review checks the
copy against the binary for.

### Optional testimonial block

Only if we are comfortable running beta-tester quotes. These are **real,
verbatim, from the survey**. **All three describe Watch sessions from the 1.0
era**; if used in 1.1, place them under the Apple Watch section, never as a
claim about phone sessions, and label them as early testers, never as
"millions of users".

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

`mindful,relax,breathwork,timer,streak,guided,nature,sounds,rain,528hz,solfeggio,theta,friends`
*(92 chars, in the paste sheet.)*

Changed for 1.1: `tracker` and `stillness` out (measurement is no longer the
lead), `timer`, `nature`, `sounds` and `friends` in. **`binaural` out, `rain`
in (2026-09-29, second pass):** no code path passes headphones, so every tone
plays isochronic and a binaural beat is unreachable in the app. Each word left
is true of the build: `breathwork` is the guide's breathing techniques (box
breathing, 4-7-8) and the "Breath work" technique in the session log; `theta`
is the Deep Meditation tone ("Theta, about 6 Hz"); `528hz` is Manifest;
`solfeggio` names the 528, 852 and 963 Hz tunings; `rain` is a nature sound;
`calm` is also the name of the alpha tone. Do not add HRV or
coherence: we do not ship either, and keywords promising absent features invite
a 2.3.7 look. Do not add "Apple Watch" or any other company's mark.

## Screenshots (6.9" required, 1320x2868)

**The committed set at `marketing/appstore/` is the 1.0 app and must be
re-shot from a Release 1.1 build** (`RELEASE_CHECKLIST.md`, item R6). It shows
the deleted dark theme, the retired flower mark, the Search tab, a
seventeen-award shelf and Watch-only captions ("Your Apple Watch knows"). The
proposed 1.1 order and captions are in the paste sheet.

`tools/store_shots.swift` composes the frames. Captions name their subject per
the standing rule. The 1.0 table below is kept for the record only.

| # | File (1.0) | Headline | Subhead |
|---|---|---|---|
| 1 | 01-score | Did that actually work? | Your Apple Watch knows. 808 tells you. |
| 2 | 02-evidence | See what your body actually did | Heart rate, stillness and breath, minute by minute |
| 3 | 03-habit | Every session, on one calendar | Your streak, your history, your practice score |
| 4 | 04-share | Share it with your friends. | Your real graphs and your streak, on one card. |
| 5 | 05-audio | Bring your own meditation | Or use the guided journey, tones and nature sounds |
| 6 | 06-awards | A sharper mind. A calmer one. | What a steady meditation practice is shown to do. |
| 7 | 07-journey | Your practice, adding up. | Streak, hours, awards, and every session logged. |
| 8 | 08-guide | Learn different techniques | Explained plainly, easiest first |

**Rules the 1.0 captions taught, still binding:** do not tell the reader what
they lack, and never set up a loser for the copy to beat ("Watch the habit take
hold" implied they had no practice; "Share the proof, not a caption" argued
with a behavior nobody has). Name the subject. No outcome claim on an image
(no room for the "this is research on meditation, not on 808" caveat).

### Apple Watch (separate required set, we ship a Watch app)

`marketing/appstore/watch/`, 416x496 (Series 11 46mm, an accepted size),
uploaded **raw, no caption frame**. **Re-shoot both from the current Watch app**
with the 1.1 build (item R6).

Two gotchas worth keeping:

- **watchOS ignores `simctl status_bar override`**, so the real clock shows.
  Apple does not require 9:41 on watch screenshots.
- **An unpaired watch simulator draws a red disconnected-phone glyph in the
  status bar.** Pair the watch and phone simulators (`xcrun simctl pair <watch>
  <phone>`) and wait for `connected`, not just `active`.

## In-app purchases, exactly as they must stand for 1.1

Product IDs must match `Store.ProductID` character for character: the app
fetches these strings and a typo shows as "nothing for sale", not an error.
**Only `monthly` and `yearly` decide whether the store is "ready"**
(`ProductID.core`): if either fails to load, the app stays open rather than
showing a paywall that cannot sell, which a reviewer reads as "the paywall is
missing". The two ladder products are optional to that check: until they load,
the "No, I don't want to pay" link simply does not appear.

**Subscription group.** Every auto-renewable, the ladder plans included, sits
in ONE group so a person can move between them without double-paying.

- Reference name (internal): `808 Membership` (can stay).
- **Group display name (USER VISIBLE, in Manage Subscriptions): recommend
  `808 Premium`.** The app calls the subscription "808 Premium" (the paywall's
  "808 Premium is $7.99 a month or $29.99 a year" line, the share-card lock,
  the Block screen), and the 1.0 group was named `808 Membership`. One name
  everywhere a customer sees it. The group's localization can be edited.
- Custom App Name: leave BLANK, so the sheet uses "808 Meditate".

**Rank (level) in the group**, top to bottom. Rank decides upgrade, downgrade
or crossgrade:

1. Yearly (and yearly50, which is not sold)
2. Monthly and Monthly with free trial (same level: same price, same length)
3. Half price monthly

**Introductory-offer eligibility is per GROUP, not per product.** Someone who
used any free trial in this group (including 1.0's 7-day trial) is not eligible
for another. The app reads eligibility (`Store.freeTrialDays(for:)`), so a rung
shown to an ineligible person says what it costs from today instead of
promising free days. Nothing to configure; worth knowing when a sandbox tester
"doesn't see the trial".

**The products:**

| Product ID | Type | Duration | Price | Introductory offer | Where the app sells it | Attach to 1.1? |
|---|---|---|---|---|---|---|
| `com.lockout.meditate808.monthly` | Auto-renewable | 1 month | $7.99 | **None. Delete the 7-day free trial** | Paywall | Yes |
| `com.lockout.meditate808.yearly` | Auto-renewable | 1 year | $29.99 | **None. Delete the 7-day free trial** | Paywall | Yes |
| `com.lockout.meditate808.monthlytrial` | Auto-renewable | 1 month | $7.99 | Free trial; length set here (the app reads it; `808.storekit` uses 3 days) | Ladder, rung 1 | **Yes, new** |
| `com.lockout.meditate808.monthly50` | Auto-renewable | 1 month | $3.99 | Free trial, 3 days | Ladder, rung 2 | **Yes, new** |
| `com.lockout.meditate808.lifetime` | Non-consumable | n/a | $99.99 | None | **No screen sells it; restore only** | No (already approved with 1.0) |
| `com.lockout.meditate808.yearly50` | Auto-renewable | 1 year | $29.99, first year $14.99 | Pay up front | **No screen sells it** | **No** |

**Why the trials had to go from Monthly and Yearly.** While an introductory
offer exists on a product, Apple's purchase sheet grants it whatever the app's
screen says. The paywall no longer mentions a trial, so a live 7-day offer
would make the screen and the sheet disagree: a 3.1.2 mismatch.

**Lifetime.** Existing Lifetime buyers must keep restoring it, so **never
delete the product.** Whether to also remove it from sale is the founders'
call (`RELEASE_CHECKLIST.md`). Removing a product from sale stops new
purchases; confirm in App Store Connect's help that previous buyers can still
restore before doing it.

**yearly50** is a leftover of the 2026-09-22 ladder. A product attached to a
submission that no screen sells makes a reviewer hunt for it (a 2.1 "we could
not locate the in-app purchase" reply). Leave it unattached.

**Localized display name and description** (user visible in the purchase
sheet, in Settings > Subscriptions and on receipts; 30 and 45 characters). The
1.0 descriptions said "Every session measured and scored", which is false for
a phone session. Replace them:

| Product | Display name | Description |
|---|---|---|
| monthly | `Monthly` | `All of 808, billed every month.` (31) |
| yearly | `Yearly` | `All of 808, billed once a year.` (31) |
| monthlytrial | `Monthly with free trial` | `All of 808, monthly after a free trial.` (39) |
| monthly50 | `Half price monthly` | `All of 808 at half the monthly price.` (37) |
| lifetime | `Lifetime` | `All of 808 with one payment.` (28) |

With the group named `808 Premium`, Manage Subscriptions reads "808 Premium,
Monthly". `808.storekit` uses the same names except `Half price` for
monthly50; align it when convenient.

**Review screenshots** (one per product, required):

- monthly and yearly: the paywall with the plans. **The committed
  `marketing/appstore/iap/paywall-review.png` is from 2026-09-01** and shows the
  old paywall; re-shoot it from the 1.1 Release build (the valley paywall,
  "Keep Otto glowing.").
- monthlytrial: the first rung's sheet ("No worries. Try it free first.").
- monthly50: the second rung's sheet ("Then have 808 at half price.").

**Small Business Program**: enrolled with the agreements (15% instead of 30%).

## Age rating (1.1, Friends ON)

Apple's questionnaire changed shape in 2025: tiers **4+, 9+, 13+, 16+, 18+**,
organized as In-App Controls, Capabilities, Mature Themes, Medical or Wellness,
Sexuality or Nudity, Violence, and Chance-Based Activities. Source:
developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/.
**Answer every question in App Store Connect fresh at submission**; this is our
worked answer, not a substitute for reading the live form.

| Question | Answer | Why |
|---|---|---|
| Parental Controls | **No** | Nothing in 1.1 manages anyone's device. If Block ships later, it still manages only the device it is set up on, for the person using it. |
| Age Assurance | **No** | 808 has no age-verification mechanism. The onboarding age question is self-reported and optional. |
| Unrestricted Web Access | **No** | No in-app browser shows arbitrary web content. Links to our own site open in Safari. |
| User-Generated Content | **Yes** | Display names, @usernames and profile photos that anyone who looks up a username can see, and report text. |
| Social Media | **Yes** | Friends: public profiles found by username, friend requests, and each friend's practice summary. |
| Social Media Disabled for Users Under 13 | **No** | No age gate exists, so we cannot claim a technical safeguard. The Terms require 13+; that is a policy floor, not an in-app control. |
| Messaging and Chat | **No** | No messages, comments or posts between users. |
| Advertising | **No** | No ad SDK, no ad serving. |
| Profanity or Crude Humor | **No** | |
| Horror or Fear Themes | **No** | |
| Alcohol, Tobacco, or Drug Use or References | **No** | |
| Health or Wellness Topics | **Yes** | The guide's meditation techniques and the practice itself: self-care content. |
| Medical or Treatment Information | **Infrequent** | `SCIENCE.md`, bundled and readable in the app, cites meditation research on cardiovascular risk (the AHA scientific statement, Levine 2017) and meta-analyses on anxiety and depression. It says plainly that 808 measures nothing cardiovascular, but the content is there, so None would be the evasive answer. |
| Sexuality or Nudity (all levels) | **No** | |
| Violence (all levels) | **No** | |
| Chance-Based Activities (all kinds) | **No** | |

**Expected tier: 13+.** UGC and Social Media are the Yeses that set it;
moderation is built (a text filter on names and handles, photo screening,
Report and Block on every profile). Confirm the computed tier in the form.

**Both UGC and Social Media flip back** if `FeatureFlags.friendsInRelease` is
ever turned off for a build. Re-answer the questionnaire for that build.

**Superseded, kept for the record:** 1.0 answered UGC No, Social No, Wellness
Yes, Medical None (4+), when nothing a user created could reach another user
and the Science page was not weighed. The 2026-09-23 draft of this section
justified UGC and Social with "Friends posts" and "a feed of friends' posts
with reactions"; posts were removed 2026-09-27.

## App Privacy (nutrition labels), 1.1

**Ten data types, every one linked.** Written 2026-09-29 from the decided
manifest list, then **checked the same day against
`Coherence/PrivacyInfo.xcprivacy` once the manifest change landed: every type,
linkage and purpose matches.** Second pass the same day: the four PostHog-only
rows flipped to Linked = Yes with the manifest (see the notes below the
table). Check once
more against the manifest in the build you archive before publishing the label
(`RELEASE_CHECKLIST.md`, item R9). The manifest is the source of truth; a label
that does not match it is a review flag by itself. The Watch app's manifest
declares no collected data.

| Category | Linked to you | Used to track you | Purpose | What it is |
|---|---|---|---|---|
| Identifiers → User ID | **Yes** | No | App Functionality, Analytics | The Friends @username and profile (App Functionality), and the analytics install ID sent with every event (Analytics). |
| Location → Coarse Location | **Yes** | No | Analytics | PostHog derives an approximate city, region and country from the IP address each event arrives from. |
| Usage Data → Product Interaction | **Yes** | No | Analytics | Named events only: sessions started and completed (with coarse length and streak bands), onboarding screens, paywall views, Friends actions, Watch measuring switched on or off. |
| Usage Data → Other Usage Data | **Yes** | No | Analytics | The device and app metadata PostHog's SDK attaches to every event (iPhone model, iOS version, app version and build, TestFlight or not, language, time zone, screen size, Wi-Fi or cellular), the install, update, open and close lifecycle events, and whether a Watch is paired. |
| Purchases → Purchase History | **Yes** | No | Analytics | Which plan was bought, restored or lapsed, and whether the install currently subscribes. No payment details ever travel this path, so Financial Info stays off. |
| Other Data → Other Data Types | **Yes** | No | App Functionality | The Friends practice summary (sessions and minutes in the last 7 days, current streak, total sessions, last session date), the profile's created and first-session dates, and the friend edges and blocks a person writes. |
| Contact Info → Name | **Yes** | No | App Functionality | The display name on a Friends profile. |
| Contact Info → Email Address | **Yes** | No | Developer's Advertising or Marketing | The old no-Watch waitlist. No 1.1 screen asks for it, but an email can still reach the waitlist sheet two ways: a saved onboarding record from an earlier version (`WaitlistClient.submit`) and a queued sign-up that flushes on launch (`WaitlistClient.flush`). It stays declared while the code can send one. |
| User Content → Photos or Videos | **Yes** | No | App Functionality | The optional Friends profile photo. |
| User Content → Other User Content | **Yes** | No | App Functionality | The text of a report someone files. |

Tracking question at the end: **No.** No IDFA, no ad networks, no data brokers,
nothing linked across apps or websites.

**Notes on rows that are easy to get wrong:**

- **One User ID entry, linked.** The 2026-09-23 plan declared two User ID rows
  with opposite linkage (the analytics ID not linked, the username linked).
  App Store Connect takes one answer per data type, so the row is the union:
  linked, because the @username identifies a person, with both purposes.
- **Every PostHog row is Linked = Yes (2026-09-29, second pass).** Apple
  treats data tied to a pseudonymous identifier as linked to the user, and
  every event from one install carries the same random `distinct_id`. The
  first pass marked Coarse Location, Product Interaction, Other Usage Data and
  Purchase History not linked; that answer only holds for data with no
  identifier at all. The privacy policy says the same thing in words: the
  data is tied only to that random identifier, never to a name, email, Apple
  ID or Friends username.
- **The IP-derived location is collected**, because PostHog resolves it
  server side from each event's IP address. Whether PostHog keeps the IP or
  discards it after GeoIP is a founder decision (`RELEASE_CHECKLIST.md`); the
  privacy policy now discloses approximate location either way.
- **Health & Fitness is correctly ABSENT.** Heart rate, breathing, stillness,
  scores and every curve stay on the device (5.1.3(ii)); HRV is no longer
  read. The practice summary counts sessions and minutes and carries no
  measurement, so it is Other Data, not Health.
- **Session photos and videos are not collected.** They sync only through the
  person's private iCloud database, which we cannot read. The profile photo is
  the only picture in the public database.
- **No Screen Time or Block row.** Nothing Block touches leaves the device, and
  Block is off in 1.1.
- **No Diagnostics row, and the code guarantees it.** PostHog's crash capture
  installs only when the app switches it on, and `Analytics.swift` sets it off
  explicitly. **Xcode's privacy report will still show Crash Data**, because
  PostHog's bundled crash-reporter framework ships its own privacy manifest
  declaring it. That entry describes what the framework could collect, not
  what 808 turns on: crash capture is off, so no Diagnostics row goes on the
  label. Whoever fills in the label from the Xcode report should expect that
  line and leave it out.

**Superseded 2026-09-29:** the 2026-09-23 table ("Eight data types"), which
listed two User ID rows and described photos and videos on Friends posts.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is in the Info.plist, so Connect should
not ask. If it does: standard Apple encryption only, exempt.

## Review notes

**The paste-ready notes are in `marketing/APP_STORE_PASTE.md`.** Why they say
what they say:

- **Subscription first.** A premium-only app whose reviewer cannot find the way
  past the paywall is rejected under 2.1. The press-and-hold on "Ready to take
  control?" is the one step a reviewer could mistake for a stuck screen, so the
  notes spell it out.
- **The ladder is described as returning to the paywall**, because each rung
  sells nothing itself: it preselects its plan and hands back to the screen
  that carries price, renewal, Restore, Privacy and Terms (3.1.2).
- **1.0 users meet the paywall** (decided 2026-09-25); past buyers keep access.
  Said up front so a reviewer with an old install is not surprised.
- **The rating prompt inside onboarding is disclosed**, unconditional and not
  tied to an answer. Whether it stays there is a founder decision.
- **The 10-second rule is disclosed** so a reviewer who locks the phone
  mid-session reads the "won't count" screen as designed, not as a bug.
- **Friends needs iCloud** and has no posts, comments or messages. The
  reviewer handle (`@REVIEWER_HANDLE` until the founders create it) gives them
  a profile to find, request, report and block without a second device.
  **Search needs a profile first** (the Friends tab opens on Create your
  profile until one exists), so the notes say to create one before searching.
- **Account deletion is in two places**: Settings, and the Account link on
  the LAUNCH paywall (the one an app that has finished onboarding opens to
  without a subscription, such as a 1.0 install that updates), so someone
  locked out by the paywall can still delete their account (5.1.1(v)).
  ~~The onboarding paywall has no Account link; nobody there has an account
  yet.~~ **Corrected 2026-09-29 (second pass):** the onboarding paywall also
  shows the Account link on a device that already holds an account's data.

**Added in the second pass, 2026-09-29, each checked against the code:**

- **The sandbox account must hold no active 808 subscription.** A payer is
  sent straight past the onboarding paywall, so a reviewer on a subscribed
  sandbox account would never see it.
- **Introductory-offer eligibility is explained**, because a sandbox account
  that already took a free trial in the group is not offered the trial rung
  (`available(_:)` in `OnboardingOffer.swift`) and sees the half price rung
  without its trial. Without the sentence, a reviewer reads a missing rung as
  a broken ladder.
- **"Plans aren't loading"** is the Release paywall's state when the core
  products do not load; the app retries on the next launch or return to the
  foreground.
- **With Apple Watch is dimmed without a paired Watch** ("Needs a paired
  Apple Watch."); the first draft said it "carries on as an iPhone session",
  which is the fallback for a Watch that never answers, not what a reviewer
  with no Watch sees.
- **The notification ask is conditional**: a timed session asks only if
  onboarding has not already asked (`SessionEndNotice`).
- **The AUDIO paragraph is gone**; the Content Rights answer covers it.

**If Block ships in the build**, append this paragraph to the notes. The notes
are 3,853 characters with the `@REVIEWER_HANDLE` placeholder in them
(2026-09-29) and Apple's limit is 4,000, so the paragraph (580 characters)
needs about 440 cut: drop the paragraph that begins "Apple allows one
introductory offer" and the sentence that begins "After the paywall:", which
brings them to about 3,955 plus whatever the real handle adds over the
placeholder's 16 characters. Count before pasting.

```
BLOCK (part of 808 Premium) uses Apple's Family Controls with individual authorization: a person manages their own iPhone, and it is not a parental control. In the Block tab, Screen Time permission is asked on first use, then apps are picked with Apple's picker. A held app shows Apple's shield. "Ask Otto" sends a notification that opens a short screen from Otto, ending in a meditation (five minutes or more opens the apps for the rest of that window) or "Not now" for 10, 20 or 30 minutes. Nothing from Screen Time leaves the device. A screen recording is available on request.
```

**If Block stays off but its extensions and entitlement stay in the binary**,
that is the founder decision in `RELEASE_CHECKLIST.md` (2.3.1 treats hidden or
dormant features as grounds for rejection). The recommendation is to ship
Block or strip it, not to explain a dormant feature in the notes.

Earlier notes (1.0's "a paired Apple Watch is required" note and the
2026-09-23 draft that described posting, reactions and a trial in Settings)
are deleted from this file so neither can be pasted by mistake; both are in
git history.

## What's New (v1.1)

**In `marketing/APP_STORE_PASTE.md`.** It names Otto, phone sessions with or
without a Watch, Record one, Friends as it is, that 808 is now a subscription
with existing subscribers and Lifetime owners keeping access, and the one-line
note that past Watch scores were rescored (`RELEASE_CHECKLIST.md`, "1.1
RESCORES EVERY EXISTING USER'S HISTORY"; migrations `scoreBackfillDone.v8` and
`.v9`).

## What's New (v1.0), for the record

> Welcome to 808. Meditate however you like, wearing your Apple Watch, and see
> what your body actually did afterwards: stillness, heart rate settling, and
> your breathing, scored out of 100. A guided journey, frequency and nature
> sounds, eight techniques explained plainly, streaks, awards and a session
> card you can share.

---

## Capabilities on the shipping App IDs (1.1)

Read from the entitlements files 2026-09-29. `tools/archive.sh` checks the
archive; this is what it should find.

| App ID | Capabilities |
|---|---|
| `com.lockout.meditate808` | HealthKit, Sign in with Apple, iCloud (CloudKit, container `iCloud.com.lockout.meditate808`), Push Notifications, App Groups (`group.com.lockout.meditate808`), Family Controls (Distribution), Time Sensitive Notifications, Sensitive Content Analysis |
| `com.lockout.meditate808.watchkitapp` | HealthKit |
| `com.lockout.meditate808.monitor` | Family Controls (Distribution), App Groups |
| `com.lockout.meditate808.shield` | Family Controls (Distribution), App Groups |
| `com.lockout.meditate808.shieldaction` | Family Controls (Distribution), App Groups |

Time Sensitive Notifications is refused on an app extension; it lives on the
app only. Whether the three Block extensions and Family Controls ship in 1.1
while Block is off is a founder decision (`RELEASE_CHECKLIST.md`).

---

## HISTORICAL: what had to happen before 1.0 could go live

**All done by the 1.0 release on 2026-09-10.** Kept for the record; nothing
below is an open task.

1. **Organization account active.** Done 2026-09-01 (Melvin's account
   converted in place; Team ID `WLZQLLHUB3` preserved).
2. **StoreKit products created** (`monthly`, `yearly`, `lifetime`). Done;
   the 1.1 product set is in "In-app purchases" above.
3. **The iCloud promise.** Verified 2026-09-12 once the Production schema was
   promoted (sessions and streak roam; health results never do, by design).
4. **Legal entity `Lock Out Inc.`** Swapped 2026-08-25. Still owed and not a
   launch gate: the LLC to corp assignment (`LEGAL_ACTION_ITEMS.md`).
5. to 10. Age rating, privacy labels, screenshots, URLs, capabilities and
   TestFlight: done for 1.0. The 1.1 versions of each are in the sections
   above and in `RELEASE_CHECKLIST.md`.

## HISTORICAL: enrolling the Organization

**Done 2026-09-01.** Melvin's Individual membership was converted to an
Organization in place, which **preserved the Team ID (`WLZQLLHUB3`)** and the
production App ID and iCloud container already registered on it. Aziz joined as
Admin at no cost. His TestFlight beta stayed on his personal team under
`com.azizmahmud.808`.

**The one rule from this that still binds:** never register the production
bundle IDs on any other team. An App ID consumed by an App Store Connect record
can never be reused, on any team.

---

## Things deliberately not in the listing

- **No "first app to" claim.** Apple's own Mindfulness app already logs heart
  rate during sessions, so "first to measure meditation" is unverifiable. Left
  out on purpose.
- **No user counts, no press logos, no awards.** We have none of them yet.
- **No health outcomes.** No sleep, anxiety, focus or blood-pressure claims,
  even in the softest form, and no theta or brainwave-state claim about the
  user.
- **No "no Watch required" line.** The positive version ("An Apple Watch is
  optional") says the same thing without defining the product by an absence.
