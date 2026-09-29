# Legal Review — Action Items

**LockOut LLC / Lock Out Inc. (808)** · prepared 2026-08-05 · entity swap executed 2026-08-25

> **2026-08-25, founder decision (Aziz), no attorney:** the user-facing legal
> surface now names **Lock Out Inc.** (the DE corp, D-U-N-S 149914479) and the
> ToS governing law moved Michigan → Delaware to match. Both bundled docs, all
> four website pages, dates bumped. Rationale: the corp will hold the Apple
> Organization account and operate the store listing, so the docs name the
> entity users will actually contract with.
>
> **What this decision creates, still owed:**
> 1. **Paper the IP assignment — NOT a launch gate (Aziz, 2026-08-25).** A
>    short assignment of the 808 app, code, brand and user-data
>    responsibilities from LockOut LLC to Lock Out Inc., signed by both
>    members. Deferred deliberately: Apple never checks it, both founders are
>    50/50 in both entities so ownership lands identically in any dispute,
>    and confirmatory assignments after the fact are routine. **It becomes
>    mandatory at the first diligence event** (outside money, acquisition
>    talk, or a serious legal threat), and it is cheapest to sign while both
>    founders agree on everything, so do it in a quiet week, not never.
> 2. **Decide the LLC's fate** (dormant vs wound down). Michigan annual report
>    still due 02/15/2027 either way while it exists.
> 3. **TR-808 trademark: accepted risk, decided without counsel.** Roland's
>    marks cover instruments and music hardware; a wellness app named 808 in a
>    different class with no drum-machine trade dress is a low-confusion
>    profile, and "808" is in broad cultural use. Revisit only if the store
>    listing ever leans on music-production aesthetics.
Members: Aziz Mahmud, Melvin Alirio Van Cleave

Priority order. Items 1–3 block launch; 4–6 should start now because they get
more expensive the longer we wait; 7 is housekeeping we handle ourselves; 8
(added 2026-09-29) is the set of questions the 1.1 release raised.

**Scope note, updated September 29, 2026 (read this one; the August 5 note
below is superseded).** 808 1.1 is what counsel should review:

- **Sessions run on the iPhone with or without an Apple Watch.** A phone
  session measures nothing. With a Watch, 808 reads **heart rate, stillness
  and breathing** (breathing from the wrist's motion, restored in August) and
  shows a score afterwards. Results stay on the device.
- **The camera is used, for pictures only**: an optional profile photo and
  optional photos or videos a person adds to their own sessions. No
  camera-based pulse reading, no face recognition, no biometric identifiers.
  Profile photos are public (anyone who looks up the username); session
  photos sync only to the person's own private iCloud.
- **Friends (social features)**: a public profile with name, @username,
  optional photo and a practice summary (sessions and minutes this week,
  streak, total sessions, last session date), friend requests, Report and
  Block. No posts, comments or messages.
- **App Store age rating 13+**, with User-Generated Content and Social Media
  both declared. The Terms require users to be 13 or older; there is no age
  verification.
- **Premium only**: a subscription is required to use the app (Monthly
  $7.99, Yearly $29.99, plus two monthly plans with free trials offered to
  people who decline). No free tier.
- **Block** (holding chosen apps until the person meditates, via Apple's
  Family Controls / Screen Time) is built and approved by Apple, and may ship
  in 1.1 or later.
- **Analytics** (PostHog): pseudonymous install ID, named product events,
  purchase events, and approximate location derived from the IP address.
  Never a health value.

**Superseded scope note (August 5, 2026), kept for the record.** We have deliberately simplified the app for v1.
It now measures only **heart rate and stillness** on the Apple Watch during a
session, and runs in the background so the user can play a meditation from
YouTube or any other app. We have **removed** the camera-based pulse reader and
the breathing-measurement feature. The documents attached reflect the simplified
app; please review against this scope rather than any earlier description.

---

## 1. Operating Agreement — highest priority, and possibly not yet sent

This is the document that protects the two of us **from each other**, and it is
the only one where a mistake is expensive and hard to undo. The Terms and
Privacy Policy protect us from users; this one protects the company.

**Confirm it actually reached the lawyer** — Aziz sent the ToS and Privacy
Policy; the Operating Agreement may not have gone with them.

Decisions we need counsel to help us finalize:

- **§11.1 — departure model.** The draft offers three options and we must pick
  one: (a) inactivity downgrade, (b) buyout at appraised value, (c) time-based
  reverse vesting over ~24 months. **Reverse vesting is the most protective if
  one founder stops contributing early** and is the standard answer for a
  two-person startup. We want a recommendation, not a menu.
- **§8 — IP assignment.** Confirms all existing work (source code in personal
  GitHub accounts, the 808 brand and mark, guided-meditation scripts,
  commissioned narration, website, product copy) is assigned into the LLC. Is
  the assignment sufficient as drafted to survive a later dispute or diligence?
- **§6.2** — confirm the tax-distribution rate.
- **Partnership representative** designation under the Code.
- **Spousal consent** — whether advisable given marital status.
- **New York** — Melvin works from NYC. Whether and when foreign qualification
  is required, and anything else NY-specific.

**Already corrected in the attached draft** (noting them so counsel knows they
were deliberate): the filing date is **July 31, 2026** per the state's FILED
stamp, not July 29 (the date Aziz signed the Articles), and Member B's full
legal name is **Melvin Alirio Van Cleave**.

---

## 2. Privacy Policy

**Please review the version attached here, which supersedes anything sent
earlier.** It has been rewritten for the simplified app. Scope is now
meaningfully smaller: **the camera-based pulse feature has been cut**, so there
is no camera access, no image capture, and no biometric-identifier exposure
(Illinois BIPA, Texas CUBI) to address. Breathing measurement is also gone.

> **Corrected 2026-09-29:** the camera IS used again, for an optional
> profile photo and session photos or videos (no pulse reading, no face
> recognition), and wrist-based breathing readings are back for Watch
> sessions. The policy was rewritten for 1.1 on 2026-09-28 and 2026-09-29;
> review the current `PRIVACY_POLICY.md`, not an earlier attachment. The
> BIPA / CUBI point still holds only if nothing derives a face template from
> a photo, which nothing does; please confirm that is enough.

What remains:

- The **"Consumer health data"** section is modeled on Washington's My Health
  My Data Act and applied to all users. Is that approach sound, and are other
  state regimes (Nevada, Connecticut) adequately covered?
- Confirm the **on-device-only storage** description is accurate and internally
  consistent: heart-rate and movement results are computed on the Apple Watch,
  stored on the user's iPhone, and never uploaded to us. Account data (name,
  email, session dates) syncs through the user's own private iCloud.
- **Website data**: the waitlist collects email plus one question; the
  questionnaire at meditate808.com/survey collects optional answers about
  meditation habits and willingness to pay, stored in a Google Sheet. Confirm
  both are adequately disclosed. (2026-09-29: the website no longer has a
  waitlist form; the questionnaire remains. The app's old no-Watch waitlist
  can still send an email from a saved onboarding record, so it stays
  disclosed.)
- **COPPA posture** — app is rated 4+ and we do not distinguish minor accounts.
  (Corrected 2026-09-29: 1.1 is rated **13+** with user-generated content and
  social features; see question 8.1.)
- **Deletion** — account deletion soft-deletes and hard-purges after 30 days.
  Confirm that satisfies the deletion rights we assert.

---

## 3. Terms of Service

**Please review the version attached here, which supersedes anything sent
earlier.** Section 2 has been rewritten to describe background measurement and
to disclaim any affiliation with third-party media services.

- **§14 arbitration** — enforceability of AAA individual arbitration, the class
  action and jury waivers, and the 30-day opt-out, particularly for Michigan
  consumers.
- **§5 / §7 — audio protection.** We commissioned a professional narrator for
  the guided meditation; the prohibition on recording, extracting, or
  redistributing app audio needs to be genuinely protective.
- **Wellness disclaimers.** The app measures heart rate and body movement and
  tells the user how their session went. We make no medical claims and state
  the app is a wellness tool, not a medical device. Is anything further needed?

---

## 4. Trademark — start the clearance search now

Melvin raised this and he is right to. **We think "808" is a hard mark to
protect and we want an honest read before we invest further in the brand.**

- It is a bare number, it is the Roland TR-808 drum machine, and it is Hawaii's
  area code — all of which cut against distinctiveness.
- We need a **clearance search** for the software and wellness classes
  (Class 9, and Class 41/44 for services) before launch, so we learn about a
  conflict now rather than through a cease-and-desist after we have users.
- If "808" alone is not registrable, we want the alternatives: a composite mark
  (logo plus wordmark), a distinctive tagline, or a different name entirely.
  **A name change is cheap today and very expensive after launch.**
- We own meditate808.com.

---

## 5. Platform and marketing compliance

- **Health claims in our marketing.** The website and in-app science page cite
  peer-reviewed research on meditation and heart-rate/EEG changes, and we
  describe the app as giving "evidence your practice landed." We want
  confirmation these are defensible wellness claims and do not stray into
  medical or efficacy claims. **Our current website copy was written for an
  earlier, larger version of the app and needs to be re-checked against what we
  actually ship.**
- **Frequency tones.** Some tones are labeled by tradition ("natural tuning,"
  Solfeggio frequencies) and we deliberately do **not** claim proven effects.
  Confirm the framing is safe.
- **Third-party media (this is now central to the product).** The app measures
  in the background specifically so a user can play a meditation from YouTube,
  Spotify, or anywhere else while we measure. We do not embed, integrate with,
  or communicate with those services. Terms §2 and the Privacy Policy now
  disclaim any affiliation. Please confirm that disclaimer is sufficient, and
  advise whether naming YouTube in App Store copy or showing it in screenshots
  creates trademark or platform-review exposure.
- **Apple Developer Program.** We are launching under Aziz's personal developer
  account and will migrate to a company account (§7.2 of the Operating
  Agreement). Any exposure in the interim, given the LLC will be receiving
  revenue paid to an individual account? (Resolved 2026-09-01: the app is
  published by Lock Out Inc.'s Organization account; no personal account
  receives revenue.)
- **Subscriptions.** Once we charge, auto-renewal disclosure laws (federal
  ROSCA and the state auto-renewal statutes) apply. What do we need in place
  before turning on billing? (2026-09-29: billing is live and 1.1 is
  subscription-only; the sharper version is question 8.3.)

---

## 6. Vendor and content licensing

Worth reviewing because our whole audio library came from third parties:

- **Narration.** The guided meditation was recorded by a professional voice
  actor through Fiverr, under a commercial license that included music. We want
  confirmation the license actually covers commercial distribution in a paid
  app, and that the bundled music is properly cleared.
- **AI-generated audio beds.** Ambient background music was generated with
  ElevenLabs Music under their commercial terms. Confirm we hold sufficient
  rights to distribute and monetize it.

---

## 7. Not legal work — our own housekeeping

Listing so nothing falls through:

- **D-U-N-S number** — in progress with Dun & Bradstreet (case # 10747633).
  This is Apple enrollment paperwork, not a legal matter.
- **Business bank account (Mercury) — CLEARED 2026-09-01.** It had been holding
  the account for proof of the physical address. Resolved, and the Paid
  Applications agreement is no longer blocked.

  **The two addresses are both correct and must not be reconciled into one.**
  The Delaware RA (8 The Green Ste A, Dover DE 19901) is the legal address:
  state filings, service of process, the D-U-N-S record, and the EU trader
  details published on the App Store listing. **183 South 8th Street, Brooklyn
  NY 11211** is the physical operating address, which is what a bank is
  required to hold under its Customer Identification Program obligations and
  what no registered agent address can ever satisfy. If anyone later
  "corrects" one of these into the other, they have broken something that was
  right.

  Company money must never touch a personal account.
- **Michigan annual report** — due **02/15/2027**.
- **Form 1065 partnership return** — due **03/15/2027**.
- **Registered agent.** Aziz's home address is currently public on the state
  record. Worth asking whether a registered agent service is advisable.

---

## 8. Questions for counsel before 1.1 (added 2026-09-29)

These come out of the 1.1 release review. Each is a decision we would rather
make with advice than without it; the founder-side list is in
`RELEASE_CHECKLIST.md`, "OPEN for 1.1: FOUNDER DECISIONS".

1. **User-generated content and a 13+ audience.** Public profiles (name,
   @username, photo, practice summary) visible to anyone who looks up a
   username, friend requests, Report and Block, no messaging. Users may be 13
   to 17. What do we owe minors here: COPPA is out of scope at 13+, but do the
   state age-assurance laws (Texas SB 2420, Utah SB 142; see
   `RELEASE_CHECKLIST.md` item 4) require Apple's Declared Age Range check
   and parental consent for Friends? Is our moderation (a text filter,
   on-device photo screening, reports emailed to us with a 24-hour response
   target in the Terms, a manual ban in the CloudKit Console) adequate, and what must the CSAM reporting procedure
   (18 U.S.C. § 2258A) look like for public profile photos?
2. **Family Controls (Block).** Apple's Family Controls terms forbid sharing
   Screen Time data beyond the person and their device, and we send none of it
   anywhere. Anything else in those terms, or in state law on apps that
   restrict a person's own phone use, that the Terms or the policy should
   say? Block may ship in 1.1 or later.
3. **The hard paywall and auto-renewal.** Nothing past the paywall opens
   without subscribing. Two further monthly plans with free trials are offered
   to people who decline. Is our disclosure (price, period, automatic renewal,
   cancel in App Store settings, on the purchase screen and in the listing)
   enough under ROSCA and **California's Automatic Renewal Law** as amended in
   2024 (its consent, reminder and online-cancellation requirements), given
   that Apple, not we, handles billing and cancellation? Do we need our own
   reminder before a free trial converts?
4. **Celebrity likeness and university marks.** Onboarding shows photos of
   Kobe Bryant, Oprah Winfrey and Ray Dalio (Wikimedia Commons, CC BY-SA, with
   credit and a line saying none of them endorse 808) beside their verbatim
   quotes, and, on a "808 is built on research" screen, the crests of Harvard,
   Heidelberg University, the Max Planck Institute and UCL, whose researchers
   ran the studies we cite (logos only, with a line saying 808 is not
   affiliated). A CC license covers the photographer's copyright, not the
   subject's right of publicity or the trademark. Should both come out
   before 1.1?
5. **Approximate location and pseudonymous analytics.** Our analytics
   provider derives city, region and country from each event's IP address and
   keeps a random install ID. The policy now discloses both. Is that enough
   under **GDPR** (legal basis for analytics without consent; do we need an
   opt-in for EU users, or an opt-out switch in the app) and under
   **Washington's My Health My Data Act** (could product events from a
   meditation app, such as "session completed", be consumer health data even
   with no measurements in them)?
6. **The struck-through anchor prices.** When the App Store's prices fail to
   load, the paywall shows our fallback prices beside a struck-through "was"
   price of $59.99 for Yearly (the code also carries $199 for Lifetime, which
   no screen shows now). Neither product ever sold at those prices. The
   August 18 clearance rested on documented intent to market at them. Does
   that satisfy the FTC's former-price rule (16 CFR 233.1) and state
   equivalents, or should they come out?
7. **The new EEA, UK and Swiss section of the privacy policy** (added
   2026-09-29, second pass; "If you are in the EEA, the UK or Switzerland" in
   `PRIVACY_POLICY.md`). We wrote it ourselves: Lock Out Inc. as controller;
   contract as the basis for the subscription, a Friends profile a person
   creates and account deletion; consent for Apple Health, notifications and
   publishing a Friends profile; legitimate interests for pseudonymous
   analytics and handling reports; transfers to PostHog, Google and
   Cloudflare in the United States under Standard Contractual Clauses or the
   EU-US Data Privacy Framework. Please check the wording and the bases. In
   particular: (a) do our analytics need **opt-in consent** in the EU and UK
   under the ePrivacy rules (PECR in the UK), because the PostHog SDK stores
   an identifier on the device and reads it on every event, whatever the
   GDPR basis for the later processing; (b) do we need an EU or UK
   representative (GDPR Article 27) as a company with no establishment there;
   (c) is listing a Friends profile under both contract and consent right, or
   should it be one; (d) does each provider actually offer the transfer
   mechanism we name.
8. **Washington's My Health My Data Act, the homepage link.** The Act asks a
   regulated entity to link its consumer health data privacy policy from its
   homepage, and the Attorney General's guidance reads that as a separate,
   prominent link. Ours is a section of the general policy
   ("Consumer health data"), linked from the site's footer as "Privacy
   Policy".
   Do we need a standalone consumer health data policy page and its own
   homepage link, given that we never receive health data (it stays on the
   device), or is the section enough?
9. **Sign in with Apple token revocation on account deletion.** Apple asks
   apps that offer Sign in with Apple to revoke the user's tokens through
   its REST API when the person deletes their account. That call needs a
   server holding our Sign in with Apple key, and we run none: deletion signs
   the person out and deletes everything we hold, and the person can end
   Sign in with Apple for 808 in their Apple Account settings. Is that an
   exposure beyond App Review (for example under a deletion right we
   assert), and is a small serverless endpoint worth building before it is
   asked for? (`RELEASE_CHECKLIST.md`, R23.)

---

## Budget

We are two founders, self-funded, pre-revenue. **We would like a flat-fee
estimate before work begins**, and if the full scope is beyond us right now, a
recommendation on which items are genuinely launch-blocking versus which can
wait until we have revenue.
