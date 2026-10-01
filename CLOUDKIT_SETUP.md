# CloudKit Console setup for Friends (1.1)

For Aziz, with Melvin. Everything here was read off the code on branch
`social-1.1`, not from memory: the record types come from
`CommunityType`, the fields from each `apply(to:)` in
`CommunityRecords.swift`, and the indexes from every `CommunityQuery` in
`CommunityStore.swift`. If the code changes, re-derive rather than trusting
this page.

**Container:** `iCloud.com.lockout.meditate808`
**Database:** PUBLIC (not Private)
**Console:** https://icloud.developer.apple.com/dashboard

**Status (2026-09-19, Melvin; moved here from `BACKLOG.md` in the
2026-09-23 sweep):** steps 1 to 4 are done. Development has the 14 fields,
the seven indexes and the roles, and Production lists all seven Friends
types, so the table below shows the state before that work. Step 5, the
round trip on two real phones, is still owed. TestFlight talks to
Production; a beta install reaches this container only with
`WITH_ICLOUD=1` (see `BACKLOG.md` > Standing notes).

**2026-09-29 update, re-derived from the code on branch `block` (the 1.1
build).** Four changes since the 2026-09-23 note below:

1. **Posting is gone (2026-09-27).** Nothing writes `Post` or `Reaction` any
   more. Both types stay, with their `author` indexes, because account
   deletion and the one-time clearing of each person's old posts
   (`CommunityModel.clearMyPostsIfNeeded`) still query them.
2. **`Profile` gained five fields**, the practice summary anyone who looks up
   a username can see: `sessions7d`, `minutes7d`, `currentStreak`,
   `totalSessions`, `lastSessionAt`. See the Profile table.
3. **`Report` must not be world-readable.** Step 4 has the roles.
4. **The private database** (each person's own sync) has fields to promote
   too; they now have their own section, "The private database".

The round trip (Step 5) is rewritten for profiles without posts.

**2026-09-29, later the same day: `Block` becomes private (Melvin: "Don't
want others to see who I blocked").** The code on `block` no longer reads
anyone else's blocks: the one Block read left is `from == me`
(`CommunityStore.myBlocks`), and a block is enforced entirely on the
blocker's side. That lets `Block` lose world Read (Step 4), drops the need
for the `Block.to` index (Step 3), and new blocks get random record names
(`block-<UUID>`, the Block table). **Order matters: ship the build that no
longer reads others' blocks BEFORE removing world Read in Production.** See
"Making Block private" at the end of Step 4.

**2026-09-23 update, NOT reflected in the snapshot table below (it is dated
2026-09-19 on purpose):** `Post` gained four fields and lost one — several
photos and videos per post replaced the single `photo` Asset with `media`,
`mediaPosters`, `mediaKinds` and `mediaAspects` (all Lists, same length, same
order). None of these four are in Development yet. No new index: nothing
queries them. See the **Post** field table below, which IS kept current with
the code, and `RELEASE_CHECKLIST.md` > "OPEN for 1.1" for the promotion step.

## Why this is the blocking step

Fields appear in the Development schema **lazily**, the first time the app
writes one. Indexes never do. So a build can work perfectly against a
simulator's fake database and fail on every screen on a real phone, because
each query needs an index that only a human can add here.

That is exactly how 1.0 broke: it shipped with a Production environment that
had no record types, and every sign-in's sync failed silently for two days.
Friends is worse if it happens again, because the feed, search and friend
requests are the whole feature.

**Nothing is submitted until step 5 passes on two real phones.**

---

## What is actually there (read off the Console, 2026-09-19)

All seven record types already exist in Development. Four of them have **no
fields at all**, only the six system metadata rows, because nobody has ever
added a friend, reacted, blocked or reported against this container. **Zero
indexes exist.**

| Type | Custom fields present | Missing |
|---|---|---|
| Post | all 11 | none |
| Profile | 4 | `avatar` |
| Username | 1 | none |
| FriendEdge | 0 | `from`, `to`, `createdAt` |
| Reaction | 0 | `post`, `author`, `createdAt` |
| Block | 0 | `from`, `to` |
| Report | 0 | `reporter`, `target`, `targetType`, `reason`, `createdAt` |

**Production never creates fields lazily.** Development does, on first write;
Production only ever gets what a promotion hands it. So every field the app
writes must exist in Development BEFORE deploying, or the write fails in
Production exactly the way 1.0's sync did. Step 2 is therefore adding the 14
missing fields by hand, not creating types.

Note (corrected 2026-10-01): a beta installed WITHOUT `WITH_ICLOUD=1` has no
iCloud at all; WITH it, it writes to `iCloud.com.lockout.meditate808`
(Development). It never used a `.dev` container. Only a normal Xcode build on the production bundle id
touches this one.

## Step 1: check what Development already has

Console → your container → **Schema → Record Types**, Development.

Friends has never run against real iCloud beyond one username claim, so
expect most of this to be missing. Whatever is there, the list below is what
must exist by the end.

## Step 2: add the 14 missing fields

Record Types → pick the type → under **Record Fields** press **+** → type the
name, pick the type → **Save Changes**. Field names are case-sensitive.

- **FriendEdge**: `from` Reference, `to` Reference, `createdAt` Date/Time
- **Reaction**: `post` Reference, `author` Reference, `createdAt` Date/Time
- **Block**: `from` Reference, `to` Reference
- **Report**: `reporter` Reference, `target` Reference, `targetType` String,
  `reason` String, `createdAt` Date/Time
- **Profile**: `avatar` Asset
- **Profile** (added 2026-09-29, the practice summary): `sessions7d`
  Int(64), `minutes7d` Int(64), `currentStreak` Int(64), `totalSessions`
  Int(64), `lastSessionAt` Date/Time. A 1.1 DEBUG build signed in to iCloud
  writes them (`CommunityModel.syncPracticeStats`, at launch and on each
  return to the app, once a profile exists), which creates them in
  Development; `lastSessionAt` is written only once a session exists, so sit
  one first. Check all five are there before deploying.

The full field list for every type, for checking against:

**Profile** — one per iCloud user, record name `profile-<userRecordName>`.
Readable by anyone who looks up the username.
| Field | Type |
|---|---|
| `username` | String |
| `displayName` | String |
| `firstSessionAt` | Date/Time |
| `createdAt` | Date/Time |
| `avatar` | Asset |
| `sessions7d` | Int(64): sessions in the last 7 days |
| `minutes7d` | Int(64): minutes meditated in the last 7 days |
| `currentStreak` | Int(64): the current streak, in days |
| `totalSessions` | Int(64): every session ever |
| `lastSessionAt` | Date/Time: when the last session was |

The five practice fields come from `PracticeStats` in
`CommunityRecords.swift` and carry counts and minutes only, never a score
or any measurement.

**Username** — the handle reservation, record name `username-<handle>`
| Field | Type |
|---|---|
| `profile` | Reference |

**FriendEdge** — one per direction, record name `edge-<from>-<to>`
| Field | Type |
|---|---|
| `from` | Reference |
| `to` | Reference |
| `createdAt` | Date/Time |

**Post** — record name derives from the session. **No 1.1 build writes a
Post (posting removed 2026-09-27).** The type and `author` stay so account
deletion and the one-time clearing of old posts can find them; the fields
below are the record of what older builds wrote.
| Field | Type |
|---|---|
| `author` | Reference |
| `title` | String |
| `caption` | String |
| `technique` | String |
| `sound` | String |
| `minutes` | Int(64) |
| `streak` | Int(64) |
| `media` | Asset List — the full-resolution file per item: the photo, or the exported video |
| `mediaPosters` | Asset List — a small JPEG per item, for the feed's strip |
| `mediaKinds` | String List — `"photo"` or `"video"`, one per item |
| `mediaAspects` | Double List — width / height of each item, so the feed can lay the strip out before anything downloads |
| `practicedAt` | Date/Time |
| `createdAt` | Date/Time |

The four `media*` fields are parallel: same length, same order, index `i`
in one is the same item as index `i` in the others. Replaced the single
`photo` Asset field (2026-09-23, several photos and videos per post). The
old `photo` field can be left in Development and Production; nothing reads
it any more.

**`score` was dropped from Post the same day, for a different reason (the
founders' call): it is derived from heart rate, and guideline 5.1.3(ii)
forbids storing personal health information in iCloud with no consent
exception.** The field cannot be deleted from an existing schema, so it can
be left in Development and Production too, holding whatever old posts
already wrote to it; the app no longer writes or reads it, so nothing shows
it again. The score itself is untouched everywhere it lived outside this
container: the private session page, the results screen, and a shared card,
which is the person's own act and not our storage.

**Reaction** — record name `react-<post>-<author>`. No 1.1 build writes one
either; account deletion still queries them by `author`.
| Field | Type |
|---|---|
| `post` | Reference |
| `author` | Reference |
| `createdAt` | Date/Time |

**Block** — record name `block-<UUID>` (random since 2026-09-29; blocks
written earlier carry `block-<from>-<to>`, and the app still finds and
removes those by querying its own). **Readable by its creator only** (Step 4).
| Field | Type |
|---|---|
| `from` | Reference |
| `to` | Reference |

Why random: with creator-only Read, a name anyone can work out from two
public profile names would still let someone ask CloudKit whether that
record exists (by fetching it, or by trying to create it) and learn who
blocked whom without reading a field. It would also let someone create my
block's name before I do and stop me blocking them.

**Report**. Written by the app, never read by it. Not world-readable (Step 4).
| Field | Type |
|---|---|
| `reporter` | Reference |
| `target` | Reference |
| `targetType` | String |
| `reason` | String |
| `createdAt` | Date/Time |

## Step 3: add the indexes

This is the part that cannot be skipped and cannot be done from the app.

Each record type has an **Indexes** tab. Add exactly these. Anything not
listed is deliberately absent: `Profile` and `Username` are **fetched by
record name, never queried**, which is why they need no index at all.

| Record type | Field | Index |
|---|---|---|
| FriendEdge | `from` | QUERYABLE |
| FriendEdge | `to` | QUERYABLE |
| Post | `author` | QUERYABLE |
| Post | `practicedAt` | SORTABLE |
| Reaction | `post` | QUERYABLE |
| Reaction | `author` | QUERYABLE |
| Block | `from` | QUERYABLE |

Seven indexes, five record types. **`Block.to` is no longer needed
(2026-09-29)**: no code queries it any more, because nobody's app may read
another person's blocks. If it is already in Development or Production,
leave it: an index grants no read access (Security Roles decide that), and a
deploy never removes one anyway. Do not add it anywhere it is missing. Where
the rest come from, so you can check the reasoning rather than trust the
table:

- `FriendEdge.from` / `.to`: every friends, followers, following, requests
  and relationship read is an equality query on one of them.
- `Post.author`: the feed and a person's posts are `author IN [...]`.
  (2026-09-29: the feed is gone; account deletion and the one-time clearing
  of old posts still query `author`, so this index stays essential.)
- `Post.practicedAt`: the feed sorts on it, descending. Sorting needs
  SORTABLE, which is a different box from QUERYABLE. (2026-09-29: no 1.1
  screen reads it. Already in Development; leaving it costs nothing, and
  indexes are never removed by a deploy anyway.)
- `Reaction.post`: reactions are fetched for a batch of posts. (2026-09-29:
  same as `practicedAt`, no 1.1 reader.)
- `Reaction.author` (NEW, 2026-09-23): account deletion queries every
  reaction I gave, across every post, so it can delete them — the only
  reader of this index is `CommunityStore.deleteEverythingOfMine()`, not the
  feed. Add it in Development and deploy it the same way as the rest of this
  table; without it, deleting an account leaves the person's reactions
  visible on other people's posts forever.
- `Block.from`: the only Block query left (`CommunityStore.myBlocks`), my own
  blocks, run by search, profile pages, every friends and requests list, the
  follower and following lists, and account deletion. It needs the
  creator-only role in Step 4 to still answer, which it does: every record it
  asks for is one the asker created.

## Step 4: security roles

On each of the seven types EXCEPT `Report` and `Block` (both below),
**Security Roles**:

- `_world`: **Read**
- `_creator`: **Read, Write, Create**

Only the creator can ever modify a record, which is the constraint the whole
design is built on: a friendship is two edges because each person can only
write their own half.

**`FriendEdge` is world-readable, and that is a disclosure, not an accident
(2026-09-29, second pass).** With `_world` Read, anyone signed in to iCloud
can query who follows whom (`FriendEdge.from` / `.to`, which are also what a
profile's followers and following show). The app needs it: every friends,
followers, following and request list reads other people's edges.

**`Block` is NOT world-readable any more. DECIDED 2026-09-29 (Melvin: "Don't
want others to see who I blocked").** It was, because the app used to check
blocks in both directions (`CommunityStore.isBlocked` fetched the other
person's block, and every list queried `Block.to == me`). The code on
`block` now reads only the blocks the current person created, so the type
can be creator-only. Taken from the second option this section used to
offer, with its cost accepted: the blocked person's app can no longer learn
it was blocked, so it can still see the blocker's public profile and send a
request, which never arrives (the blocker's app filters it out and refuses
to accept it). See "Making Block private" below for the roles and the order.

**Except `Report` (2026-09-29): take Read away from `_world`.** A report holds
the reporter's profile reference and the words they wrote about someone else;
with world Read, anyone signed in to iCloud could query who reported whom. The
app only ever writes a report (`CommunityStore.report`) and never reads one,
so it loses nothing. On `Report`:

- `_world`: **no permissions**
- `_icloud`: **Create** (any signed-in person can file one)
- `_creator`: **Read, Write** (the reporter can see and amend their own)

Set it in Development and confirm Production after the deploy; a Security
Roles change is part of the schema that a deploy promotes, but check it in the
Production Console anyway.

### Making Block private (2026-09-29)

On `Block`, the same roles as `Report`:

- `_world`: **no permissions** (take Read away)
- `_icloud`: **Create** (any signed-in person can block someone)
- `_creator`: **Read, Write** (the blocker can list, and delete, their own:
  the Blocked list, Unblock, and account deletion all need both)

**Order, and it matters:**

1. **Ship the code first.** Every build that reads another person's blocks
   (anything built from before this change: it fetched `block-<them>-<me>`
   and queried `Block.to == me` on every Friends list) stops working the
   moment world Read goes, so Production keeps world Read until the build
   that never reads others' blocks is the one people run. Friends has not
   been on the App Store yet, so in practice "people" means testers: have
   every tester phone on a build with this change before step 3.
2. **Development first.** Change the role in Development, run the Step 5
   round trip there (block, unblock, and check that blocking still works on
   BOTH phones), then deploy Development to Production (Step 6).
3. **Production.** Confirm in the Production Console that `Block` shows
   `_world` with no Read after the deploy; a role change is promoted with the
   schema, but check it.

**Check once in Development, before relying on it:** that a query of
`Block.from == me` still answers normally when other people's Block records
exist (CloudKit should leave out records the asker cannot read; a query that
failed outright instead would break every Friends list). Two phones: block
someone on each, then open Friends on both. `CommunityStore.myBlocks` also
drops anything not authored by the asker, so a stray record could only ever
be ignored, never believed.

**Old-format blocks.** Blocks written before this change are named
`block-<from>-<to>`. They keep working (the app finds them by `from == me`
and Unblock deletes them), but their NAME still says who blocked whom, which
a fetch-by-name probe could test for. Only testers have any. Have each
tester unblock and block again (the new block gets a random name), or delete
Block records with that name shape in the Console, which unblocks them, and
let the tester block again. Do it before counting the change as done.

**The ban path (check in Production, 2026-09-29).** The app cannot remove
anyone else's records, by design. Removing an abusive profile therefore means
deleting that person's `Profile` and `Username` records by hand in the
**Production** Console (Data, public database, query by record name
`profile-<id>` or `username-<handle>`). Confirm that the developer account can
actually delete a record it did not create there, before submitting; if it
cannot, there is no way to act on a report.

## The private database (each person's own sync)

Separate from Friends, and just as silent when it breaks: SwiftData syncs
`User`, `Preferences`, `Session`, `SessionReflection` and `SessionPhoto` to the
person's PRIVATE database as `CD_` record types (never `MeditationStats`, which
stays on the device). Production rejects a field it has never seen, so every
field added since the 2026-09-12 promotion must be in Development before the
deploy. Read off `Shared/Models/` on 2026-09-29:

| Record type | Fields added since 2026-09-12 |
|---|---|
| `CD_Preferences` | `evidenceGrantRemaining`, `evidenceGrantSince`, `rewardedFriends`, `grantedSessionIDs`, **`ownedHatIDs`**, **`wornHatID`** |
| `CD_SessionReflection` | `title`, `publicNote`, `visibility` |
| `CD_Session` | `source` |
| `CD_User` | `username` (added the morning of the promotion; check it) |
| `CD_SessionPhoto` (new type) | `sessionID`, `takenAt`, `jpeg`, `thumbnail`, **`video`**, **`order`**, `createdAt` |

`ownedHatIDs` and `wornHatID` belong to the Shop, which is off in 1.1, but they
are non-optional with empty-string defaults, so every Preferences save writes
them regardless. `video` is the one optional field here, and a nil field is
never written: save a session with a video from a DEBUG build signed in to
iCloud so it reaches Development. The CoreData field names carry a `CD_`
prefix in the Console (`CD_video`, `CD_order` and so on).

## Step 5: the real round trip, BEFORE deploying to Production

Two phones, both on the "808 Beta" installed with `WITH_ICLOUD=1
./tools/beta_install.sh <UDID>` (it talks to `iCloud.com.lockout.meditate808`,
Development environment), different iCloud accounts. Aziz's phone has it as
of 2026-10-01. This is
still Development, so mistakes are cheap. **Rewritten 2026-09-29 for profiles
without posts.**

1. **Claim** a username on each (Create your profile, agreeing to the
   community rules).
2. **Search** for the other by username. The profile and its practice
   summary show before any friendship: anyone who looks up a username sees it.
3. **Request**: send a friend request from phone A.
4. **Accept** it on phone B. Both friends lists show the other; followers and
   following read correctly on both profiles.
5. **Check the summary**: sit a session on phone A, return to Friends on
   phone B and pull to refresh. Sessions and minutes this week, streak, total
   and last session update (a relaunch of A forces the publish if it lags).
6. **Report** phone A's profile from phone B. The report saves without an
   error (and, once `ReportClient.endpoint` is set, the email arrives).
7. **Block** phone A from phone B (one-sided and private since 2026-09-29):
   the friendship ends on BOTH phones. On B, A is gone from search, lists
   and requests. On A nothing says it was blocked: A can still find B and
   send a request, which never shows on B, and B cannot accept it. Unblock
   from Requests > Blocked on B. Run this with `Block` already creator-only
   in Development (Step 4, "Making Block private"), so every Friends screen
   is proven to work without world Read.
8. **Delete account** on phone A (Settings, Profile tab, gear). On phone B,
   searching A's username finds nothing and A leaves the friends list. The
   handle can be claimed again.

**If any screen is empty or spins, it is almost certainly a missing index**,
not a bug in the app. Come back to step 3.

## Step 6: deploy Development to Production

Only once step 5 passes.

Console → **Deploy Schema Changes** → review → Deploy.

The promotion is **additive and one-way**: it adds types, fields and indexes
to Production and never removes anything. Read the diff before confirming.

## Step 7: verify Production

Switch the Console's environment selector to **Production** and confirm all
seven record types are listed with their indexes. The App Store build talks
to Production; TestFlight does too. The beta on a cable talks to
Development, which is why the beta working proves nothing about this.

---

## After the deploy, in Production (added 2026-09-29)

- **Bulk-delete test `Post` and `Reaction` records** left by TestFlight
  rounds from when posting existed. Each person's own posts are cleared on
  their next launch of 1.1, but a test account that never launches 1.1 would
  leave its records in the public database for good.
- **Confirm the ban path and the Report roles** (Step 4) in the Production
  Console, not just Development.

## What is still owed after this, and is not CloudKit

Full list in `RELEASE_CHECKLIST.md` under "OPEN for 1.1" and "OPEN for 1.1:
release-docs pass".

- Age rating questionnaire: **UGC and Social both flip to Yes**, and Medical
  or Treatment Information to Infrequent (2026-09-29).
- App Privacy labels: ~~add Photos or Videos, Other User Content, Name, User
  ID, all linked, App Functionality, to match `PrivacyInfo.xcprivacy`~~
  (superseded 2026-09-29) the ten-row table in `APP_STORE.md`, checked
  against `PrivacyInfo.xcprivacy` in the archived build.
- Redeploy the website so the live privacy policy and terms carry the new
  sections. The bundled copies are already updated; Cloudflare Pages is a
  manual drag of the `website` folder, and the App Store links point at the
  website.
- Deploy `tools/community-reports.gs` and paste its `/exec` URL into
  `ReportClient.endpoint`, which is empty today. Reports are written to
  CloudKit either way, but nobody is notified, and guideline 1.2 expects a
  path that reaches a person within 24 hours. **A blocker (2026-09-29).**
- Store screenshots: ~~the Search tab is now Friends~~ every one must be
  re-shot from a 1.1 Release build (2026-09-29).
- TestFlight with the founders plus a few friends.
