# 808 for Garmin (Connect IQ watch app)

The design record is `../GARMIN.md`. Read it first: it carries the five
platform facts that decided this shape, and the architecture rule it breaks
on purpose.

**Status 2026-09-18: builds clean for all thirteen devices in the manifest,
and nine unit tests pass in the simulator.** Never run on real hardware,
because nobody on the team owns a Garmin watch; treat every number as a
simulator number until one does.

## What it does

Samples the accelerometer at 25 Hz, estimates gravity with a slow exponential
average, and from that derives the two things Apple hands us for free and
Garmin does not: where the wrist is pointing (pitch and roll, for breathing)
and what the body did with gravity removed (the residual, for stillness).
Bins to 5 Hz, batches every 4 seconds, sends to the iPhone over BLE. The
phone runs `SignalEngine` unchanged, so a Garmin sit is scored by the same
code as a Watch sit and sits in the same history.

## Build and test (these commands were run, they work)

    export PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin:$PATH"

    # Build for one device. Every id in manifest.xml works.
    monkeyc -f monkey.jungle -d vivoactive5 -o bin/808.prg \
            -y ~/.garmin/808_developer_key.der

    # Tests: build with --unit-test, run with -t. The simulator must be up
    # (`connectiq &`), and the results print to stdout.
    monkeyc -f monkey.jungle -d vivoactive5 -o bin/808_test.prg \
            -y ~/.garmin/808_developer_key.der --unit-test
    monkeydo bin/808_test.prg vivoactive5 -t

A device can only be targeted if it is BOTH in `manifest.xml` AND installed
in SDK Manager. Only the fenix and vivoactive families are installed here,
which is why no Forerunner or Venu is listed.

`~/.garmin/808_developer_key.der` **is worth backing up**: a published
Connect IQ app is tied to it, and losing it means never updating that app.
Never commit it.

## Files

- `source/Reducer.mc` the arithmetic. The only file with ideas in it.
- `source/ReducerTests.mc` nine tests, stripped from non-test builds.
- `source/Capture.mc` sensors, the activity session, the 4 s batch.
- `source/Bridge.mc` one batch out every 4 s; drops rather than queues.
- `source/SessionView.mc` elapsed time and whether the phone is listening.
- `source/SessionDelegate.mc` start and stop.
- `source/EightZeroEightApp.mc` entry, and the stop that must fire on exit.
- `manifest.xml` app id is a PLACEHOLDER (see the comment in the file).
- `resources/drawables/launcher_icon.png` hand-generated placeholder.

## Not built yet

The iPhone half: `GarminBridge` (needs the ConnectIQ Swift package added in
Xcode), the device picker, `FeatureFlags.garmin`, and a test feeding a
reduced stream through `SignalEngine` so a Garmin sit and a Watch sit
provably score the same.
