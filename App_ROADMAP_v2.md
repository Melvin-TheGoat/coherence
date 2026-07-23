# Coherence — v1 Development Roadmap (v2)

Motion-based guided-meditation app · iPhone + Apple Watch · Swift / SwiftUI / SwiftData / HealthKit / CoreMotion
Execution model: instructions pasted into **Claude Code in a terminal** (no IDE integration). Project defined via **XcodeGen** so Claude Code can edit `project.yml` and regenerate the `.xcodeproj` with one command.

**Pivot (post-Phase-2):** heart coherence proved impossible on Apple Watch for a third-party app (no beat-to-beat RR; verified on-device — see CLAUDE.md "Why not heart coherence"). The product now proves a session landed with **three motion/heart signals**: **stillness** (accelerometer), **heart-rate deceleration** (~5 s averaged HR trend), and **belly breathing** (optional — `CMDeviceMotion` gravity-tilt recovers the ~0.1 Hz breathing waveform directly). Regular sessions = 2 signals (stillness + HR); belly sessions add breathing. Phases 2–6 below reflect this; Phases 0/1 are already built and reused.

**Other decisions:** Sign in with Apple only (Google + email/password deferred); CloudKit deferred from Phase 0 to Phase 7; explicit pre-account user handling; multi-user **sharing is deferred to a future phase** (CloudKit public/`CKShare` vs. backend is an open decision — do not build it in these phases); calendar day-tap opens that day's Meditation Logged.

---

## Architecture decisions baked into this plan (read once, do not relitigate)

- **The phone is the only persistence layer.** SwiftData lives on iOS. The Watch holds **no** store; it captures heartbeat data, computes stats, and ships the result to the phone over WatchConnectivity. The phone performs every write. "One writer per object" is preserved as a *logical* rule (the Watch is the logical author of heartbeat data; the physical write happens on the phone when the payload lands).
- **Phone-triggered start = `HKHealthStore.startWatchApp(with:)`.** You cannot launch a watchOS app from the phone via WatchConnectivity. `startWatchApp` is the supported mechanism. Therefore the **iOS target carries the HealthKit entitlement + usage strings to issue the launch command only** — it reads zero biometric data. All heartbeat *logic* stays on the Watch.
- **Foreign keys are stored as plain `UUID` properties, not SwiftData `@Relationship`.** Matches the ERD, honors "screens read independently," and avoids CloudKit relationship-optionality constraints.
- **CloudKit compatibility is non-negotiable in every model** *even before CloudKit is switched on*: no `@Attribute(.unique)`, no non-optional relationships, every stored property optional or defaulted. Uniqueness (one Stats/session, one User/appleUserID) is enforced in code, never in schema. CloudKit itself is enabled in Phase 7 — the models are built for it from Phase 0 so the flip is a one-line change.
- **Auth is Sign in with Apple only in v1.** No passwords, no Google. Apple handles verification, resets, and credential storage; this removes `auth_provider`, `provider_user_id`, `password_hash`, and `email_verified` from the User model, and removes the cross-provider account-collision problem entirely. Additive to re-add later.
- **Timed sessions are clocked by the Watch** (it fires the authoritative end-haptic). The phone runs a parallel timer only to stop audio. Open-ended sessions end from a Watch button.
- **All three signals are analyzed with overlapping sliding windows.** Each per-window metric (breathing rate, stillness, HR) is computed on a `windowSec` window advancing by a small `hopSec` (5 s), producing smooth curves instead of one point per minute. The three resampled timeseries share one `windowSec`, one `hopSec`, and one index/length. Both are stored on every result so old sessions remain interpretable after the parameters change. (`windowSec` default 30 s — enough to estimate a slow breathing rate; the old 60 s coherence constraint is gone.)
- **The Watch captures motion, not just heart.** The `HKWorkoutSession` (`.mindAndBody`) exists to keep the app foregrounded and stream averaged HR; `CMDeviceMotion` (gravity-tilt pitch + userAcceleration, 10–25 Hz) is the primary signal source. HealthKit scope shrinks to HR read + workout share; CoreMotion needs `NSMotionUsageDescription`.

**HARD GATE:** Phase 0 runs on a free Apple ID with a **local** (non-CloudKit) store. **Phase 1 onward requires the paid Apple Developer Program ($99/yr)** — HealthKit on device, CloudKit, and Sign in with Apple are unavailable under free provisioning. Buy it before starting Phase 1.

**Bundle IDs used throughout (change the prefix once, here, if you want):**
- iOS app: `com.lockout.coherence`
- Watch app: `com.lockout.coherence.watchkitapp`
- iCloud container: `iCloud.com.lockout.coherence`

---

# Phase 0 — Project skeleton, schema, local store, CLAUDE.md

**GOAL:** A regenerable XcodeGen project with iOS + watchOS targets, all 5 SwiftData models (CloudKit-safe in shape, local in storage), a local ModelContainer on the phone, a central color catalog, and a `CLAUDE.md` that future sessions inherit — building green in the simulator.

### PASTE INTO CLAUDE CODE
```
We are building "Coherence," a heart-coherence meditation app for iPhone + Apple Watch. Set up the project from scratch in the current empty directory. Requirements:

1. Install XcodeGen if absent: `brew install xcodegen`. Verify with `xcodegen --version`.

2. Create this folder layout:
   Coherence/            (iOS app target sources)
   CoherenceWatch/       (watchOS app target sources)
   Shared/               (code compiled into BOTH apps + the test target)
   Shared/Models/        (SwiftData @Model files)
   Shared/Engine/        (pure-Swift signal engine — Phase 3 — plus StreakCalculator; create empty dir now)
   CoherenceTests/       (unit tests)

3. Write `project.yml` defining three targets:
   - "Coherence": iOS application, deploymentTarget iOS 17.0, sources [Coherence, Shared]. It EMBEDS the watch app (dependency on CoherenceWatch, embed: true). PRODUCT_BUNDLE_IDENTIFIER com.lockout.coherence. INFOPLIST_FILE Coherence/Info.plist, CODE_SIGN_ENTITLEMENTS Coherence/Coherence.entitlements, GENERATE_INFOPLIST_FILE NO, SWIFT_VERSION 5.10.
   - "CoherenceWatch": watchOS application, deploymentTarget watchOS 10.0, sources [CoherenceWatch, Shared]. PRODUCT_BUNDLE_IDENTIFIER com.lockout.coherence.watchkitapp, WKCompanionAppBundleIdentifier com.lockout.coherence, INFOPLIST_FILE CoherenceWatch/Info.plist, CODE_SIGN_ENTITLEMENTS CoherenceWatch/CoherenceWatch.entitlements, GENERATE_INFOPLIST_FILE NO.
   - "CoherenceTests": iOS unit-test bundle, host application Coherence, sources [CoherenceTests, Shared].
   Set options.bundleIdPrefix com.lockout, createIntermediateGroups true. Leave DEVELOPMENT_TEAM empty (I set it in Xcode).

4. Create the 5 SwiftData models in Shared/Models/, one file each. EVERY property must be optional OR have a default (CloudKit requirement — we enable CloudKit in Phase 7 and the models must already be compatible). NO @Attribute(.unique) anywhere. Store enums as String with computed enum accessors. Store foreign keys as plain UUID? properties (NOT @Relationship). Exact fields:

   User.swift — id:UUID=UUID(), appleUserID:String="", email:String?, displayName:String?, marketingOptIn:Bool=false, createdAt:Date=Date(), updatedAt:Date=Date(), deletedAt:Date?
   Preferences.swift — id:UUID=UUID(), userID:UUID?, onboardingComplete:Bool=false, defaultDurationSec:Int? (nil=open-ended), remindersEnabled:Bool=false, reminderTime:Date?, theme:String="system", hapticsEnabled:Bool=true, createdAt:Date=Date(), updatedAt:Date=Date()
   MeditationTrack.swift — id:UUID=UUID(), type:String="guided", title:String="", trackDescription:String?, audioURL:String="", durationSec:Int?, sortOrder:Int=0, isActive:Bool=true, createdAt:Date=Date(), updatedAt:Date=Date()
   Session.swift — id:UUID=UUID(), userID:UUID?, trackID:UUID? (nil=silence), mode:String="silence", bellyBreathing:Bool=false, startedAt:Date=Date(), durationSec:Int=0, createdAt:Date=Date(). NO updatedAt — immutable.
   MeditationStats.swift — id:UUID=UUID(), sessionID:UUID?, heartRateTimeseries:[Double]=[], meanHR:Double=0, startHR:Double?, endHR:Double?, hrDecline:Double?, stillnessTimeseries:[Double]=[], stillnessScore:Double?, stillnessMethod:String="total", breathingRateTimeseries:[Double]=[], breathDepthTimeseries:[Double]=[], meanBreathingRate:Double?, breathingRegularity:Double?, resonanceMatchScore:Double?, overallScore:Double?, windowSec:Int=30, hopSec:Int=5, algorithmVersion:String="1.0.0", createdAt:Date=Date(). Immutable.
   NOTE: there is NO HeartbeatSeries model — the coherence/RR path was cut. Breathing fields stay empty/nil for Regular (non-belly) sessions and for belly sessions where the breathing signal couldn't be read. stillnessMethod is "total" (regular) or "breathingExcluded" (belly).

   NOTE: Streak is NOT a stored model — it is derived at read time from Session dates. Instead create Shared/Engine/StreakCalculator.swift (pure Swift, imports Foundation ONLY — no SwiftData/HealthKit/UI):
     func streak(from sessionDates: [Date], today: Date = Date(), calendar: Calendar = .current) -> (current: Int, longest: Int)
   Reduce sessionDates to a Set of local day-starts via calendar.startOfDay. current: anchor = today if present in the set, else yesterday if present, else return current 0; then walk backward from the anchor counting consecutive days present. longest: the maximum run of consecutive calendar days over all unique days. Handle empty input (returns 0, 0). Keep it allocation-light and deterministic.

   NOTE on MeditationStats: windowSec is the analysis window; hopSec is how far it advances between points. The three resampled timeseries (heartRate, stillness, breathingRate) share one index and are always the same length. Both values are stored per-row so a result stays interpretable if the parameters ever change.

   Add String-backed enums (Theme, TrackType, SessionMode) in Shared/Models/Enums.swift with computed accessors on the models.

5. Create Shared/Persistence.swift with THREE ModelContainer factories: (a) `local()` — ModelConfiguration(schema:, isStoredInMemoryOnly:false, cloudKitDatabase:.none), used now; (b) `cloudKit()` — same but cloudKitDatabase:.automatic, written now, NOT called until Phase 7; (c) `inMemory()` for tests/previews. Phase 0 uses local(). Leave a comment saying CloudKit is switched on in Phase 7.

6. Create Coherence/CoherenceApp.swift (iOS @main, SwiftUI App) injecting the LOCAL ModelContainer, showing a placeholder ContentView with the app name. Create CoherenceWatch/CoherenceWatchApp.swift (watchOS @main) with a placeholder view — NO ModelContainer on the watch.

7. Create the color asset catalog Shared/Assets.xcassets with named colors: BackgroundPrimary, BackgroundSecondary, AccentGold, TextPrimary, TextSecondary, each with Any + Dark appearance variants (near-black bg, gold accent, per brand). Add a Swift file Shared/Theme/AppColor.swift exposing them as Color statics. RULE for all future code: never hardcode hex; go through AppColor.

8. Entitlements files:
   Coherence/Coherence.entitlements — LEAVE EMPTY (an empty plist dict) for Phase 0. Free provisioning cannot sign iCloud, Sign in with Apple, or HealthKit entitlements; we add them in Phase 1 and Phase 7. Add a comment file or CLAUDE.md note recording exactly what gets added later:
     Phase 1: com.apple.developer.healthkit true (BOTH targets)
     Phase 7: com.apple.developer.applesignin ["Default"]; com.apple.developer.icloud-container-identifiers ["iCloud.com.lockout.coherence"]; com.apple.developer.icloud-services ["CloudKit"]; aps-environment "development"
   CoherenceWatch/CoherenceWatch.entitlements — also empty for Phase 0.

9. Info.plist files:
   Coherence/Info.plist — NSHealthShareUsageDescription and NSHealthUpdateUsageDescription (short honest strings); UIBackgroundModes ["remote-notification"].
   CoherenceWatch/Info.plist — NSHealthShareUsageDescription, NSHealthUpdateUsageDescription, NSMotionUsageDescription (CoreMotion drives stillness + belly breathing); WKBackgroundModes ["workout-processing"]; WKApplication true.

10. Write CLAUDE.md at repo root capturing: the product ("evidence a practice landed — three motion/heart signals, shown after not during"), the architecture decisions (phone is sole store; Watch is stateless sensor/compute/transfer; startWatchApp for triggering; FKs as UUIDs; CloudKit-safe modeling from day one with CloudKit itself enabled in Phase 7; Apple-only auth; Watch-clocked timing; sliding-window signal analysis with windowSec + hopSec), the full 5-entity schema, the session-end sequence, and the conventions (colors via catalog only; all sensor/HealthKit/CoreMotion code in the Watch target only, except iOS calling startWatchApp; the three timeseries share one windowSec/hopSec and one index; sessions and stats immutable; screens never pass data to screens, only IDs). [NOTE: the current CLAUDE.md already reflects the motion pivot — keep it in sync, don't regress it to coherence.]

11. Regenerate the project: `xcodegen generate`. Then run a headless build of both schemes with xcodebuild to confirm they compile (iOS simulator destination, generic watchOS simulator destination). Fix any compile errors. Do NOT attempt device builds or signing. Add a .gitignore for Xcode/SwiftPM. Init git and make the first commit "Phase 0: project skeleton + schema".
```

### YOU DO MANUALLY
1. Open the generated `Coherence.xcodeproj` in Xcode (`open Coherence.xcodeproj`).
2. Select the **Coherence** target → Signing & Capabilities → set your **Team** (free personal team is fine for Phase 0). Repeat for **CoherenceWatch**.
3. Product → Run on the **iOS Simulator** (iPhone 15).

### HUMAN CHECKPOINT
- ☐ Run `xcodegen generate && xcodebuild -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 15' build`. You should see **BUILD SUCCEEDED**. If you see "No such module 'SwiftData'" the deployment target is below iOS 17 — fix `project.yml`.
- ☐ Run the iOS app in the simulator. You should see the placeholder screen with the app name and gold-on-near-black colors. If the app **crashes on launch** with a ModelContainer error, check in this order: (1) is `Persistence.local()` being used, with `cloudKitDatabase:.none`? A CloudKit container will fail here — you have no paid account and no iCloud entitlement yet. (2) Only after ruling that out: grep the models for a non-optional relationship or a `.unique` attribute.
- ☐ Open `CLAUDE.md`. You should see the full schema and architecture rules written out. If it's thin, tell Claude Code to expand it — every later phase relies on it.

### ROLLBACK
Commit `Phase 0: project skeleton + schema` **before** starting Phase 1. If Phase 1 corrupts the project, `git reset --hard` to here and regenerate.

---

# Phase 1 — Watch: live heart rate on real hardware

**GOAL:** The Watch app starts an `HKWorkoutSession` and displays your live BPM on your wrist.

> Requires the **paid** Apple Developer Program and a Watch paired to your Mac's Xcode.

### PASTE INTO CLAUDE CODE
```
Implement live heart rate on the Watch (CoherenceWatch target ONLY — no HealthKit code touches the iOS target in this phase).

0. Add the HealthKit entitlement to BOTH entitlements files now: com.apple.developer.healthkit true. Regenerate with xcodegen.

1. Create CoherenceWatch/Health/HealthKitAuth.swift: request HealthKit authorization for READ [HKQuantityType(.heartRate), HKSeriesType.heartbeat(), HKObjectType.workoutType()] and SHARE [HKObjectType.workoutType()]. Expose an async authorize() that returns the status.

2. Create CoherenceWatch/Health/WorkoutManager.swift: an ObservableObject that:
   - starts an HKWorkoutSession + HKLiveWorkoutBuilder with HKWorkoutConfiguration(activityType: .mindAndBody, locationType: .unknown),
   - conforms to HKLiveWorkoutBuilderDelegate, and on each .heartRate statistics update publishes the most recent BPM (mostRecentQuantity, unit count/min),
   - exposes start() and end() methods and an @Published currentHR: Double?.

3. Build a minimal CoherenceWatch view: an "Authorize" button (calls authorize), a "Start" button (calls WorkoutManager.start), a large live BPM label bound to currentHR, and an "End" button (calls end). Colors via AppColor only.

4. Do NOT build a timer, haptics, RR-interval readback, or any persistence yet. This phase proves permissions + entitlements + on-device workout only.

5. Build the watch scheme headlessly to confirm it compiles. Do not attempt to run it on device (I do that in Xcode). Commit "Phase 1: watch live heart rate".
```

### YOU DO MANUALLY
1. In Xcode, select the **CoherenceWatch** scheme and your physical **Apple Watch** as the run destination (pair it via the paired iPhone first if it isn't listed).
2. Trust the developer profile on the Watch if prompted (Watch → Settings → General → Device Management).
3. Run. On the Watch, tap **Authorize** and grant HealthKit access, then tap **Start**.

### HUMAN CHECKPOINT
- ☐ Tap Start and wait ~10 seconds. You should see a **live BPM number updating** on your wrist. If it stays blank: authorization was denied (re-check in Watch → Settings → Privacy → Health) or the workout session failed to start (read the Xcode console).
- ☐ Cover the sensor / take the watch off — the number should stop updating or go stale, confirming it's real sensor data, not a placeholder.
- ☐ If the app won't install: signing. Confirm the paid membership is active and both targets have your Team selected with automatic signing.

### ROLLBACK
Commit before Phase 2. Live HR working on hardware is your first real milestone — tag it (`git tag phase1-hr-live`).

---

# Phase 2 — Watch: CoreMotion capture (breathing waveform + stillness + HR)

**GOAL:** During a session the Watch captures `CMDeviceMotion` and averaged HR, and on end produces a raw capture: a motion waveform, HR samples, and — for a belly-breathing session — a live breaths-per-minute readout. This replaces the dead RR-readback phase.

> **Context:** heart coherence is off the table (no third-party beat-to-beat on Apple Watch — proven in the original Phase 2 test). We now measure resonance breathing DIRECTLY via motion. See CLAUDE.md "Why not heart coherence." The Phase-1 `HKWorkoutSession` is reused: it keeps the app foregrounded so motion keeps flowing, and streams the HR trend.

### PASTE INTO CLAUDE CODE
```
Rework the CoherenceWatch capture. FIRST prune the dead coherence path, then add motion.

0. Prune: delete Shared/Models/HeartbeatSeries.swift equivalents on the watch — remove the HKHeartbeatSeriesQuery readback, CapturedSeries, the Scan-24h diagnostic, the stored-cadence probe, and the temporary measurement UI from WorkoutManager/WatchContentView. Drop the HRV(SDNN)/heartbeat-series READ types from HealthKitAuth (keep heart-rate READ + workout SHARE). Add NSMotionUsageDescription to CoherenceWatch/Info.plist. Regenerate with xcodegen.

1. Create CoherenceWatch/Motion/MotionRecorder.swift: a CMMotionManager wrapper. Start deviceMotion updates at ~20 Hz (deviceMotionUpdateInterval = 1/20). For each CMDeviceMotion sample, record timestamp, attitude.pitch (and roll), gravity vector, and userAcceleration. Accumulate into arrays. Expose start()/stop() and the captured buffers.

2. Extend WorkoutManager: keep the HKWorkoutSession (.mindAndBody) running to stay active + stream averaged HR; drive MotionRecorder alongside it. On end(), assemble a raw SessionCapture { motionSamples (t, pitch, roll, gravity, userAccel); hrSamples (t, bpm); bellyBreathing: Bool }.

3. Live belly readout (only when bellyBreathing == true): on a short sliding window of the pitch signal (detrend + band-pass 0.05–0.5 Hz), estimate current breaths/min and publish it for a live label. This is a temporary debug readout to prove the motion signal is real; the mid-session product screen shows NO live biometrics.

4. Temporary Phase-2 UI: a "Belly breathing" toggle, Start/End, and after end a dump of motionSamples count, HR sample count, and (belly) a small plot of the pitch waveform + estimated breaths/min. Handle the weak-signal path: if belly mode found no clear oscillation, show "no clear breathing signal" rather than a fake number.

5. Build the watch scheme headlessly. Commit "Phase 2: CoreMotion capture".
```

### YOU DO MANUALLY
1. Run CoherenceWatch on the physical Watch.
2. **Belly test:** toggle Belly breathing ON, lie down, rest the watch wrist flat on your belly, breathe slowly (~6/min) for a few minutes, End.
3. **Regular test:** toggle OFF, sit normally, End.

### HUMAN CHECKPOINT
- ☐ **Belly:** the pitch waveform is a clean oscillation that tracks your breath, and the breaths/min readout is in the ~4–8 range when you breathe slowly. If the waveform is flat, the wrist isn't picking up belly movement — adjust placement (flat on the belly, not the side).
- ☐ **Milestone (from the spec):** a stable live breaths-per-minute readout from the wrist-on-belly motion over a 5-minute session, plus a waveform plot. Once that's solid, depth/regularity/resonance are layered in the engine (Phase 3).
- ☐ **Regular:** motion + HR samples are captured; no breathing readout is attempted (or it honestly reports "no clear breathing signal").
- ☐ HR sample count is roughly duration/5s (the ~5 s averaged cadence we confirmed).

### ROLLBACK
Tag `phase2-motion-verified`. Do not build the engine (Phase 3) until the belly waveform visibly tracks real breathing.

---

# Phase 3 — Signal engine: breathing + stillness + HR (pure Swift, fully unit-tested)

**GOAL:** A pure-Swift module (no UI, no HealthKit, no CoreMotion) that turns the raw capture (motion waveform + HR samples + a `bellyBreathing` flag) into stillness, HR-decline, and — for belly sessions — breathing metrics, plus aligned timeseries and one overall score. Proven against synthetic signals before any watch is involved.

### PASTE INTO CLAUDE CODE
```
Build the signal engine in Shared/Engine/ as pure Swift (Foundation + Accelerate ONLY — no HealthKit/CoreMotion/SwiftUI). It compiles into both apps and the test target.

1. SignalEngine.swift with:
   struct SignalResult { heartRateTimeseries:[Double]; meanHR:Double; startHR:Double?; endHR:Double?; hrDecline:Double?; stillnessTimeseries:[Double]; stillnessScore:Double?; stillnessMethod:String; breathingRateTimeseries:[Double]; breathDepthTimeseries:[Double]; meanBreathingRate:Double?; breathingRegularity:Double?; resonanceMatchScore:Double?; overallScore:Double?; windowSec:Int; hopSec:Int; algorithmVersion:String }
   static func analyze(motion: [MotionSample], hr: [HRSample], bellyBreathing: Bool, windowSec: Int = 30, hopSec: Int = 5) -> SignalResult
   (MotionSample = t, pitch, roll, gravity, userAccel; HRSample = t, bpm. Define these plain structs in Shared/Engine too.)

2. Sliding windows (pin algorithmVersion "2.0.0"): window i covers [i*hopSec, i*hopSec+windowSec); count = floor((totalSec-windowSec)/hopSec)+1, or 0 if too short. The three resampled timeseries (heartRate, stillness, breathingRate) share ONE index/length; point i timestamp = startedAt + i*hopSec + windowSec/2. Document in a header comment.

3. HR (always): resample averaged HR onto the window grid -> heartRateTimeseries; meanHR; startHR/endHR = first/last window means; hrDecline = startHR - endHR (positive = slowed). No RR, no HRV.

4. Stillness — TWO methods, branch on bellyBreathing:
   - Regular (bellyBreathing == false): stillnessMethod = "total". Per window, stillness from TOTAL motion — low userAcceleration magnitude / low jerk = high stillness. Normalize to 0..1 (1 = perfectly still).
   - Belly (true): stillnessMethod = "breathingExcluded". The deliberate belly oscillation must NOT count as restlessness. Band-STOP the breathing band (0.05–0.5 Hz) out of the motion signal and score stillness from the RESIDUAL (gross movement / higher-freq jerk). So deep belly breathing scores HIGH stillness.

5. Breathing (belly only; else leave empty/nil): take the pitch signal, detrend + high-pass (~0.05 Hz), band-pass 0.05–0.5 Hz, baseline the first few seconds. Per window: dominant frequency (FFT peak or peak-to-peak) -> breathingRateTimeseries (breaths/min); amplitude peak-to-trough -> breathDepthTimeseries. Session: meanBreathingRate; breathingRegularity from breath-interval variance (lower variance = higher regularity, normalize 0..1); resonanceMatchScore = closeness of mean rate to ~6/min (0.1 Hz), 0..1.
   WEAK-SIGNAL FALLBACK: if belly mode can't find a clear oscillation (low band power / unstable rate), return breathing fields empty/nil AND set stillnessMethod = "total" (score stillness the regular way). The session degrades to a 2-signal result; the reader shows "we couldn't read your breathing this time."

6. overallScore: combine the available signals (stillness + hrDecline, plus resonanceMatch+regularity when present) into one 0..1 "practice landed" number. Document the weighting.

7. SignalEngineTests.swift in CoherenceTests/ with named tests (synthetic MotionSample/HRSample builders):
   - test_pointOneHzPitch_readsSixBreaths: pitch = clean 0.1 Hz sinusoid over 120 s, belly=true -> meanBreathingRate ≈ 6 & high resonanceMatchScore.
   - test_noisyPitch_lowRegularity: random pitch, belly=true -> low breathingRegularity (or weak-signal fallback fires).
   - test_bellyBreathingHighStillness: pitch = strong 0.1 Hz oscillation, no gross movement, belly=true -> stillnessScore HIGH (breathing band excluded).
   - test_sameSignalRegularModeLowerStillness: the SAME 0.1 Hz oscillation with belly=false -> stillnessScore LOWER than the belly case (total motion counts it). This proves the branch flips the calculation.
   - test_regularSessionHasNoBreathing: belly=false -> breathing arrays empty, meanBreathingRate nil, stillnessMethod == "total".
   - test_weakBellySignalFallsBack: belly=true but flat/near-zero pitch -> breathing nil AND stillnessMethod == "total".
   - test_hrDecline: HR from 75 -> 60 over the session -> hrDecline ≈ +15, startHR≈75, endHR≈60.
   - test_timeseriesAlignment: heartRate/stillness/breathingRate timeseries counts equal (breathing all-zeros/empty length matches when regular — pick one convention and assert it).
   - test_windowCount: 600 s, windowSec=30, hopSec=5 -> count == floor((600-30)/5)+1.

8. Run `xcodebuild test -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17'`. Iterate until all pass. Commit "Phase 3: signal engine + unit tests".
```

### YOU DO MANUALLY
Nothing on device. Verify the math with tests, not by meditating.

### HUMAN CHECKPOINT
- ☐ All tests pass. If `test_pointOneHzPitch_readsSixBreaths` fails on rate, the FFT bin-to-Hz mapping is wrong (sample rate / N mismatch) — the usual bug.
- ☐ `test_sameSignalRegularModeLowerStillness` passes — this is the proof the two stillness methods actually differ (deep belly breathing must not be penalized as motion).
- ☐ `test_weakBellySignalFallsBack` passes — belly with no readable breathing degrades cleanly to a 2-signal session, no fake number.
- ☐ **Read the synthetic-signal tests yourself.** Confirm the 0.1 Hz pitch test really builds a 0.1 Hz signal. A passing test that tests the wrong thing is worse than none — the product's claim is "the number is real."

### ROLLBACK
Tag `phase3-engine-verified`.

---

# Phase 4 — Session pipeline: trigger → capture → transfer → persist

**GOAL:** From the phone you start a real session; the Watch captures motion + HR and computes; the phone receives the payload and writes Session + MeditationStats.

> **Pre-account users.** Accounts don't exist until Phase 7. Until then, the app creates a single local User row on first launch with `appleUserID = ""` and treats it as the current user, so `Session.userID` is never nil. At Phase 7, first successful Sign in with Apple **adopts** this row — it fills in `appleUserID`, `email`, `displayName` rather than creating a second User. Your Phase 4–6 test sessions therefore survive into the real account. Write this rule in CLAUDE.md now.

### PASTE INTO CLAUDE CODE
```
Wire the end-to-end pipeline. Respect target boundaries: capture/compute on Watch, ALL persistence on iOS.

0. Local user bootstrap (iOS): on first launch, if no User row exists, create one with appleUserID = "" plus its Preferences row. Expose a `currentUser()` accessor. Phase 7 will adopt this row at sign-in rather than creating a new one. Never create a second User while appleUserID is "".

1. WatchConnectivity: create Shared/Connectivity/SessionPayload.swift, a Codable struct { sessionID: UUID; startedAt: Date; mode: String; trackID: UUID?; bellyBreathing: Bool; durationSec: Int; result: SignalResult-flattened fields (all timeseries + scores + windowSec + hopSec + algorithmVersion); discard: Bool }. Create WCSessionManager on each side (activate WCSession).

2. Phone-side start (iOS): create Coherence/Session/SessionCoordinator.swift. On "begin", it:
   - generates a sessionID,
   - sends session params (sessionID, mode, trackID, plannedDurationSec or nil, hapticsEnabled) to the watch via WCSession (transferUserInfo; also sendMessage if reachable),
   - calls HKHealthStore().startWatchApp(with: HKWorkoutConfiguration(activityType:.mindAndBody, locationType:.unknown)) to launch/foreground the watch workout. (iOS uses HealthKit ONLY to issue this launch + request workout authorization — no biometric reads on iOS.)
   Add iOS HealthKit authorization for workoutType (share/read) needed by startWatchApp.

3. Watch-side run: on receiving params (including bellyBreathing), WorkoutManager + MotionRecorder start recording. For a timed session the WATCH owns the countdown; for open-ended it shows an End button. On end, assemble the raw capture; call SignalEngine.analyze(motion:hr:bellyBreathing:windowSec:30 hopSec:5); assemble SessionPayload (actual elapsed duration, discard=true if too short); send via transferUserInfo (guaranteed queued delivery).

4. Phone-side persistence: on receiving SessionPayload (iOS), in SessionCoordinator:
   - if discard OR too short -> write nothing, just dismiss.
   - else, in ONE ModelContext transaction: insert Session (actual duration, bellyBreathing, userID = currentUser().id) + MeditationStats (all engine fields incl. windowSec, hopSec, stillnessMethod, algorithmVersion). NO HeartbeatSeries. No streak write — streak is derived at read time from Session dates via StreakCalculator.
   - Enforce single-writer/uniqueness in code: never create a second Stats for a sessionID.

5. Temporary Phase-4 iOS UI: a "Begin (Regular, 2 min)" button AND a "Begin (Belly, 2 min)" button. After the payload lands, a debug screen dumping Session.durationSec, Session.bellyBreathing, Stats.stillnessScore, Stats.hrDecline, Stats.meanBreathingRate (nil for regular), Stats.overallScore, the timeseries counts, and the current streak (via StreakCalculator over the user's Session start dates).

6. Add StreakCalculatorTests.swift in CoherenceTests/ with these named tests (pass explicit today/calendar for determinism): test_sameDayDoesNotIncrement (two sessions on the same local day -> current stays 1), test_oneDayGapContinues (consecutive days -> current increments), test_multiDayGapResets (a gap > 1 day -> current resets to the run ending at the anchor), test_longestSurvivesBreak (longest reflects the best past run even after a break), test_emptyReturnsZero (empty input -> (0, 0)).

7. Build both schemes headlessly; run engine tests. Commit "Phase 4: session pipeline".
```

### YOU DO MANUALLY
1. Run the **iOS** app on your iPhone (with the Watch paired and this build on the Watch).
2. Tap **Begin**, confirm the Watch launches into the session and taps your wrist, meditate ~2 min, let it end.

### HUMAN CHECKPOINT
- ☐ After a **Regular** session: durationSec ≈ 120, a plausible **stillnessScore** and **hrDecline**, **meanBreathingRate = nil**, **overallScore** present, **Streak = 1**, and timeseries counts around 19 (120 s at windowSec 30 / hopSec 5). If a count is off, the hop/window isn't reaching the Watch call site.
- ☐ After a **Belly** session (wrist on belly): **meanBreathingRate** is a real ~4–8 value and **resonanceMatchScore** is present; stillnessMethod == "breathingExcluded". If breathing is nil, the signal was too weak (bad placement) and it fell back to a 2-signal result — expected behavior, retry placement.
- ☐ If nothing appears on the phone: the payload didn't transfer — `transferUserInfo` can lag; wait 30–60 s, then check whether `startWatchApp` launched the watch app.
- ☐ Run a **second** session the same day → **Streak stays 1**. If it goes to 2, the day-comparison is using timestamps, not local calendar days.
- ☐ End a very short session → **nothing is written** and the UI dismisses cleanly.

### ROLLBACK
Tag `phase4-pipeline-verified`. This is the second-riskiest gate; the product exists after this.

---

# Phase 5 — Audio playback + meditation setup hierarchy

> **⚠️ RESEQUENCED (2026-07-19): DEFERRED until after the biometric-evidence work.**
> Priority is nailing the biometric data (capture + display) before setup/audio
> polish. **Phase 6 (Meditation Logged / Calendar / Stats — the evidence graphs)
> runs FIRST**, using the temp "Begin Regular/Belly" buttons as the session
> trigger. This audio + setup-hierarchy + haptics work comes after the graphs are
> solid. (Step 1 — built-in track seeding — is already done; the rest waits.)

**GOAL:** The real setup flow — mode chooser, track lists, silence, duration picker, open-ended sessions with a Watch end control, and bookend haptics — driving the Phase-4 pipeline.

### PASTE INTO CLAUDE CODE
```
Build the setup hierarchy and audio (iOS drives audio + navigation; Watch fires bookend haptics).

1. Seed one MeditationTrack per type at first launch (guided with a real duration, one frequency, one nature) — bundle placeholder audio files in Coherence/Audio/ and set audio_url to the bundled filenames. Silence is a MODE, never a track row.

2. Meditation Setup screen (iOS): always a chooser, NO default mode — four options: Guided, Frequency, Nature, Silence.
   - Guided -> since only ONE guided track exists at launch, SKIP the track list and go straight to session (build the list component but branch: if count==1, skip). Duration = the track's durationSec.
   - Frequency / Nature -> track list (query tracks where type==X && isActive, ordered by sortOrder) -> duration picker -> session.
   - Silence -> duration picker -> session (trackID nil, mode silence).
   Duration picker: preset options + an "Open-ended" choice (nil). Persist the chosen value to Preferences.defaultDurationSec as the remembered pick.

2b. Posture choice (sets Session.bellyBreathing, orthogonal to mode): after duration, a simple two-option step — "Regular" (default) or "Belly breathing." Belly shows a short instruction card: lie down, rest the watch wrist flat on your belly, breathe slowly. Most users pick Regular; belly is the deliberate opt-in that unlocks the breathing signal. Pass bellyBreathing into the session params sent to the Watch.

3. Audio: AVAudioSession configured for playback + background audio; play the selected track (or nothing for silence). For timed sessions the WATCH owns end timing; the phone runs a parallel timer only to stop/fade audio. For open-ended, audio loops until the Watch's End button signals stop over WCSession.

4. Haptics (Watch): read hapticsEnabled from the params. Fire ONE WKInterfaceDevice haptic at session start (recording confirmed) and ONE at end (time's up). NEVER mid-session. If hapticsEnabled false, fire neither.

5. Mid-meditation screen (iOS): calm, minimal, NO live biometrics (evidence comes after, not during). Show elapsed time and a Stop control. Wire Stop to end the session (phone tells Watch to end via WCSession; Watch finalizes and sends the payload).

6. Build both schemes; run tests. Commit "Phase 5: setup hierarchy + audio + haptics".
```

### YOU DO MANUALLY
1. Run iOS on iPhone (Watch paired). Walk each path: Guided, Frequency→track→duration, Nature→track→duration, Silence→duration, and one **Open-ended** session.

### HUMAN CHECKPOINT
- ☐ Guided **skips the track list** (one track) and uses the track's length. Frequency/Nature **show a list then a duration picker**. Silence shows only a duration picker. If Guided shows a list, the count==1 skip branch is missing.
- ☐ The **posture step** appears after duration; **Regular is the default**, and choosing **Belly** shows the lie-down / wrist-on-belly instructions. The chosen value reaches the Watch (verify a belly session produces breathing metrics).
- ☐ You feel **exactly one wrist tap at start and one at end**, none in between; toggling haptics off in Preferences silences both.
- ☐ An **open-ended** session runs until you tap **End on the Watch**, then audio stops on the phone. If audio keeps playing, the Watch→phone stop signal isn't landing.
- ☐ The mid-meditation screen shows **no heart rate, no coherence, no numbers** beyond elapsed time. This is a product stance, not an oversight.

### ROLLBACK
Tag `phase5-flow-complete`.

---

# Phase 6 — Meditation Logged, Calendar, Stats (pure readers)

> **⚠️ RESEQUENCED (2026-07-19): PULLED FORWARD — runs before Phase 5 (audio).**
> This is the biometric-evidence display: the post-session results screen with the
> three signal graphs (HR-settling, stillness, belly-breathing) + the logged
> history / calendar / streak. It reads `MeditationStats` already produced by the
> Phase-4 pipeline, so it has NO dependency on the deferred audio/setup work.

**GOAL:** The emotional payoff and history screens — each reads storage independently, screens pass only IDs, no screen writes.

### PASTE INTO CLAUDE CODE
```
Build three READER screens (iOS). None of them writes. None receives data from another screen — each does its own SwiftData fetch; navigation passes only a sessionID or a date.

1. Meditation Logged: appears automatically when a session's payload has been persisted. Given a sessionID, it fetches Session + MeditationStats independently and renders the "practice landed" payoff. Branch on the data:
   - Headline: overallScore. Always show two panels:
     - **Stillness**: the stillness curve over time + stillnessScore.
     - **Heart rate**: the HR curve over time with its **decline annotated** (start→end delta or a trend line) — this IS the "deceleration," not a separate graph.
   - **Belly sessions with breathing data** add a third panel: the **breathing waveform** + rate / regularity / resonance-match.
   - **Belly sessions where breathing couldn't be read** (breathing fields empty): omit the breathing panel and show a gentle "we couldn't read your breathing this time — showing stillness + heart rate" note; it renders exactly like a Regular 2-signal session.
   All curves share one x-axis: time for point i = startedAt + i*hopSec + windowSec/2 — read windowSec/hopSec from the stored row, never hardcode. Use Swift Charts. Show started_at ("tonight at 9pm"), duration, and (if belly) a small "Belly breathing" tag. Colors via AppColor.

2. Calendar: fetches all Sessions for the user, groups by started_at LOCAL day, marks days with sessions. Tapping a day opens that day's Meditation Logged (pass sessionID only — never the fetched objects). If a day has multiple sessions, show a simple list of that day's sessions first, then tap through to one. Keep the list dumb; a richer day-detail design is a later decision.

3. Stats: independent fetches — total sessions, current + longest streak (computed via StreakCalculator from the user's Sessions), most-used mode (from Session.mode), and trends across sessions (mean stillness, mean HR decline, and — over belly sessions only — mean resonance-match). Read-only.

4. Assemble the tab bar (Calendar, Stats, Meditation Setup, Profile placeholder) — all mutually reachable. Streak displays on BOTH Calendar and Stats, computed via StreakCalculator from the user's Sessions.

5. Build; run tests. Commit "Phase 6: reader screens".
```

### YOU DO MANUALLY
1. Run iOS. Complete a fresh session and let **Meditation Logged** appear. Then open **Calendar** and **Stats**.

### HUMAN CHECKPOINT
- ☐ A **Regular** session shows **two panels** (stillness + HR-with-decline), each a smooth curve with dozens of points, not a staircase. If it's a staircase, hopSec isn't honored end to end.
- ☐ A **Belly** session shows a **third panel** (breathing waveform + rate/regularity/resonance). If the panels have different lengths, the arrays aren't sharing windowSec/hopSec — a Phase-3 alignment regression.
- ☐ A **belly session with weak breathing** renders as a 2-panel session with the "couldn't read your breathing" note — no empty graph, no fake number.
- ☐ Tapping today on the **Calendar** reopens that day's session in the Logged view. Kill and relaunch the app, reopen it from Calendar — data persists (SwiftData local store).

### ROLLBACK
Tag `phase6-readers-done`.

---

# Phase 7 — Onboarding, Sign in with Apple, CloudKit, Preferences, account deletion

**GOAL:** The account layer, cloud sync, and settings — Apple-only auth, first-run onboarding, editable preferences, and a compliant delete + 30-day purge.

### PASTE INTO CLAUDE CODE
```
Build accounts, sync, and settings (iOS). Apple-only auth — no passwords, no Google, no email/password in v1.

0. Entitlements: add com.apple.developer.applesignin ["Default"]; com.apple.developer.icloud-container-identifiers ["iCloud.com.lockout.coherence"]; com.apple.developer.icloud-services ["CloudKit"]; aps-environment "development" to Coherence.entitlements. Regenerate with xcodegen. Switch CoherenceApp.swift from Persistence.local() to Persistence.cloudKit(). Run once and confirm the app still launches — a CloudKit ModelContainer crash here means a model property is non-optional or carries .unique.

1. Onboarding: Purpose Description -> Science Description (both static, re-readable later from Settings) -> Sign in with Apple -> land in the app. Gate on Preferences.onboardingComplete; set it true after first successful sign-in. Note the bootstrap Preferences row from Phase 4 already exists with onboardingComplete=false, so the gate reads a real row, not an absent one.

2. Sign in with Apple (AuthenticationServices): on success, read the credential's user identifier (appleUserID), and — ONLY on first sign-in — the name and email (Apple gives these once; persist immediately). Account matching, in this order:
   a. Query User by appleUserID. If found, sign in as that user.
   b. Else, if the local bootstrap User exists (appleUserID == ""), ADOPT it: set appleUserID, email, displayName on that row. Do NOT create a second User — the pre-account sessions and streak belong to it.
   c. Else create a new User plus its Preferences row in one transaction.
   Set email only if provided; detect Hide My Email by checking whether email ends in "privaterelay.appleid.com" (no separate column). display_name and email are nullable — tolerate their absence. There is no email verification flow: Apple vouches for the address.

3. Preferences / Profile-Settings screen: reads + writes User (display_name, marketing_opt_in) and Preferences (theme, reminders_enabled + reminder_time, default_duration_sec, haptics_enabled). Re-expose Purpose and Science content here. Theme switch drives the app appearance (system/light/dark) via the asset catalog.

4. Daily reminder: if reminders_enabled, schedule ONE UNUserNotificationCenter local notification at reminder_time; reschedule on change; cancel when disabled.

5. Marketing email list export: on marketing_opt_in true AND a non-relay email present, POST {email} to the configured list provider (leave the endpoint as a TODO constant) — do NOT build a backend. Explicit opt-in only.

6. Account deletion (Apple requirement): a "Delete Account" control that (a) soft-deletes — set User.deletedAt = now, sign the user out — and (b) a purge routine that runs on app launch: find Users where deletedAt <= now - 30 days and HARD-DELETE the User row and every row FK'd to it (Preferences, Sessions, MeditationStats) in one transaction. We store no raw biometrics (only computed timeseries), so no HealthKit deletion is needed.

7. Build; run tests. Commit "Phase 7: accounts + CloudKit + settings + deletion".
```

### YOU DO MANUALLY
1. Run iOS on device. Fresh install → complete onboarding → **Sign in with Apple** (try once with **Hide My Email**).
2. In Settings, change theme, toggle a reminder, edit display name. Then exercise **Delete Account**.

### HUMAN CHECKPOINT
- ☐ Sign in with Apple completes and lands you in the app; relaunch keeps you signed in (appleUserID matched, not re-created). If a second account appears on re-sign-in, the appleUserID match query is broken — you'd silently split streaks.
- ☐ Sign in on a device that already has **pre-account test sessions**. Your old sessions and streak are still there afterward — the adopt path (2b) worked. If they vanish, a second User was created.
- ☐ Theme switch flips the whole app light/dark **through the asset catalog** (no screen ignores it — proof no hardcoded hex slipped in).
- ☐ Hide-My-Email sign-in stores a `privaterelay.appleid.com` address and the app still works, and that address is **excluded** from the marketing list export.
- ☐ Delete Account signs you out and sets deletedAt. To verify purge without waiting 30 days, temporarily shorten the window to 0 in a debug build, relaunch, and confirm the User and all FK'd rows are gone. **Restore the 30-day window before shipping.**

### ROLLBACK
Tag `phase7-v1-feature-complete`.

**STATUS: BUILT (v1 feature-complete).** Onboarding + Sign in with Apple, bootstrap-User adopt, Settings (profile/theme/haptics/reminders/re-read Purpose+Science), account deletion + 30-day purge, and CloudKit sync are all in and unit-tested (47 tests). CloudKit is NOT yet verified cross-device (no second device on hand); marketing-list export still stubbed. See CLAUDE.md "Phase 7 DONE."

---

## After Phase 7 — before TestFlight
- Replace placeholder audio with real tracks; set `algorithmVersion` intentionally if the math changed.
- Confirm `aps-environment` is `production` for release and CloudKit is deployed to the production environment in the CloudKit dashboard.
- Privacy nutrition labels: declare Health data usage; you store references, not raw biometrics — say so accurately.
- Deferred, don't reopen now: **multi-user sharing** (share a session/feed with other users — needs an infra decision: CloudKit public DB / `CKShare` vs. a real backend, plus public identity fields on User and per-session visibility); **external BLE HRV sensor "Pro" tier** (true HRV + coherence via Polar/HeartMath-class sensor over CoreBluetooth — the only path to real coherence); subscriptions/paywall (`is_premium`/`premium_expires_at`); Google + email/password auth; streak freezes; track artwork; nature-sound mixing; richer calendar day-detail. All clean additive upgrades.

---

# Phase 8 — Design polish, brand, and App Store launch (ROUGH)

**GOAL:** Turn the working-but-utilitarian app into something that looks and feels like a shippable product, give it a brand (name lockup, logo, app icon), and get it live on the App Store. The app is feature-complete (Phases 0–7); this phase is design + go-to-market, not new capability.

> This is a rough plan — it firms up as we go. Three streams; **8a and 8b can run in parallel** with each other and with any remaining engineering.

## 8a — UI / UX design polish

The current screens are functional debug UI (bordered buttons, monospace dumps). Redesign the real user-facing flow into a cohesive, calm, premium experience — dark-first (gold-on-near-black is the current palette; finalize it).

Screens to design (all already exist functionally): **Onboarding** (Purpose/Science/sign-in), **Home**, **Session setup** (mode/length/posture/sound), **Mid-session** (calm, no live biometrics — product stance), **Post-session evidence** (the payoff — stillness / HR-decline / breathing graphs + overall), **Calendar / History**, **Settings**.

- Establish a small **design system**: typography scale, spacing, corner radii, the existing `AppColor` palette (keep everything routed through it — no hardcoded hex), reusable components (cards, stat tiles, buttons, graph styling via Swift Charts).
- Motion/transitions, empty states, loading/`analyzing…` states, and **accessibility** (Dynamic Type, VoiceOver labels, contrast).
- Remove all TEMP debug UI (belly-diagnostic box, the console/summary dumps, dev "Skip" — keep dev skip behind `#if DEBUG`).
- Light + dark both look right (theme switch already wired).

## 8b — Brand & assets

- **Name lockup + logo** for **808**; finalize the palette.
- **App icon** (1024×1024, plus the generated sizes) — no transparency, no rounded corners (Apple rounds it).
- **App Store screenshots** for required device sizes (6.7"/6.9" iPhone at minimum; Apple Watch screenshots if we surface the watch), plus optional preview video.
- Marketing copy: subtitle, promo text, description, keywords, category (Health & Fitness).

## 8c — App Store go-live (research done — see below)

**Legal / hosting (do first; reviewers check the URLs):**
- **Privacy policy** — REQUIRED (hard requirement for HealthKit/health apps), publicly hosted HTTPS URL, and also reachable in-app. Must describe our health/motion data use. Our story is clean: **we store no raw biometrics** (only computed stats), the phone reads zero biometrics, and we don't use health data for ads — say all of this accurately.
- **Support URL** — REQUIRED and must actually work (reviewers visit it).
- **Terms of Service / EULA** — Apple's standard EULA covers the basics; add a **wellness disclaimer** ("808 is not a medical device; not medical advice") given the health framing. Keep all claims **wellness, not medical** (SCIENCE.md already does — no "detects theta," no medical claims).
- **A simple website/landing page** to host the above (privacy + support + ToS). A one-pager is enough to start.

**Founders' agreement + IP assignment — DEFERRED (do before/around launch).** Two equal founders (Melvin NYC, Aziz Detroit). Agreed to handle the founders'/operating agreement + IP assignment later; it's the highest-value legal doc but not a launch blocker (v1 can ship on Melvin's individual Apple account). LLC structure discussed: multi-member, **Michigan domestic + New York foreign-qualification with an Albany-county registered agent** (NY publication is county-priced, ~$230 Albany vs ~$2k Manhattan; foreign LLCs must publish too); skip Delaware unless raising VC. See the LLC-formation notes.

**Account decision (Melvin + Aziz):**
- **Individual** account → your personal legal name shows as the App Store seller; no D-U-N-S; simplest/cheapest; fine to launch and convert later.
- **Organization** (LLC/Corp) → company name as seller, requires a **legal entity + D-U-N-S number**, lets you add teammates and share ownership. If you form an LLC you *must* enroll as an organization. Given two co-founders + a planned social product, an LLC + org account is the "real company" path — but not required to ship v1.

**App Store Connect setup:**
- Enable every capability the app uses on the App ID: **HealthKit, Sign in with Apple, CloudKit/iCloud, Push (aps)** — and flip `aps-environment` to `production` and **deploy the CloudKit schema to the production environment** before release.
- Fill the **App Privacy "nutrition labels"** carefully: declare Health & Fitness data, plus email/name from Sign in with Apple, and whether each is linked to the user. (Apple's 2026 review is stricter on data transparency.)
- Age rating questionnaire, export-compliance (standard — no non-exempt encryption), category, pricing (free to start).
- Replace any placeholder audio with licensed/owned tracks; set `algorithmVersion` intentionally.

**Ship:**
- Internal + external **TestFlight** beta first (this is also where cross-device CloudKit sync finally gets verified on real hardware).
- Then submit for review. **Top rejection causes to pre-empt:** crashes/bugs (>40% of rejections — test thoroughly), missing/incomplete privacy disclosures, and metadata inaccuracies. We're in good shape on the Apple-specific gotchas: account deletion is built (required), Sign in with Apple is the only auth (compliant), HealthKit usage strings are present and honest.

### Research sources
[App Store submission checklist 2026](https://appbuilder.academy/blog/app-store-submission-checklist) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Health-app privacy guidelines](https://www.termsfeed.com/blog/privacy-guidelines-health-apps/) · [Individual vs Organization enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) · [D-U-N-S requirement](https://developer.apple.com/support/D-U-N-S/index.html)

## Global conventions (enforced every phase)
- Never hardcode a hex value — every color routes through the asset catalog / `AppColor`.
- All sensor / HealthKit / CoreMotion code lives in the **Watch target only** (the one exception: iOS calls `startWatchApp` to trigger, reading no biometric data).
- The three resampled timeseries share one `windowSec`, one `hopSec`, and one index. Never hardcode either value in the UI — read them from the stored row.
- Read which signals a session has from `Session.bellyBreathing` + populated Stats fields: Regular = stillness + HR; Belly = +breathing, or degrades to 2 if breathing couldn't be read.
- Screens read storage independently and pass only IDs; Sessions and Stats are immutable.
- Every SwiftData model stays CloudKit-safe: optional/defaulted properties, no `.unique`, no non-optional relationships.
- Uniqueness is enforced in code: one Stats per session, one User per appleUserID, one bootstrap User while appleUserID is "".
