# Before you submit a build

Read this top to bottom before pressing "Add for Review" in App Store Connect.
`tools/archive.sh` prints the OPEN section at the end of every archive, and a
Claude session asked to submit must go through it with you first.

Tick an item by moving it to DONE with the date. Never delete a line.

## HOLD

- **1.0.2 (build 202609141719) is uploaded and NOT submitted. Do not create
  the version, attach the build or press Add for Review until Aziz says so**
  (2026-09-14: "there is a decent amount I want to do before we do that").
  More changes will likely go into this version first, which means a new
  archive; this build may never ship.

## WHAT THE NEXT BUILD CONTAINS (read before archiving)

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

## OPEN: must be done in the submission that ships the next build

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
  review flag. Publish the label change before submitting.

- [ ] **Website: redeploy.** Drag the `website/` folder into Cloudflare Pages
  (Workers & Pages → meditate808 → Create deployment). Why: `privacy.html`
  gained the in-app waitlist paragraph (dated September 14, 2026). The app
  and the website must say the same thing on the day the build goes live.

- [ ] **One real no-Watch signup on the new build.** After the update is
  live, install it on a phone, answer "no" at "Do you have an Apple Watch?",
  join the waitlist with a throwaway address, and confirm a row appears in
  the **808 no watch waitlist** sheet. Then delete that row.

## OPEN for 1.1 (Friends), before that build is submitted

- [ ] **CloudKit Console, `iCloud.com.lockout.meditate808`:** the six PUBLIC
  record types (Profile, FriendEdge, Post, Reaction, Block, Report) with
  queryable indexes on `username`, `from`, `to`, `author`, `post`,
  `practicedAt`, `createdAt`; security roles `_world` read / `_creator`
  write on each; AND the four new `CD_Preferences` fields
  (`evidenceGrantRemaining`, `evidenceGrantSince`, `rewardedFriends`,
  `grantedSessionIDs`). Run the schema primer on a dev build, then deploy
  Development → Production. A promotion is a release step (the 1.0 lesson).
- [ ] **Age rating questionnaire:** UGC and Social both flip to **Yes**.
- [ ] **App Privacy label:** add Photos or Videos, User Content, Name, User
  ID (linked, not tracking, App Functionality). `PrivacyInfo.xcprivacy`
  matches in the same build.
- [ ] **Privacy policy, both copies:** a "Friends and posts" section; the
  "we transmit nothing we can read" line is no longer true.
- [ ] **Terms of use:** a user-content section (no tolerance for
  objectionable content; repeat offenders removed).
- [ ] **Report email path:** create the "808 friends reports" sheet, deploy
  `tools/community-reports.gs` (steps in its header), paste the /exec URL
  into `ReportClient.endpoint` (empty today, so nothing is sent), and file
  one real report to see the email arrive.
- [ ] **Photo screening entitlement:** add
  `com.apple.developer.sensitivecontentanalysis.client` to
  `Coherence/Coherence.entitlements` and enable it on the App ID. Without it
  `PhotoScreen` lets every photo through (reports remain the backstop). Left
  out on purpose so the Friends-off build did not change entitlements.
- [ ] **Flip `FeatureFlags.friendsInRelease` to true** in the archive that
  ships 1.1 (and update `FeatureFlagTests` in the same commit).
- [ ] **Camera string:** `NSCameraUsageDescription` already names the selfie
  and the profile photo; confirm the App Privacy label adds Photos or Videos.
- [ ] **Store screenshots:** the Search tab is now Friends; re-shoot any
  screenshot showing the tab bar.
- [ ] **TestFlight with the founders plus five friends** before the store.

## ALWAYS: every submission

- [ ] Version number bumped (`MARKETING_VERSION` in `project.yml`) and the
  What's New text names what changed.
- [ ] Archive from the org team: `TEAM=WLZQLLHUB3 ./tools/archive.sh`, and all
  five checks it prints read `ok`.
- [ ] `Store.previewFreeByDefault` is `false`.
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
