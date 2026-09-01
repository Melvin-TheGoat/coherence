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

**`808 Meditate`** — REGISTERED 2026-08-30, this is the live App Store Connect
record. No colon: **`808: Meditate` was rejected as already in use**, and
dropping the colon cleared it, because Apple checks the exact string.

`CFBundleDisplayName` stays `808`, so the icon on the home screen reads 808
regardless. The store listing name and the springboard name are separate
fields and are meant to differ here.

**Why not the bare "808".** An earlier draft of this file said the bare name was
taken. That was never verified and should not have been stated as fact: App
Store Connect is the only authority. The reason to qualify the name anyway is
threefold, and none of it depends on availability:

1. **The name field is the heaviest ASO signal there is**, and "808" alone is a
   keyword we can never rank for. The 808 space on the App Store belongs to
   drum machines and bass synths (EGDR808, X808, LE01 Bass 808, Boom 808).
   Nobody searching that string wants meditation, and we would be competing for
   an audience that is not ours.
2. **A searcher who sees "808" alone learns nothing.** Same rule the screenshot
   captions follow: the listing is met with no context.
3. **Trademark distance.** Roland's TR-808 is a live mark in music hardware. A
   bare numeric "808" sitting in a music-adjacent search result is closer to it
   than "808: Meditate", which lands the name unambiguously in wellness. Still
   worth one question to the attorney, but the qualified name is the safer of
   the two.

Do not spend the name on words already carried elsewhere: the subtitle holds
"score" and "meditation", and `tracker` is in the keyword field. Repeating a
term across fields buys nothing; Apple counts each token once.

## Seller / parent company

**Lock Out Inc.**, a Delaware corporation, D-U-N-S 149914479. This exact string
is the App Store seller name, the party named in the privacy policy and terms,
and the attribution shown in the app's Settings screen. It must match the Apple
Developer enrolment character for character.

## Category

Primary **Health & Fitness** · Secondary **Lifestyle**

## Promo text and Description

**Both live in `marketing/APP_STORE_PASTE.md` and nowhere else.**

They used to be duplicated here, and the copies drifted: this file still
carried the technique count and the awards-are-kept line for a day after both
were cut, which is exactly how the wrong text gets pasted into Connect. One
source, and it is the paste sheet, because that is the file someone actually
copies from with the form open.

The reasoning behind the current copy is recorded at the top of that file: the
description opens on the problem rather than the score, checked against how
Athlytic, Gentler Streak, Balance and Muse open.

**The subscription block inside the description is REQUIRED** for
auto-renewables (title, length, price, renewal statement, and a functional
Terms of Use link in the metadata itself). It is one of the most-rejected 3.1.2
items. The prices there must match App Store Connect exactly; change both or
neither.

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
| 1 | 01-score | Did that actually work? | Your Apple Watch knows. 808 tells you. |
| 2 | 02-evidence | See what your body actually did | Heart rate, stillness and breath, minute by minute |
| 3 | 03-habit | Every session, on one calendar | Your streak, your history, your practice score |
| 4 | 04-share | Share it with your friends. | Your real graphs and your streak, on one card. |
| 5 | 05-audio | Bring your own meditation | Or use the guided journey, tones and nature sounds |
| 6 | 06-awards | A sharper mind. A calmer one. | What a steady meditation practice is shown to do. |
| 7 | 07-journey | Your practice, adding up. | Streak, hours, awards, and every session logged. |
| 8 | 08-guide | Learn different techniques | Explained plainly, easiest first |

Melvin's revision pass (2026-08-25): slide 2 opens on the FULL top of the
results page (score ring first, never mid-scroll) with the scrub callout
visible on the heart graph as a detail, and its caption stays the evidence
line: the scrub is a feature to glimpse, not the selling point of the first
screen a searcher sees. `PREVIEW_SCRUB=<minutes>` is the DEBUG hook that pins
the callout so a screenshot can hold it. Slide 5 sells the chase, not the
keeping (keeping is implied). Slide 7 names no count: the guide is a growing
list and a fixed number caps it.

The first three are what appear in search results, so they carry the argument:
the question, then the evidence that answers it, then the habit.

**Sharing moved to slide 4** (Melvin, 2026-09-01): it is the only organic
acquisition loop 808 has, so eighth was underselling it. Files are renumbered so
folder order matches upload order.

**Three captions were rewritten the same day, all for the same fault: assuming
something about the reader.** "Watch the habit take hold" implied they had no
practice yet, when most users already meditate. "Share the proof, not a caption"
invented a behaviour nobody recognises and then argued against it. And the
awards slide named thresholds ("ten straight days, a score of 90"), which read
as chores rather than reasons. The rule these all break: **do not tell the
reader what they lack, and never set up a loser for the copy to beat.**

The awards slide now carries a benefit rather than a mechanic, using the same
kickers as the website's research section. A specific alternative was drafted
and rejected as the riskier of the two: "Two weeks in, a sharper mind" with
Mrazek 2013's +16 percentile points. It is true and cited, but it is an outcome
claim on an image with no room for the "this is research on meditation, not on
808" caveat that every other surface carries.

**Slide 1 asks before it answers** (Melvin, 2026-09-01, the same correction that
reshaped the description). It used to read "Proof your meditation landed / A
score out of 100", which leads with a metric nobody has been given a reason to
want. It now names the question the reader already has. Slide 5 was recaptured
the same day: the awards shelf no longer carries the "yours for good" line.

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

## In-app purchases, exactly as to be created

Blocked until the **Paid Applications agreement** is active (App Store Connect
hides Monetization without it), so this is data entry for the day the bank
clears. Product IDs must match `Store.ProductID` character for character: the
app fetches these strings and a typo shows as "nothing for sale", not an error.

**Subscription group** (monthly and yearly share ONE group so a user can move
between them without double-paying):

- Reference name (internal): `808`
- Group display name (USER VISIBLE, in Manage Subscriptions): `808`

**The three products:**

| Product ID | Type | Duration | Price | Intro offer |
|---|---|---|---|---|
| `com.lockout.meditate808.monthly` | Auto-renewable | 1 month | $7.99 | 7 days free |
| `com.lockout.meditate808.yearly` | Auto-renewable | 1 year | $29.99 | 7 days free |
| `com.lockout.meditate808.lifetime` | Non-consumable | n/a | $99.99 | **none** |

Lifetime takes no introductory offer on purpose. Its button reads "charged
today, nothing renews", and a free week attached to it would be the paywall
contradicting the purchase sheet, which is the 3.1.2 problem the ladder was
built to avoid.

**Localized display name and description** (user visible, App Store Connect
requires both per product; 30 and 45 characters respectively):

- **Monthly** → name `808 Monthly` · description `Every session measured and scored.`
- **Yearly** → name `808 Yearly` · description `A year of measured practice. Best value.`
- **Lifetime** → name `808 Lifetime` · description `Pay once. Every session, measured, forever.`

Each product also needs a **review screenshot**. Use
`marketing/appstore/01-score.png`: it shows the scored result, which is the
thing being sold, and a reviewer can see immediately what the purchase unlocks.

**Enrol in the Small Business Program** in the same sitting as the agreements.
15% commission instead of 30%, applies while revenue is under the threshold,
and there is no reason to defer it.

## Age rating

**The four answers, and why** (2026-09-01):

| Question | Answer |
|---|---|
| User-Generated Content | **No** |
| Social Media | **No** |
| Health or Wellness Topics | **Yes** |
| Medical or Treatment Information | **None** |

**The wellness pair goes together and only makes sense together.** Apple splits
"self-care or lifestyle recommendations" from "diagnoses or guidance around the
management of medical conditions"; if generic wellness content belonged in the
medical question, the wellness question would be redundant. So the guide's
eight techniques are declared under Health or Wellness Topics, and Medical is
None because nothing in 808 diagnoses anything or tells anyone how to manage a
condition. Answering Yes to wellness is what makes None honest rather than
evasive: the content is declared, in the right box.

**Medical becomes Infrequent the moment any content is condition-targeted.**
A "meditation for anxiety" or "for insomnia" entry in the guide is guidance on
managing a condition. The guide is deliberately general today.

If a reviewer questions the None, the app's own copy is the defence: the
description states 808 is a wellness app and not a medical device, and the
bundled Science page says the cited research is about meditation rather than
about 808.

Both are No because nothing a user creates in 808 can reach another user. The
reflection note is private (device plus the user's own private CloudKit); the
share card leaves only through the system share sheet, to a destination the
user picks, after the sheet shows them the finished image. There is no feed, no
follows, no comments, no discovery, and no server of ours for content to pass
through.

**Answering Yes would be worse than wrong, not safer.** Yes invokes Guideline
1.2, which requires content filtering, a reporting mechanism, the ability to
block abusive users, and published moderation contact details. 808 implements
none of that because it has nothing to moderate, so a Yes is a rejection in the
other direction, and it raises the age rating for nothing.

**Both answers flip the day a community ships.** "The social network for those
who breathe" means a feed, and a feed means Yes to both plus the whole 1.2
moderation stack built BEFORE submission. Scope it as a real feature, never as
an addition to a release.

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
> a session; everything else (onboarding, sounds, guide, history, settings,
> and all three in-app purchases) is fully reviewable on iPhone alone. Sign in
> with Apple is the only sign-in and it is optional, so no demo account exists
> or is needed.
>
> Reviewing without an Apple Watch: at the onboarding question "Do you have an
> Apple Watch?", answer YES (answering no honestly routes to a waitlist and
> deliberately never shows the paywall, since the app will not sell to someone
> it cannot measure for). At the "Put your Watch on" screen, tap "Check again"
> three times; a "My Watch isn't with me. Continue" option appears and the
> two-minute practice is skipped, never simulated. The paywall, the free tier,
> and every purchase flow are reachable from there with no hardware.
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
4. **Legal entity: `Lock Out Inc.` DONE, one page still owed.** The DE
   corporation is the parent company of 808 and the party every legal document
   names. The swap was executed 2026-08-25: the privacy policy, the terms, all
   four website footers and the in-app Settings screen now read **Lock Out
   Inc.** character for character, which is the string the D-U-N-S record
   carries (149914479) and therefore the string the Apple enrolment and the App
   Store seller name must match exactly. A space, and `Inc.`, never `LockOut
   LLC`.

   Still owed, not a launch blocker: a papered LLC to corp assignment of the
   app and the user data, plus a decision on whether the Michigan LLC stays
   dormant or is wound down. See `LEGAL_ACTION_ITEMS.md`.

Then, in Connect:

5. Age-rating questionnaire (new format, answered honestly).
6. App Privacy labels set to Product Interaction, per the section above.
7. Screenshots uploaded: the eight iPhone images in `marketing/appstore/` and
   the two Apple Watch images in `marketing/appstore/watch/`. Both sets are
   done and committed.
8. Support URL `https://meditate808.com/#support` (the anchor exists), marketing
   URL `https://meditate808.com`, privacy URL
   `https://meditate808.com/privacy.html`, and the copyright field:
   `© 2026 Lock Out Inc.` (exact string, the space and `Inc.`). The website is a **manual** Cloudflare Pages upload, so any
   copy change there has to be dragged in by hand; pushing to git deploys
   nothing.
9. Capabilities on the shipping App ID: HealthKit, Sign in with Apple, CloudKit,
   Push.
10. Internal TestFlight on the Org build, then external, then submit.

## Enrolling the Organization (the current blocker)

**Do NOT pay a third $99.** Melvin and Aziz each already hold an Individual
membership. Apple lets an existing Individual membership be **converted** to an
Organization in place, and additional people join that one team for free, so
the company needs exactly one paid membership, not three.

**Decided 2026-08-24: Melvin's account converts.** He holds the corporate
paperwork and owns the store listing. It is also the better team technically:
converting **preserves the Team ID (`WLZQLLHUB3`)**, and that team already has
the production App ID `com.lockout.meditate808` registered and the
`iCloud.com.lockout.meditate808` container created and entitled. All of it
carries over instead of being rebuilt.

### How the conversion works

Sign in as the Account Holder at
[developer.apple.com/account](https://developer.apple.com/account) → **Membership
details** → **Submit a request** next to *Convert to Organization*. (The same
request can be raised through Contact us → Membership and Account → Program
Enrollment.)

Supply: the CEO's first and last name, the company name **including the entity
type** (Inc. / Corp.), the D-U-N-S Number, the company address, and a phone
number Apple can actually reach. Only a founder or co-founder may request it,
which both cofounders satisfy.

Expect several days. Apple may telephone to verify within about two weeks and
may ask for business documents, so the number on the D&B record has to reach a
human.

### What this changes about the earlier advice

An earlier draft of this file said to enrol fresh on the web with a new
company-owned Apple Account. That is correct for someone with no membership and
wrong here: it would mean paying again and abandoning a team that already holds
the right App ID and iCloud container. The one genuine cost of converting is
that the Account Holder is Melvin's personal Apple Account rather than a
company address. That is reversible: Apple permits transferring the Account
Holder role to another team member later, so it can move to a company Apple
Account once one exists.

### Aziz, and the running beta

Aziz joins the converted team as **Admin**, using his own Apple Account, at no
cost. Roles control access; only the organization pays.

**His TestFlight beta does not come with him.** It lives on his individual team
under `com.azizmahmud.808` and stays there. That costs us nothing, because the
store build must ship under `com.lockout.meditate808` regardless, and a
different bundle ID means a different app record and re-invited testers either
way. So the beta keeps running on his account during the transition and is
retired when the org build takes over.

**Do not cancel his membership until the org is verified and the beta is no
longer needed.** After that it can simply lapse at renewal.

### Then, in order

1. Conversion approved, and the team reads Organization with the corporation's
   exact legal name.
2. Accept the **Paid Applications Agreement** in App Store Connect and complete
   banking and tax with the corp's EIN. **This is the step people forget**, and
   until it is done no subscription can sell, which silently blocks the entire
   paywall.
3. Confirm the App ID `com.lockout.meditate808` carries HealthKit, Sign in with
   Apple, CloudKit and Push, register the Watch App ID, and create the app
   record as **808 Meditate** (the colon variant was already rejected as in use).
4. Invite Aziz as Admin. Local signing keeps working on both machines: the Team
   ID is unchanged for Melvin, and Aziz switches his uncommitted `project.yml`
   to `WLZQLLHUB3` with the `com.lockout.meditate808` prefix when he builds for
   the org.

**Do not register the production bundle IDs on any other team while waiting.**
An App ID consumed by an App Store Connect record can never be reused, on any
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
