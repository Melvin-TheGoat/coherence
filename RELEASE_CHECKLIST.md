# Before you submit a build

Read this top to bottom before pressing "Add for Review" in App Store Connect.
`tools/archive.sh` prints the OPEN section at the end of every archive, and a
Claude session asked to submit must go through it with you first.

Tick an item by moving it to DONE with the date. Never delete a line.

## NEXT RELEASE: 1.1 (Friends, and Block if verified)

**Added 2026-09-23, App Review prep pass.** This section is the ORDER the
remaining human steps happen in, for whichever build actually ships next
(Friends alone, or Friends plus Block once `blockInRelease` is verified on
a phone and flipped). It points at the detailed sections below and at
`CLOUDKIT_SETUP.md` rather than repeating them; when the two disagree, the
detailed section and the code are the truth, and this list should be
corrected to match. Do every step below it before returning here.

**Release-docs pass, 2026-09-29.** The store listing, review notes, What's
New, IAP setup and privacy label were rewritten for the 1.1 that actually
ships (premium only, no trial on Monthly or Yearly, the two ladder products,
Friends as profiles only, Block / Shop / Otto chat off). Everything to paste is
in `marketing/APP_STORE_PASTE.md`; the reasoning and the product table are in
`APP_STORE.md`. Items this pass found are **R1 to R18** in the `## OPEN for
1.1: release-docs pass` section right after this one, and the calls only the
founders can make are in `## OPEN for 1.1: FOUNDER DECISIONS` after that.
Lines below that no longer hold are struck through with the date and the
reason, never deleted.

**Second docs pass, 2026-09-29.** The privacy policy, terms, manifest, label
table, description, keywords and review notes were corrected against the code
a second time (all ten label rows are now Linked = Yes; the notes were checked
line by line against the Release build). New items are **R19 to R24** at the
end of the release-docs pass section, and three more founder decisions. **Do R1
and R2 first: R2 is a BLOCKER, and R1 is the one placeholder left in the
review notes.**

0b. **FRIENDS WITHOUT POSTS, AND THE STORE (Melvin, 2026-09-27).** The
   feed and all photo and video posting are gone; friends see each other's
   name and how often they meditate. Owed before the build that ships it:
   - [ ] CloudKit Development → Production: five new fields on the public
     `Profile` record type (`sessions7d`, `minutes7d`, `currentStreak`,
     `totalSessions`, `lastSessionAt`), and two on the synced `Preferences`
     (`ownedHatIDs`, `wornHatID`). A field that is not in Production is
     silently dropped on a real install.
   - [ ] Privacy policy, both copies, and the App Privacy label: the
     "Friends and posts" section still describes photos, videos and posts.
     It now publishes the name, @username and those five practice numbers
     (session counts, minutes, streak, last session date) ~~to people who
     follow you~~ **to anyone who looks up the username** (corrected
     2026-09-29: a public profile is readable by anyone, which is the
     decision the policy and the review notes now state), ~~and nothing
     else~~ **plus who the person has added and who has added them
     (following and followers), and the month the profile was created
     (corrected 2026-09-29, second pass)**.
     Photos or Videos can come off the label
     once no build that posts is in use; the profile photo is still a photo.
     (2026-09-29: it stays on the label, for the profile photo. The full 1.1
     label is in `APP_STORE.md`.)
   - [ ] Existing posts are deleted from iCloud once, on each person's next
     launch (`CommunityModel.clearMyPostsIfNeeded`). Nothing to do but know.
   - [ ] The Store is behind `FeatureFlags.shopInRelease` (off). Flip it
     only when every hat has its art (`Coherence/Shop/Hats/hat-<id>.png`)
     and the Store tab has its icon (`sloth-store`); until then Release keeps
     the Friends tab where the Store would be.
0a. **THE LADDER'S TWO PRODUCTS (Melvin, 2026-09-27).** In the same
   subscription group as Monthly and Yearly, create
   `com.lockout.meditate808.monthlytrial` ($7.99 a month, introductory offer:
   free trial, the length you want; the app reads it) and
   `com.lockout.meditate808.monthly50` (**$3.99 a month, every month**,
   introductory offer: free trial, 3 days; changed 2026-09-27 from a
   half-off first month, because Melvin wants the trial on it and Apple
   allows one introductory offer per product), and attach both to the
   version. Until they exist the "No, I don't want to pay" link does not
   appear in Release; nothing else breaks. Test each once in the sandbox:
   the trial rung's purchase sheet must show the free trial, the half-price
   one 3 days free then $3.99 a month.
   (2026-09-29) Display names, descriptions, rank and review screenshots for
   both are in `APP_STORE.md`, "In-app purchases"; see also R7. Use a sandbox
   tester who has never taken a trial in this group: eligibility for an
   introductory offer is per subscription group, so a tester who took 1.0's
   7-day trial is shown the rung's price from today, correctly.
0. **NO FREE TRIAL (Aziz, 2026-09-26), App Store Connect must match the
   build.** The app no longer offers or mentions a trial
   (`Monetization.freeTrial = false`), and sells only Monthly and Yearly
   with no way past the paywall but buying or restoring.
   - [ ] Delete the introductory offer ~~(the 3-day free trial) on
     `com.lockout.meditate808.monthly`, and on `.yearly` if it carries one~~
     **(the 7-day free trial) on BOTH `com.lockout.meditate808.monthly` and
     `com.lockout.meditate808.yearly`** (corrected 2026-09-29: both 1.0
     products were created with a 7-day free trial, per `APP_STORE.md` and
     step 3 below, and the 3-day trial was only ever a plan).
     While it exists, Apple's purchase sheet still grants a trial the paywall
     never mentions: a 3.1.2 mismatch between the screen and the sheet.
   - [ ] Leave `com.lockout.meditate808.lifetime` for sale or not (the
     founders' call): the paywall no longer shows it, but existing Lifetime
     buyers must keep restoring it, so do NOT delete the product.
   - [ ] Update the store description, review notes and the subscription
     block in `APP_STORE.md` so none of them promise a trial or Lifetime.
     (2026-09-29: written, in `marketing/APP_STORE_PASTE.md`. Tick this once
     it is pasted into App Store Connect.)

1. **Developer portal (Certificates, Identifiers & Profiles), done once, by
   the Account Holder:**
   - [x] Family Controls (Distribution) approved on all four App IDs
     (the app, `.monitor`, `.shield`, `.shieldaction`), 2026-09-22. Nothing
     to redo unless a new extension is added.
   - [x] App Group `group.com.lockout.meditate808` exists (production) and
     `group.com.lockout.meditate808.dev` (beta).
   - [ ] Time Sensitive Notifications capability confirmed present on the
     APP's App ID only (an extension cannot carry it; the entitlement file
     already declares it, confirm the portal and the archived profile agree,
     via `tools/archive.sh`'s checks).
   - [x] **Sensitive Content Analysis: DONE (2026-09-26).** Capability
     ticked on both App IDs (Melvin, 2026-09-25);
     `com.apple.developer.sensitivecontentanalysis.client` = [`analysis`] is
     in `Coherence/Coherence.entitlements` and the beta signed with it. At
     archive, check the App Store build's entitlements list it too
     (`codesign -d --entitlements - <app>`).
   - [x] **Privacy manifests for Block's three app extensions: DONE in code,
     2026-09-23 (commit 7c31bcd).** Each of BlockMonitor, BlockShield and
     BlockShieldAction reads and writes the shared App Group's `UserDefaults`
     through `BlockKit/BlockStore.swift`, so each now carries its own
     `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults`
     reason `1C8F.1`, and the app's manifest declares `1C8F.1` beside its
     `CA92.1`. Verified inside every `.appex` of a built product. Without them
     an upload is refused automatically (ITMS-91053). The extensions are
     compiled into every archive whatever `blockInRelease` says, so this
     applies to a Friends-only build too.
2. **CloudKit Console, in order, following `CLOUDKIT_SETUP.md` exactly**
   (that file is derived from the code and kept current; re-derive from
   `CommunityRecords.swift` / `CommunityStore.swift` if it and the code ever
   disagree):
   - [ ] PUBLIC database (`iCloud.com.lockout.meditate808`): confirm all
     seven Friends record types, add any missing fields including the four
     newer `Post` media List fields (`media`, `mediaPosters`, `mediaKinds`,
     `mediaAspects`, replacing the single `photo` field), add the eight
     documented indexes (QUERYABLE on `FriendEdge.from`/`.to`,
     `Post.author`, `Reaction.post`, `Reaction.author`, `Block.from`/`.to`;
     SORTABLE on `Post.practicedAt`).
   - [ ] **One more index, now in `CLOUDKIT_SETUP.md` (the account deletion
     that needs it landed in code 2026-09-23): QUERYABLE on
     `Reaction.author`.** Deleting an account deletes the reactions that
     person gave, across every post, and that query needs this index. Eight
     indexes in all.
   - [ ] Security roles `_world` read / `_creator` write confirmed on all
     seven public types. (2026-09-29: **except Report**, which must NOT be
     world-readable: a report carries the reporter and their words. See
     `CLOUDKIT_SETUP.md` Step 4 and R4.)
   - [ ] (2026-09-29) The five practice-summary fields on the public
     `Profile` type (`sessions7d`, `minutes7d`, `currentStreak`,
     `totalSessions`, `lastSessionAt`, from 0b) are in Development before the
     deploy. Seven record types and eight indexes in all; nothing new to
     index.
   - [ ] PRIVATE database (the per-user CloudKit sync): confirm
     `CD_SessionPhoto` (including the newer `order` and `video` fields),
     `CD_Session.source`, and `CD_User.username` are all present in
     Development with every field, including the ones that only appear
     after an app actually writes them (save a session with a video and a
     custom order from a DEBUG build signed in to iCloud first).
     (2026-09-29) Plus `CD_Preferences.ownedHatIDs` and
     `CD_Preferences.wornHatID` (the Shop's, written with defaults even
     while the Shop is off). Full list in `CLOUDKIT_SETUP.md`, "The private
     database".
   - [ ] Run the real round trip on two phones, per `CLOUDKIT_SETUP.md`
     Step 5, in Development, BEFORE deploying. (2026-09-29: Step 5 is
     rewritten for profiles without posts: claim, search, request, accept,
     check the summary, report, block, delete account.)
   - [ ] Deploy Development → Production. Read the diff before confirming;
     it is additive and one-way.
   - [ ] Verify Production lists every type, field and index from the
     Development side.
3. **App Store Connect:**
   - [ ] **1.1 is PREMIUM ONLY (Melvin and Aziz, 2026-09-23;
     `Monetization.premiumOnly`).** Onboarding ends on the paywall and the
     app opens to it for anyone without a subscription. Before submitting:
     - ~~Set the trial length on BOTH subscriptions' introductory offers
       ("likely 3 days"; Connect says 7 today). The app reads it off the
       monthly product, so nothing else changes.~~ **Superseded 2026-09-29:**
       Monthly and Yearly carry NO trial since 2026-09-26 (step 0 deletes
       it); the only trials are on the two ladder products (0a), and the
       app reads the trial length off `monthlytrial`.
     - ~~The description and promotional text say plainly that 808 is a
       subscription with a free trial.~~ **Superseded 2026-09-29:** they say
       808 is a subscription with every feature included; trials are
       described only for the two ladder plans, in the subscription block.
     - ~~Review notes: "808 is a subscription app. The paywall at the end of
       onboarding offers a free trial; start it with the sandbox account to
       reach everything. Restore purchase is on the same screen."~~
       **Superseded 2026-09-29:** the paywall offers no trial. The notes are
       in `marketing/APP_STORE_PASTE.md` (how to pass the press-and-hold
       screen, the ladder, the Account link, 1.0 users).
     - ~~All four products attached to the version~~ **The real set
       (corrected 2026-09-29): attach `monthly`, `yearly`, `monthlytrial` and
       `monthly50`; do NOT attach `lifetime` (restore only, already approved
       with 1.0) or `yearly50` (no screen sells it)** and their review
       screenshots uploaded: if the sandbox cannot return them, the app stays
       open instead of showing a paywall that cannot sell, which a reviewer
       reads as "the paywall is missing". (Only `monthly` and `yearly` decide
       that; the ladder link just hides if its two are missing.)
     - Decide what people who installed 1.0 or 1.0.1 for free get when they
       update (BACKLOG.md "Decisions from the 2026-09-23 call"): today they
       meet the paywall at launch. **Moved to DONE 2026-09-29** (decided
       2026-09-25: they meet the paywall; past buyers keep access).
   - [ ] Age rating questionnaire, answered fresh in the live form (do not
     assume the shape hasn't changed since this was written): see "Age
     rating (1.1, Friends ON)" ~~below~~ **in `APP_STORE.md`** for the worked
     answers and expected 13+ tier. (2026-09-29: Medical or Treatment
     Information is now **Infrequent**, because the bundled `SCIENCE.md`
     cites cardiovascular and anxiety research; see R10.)
   - [ ] App Privacy labels updated to match `Coherence/PrivacyInfo.xcprivacy`
     exactly: see the "App Privacy (nutrition labels)" table ~~below~~ **in
     `APP_STORE.md` (ten data types, rewritten 2026-09-29; R9)**. No
     Diagnostics row: PostHog crash capture is off in code
     (`Analytics.swift`, 2026-09-23), and the dashboard cannot turn it on.
   - [ ] Description and promotional text updated in
     `marketing/APP_STORE_PASTE.md` (owned by that file, not this one) to
     lead with what 808 now is; draft copy and themes are in APP_STORE.md's
     "1.1 rewrite still owed" note. (2026-09-29: written; paste it.)
   - [ ] Subscription block inside the description still present, prices
     matching Connect exactly.
   - [ ] Review notes replaced with the 1.1 version ~~in `APP_STORE.md`
     (Watch is optional, how to test Friends, how to test Block if it
     ships, offer to provide a screen recording for the Screen Time parts)~~
     **from `marketing/APP_STORE_PASTE.md`, after R1 fills in the reviewer
     handle** (corrected 2026-09-29; the Block paragraph is in
     `APP_STORE.md` for a build that ships Block).
   - [ ] What's New set to the ~~matching 1.1 variant in `APP_STORE.md`~~
     **1.1 text in `marketing/APP_STORE_PASTE.md`** (2026-09-29; it says 808
     is now a subscription and existing subscribers and Lifetime owners keep
     access), including the one-line note that past scores were rescored
     (see "1.1 RESCORES EVERY EXISTING USER'S HISTORY" below).
   - [ ] Store screenshots re-shot wherever the tab bar shows (Search is
     now Friends) and wherever Block appears, if it ships. **Superseded
     2026-09-29 by R6: every screenshot must be re-shot.**
   - [ ] Confirm the existing IAP/subscription products are attached to
     this version; ~~nothing new needs creating for Friends~~ (2026-09-29:
     two new products, `monthlytrial` and `monthly50`, see 0a). If Block ships
     paid through the same subscription group, confirm its paywall entry
     point carries the same required disclosures (price, length, renewal,
     Privacy Policy and Terms links) as the main paywall. Checked in code
     2026-09-23: `HomeSheet.blockPaywall` presents the same `PaywallScreen`
     (placement "block"), so it does.
4. **The report email pipeline** (guideline 1.2 needs a path that reaches a
   person, not just a stored record): create the "808 friends reports"
   sheet, deploy `tools/community-reports.gs`, paste its `/exec` URL into
   `ReportClient.endpoint` (a Swift change, out of scope here), file one
   real test report and confirm the email arrives. **(2026-09-29: a BLOCKER,
   see R2. `ReportClient.endpoint` is still `""`, so today a report is
   stored in CloudKit and nobody is told, while the app and the review
   notes promise that a person reads reports.)**
   - [ ] **Child sexual abuse material: a written procedure before photo
     posts go live** (added 2026-09-25). (2026-09-29: posts are gone, but
     profile photos are public and still need this procedure, and the
     report path in R2 is how one would reach us.) US law (18 U.S.C. § 2258A) requires
     a provider that learns of apparent CSAM to report it to NCMEC's
     CyberTipline and preserve it; the REPORT Act added penalties. Register
     808 with NCMEC as an electronic service provider, and write down who
     checks reported photos, how one is preserved and reported, and that it
     is then removed. Screening photos does not replace this.
   - [ ] **Texas SB 2420 is enforceable now** (the Supreme Court let it
     stand on 2026-07-06; Utah's SB 142 has been live since 2026-05-06;
     Louisiana 2027-07-01; California AB 1043 2027-01-01). Apple's age
     assurance page: "In regions where legally required, you need to check
     the age of the people using your app with the Declared Age Range API",
     and for a significant update, "Until the parent provides consent, the
     child must be prevented from accessing the significant update". 1.1
     adds social features and a paid-only model, which likely counts. Decide
     WITH THE LAWYER, before submitting, whether 1.1 must check age with
     Declared Age Range for users in those states and hold Friends from
     minors until a parent consents. The onboarding age question is
     self-reported and does not count as this check.
5. **Website redeploy** (manual, Cloudflare Pages, drag the `website`
   folder in): both `website/privacy.html` and `website/terms.html` now
   carry the Friends media-plural wording, the Block section, and the
   September 23, 2026 date; they must go live the same day the build does,
   never before the build and preferably not long after. (2026-09-29: the
   policy and terms changed again on 2026-09-28 and 2026-09-29; see R12.)
6. **The two-phone TestFlight round trip**, Friends: ~~claim a username on
   each, add each other, post a session with a couple of photos or a video,
   confirm it appears on the other phone, react, report, block, unblock,
   delete an account and confirm the profile and posts vanish from the
   other phone's view.~~ **Superseded 2026-09-29 (posting removed
   2026-09-27):** claim a username on each, search, request, accept, check
   each other's practice summary after a session, report, block, unblock,
   delete an account and confirm the profile and username vanish from the
   other phone. Same steps as `CLOUDKIT_SETUP.md` Step 5, on TestFlight
   (Production) instead of Development.
7. **On-phone Block verification**, only if this build flips
   `blockInRelease`: everything already listed under "OPEN for the build
   that flips `FeatureFlags.blockInRelease`" below, unchanged by this pass.

Nothing above is a substitute for reading the rest of this file; it is the
order to read it in.

## OPEN for 1.1: release-docs pass (R1 to R18, added 2026-09-29)

Under an `## OPEN` heading so `tools/archive.sh` prints them at the end of
every archive.

- [ ] **R1. Reviewer handle.** [founders: create and insert a reviewer
  handle] Make a standing Friends account on a spare Apple Account signed
  in to iCloud, claim a handle, sit a session or two so its practice summary
  shows something, then replace `@REVIEWER_HANDLE` in the review
  notes in `marketing/APP_STORE_PASTE.md` with that handle. Keep the account
  alive through review and accept any request it gets. It needs an active
  subscription (an offer code or a founder's plan) to get past the paywall
  to Friends. Also referenced in `APP_STORE.md`, "Review notes".
- [ ] **R2. BLOCKER (App Review guideline 1.2): reports must reach a
  person.** Deploy `tools/community-reports.gs` (steps in its header), set
  `ReportClient.endpoint` to its `/exec` URL (a Swift change, not in this
  pass), file one real report from a Release build and confirm the email
  arrives. The Terms (section 6a) say reports reach us and are answered
  within 24 hours; with the endpoint empty, nobody is told. Same item as
  step 4, promoted.
- [ ] **R3. The ban path, verified in the PRODUCTION CloudKit Console.**
  Confirm the developer can delete ANOTHER user's `Profile` and `Username`
  records there (the only way to remove an abusive profile, since the public
  database lets only a record's creator modify it from the app). If the
  Console refuses, we have no way to act on a report, and that has to be
  solved before submitting.
- [ ] **R4. Report records are not world-readable.** In Production (and
  Development), Security Roles on `Report`: `_world` no Read. A report
  carries the reporter's reference and their own words. `CLOUDKIT_SETUP.md`
  Step 4 has the exact roles; the app only ever writes reports, never reads
  them.
- [ ] **R5. Bulk-delete test `Post` and `Reaction` records in Production.**
  Anything left from TestFlight rounds when posting existed. Each person's
  own posts are deleted on their next launch (`clearMyPostsIfNeeded`), but
  records from test accounts that never launch 1.1 would sit in the public
  database forever.
- [ ] **R6. Re-shoot every store screenshot from a Release 1.1 build**, the
  eight iPhone images and the two Apple Watch images. The committed sets show
  the deleted dark theme, the retired flower mark, the Search tab, 17
  awards and Watch-only copy ("Your Apple Watch knows"). Proposed order and
  captions are in `marketing/APP_STORE_PASTE.md`, "Screenshots". Media
  Manager orders by upload completion: upload one at a time, in order.
- [ ] **R7. In-app purchase metadata.** Review screenshots and localizations
  (display name, description) for `monthlytrial` and `monthly50`; new
  descriptions for `monthly`, `yearly` and `lifetime` (the 1.0 ones say
  "Every session measured and scored", false for a phone session); re-shoot
  `marketing/appstore/iap/paywall-review.png` (from 2026-09-01, the old
  paywall). All values in `APP_STORE.md`, "In-app purchases".
- [ ] **R8. Subscription group display name**: recommend `808 Premium`, the
  name the app uses, instead of the 1.0 `808 Membership`. Set the rank per
  `APP_STORE.md`.
- [ ] **R9. App Privacy label from the manifest in the archive.** The table
  in `APP_STORE.md` was written from the decided list while the manifest was
  being changed in parallel; before publishing the label, compare it with
  `Coherence/PrivacyInfo.xcprivacy` in the build being submitted (ten data
  types, tracking none). (2026-09-29, second pass: **all ten are Linked =
  Yes**; the four PostHog-only rows were flipped because Apple counts data
  tied to a pseudonymous ID as linked. The manifest also gained FileTimestamp
  `C617.1` and SystemBootTime `35F9.1`.)
- [ ] **R10. Age rating, Medical or Treatment Information = Infrequent**,
  plus UGC Yes, Social Yes, Messaging No. Expected 13+.
- [ ] **R11. PostHog IP and GeoIP.** The privacy policy now discloses
  approximate location from the IP address, and the label declares Coarse
  Location. Decide whether PostHog keeps the IP: the project setting
  "Discard client IP data" off or on is the founders' call. On means no
  stored IP and no GeoIP; then take Coarse Location off the label and the
  policy together.
- [ ] **R12. Redeploy the website after the privacy policy and terms
  change** (`python3 tools/legal_pages.py`, then the manual Cloudflare
  upload), the same day the build goes live. Both App Store URLs point at
  the website, not the bundled copies.
- [ ] **R13. Content Rights answer** in App Information depends on the
  photos decision below: No third-party content only if the famous-meditator
  photos and university crests are removed.
- [ ] **R14. Lifetime: remove from sale or not** (founders). No screen sells
  it in 1.1. Never delete the product; buyers must keep restoring it.
- [ ] **R15. Copyright field**: `© 2026 Lock Out Inc.` exactly.
- [ ] **R16. Paste the 1.1 subtitle, promotional text, description,
  keywords and What's New** from `marketing/APP_STORE_PASTE.md`.
- [ ] **R17. One real purchase of each ladder plan** in the sandbox on the
  Release build, from "No, I don't want to pay", confirming each rung
  returns to the paywall with its plan selected and the purchase sheet
  agrees with the screen.
- [ ] **R18. The launch paywall's Account link works for someone who never
  pays**: Manage subscription, Redeem a code, Restore, Sign out and Delete
  account (5.1.1(v) needs deletion reachable without buying). ~~It shows only
  on the LAUNCH paywall (`placement == "root_lock"`, an app that finished
  onboarding with no subscription), not on the onboarding paywall.~~
  **Corrected 2026-09-29 (second pass):** it shows on the LAUNCH paywall
  (`placement == "root_lock"`) and also on the onboarding paywall on a device
  that already holds an account's data. Test it
  on a 1.0 install updated to the 1.1 Release build, or with a sandbox
  subscription left to expire.

- [ ] **R19. Pre-1.1 analytics that 1.1 no longer sends** (added
  2026-09-29, second pass). Versions before 1.1 sent `award_unlocked` for the
  three score awards (a score of 50, 75 or 90 reached, derived from heart
  rate) and `watch_gate` (whether the person said they own an Apple Watch).
  The privacy policy now discloses both as past behavior. Either delete those
  events in PostHog (the score-award `award_unlocked` rows and every
  `watch_gate` row) or leave them under that disclosure; decide, then drop the
  Watch gate tab and the "Said they have a Watch" row from
  `tools/posthog_sheet.gs` so the sheet stops reading a question 1.1 never
  asks.
- [ ] **R20. The reviewer's sandbox account holds no active 808
  subscription.** Onboarding sends a payer straight past the paywall, so a
  reviewer on a subscribed account would never see it. The review notes ask
  for this; make sure the account named in App Store Connect (if any) and the
  one used for R17 are clean. (R1's reviewer handle account is the opposite
  case: it needs a subscription to reach Friends. Keep the two separate.)
- [ ] **R21. Manage subscription and Redeem a code open from the Account
  sheet, on a device.** Both are system sheets that do not appear in the
  simulator the way they do on a phone. Test from the launch paywall's
  Account link and from Settings on a Release build.
- [ ] **R22. Regenerate and redeploy the legal pages after this pass.**
  `python3 tools/legal_pages.py` was run on 2026-09-29 (second pass); the
  Cloudflare upload is still owed (same as R12).
- [ ] **R23. Note, not a blocker: Sign in with Apple token revocation on
  account deletion.** Apple asks apps that offer Sign in with Apple to revoke
  the user's tokens through its REST API when they delete their account. That
  call needs a server holding our Sign in with Apple private key, and 808 runs
  none. Today deletion signs the person out and deletes everything we hold;
  the person can also stop using Sign in with Apple for 808 in their Apple
  Account settings on the iPhone. Record it for counsel
  (`LEGAL_ACTION_ITEMS.md`, question 9) and revisit if review asks.
- [ ] **R24. The Report roles in R4 are what the privacy policy promises.**
  The policy now says reports are the one part of the shared area other
  people's copies of 808 cannot read. That is true only once R4's Security
  Roles are set in Production; do R4 before the policy goes live.

## OPEN for 1.1: FOUNDER DECISIONS pending before submitting (added 2026-09-29)

Only Melvin and Aziz can make these. Each is a real rejection or legal risk;
none is a code task until they decide.

- [ ] **Ship Block in 1.1, or strip it from the archive.** Its three
  extensions and the Family Controls entitlement ship in the binary even
  with `blockInRelease = false`. App Review may read an entitlement for a
  feature nobody can reach as a hidden or dormant feature (2.3.1).
  Recommended: ship it once verified on a phone (section above), or take the
  extensions and the entitlement out of the 1.1 archive.
- [ ] **Remove the celebrity photos on "808 was made for people like you"
  and the university crests on the research screen.** A famous person's face
  in an ad-like screen raises right-of-publicity claims, and a crest implies
  an affiliation none of them gave (5.2.1). The footnotes disclaiming
  endorsement reduce the risk; they do not remove it.
- [ ] **The website advertises Block and hats** (the "Block" chip and
  points buying hats in `website/index.html`) while both are off in 1.1.
  Change the page or ship the features before the 1.1 listing links to it.
- [ ] **The struck-through anchor prices, $59.99 (Yearly) and $199
  (Lifetime)** (`SubscriptionPlan.anchorPrice`). They show only beside our
  fallback prices, when the App Store's prices fail to load, and Lifetime is
  no longer a card on the paywall, so in practice it is $59.99. FTC guidance
  (16 CFR 233.1) treats a "was" price as deceptive unless the product
  genuinely sold at it for a reasonable time; neither ever did. The code
  comment records an attorney clearance (2026-08-18) on documented prior
  intent to market at them, which is not the same thing as a prior selling
  price. Remove them, or document a real prior selling price. (The half-off
  rung's struck $7.99 is a true reference: Monthly sells at $7.99.)
- [ ] **Locking the phone during a phone session counts as leaving** after
  10 seconds, so a reviewer (or anyone) who locks the phone to meditate is
  told the session won't count. The review notes now say so, and "I was
  still meditating" keeps it. Decide whether a locked screen should count as
  staying.
- [ ] **The rating prompt fires inside onboarding**, beside a five-star
  graphic, before anyone has used the app. It uses Apple's own sheet and is
  unconditional (not gated on an answer), which keeps it inside the rules
  (guideline 5.6.1), but a rating ask next to a picture of five stars,
  before a single session, is the pattern reviewers question. Moving it back
  to after the third session (`ReviewPrompt`, which still exists) is the
  safe option.
- [ ] **An in-app analytics opt-out switch** in Settings. Not required by
  App Review for pseudonymous first-party analytics, but the policy now
  discloses approximate location, and a switch is the honest companion to
  that sentence (and helps under GDPR).
- [ ] **"Regulate your emotions and stress"** (added 2026-09-29, second
  pass). Onboarding's "In 1 week, 808 will help you:" screen lists it as an
  outcome. It is the one row that promises an effect on the person rather
  than a habit ("Make meditation part of your daily routine"), and 808
  measures nothing about emotions. Keep it, soften it (for example "Make
  time to settle when you're stressed"), or cut it; the listing already
  avoids outcome claims, and a reviewer reading onboarding can hold the app
  to the same line (1.4.1, 2.3.1).
- [ ] **Who blocked whom is readable by anyone** (added 2026-09-29, second
  pass). `Block` records are world-readable in the public database, as
  `FriendEdge` records are, because the app checks blocks in both directions.
  The privacy policy now discloses it. Keep it that way, or redesign blocks
  so they are not exposed; the options are in `CLOUDKIT_SETUP.md`, Step 4.
- [ ] **808 opens for free when StoreKit cannot load** (added 2026-09-29,
  second pass). If Monthly or Yearly fail to load (offline at first launch,
  products missing in App Store Connect, an App Store outage), the paywall
  reads "Plans aren't loading" and lets the person continue, so a
  premium-only app runs unpaid until the next successful load. That is the
  safe choice for App Review (a paywall that cannot sell is a 2.1 rejection)
  and for payers (cached entitlements still unlock). The cost is that
  anyone who starts 808 offline gets in. Decide whether that is acceptable,
  or whether the lock should hold after the first successful load.

## HOLD

- **1.0.2 (build 202609141719) is uploaded and NOT submitted. Do not create
  the version, attach the build or press Add for Review until Aziz says so**
  (2026-09-14: "there is a decent amount I want to do before we do that").
  More changes will likely go into this version first, which means a new
  archive; this build may never ship. (2026-09-29: the next submission is
  1.1, which needs its own archive; this build predates all of it.)

## WHAT 1.1 CONTAINS (read before archiving, added 2026-09-29)

Archive the 1.1 build from the branch the founders name for it (the work is on
`block` as of 2026-09-29; `mvp` and `main` were fast-forwarded to it on
2026-09-23 and have not followed since). `MARKETING_VERSION` is 1.1. In
Release it ships:
- **Premium only, no trial on Monthly or Yearly** (`Monetization`): the
  launch paywall for anyone without a subscription, the two-rung ladder
  (`monthlytrial`, `monthly50`), and the Account link on the paywall.
- **Sessions on the iPhone with or without a Watch**: the plus offers
  Meditate, With Apple Watch and Record one.
- **Onboarding in its 2026-09-26 shape**: about thirty screens, the paywall
  right after "Ready to take control?", then reminders, Apple Health (paired
  Watch only), Sign in with Apple (optional), Create your profile
  (optional), the tour.
- **Friends ON as profiles only** (`friendsInRelease = true`): name,
  @username, optional photo, practice summary; no posts.
- **Block, the Shop (hats, points) and Otto's chat OFF**; Block's extensions
  and Family Controls ship in the binary (founder decision above).
- 58 awards in the catalog; score migrations `scoreBackfillDone.v8` and
  `.v9` rescore past Watch sessions.

## ~~WHAT THE NEXT BUILD CONTAINS (read before archiving)~~

**Superseded 2026-09-29 by "WHAT 1.1 CONTAINS" above.** This described the
1.0.2 build that was never submitted: Friends OFF with a Search tab, "Let's
find out" on screen one, and an archive from `mvp`. None of that is true of
1.1. Kept for the record.

Archive from `mvp` at or after the commit that added `FeatureFlags`. It ships:
- **Onboarding: no sign-in until the end, and progress resumes** (Aziz asked
  for this in the next release, 2026-09-14). Check on a device: screen one
  has only "Let's find out"; quit mid-interview and relaunch lands on the
  same question.
- Everything already listed for 1.0.2 (no-Watch waitlist, Watch fixes).
- **"Too short to score" screen** (Aziz, 2026-09-14): a session ended under
  30 seconds now says so instead of silently vanishing, and logs
  `session_discarded` (reason `too_short` or `unreadable`) instead of looking
  like a broken session. Check on a device: Begin, End within a few seconds.
- Melvin's onboarding round 2 (merged 2026-09-14).
- **Friends is compiled in but OFF** (`FeatureFlags.friendsInRelease = false`,
  locked by `FeatureFlagTests`). The tab reads Search with "Friends are
  coming", matching the store screenshots. Do not flip it for this build.

The 1.0.2 build uploaded earlier (202609141719) predates all of this, so
this release needs a NEW archive.

## OPEN for the build that flips `FeatureFlags.ottoInRelease`

- [ ] Privacy policy, both copies (`PRIVACY_POLICY.md`, `website/privacy.html`):
      one sentence that Otto answers on the device using Apple's on-device
      model (Apple Intelligence) and that nothing you ask or your session
      data is sent anywhere. Redeploy the website.
- [ ] Paid tier description in App Store Connect names Otto; screenshots if
      it appears in one.
- [ ] Review notes: "the assistant runs on Apple's on-device Foundation
      Models framework; no server, no third-party AI service" (keeps the
      earlier answers true).
- [ ] Melvin and Aziz have read a dozen of Otto's answers on a phone.

## OPEN for the build that flips `FeatureFlags.blockInRelease` (Block, 2026-09-22)

- [ ] **Seen working on a phone** (the simulator cannot draw a shield):
      a held app shows Otto's shield; Ask Otto sends "Otto wants a word";
      tapping it opens one of Otto's screens; a 5 minute pass closes the apps
      again on time (the 15-minute DeviceActivity floor, see CONSISTENCY.md);
      a session releases the window; a daily limit holds after its minutes.
      **And pick "All Apps & Categories", then check 808 itself still
      opens**: if Screen Time shields the app that set the shield, nobody
      could open 808 to meditate. Also whether a
      window that repeats overnight still closes (`intervalDidEnd`).
      `tools/beta_install.sh` installs 808 Beta.
- [ ] Signing for App Store: the three extension App IDs
      (`com.lockout.meditate808.monitor`, `.shield`, `.shieldaction`) carry
      Family Controls (Distribution, approved 2026-09-22) and the App Group
      `group.com.lockout.meditate808`, and the app carries Time Sensitive
      Notifications (an extension cannot: signing refuses it). Automatic
      signing adds the capabilities but **cannot create an App Group**: the
      group must first exist in Certificates, Identifiers & Profiles >
      Identifiers > App Groups (done by the Account Holder; the beta needs
      `group.com.lockout.meditate808.dev` too). Confirm in the archive
      (`tools/archive.sh`).
- [ ] Privacy policy, both copies: 808 uses Apple's Screen Time to hold the
      apps the person picks; the picks are opaque tokens even to 808; nothing
      from Screen Time leaves the phone or reaches analytics. Redeploy the
      website.
- [ ] App Privacy labels: no change needed if nothing from Block is
      collected (it is not); confirm, and keep PostHog free of Block events
      (Apple's Family Controls terms).
- [ ] Review notes: how to try Block (the Block tab, Mindful day, Ask Otto
      on a held app), that it is individual Screen Time authorization and not
      parental control, and that Block is part of 808 Premium.
- [ ] Camera usage string now also names Otto's ~~FaceTime~~ video call
      screen (live preview only, nothing recorded; renamed 2026-09-23 so the
      string does not borrow Apple's mark, 5.2.5). A changed usage string is
      reviewed.
- [ ] Store description, screenshots and the website lead with consistency
      and Block (the app's primary purpose must be Apple's purpose 2 for
      Family Controls; see CONSISTENCY.md).

## OPEN: must be done in the submission that ships the next build

- [ ] **Privacy policy and terms were rewritten on 2026-09-28; the App
  Privacy label must match them.** New since the last submission: Friends
  profiles publish a practice summary (sessions and minutes in the last 7
  days, streak, total sessions, last session date) to the public database,
  and posts are gone. Declare the summary under App Privacy (it is data we
  can read, linked to the profile), drop anything that only described posts,
  and redeploy the website so `meditate808.com/privacy` and `/terms` show the
  same text the app bundles (`python3 tools/legal_pages.py` rebuilds them).
  (2026-09-29: the label is written, as Other Data Types, in `APP_STORE.md`;
  the policy and terms changed again on 2026-09-29. See R9 and R12.)

- [ ] **CloudKit Console: promote the schema Development → Production
  BEFORE the build goes live.** This build adds fields to two synced models:
  `CD_Preferences` (evidenceGrantRemaining, evidenceGrantSince,
  rewardedFriends, grantedSessionIDs) and `CD_SessionReflection` (title,
  publicNote, visibility). Production rejects fields it has never seen, so
  without the promotion every Preferences and Reflection export fails
  silently for every user, the same failure 1.0 shipped with. Run a DEBUG
  build signed in to iCloud first (or the schema primer in Settings > CloudKit)
  so Development has the fields, then deploy. Verify the fields are listed
  under Production before releasing.

- [ ] **App Privacy label: add Email Address.** App Store Connect → 808
  Meditate → App Privacy → Edit → add *Contact Info → Email Address*.
  Answers: **Linked to the user: Yes. Used for tracking: No. Purpose:
  Developer's Advertising or Marketing.** Why: the no-Watch waitlist now sends
  the typed email to our sheet (`WaitlistClient`), and the app's privacy
  manifest already declares it. A label that doesn't match the manifest is a
  review flag. Publish the label change before submitting. (2026-09-29: it
  is one of the ten rows in `APP_STORE.md`'s 1.1 table; no 1.1 screen asks
  for an email, but an old resume record can still send one.)

- [ ] **Website: redeploy.** Drag the `website/` folder into Cloudflare Pages
  (Workers & Pages → meditate808 → Create deployment). Why: `privacy.html`
  gained the in-app waitlist paragraph (dated September 14, 2026). The app
  and the website must say the same thing on the day the build goes live.

- [ ] ~~**One real no-Watch signup on the new build.** After the update is
  live, install it on a phone, answer "no" at "Do you have an Apple Watch?",
  join the waitlist with a throwaway address, and confirm a row appears in
  the **808 no watch waitlist** sheet. Then delete that row.~~
  **Superseded 2026-09-29:** the question "Do you have an Apple Watch?" was
  removed on 2026-09-22 (the phone detects a paired Watch instead), so no
  1.1 screen reaches the waitlist and this test cannot be run. The sheet
  and `WaitlistClient` stay for signups queued by older installs.

## OPEN for 1.1 (Friends), before that build is submitted

**Branch `social-1.1` (2026-09-18).** Melvin: ship the social update first,
on its own, because it is what people want and it does not wait on the
privacy work Otto and camera vision need. That branch carries Friends ON
(`friendsInRelease = true`), Otto OFF, version 1.1, follower and following
counts, and the technique picker matching the self-log. Camera vision is not
on it. (2026-09-29: 1.1 is now built from `block`, which carries all of this
plus the premium-only model; see "WHAT 1.1 CONTAINS". Posting was removed
2026-09-27, so every post-related line below is struck through.)

**Done on that branch, in code:**
- [x] `FeatureFlags.friendsInRelease = true`; `FeatureFlagTests` rewritten to
  assert it (and that Otto stays off).
- [x] `MARKETING_VERSION` 1.1.
- [x] `PrivacyInfo.xcprivacy`: Photos or Videos, Other User Content, Name,
  all LINKED, App Functionality. The labels in App Store Connect must match.
  (2026-09-29: the 1.1 manifest declares ten types; `APP_STORE.md` has the
  table.)
- [x] Privacy policy: a "Friends and posts" section, and the short version no
  longer claims we cannot see anything. (2026-09-29: rewritten since for
  profiles without posts.)
- [x] Terms: section 6a, user content and no tolerance for objectionable
  content, with the report/block/remove path spelled out (guideline 1.2).

**The rest is not code and none of it can be skipped:**

- [ ] **CloudKit Console: follow `CLOUDKIT_SETUP.md`**, which has the exact
  types, fields, indexes and roles derived from the code, plus the round trip
  to run before promoting. Summary, `iCloud.com.lockout.meditate808`: the six PUBLIC
  **SEVEN** public record types (Profile, Username, FriendEdge, Post,
  Reaction, Block, Report: the earlier count of six missed Username, and
  without it no handle can be claimed) and exactly ~~SEVEN~~ **EIGHT**
  indexes (corrected 2026-09-29: `Reaction.author` was added 2026-09-23 for
  account deletion; this line predates it), which are
  fewer and different from what this line used to claim: QUERYABLE on
  `FriendEdge.from`, `FriendEdge.to`, `Post.author`, `Reaction.post`,
  **`Reaction.author`**,
  `Block.from`, `Block.to`, and SORTABLE on `Post.practicedAt`. Profile and
  Username are fetched by record name and never queried, so they need no
  index. Security roles `_world` read / `_creator` write on each; AND the
  four new `CD_Preferences` fields
  (`evidenceGrantRemaining`, `evidenceGrantSince`, `rewardedFriends`,
  `grantedSessionIDs`). Run the schema primer on a dev build, then deploy
  Development → Production. A promotion is a release step (the 1.0 lesson).
- [ ] **CloudKit PUBLIC schema: `Post` gained four fields (2026-09-23) and
  lost one.** **Superseded 2026-09-29:** posting was removed 2026-09-27 and
  nothing writes these fields any more. The `Post` type and its `author`
  index are still needed (account deletion and the one-time clearing of old
  posts query them); the four media fields are not. Several photos and videos per post (Melvin: "you should be
  able to share multiple photos or videos") replaced the single `photo`
  Asset with four parallel List fields, all the same length, in order:
  `media` (Asset List, the full-resolution file per item), `mediaPosters`
  (Asset List, a small thumbnail per item), `mediaKinds` (String List,
  `"photo"` or `"video"`), `mediaAspects` (Double List, width / height, so
  the feed can lay the strip out before anything downloads). Same rule as
  every other field here: get them into Development first (post a session
  with two photos and a video from a DEBUG build signed in to iCloud, since
  the old `photo` field never had a List counterpart to inherit), then
  deploy. The old `photo` field can stay; nothing reads it and CloudKit does
  not require removing fields. `CLOUDKIT_SETUP.md`'s Post table has the
  full, current list.
- [ ] **CloudKit PRIVATE schema, everything synced since the 2026-09-12
  promotion** (added 2026-09-23: CLAUDE.md said `SessionPhoto` was on this
  list and it was not). The new `CD_SessionPhoto` record type (`sessionID`,
  `takenAt`, `jpeg`, `thumbnail`, `video`, `order`, `createdAt`. `order`
  added 2026-09-23, several photos per session, defaulted to 0 so every row
  saved before it existed still sorts first), `CD_Session.source`
  (2026-09-21), and check `CD_User.username` (added the morning of the
  promotion). Production rejects what it has never seen, so photos and
  phone sessions would stop syncing silently. `order` is a non-optional Int,
  so an ordinary photo save writes it (even at its default 0) the same as
  every other field; `video` is the one still OPTIONAL, and a nil field is
  never written, so get it into Development on purpose: save a session with
  a video, and set a username, from a DEBUG build signed in to iCloud.
  Deploy, then confirm Production lists them. (2026-09-29: plus
  `CD_Preferences.ownedHatIDs` and `wornHatID`; see step 2 above.)
- [ ] **Age rating questionnaire:** UGC and Social both flip to **Yes**.
  (2026-09-29: and Medical or Treatment Information to **Infrequent**; R10.)
- [ ] **App Privacy label:** add Photos or Videos, User Content, Name, User
  ID (linked, not tracking, App Functionality), to match the manifest.
  **Superseded 2026-09-29 by the ten-row table in `APP_STORE.md` (R9)**,
  which also adds Coarse Location, Other Usage Data and Other Data Types,
  and merges the two User ID rows into one linked row.
- [ ] **Redeploy the website** so `privacy.html` and `terms.html` carry the
  new sections. The bundled copies are updated; Cloudflare Pages is a manual
  drag-and-drop and the App Store links point at the website, not the bundle.
- [ ] **Report email path:** create the "808 friends reports" sheet, deploy
  `tools/community-reports.gs` (steps in its header), paste the /exec URL
  into `ReportClient.endpoint` (empty today, so nothing is sent), and file
  one real report to see the email arrive. (2026-09-29: BLOCKER, R2.)
- [x] **Photo screening entitlement:** DONE 2026-09-26 (see "NEXT
  RELEASE: 1.1" above).
- [x] **Flip `FeatureFlags.friendsInRelease` to true** in the archive that
  ships 1.1 (and update `FeatureFlagTests` in the same commit). **Moved to
  DONE 2026-09-29**: it is already `true` in `Coherence/FeatureFlags.swift`.
- [ ] **Camera string:** `NSCameraUsageDescription` already names the selfie
  and the profile photo; confirm the App Privacy label adds Photos or Videos.
  (2026-09-29: the selfie post is gone; the camera takes the profile photo
  and session photos or videos. Photos or Videos is on the 1.1 label.)
- [ ] **Store screenshots:** the Search tab is now Friends; re-shoot any
  screenshot showing the tab bar. **Superseded 2026-09-29 by R6** (re-shoot
  all of them).
- [ ] **TestFlight with the founders plus five friends** before the store.

**The two that would break Friends on day one, so do them first:**

1. **The Production schema.** Friends has never run against real iCloud
   (only the username claim has). The ~~six~~ **seven** (corrected
   2026-09-29) public record types need their
   QUERYABLE INDEXES, and indexes are never created lazily the way fields
   are: without them every ~~feed,~~ search and request query fails on a real
   install while working perfectly in the simulator's fake. This is the 1.0
   failure exactly, on a feature whose whole value is the server.
2. **One real round trip on two phones** before submitting: claim a
   username, add each other, ~~post a session, see it appear,~~ **check each
   other's practice summary after a session (corrected 2026-09-29, posts
   are gone),** report and block, then delete an account.
   Fifteen minutes, and it is the only thing that proves the above.

## 1.1 RESCORES EVERY EXISTING USER'S HISTORY. SAY SO.

1.0.1 shipped score v5.2 (stillness floored). 1.1 carries v5.3 (stillness
cubed) and migration `scoreBackfillDone.v8`, which rescores all history on
first launch. Measured on the real engine for a 15 minute sit whose heart
settled 8 beats: stillness 0.84 goes 61 to 76, 0.90 goes 75 to 82, 0.94 goes
84 to 86, 0.98 goes 93 to 90. So most people's old sessions JUMP several
points the moment they update.

Melvin hit this on the first TestFlight install and read it as his history
being overwritten with "random shit" (2026-09-19). If a founder reads it
that way, a stranger will file a one-star review.

- [ ] **What's New names it**, in one line: the score's stillness curve
  changed, past sessions were rescored on the same scale so the history
  graph still compares like with like, and no measurement changed.
  (2026-09-29: the 1.1 What's New in `marketing/APP_STORE_PASTE.md` carries
  it. Score 5.3.1, migration `scoreBackfillDone.v9`, also rescores on the
  session's wall-clock length; the same line covers both.)

## ALWAYS: every submission

- [ ] Version number bumped (`MARKETING_VERSION` in `project.yml`) and the
  What's New text names what changed.
- [ ] Archive from the org team: `TEAM=WLZQLLHUB3 ./tools/archive.sh`, and all
  five checks it prints read `ok`.
- [ ] `Store.previewFreeByDefault` is `false`. **Superseded 2026-09-29:**
  the constant is inside `#if DEBUG` (`Coherence/Store/Entitlements.swift`),
  so it cannot reach an archived Release build whatever its value, and 1.1
  has no free tier to preview. Checked instead, below.
- [ ] `Monetization.premiumOnly` and `Monetization.freeTrial` match App Store
  Connect: no introductory offer on `monthly` or `yearly` while `freeTrial`
  is false, and every product the paywall and ladder sell is attached.
- [ ] Every `FeatureFlags.*InRelease` value is the one the founders chose for
  this build, and the listing, review notes and screenshots describe only
  what those flags switch on.
- [ ] Store screenshots still match the app (compare against the current UI).
- [ ] Full test suite green.
- [ ] Release setting chosen on purpose (automatic vs manual).
- [ ] Tell Melvin before pulling anything from review.

## Standing rules (never ticked, never forgotten)

- **Waitlist script:** if `tools/nowatch-waitlist.gs` changes, redeploy it as a
  NEW VERSION of the existing deployment (Deploy → Manage deployments →
  pencil → New version). Never a new deployment: that changes the URL and
  every installed copy of the app keeps posting to the dead one.
- **Privacy manifest and labels change together.** Any new data leaving the
  phone means: manifest, both privacy policy copies, and the App Store label,
  in the same submission.

## DONE

(Move items here with the date they were done.)

- [x] **2026-09-29 (recorded):** `FeatureFlags.friendsInRelease = true`,
  done on `social-1.1` on 2026-09-18 and carried to `block`;
  `FeatureFlagTests` asserts it. (From "OPEN for 1.1 (Friends)".)
- [x] **2026-09-29 (recorded; decided 2026-09-25, Melvin):** people who
  installed 1.0 or 1.0.1 for free meet the paywall when they update; anyone
  who bought a plan or Lifetime keeps access. The review notes and What's
  New say so. (From "NEXT RELEASE: 1.1", step 3.)
- [x] **2026-09-29:** listing, review notes, What's New, IAP table, privacy
  label table and age-rating answers rewritten for 1.1
  (`marketing/APP_STORE_PASTE.md`, `APP_STORE.md`). Pasting them into App
  Store Connect is still open (R16).
