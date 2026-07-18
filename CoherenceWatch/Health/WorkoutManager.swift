import Foundation
import HealthKit
import os

/// The finished session's analyzed result, ready to fold into a `SessionPayload`.
struct FinishedSession {
    let startedAt: Date
    let durationSec: Int
    let result: SignalResult
}

/// Runs the on-wrist workout and captures CoreMotion (stillness + belly breathing)
/// alongside it, then on finish trims transients, rebases the clock, and runs the
/// signal engine. Watch-only.
///
/// The `HKWorkoutSession` (`.mindAndBody`) keeps the app foregrounded so motion
/// keeps flowing and streams averaged HR. No live biometrics are surfaced — the
/// product stance is evidence after, not during.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    /// True while a workout session is actively collecting.
    @Published var isRunning = false
    /// Last error surfaced to the UI (nil when healthy).
    @Published var statusMessage: String?

    private let store = HealthKitAuth.store
    private let motion = MotionRecorder()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var bellyBreathing = false
    private var sessionStart: Date?
    private var hrSamples: [HRSample] = []

    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "Workout")

    /// True once the workout type is shareable — the real gate for starting.
    var isWorkoutAuthorized: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Starts a mind-and-body workout + motion capture. Returns true once
    /// collection has actually begun.
    @discardableResult
    func start(bellyBreathing: Bool) async -> Bool {
        guard !isRunning else { return false }
        self.bellyBreathing = bellyBreathing
        statusMessage = nil
        hrSamples = []
        sessionStart = nil

        guard isWorkoutAuthorized else {
            log.error("workoutType share not authorized")
            statusMessage = "Enable Workouts for Coherence: iPhone Health app → Sharing → Apps → Coherence."
            return false
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            let began: Bool = await withCheckedContinuation { cont in
                builder.beginCollection(withStart: startDate) { success, error in
                    if let error { self.log.error("beginCollection failed: \(error.localizedDescription)") }
                    cont.resume(returning: success)
                }
            }
            guard began else {
                statusMessage = "Couldn't start the session. Try again."
                teardown()
                return false
            }
            sessionStart = startDate
            isRunning = true
            motion.start()
            return true
        } catch {
            log.error("Failed to create workout session: \(error.localizedDescription)")
            statusMessage = "Session error: \(error.localizedDescription)"
            teardown()
            return false
        }
    }

    /// Ends the session, then trims edge transients, rebases the clock to 0, and
    /// runs `SignalEngine`. Returns the analyzed result, or nil if nothing ran.
    func finish() async -> FinishedSession? {
        guard let session, let builder, let startedAt = sessionStart else { return nil }
        isRunning = false
        motion.stop()
        session.end()
        _ = await finishBuilder(builder)

        let motionAll = motion.snapshot()
        let hrAll = hrSamples
        let elapsed = max(motionAll.last?.t ?? 0, hrAll.last?.t ?? 0)

        // Trim the first/last 5 s (lying down after Start, getting up before End)
        // and rebase both channels to t=0 — the engine windows from zero and does
        // not trim. Motion and HR share one session clock, so use one offset.
        let lo: Double, hi: Double
        if elapsed > 20 { lo = 5; hi = elapsed - 5 } else { lo = 0; hi = elapsed }
        let motionTrim = motionAll
            .filter { $0.t >= lo && $0.t <= hi }
            .map { MotionSample(t: $0.t - lo, pitch: $0.pitch, roll: $0.roll, userAccel: $0.userAccel) }
        let hrTrim = hrAll
            .filter { $0.t >= lo && $0.t <= hi }
            .map { HRSample(t: $0.t - lo, bpm: $0.bpm) }

        let result = SignalEngine.analyze(motion: motionTrim, hr: hrTrim, bellyBreathing: bellyBreathing)
        let durationSec = Int(elapsed.rounded())
        log.debug("Finished: \(durationSec)s, motion=\(motionAll.count) hr=\(hrAll.count) overall=\(String(describing: result.overallScore))")
        teardown()
        return FinishedSession(startedAt: startedAt, durationSec: durationSec, result: result)
    }

    /// Drops references and marks the manager idle so a fresh `start()` can run.
    private func teardown() {
        isRunning = false
        session = nil
        builder = nil
    }

    private func finishBuilder(_ builder: HKLiveWorkoutBuilder) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { workout, _ in
                    continuation.resume(returning: workout)
                }
            }
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }
        let stats = workoutBuilder.statistics(for: hrType)
        let bpm = stats?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let sampleTime = stats?.mostRecentQuantityDateInterval()?.start
        Task { @MainActor in
            guard let bpm, let sampleTime, let start = self.sessionStart else { return }
            let t = sampleTime.timeIntervalSince(start)
            if self.hrSamples.last?.t != t {
                self.hrSamples.append(HRSample(t: t, bpm: bpm))
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.log.debug("Workout session \(fromState.rawValue) -> \(toState.rawValue)")
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.log.error("Workout session failed: \(error.localizedDescription)")
            self.statusMessage = "Workout failed: \(error.localizedDescription)"
            self.teardown()
        }
    }
}
