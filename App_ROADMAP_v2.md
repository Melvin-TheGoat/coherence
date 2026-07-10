# Coherence — v1 Development Roadmap (v2)

Heart-coherence meditation app · iPhone + Apple Watch · Swift / SwiftUI / SwiftData / HealthKit
Execution model: instructions pasted into **Claude Code in a terminal** (no IDE integration). Project defined via **XcodeGen** so Claude Code can edit `project.yml` and regenerate the `.xcodeproj` with one command.

**Changes from v1:** sliding-window coherence analysis (`hopSec`); Sign in with Apple only (Google + email/password deferred); CloudKit deferred from Phase 0 to Phase 7; explicit pre-account user handling; Phase 2 fallback plan; calendar day-tap opens that day's Meditation Logged.

---

## Architecture decisions baked into this plan (read once, do not relitigate)

- **The phone is the only persistence layer.** SwiftData lives on iOS. The Watch holds **no** store; it captures heartbeat data, computes stats, and ships the result to the phone over WatchConnectivity. The phone performs every write. "One writer per object" is preserved as a *logical* rule (the Watch is the logical author of heartbeat data; the physical write happens on the phone when the payload lands).
- **Phone-triggered start = `HKHealthStore.startWatchApp(with:)`.** You cannot launch a watchOS app from the phone via WatchConnectivity. `startWatchApp` is the supported mechanism. Therefore the **iOS target carries the HealthKit entitlement + usage strings to issue the launch command only** — it reads zero biometric data. All heartbeat *logic* stays on the Watch.
- **Foreign keys are stored as plain `UUID` properties, not SwiftData `@Relationship`.** Matches the ERD, honors "screens read independently," and avoids CloudKit relationship-optionality constraints.
- **CloudKit compatibility is non-negotiable in every model** *even before CloudKit is switched on*: no `@Attribute(.unique)`, no non-optional relationships, every stored property optional or defaulted. Uniqueness (one Stats/session, one User/appleUserID) is enforced in code, never in schema. CloudKit itself is enabled in Phase 7 — the models are built for it from Phase 0 so the flip is a one-line change.
- **Auth is Sign in with Apple only in v1.** No passwords, no Google. Apple handles verification, resets, and credential storage; this removes `auth_provider`, `provider_user_id`, `password_hash`, and `email_verified` from the User model, and removes the cross-provider account-collision problem entirely. Additive to re-add later.
- **Timed sessions are clocked by the Watch** (it fires the authoritative end-haptic). The phone runs a parallel timer only to stop audio. Open-ended sessions end from a Watch button.
- **Coherence is analyzed with overlapping sliding windows.** A 60 s window is required to resolve the ~0.1 Hz peak, but non-overlapping windows would yield one point per minute — a 10-point graph for a 10-minute session. The window advances by a small `hopSec` instead, producing a smooth trajectory. `windowSec` and `hopSec` are both stored on every result so old sessions remain interpretable after the parameters change.

**HARD GATE:** Phase 0 runs on a free Apple ID with a **local** (non-CloudKit) store. **Phase 1 onward requires the paid Apple Developer Program ($99/yr)** — HealthKit on device, CloudKit, and Sign in with Apple are unavailable under free provisioning. Buy it before starting Phase 1.

**Bundle IDs used throughout (change the prefix once, here, if you want):**
- iOS app: `com.lockout.coherence`
- Watch app: `com.lockout.coherence.watchkitapp`
- iCloud container: `iCloud.com.lockout.coherence`

---

# Phase 0 — Project skeleton, schema, local store, CLAUDE.md

**GOAL:** A regenerable XcodeGen project with iOS + watchOS targets, all 6 SwiftData models (CloudKit-safe in shape, local in storage), a local ModelContainer on the phone, a central color catalog, and a `CLAUDE.md` that future sessions inherit — building green in the simulator.

### PASTE INTO CLAUDE CODE
```
We are building "Coherence," a heart-coherence meditation app for iPhone + Apple Watch. Set up the project from scratch in the current empty directory. Requirements:

1. Install XcodeGen if absent: `brew install xcodegen`. Verify with `xcodegen --version`.

2. Create this folder layout:
   Coherence/            (iOS app target sources)
   CoherenceWatch/       (watchOS app target sources)
   Shared/               (code compiled into BOTH apps + the test target)
   Shared/Models/        (SwiftData @Model files)
   Shared/Engine/        (pure-Swift coherence engine — Phase 3, create empty dir now)
   CoherenceTests/       (unit tests)

3. Write `project.yml` defining three targets:
   - "Coherence": iOS application, deploymentTarget iOS 17.0, sources [Coherence, Shared]. It EMBEDS the watch app (dependency on CoherenceWatch, embed: true). PRODUCT_BUNDLE_IDENTIFIER com.lockout.coherence. INFOPLIST_FILE Coherence/Info.plist, CODE_SIGN_ENTITLEMENTS Coherence/Coherence.entitlements, GENERATE_INFOPLIST_FILE NO, SWIFT_VERSION 5.10.
   - "CoherenceWatch": watchOS application, deploymentTarget watchOS 10.0, sources [CoherenceWatch, Shared]. PRODUCT_BUNDLE_IDENTIFIER com.lockout.coherence.watchkitapp, WKCompanionAppBundleIdentifier com.lockout.coherence, INFOPLIST_FILE CoherenceWatch/Info.plist, CODE_SIGN_ENTITLEMENTS CoherenceWatch/CoherenceWatch.entitlements, GENERATE_INFOPLIST_FILE NO.
   - "CoherenceTests": iOS unit-test bundle, host application Coherence, sources [CoherenceTests, Shared].
   Set options.bundleIdPrefix com.lockout, createIntermediateGroups true. Leave DEVELOPMENT_TEAM empty (I set it in Xcode).

4. Create the 6 SwiftData models in Shared/Models/, one file each. EVERY property must be optional OR have a default (CloudKit requirement — we enable CloudKit in Phase 7 and the models must already be compatible). NO @Attribute(.unique) anywhere. Store enums as String with computed enum accessors. Store foreign keys as plain UUID? properties (NOT @Relationship). Exact fields:

   User.swift — id:UUID=UUID(), appleUserID:String="", email:String?, displayName:String?, marketingOptIn:Bool=false, createdAt:Date=Date(), updatedAt:Date=Date(), deletedAt:Date?
   Preferences.swift — id:UUID=UUID(), userID:UUID?, onboardingComplete:Bool=false, defaultDurationSec:Int? (nil=open-ended), remindersEnabled:Bool=false, reminderTime:Date?, theme:String="system", hapticsEnabled:Bool=true, createdAt:Date=Date(), updatedAt:Date=Date()
   MeditationTrack.swift — id:UUID=UUID(), type:String="guided", title:String="", trackDescription:String?, audioURL:String="", durationSec:Int?, sortOrder:Int=0, isActive:Bool=true, createdAt:Date=Date(), updatedAt:Date=Date()
   Session.swift — id:UUID=UUID(), userID:UUID?, trackID:UUID? (nil=silence), mode:String="silence", startedAt:Date=Date(), durationSec:Int=0, createdAt:Date=Date(). NO updatedAt — immutable.
   HeartbeatSeries.swift — id:UUID=UUID(), sessionID:UUID?, healthkitUUID:String="", beatCount:Int=0, createdAt:Date=Date()
   MeditationStats.swift — id:UUID=UUID(), sessionID:UUID?, coherenceScore:Double? (nil=too short), coherenceTimeseries:[Double]=[], hrvTimeseries:[Double]=[], heartRateTimeseries:[Double]=[], windowSec:Int=60, hopSec:Int=5, meanHR:Double=0, rmssd:Double=0, peakFrequencyHz:Double?, algorithmVersion:String="1.0.0", createdAt:Date=Date()

   NOTE: Streak is NOT a stored model — it is derived at read time from Session dates. Instead create Shared/Engine/StreakCalculator.swift (pure Swift, imports Foundation ONLY — no SwiftData/HealthKit/UI):
     func streak(from sessionDates: [Date], today: Date = Date(), calendar: Calendar = .current) -> (current: Int, longest: Int)
   Reduce sessionDates to a Set of local day-starts via calendar.startOfDay. current: anchor = today if present in the set, else yesterday if present, else return current 0; then walk backward from the anchor counting consecutive days present. longest: the maximum run of consecutive calendar days over all unique days. Handle empty input (returns 0, 0). Keep it allocation-light and deterministic.

   NOTE on MeditationStats: windowSec is the FFT analysis window; hopSec is how far the window advances between points. The three timeseries arrays are sampled at hopSec, share one index, and are always the same length. Both values are stored per-row so a result stays interpretable if the parameters ever change.

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
   CoherenceWatch/Info.plist — NSHealthShareUsageDescription, NSHealthUpdateUsageDescription; WKBackgroundModes ["workout-processing"]; WKApplication true.

10. Write CLAUDE.md at repo root capturing: the product ("coherence as evidence, not a training score"), the architecture decisions from the top of ROADMAP.md (phone is sole store; Watch is stateless sensor/compute/transfer; startWatchApp for triggering; FKs as UUIDs; CloudKit-safe modeling from day one with CloudKit itself enabled in Phase 7; Apple-only auth; Watch-clocked timing; sliding-window coherence with windowSec + hopSec), the full 6-entity schema, the session-end sequence, and the conventions (colors via catalog only; all HealthKit/heartbeat code in the Watch target only, except iOS calling startWatchApp; the three timeseries share one windowSec/hopSec and one index; sessions and stats immutable; screens never pass data to screens, only IDs).

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

# Phase 2 — Watch: read back RR intervals after a session (make-or-break)

**GOAL:** After ending a session, the Watch queries the recorded `HKHeartbeatSeriesSample` and produces the array of beat-to-beat (RR) intervals — the single capability the whole product depends on.

> **Before writing code:** spend 30 minutes confirming what actually causes watchOS to record an `HKHeartbeatSeriesSample`. It is well established that Apple's own Mindfulness/Breathe sessions and ECG produce one, and that third-party apps can *read* series via `HKHeartbeatSeriesQuery`. What this phase assumes — that a *third-party* `HKWorkoutSession` with `.mindAndBody` also triggers series recording — is the assumption the entire product rests on. Check Apple's HealthKit documentation and developer forums first.

### PASTE INTO CLAUDE CODE
```
Extend WorkoutManager (CoherenceWatch ONLY) to record and read back beat-to-beat data.

1. On end(): finish the HKLiveWorkoutBuilder, obtain the finished HKWorkout, then run an HKHeartbeatSeriesQuery to fetch the HKHeartbeatSeriesSample recorded during the session. From the query's per-beat callback, accumulate the time-since-series-start values and convert consecutive differences into RR intervals (in seconds). Also capture the HKHeartbeatSeriesSample's UUID string and the total beat count.

2. Create a struct CapturedSeries { rrIntervals: [Double]; healthkitUUID: String; beatCount: Int } and have end() return it (async).

3. Add a debug view state: after ending, display beatCount, healthkitUUID (truncated), and the first ~10 RR intervals in ms on the watch screen. This is temporary Phase-2 UI to eyeball the data.

4. Handle the failure path: if no heartbeat series was recorded (query returns nothing), surface "NO SERIES" on screen rather than crashing.

5. Build the watch scheme headlessly. Commit "Phase 2: RR interval readback".
```

### YOU DO MANUALLY
1. Run CoherenceWatch on the physical Watch.
2. Start a session, **wear the watch snugly**, sit still for **at least 2 minutes** (beat-to-beat series needs real duration to populate), then End.

### HUMAN CHECKPOINT
- ☐ After ending, you should see a **non-zero beatCount** and a list of **RR intervals roughly in the 600–1100 ms range** (i.e., ~55–100 bpm). If you see "NO SERIES," work the causes in this order: (1) session too short — rerun for 3+ minutes; (2) loose band / poor sensor contact — tighten and rerun; (3) **the mechanism itself** — a third-party workout session may not trigger series recording at all. Distinguish (3) from (1) and (2) by running Apple's own **Mindfulness** app for 3 minutes, then querying HealthKit for a heartbeat series in that time range. If Apple's app produces a series and yours never does, the mechanism is the problem, not your execution.
- ☐ Sanity-check the numbers: 60/(mean RR in seconds) should approximate the BPM you saw live in Phase 1. If it's wildly off (e.g., 2× or ½), the RR conversion is doubling or halving intervals — tell Claude Code the mean RR and expected BPM to fix the diff logic.
- ☐ **Do not proceed until you see real RR intervals from your own app.** Everything downstream is worthless without this.

### IF THIS PHASE FAILS
Do not improvise. The fallback options, in order of preference:
1. **Read Apple's series instead of recording your own.** Prompt the user to run a Mindfulness session (or trigger one), then query the resulting `HKHeartbeatSeriesSample` by date range. Costs UX elegance; keeps the science intact.
2. **Camera PPG on the iPhone.** Finger on the lens, extract beat-to-beat intervals from the video signal. Loses the Watch story entirely; changes the product.
3. **Reconsider the metric.** HealthKit exposes HRV (SDNN) samples without a heartbeat series — but SDNN alone cannot produce a coherence score, because coherence is about the *rhythmicity* of the variation, not its magnitude. This path is a different product.

### ROLLBACK
Tag `phase2-rr-verified`. This is the riskiest gate in the project; do not build further on an unverified pipeline.

---

# Phase 3 — FFT coherence engine, sliding-window (pure Swift, fully unit-tested)

**GOAL:** A pure-Swift module (no UI, no HealthKit) that turns an RR-interval array into a coherence score, three aligned timeseries, and summary stats — proven correct against synthetic signals before any watch is involved.

### PASTE INTO CLAUDE CODE
```
Build the coherence engine in Shared/Engine/ as pure Swift (import Foundation + Accelerate ONLY — no HealthKit, no SwiftUI). It compiles into both apps and the test target.

1. CoherenceEngine.swift with a struct CoherenceResult { coherenceScore: Double?; coherenceTimeseries: [Double]; hrvTimeseries: [Double]; heartRateTimeseries: [Double]; windowSec: Int; hopSec: Int; meanHR: Double; rmssd: Double; peakFrequencyHz: Double?; algorithmVersion: String } and a static func analyze(rrIntervals: [Double], windowSec: Int = 60, hopSec: Int = 5) -> CoherenceResult.

2. Session-wide algorithm (pin as algorithmVersion "1.0.0"):
   a. Build a tachogram: cumulative time from RR intervals, then linearly interpolate to an evenly sampled series at 4 Hz.
   b. Remove mean and linear trend.
   c. Apply a Hann window (vDSP).
   d. FFT via Accelerate (vDSP), compute the power spectrum.
   e. In the analysis band 0.04–0.26 Hz, find the peak frequency -> peakFrequencyHz.
   f. coherenceScore = (power in a ±0.015 Hz window around the peak) / (total power in 0.04–0.26 Hz), clamped 0...1.
   g. If the RR series is too short to resolve 0.1 Hz (define: total covered time < 60 s OR fewer than ~2 full cycles at the peak), return coherenceScore = nil and peakFrequencyHz = nil, but STILL return valid HR/HRV timeseries and summary stats.
   h. meanHR and rmssd = session-wide values.

3. SLIDING-WINDOW TIMESERIES (this is the change from the previous plan — read carefully):
   - The analysis window is windowSec (60 s) — long enough to resolve the ~0.1 Hz peak.
   - The window ADVANCES by hopSec (5 s), not by windowSec. Windows overlap heavily.
   - Window i covers [i*hopSec, i*hopSec + windowSec). Number of windows = floor((totalSec - windowSec) / hopSec) + 1, or 0 if totalSec < windowSec.
   - For EACH window compute: mean bpm (60 / mean RR in that window) -> heartRateTimeseries[i]; RMSSD in ms -> hrvTimeseries[i]; the coherence ratio from step 2f applied to that window's spectrum -> coherenceTimeseries[i] (0 where unresolvable, never nil inside the array).
   - All three arrays therefore have IDENTICAL length and index alignment; a point's timestamp is startedAt + i*hopSec + windowSec/2 (window center). Document this timestamp convention in a header comment — the UI depends on it.
   - Rationale (keep in the comment): non-overlapping 60 s windows would give a 10-minute session only 10 points. With hopSec=5 it gives ~109. The trajectory is the product's payoff; it needs resolution.
   - Cost check: ~109 FFTs of a 240-sample window is trivial on-watch. If profiling ever shows otherwise, raise hopSec — do not shrink windowSec, which would destroy frequency resolution.

   Document the exact math in a header comment; algorithmVersion is the contract. windowSec and hopSec are returned in the result and persisted per-row.

4. CoherenceEngineTests.swift in CoherenceTests/ with these named tests:
   - test_pureTenthHzSinusoid_scoresHighCoherence: synthesize an RR series whose instantaneous rate is modulated by a clean 0.1 Hz sinusoid over 120 s; assert coherenceScore > 0.7 and abs(peakFrequencyHz - 0.1) < 0.02.
   - test_randomNoise_scoresLowCoherence: white-noise RR over 120 s; assert coherenceScore < 0.3.
   - test_tooShortSeries_returnsNilScore: ~20 s of RR; assert coherenceScore == nil AND heartRateTimeseries is EMPTY (no window fits) — assert this does not crash, and meanHR is still computed.
   - test_timeseriesAlignment: assert heartRateTimeseries.count == hrvTimeseries.count == coherenceTimeseries.count.
   - test_windowCount: 600 s of RR with windowSec=60, hopSec=5 -> assert all three arrays have count == 109 (floor((600-60)/5)+1). This test is what proves the sliding window actually slides.
   - test_knownHR: RR series of constant 1.0 s -> assert meanHR ≈ 60.
   - test_trajectoryDetectsChange: synthesize 300 s where the first half is noise and the second half is a clean 0.1 Hz sinusoid; assert coherenceTimeseries.last! > coherenceTimeseries.first! by a wide margin. This is the "when they settled in" behavior in test form.

5. Run `xcodebuild test -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 15'`. Iterate until all tests pass. Commit "Phase 3: coherence engine + unit tests".
```

### YOU DO MANUALLY
Nothing on device. This phase is deliberately hardware-free — you verify math with tests, not by meditating.

### HUMAN CHECKPOINT
- ☐ Run the test suite. **All seven tests pass.** If `test_pureTenthHzSinusoid` fails on the frequency assertion, the FFT bin-to-Hz mapping is wrong (sample rate / N mismatch) — the most common bug here.
- ☐ `test_windowCount` passes with **109**, not 10. If it's 10, the window is advancing by windowSec instead of hopSec — the whole point of this phase's change is missing.
- ☐ `test_trajectoryDetectsChange` passes. This is the single test that proves the graph will tell a story rather than draw a flat line.
- ☐ **Read the synthetic-signal tests yourself.** Confirm the 0.1 Hz test actually builds a 0.1 Hz signal and the noise test is actually noise. A passing test that tests the wrong thing is worse than no test. This is your integrity checkpoint — the product's entire claim is "the number is real."

### ROLLBACK
Tag `phase3-engine-verified`.

---

# Phase 4 — Session pipeline: trigger → capture → transfer → persist

**GOAL:** From the phone you start a real session; the Watch captures and computes; the phone receives the payload and writes Session + HeartbeatSeries + MeditationStats.

> **Pre-account users.** Accounts don't exist until Phase 7. Until then, the app creates a single local User row on first launch with `appleUserID = ""` and treats it as the current user, so `Session.userID` is never nil. At Phase 7, first successful Sign in with Apple **adopts** this row — it fills in `appleUserID`, `email`, `displayName` rather than creating a second User. Your Phase 4–6 test sessions therefore survive into the real account. Write this rule in CLAUDE.md now.

### PASTE INTO CLAUDE CODE
```
Wire the end-to-end pipeline. Respect target boundaries: capture/compute on Watch, ALL persistence on iOS.

0. Local user bootstrap (iOS): on first launch, if no User row exists, create one with appleUserID = "" plus its Preferences row. Expose a `currentUser()` accessor. Phase 7 will adopt this row at sign-in rather than creating a new one. Never create a second User while appleUserID is "".

1. WatchConnectivity: create Shared/Connectivity/SessionPayload.swift, a Codable struct { sessionID: UUID; startedAt: Date; mode: String; trackID: UUID?; durationSec: Int; healthkitUUID: String; beatCount: Int; result: CoherenceResult-flattened fields (including windowSec and hopSec); discard: Bool }. Create WCSessionManager on each side (activate WCSession).

2. Phone-side start (iOS): create Coherence/Session/SessionCoordinator.swift. On "begin", it:
   - generates a sessionID,
   - sends session params (sessionID, mode, trackID, plannedDurationSec or nil, hapticsEnabled) to the watch via WCSession (transferUserInfo; also sendMessage if reachable),
   - calls HKHealthStore().startWatchApp(with: HKWorkoutConfiguration(activityType:.mindAndBody, locationType:.unknown)) to launch/foreground the watch workout. (iOS uses HealthKit ONLY to issue this launch + request workout authorization — no biometric reads on iOS.)
   Add iOS HealthKit authorization for workoutType (share/read) needed by startWatchApp.

3. Watch-side run: on receiving params, HealthKitAuth + WorkoutManager start recording. For a timed session the WATCH owns the countdown; for open-ended it shows an End button. On end, WorkoutManager returns CapturedSeries; feed rrIntervals into CoherenceEngine.analyze (default windowSec 60, hopSec 5); assemble SessionPayload (actual elapsed duration, discard=true if elapsed < 60s); send to phone via transferUserInfo (guaranteed queued delivery).

4. Phone-side persistence: on receiving SessionPayload (iOS), in SessionCoordinator:
   - if discard OR durationSec < 60 -> write nothing, just dismiss.
   - else, in ONE ModelContext transaction: insert Session (actual duration, userID = currentUser().id), insert HeartbeatSeries (healthkitUUID, beatCount, sessionID), insert MeditationStats (all engine fields including windowSec and hopSec, algorithmVersion). No streak write — streak is derived at read time from Session dates via StreakCalculator.
   - Enforce single-writer/uniqueness in code: never create a second Stats for a sessionID.

5. Temporary Phase-4 iOS UI: a "Begin (Silence, 2 min)" button and, after the payload lands, a debug screen dumping the written Session.durationSec, Stats.coherenceScore, Stats.meanHR, Stats.coherenceTimeseries.count, and the current streak (computed via StreakCalculator over the user's Session start dates, not read from a stored row).

6. Add StreakCalculatorTests.swift in CoherenceTests/ with these named tests (pass explicit today/calendar for determinism): test_sameDayDoesNotIncrement (two sessions on the same local day -> current stays 1), test_oneDayGapContinues (consecutive days -> current increments), test_multiDayGapResets (a gap > 1 day -> current resets to the run ending at the anchor), test_longestSurvivesBreak (longest reflects the best past run even after a break), test_emptyReturnsZero (empty input -> (0, 0)).

7. Build both schemes headlessly; run engine tests. Commit "Phase 4: session pipeline".
```

### YOU DO MANUALLY
1. Run the **iOS** app on your iPhone (with the Watch paired and this build on the Watch).
2. Tap **Begin**, confirm the Watch launches into the session and taps your wrist, meditate ~2 min, let it end.

### HUMAN CHECKPOINT
- ☐ After the session, the phone debug screen shows a **Session with durationSec ≈ 120**, a **coherenceScore** (a real number or a deliberate null), a plausible **meanHR**, **Streak = 1**, and a **coherenceTimeseries.count around 13** (a 120 s session at windowSec 60 / hopSec 5). If the count is 2, the engine's hop parameter isn't reaching the Watch call site.
- ☐ If nothing appears on the phone: the payload didn't transfer — WatchConnectivity via `transferUserInfo` can lag; wait 30–60 s, then check whether `startWatchApp` even launched the watch app.
- ☐ Run a **second** session the same day → **Streak stays 1** (same-day sessions don't double it). If it goes to 2, the day-comparison is using timestamps, not local calendar days.
- ☐ End a session **under 60 seconds** → **nothing is written** and the UI dismisses cleanly. If a short session persists, the discard rule isn't firing.

### ROLLBACK
Tag `phase4-pipeline-verified`. This is the second-riskiest gate; the product exists after this.

---

# Phase 5 — Audio playback + meditation setup hierarchy

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

3. Audio: AVAudioSession configured for playback + background audio; play the selected track (or nothing for silence). For timed sessions the WATCH owns end timing; the phone runs a parallel timer only to stop/fade audio. For open-ended, audio loops until the Watch's End button signals stop over WCSession.

4. Haptics (Watch): read hapticsEnabled from the params. Fire ONE WKInterfaceDevice haptic at session start (recording confirmed) and ONE at end (time's up). NEVER mid-session. If hapticsEnabled false, fire neither.

5. Mid-meditation screen (iOS): calm, minimal, NO live biometrics (evidence comes after, not during). Show elapsed time and a Stop control. Wire Stop to end the session (phone tells Watch to end via WCSession; Watch finalizes and sends the payload).

6. Build both schemes; run tests. Commit "Phase 5: setup hierarchy + audio + haptics".
```

### YOU DO MANUALLY
1. Run iOS on iPhone (Watch paired). Walk each path: Guided, Frequency→track→duration, Nature→track→duration, Silence→duration, and one **Open-ended** session.

### HUMAN CHECKPOINT
- ☐ Guided **skips the track list** (one track) and uses the track's length. Frequency/Nature **show a list then a duration picker**. Silence shows only a duration picker. If Guided shows a list, the count==1 skip branch is missing.
- ☐ You feel **exactly one wrist tap at start and one at end**, none in between; toggling haptics off in Preferences silences both.
- ☐ An **open-ended** session runs until you tap **End on the Watch**, then audio stops on the phone. If audio keeps playing, the Watch→phone stop signal isn't landing.
- ☐ The mid-meditation screen shows **no heart rate, no coherence, no numbers** beyond elapsed time. This is a product stance, not an oversight.

### ROLLBACK
Tag `phase5-flow-complete`.

---

# Phase 6 — Meditation Logged, Calendar, Stats (pure readers)

**GOAL:** The emotional payoff and history screens — each reads storage independently, screens pass only IDs, no screen writes.

### PASTE INTO CLAUDE CODE
```
Build three READER screens (iOS). None of them writes. None receives data from another screen — each does its own SwiftData fetch; navigation passes only a sessionID or a date.

1. Meditation Logged: appears automatically when a session's payload has been persisted. Given a sessionID, it fetches Session + MeditationStats independently and renders: the headline coherenceScore (or an honest "too short to measure" when nil), and three aligned graphs (heart rate, HRV, coherence) plotted against a shared x-axis using the stored arrays directly (no recomputation). X-axis time for point i = startedAt + i*hopSec + windowSec/2 (window center) — read windowSec and hopSec from the stored row, never hardcode them. Use Swift Charts. Show started_at ("tonight at 9pm") and actual duration. Colors via AppColor.

2. Calendar: fetches all Sessions for the user, groups by started_at LOCAL day, marks days with sessions. Tapping a day opens that day's Meditation Logged (pass sessionID only — never the fetched objects). If a day has multiple sessions, show a simple list of that day's sessions first, then tap through to one. Keep the list dumb; a richer day-detail design is a later decision.

3. Stats: independent fetches — total sessions, current + longest streak (computed via StreakCalculator from the user's Sessions), most-used mode (from Session.mode), mean coherence trend. Read-only.

4. Assemble the tab bar (Calendar, Stats, Meditation Setup, Profile placeholder) — all mutually reachable. Streak displays on BOTH Calendar and Stats, computed via StreakCalculator from the user's Sessions.

5. Build; run tests. Commit "Phase 6: reader screens".
```

### YOU DO MANUALLY
1. Run iOS. Complete a fresh session and let **Meditation Logged** appear. Then open **Calendar** and **Stats**.

### HUMAN CHECKPOINT
- ☐ Meditation Logged shows **three aligned graphs sharing one x-axis**, and the coherence trajectory is a **smooth curve with dozens of points**, not a 10-point staircase. If it's a staircase, hopSec isn't being honored end to end.
- ☐ If the three graphs have different lengths, the arrays aren't sharing windowSec/hopSec — a Phase-3 alignment regression.
- ☐ Tapping today on the **Calendar** reopens that day's session in the Logged view. Kill and relaunch the app, reopen it from Calendar — data persists (SwiftData local store).
- ☐ A **null-coherence** (short) session renders "too short to measure" rather than a crash or a fake 0.

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

6. Account deletion (Apple requirement): a "Delete Account" control that (a) soft-deletes — set User.deletedAt = now, sign the user out — and (b) a purge routine that runs on app launch: find Users where deletedAt <= now - 30 days and HARD-DELETE the User row and every row FK'd to it (Preferences, Sessions, HeartbeatSeries, MeditationStats) in one transaction. HealthKit raw data is never ours (we only hold references), so no HealthKit deletion is needed.

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

---

## After Phase 7 — before TestFlight
- Replace placeholder audio with real tracks; set `algorithmVersion` intentionally if the math changed.
- Confirm `aps-environment` is `production` for release and CloudKit is deployed to the production environment in the CloudKit dashboard.
- Privacy nutrition labels: declare Health data usage; you store references, not raw biometrics — say so accurately.
- Deferred, don't reopen now: subscriptions/paywall (needs `is_premium`/`premium_expires_at` on User), Google + email/password auth (needs `auth_provider`/`provider_user_id`/`password_hash`/`email_verified` back on User, plus account-collision matching on verified email), streak freezes (`freezes_remaining`), camera-PPG, track artwork, nature-sound mixing, richer calendar day-detail view. All clean additive upgrades.

## Global conventions (enforced every phase)
- Never hardcode a hex value — every color routes through the asset catalog / `AppColor`.
- All heartbeat / HealthKit code lives in the **Watch target only** (the one exception: iOS calls `startWatchApp` to trigger, reading no biometric data).
- The three timeseries share one `windowSec`, one `hopSec`, and one index. Never hardcode either value in the UI — read them from the stored row.
- Screens read storage independently and pass only IDs; Sessions and Stats are immutable.
- Every SwiftData model stays CloudKit-safe: optional/defaulted properties, no `.unique`, no non-optional relationships.
- Uniqueness is enforced in code: one Stats per session, one User per appleUserID, one bootstrap User while appleUserID is "".
