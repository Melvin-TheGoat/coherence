# Friends: the community feature (design, 2026-09-14)

Aziz's ask: after a meditation, post the session with a photo to your
friends, the way a Strava run goes to your feed. Friends, not followers.
Use it to get people inviting each other, and reward the inviting.

This file is the decision record. The mockup is `mockups/friends.html` and
must be reviewed before any Swift (standing rule). Nothing here is built yet.

## What ships in v1, and what does not

**In:** mutual friends (request, accept), a feed of friends' posts, a post
made from the results screen (photo optional, caption optional, score,
minutes, streak, technique), one reaction per post, a friend's profile,
report and block, an invite link, the invite reward, a username claim.

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

**A post carries exactly what the free share card carries: score, minutes,
streak, the technique, a photo and a caption. Never a heart-rate number, a
breath rate, a stillness value, or a curve.** Two reasons and both are hard:

1. Guideline 5.1.3(ii) forbids storing personal health information in
   iCloud. The public CloudKit database is iCloud. The score is a derived
   number the user already publishes to Instagram by hand, and we treat a
   deliberate "Post" tap the same way. A heart-rate delta is HealthKit data
   and does not go, full stop.
2. The free tier rule: free gives you the score, paid gives you the evidence.
   A post showing curves would be the way around the lock, for the author
   and for everyone reading.

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
| `Post` | `author` (ref), `score`, `minutes`, `streak`, `technique`, `caption`, `photo` (asset), `practicedAt`, `createdAt` | the author |
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

## Post-session flow

Results screen → new row under the verdict: **"Post to friends"** (gold only
when Share has stepped down, one gold object per section). Opens the
composer: photo (camera or library, optional), caption (optional, 140
characters), the stat strip it will carry, the technique from the reflection
if one was set. **Post.** Back on results. The card on the feed is the photo,
the score ring, minutes, streak, the technique, the caption.

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
- **Free users get the evidence for their next 10 sessions.** Curves,
  tiles, readings, the four locked share layouts: the full paid results
  screen, ten times. It is the best possible taste of what paid is, and it
  is exactly the thing a free user cannot get any other way. Implemented as
  a grant in the private database (`Preferences.evidenceGrantRemaining`),
  decremented as each results screen is first opened, read by
  `Entitlements` as `paid || grantRemaining > 0`. Ten per friend, stacking,
  capped at 50 outstanding so a burst of invites cannot mint a year of
  premium.
- **Paid users get an award and a skin.** A "Brought a friend" award on the
  shelf (the `AwardEngine` "did this ever happen" rule applies) and a fifth
  share-card skin, **Circle**, only earnable this way. Paid users already
  have the evidence; what they lack is a way to show they brought people.
  Comping subscription time is possible later through one-time offer codes
  but is manual per code, so not v1.
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
4. Reward: the grant in `Preferences`, `Entitlements` reads it, the award,
   the Circle skin.
5. Moderation: word list, sensitive content check, report script
   (`tools/community-reports.gs`, deployed once, edited only as new
   versions of that deployment).
6. Policy, terms, labels, manifest, age rating, Console promotion.
7. TestFlight with the founders and five friends before it goes to the
   store. It ships as **1.1**, not inside 1.0.2.

Three weeks of work at a realistic pace, and it must not stall 1.0.2.
