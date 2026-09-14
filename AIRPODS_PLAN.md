# AirPods as the heart-rate source: the no-Watch session

Research and spike, 2026-09-14, branch `airpods`. Answers the BACKLOG.md item
"AirPods as the heart-rate source" (Melvin's friend, 2026-09-12).

## Verdict: feasible with caveats, on iOS 26

A third-party iPhone app can receive live heart-rate samples from AirPods
Pro 3 and Powerbeats Pro 2 with no Apple Watch, by running its own workout
session on the iPhone. Apple documents every link in that chain except two:
the sample cadence, and whether samples keep arriving while the phone is
locked with our app in the background. Both are measured by the probe below,
not assumed. Head motion is documented and cheap; breathing from head motion
has peer-reviewed support only for a still head, at roughly 2 breaths/min
error, so it is a hypothesis to test, not a feature to promise.

## Part 1a: the API path (dated, sourced)

- iOS 26 brings `HKWorkoutSession`, `HKLiveWorkoutBuilder` and
  `HKLiveWorkoutDataSource` to iPhone and iPad. Apple: "If you're already
  running workouts in an app on Apple Watch, you'll be able to use the same
  code on iPhone and iPad with only minimal changes." (WWDC25 session 322,
  "Track workouts with HealthKit on iOS and iPadOS", June 2025,
  developer.apple.com/videos/play/wwdc2025/322/)
- Availability confirmed in the API reference, fetched 2026-09-14:
  `HKWorkoutSession.init(healthStore:configuration:)` iOS 26.0+,
  `HKLiveWorkoutBuilder` iOS 26.0+ (developer.apple.com/documentation/healthkit).
  This is a real iPhone-side session, not the Watch-to-phone mirroring API
  that existed since iOS 17.
- Heart rate on iPhone comes from a paired sensor. Apple: "these devices don't
  contain a heart rate sensor. But you can pair them with any device that you
  wear during a workout that supports the heart rate GATT profile, like a
  wearable heart rate monitor or the Powerbeats Pro 2 ... Once a device is
  paired, HealthKit will handle getting heart rate data from the device and
  saving it as samples to the Health Store, making it available to your app."
  (WWDC25 session 322.) The `HKWorkoutSession` reference says the same:
  "Collecting heart rate data on iPhone or iPad requires pairing with an
  external heart rate sensor" (fetched 2026-09-14).
- AirPods Pro 3 are covered by Apple's support pages rather than the WWDC
  talk, which predates them: "When you use a third-party workout app for the
  first time, give permission for the workout app to read heart rate data,
  and to read and record workouts", and "AirPods Pro 3 measure your heart rate
  continuously during the workout" (Apple Support, AirPods User Guide,
  "Track your heart rate during workouts with AirPods Pro 3", and HT article
  123184, both fetched 2026-09-14). The Beats guide says the same for
  Powerbeats Pro 2 and states it applies to iOS 26 or later (Apple Support,
  Beats User Guide, "Monitor your heart rate with Powerbeats Pro 2", fetched
  2026-09-14). Named third-party adopters: Nike Run Club, Peloton, Runna,
  Ladder (Engadget, 2025-09-29).
- Samples reach the app two ways, both used by the probe: the builder's
  `HKLiveWorkoutBuilderDelegate.workoutBuilder(_:didCollectDataOf:)` with
  `statistics(for: heartRate)` (WWDC25 session 322, and the Watch's existing
  `WorkoutManager`), and an `HKAnchoredObjectQuery` on `heartRate` from the
  session start, which delivers every sample with its source device name.
  No `HKObserverQuery` is needed while the app is running; the user does not
  need Apple's Fitness app.
- Cadence: Apple says "continuously" and publishes no interval (support pages
  above). The Newsroom release describes the sensor as PPG "pulsed at 256
  times per second" fused with the buds' accelerometer and gyroscope and an
  on-device model on iPhone (Apple Newsroom, 2025-09-09). The interval at
  which HealthKit writes samples is what the probe's `t,bpm` CSV measures.
  Do not write "every 5 seconds" anywhere until it is measured.
- Background: Apple says "your iPhone will most likely lock while a workout is
  running" and that on the first session "the system will show a prompt
  indicating that workout data will be available to your app, even while the
  device is locked" (WWDC25 session 322). Crash recovery uses a scene-delegate
  option. Neither source says whether a backgrounded third-party app keeps
  receiving samples; a third-party write-up notes locked-phone collection
  "require[s] explicit configuration" (blakecrosley.com, 2026-05-03). Hardware
  test item 6 below. The probe keeps the screen awake for the first captures.
- HRV is not available from the buds: "AirPods Pro 3 doesn't generate HRV
  samples as of today; it only generates heart rate samples" (Apple DTS,
  Developer Forums thread 805536, October 2025). Consistent with the
  "Why not heart coherence" verdict in CLAUDE.md; nothing changes there.
- AirPods Pro 3 do not broadcast the Bluetooth heart-rate profile, unlike
  Powerbeats Pro 2, so HealthKit is the only route (DC Rainmaker, 2025-09-15).

## Part 1b: when the sensor runs, which workouts

- The sensor is on by default and measures during workouts started in the
  Fitness app, Apple Fitness+, or a third-party workout app (Apple Support
  123184 and the AirPods User Guide, fetched 2026-09-14). Apple's spec sheet
  calls it a "Heart rate sensor for workouts" (apple.com/airpods-pro/specs,
  fetched 2026-09-14). A spot reading is also possible from the Health app or
  Siri (Engadget, 2025-09-29). Users can switch it off in Settings > AirPods >
  Heart Rate (same source).
- Workout types: Apple says "all workout activity types are available on
  iPhone and iPad" (WWDC25 session 322) and the Fitness app offers "up to 50
  different workout types" with the buds (Apple Newsroom, 2025-09-09). No
  Apple source restricts heart-rate sensing by activity type, and none names
  `.mindAndBody`. The probe uses `.mindAndBody` because that is what the
  Watch uses; whether the buds' sensor engages for it is hardware test item 1.
- With a Watch also worn, "the highest-confidence source in the moment is
  automatically used" (Apple Support, both guides). DC Rainmaker describes
  the fusion as a rolling selection (2025-09-15). The probe's source column
  shows which device wrote each sample.

## Part 1c: head motion, and whether it carries a breath

- `CMHeadphoneMotionManager` (iOS 14+) streams `CMDeviceMotion` (attitude,
  user acceleration, rotation rate) "from audio products that support spatial
  audio with dynamic head tracking, like AirPods Pro" (WWDC23 session 10179,
  June 2023). Automatic Ear Detection raises disconnect and connect events
  when a bud leaves or re-enters the ear (same session). The API reference
  requires `NSMotionUsageDescription` and states the app crashes without it
  (developer.apple.com/documentation/coremotion/cmheadphonemotionmanager,
  fetched 2026-09-14).
- AirPods Pro 3 list "Personalized Spatial Audio with dynamic head tracking"
  and a "Motion-detecting accelerometer" (Apple tech specs, fetched
  2026-09-14), so they qualify. Powerbeats Pro 2 advertise the same spatial
  audio with dynamic head tracking (beatsbydre.com product page, fetched
  2026-09-14). Apple publishes no per-model list for this API; the probe's
  "Available" line is the ground truth for a given pair.
- Rate: Apple documents none. Developers report "around 25 Hz" (Anand
  Chowdhary, 2025-09-29; the tukuyo AirPodsPro-Motion-Sampler project lists
  AirPods Pro 1 and 2, AirPods Max, AirPods 3, Beats Fit Pro). 25 Hz is ample
  for breathing (0.05 to 0.5 Hz) and the probe measures the true rate.
- Breathing from an in-ear IMU is published, for a still head only:
  - Roddiger et al., "Towards Respiration Rate Monitoring Using an In-Ear
    Headphone Inertial Measurement Unit", EarComp 2019 (ACM, DOI
    10.1145/3345615.3361130): 12 participants, 50 Hz IMU, 20 s windows, mean
    absolute error 2.62 breaths/min (accelerometer) and 2.55 (gyroscope),
    with movement windows discarded.
  - Ahmed et al., "Remote Breathing Rate Tracking in Stationary Position
    Using the Motion and Acoustic Sensors of Earables", CHI 2023 (DOI
    10.1145/3544548.3581265): 30 participants, MAE under 2 breaths/min,
    keeping 75% of real-world sessions; IMUs work "only under stationary
    conditions by discarding data from periods with motions".
  - Liu et al., "RespEar", 2024 (arXiv 2407.06901): reaches 1.48 breaths/min
    sedentary, but with the in-ear microphone, not the IMU; it describes the
    IMU breathing signal as "almost imperceptible" under daily activity.
  - Apple's own 2021 work estimated respiratory rate from AirPods audio, not
    motion (MacRumors, 2021-08-12).
  Reading: stillness from head motion is straightforward. A breath curve is
  plausible for a seated, still meditator doing deliberate slow breathing,
  which is exactly the regime the wrist engine already scores (doorway rule,
  CLAUDE.md), and unproven for anything else. The probe's motion CSV is the
  evidence that decides it; do not design UI for head-breath before then.

## Part 1d: privacy, PrivacyInfo, App Review

- Today the iOS target holds HealthKit authorization and queries nothing
  (`HealthScope`, CLAUDE.md). An AirPods session makes the phone read heart
  rate for the first time. What changes if it ships:
  - `PRIVACY_POLICY.md` and `website/privacy.html`: every sentence that says
    the Watch measures heart rate ("your Apple Watch measures your heart
    rate", "Source: the sensors of your own Apple Watch") gains AirPods Pro 3
    and Powerbeats Pro 2 via Apple HealthKit. The scope bullet is unchanged
    (heart rate, HRV SDNN, workouts, mindful minutes).
  - `Coherence/Info.plist`: `NSHealthShareUsageDescription` and
    `NSHealthUpdateUsageDescription` currently say "recorded on your Apple
    Watch"; both must name the buds. `NSMotionUsageDescription` must be
    added to the iOS app. Any Info.plist or entitlement change forces a fresh
    App Review pass (usage strings are reviewed) and re-enters Beta App
    Review on TestFlight (CLAUDE.md, TestFlight section).
  - `PrivacyInfo.xcprivacy`: no change. Apple's "collected" means transmitted
    off device; heart rate still never leaves the phone. App Privacy labels
    stay as they are.
  - 5.1.3 posture: unchanged and still true. Results are computed on device,
    `MeditationStats` stays in the device-local store, no server, no AI
    service, analytics carry names only and never a biometric.
  - `HealthScopeTests.test_theiOSTargetQueriesNoHealthData` now exempts
    `Coherence/AirPods/` on the condition that every file there opens with
    `#if DEBUG` and closes with `#endif`. Shipping the path means rewriting
    that test's promise deliberately, not deleting it.
  - The onboarding Watch gate only requests the Health scope for people who
    say they have a Watch (`OnboardingView`); the AirPods path needs its own
    request. Onboarding is another agent's area today; noted, not touched.

## Proposed session flow (product, not built)

1. Setup sheet gains a source choice when no Watch is paired: "Apple Watch"
   or "AirPods Pro 3 / Powerbeats Pro 2 (iOS 26)". Copy states what is
   needed: both buds in, connected to this iPhone, Heart Rate on in Settings.
2. Begin runs an iPhone-side `.mindAndBody` `HKWorkoutSession` with a live
   builder, exactly as the probe does, plus `CMHeadphoneMotionManager`.
   Audio keeps playing phone-side as today. The phone is the recorder, the
   analyser and the persister; no WatchConnectivity.
3. End stops the session (stopActivity, endCollection, finishWorkout) and
   runs `SignalEngine.analyze` on head motion (stillness from user
   acceleration; breathing only if the captures justify it) and the HR
   samples. Results reuse the existing screen and tiles; the source is
   recorded on the Session so history stays honest about what measured it.

Score split proposal: heart 0.60 / stillness 0.40, the engine's documented
no-breath split (CLAUDE.md, v5.0.0), with breath absent until head-breath is
validated. Stillness from head motion needs its own calibration of the
`[0.80, 0.98]` rescale, since a head and a wrist do not move alike; the
weights should not move before that.

## Part 2: the spike (built, DEBUG only)

- `Coherence/AirPods/AirPodsProbe.swift` and `AirPodsProbeView.swift`, both
  wrapped in `#if DEBUG`, gated `@available(iOS 26.0, *)`. Reached from
  Settings > "AirPods (debug)" > "AirPods capture probe" (the row exists only
  on iOS 26). Start asks `HealthScope`, starts the workout, subscribes to
  heart rate (builder delegate plus anchored query) and headphone motion,
  shows phase, elapsed, HR sample count, last bpm, source name, gap between
  samples, builder bpm, motion availability, authorization, connection,
  sample count and rate in Hz. Writes every 30 s and at Stop:
  `Documents/AirPodsCaptures/airpods-<id>-hr.csv` (`t,bpm`, seconds since
  start), `airpods-<id>-motion.csv` (`t,pitch,roll,yaw,ax,ay,az`), and
  `airpods-<id>-meta.txt` (start time, device, sources seen, counts).
  The workout is discarded at Stop so no probe run appears in Health.
- `NSMotionUsageDescription` reaches ONLY Debug builds: a post-build script
  in `project.yml` (`postBuildScripts` on target Coherence) writes it into
  the built Info.plist with PlistBuddy when `CONFIGURATION` is Debug, ordered
  after Xcode's plist processing by declaring that plist as its input.
  (`INFOPLIST_KEY_*` settings are ignored while `GENERATE_INFOPLIST_FILE` is
  NO; tried first.) Verified on the built products: the Debug plist carries
  the string, the Release plist and binary carry nothing of the probe.
  `Coherence/Info.plist` is unchanged, so nothing here re-enters App Review.
  No entitlement was added: the iOS target already holds HealthKit.
- Build: `xcodebuild -scheme Coherence -destination 'platform=iOS
  Simulator,name=iPhone 17' build` succeeds; the test suite passes with the
  `HealthScopeTests` exemption above.

## What a human must test on real hardware

Melvin, an iPhone on iOS 26, AirPods Pro 3 (or Powerbeats Pro 2). Debug
build over the cable (`CURRENT_PROJECT_VERSION=$(date -u +%Y%m%d%H%M)` so
the Watch companion is not downgraded, per CLAUDE.md).

1. Both buds in, connected to the iPhone, Settings > AirPods > Heart Rate on.
   Settings > AirPods (debug) > AirPods capture probe > Start capture. Accept
   the Health prompt (heart rate read, workouts read and write), the motion
   prompt, and the system's "workout data while locked" prompt if shown.
   Pass: HR sample count climbs within a minute, Source reads the buds'
   name, Motion rate reads roughly 25 Hz. This answers whether the sensor
   engages for `.mindAndBody`.
2. Sit still 3 minutes breathing naturally, then 2 minutes at about 6/min
   counting breaths and noting the clock, then 1 minute turning the head.
   Stop. Note the counted rates and times in the capture's meta file name.
3. Read the Gap line during the run and the `t` column afterwards: that is
   the cadence. Record it in BACKLOG.md.
4. One bud only, both orders. Does HR continue, does motion switch buds.
5. Wear the Watch as well: which source name wins, and does the count double.
6. Lock the phone for 2 minutes mid-capture, unlock, Stop. Compare the
   sample timestamps across the locked span for both CSVs. Then repeat with
   808 sent to the background behind another app playing audio.
7. Pull the files: `xcrun devicectl device copy from --domain-type
   appDataContainer --domain-identifier com.lockout.meditate808 --source
   Documents/AirPodsCaptures --destination ~/Desktop/captures/airpods
   --device <udid>` (or AirDrop from the Files app). Captures stay out of
   the repo, like the wrist captures.
8. Offline: histogram the HR gaps; run the motion CSV through a copy of
   `tools/breath_probe.py` adapted to 25 Hz and the head's gravity frame,
   against the counted rates from step 2. That result decides whether
   head-breath is pursued.
