# 808 for Garmin (Connect IQ watch app)

The design record is `../GARMIN.md`. Read it first: it carries the five
platform facts that decided this shape, and the architecture rule it breaks
on purpose.

**NEVER COMPILED.** The Connect IQ SDK is not on this machine, so no line
here has passed a type checker. Expect the first build to fail on small
things: an enum name (`Activity.SPORT_MEDITATION` and `SUB_SPORT_BREATHING`
are the likeliest), a product id in `manifest.xml`, or an access modifier.
The SHAPE is the deliverable; the syntax is a first draft.

## What it does

Samples the accelerometer at 25 Hz, estimates gravity with a slow exponential
average, and from that derives the two things Apple hands us for free and
Garmin does not: where the wrist is pointing (pitch and roll, for breathing)
and what the body did with gravity removed (the residual, for stillness).
Bins to 5 Hz, batches every 4 seconds, sends to the iPhone over BLE. The
phone runs `SignalEngine` unchanged, so a Garmin sit is scored by the same
code as a Watch sit and sits in the same history.

## Build, once the SDK exists

    # 1. A JDK must be on PATH before /usr/bin (Apple Silicon needs this)
    java -version

    # 2. SDK Manager > download the current SDK > accept as active, then
    export PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/<current>/bin:$PATH"

    # 3. A developer key, once
    openssl genrsa -out /tmp/808.pem 4096
    openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/808.pem -out ~/.garmin/808_developer_key.der -nocrypt

    # 4. Build for one device
    monkeyc -f monkey.jungle -d fr265 -o bin/808.prg -y ~/.garmin/808_developer_key.der

    # 5. Run it in the simulator
    connectiq && monkeydo bin/808.prg fr265

The simulator is enough to develop against; nobody on the team owns a Garmin
watch yet, and until one exists every result is a simulator result and must
be labelled as one.

## Files

- `source/Capture.mc` the reduction. The only file with ideas in it.
- `source/Bridge.mc` one batch out every 4 s; drops rather than queues.
- `source/SessionView.mc` elapsed time and whether the phone is listening.
- `source/SessionDelegate.mc` start and stop.
- `source/EightZeroEightApp.mc` entry, and the stop that must fire on exit.
- `manifest.xml` app id is a PLACEHOLDER (see the comment in the file).
- `resources/drawables/launcher_icon.png` hand-generated placeholder.

## Not built yet

The iPhone half: `GarminBridge` (needs the ConnectIQ Swift package added in
Xcode), the device picker, `FeatureFlags.garmin`, and tests pinning the
reduction against what `SignalEngine` expects to receive.
