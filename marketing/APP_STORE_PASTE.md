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

**This file is the ONE source for the description, promotional text, What's
New and the review notes.** `APP_STORE.md` points here rather than carrying
copies, because copies drift and the drifted one is the one that gets pasted.

**No reviewer test account** (Aziz, 2026-09-29). The notes explain where
Report, Block and Requests live instead of naming a profile to find
(`RELEASE_CHECKLIST.md`, item R1).

**The description's subscription block and the review notes say "3 day free
trial" for the ladder plans only.** That must be what App Store Connect
holds on `monthlytrial`, `yearlytrial` and `monthly50`, and `monthly` and
`yearly` must carry
NO introductory offer (`RELEASE_CHECKLIST.md`, step 0 and R25). If Connect
ends up with any other trial length, change every "3 day" in this file before
pasting. What's New and the promotional text mention no trial, on purpose: the
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

**Description** (4000 max; this one is 3993)

```
Meditate consistently with Otto, a sloth who meditates with you. He glows brighter every day you do and blocks your apps when you don't. Every minute earns points for his hats.

OTTO GLOWS WITH YOUR PRACTICE
Every day you meditate, Otto glows a little brighter, and your streak grows with him. Your streak allows one rest day a week.

OTTO ON YOUR HOME SCREEN
Add the 808 widget, small or medium, to see Otto, your streak and what he has to say, lit for the time of day.

HE BLOCKS YOUR APPS UNTIL YOU MEDITATE
Pick the apps that pull you away and choose when Otto holds them: all day, during hours you set, or once you reach a daily limit. Open one and Otto asks you to meditate first. Tap Ask Otto and he may text you or call. Meditate and they open for the rest of that window, or tell Otto "Not now" for 5, 10 or 30 minutes. Block manages your own iPhone, and the apps you pick stay private to your phone.

COLLECT POINTS, BUY HIM HATS
Every minute you meditate earns a point. Spend your points in the Shop on hats for Otto, from a beanie to a golden crown.

MEDITATE YOUR WAY
Set a timer or leave it open. Sit in silence, with rain, ocean, forest or campfire, with brainwave paced tones for delta, theta and alpha, or with traditional tunings at 432, 528, 852 and 963 Hz. Or follow a professionally narrated 25 minute guided journey.
Like a meditation in another app? Play it there, then begin your session in 808.
Meditated somewhere else? Record the session by hand and it counts toward your streak.

WITH AN APPLE WATCH, SEE WHAT YOUR BODY DID
An Apple Watch is optional. Wear one and 808 also reads your heart rate, how still you became and your breathing, then shows you a score out of 100 and the curves behind it after the session. Each Apple Watch session is saved to Apple Health as a workout and as mindful minutes.

MEDITATE WITH FRIENDS
Add friends by @username and see how often each of them meditates: sessions and minutes this week, their streak and their total. A profile is optional, and anyone who looks up your username can see it.

EVERY DAY ADDS UP
Your streak, your week at a glance, your full history, more than fifty awards, and a written guide to different ways to meditate, easiest first.

PRIVATE BY DESIGN
Heart rate and every reading from your Watch stay on your iPhone and are never uploaded to us. Your sessions sync through your own private iCloud, which we cannot read. Our analytics are pseudonymous and never include a body measurement or anything from Screen Time. No ads. No data sales. Sign in with Apple is optional.

HONEST SCIENCE
The Watch readings are grounded in peer reviewed research on wrist worn motion sensing. The 432, 528, 852 and 963 Hz tunings are offered as a tradition, not as science. 808 is a wellness app, not a medical device, and does not diagnose, treat or prevent any condition.

808 MEMBERSHIP
808 is a membership, and every feature is included in it.

SUBSCRIPTION INFORMATION
808 Membership Yearly: $29.99 per year.
808 Membership Monthly: $7.99 per month.
If you decline the plans above, the app may offer Monthly, half price: a 7 day free trial, then $3.99 per month.
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
... `10-awards.png`, with `65/` beside them), the 6.5 inch copies in `appstore/65/`, the Watch pair in
`appstore/watch/`). Framed by `tools/store_shots.swift` in the valley's
daytime sky, SF Pro Rounded captions, a drawn generic bezel. Captured on the
iPhone 17 Pro Max simulator from a Debug build with `STORE_SHOTS=1`, which
hides the development-only test-mode cards and switches Otto's chat off as
Release has it; how to regenerate is in `marketing/README.md`.

**iPhone 6.9 inch (required). The listing leads with Otto, not Block**
(Melvin, 2026-09-29: "Youre focusing too much on the blocking aspect, thats
just one feature"). Upload in this order:

| # | File | Screen | Headline | Subhead |
|---|---|---|---|---|
| 1 | 01-otto | Home, Otto glowing at 100%, 7-day streak | Meditate consistently with Otto | He glows brighter every day you do |
| 2 | 02-shield | A held app's block screen ("not the doom scroll"), Otto gold | Otto blocks your apps until you meditate | Open one too soon and he lets you know |
| 3 | 03-shop | Shop, Otto trying on the Straw Sun Hat | Collect points, buy him hats | Every minute you meditate earns a point |
| 4 | 04-widget | Home screen with the medium and two small widgets | Otto on your home screen | Your streak and his glow at a glance |
| 5 | 05-sounds | The plus: the Ready screen's sound list | Meditate your way | Silence, nature, tones, a guided journey or your own audio |
| 6 | 06-texts | Otto's text thread after Ask Otto | Otto texts you before you scroll | Open a held app and he asks you to meditate first |
| 7 | 07-profile | Profile: a preset picture, "8 friends", streak, stats, your minutes (retaken 2026-10-19 for 1.4) | Every day adds up | Your streak and your minutes at a glance |
| 8 | 08-watch | A measured Watch session's results | Wear an Apple Watch for more | Heart rate, stillness and breathing, after each session |
| 9 | 09-friends | Friends: a weekly goal with Priya, eight friends, every one with a picture (retaken 2026-10-19 for 1.4) | Meditate with friends | See how often your friends meditate each week |
| 10 | 10-awards | The awards shelf, 30 of 58 | More than fifty awards | For showing up, going longer and trying new ways in |

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

**Apple Watch (required, we ship a Watch app)**: `appstore/watch/01-begin.png`
(start screen) and `02-measuring.png` (a live session), both 422 x 514, the
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
weekly goals and nudges 2026-10-18, 3,983 counted with line breaks twice).
Count again after any edit.

```
808 is a meditation app for iPhone with an optional Apple Watch app. No part of this review needs an Apple Watch.

SUBSCRIPTION
Nothing past the paywall opens without buying or restoring. The in-app purchases are attached to this version; use a sandbox account with no active 808 subscription.
To reach the paywall, go through onboarding. On "Ready to take control?", press and hold the round button for about three seconds until Otto rises and "Let's go!" appears, then tap Continue. The paywall is next.
It sells Yearly ($29.99, preselected) and Monthly ($7.99), with no free trial, plus Restore, Privacy Policy and Terms of Use. Tapping "No, I don't want to pay", or cancelling the purchase sheet, raises a banner offering Monthly, half price ($3.99 a month after a 7 day free trial) with its renewal terms and Terms and Privacy links. "Claim half price" opens the purchase sheet; "No thanks" closes it.
An account that already had a free trial is offered the half price from the first month.
"Plans aren't loading" means the sandbox returned no products.
People updating from 1.0 without a subscription meet the paywall at launch, with an Account link (Manage subscription, Redeem a code, Restore, Sign out, Delete account). Subscribers and Lifetime owners keep full access.

BLOCK (part of 808 Membership)
Family Controls with individual authorization: a person manages their own iPhone, not a parental control. After the paywall, onboarding asks for Screen Time permission. Declining continues; once allowed, at least one app is picked in Apple's picker. A held app shows Apple's shield. "Ask Otto" sends a notification that opens a short screen from Otto, ending in a meditation (five minutes or more opens the apps for the rest of that window) or "Not now" for 10, 20 or 30 minutes. If notifications are off, the shield says to open 808, and Otto appears there. Nothing from Screen Time leaves the device.

SESSIONS
Tap the plus, then the first button ("Meditate") to choose:
- Meditate: a timer on the iPhone. Nothing is measured.
- With Apple Watch: dimmed unless a Watch is paired; it wakes the Watch app to measure.
- Record one: logs a session done elsewhere.
Sessions count from one minute. Keep 808 open during an iPhone session: after 10 seconds away, including a locked screen, 808 says it won't count, and "I was still meditating" keeps it.
"Silence notifications" runs two Shortcuts, "808 Silence" and "808 Restore", added once from iCloud links (tap Add Shortcut, return to 808, then the second). When a session ends 808 briefly opens Shortcuts to run 808 Restore. 808 never changes Focus itself.

POINTS AND THE SHOP
Each whole minute meditated earns one point, spent in the Shop tab on hats for Otto. Recorded sessions earn none and never open Block's apps. Points cannot be bought and have no cash value.

FRIENDS
Opens from the circle at the top right of Home; needs iCloud. No posts, comments or typed messages. A profile shows a name, @username, optional photo, practice summary and friends, visible to anyone who looks up the username. It is optional and requires agreeing to the community rules.
Friends are added by @username or invite code. Two friends can share a weekly goal (days a week, from sessions of five minutes or more) and nudge each other once a day.
Other people's profiles carry Report and Block (... menu); reports reach our inbox at once, and a reported profile or photo is removed within 24 hours. Seeing another person takes a second device on another iCloud account.
Delete account (Profile tab, gear icon, or the launch paywall's Account link) removes the Friends profile, username, invite code, goals and connections.

HEALTH DATA
Heart rate is read only during a session measured by an Apple Watch. Results stay on the device, excluded from iCloud sync and backup (5.1.3(ii)). Each Watch session is saved to Apple Health as a workout and mindful minutes. Analytics never include a health value.
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
