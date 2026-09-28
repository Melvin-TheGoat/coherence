# Privacy Policy

**Last updated: September 28, 2026**

This Privacy Policy explains how **Lock Out Inc. ("we," "us")** handles
information in the **808 Meditate** app ("808") for iPhone, with optional
support for Apple Watch.

## The short version

808 is built to be private by design:

- **We don't run a server.** Your account, preferences, and session log sync
  through **your own private iCloud account** (Apple's CloudKit). Your
  **health results** (heart-rate trend, stillness, breathing rate, and Apple's
  heart-rate-variability readings when your Watch produces them) are stored
  **only on the device that recorded them**. The app never uploads them
  anywhere, not even to iCloud.
- **The one thing we can see is your Friends profile.** If you use Friends,
  your profile and a short summary of how often you meditate go to a shared
  area of iCloud that other people in 808 can read, and so can we. Nothing
  goes there unless you set up a profile, your health results never do, and
  you can delete all of it. See "Friends" below.
- **If you use Block, nothing about it ever reaches us.** The apps you
  choose to hold, and everything about how and when you open them, stay on
  your phone in Apple's own Screen Time system. See "Block" below.
- **We don't sell your data, run ads, or track you.** There are no advertising
  identifiers and no cross-app tracking. We collect anonymous usage analytics
  (which features are used, not what your body measured); see "Usage
  analytics" below.
- **Your health data never leaves your devices.** It's measured on your Apple
  Watch and turned into your session results; we never use it for advertising and
  never share it.
- **We don't know what you listen to.** 808 measures in the background so you can
  play a meditation from YouTube or any other app. We receive no information about
  what you play, and we have no connection to those services.
- **You can delete everything** at any time from Settings → Delete Account.

## Information the app handles

**Account information.** When you sign in with **Sign in with Apple**, the app
receives and stores a unique Apple user identifier. If you choose to share
them, it also receives your **name** and **email address** (which may be an
Apple private "Hide My Email" relay address). You may also set a display
name and choose whether to receive product emails.

**Health and motion data.** An Apple Watch is optional. When you start a
session on your Watch, or start one on your iPhone with "Meditate with Apple
Watch" turned on, your **Apple Watch** measures your **heart rate**
(via Apple HealthKit) and **movement** (via the motion sensors). The Watch
processes these into your **session results**: a heart-rate trend
(averaged, not beat-to-beat), a stillness measure, a breathing rate, Apple's
heart-rate-variability (SDNN) readings when your Watch happens to produce
them, and a summary score. A session you start on your iPhone without the
Watch measuring runs a plain timer: it measures nothing about your body.
Important details:

- The app requests HealthKit permission only for **heart rate**,
  **heart-rate variability (SDNN)**, **workouts** and **mindful minutes**.
  Each session is written to Health as a Mind and Body workout and as mindful
  minutes, so it appears beside Apple's own. Heart rate is read
  **live during a session** only. HRV is read as Apple's own passive samples,
  including up to 30 days of them, solely to give your readings a baseline.
  Nothing else in your Health history is read.
- We store the **computed results**, not raw biometric samples. The iPhone reads
  **no** biometric data directly.
- **Measurement runs only during a session you start**, and stops when the session
  ends. It does not run in the background at other times.
- **The camera is used in three places, and never records or saves anything
  beyond what you choose.** You can take a profile photo for Friends; you can
  add photos or videos to a session's own page, either taken with the camera
  or chosen from your library through Apple's private picker (which hands
  808 only the items you pick, never access to your library); and if you use
  Block, Otto's video-call-style screen shows you a live preview of your own
  front camera, the way an incoming call would, which is never recorded,
  saved, or sent anywhere. Photos and videos you add to a session stay
  private to you.
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
and similar settings). Otto's glow, your points and the hats you choose for
him are worked out on your phone from your own sessions. Your answers to the
questions when you first open the app are kept in the app and are never sent
to us.

**Notifications.** Besides the optional daily reminder, 808 can send you
three kinds of notification, all about something you started yourself: that
a timed session you set is finishing; that a session on your phone is still
running after you left the app, so you can come back to it; and, if you use
Block, a note from Otto after you open an app you chose to hold. These are
marked Time Sensitive so they can reach you even if you have notifications
quieted, the same way a timer or an alarm would. You
choose whether to allow notifications at all, in the iOS prompt or in
Settings, and 808 only asks the first time one of these moments happens.

**Silencing notifications during a sit.** If you set it up, the session
screen can offer a switch that turns Do Not Disturb on while you sit and
off again afterward. No app can turn Do Not Disturb on directly, so this
works by running two small Shortcuts you install yourself from a link we
publish; 808 asks Shortcuts to run them by name. To show the switch's state
honestly, 808 may ask permission to read whether a Focus is currently on;
that read happens only on your device and is never sent anywhere. This
feature is entirely optional and does nothing unless you set it up.

**Usage analytics.** The app sends us anonymous usage events so we can see
which features are used and where people get stuck: things like "a session was
started", "a session was completed" with its rough length, which onboarding
screens were completed, and whether a subscription screen was viewed. These
events are processed for us by PostHog, Inc. on servers in the United States,
under an anonymous identifier created for your install. They are never linked
to your name, email, or Apple ID.

**Your measurements are never in those events.** No heart rate, breathing
values, stillness, scores, or anything derived from your body's signals is
ever included, at any precision. Your health results stay on your device,
exactly as described above. Nothing about your Block apps or how you use them
is ever included either; see "Block" below.

**What we do NOT collect.** We do not collect your location, contacts, or
browsing activity. We do not access, monitor, or receive any information about
other apps you use or the audio, video, or media you play while a session runs.
We use no advertising identifiers and no cross-app or cross-website tracking.

## Where your information lives and who can access it

Your information lives in four places, by design:

- **Health results stay on your device.** Your session measurements (the
  heart-rate trend, stillness, breathing-rate and heart-rate-variability
  results) are stored **only in the app's local storage on the device that
  recorded them**. The app never syncs them to iCloud or anywhere else.
- **Account and session log sync privately.** Your account info, preferences,
  and the log of your sessions (dates, durations, types, ratings, notes, and
  any photos or videos you add after a session) sync to **your personal
  private iCloud database** using Apple's CloudKit, so they survive
  reinstalls and follow your own devices. None of it is shared with anyone.
- **Your Friends profile is shared.** If you set up a profile in Friends,
  your username, display name, profile photo and practice summary go to a
  **shared (public) area of our iCloud container**. Other people using 808
  can see it, and so can we. This is the only information you give 808 that
  we are able to read.
- **Block and Screen Time choices stay on your device only.** If you use
  Block, the apps you pick to hold and everything about when you open them
  live in an area your phone shares privately between 808 and its Screen
  Time extensions. Nothing about it is stored in iCloud, on any server, or
  anywhere we or anyone else can reach. See "Block" below.

**We do not operate servers of our own, and we cannot access the contents of
your private iCloud database.** Apple processes all of this under
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## Friends

Friends is optional. If you never create a profile, nothing in this section
applies to you and 808 never touches the shared area.

**What goes there when you use it:**

- Your **profile**: the username you choose, your display name, a profile
  photo if you add one, and the month you started practicing.
- Your **practice summary**: how many sessions and minutes you meditated in
  the last seven days, your current streak, your total number of sessions,
  and when your last session was. The app works these out from your session
  log and updates them when you open it.
- **Who you have added**, and who has added you.
- A **report** you file about someone, including the reason you type, and
  anyone you **block**.

**What never goes there:** your score, your heart rate, your breathing, your
stillness, any of the curves or readings behind them, your notes, and the
photos or videos you add to your sessions.

**Posts.** Earlier versions of 808 let you post a session to friends. The app
no longer does, and posts made in those versions have been deleted.

**Who can see it:** anyone using 808 can find your profile by your username,
and your practice summary is part of that profile. We can read everything in
the shared area, because moderating it requires that.

**Moderation.** Usernames and names are filtered for objectionable language
before they are accepted. You can report a person, and you can block someone,
which hides you from each other in both directions. We remove content that
breaks our terms and we can remove accounts that repeatedly break them.

**Deleting it.** **Deleting your account removes your profile, your practice
summary, the friend requests and connections you created, the reactions you
gave, and the blocks you made, from the shared area.** This starts right
away; if the shared area can't be reached at that moment it finishes
automatically the next time you open the app. Reports you filed are kept as
a record of what was reported, the way any report stays on file after the
person who filed it moves on, so we can keep acting on them. A friend request
or connection someone else made toward you belongs to them, and deleting your
account is what removes your side of it and empties it of meaning, since your
profile is gone.

## Block

Block is optional and is part of 808's paid membership. If you never turn on
a blocker, nothing in this section applies to you.

Block uses Apple's own Screen Time tools (the Family Controls framework) so
you can hold apps you find distracting until you've meditated. You pick the
apps, categories, or websites yourself, from Apple's own picker, for a
window you choose. **808 never learns which apps you picked.** Apple hands
the app your choices as sealed tokens that identify what to shield without
identifying it to us, and we never ask for anything more specific.

When a held app is shielded, you can ask Otto for a few minutes or start a
meditation; finishing a short one releases the apps for the rest of that
window. Every part of that, including whether you've meditated today, which
apps are currently held, and how many times you've asked for a few more
minutes, is worked out on your phone and stays there.

**Nothing from Block ever leaves your phone.** Apple's own terms for the
Family Controls framework say this plainly: this kind of data "may only be
used for providing family controls, or individual device management," may
not be shared "beyond... the individual and their device," and may never be
used or shared "for purposes of advertising or advertising measurements," or
given to a data broker. 808 follows that to the letter: nothing about your
blockers, the apps you picked, or how you use Block reaches our usage
analytics, your Friends profile, or any server, ours or anyone else's.

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
- To send **product emails**, only if you opt in and provide a non-relay email.
  If you opt in, your email address may be shared with our email delivery provider
  solely to send those messages; you can opt out any time in Settings.

We never use your health or motion data for advertising, and we never sell it.

## Third-party apps and media you choose

808 is designed so that you can play a meditation, music, or a video from any
other app or website while it measures. Those services are **not affiliated with
us, not integrated with 808, and not under our control**. We do not embed them,
communicate with them, or receive any data from them, and your use of them is
governed by their own terms and privacy policies, not ours.

## Our website and earlier waitlists

Our website does not ask for your email and sets no account. If you fill out
our optional questionnaire, we collect only the answers you choose to give
about your meditation habits and interest in the app, and use them to shape
the product. We do not sell or share them.

**Earlier waitlists.** Before 808 launched, our website offered a waitlist,
and earlier versions of the app offered a waitlist for a version that works
without an Apple Watch. If you joined one, we hold only the email address you
gave (and, for the website list, whether you said you own an Apple Watch; for
the app list, the app's version number). We use it only to email you about
808, every email includes an unsubscribe link, and you can email us to be
removed at any time. Neither list is linked to your app usage or to any
health data.

## Third parties

- **Apple**: Sign in with Apple, HealthKit, Screen Time (Family Controls),
  CloudKit/iCloud sync, Shortcuts, and App Store distribution, governed by
  Apple's terms.
- **Email delivery provider**: only your email address, and only if you opt into
  product emails or joined one of the earlier waitlists. The provider stores the
  address in order to send those emails and does not receive any health data.
- **Form processing**: questionnaire responses and the earlier waitlist emails
  are stored in spreadsheets hosted by Google. No health data is collected
  there.
- **PostHog, Inc.**: anonymous usage analytics for the app, as described
  under "Usage analytics." PostHog receives feature-usage events under an
  anonymous identifier and never receives health data, Block or Screen Time
  data, your name, or your email.
- Audio in the app is bundled with the app; playing it sends no data about you.

We otherwise do not share your information with third parties, and we do not use
health data with any third party for advertising.

## Data retention and deletion

We keep your data until you delete it. **Settings → Delete Account** signs you out
and marks your account for deletion; your account and all associated data,
including your Friends profile as described under "Friends" above, are then permanently removed within **30 days**. Signing back in before
then restores it. You can also delete the app; to remove synced data, delete the
app's data from your iCloud settings.

## Your choices and rights

- **Access / delete:** your data is in the app; you can delete all of it via
  Delete Account.
- **Product emails:** opt in/out in Settings.
- **HealthKit:** you control heart-rate and workout permissions in the iOS/watchOS
  Health and privacy settings at any time.
- **Notifications:** you control them in iOS Settings at any time.
- **Block and Screen Time:** you control every blocker in the app at any time,
  and your choices never leave your device in the first place.
- Depending on where you live (e.g., the EU/UK under GDPR, or California under the
  CCPA/CPRA), you may have additional rights to access, correct, or delete your
  information, and to not be discriminated against for exercising them. Because we
  hold no copy of your health data on our own servers, most requests are fulfilled
  directly through the app's deletion controls. Contact us with any questions.

## Consumer health data

This section supplements the rest of this policy for laws that specifically
protect **consumer health data** (such as the Washington My Health My Data Act)
and applies to all users.

- **Categories we process:** heart rate measured by your Apple Watch during a
  session you start with the Watch measuring; motion-derived measurement of how still your
  body was; and the session results computed from them. A session started on
  your iPhone without the Watch measuring processes none of this.
- **Source:** the sensors of your own Apple Watch, via Apple HealthKit and
  CoreMotion, only while a session you started is running.
- **Purpose:** solely to compute and show you your own session results. No
  other use.
- **Consent:** the app asks for your consent in-app before any measurement, and
  Apple's HealthKit permission prompt independently controls heart-rate access.
- **Sharing and sale:** we do **not** sell consumer health data, and we do not
  share it with anyone. It is processed on your devices; we never receive it.
- **Your rights:** view your results in the app at any time; delete them via
  **Settings → Delete Account** (which removes all app data) or by deleting the
  app from the device holding the results. For questions or requests, contact us
  at **support@meditate808.com**.

## Children

808 is not directed to children under 13, and we do not knowingly collect personal
information from children under 13.

## Security

Your data is protected by your device's security and by Apple's encryption of
iCloud data. No method of storage or transmission is 100% secure, but because we
operate no servers holding your personal or health data, the attack surface
for that data is limited to your own device and Apple's infrastructure.
Anonymous usage events are held by PostHog under its own security practices.

## Changes to this policy

We may update this policy. We'll revise the "Last updated" date and, for material
changes, provide notice in the app. Continued use after an update means you accept
the revised policy.

## Contact

Questions about this policy or your data: **support@meditate808.com**.
