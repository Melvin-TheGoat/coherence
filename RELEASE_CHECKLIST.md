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

## OPEN: must be done in the submission that ships the next build

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
- [ ] **Report email path** (`tools/community-reports.gs`) deployed and
  tested with one real report.
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
