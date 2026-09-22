# 808 is a consistency app

Written down 2026-09-21 from Melvin's brief, because it changes the purpose,
the website, the store copy and most of the app's sentences. Read this before
writing anything a user will see.

## The pivot in one paragraph

The hardest thing about meditation is not doing it well, it is doing it again
tomorrow. 808's value is making meditation consistent. Otto is the way it
does that: someone you take care of, like a Tamagotchi or the brain in
Brainrot, who glows when you keep showing up and slumps when you do not, so
there is a reason to sit today that is not willpower. And because the thing
that eats the time is the phone, 808 holds your most addictive apps until you
have meditated, in the window you chose: before the first scroll in the
morning, before bed at night, or anywhere in between.

Measurement (the score, the Watch) stays, as a feature. It is no longer the
headline.

## Otto's job

- **He is someone you look after.** His aura (`OttoAura`, built) rises with
  every day you meditate and sinks when you miss days, with one rest day a
  week free. Low, Frustrated, Curious, Progressing, In flow, Enlightened.
- **He keeps you accountable without nagging.** Chill but convincing. He
  asks, he never scolds, and he never tells you what you lack (the copy rules
  in CLAUDE.md still bind: state the positive, no em dashes, no invented
  numbers about the person).
- **He lives on Home** (built): centred in the valley, his line in a bubble,
  the streak in the corner, the guide in a circle under it.

## Block: the feature

### Where it lives

The Guide tab becomes **Block**. The guide moved to a circle under the streak
on Home (built 2026-09-21). Tabs: Home, Block, the plus, Friends, Profile.

### The loop

1. You set a blocker: which days, which window, which apps.
2. Inside the window, until you have meditated that day, those apps are held.
3. You open one. Apple's shield covers it: Otto's face, "Otto's holding this
   one", and a button, "Ask Otto".
4. Tapping it sends a notification ("Otto wants a word"), because a shield is
   not allowed to open an app. You tap the notification and 808 opens.
5. Otto meets you with one of about twenty interventions (below). Every one
   ends in the same two doors:
   - **"Okay, let's meditate"**: the sit starts. Finishing it (even a short
     one) releases the apps for the rest of the window, and feeds Otto.
   - **"Not now"**: Otto asks how long, 5, 10, 15, 30 or 60 minutes, and the
     apps open for that long. Then they are held again.

### What you can set (per blocker)

1. **How often:** which days it runs (every day, weekdays, custom).
2. **When:** the window (6 to 10 in the morning, 9 to midnight, anything).
3. **Which apps:** Apple's own picker; apps, categories or websites.
4. **How strict** (added, worth having): *Chill* (one screen, then either
   door), *Firm* (you breathe with Otto for ten seconds before "Not now"
   works), *Strict* (no "Not now": meditate to open).
5. **How many passes** (added): unblocks allowed per day, e.g. three, then
   only meditating opens them.
6. **What counts** (added): the shortest sit that releases the apps, 1, 2, 5
   or 10 minutes.

Presets, like Brainrot's: **Mindful morning** (6 to 10, social apps, the
default), **Wind down** (9 pm to midnight), **Focus hours** (9 to 5,
weekdays), **Daily limit** (30 minutes a day, then held until you sit).

### The interventions (about twenty, rotated, never the same twice running)

Each is one screen in 808 after the notification. Some read the moment
(morning, night, streak, Otto's mood, a friend):

1. **Otto standing**, one line in his bubble: "Got two minutes for me first?"
2. **A text thread**: "yo it's otto" / "quick sit before the scroll?" with
   reply chips, typing dots and all.
3. **A FaceTime call**: Otto calling, full screen, accept and decline.
   Accept shows your front camera with Otto in the corner and his lines.
4. **Breathe with me**: one breath together before the choice.
5. **A voice note**: Otto left you one, waveform and transcript.
6. **A note on the fridge**: "Sit first, scroll after. O."
7. **Still there later**: "It will all still be here in two minutes."
8. **Waking Otto** (morning): "zzz... oh, hey. Morning sit?"
9. **Otto's sign**: he holds up a hand-lettered sign, "Meditate first".
10. **The streak**: "Day 6 is waiting. Two minutes keeps it going."
11. **His glow** (tamagotchi): "Help me glow? One sit today."
12. **Two doors, playful**: "What do you want more right now?" Calm, or the
    scroll.
13. **The countdown**: the app opens in ten, nine... while Otto breathes.
    You can wait it out, or sit instead.
14. **An affirmation** (morning): "I start my day on purpose."
15. **Bedtime** (night): Otto in the moonlight, "Wind down with me?"
16. **A sticker**: Otto sent you a sticker of himself meditating.
17. **The valley**: the scene, Otto waving, "It's quiet out here."
18. **A friend** (Friends on): "Maya already sat today. Join her?"
19. **One minute**: "Just one minute. I'll keep time."
20. **Otto asks why**: "What are you opening it for?" Bored, checking
    something, habit. Then the two doors.

## What Apple allows, and how it is built

- **Screen Time API**: FamilyControls (individual authorization, iOS 16+, we
  target 17), ManagedSettings (the shields), DeviceActivity (the schedules).
- **Three app extensions** beside the app: a DeviceActivity monitor (turns
  shields on and off on the schedule), a shield configuration (Otto's face and
  the words on the shield), and a shield action (the "Ask Otto" button, which
  posts the notification). They share state with the app through an App Group
  (`group.com.lockout.meditate808`): "meditated today", "open until".
- **The shield's limits**: an icon, a title, a subtitle, two buttons and
  colours. Nothing else. So the twenty interventions live in the app, reached
  through the notification, exactly as Brainrot does it ("Notification sent.
  Tap the notification above.").
- **Short unblocks**: a DeviceActivity schedule must span at least 15
  minutes. A 5-minute pass is done by starting the interval in the past so it
  ends 5 minutes from now. To be verified on a device.
- **Time Sensitive notifications** need their own entitlement, so the "Otto
  wants a word" notification breaks through Focus.
- **Nothing leaves the phone.** App choices are opaque tokens even to us.
  The privacy policy, the App Privacy labels and the review notes must say
  808 uses Screen Time to hold apps the person chose.
- **GATE, and it is Melvin's or Aziz's to start now:** the Family Controls
  entitlement for App Store distribution must be requested from Apple
  (developer.apple.com, contact, "Family Controls (Distribution)"), for the
  app and each extension. Approval takes days to weeks. Development builds
  work on a phone without it; nothing ships without it.
- **The simulator cannot show shields.** Block is tested on a phone.

## What else has to change

- `PURPOSE.md` and `SCIENCE.md`: lead with consistency and Otto; the
  measurement becomes one of the things 808 does.
- The website hero, the App Store description, keywords and screenshots.
- Otto's lines on Home, notification copy, the Ready screen.
- Onboarding, if it comes back: ask when you want to meditate and which apps
  to hold, then meet Otto.

## More ideas for consistency, most promising first

1. **Otto on the Home Screen and Lock Screen** (widgets): his mood where you
   look eighty times a day. The strongest tamagotchi move there is.
2. **Mindful morning as the default blocker**, on for new people: the first
   scroll waits for the first sit.
3. **Bedtime tied to iOS Sleep**: the wind-down window follows the Sleep
   schedule instead of a time typed in.
4. **Sitting earns time**: a 10-minute sit opens the apps until the window
   ends; a 2-minute sit opens them for an hour.
5. **A Live Activity during the window**: "A two minute sit opens your apps"
   on the Lock Screen and Dynamic Island.
6. **An accountability friend** (Friends): opt in, and a friend sees when your
   Otto is low and can nudge you.
7. **A weekly letter from Otto**: what the week looked like, in his voice.
8. **Tiny sits count**: one minute releases the apps on Chill.
9. **Reminders at the moment you usually first unlock**, not at a fixed time.

## Open questions

1. Does meditating release the apps for the rest of the window, or the rest
   of the day?
2. Should "Not now" cost Otto anything (a little aura), or only meditating
   and missing days move him?
3. Strict mode: offered, or too much for a first version?
4. Is Block part of the free app, or paid (Brainrot charges for it)?
5. Default blocker for new people: Mindful morning on by default, or off
   until they set it up?
