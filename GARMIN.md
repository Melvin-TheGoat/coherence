# 808 on Garmin

The record for the Garmin path: what the platform actually gives us, the
architecture that follows from it, and what is built. Started 2026-09-18
(Aziz: "lets start building the garmin version as well"). Ranked against the
other wearables in `BACKLOG.md`; Garmin is the only non-Apple watch that can
run our code and talk to an iPhone.

## The five facts that decided everything

Read from Garmin's own docs, not from memory. Each one closed an option.

1. **A watch app gets 28.5 KB to 128 KB of memory** (fenix 5 is 28.5 KB;
   current watches 128 to 256 KB). `SignalEngine` cannot be ported to Monkey
   C. **So the watch reduces and streams; the PHONE analyses.** This inverts
   the Apple architecture and is the single biggest difference.
2. **Accelerometer at up to 25 Hz, in milli-g, as arrays** delivered per
   callback with a period of up to 4 seconds
   (`Sensor.registerSensorDataListener`). Plenty: the breathing band tops out
   at 0.5 Hz.
3. **There is no fused attitude.** Apple hands us `CMDeviceMotion.attitude`
   (pitch and roll from a sensor-fusion estimate of gravity); Garmin hands us
   raw acceleration only. **We derive gravity ourselves** with a slow
   exponential average, which is legitimate here precisely because the user
   is sitting still: at rest the accelerometer vector IS gravity. Pitch and
   roll then fall out by arctangent, and the residual (sample minus gravity)
   is the same quantity `userAcceleration` gives us for stillness.
4. **Beat-to-beat intervals are available** (`heartBeatIntervals`, an array
   of milliseconds). **This is something the Apple Watch has never given a
   third-party app** (see CLAUDE.md "Why not heart coherence"). Real HRV, and
   eventually real coherence, is reachable on Garmin and is not reachable on
   the hardware 808 ships on today. Do not build on it in v1, but do not
   forget it: it is the reason this platform might one day carry the Pro tier.
5. **The iOS companion talks to the watch directly over BLE** (the SDK wraps
   `CBCentralManager`); Garmin Connect Mobile is needed **only** to discover
   and hand over the paired devices the first time, through a URL-scheme
   round trip. After that GCM is not in the path. **But the watch cannot
   launch the iPhone app.** A Garmin-started session only reaches 808 if 808
   is already running or backgrounded, so the Apple Watch's watch-initiated
   sessions have no equal here in v1. Sessions start on the phone.

Two smaller ones that will bite if forgotten: sensors return null on real
hardware until an **ActivityRecording session** is running (works fine in the
simulator, which is how people lose an afternoon), and the SDK **requires**
`CFBundleDisplayName` or device selection fails silently.

## The architecture

    Garmin watch (Monkey C)                  iPhone (808)
    25 Hz accel + RR intervals
      -> gravity EMA -> pitch, roll
      -> residual magnitude
      -> 5 Hz triples, binned
      -> batch every 4 s  --BLE-->  GarminBridge -> SessionCoordinator
                                      -> SignalEngine.analyze (unchanged)
                                      -> MeditationStats, the same score

**The phone runs the engine.** Every rule about windows, gates, the doorway
and the score is untouched: the samples arrive in the same shape
`SignalEngine` already consumes, so a Garmin sit and an Apple Watch sit are
scored by the same code and are comparable in the same history. That is the
whole point, and it is why the reduction happens on the watch rather than
sending raw 25 Hz.

**Volume.** 25 Hz x 3 axes for 20 minutes is 90,000 numbers, which is far
too much for a BLE message queue Garmin asks us to keep small. Binned to
5 Hz triples it is 18,000, batched 20 triples to a message every 4 seconds.
The breathing band is 0.05 to 0.5 Hz, so 5 Hz is four times Nyquist with
room to spare, and stillness survives because the bin carries the RMS of the
residual rather than a sample of it.

**Units on the wire are integers**: milliradians for pitch and roll,
milli-g for the residual, milliseconds for RR. Smaller messages, no float
formatting, and the phone scales once.

**A dropped batch is a gap, not a failure.** If the phone is unreachable the
watch drops the batch and counts it; `SignalEngine` already skips windows
with too few samples (the camera path taught us the same lesson about
dropped frames). v1 assumes the phone is nearby, which it is: the audio
plays there.

### The architecture rule this breaks, deliberately

CLAUDE.md says "all sensor / HealthKit / CoreMotion code lives in the Watch
target only" and "the phone reads zero biometric data". On Garmin the phone
must do the analysis, because 28.5 KB cannot hold the engine. The rule's
REASON was App Review 5.1.3, which governs HealthKit data; Garmin samples
never touch HealthKit, so 5.1.3 does not bind them. What does follow:

- The privacy policy, both copies, gains a paragraph: what the Garmin watch
  sends, that it stays on the phone, that it is stored device-local exactly
  as Watch results are.
- `NSBluetoothAlwaysUsageDescription` and the `bluetooth-central` background
  mode are new Info.plist and entitlement changes, so the build carrying
  Garmin **re-enters Beta App Review**. That goes on RELEASE_CHECKLIST.md the
  day the flag is flipped, not after.
- Writing the session as an `HKWorkout` is still correct and still done on
  the phone: it is the user's own record, and it is how a Garmin sit lands in
  Health beside the Apple Watch ones.

## What is built (2026-09-18)

`GarminWatch/`, the Monkey C app. **Never compiled**: the Connect IQ SDK is
not on this machine (see Setup below), so treat every line as a first draft
that has passed nobody's type checker.

- `source/EightZeroEightApp.mc` the app entry, holds the capture.
- `source/Capture.mc` the whole idea: gravity EMA, pitch/roll, residual,
  0.2 s bins, 4 s batches, RR collection, the activity session that keeps
  the sensors alive.
- `source/Bridge.mc` `Communications.transmit` with a listener that counts
  drops rather than retrying (memory).
- `source/SessionView.mc` / `SessionDelegate.mc` elapsed time, a start and
  an end, nothing else. No haptics: the Watch's no-haptics rule is a product
  rule, not an Apple one, and it applies here.
- `manifest.xml`, `monkey.jungle`, `resources/`.

Not built yet, in order: the iOS `GarminBridge` (needs the SDK package added
in Xcode), the device-picker screen, `FeatureFlags.garmin`, and the tests
that pin the reduction against `SignalEngine`'s expectations.

## Setup, and the parts only Aziz or Melvin can do

1. **A Garmin developer account** (free) at developer.garmin.com. Claude does
   not create accounts.
2. **Install a JDK.** `java -version` on this Mac says no runtime. Monkey C's
   compiler needs one, and on Apple Silicon the JDK's `bin` must precede
   `/usr/bin` on PATH or `monkeyc` reports it cannot find Java.
3. **Install the Connect IQ SDK Manager**, download the current SDK, accept
   it as active, and add its `bin` to PATH. The simulator comes with it, and
   the simulator is enough to develop against: **we do not need to own a
   Garmin watch to build this**, only to trust it.
4. **A watch to verify on, eventually.** Nobody on the team owns one. The
   cheapest device that exercises everything we use (25 Hz accel, RR
   intervals, Connect IQ apps) is a current Forerunner or Venu; a fenix is
   not needed. Until one exists, every result is a simulator result and must
   be labelled as such, the same discipline the camera work uses.
5. **An app UUID** is generated when the app is registered in the Connect IQ
   store; the iOS side needs it, and the store listing is a separate review
   from Apple's.

## Open questions, not yet decided

- **Does a Garmin session need its own onboarding branch?** The Watch gate
  asks "do you have an Apple Watch". A third answer changes the funnel and
  the waitlist, and that is a Melvin and Aziz decision, not a build.
- **RR intervals: show them, score them, or ignore them?** They are the one
  thing Garmin does better than Apple. Ignoring them in v1 keeps every
  session comparable; using them creates two classes of history. The
  comparability rule says ignore for now, and revisit as a Pro tier.
- **Store presence.** A Connect IQ store listing is free marketing to exactly
  the audience that owns the hardware, and it is also a second review queue
  and a second support surface.
