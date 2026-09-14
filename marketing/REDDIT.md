# Reddit, launch week

Written 2026-09-13 after reading every candidate subreddit's rules directly
(the `about/rules.json` of each, not a summary). The launch plan said
"r/AppleWatch allows app posts". **It does not.** Rule 5 there is "No Self
Promo. This includes promoting your own app", and rule 2 requires explicit
moderator approval for anything promotional. So the plan's one post needs a
modmail first, and the real openings are elsewhere.

Posting account: Aziz's own, under his name. Every post says he built it.
No link where the sub forbids links; the App Store name is enough, and the
`reddit` campaign link (`CAMPAIGN_LINKS.md`) goes only where links are
allowed. No em dashes. No invented numbers. Honest limits in every post:
needs an Apple Watch, and the breath reading works for slow deliberate
breathing, not for every breath.

## Where, and on what terms

| Sub | Verdict | The rule that decides it | What it takes |
|---|---|---|---|
| **r/apple** (largest reach) | **Yes, Sundays only** | Rule 9: developers may self-promote on Sundays (California time), self-post only, "simply linking your app is no longer allowed". **Needs 5 organic posts or comments in r/apple in the past month**, not made right before posting. Immediate ban for abuse. Modmail must quote the word "Unicorn" to prove the rules were read. | Check Aziz's r/apple activity this month. If under 5, participate this week and post NEXT Sunday, 2026-09-20. |
| **r/iosapps** | **Yes, once per 30 days** | Needs 10 karma earned inside r/iosapps. Main feed only via the Transparency path: real name + a reachable identity (company site or LinkedIn) AND the website's Privacy Policy and Terms linked in the post. ABC format (Answer, Better, Cost). Flair by priority: Lifetime outranks Subscription outranks Freemium, so **Lifetime**. Promo codes go in the post body, never "comment for a code". Full App Store link, no shorteners. | Earn 10 local karma by answering a few "looking for an app that..." threads honestly first. |
| **r/SideProject** | **Yes, no rules listed** | The sub has no posted rules; it is the maker crowd. Smaller and less targeted, but a fine place for the "what I learned building it" post and it feeds feedback. | Post any day. |
| **r/AppleWatch** | **Only with mod approval** | Rule 5 bans self-promo outright; rule 2 allows promotional content only with explicit moderator approval; rule 3 bans links "where you stand something to gain". | Send the modmail below. If approved, post the discussion version with no link. |
| **r/QuantifiedSelf** | **Monday megathread only** | App promotion is confined to the weekly "Self-Tracking Tools & Apps" megathread (Mondays), unless the post carries real research under an [Ad] flair. | Comment in tomorrow's megathread (2026-09-14). A full post later, once there is a real data write-up. |
| **r/iOS** | Modmail first | Rule 2: developers must modmail before promoting or doing an AMA. | Optional; send the same modmail if r/AppleWatch says yes. |
| r/iphone | Modmail first | Guidelines wiki: "open to developers showcasing their apps and running AMAs, but please message us first"; they hand out a developer flair in return. Flair mandatory on every post. | Send the modmail; a developer flair there is worth having. Lower priority than the Watch subs. |
| r/Mindfulness | **No** | Rule 4 prohibits advertising apps. | Do not post. |
| r/Biohackers | **No** | Rule 5: no selling or promotion. | Do not post. |
| r/AppleWatchFitness | **No** | Rule 3: "Promotions are completely forbidden". | Do not post. |
| r/Meditation | **No** | Bans promotion (per the launch plan). | Do not post. |

Order: r/SideProject today, r/QuantifiedSelf megathread Monday, r/iosapps as
soon as the karma is there, r/apple next Sunday, r/AppleWatch only if the
mods say yes. Reply to every comment for 48 hours after each post.

Timing note: 1.0.1 (the build that fixes sessions failing to start) went
live 2026-09-14 around 4 AM EDT, so the posts are clear to go. Every one of
them sends people to their first session.

---

## Posted

- **r/SideProject, 2026-09-13 ~1:50 PM EDT, u/No_Shelter5464.** Aziz's
  personal-journey post (future self, Dispenza, "what did my body actually
  do", 808 in one paragraph with a four-word disclosure, ends on a question
  to the sub). Not the draft below; Aziz wrote it.
  https://www.reddit.com/r/SideProject/comments/1wfeqfz/i_started_meditating_to_become_a_future_version/
  **REMOVED by Reddit's filters (seen 2026-09-14).** Site-wide spam filter,
  not the sub's mods: a brand-new account with no karma posting an outbound
  link is the textbook trigger, and only the sub's moderators can restore a
  filtered post. Do NOT repost from the same account; a second removal marks
  it as spam. Sequence: (1) modmail r/SideProject asking them to approve it
  (text below); (2) meanwhile the account earns comment karma, no links, for
  a few days; (3) if they say no, post again in a week from an account with
  history, or with the link replaced by the App Store name.

  **2026-09-14: the r/SideProject post goes again from MELVIN's account**
  (it has history and karma), using draft 4 below, which is different text
  from Aziz's removed post. Text post, not a link post. Aziz's account stays
  on comments only until it has karma.

  Modmail to r/SideProject:
  > Hi. My post "I started meditating to become a future version of myself"
  > was removed by Reddit's filters, I think because the account is new.
  > It is a personal write-up of a meditation app two of us built, with the
  > disclosure in the first paragraph. Would you approve it? Happy to take
  > the link out if that helps. Thank you.

## 1. r/AppleWatch modmail (send first; post nothing there until they answer)

**Subject:** Developer asking permission before posting

Hi mods. I'm one of two people who built 808 Meditate, an app that uses the
Watch to measure a meditation session (heart rate settling, stillness from
the accelerometer, and breathing rate from wrist tilt when someone breathes
slowly). It went live on the App Store this week.

I've read rules 2, 3 and 5. I'd like to post one discussion thread about
what a third-party app can and can't read from the Watch during a session
(for example: HR arrives as a rolling average roughly every five seconds,
and beat-to-beat intervals aren't available to third-party workouts at all,
which rules out real HRV). I'd say plainly that I built the app, name it
once, post no link, and answer questions. If that's not something you want
here, I understand and won't post. Thanks.

Aziz

## 2. r/apple, Self-Promotion Sunday (self-post, no bare link)

**Title:** I built an Apple Watch app that scores your meditation from your heart rate and stillness, and here's what the Watch will and won't tell a third-party app

**Body:**

I'm Aziz, one of the two people behind 808 Meditate. It went live on the App
Store this week. Posting on the Sunday rule.

What it does: you meditate however you already do (your own YouTube video,
Spotify, silence, or the 25-minute guided track we recorded), and the Watch
measures the session. Afterwards you get a score out of 100 built from three
things: how far your heart rate settled, how still you stayed, and whether
you slowed your breathing. Nothing shows during the session on purpose. The
point is evidence after, not a number to chase while you sit.

Things I learned building it that people here might find interesting:

- A third-party workout session on the Watch gets heart rate as an average
  updated roughly every five seconds. It does not get beat-to-beat
  intervals, so real HRV during a session isn't possible for any third-party
  app, whatever the marketing says. We measure the drift of heart rate
  instead, which the Watch does give you cleanly.
- Breathing can be read from wrist tilt with the motion sensors, but only
  when the breathing is slow and deliberate (roughly 4 to 7 breaths a
  minute). Normal quiet breathing is too small to separate from the way
  your arm drifts. So the app reads the slow breathing people do to settle
  in, and says nothing when it can't read a breath, rather than guessing.
- Stillness from the accelerometer turned out to be a great check that
  you actually sat there, and a poor measure of how deep you went. We
  weight it lowest for that reason.

Honest limits: it needs an Apple Watch (the phone reads nothing on its
own), and it isn't a medical device. Every measurement is computed on the
Watch and the phone; heart data never leaves the device and there is no
server.

Pricing: the score, the verdict, streaks and history are free. The curves
behind the score and the guided track are a membership: $7.99 a month or
$29.99 a year, both with a 7-day free trial, or $99.99 once.

It's "808 Meditate" on the App Store. Happy to answer anything about the
Watch side; that's the part I'd genuinely like to talk about.

## 3. r/iosapps (flair: Lifetime; needs 10 local karma first)

**Title:** 808 Meditate: your Apple Watch scores your meditation from heart rate, stillness and breathing. Free score, paid curves.

**Body:**

**Answer (what problem it solves):** You sit for ten minutes and have no
idea whether anything happened. 808 uses the Apple Watch you already own to
measure the session and shows you afterwards: how far your heart rate
settled, how still you were, and whether you slowed your breath. One score
out of 100, and the graphs behind it. It works with whatever audio you
already use; you don't have to switch to our library.

**Better (why over alternatives):** Apple's Mindfulness app logs heart rate
during a session but doesn't score it or tell you anything about it.
Headspace, Calm and the rest are content libraries; none of them measure
your body. Watch-only apps that promise HRV coherence during a session are
promising something the Watch doesn't give third-party apps (no beat-to-beat
data during a workout), so we measure what it actually provides and say so.

**Cost:** Free tier: score, written verdict, streak, calendar, history,
nature and tone sounds, bring your own audio. Membership unlocks the
heart-rate, stillness and breathing curves, the metric tiles, the 25-minute
guided track and the full share cards: $7.99/month or $29.99/year, each
with a 7-day free trial, or $99.99 lifetime.

Requires an Apple Watch and iPhone. Everything is computed on device; no
account is required; no server.

App Store: https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=reddit&mt=8
Privacy Policy: https://meditate808.com/privacy.html
Terms: https://meditate808.com/terms.html

I'm Aziz Mahmud, cofounder, Lock Out Inc. (meditate808.com,
support@meditate808.com). I built this with Melvin Van Cleave. Ask me
anything about how the measuring works; the honest answer to "can it read
my breathing" is "when you breathe slowly on purpose, yes; otherwise it
stays quiet rather than guess".

(Promo codes: paste a handful here once 1.0.1 is live, per the sub's rule
that codes go in the body.)

## 4. r/SideProject

**What wins there (top 25 posts of the month, read 2026-09-14 via the sub's
RSS; Melvin asked for the post to be rewritten in that register):** nearly
every top post is a VIDEO or image post with the text as the body; the title
is "I built a [platform] app that [one concrete thing it does]", first person,
present tense, no essay title; the body opens "I'm the developer" and
explains the mechanics in second person ("put the phone on the floor, get
into a plank, and it counts your reps"); one paragraph on what took most of
the dev time; one line on privacy where it applies ("no frame leaves the
phone"); a "the reason it exists" paragraph; prices stated plainly with the
renewal disclosure; one direct link; and it closes with an ask ("tell me
where it falls short"). Short paragraphs, no numbered lists, no headers. One
top post put a public offer code in the body with no redemption limit and
credited it for installs. The "three things we got wrong" listicle below is
kept for the record; the version that goes up is 4b.

### 4b. The version that goes up (Melvin's account, video post)

Attach the screen recording as the post itself: Watch end, then the phone's
results screen with the score and the curves, 20 to 30 seconds, no music.
The text is the body.

**Title:** I built an Apple Watch app that scores your meditation from your heart rate, your stillness and your breathing

**Body:**

I'm one of the two people who built it. You put on your Watch, press start
on the phone or the wrist, and meditate the way you already do: a guided
track, your own audio from any app, or silence. The Watch measures the whole
time and shows you nothing during the session. When you end it, the phone
gives you a score from three things: how far your heart rate settled and
whether it stayed there, how still you sat, and whether you slowed your
breathing in the first few minutes.

Most of the dev time went into the breathing. The first version only worked
lying down with the Watch on your belly. It worked, and nobody was ever
going to do that. The shipped version reads slow breathing from tiny wrist
tilt, sitting however you like. It's built for deliberate slow breathing,
the four to seven a minute kind, and when it can't read a breath it says
nothing rather than inventing a number. That rule runs through the whole
app: if it wasn't measured, it isn't claimed.

Everything is computed on the Watch and stored on your phone. Your heart
rate never leaves your devices, and there's no account unless you want
iCloud sync.

The reason it exists: I meditated for years without knowing whether a given
session did anything. Now I finish and see it, and the bad sits turned out
to be as useful as the good ones.

Free gives you the score, your streak and your history. Premium is the
curves behind the score plus a 25-minute guided journey: $7.99 a month or
$29.99 a year, both with a 7-day free trial, or $99.99 once. Needs an Apple
Watch.

App Store: https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=reddit&mt=8

Tell me where it falls short.

### 4a. The earlier draft (not used)

**Title:** Two of us made the Apple Watch score a meditation. It's live. What we got wrong along the way.

**Body:**

808 Meditate went live this week. You meditate with any audio, your Watch
measures, and afterwards you get a score from heart-rate settling, stillness
and breathing.

Three things we got wrong and fixed:

1. We started out trying to measure heart coherence (the HRV thing). Spent
   weeks on it before proving on real hardware that a third-party workout on
   the Watch only gets averaged heart rate, never beat-to-beat. Threw it
   out and measured heart-rate drift instead, which the Watch does give you.
2. Our first breathing detector needed you to lie down with the Watch on
   your belly. It worked, and nobody would ever do it. The shipped version
   reads slow breathing from ordinary wrist tilt, sitting however you like,
   and says nothing when it can't read a breath instead of inventing one.
3. Our first score was 55% "did you sit still", which meant half the score
   was a constant. Stillness is now the smallest weight; it's a validity
   check, not a depth measure.

Stack: Swift, SwiftUI, SwiftData, HealthKit, CoreMotion. All the analysis
runs on the Watch; the phone stores results. No server at all, which made
the privacy policy short and the App Review conversation easy.

Free score, paid curves. Needs an Apple Watch. Search "808 Meditate" or:
https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=reddit&mt=8

Happy to go into any of it.

## 5. r/QuantifiedSelf, Monday megathread comment

808 Meditate (iOS + Apple Watch). Measures a meditation session from the
Watch: heart-rate drift, stillness from the accelerometer, and breathing
rate from wrist tilt when you breathe slowly. Score plus the raw curves
afterwards, nothing live during the sit. Limits, since this sub cares: HR
is the Watch's ~5-second average, not beat-to-beat, so no HRV; breathing
only reads deliberate slow breathing (roughly 4 to 7/min). All on-device.
Free score, paid curves. I'm one of the two people who built it.
