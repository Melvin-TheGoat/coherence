# Friends: the community feature (design, 2026-09-14)

> **Built, and changed since (checked in the 2026-09-23 sweep).** Friends is
> built behind `FeatureFlags.friends` (see "Build status" at the end), and
> CLAUDE.md records what moved after this was written: follower and
> following counts (2026-09-18); the invite reward is 3 sessions, capped at
> 15 (2026-09-15); the selfie rule is gone, so a post takes any photo and a
> session can hold a video (2026-09-22); a post's score went from required,
> to optional (2026-09-22), to gone entirely (2026-09-23, the founders' call
> — see "The rule for what a post may carry" below); the tab is in the
> valley (2026-09-22). Ideas still open are in `BACKLOG.md` > Potential
> features.

Aziz's ask: after a meditation, post the session with a photo to your
friends, the way a Strava run goes to your feed. Friends, not followers.
Use it to get people inviting each other, and reward the inviting.

This file is the decision record. The mockup is `mockups/friends.html` and
must be reviewed before any Swift (standing rule).

## What ships in v1, and what does not

**In:** mutual friends (request, accept), a feed of friends' posts, a post
made from the results screen (photo optional, caption optional, minutes,
streak, technique, never a score), one reaction per post, a friend's
profile, report and block, an invite link, the invite reward, a username
claim.

**Out, on purpose:** comments (every text field is a moderation surface;
reactions carry the whole Strava kudos loop without one), clubs, leaderboards,
follower or friend counts anywhere public, contact-list matching (uploads
phone numbers, changes the privacy label, and is the feature people quietly
resent), push notifications (the tab checks on open; a badge is enough), a
public feed of strangers (guideline 1.2 treats stranger-to-stranger content
as the full UGC case and we want none of that surface).

## Why it is worth building, and what it is really for

Strava's own numbers say kudos drive activity: the peer-reviewed study
(Social Networks, 2022) found runners who received kudos ran more and more
often, and social streaks run longer than private ones. That is the retention
argument. But 808 has 33 installs. A feed with no friends in it is an empty
room, so for the next few months this feature earns its keep as the
**invite loop**, not the feed: the only reason to bring a friend into 808 is
that something happens between you once they are there. Build the thin
version that makes inviting worth doing, then let the feed grow into the
retention feature when there are people in it.

## The rule for what a post may carry

**A post carries the free share card's data minus its one number: minutes,
streak, the technique, a photo and a caption. Never a score, a heart-rate
number, a breath rate, a stillness value, or a curve.** Two reasons and both
are hard:

1. Guideline 5.1.3(ii) forbids storing personal health information in
   iCloud. The public CloudKit database is iCloud. A heart-rate delta is
   HealthKit data and does not go, full stop.
2. The free tier rule: free gives you the score, paid gives you the evidence.
   A post showing curves would be the way around the lock, for the author
   and for everyone reading.

**Score was on this list at first and came out 2026-09-23 (the founders'
call).** The original argument was that the score is a derived number the
user already publishes to Instagram by hand, so a deliberate "Post" tap
could be treated the same way. That argument holds for SHARING a card,
which is the person's own act each time; it does not hold for us STORING
the number indefinitely in a database we can read, which a post does and a
shared card never did. Whether a coarse 0-100 score derived from heart rate
counts as "personal health information" under 5.1.3(ii) was genuinely
arguable either way (the reasoning is in `APP_STORE.md`'s App Privacy
notes), so the zero-risk answer was taken instead: a post never carries
one, whether or not the sit that produced it had one.

The post is drawn natively (photo on top, a stat strip below), not as the
rendered share-card image, so it can be themed and read at row size.

## Backend: CloudKit public database. No server.

Chosen over Supabase and Firebase because it keeps every answer we gave App
Review true (no server, no third-party service holding user content), costs
nothing at any scale we will see (1 PB of public storage comes with the
membership), needs no account system (the CloudKit user record is the
identity; Sign in with Apple stays the sign-in), and the container is already
entitled and promoted to Production. What it costs us: no server-side
logic, so moderation and feed assembly are client-side, and only the
record's creator can modify a public record. The model below is shaped
around that constraint rather than fighting it.

Record types (public database, `iCloud.com.lockout.meditate808`):

| Type | Fields | Written by |
|---|---|---|
| `Profile` | `username`, `displayName`, `avatar` (asset, optional), `firstSessionAt`, `createdAt` | the owner, once; edited by the owner |
| `FriendEdge` | `from` (ref Profile), `to` (ref Profile), `createdAt` | the `from` user |
| `Post` | `author` (ref), `minutes`, `streak`, `technique`, `caption`, `photo` (asset), `practicedAt`, `createdAt` | the author |
| `Reaction` | `post` (ref), `author` (ref), `createdAt` | the reactor |
| `Block` | `from` (ref), `to` (ref) | the blocker |
| `Report` | `reporter`, `target` (ref Post or Profile), `reason`, `createdAt` | the reporter |

- **A friendship is two edges.** A request is A writing `A → B`; accepting is
  B writing `B → A`; declining is doing nothing. Mutual edges are friends.
  This is the one shape where nobody ever needs to modify someone else's
  record. Removing a friend deletes your own edge.
- **The feed is one query:** `Post` where `author IN friends`, newest first,
  paged. Friend lists under a few hundred fit a single `IN` predicate.
- **Reactions are one per person per post,** enforced by the client
  (record name = `post.id + author.id`, so a second save overwrites, never
  duplicates).
- **Blocks live in the public database so they cut both ways** on honest
  clients: a blocked person's posts and requests vanish for the blocker, and
  the blocked person's client refuses to friend or view the blocker. A
  modified client could ignore that; at our size that is an accepted limit,
  and the same limit every CloudKit-only social app has.
- **Photos:** JPEG, longest side 1080, about 200 KB. `CKAsset`.
- **Usernames become real.** `Profile.username` is claimed on first use of
  the tab by querying for an existing one, then saving. The race between two
  people claiming the same name in the same second is resolved by a
  second query after save; the loser is asked again. Existing cosmetic
  usernames are offered as the default and may collide; the claim screen
  handles that honestly.

## Every post is a selfie (Aziz, 2026-09-14, "like BeReal")

No selfie, no post. The composer opens on a big "Take your selfie" area
that launches the FRONT camera; there is no photo library, so a post shows
you, sitting, today. Post stays disabled until the selfie exists, Retake
replaces it, and `CommunityStore.post` refuses a draft without one
(`CommunityError.selfieRequired`, `test_noSelfieNoPost`). An edit to an
existing post keeps its selfie. The first-post agreement is one line
("Post your own practice. Anything abusive or explicit gets taken down.")
because Aziz asked for less, and the "What goes out" section is gone. The
agreement itself stays: guideline 1.2 expects users to accept that abusive
content is not tolerated. DEBUG simulator builds only get a stand-in photo
picker, since the simulator has no camera.

## Post-session flow

Results screen → new row under the verdict: **"Post to friends"** (gold only
when Share has stepped down, one gold object per section). Opens the
composer: photo (camera or library, optional), caption (optional, 140
characters), the stat strip it will carry, the technique from the reflection
if one was set. **Post.** Back on results. The card on the feed is the photo,
minutes, streak, the technique, the caption. No score (2026-09-23): a post
never carries one.

The first post ever shows the **community rules** once (be kind, your own
practice only, no nudity, no harassment, we remove what is reported and
remove people who keep doing it) with an Agree button. Guideline 1.2
reviewers look for exactly this.

## Moderation, the four things guideline 1.2 requires

1. **Filter.** Captions run through a word list on device before save.
   Photos run through Apple's on-device Sensitive Content Analysis
   framework (iOS 17+, `SCSensitivityAnalyzer`) before upload; a flagged
   photo is refused with a plain message. This needs the
   `com.apple.developer.sensitivecontentanalysis.client` entitlement and is
   a real filter, not a promise of one.
2. **Report.** Every post and profile has Report in its menu. A `Report`
   record is written AND the same payload is posted to an Apps Script web
   app (the waitlist pattern) that emails support@meditate808.com, so a
   report reaches a person within minutes without a server.
3. **Block.** Every profile has Block. See the model above.
4. **Contact.** support@meditate808.com is published in the app and on
   the store page already.

Removal is manual: a reported post is deleted from the CloudKit Console.
Reviewers ask for a "timely" response; the email makes 24 hours realistic.

## The invite reward

Aziz's idea, adjusted to what Apple allows. Apple rejects rewarding the
INVITED person for installing (it pays for downloads and games the charts).
Rewarding the INVITER with your own digital content is common and accepted
(Duolingo gives Super time for referrals on iOS). So:

- **Trigger:** a friend request you sent is accepted AND that friend's
  profile shows a first session. Not on install, not on sign-up. Both facts
  are public records, so the client can verify them without a server.
- **Free users get the evidence for their next 3 sessions** (was 10 until
  2026-09-15, Aziz: "10 sessions is too much"; the cap went 50 → 15). Curves,
  tiles, readings, the four locked share layouts: the full paid results
  screen, ten times. It is the best possible taste of what paid is, and it
  is exactly the thing a free user cannot get any other way. Implemented as
  a grant in the private database (`Preferences.evidenceGrantRemaining`),
  decremented as each results screen is first opened, read by
  `Entitlements` as `paid || grantRemaining > 0`. Ten per friend, stacking,
  capped at 50 outstanding so a burst of invites cannot mint a year of
  premium.
- **Everyone gets the "Brought a friend" award** (the `AwardEngine` "did
  this ever happen" rule applies; `friendBroughtAt` is the first payout
  date). **Paid users also bank the three sessions**, which only matter if
  the membership lapses; they have nothing else to unlock. The Circle skin
  first proposed for them is NOT built: `CardSkin` exists as an enum with
  no drawing behind it, so a skin reward would mean building the skin
  system first. Revisit when skins are real.
- **Both tiers:** the profile shows the friend count only to you. No public
  counts, ever (Aziz).

Gaming it (a second Apple ID, one session) buys ten results screens of
curves. Not worth defending against in v1.

## The invite link

`meditate808.com/f/<username>`: a page on the site that says who invited
you, links to the App Store with `ct=invite`, and tells you to search that
username after installing. No install-time attribution exists without a
universal link plus a paste-board trick, and the reward does not need it:
the accepted request is the attribution. A universal link (associated
domains entitlement + an `apple-app-site-association` file on Cloudflare
Pages) can come later and would open straight to the friend's profile.

## What changes outside the code (the submission-day list)

- **Age rating questionnaire:** UGC and Social both flip to **Yes** (they
  were answered No in the 1.0 pass, deliberately). Expect the rating to
  move; Apple's 2026 tiers gate UGC apps by whether content is moderated.
- **App Privacy label:** add Photos or Videos, User Content (photos, other
  user content), Name, User ID; all linked, none for tracking, purpose App
  Functionality. `PrivacyInfo.xcprivacy` matches in the same build.
- **Privacy policy, both copies:** a "Friends and posts" section. The
  current line "we transmit nothing we can read" becomes false: posts are
  public to the author's friends and readable by us. Say so.
- **Terms of use:** a UGC section (no tolerance for objectionable content,
  we remove content and eject repeat offenders).
- **Entitlements:** Sensitive Content Analysis client. New entitlement means
  a fresh Beta App Review for the next TestFlight build.
- **CloudKit Console:** the six new public record types, indexes on
  `author`, `from`, `to`, `post`, `createdAt`; promote Development →
  Production before the build ships (this is a release step; see CLAUDE.md,
  the 1.0 lesson).
- **Public database security roles:** `_world` read, `_creator` write, on
  every type. Confirm in the Console; the defaults are right but check.

## Build order

1. Mockup review (this commit). Aziz and Melvin sign off on the six screens.
2. `Coherence/Community/CommunityStore.swift`: CloudKit public DB access,
   Profile claim, edges, feed query, post, react, block, report. Tests
   against a protocol-backed fake database, since CloudKit does not run in
   unit tests.
3. Screens: `FriendsTab` replaces `SearchTab` (feed, requests, search,
   empty state), `PostComposer` off results, `FriendProfileView`,
   `CommunityRulesSheet`, `InviteSheet`.
4. Reward: the grant in `Preferences` (`RewardLedger`), `Entitlements`
   reads it per session, the award. BUILT 2026-09-14.
5. Moderation: word list, sensitive content check, report script
   (`tools/community-reports.gs`, deployed once, edited only as new
   versions of that deployment).
6. Policy, terms, labels, manifest, age rating, Console promotion.
7. TestFlight with the founders and five friends before it goes to the
   store. It ships as **1.1**, not inside 1.0.2.

Three weeks of work at a realistic pace, and it must not stall 1.0.2.


## Build status (2026-09-14, end of day)

Everything above the moderation line is built and behind
`FeatureFlags.friends` (on in DEBUG, off in Release until 1.1):

- Data layer, Friends tab, invite reward, usernames reserved by record name.
- **Save session** opens after every live session (title, Friends / Only
  you, front-camera selfie for Friends, description, technique, private
  notes), then results. The results chip reopens it to change visibility;
  Only you takes the post down. Decisions taken at the v2 mockup's
  recommendations: score shown on Save, Friends default with a profile,
  username required except without iCloud, private notes never posted.
- **Create your profile** (photo + @username, nickname beside it) ends
  onboarding in Friends builds, is the Friends tab's first screen, and backs
  Edit profile. **FriendsIntroView** asks existing users once they have no
  profile, with no skip.
- **Strava-shaped feed cards** and a profile with photo, Edit profile, Share
  profile and a private friend count.
- **Moderation:** `ContentFilter` (Shared, on-device, whole-word after
  normalisation, catches f*ck / fvck / f u c k, passes Scunthorpe) runs on
  titles, captions, nicknames and handles in the store itself;
  `PhotoScreen` uses Sensitive Content Analysis when the entitlement exists
  and the user has Sensitive Content Warning on, otherwise it cannot screen
  and lets the photo through; `ReportClient` + `tools/community-reports.gs`
  email each report (inert until deployed).

Open for 1.1 (RELEASE_CHECKLIST.md): CloudKit public record types and
indexes, the entitlement, the report script, age rating, privacy labels,
policy and terms, store screenshots, and a TestFlight on two real phones.
Nothing has run against real iCloud yet beyond the username claim.
