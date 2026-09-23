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

Note: the 808 Dev beta writes to `iCloud.com.lockout.meditate808.dev`, a
different container. Only a normal Xcode build on the production bundle id
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

The full field list for every type, for checking against:

**Profile** — one per iCloud user, record name `profile-<userRecordName>`
| Field | Type |
|---|---|
| `username` | String |
| `displayName` | String |
| `firstSessionAt` | Date/Time |
| `createdAt` | Date/Time |
| `avatar` | Asset |

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

**Post** — record name derives from the session
| Field | Type |
|---|---|
| `author` | Reference |
| `title` | String |
| `caption` | String |
| `technique` | String |
| `sound` | String |
| `score` | Int(64) |
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

**Reaction** — record name `react-<post>-<author>`
| Field | Type |
|---|---|
| `post` | Reference |
| `author` | Reference |
| `createdAt` | Date/Time |

**Block** — record name `block-<from>-<to>`
| Field | Type |
|---|---|
| `from` | Reference |
| `to` | Reference |

**Report**
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
| Block | `from` | QUERYABLE |
| Block | `to` | QUERYABLE |

Seven indexes, five record types. Where they come from, so you can check the
reasoning rather than trust the table:

- `FriendEdge.from` / `.to`: every friends, followers, following, requests
  and relationship read is an equality query on one of them.
- `Post.author`: the feed and a person's posts are `author IN [...]`.
- `Post.practicedAt`: the feed sorts on it, descending. Sorting needs
  SORTABLE, which is a different box from QUERYABLE.
- `Reaction.post`: reactions are fetched for a batch of posts.
- `Block.from` / `.to`: blocks are checked in both directions on every read
  and every write.

## Step 4: security roles

On each of the seven types, **Security Roles**:

- `_world`: **Read**
- `_creator`: **Read, Write, Create**

Only the creator can ever modify a record, which is the constraint the whole
design is built on: a friendship is two edges because each person can only
write their own half.

## Step 5: the real round trip, BEFORE deploying to Production

Two phones, both on the 808 Dev beta, different iCloud accounts. This is
still Development, so mistakes are cheap.

1. Claim a username on each.
2. Search for each other by username and send a request.
3. Accept it on the other phone.
4. Sit a session, set it to Friends, take the selfie, save.
5. Check it appears in the other person's feed, with the photo.
6. Tap the reaction.
7. Check followers and following read correctly on both profiles.
8. Report the post from the other phone, then block, then unblock.

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

## What is still owed after this, and is not CloudKit

Full list in `RELEASE_CHECKLIST.md` under "OPEN for 1.1".

- Age rating questionnaire: **UGC and Social both flip to Yes**.
- App Privacy labels: add Photos or Videos, Other User Content, Name, User
  ID, all linked, App Functionality, to match `PrivacyInfo.xcprivacy`.
- Redeploy the website so the live privacy policy and terms carry the new
  sections. The bundled copies are already updated; Cloudflare Pages is a
  manual drag of the `website` folder, and the App Store links point at the
  website.
- Deploy `tools/community-reports.gs` and paste its `/exec` URL into
  `ReportClient.endpoint`, which is empty today. Reports are written to
  CloudKit either way, but nobody is notified, and guideline 1.2 expects a
  path that reaches a person within 24 hours.
- Store screenshots: the Search tab is now Friends.
- TestFlight with the founders plus a few friends.
