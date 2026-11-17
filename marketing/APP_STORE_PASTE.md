# App Store Connect paste sheet

Values only, in the order the forms ask for them. Reasoning lives in
`APP_STORE.md`; this file exists to be copied from without reading.

**Paywall changed 2026-10-26 (Melvin and Aziz), for the next version:** two
cards, Yearly ($29.99, preselected) over Monthly ($7.99); Lifetime is off the
paywall (still restores); one answer to a "no", a half-price banner selling
`monthly50` ($3.99 a month) after a **7-day** free trial. The subscription
information and review notes below are updated; the history under this
paragraph describes 1.1.

**Rewritten 2026-09-29 for 1.1** against the Release build on branch `block`,
and **corrected later the same day for the founders' decisions (Melvin; code
in commit 9ffa513)**: 808 is premium only and fails closed (no free tier; if
the plans cannot load, nobody without a membership gets past the paywall).
**The paywall sells Monthly ($7.99), Yearly ($29.99) and Lifetime ($99.99, one
payment) with NO free trial.** The free trial is an upsell, hidden until
someone declines: "No, I don't want to pay" offers a 3-day free trial on
Monthly or Yearly (`monthlytrial`, then $7.99 a month; `yearlytrial`, then
$29.99 a year; the paywall returns with both, Yearly preselected), and if that
is declined too, Monthly, half price (`monthly50`, a 3-day free trial, then
$3.99 a month).
**Block and the Shop (points and hats) ship**; Friends is profiles and
practice summaries with no posts, opened from a circle on Home; Otto's chat
is off. Sessions run on the iPhone with or without a Watch, and count from one
minute. Verified in code: 58 awards in the catalog (three score awards stay
hidden until earned), the 25-minute guided journey, 4 nature sounds, 3
brainwave tones, 4 tunings, 11 hats.

*Superseded the same day:* the morning's version of this sheet had Lifetime
restore-only and Block and the Shop off; its trial setup (none on Monthly or
Yearly, two rungs) was right. A rewrite labelled "evening" in these files then
put a 3-day free trial on Monthly and Yearly and cut the ladder to one rung.
That misread Melvin's "same as before, 3 day offer" and held for a few hours;
every trial line below is corrected.

**2026-11-11 (Aziz): onboarding now LEADS with the free trial, 7 days.**
Two screens after "Let's go!" ("We want you to try 808 Meditate for free",
"I'll remind you the day before it ends"), then a paywall selling
`yearlytrial` and `monthlytrial` with a timeline; "No, I don't want to pay"
raises the half-price banner from the paywall rebuild. The subscription block
and the review notes below are updated for it. Needs App Store Connect to
match: the free trial on all three trial products is **1 week**; `monthly`
and `yearly` still carry none (`RELEASE_CHECKLIST.md`, "OPEN for the build
that leads onboarding with the free trial").

**This file is the ONE source for the description, promotional text, What's
New and the review notes.** `APP_STORE.md` points here rather than carrying
copies, because copies drift and the drifted one is the one that gets pasted.

**No reviewer test account** (Aziz, 2026-09-29). The notes explain where
Report, Block and Requests live instead of naming a profile to find
(`RELEASE_CHECKLIST.md`, item R1).

**Since 1.4.1 the description's subscription block and the review notes say
"7 day free trial", for the half-price plan only.** That must be what App
Store Connect holds on `monthly50` (and, to match, on the dormant
`monthlytrial` and `yearlytrial`), and `monthly` and `yearly` must carry NO
introductory offer (`RELEASE_CHECKLIST.md`, OPEN for 1.4.1). If Connect ends
up with any other trial length, change every "7 day" in the pasted text
before pasting. (1.1 to 1.4 said "3 day"; the history below still does.) What's New and the promotional text mention no trial, on purpose: the
trial is only offered after a "no".

---

## App Information (set once, not per version)

**Name**

```
808 Meditate
```

**Subtitle** (30 max; this one is 30; Melvin's pick 2026-10-01, it adds
"meditation", "daily" and "habit" to search, none of which the keywords carry)

```
Build a daily meditation habit
```

**Category**: Primary `Health & Fitness` · Secondary `Lifestyle`

**Content Rights**: **Yes**, it contains third-party content (decided
2026-09-29: the famous-meditator photos ship). Keep the rights on file: the
three photos are Wikimedia Commons images under CC BY-SA, credited in the app;
the research screen's university logos are also third-party (their fate is
still a founder decision, `RELEASE_CHECKLIST.md`). Everything else is ours or
licensed: narration commissioned with a commercial license, tones synthesized
at runtime, beds and nature recordings generated under commercial license. If
App Review ever makes the app drop the photos AND the logos go too, this
becomes **No**.

**Age rating questionnaire** (Apple's 2025 form; worked answers and reasons in
`APP_STORE.md`):

| Question | Answer |
|---|---|
| Parental Controls | No (Block is individual self-management, not parental control) |
| Age Assurance | No |
| Unrestricted Web Access | No |
| User-Generated Content | **Yes** |
| Social Media | **Yes** |
| Social Media Disabled for Users Under 13 | No |
| Messaging and Chat | **No** |
| Advertising | No |
| Profanity or Crude Humor | No |
| Horror or Fear Themes | No |
| Alcohol, Tobacco, or Drug Use or References | No |
| Health or Wellness Topics | **Yes** |
| Medical or Treatment Information | **Infrequent** |
| Sexuality or Nudity (all levels) | No |
| Violence (all levels) | No |
| Chance-Based Activities (all kinds) | No |

Expected result: **13+**. Confirm the computed tier in the live form.

**Digital Services Act (trader details, PUBLISHED on the EU listing)**: use
the registered address, never the Brooklyn one:

```
Lock Out Inc.
8 The Green, Ste A
Dover, DE 19901
United States
```

**App Encryption**: nothing to upload. Both app targets declare
`ITSAppUsesNonExemptEncryption = false`; the app uses only Apple's standard
HTTPS and CloudKit encryption.

**Accessibility Nutrition Labels**: deliberately left EMPTY. These labels are a
public claim, and none of the features they list has been verified in 808.

---

## Version 1.1

**Promotional Text** (170 max; this one is 148; editable later without a new
review)

```
Meditate consistently with Otto. He glows brighter every day you do, blocks your apps when you don't, and now lives on your home screen as a widget.
```

**Description** (4000 max; this one is 3,939, 3,980 counting line breaks twice; rewritten for 1.5 2026-11-17: Block and Friends lead, the feed and Otto's forms added)

```
Make meditation a daily habit. 808 blocks the apps that pull you away until you meditate, lets you meditate alongside friends, and gives you Otto, a sloth who glows brighter every day you show up.

BLOCK YOUR APPS UNTIL YOU MEDITATE
Pick the apps that pull you away and when they're held: all day, during hours you set, or after a daily limit. Open one and Otto asks you to meditate first. Tap Ask Otto and he may text you or call. Meditate for 1 minute and they open for the rest of the day, or choose "Not now" for 5, 10 or 30 minutes. Block manages your own iPhone, and the apps you pick stay private to your phone.

MEDITATE WITH FRIENDS
Post a session with photos, a title and a note, and see your friends' sessions in your feed. Double tap to give kudos. Tap a friend to see their Otto, their streak and how often they meditate. Set a weekly goal together and nudge each other. Add friends by @username or invite code; a friend you invite gets their first month free. A profile is optional and public to anyone with your username.

A STREAK THAT GLOWS
Every day you meditate, Otto glows a little brighter and your streak grows, with one rest day a week. Add the widget to see both on your home screen.

UNLOCK NEW FORMS
Every minute you meditate earns a point. Collect enough and Otto is reborn as a red panda, a tiger, a phoenix and finally a dragon. Wear whichever form you like.

COLLECT POINTS, BUY HATS
A week finished with a friend earns 10 more points. Spend them in the Shop on hats, from a beanie to a golden crown.

MEDITATE YOUR WAY
Set a timer or leave it open. Sit in silence, with rain, ocean, forest or campfire, with brainwave paced tones, or with traditional tunings at 432, 528, 852 and 963 Hz. Or follow a narrated 25 minute guided journey.
Or play a meditation from another app and begin your session in 808. Meditated elsewhere? Record it by hand.

WITH AN APPLE WATCH, SEE WHAT YOUR BODY DID
An Apple Watch is optional. Wear one and 808 also reads your heart rate, how still you became and your breathing, then shows you a score out of 100 and the curves behind it after the session. Each Apple Watch session is saved to Apple Health as a workout and as mindful minutes.

PRIVATE BY DESIGN
Heart rate and every Watch reading stay on your iPhone, are never uploaded to us, and never appear on a post. Your sessions sync through your own private iCloud, which we cannot read. Our analytics are pseudonymous and never include a body measurement or anything from Screen Time. No ads. No data sales. Sign in with Apple is optional.

HONEST SCIENCE
The 432, 528, 852 and 963 Hz tunings are offered as a tradition, not as science. 808 is a wellness app, not a medical device, and does not diagnose, treat or prevent any condition.

808 MEMBERSHIP
808 is a membership, and every feature is included in it.

SUBSCRIPTION INFORMATION
808 Membership Yearly: $29.99 per year.
808 Membership Monthly: $7.99 per month.
New members are offered Yearly or Monthly with a 7 day free trial, then $29.99 per year or $7.99 per month. If you decline the plans above, the app may offer Monthly, half price: a 7 day free trial, then $3.99 per month. Someone invited by a friend may be offered Monthly with the first month free, then $7.99 per month.
A free trial is available once per Apple Account across 808's subscriptions. Payment is charged to your Apple Account when you confirm the purchase, or when a free trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period or free trial, and your account is charged for the renewal within the 24 hours before the period ends. Manage or cancel any time in your App Store account settings. Any unused part of a free trial ends when you buy a subscription.
Restore, on the paywall or in Settings, brings a purchase back on a new device.

Terms of Use: https://meditate808.com/terms
Privacy Policy: https://meditate808.com/privacy
```

**Keywords** (100 max; this is 99; no spaces after the commas, and none of the
name or subtitle words, which Apple already counts)

```
mindfulness,guided,timer,streak,focus,stress,relax,breathing,blocker,detox,selfcare,pet,zen,friends
```

**Support URL**

```
https://meditate808.com/#support
```

**Marketing URL**

```
https://meditate808.com
```

**Privacy Policy URL**

```
https://meditate808.com/privacy
```

**Version**

```
1.1
```

**Copyright**

```
© 2026 Lock Out Inc.
```

**What's New in This Version, 1.4.1** (4000 max; this one is 592, 604 counting line breaks twice; Melvin's wording, approved 2026-10-27. It names only what a member can see: the paywall rebuild and the founders' note are left out on purpose.)

```
Five new hats for Otto in the Shop: a baseball cap, a sombrero, a top hat, a tiara, and an astronaut helmet!

New Friends awards: your first friend, 5, 10 and 25 friends, a goal started, and weeks finished together.

Finish a week with a friend and you both hear about it, with 10 points for Otto's hats. Every week you finish together shows on your goal's page.

Block now opens your apps for the rest of the day after 1 minute of meditating, whenever you do it.

A reminder at 11:30 pm on nights your streak would end at midnight.

Hats sit more cleanly on Otto when he glows.

Small fixes.
```

**What's New in This Version, 1.4** (4000 max; this one is 354, 360 counting line breaks twice; 2026-10-19, approved by Melvin.)

```
Meditate together: set a weekly goal with a friend, see each other's week, and send a nudge when it helps.

Invite friends with your own code. When they join with it, you're friends right away.

Pick a profile picture, or one of 21 of ours, including Otto and his friends.

On Apple Watch, the session length turns smoothly, and you can type the minutes.
```

**What's New in This Version, 1.3.1** (4000 max; this one is 86, 88 counting line breaks twice; 2026-10-15, for Melvin to approve.)

```
Rate 808 anytime from Settings. Each rating helps someone else find 808.

Small fixes.
```

**What's New in This Version, 1.3** (4000 max; this one is 556, 564 counting line breaks twice; 2026-10-13, for Melvin to approve. 1.2 shipped on 2026-10-07 with the widget, the new block screen, Otto's replies, the blocker check, the bell and the freeze fix; its text is in git history.)

```
Smarter reminders: a nudge at your time, and a couple more on days you haven't meditated yet. They stop as soon as you do. Prefer one a day? Choose it in Settings.

Otto now asks you to pick at least one app for him to hold until you've meditated.

808 has music now, with gentle sounds and a soft tap on every button. Turn any of them off in Settings.

After a session, its page opens so you can add how it felt, a photo or a note.

On Apple Watch, Otto sits in his valley. Set a session's length with the Digital Crown and choose a sound from your wrist.
```

---

## Screenshots

**Re-shot for 1.1 on 2026-09-29** into `marketing/appstore/` (the eight that are live). **The next version's ten are in `marketing/appstore-new/`** (`01-otto.png`
... `10-watch.png`, with `65/` beside them and `screenshots-preview.jpg` showing all ten), the 6.5 inch copies of the live eight in `appstore/65/`, the Watch set in
`appstore/watch/`). Framed by `tools/store_shots.swift` in the valley's
daytime sky, SF Pro Rounded captions, a drawn generic bezel. Captured on the
iPhone 17 Pro Max simulator from a Debug build with `STORE_SHOTS=1`, which
hides the development-only test-mode cards and switches Otto's chat off as
Release has it; how to regenerate is in `marketing/README.md`.

**Captions rewritten 2026-11-16 (Melvin: "Too much Otto... hes the mascot not the entire app"): Otto is named once, in shot 1's subhead; every headline names what the app does. Same day: Block and Friends moved up to 2 and 3, and the evolution shot became the dragon rebirth reveal at 4.**

**iPhone 6.9 inch (required). The listing leads with Otto, not Block**
(Melvin, 2026-09-29: "Youre focusing too much on the blocking aspect, thats
just one feature"). **Reshot 2026-11-13 (Melvin's lineup)** for the release
with Otto's forms and the Friends feed: Profile and awards dropped, the next
form, the forms picker and the feed added. Upload in this order:

| # | File | Screen | Headline | Subhead |
|---|---|---|---|---|
| 1 | 01-otto | Home, Otto glowing at 100%, 7-day streak | Make meditation a daily habit | Your streak grows, and Otto glows a little brighter every day you meditate |
| 2 | 02-shield | A held app's block screen ("bruh."), gold palette | Block distracting apps until you meditate | Meditate for a minute and they open for the rest of the day |
| 3 | 03-friends | The Friends feed: Priya's "Evening meditation" with photos, Maya's own post | Meditate with friends | Post your sessions and cheer each other on |
| 4 | 04-evolve | The rebirth reveal: "Otto was reborn as a dragon" | Unlock new forms as you meditate | Every minute brings the next one closer |
| 5 | 05-shop | The Shop, the red panda trying on the Straw Sun Hat | Earn points for every minute | Spend them on hats in the Shop |
| 6 | 06-forms | Otto's forms: sloth, red panda (worn), tiger, phoenix, dragon at 5,500 | Five forms to collect | A sloth, a red panda, a tiger, a phoenix and a dragon |
| 7 | 07-texts | Otto's text thread after Ask Otto | A nudge before you scroll | Open a held app and get a text asking you to meditate first |
| 8 | 08-widget | Home screen with the medium and two small widgets (unchanged from the 2026-10-13 set) | Your streak on your home screen | Your practice at a glance, all day long |
| 9 | 09-sounds | The plus: the Ready screen's sound list | Meditate your way | Silence, nature, tones, a guided journey or your own audio |
| 10 | 10-watch | A measured Watch session's results | Wear an Apple Watch for more | Heart rate, stillness and breathing, after each session |

**The 2026-10-13 ten, superseded 2026-11-13, kept for the record:** 01 Otto,
02 shield, 03 Shop, 04 widget, 05 sounds, 06 texts, 07 Profile ("Every day
adds up"), 08 Watch, 09 Friends list ("See how often your friends meditate
each week"), 10 awards ("More than fifty awards").

**Reworked 2026-10-13 (Aziz), in `marketing/appstore-new/`,** for the release after 1.2; `marketing/appstore/` still holds the live eight: the Block-list shot
(2) became the block screen itself, and the widget (4) and Otto's texts (6)
were added, ten in all, Apple's maximum. Otto still leads. The widget shot is
the simulator's home screen with the widget's own renders
(`mockups/widget/v3/`) laid on it, because the simulator's widget gallery
would not take scripted taps. The 1.1 eight were in this table before.

**Superseded 2026-09-29 (evening), kept for the record:** the morning's
Block-first order below.

| # | Screen | Headline | Subhead |
|---|---|---|---|
| ~~1~~ | ~~Block tab, or a held app's shield~~ | ~~Meditate first, then scroll~~ | ~~808 holds the apps you choose until you've meditated~~ |
| ~~2~~ | ~~Home, Otto glowing, streak~~ | ~~Meet Otto~~ | ~~He glows brighter every day you meditate~~ |
| ~~3~~ | ~~The plus: Ready screen with sounds~~ | ~~Meditate your way~~ | ~~Silence, nature, tones, a guided journey or your own audio~~ |
| ~~4~~ | ~~Shop, Otto in a hat~~ | ~~Dress Otto up~~ | ~~Every minute you meditate earns points for hats~~ |
| ~~5~~ | ~~Home: this week and streak~~ | ~~Every day adds up~~ | ~~Your streak and your week at a glance~~ |
| ~~6~~ | ~~A Watch session's results~~ | ~~Wear an Apple Watch for more~~ | ~~Heart rate, stillness and breathing, after each session~~ |
| ~~7~~ | ~~Friends list~~ | ~~Meditate with friends~~ | ~~See how often your friends sit each week~~ |
| ~~8~~ | ~~Awards shelf~~ | ~~More than fifty awards~~ | ~~For showing up, going longer and trying new ways in~~ |

The order before that (Otto, Ready, week, Friends, Watch, awards, Guide,
Record one) was superseded earlier the same day. Guide and Record one stay in
the description.

**Apple Watch (required, we ship a Watch app)**: four, retaken 2026-10-27 in
the valley design: `appstore/watch/01-begin.png` (start screen, 10 min,
Silence), `02-length.png` (the length tape), `03-sound.png` (the sound list)
and `04-measuring.png` (a timed session, 6:07 left), all 422 x 514, the
Apple Watch Ultra 3 size, which is the largest App Store Connect takes. The
watchOS simulator will not override its clock, so the corner shows whatever
time they were captured at.

No iPad set: the app is iPhone and Watch only (`TARGETED_DEVICE_FAMILY: 1`).

---

## App Review Information

**Sign-in required?** No. Sign in with Apple is the only sign-in and it is
optional, so no demo account exists or is needed. Purchases use the reviewer's
own sandbox Apple Account.

**Contact**: First name `Melvin`, last name `Van Cleave`, phone
`818-422-1140`, email `support@meditate808.com` (never a personal Gmail;
Apple emails this address about the review).

**Notes** (4000 max, with line breaks possibly counted twice; checked
against the code 2026-09-30 in a third review pass; the Block sentence
reworded 2026-10-13 for the required app pick; Friends gained invite codes,
weekly goals and nudges 2026-10-18; Block's one minute, the rest of the
day, and "Not now" for 5, 10 or 30 corrected 2026-10-27; goals from a
minute 2026-10-27; the free-trial screens 2026-11-12; Friends feed and Otto's forms for 1.5 2026-11-17, 3,994 counted with line breaks twice). Count again after any edit.

```
808 is a meditation app for iPhone with an optional Apple Watch app. No part of this review needs an Apple Watch.

SUBSCRIPTION
Nothing past the paywall opens without buying or restoring. Use a sandbox account with no active 808 subscription.
In onboarding, on "Ready to take control?", hold the round button about three seconds until "Let's go!" appears, then tap Continue. Two screens follow; "Continue for FREE" asks for notifications; any answer works. Then the paywall.
It sells Yearly ($29.99, preselected) and Monthly ($7.99), each with a 7 day free trial, plus Restore, Privacy Policy and Terms of Use. "No, I don't want to pay", or cancelling the purchase sheet, raises a banner: Monthly, half price ($3.99 a month after a 7 day free trial), with its renewal terms and legal links. "Claim half price" opens the purchase sheet; "No thanks" closes it.
An account that already had a trial skips those screens and sees no trials; half price charges from the first month.
Members updating keep full access; others meet the paywall at launch, with an Account link (Restore, Sign out, Delete account).

BLOCK (part of 808 Membership)
Family Controls with individual authorization: a person manages their own iPhone, not a parental control. After the paywall, onboarding asks for Screen Time permission. Declining continues; once allowed, at least one app is picked in Apple's picker. A held app shows Apple's shield. "Ask Otto" sends a notification that opens a short screen from Otto, ending in a meditation (one minute or more opens the apps for the rest of the day) or "Not now" for 5, 10 or 30 minutes. If notifications are off, the shield says to open 808, and Otto appears there. Nothing from Screen Time leaves the device.

SESSIONS
Tap the plus, then the first button ("Meditate") to choose:
- Meditate: a timer on the iPhone. Nothing is measured.
- With Apple Watch: dimmed unless a Watch is paired.
- Record one: logs a session done elsewhere.
Sessions count from one minute. Keep 808 open during an iPhone session: after 10 seconds away, including a locked screen, 808 says it won't count, and "I was still meditating" keeps it.
"Silence notifications" runs two Shortcuts, "808 Silence" and "808 Restore", added once from iCloud links (tap Add Shortcut, return to 808, then the second). At the end 808 briefly opens Shortcuts to run 808 Restore. 808 never changes Focus itself.

POINTS, FORMS AND THE SHOP
A meditated minute earns a point; a week finished with a friend earns 10. Points buy hats in the Shop (the circle at the top right of Home). Lifetime points also unlock Otto's other forms: a red panda at 300, a tiger at 800, a phoenix at 2,200, a dragon at 5,500; the person picks which to wear. Recorded sessions earn none and never open Block's apps. Points can't be bought and have no cash value.

FRIENDS
The Friends tab; needs iCloud. Friends are added by @username or invite code. A session's page can post it to friends with optional photos or videos, a title and a note; "Only me" keeps it private. A post shows time, streak and sound, never a score or heart rate. Friends give kudos (double tap or one of four emoji); no comments or typed messages. Media is screened on the device (Sensitive Content Analysis) before posting.
Posts and profiles from others carry Report and Block (... menu); reports reach our inbox at once, and reported content is removed within 24 hours. Friends can share a weekly goal and nudge once a day. An invite code can open a paywall offering the first month free. Seeing another person needs a second iCloud account.
Delete account (Profile tab, gear icon) removes the profile, username, invite code, posts, kudos, goals and connections.

HEALTH DATA
Heart rate is read only during a session measured by an Apple Watch. Results stay on the device, out of iCloud sync and backup (5.1.3(ii)). Each Watch session is saved to Apple Health as a workout and mindful minutes. Analytics never include a health value.
```

---

## App Privacy

**Do not answer from this file.** The label table lives in `APP_STORE.md`
("App Privacy (nutrition labels), 1.1"), mirrored from
`Coherence/PrivacyInfo.xcprivacy`. If the label and the manifest disagree,
that is a rejection. Change them together, always.

---

## Pricing and in-app purchases

The app is **free** to download; everything inside it is in 808 Membership.
Products, prices, display names, descriptions and which ones to attach to 1.1
are in `APP_STORE.md` ("In-app purchases"). In short (corrected later on
2026-09-29): `monthly` and `yearly` with **NO introductory offer** (remove any
they carry), `lifetime` for sale (confirm Cleared for Sale),
`monthlytrial` at $7.99 a month and `yearlytrial` at $29.99 a year, each with
a **3-day free trial** (ladder rung 1), and `monthly50` at $3.99 a month with a
**3-day free trial** (ladder rung 2); attach all six (`lifetime` if Connect
offers it). `yearly50` is sold by no screen: do not attach it. **The app
fails closed, so a product that is not attached and loadable locks the
reviewer out.**

~~In short (2026-09-29, evening): `monthly` and `yearly` each with a 3-day
free trial introductory offer, `lifetime` for sale (confirm Cleared for Sale),
and `monthly50` at $3.99 a month with a 3-day free trial; attach all four.
`monthlytrial` is not needed and `yearly50` is sold by no screen: attach
neither.~~ (The misread version, kept for the record.)
