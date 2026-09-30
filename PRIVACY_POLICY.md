# Privacy Policy

**Last updated: September 29, 2026**

This Privacy Policy explains how **Lock Out Inc. ("we," "us")** handles
information in the **808 Meditate** app ("808") for iPhone, with optional
support for Apple Watch.

## The short version

808 is built to be private by design:

- **We don't run servers of our own.** Your account, preferences, and session
  log sync through **your own private iCloud account** (Apple's CloudKit),
  which we cannot read. Your **health results** (heart-rate trend, stillness,
  breathing rate, and score) are stored **only on your iPhone** and are left
  out of your iCloud Backup. The app never uploads them anywhere, not even to
  iCloud, unless you choose to share or save a session card.
- **What reaches us is limited.** We can read your Friends profile if you
  choose to create one, pseudonymous usage analytics, and any report you file
  about another person. See "Friends" and "Usage analytics" below.
- **Friends is optional.** If you create a profile, your username, name,
  optional photo, a summary of how often you meditate, and who you have added
  and who has added you go to a shared area of iCloud where anyone using 808
  can look them up. Your health results never go there.
- **Nothing about Block reaches us.** The apps you choose to hold, and
  everything about how and when you open them, stay on your phone in Apple's
  own Screen Time system. See "Block" below.
- **We don't sell your data, run ads, or track you.** There are no advertising
  identifiers and no cross-app tracking. We collect pseudonymous usage
  analytics (which features are used, on what kind of iPhone, and roughly
  where in the world), never what your body measured, and you can turn them
  off in Settings. See "Usage analytics" below.
- **808 never sends your health data off your devices** unless you choose to
  share or save a session card. It's measured on your Apple Watch and turned
  into your session results on your own devices; we never receive it, never
  use it for advertising, and never share it.
- **We don't know what you listen to.** 808 measures in the background so you can
  play a meditation from YouTube or any other app. We receive no information about
  what you play, and we have no connection to those services.
- **You can delete your account at any time**, from Settings or from Account
  on the membership screen. "Data retention and deletion" below explains
  exactly what that removes and what it does not.

## Information the app handles

**Account information.** Signing in is optional. If you sign in with
**Sign in with Apple**, the app receives and stores a unique Apple user
identifier. If you choose to share it, it also receives your **name**. 808
does not ask Sign in with Apple for your email address. Earlier versions did,
so an account created before version 1.1 may hold one (possibly an Apple
private "Hide My Email" relay address). Your name, and any such address, stay
in the app and in your private iCloud, where we cannot read them. You may
also set a display name. 808 does not send product or
marketing emails; if that ever changes, we will ask first and update this
policy.

**Health and motion data.** An Apple Watch is optional. When you start a
session on your Watch, or start one on your iPhone with Apple Watch measuring
turned on, your **Apple Watch** measures your **heart rate** (via Apple
HealthKit) and **movement** (via the motion sensors). The Watch processes
these into your **session results**: a heart-rate trend (averaged, not
beat-to-beat), a stillness measure, a breathing rate, and a summary score.
It sends them straight to your iPhone. A session you start on your iPhone
without the Watch measuring runs a plain timer: it measures nothing about
your body. Important details:

- The app requests HealthKit permission only to **read heart rate** and to
  **save workouts and mindful minutes**. Each measured session is saved to
  Apple Health as a Mind and Body workout and as mindful minutes, so it
  appears beside Apple's own. Heart rate is read **live during a session**
  only. 808 never reads your workout history; it only saves the workouts its
  own sessions create. Nothing else in your Health history is read. Once saved,
  those workouts and mindful minutes are part of your Apple Health data and
  are handled under your own Health settings.
- We store the **computed results**, not raw biometric samples. The iPhone reads
  **no** biometric data directly.
- **Measurement runs only during a session you start**, and stops when the session
  ends. It does not run in the background at other times.
- **The camera is used only when you choose to take a photo, and never records
  or saves anything beyond what you choose.** You can take a profile photo for
  Friends, and you can add photos or videos to a session's own page, taken with
  the camera or chosen from your library through Apple's private picker (which
  hands 808 only the items you pick, never access to your library). Photos and
  videos you add to a session stay private to you. When Block invites you to
  meditate, Otto's video-call-style screen can also show you a live preview
  of your own front camera, the way an incoming call would; that preview is
  never recorded, saved, or sent anywhere.
- **Saving a session card to your Photos is add-only.** If you tap Share on
  a result, 808 can save that card as an image to your photo library. It
  uses **add-only** access, which means it can add that one image and
  cannot see, read, or browse anything already there.

**Sessions run in the background.** So that you can listen to whatever you like
while you practice, a session keeps measuring on your Apple Watch after you leave
the 808 app on your phone. This does not change what we collect: the same heart
rate and movement, only during a session you started, only on your own devices.

**Session and app data.** Session dates, durations, the type of session, your
results and streak, and your **preferences** (reminder time, default length,
and similar settings). Otto's glow, your points, and the hats you choose for
him are worked out on your phone from your own sessions. In 808 1.1 and later,
your answers to the questions when you first open the app are kept in the app
and are never sent to us. The one exception is what you choose to put on a
Friends profile, such as your name and username. Versions before 1.1 sent one
answer with usage analytics: whether you said during setup that you own an
Apple Watch.

**Notifications.** Besides the optional daily reminder, 808 can send you three
kinds of notification, all about something you started yourself: that a timed
session you set is finishing; that a session on your phone is still running
after you left the app, so you can come back to it; and a note from Otto after
you open an app you chose to hold with Block. These are marked Time Sensitive
so they can reach you even if you have notifications quieted, the same way a
timer or an alarm would. You choose whether to allow notifications at all, in
the iOS prompt or in Settings. 808 asks during setup or the first time one of
these moments happens.

**Silencing notifications during a sit.** If you set it up, the session
screen can offer a switch that turns Do Not Disturb on while you sit and
off again afterward. No app can turn Do Not Disturb on directly, so this
works by running two small Shortcuts you install yourself from a link we
publish; 808 asks Shortcuts to run them by name. To show the switch's state
honestly, 808 may ask permission to read whether a Focus is currently on;
that read happens only on your device and is never sent anywhere. This
feature is entirely optional and does nothing unless you set it up.

**Usage analytics.** The app sends us pseudonymous usage events so we can see
which features are used and where people get stuck. They are processed for
us by PostHog, Inc. on servers in the United States, and they include:

- **What you do in the app**, for example: which setup screens you finished
  (never your answers), whether you allowed reminders and Health access,
  sessions started and completed with their rough length and your rough
  streak (in bands such as "3 to 7 minutes"), whether a session with your Watch saved its readings
  (never the readings themselves), sessions recorded by hand or deleted, Otto's
  glow moving to a new stage, awards earned, which of 808's own notifications
  you opened, which hat Otto wears, and counts of
  Friends actions such as creating a profile, sending a request, or blocking
  someone.
- **Subscriptions:** when a plan screen or offer is shown, the plan you pick,
  purchases, free trials, restores, and a subscription ending, and whether you
  currently subscribe and to which plan.
- **Your Apple Watch setup:** whether a Watch is paired with your iPhone,
  whether you turn Watch measuring on or off, and the first time a Watch
  connects to 808.
- **When the app is installed, updated, opened, and closed.**
- **Device and app information** that PostHog's software adds automatically:
  your iPhone model, iOS version, the app's version and build number, whether
  it was installed from TestFlight, language, time zone, screen size, and
  whether you are on Wi-Fi or cellular.
- **Approximate location.** PostHog receives your device's IP address with
  each event, as any internet service does, and uses it to estimate an
  approximate location (country, region, and city). We use it only to
  understand where people use 808.

These events are tied to a random identifier created for your install. They
never carry your name, email, Apple ID, or Friends username, and the
identifier is replaced with a new one when you sign out or delete your
account. Because every event from one install shares that identifier, the
App Store lists this data as linked to you; the identifier is the only thing
it is tied to. We also keep a copy of these analytics in a Google Sheet so
we can read them more easily: one row per install, with its random
identifier, when it was installed and last opened, its app and iOS version,
iPhone model, approximate location, the plan bought if any, and counts of
what was used.

**You can turn usage analytics off** at any time in the app's Settings with
the **Share usage analytics** switch. While it is off, the app sends no usage
events to PostHog at all, and it stays off until you turn it back on. It is
on when you first install 808.

**Your measurements are never in those events.** In 808 1.1 and later, no
heart rate, breathing values, stillness, scores, or anything derived from
your body's signals is included, at any precision. Your health results stay
on your device, exactly as described above. Versions before 1.1 sent one
fact derived from a score: that you earned an award for reaching a score of
50, 75 or 90. Nothing about your Block apps or how you use them is ever
included; see "Block" below.

**What we do NOT collect.** We do not collect your precise location, contacts,
or browsing activity. We do not access, monitor, or receive any information about
other apps you use or the audio, video, or media you play while a session runs.
We use no advertising identifiers and no cross-app or cross-website tracking.

## Where your information lives and who can access it

Your information lives in these places, by design:

- **Health results stay on your iPhone.** Your session measurements (the
  heart-rate trend, stillness, breathing rate, and score) are stored **only in
  the app's local storage on your iPhone** and are left out of your iCloud
  Backup. The app never uploads them to iCloud or anywhere else unless you
  choose to share or save a session card.
- **Account and session log sync privately.** Your account info, preferences,
  and the log of your sessions (dates, durations, types, ratings, notes, and
  any photos or videos you add after a session) sync to **your personal
  private iCloud database** using Apple's CloudKit, so they survive
  reinstalls and follow your own devices. None of it is shared with anyone,
  and we cannot read it.
- **Your Friends profile is shared.** If you create a profile in Friends,
  your username, display name, profile photo, practice summary, and who you
  have added and who has added you go to a **shared (public) area of our
  iCloud container**. Anyone using 808 can look it up, and we can read
  everything in that area. See "Friends" below.
- **Usage analytics and reports reach us.** Pseudonymous usage events go to
  PostHog, with a copy in a Google Sheet, as described under "Usage
  analytics." A report you file is stored in the shared area and sent to us,
  as described under "Friends."
- **Block and Screen Time choices stay on your device only.** The apps you
  pick to hold with Block and everything about when you open them live in an
  area your phone shares privately between 808 and its Screen Time
  extensions. It is never synced to iCloud or sent to any
  server, ours or anyone else's; like the rest of your phone, it can be part
  of your own device backup. See "Block" below.

**We run no servers of our own.** Information reaches us only through
services we use: PostHog for usage analytics, the shared area of our iCloud
container for Friends, Google Sheets, and two small Google Apps Script web
apps we control, which receive reports and, from earlier versions of 808,
waitlist sign-ups. **We cannot access the contents of your private iCloud
database.** Apple processes iCloud data under
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## Friends

Friends is optional. You can choose "Not now" wherever 808 offers it, and
creating a profile asks you to agree to our community rules (section 6a of
our [Terms of Service](https://meditate808.com/terms)). If you never create a
profile, 808 writes nothing about you to the shared area.

**What goes there when you create a profile:**

- Your **profile**: the username you choose, your display name, a profile
  photo if you add one, and the dates you created your profile and first
  meditated with 808. The profile itself shows only the month you created
  it.
- Your **practice summary**: how many sessions and minutes you meditated in
  the last seven days, your current streak, your total number of sessions,
  and the date and time of your last session. The app works these out from
  your session log and updates them when you open it. It is published only
  if you have a profile.
- **Who you have added**, and who has added you.
- A **report** you file about someone, including the reason you type, and
  anyone you **block**.

**What never goes there:** your score, your heart rate, your breathing, your
stillness, any of the curves or readings behind them, your notes, and the
photos or videos you add to your sessions.

**Posts.** Test versions of 808 let testers post a session to friends. The
App Store version never has, and posts made in those test versions are
deleted.

**Who can see it:** anyone using 808 who looks up your username can see your
profile: your name, username, photo if you added one, the month you created
your profile, your streak, your sessions and minutes this week, your total
number of sessions, the date of your last session, and who you have added
and who has added you (your following and followers). This is not limited to
people you have added.

Everything else 808 writes to the shared area is stored where other
people's copies of 808 can read it too, even though the app does not show it
to them. That includes the exact dates and times you created your profile,
first meditated with 808, and last meditated. Reports and blocks are the
exceptions: a report is kept where only we and the person who filed it can
read it, and a block where only we and the person who made it can read it.
We can read everything in the shared area, reports and blocks included,
because moderating it requires that.

**Reports.** When you report someone, the report (who filed it, who it is
about, and the reason you give) is stored in the shared area. A copy with the
report's reference numbers, the reason you gave, and the app version is also
sent through a Google Apps Script web app we control, which adds it to a
Google Sheet and emails us so we can act on it quickly. The person you report
is not told who reported them.

**Moderation.** Usernames and names are filtered for objectionable language
before they are accepted. You can report a person, and you can block someone.
A block is private and one-sided: the person you block is not told, their
friend requests never reach you and cannot be accepted, and you stop seeing
them anywhere in Friends. Because profiles are public, they can still look up
your profile (your name, username, photo and practice summary). We remove
content that breaks our terms and we can remove accounts that repeatedly break
them.

**Deleting it.** **Deleting your account deletes your profile, your username,
your practice summary, the friend requests and connections you created, and
the blocks you made from the shared area, right away.** If the shared area
can't be reached at that moment, the deletion finishes automatically on a
later launch of the app, once it can be reached. Signing back in does not bring your profile back; you
would create a new one. Reports you filed are kept as a record of what was
reported, the way any report stays on file after the person who filed it
moves on, so we can keep acting on them. A friend request or connection
someone else made toward you belongs to them; once your profile is gone, it
no longer points to anyone.

## Block

Block, part of 808's paid membership since version 1.1, is optional: if you
never turn on a blocker, nothing in this section applies to you.

Block uses Apple's own Screen Time tools (the Family Controls framework) so
you can hold apps you find distracting until you've meditated. You pick the
apps, categories, or websites yourself, from Apple's own picker, for a
window you choose. **808 never learns which apps you picked.** Apple hands
the app your choices as sealed tokens that identify what to shield without
identifying it to us, and we never ask for anything more specific.

When a held app is shielded, you can ask Otto, who invites you to meditate.
A meditation of five minutes or more opens the apps for the rest of that
window, or you can tell Otto "Not now" for 10, 20 or 30 minutes. Every part
of that, including whether you've meditated today, which apps are currently
held, and when you told Otto "Not now", is worked out on your phone and stays
there.

**Nothing from Block is ever sent anywhere.** Apple's own terms for the
Family Controls framework say this plainly: this kind of data "may only be
used for providing family controls, or individual device management," may
not be shared "beyond... the individual and their device," and may never be
used or shared "for purposes of advertising or advertising measurements," or
given to a data broker. 808 follows that to the letter: nothing about your
blockers, the apps you picked, or how you use Block reaches our usage
analytics, your Friends profile, or any server, ours or anyone else's. It is
never synced to iCloud; like the rest of your phone, it can be part of your
own device backup.

**This is self-management, not parental control.** Block only manages the
iPhone you set it up on, for the person using it. 808 has no way to manage,
see, or restrict a device that isn't yours, and it isn't built to.

**Otto's screens.** When Block invites you to meditate, one of the screens
you may see is a video-call-style invitation from Otto. It shows you a live
preview of your own front camera, the way an incoming call would show your
own picture, so you can see yourself before you answer. That preview is
never recorded, saved, or sent anywhere. It disappears the moment you leave
the screen.

**Turning it off.** You can switch any blocker off, adjust its apps or
timing, or leave it on hold for a while, at any time in the app.

## How the information is used

- To provide the app: run sessions, compute and show your evidence and history,
  and sync across your own devices.
- To let you know when a timed session is ending, or when Otto has something
  to say after Block held an app, as described under "Notifications" above.
- To send a **daily reminder**, only if you enable it (a local notification
  scheduled on your device).
- To show your Friends profile to other people using 808, only if you create
  one, and to review and act on reports.
- To understand which features are used and where people get stuck, through
  pseudonymous usage analytics.
- To email people who joined an earlier waitlist about 808, as described
  under "Our website and earlier waitlists."

808 does not send product or marketing emails; if that ever changes, we will
ask first and update this policy.

We never use your health or motion data for advertising, and we never sell it.

## Third-party apps and media you choose

808 is designed so that you can play a meditation, music, or a video from any
other app or website while it measures. Those services are **not affiliated with
us, not integrated with 808, and not under our control**. We do not embed them,
communicate with them, or receive any data from them, and your use of them is
governed by their own terms and privacy policies, not ours.

## Our website and earlier waitlists

Our website has no accounts and shows no ads. It is hosted by Cloudflare,
which handles the technical information any website receives, such as your
IP address, in order to deliver the pages. If you fill out our optional
questionnaire, we collect only the answers you choose to give about your
meditation habits and interest in the app, plus your email address if you
choose to add it so we can tell you when something is ready. Your answers go
to a Google Sheet through a Google Apps Script web app we control. If that
fails, they are sent to us by email through FormSubmit (formsubmit.co)
instead. We use them to shape the product and do not sell or share them.

**Earlier waitlists.** Before 808 launched, our website offered a waitlist,
and earlier versions of the app offered a waitlist for a version that works
without an Apple Watch. If you joined one, we hold only the email address you
gave (and, for the website list, whether you said you own an Apple Watch; for
the app list, the app's version number). We use it only to email you about
808, and you can ask to be removed at any time by replying to one of our
emails or writing to support@meditate808.com. Neither list is linked to your
app usage or to any health data.

## Third parties

- **Apple**: Sign in with Apple, HealthKit, Screen Time (Family Controls),
  CloudKit/iCloud sync, Shortcuts, and App Store distribution, governed by
  Apple's terms.
- **PostHog, Inc.**: pseudonymous usage analytics for the app, as described
  under "Usage analytics." PostHog receives usage events, device and app
  information, and your IP address (which it uses to estimate an approximate
  location) under a random identifier. It never receives health data, Block
  or Screen Time data, your name, your email, or your Friends username.
- **Google**: questionnaire responses, the earlier waitlist emails, a copy of
  the usage analytics (one row per install: its random identifier, when it
  was installed and last opened, app and iOS version, iPhone model,
  approximate location, the plan bought if any, and counts of what was
  used), and reports you file
  are kept in spreadsheets hosted by Google. Reports and app waitlist sign-ups
  reach them through Google Apps Script web apps we control, and reports are
  also emailed to us. No health data is ever sent there.
- **FormSubmit**: if our questionnaire can't reach Google, FormSubmit
  (formsubmit.co) forwards your answers to us by email.
- **Cloudflare**: hosts our website.
- **Email delivery provider**: if we write to people on an earlier
  waitlist, an email service may receive your email address in order to
  deliver those emails. It never receives health data.
- Audio in the app is bundled with the app; playing it sends no data about you.

Each service provider above that handles your information for us is bound,
under its terms with us, to protect it at least as well as this policy does
and to use it only to provide its service to us. We otherwise do not share
your information with third parties, and we never share health data with any
third party.

## Data retention and deletion

We keep your data until you delete it. You can delete your account from
**Settings → Delete account**, or from **Account → Delete account** on the
membership screen, whether or not you have a subscription. Deleting your
account does not cancel a subscription: an active one keeps billing until
you cancel it in the Settings app on your iPhone (tap your name, then
Subscriptions). Here is exactly what happens:

- **Right away, and permanently:** the app deletes your account, sessions,
  results, reflections, photos, videos and preferences from your iPhone, and
  the same deletion removes them from your private iCloud as it syncs (the
  next time your iPhone reaches iCloud, if it can't at that moment). It also
  deletes your Friends profile and everything you wrote to the shared area
  (except reports), as described under "Friends", and replaces the
  analytics identifier on your phone with a new one. Nothing can be
  restored: signing in again with the same Apple ID starts a new, empty
  account.
- **What deleting your account does not remove:** the Mind and Body workouts
  and mindful minutes saved to Apple Health (you can delete them in the
  Health app); usage analytics already sent, which are tied only to the
  random identifier described under "Usage analytics," never to your name,
  email, Apple ID or Friends username; and reports you filed. If you delete
  the app without deleting your account, the copy in your private iCloud
  stays until you remove it: on
  your iPhone, go to Settings, tap your name, then iCloud, and delete 808's
  data from your iCloud storage.

You can also delete individual sessions in the app at any time.

We keep usage analytics only as long as they help us improve 808, and they
are tied only to the random identifier described under "Usage analytics,"
never to your name, email, Apple ID or Friends username. We keep reports as
long as we need them to moderate Friends.

## Your choices and rights

- **Access / delete:** your data is in the app, and you can delete your
  account and its data as described under "Data retention and deletion."
- **HealthKit:** you control heart-rate, workout, and mindful-minutes
  permissions in the iOS/watchOS Health and privacy settings at any time.
- **Notifications:** you control them in iOS Settings at any time.
- **Usage analytics:** turn them off or back on at any time with the
  **Share usage analytics** switch in the app's Settings.
- **Friends:** creating a profile is your choice, and deleting your account
  deletes it.
- **Block and Screen Time:** you control every blocker in the app at any time,
  and your choices are never sent to us or anyone else.
- Depending on where you live (for example, California under the CCPA/CPRA,
  or the EEA, UK or Switzerland, described in the next section), you may have
  additional rights to access, correct, or delete your information, and to
  not be discriminated against for exercising them. Because we never receive
  your health data, most requests are fulfilled directly through the app's
  deletion controls. For anything else, including usage analytics, reports,
  or waitlist emails, contact us.

## If you are in the EEA, the UK or Switzerland

**Who is responsible.** Lock Out Inc. is the controller of the personal data
described in this policy. Contact us at **support@meditate808.com** or at the
address under "Contact."

**Why we may use it (legal bases).**

- **Our contract with you:** providing the app and your subscription,
  creating and showing a Friends profile you ask us to create, and deleting
  your account when you ask.
- **Your consent:** reading Apple Health data during a measured session,
  sending notifications, and publishing a Friends profile. You can withdraw
  consent at any time: in the Health app, in iOS Settings, or by deleting
  your account. Withdrawing does not affect what happened before.
- **Our legitimate interests:** pseudonymous usage analytics, to understand
  which features are used and where people get stuck, and handling reports,
  to keep Friends safe. You can object to either, as described below.

**International transfers.** PostHog, Google and Cloudflare process data for
us in the United States. Those transfers rely on the European Commission's
Standard Contractual Clauses or on the EU-US Data Privacy Framework (and its
UK and Swiss counterparts), as each provider offers.

**Your rights.** You may ask to access, correct, delete or port your personal
data, and object to our use of it, by writing to
**support@meditate808.com**. You also have the right to complain to a data
protection authority where you live or work.

## Consumer health data

This section supplements the rest of this policy for laws that specifically
protect **consumer health data** (such as the Washington My Health My Data Act)
and applies to all users.

- **Categories we process:** heart rate measured by your Apple Watch during a
  session you start with the Watch measuring; how still your body was and your
  breathing rate, both worked out from your Watch's motion sensors; the session
  results and score computed from them; and the Mind and Body workouts and
  mindful minutes 808 saves to Apple Health. A session started on your iPhone
  without the Watch measuring processes none of this.
- **Source:** the sensors of your own Apple Watch, via Apple HealthKit and
  CoreMotion, only while a session you started is running.
- **Purpose:** solely to compute and show you your own session results, and
  to save your sessions to Apple Health where you allowed it. No other use.
- **Consent:** if an Apple Watch is paired when you first set up 808, the
  app explains what it measures and asks you to agree during setup, before
  Apple's Health permission sheet appears. Otherwise, Apple's Health
  permission sheet asks for your permission before your first measured
  session. Either way, heart rate cannot be read until you allow it there,
  and you can change that permission at any time in your Health settings.
- **Sharing and sale:** we do **not** sell consumer health data, and we do not
  share it with anyone. It is processed on your devices; we never receive it.
  (Versions of 808 before 1.1 sent one score-derived fact with usage
  analytics, as described under "Usage analytics.")
- **Your rights:** view your results in the app at any time; delete them by
  deleting a session, by deleting your account (as described under "Data
  retention and deletion"), or by deleting the app from the iPhone holding the
  results. Workouts and mindful minutes saved to Apple Health can be deleted
  in the Health app. For questions or requests, contact us at
  **support@meditate808.com**.

## Children

808 is for people at least 13 years old, or the minimum age of digital
consent where you live, the same age our Terms of Service require. It is not
directed to anyone younger, and we do not knowingly collect personal
information from them. If you believe someone younger has created a Friends
profile or otherwise given us information, write to
**support@meditate808.com** and we will remove it.

## Security

Your data is protected by your device's security and by Apple's encryption of
iCloud data. No method of storage or transmission is 100% secure, but because we
run no servers of our own and never receive your health data, the attack surface
for that data is limited to your own devices and Apple's infrastructure.
Pseudonymous usage events are held by PostHog, and the copies in our Google
Sheets by Google, under their own security practices.

## Changes to this policy

We may update this policy. We'll revise the "Last updated" date and, for material
changes, provide notice in the app. Continued use after an update means you accept
the revised policy.

## Contact

Questions about this policy or your data: **support@meditate808.com**, or
Lock Out Inc., 8 The Green, Ste A, Dover, DE 19901, United States.
