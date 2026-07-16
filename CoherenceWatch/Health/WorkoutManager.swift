import Foundation
import HealthKit
import os

/// A downsampled pitch point for plotting the belly-breathing waveform.
struct PitchPoint: Identifiable {
    let id: Int
    let t: Double
    let pitch: Double
}

/// What the Watch captured this session — Phase-2 debug summary shown after end.
struct CaptureSummary {
    let motionCount: Int
    let hrCount: Int
    let bellyBreathing: Bool
    let finalBreaths: Double?      // nil = no clear breathing signal
    let pitchSeries: [PitchPoint]
}

/// Runs the on-wrist workout, streams live heart rate, and captures CoreMotion
/// (stillness + belly breathing) alongside it. Watch-only.
///
/// The `HKWorkoutSession` (`.mindAndBody`) keeps the app foregrounded so motion
/// keeps flowing and streams averaged HR. On end it assembles the raw capture;
/// the Phase-3 signal engine turns it into stillness / HR-decline / breathing.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    /// Most recent heart rate in beats/min, or nil before the first sample.
    @Published var currentHR: Double?
    /// True while a workout session is actively collecting.
    @Published var isRunning = false
    /// Live breaths/min estimate (belly sessions only); nil when unreadable.
    @Published var liveBreaths: Double?
    /// Post-session capture summary (Phase-2 debug UI).
    @Published var capture: CaptureSummary?
    /// Last error surfaced to the UI (nil when healthy). Debug aid.
    @Published var statusMessage: String?

    private let store = HealthKitAuth.store
    private let motion = MotionRecorder()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var bellyBreathing = false
    private var sessionStart: Date?
    private var hrSamples: [(t: TimeInterval, bpm: Double)] = []
    private var liveTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "Workout")

    /// Starts a mind-and-body workout + motion capture. `bellyBreathing` enables
    /// the live breaths/min readout and (later) the breathing analysis.
    func start(bellyBreathing: Bool) {
        guard !isRunning else { return }
        self.bellyBreathing = bellyBreathing
        statusMessage = nil
        liveBreaths = nil
        capture = nil
        hrSamples = []
        sessionStart = nil

        // Recording a workout needs WRITE access to the workout type. Read grants
        // are opaque by design, but share status is readable — check it up front
        // so a missing "Workouts" toggle names itself instead of surfacing as a
        // generic "Not authorized" from beginCollection.
        let shareStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        guard shareStatus == .sharingAuthorized else {
            log.error("workoutType share not authorized (status \(shareStatus.rawValue))")
            statusMessage = "Enable Workouts for Coherence: iPhone Health app → Sharing → Apps → Coherence."
            return
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
            builder.beginCollection(withStart: startDate) { [weak self] success, error in
                Task { @MainActor in
                    guard let self else { return }
                    if success {
                        self.sessionStart = startDate
                        self.isRunning = true
                        self.motion.start()
                        self.startLiveLoop()
                    } else {
                        self.log.error("beginCollection failed: \(String(describing: error))")
                        self.statusMessage = "Start failed: \(error?.localizedDescription ?? "unknown")"
                        self.teardown()
                    }
                }
            }
        } catch {
            log.error("Failed to create workout session: \(error.localizedDescription)")
            statusMessage = "Session error: \(error.localizedDescription)"
            isRunning = false
        }
    }

    /// Ends the session, stops capture, and assembles the raw capture summary.
    func end() async {
        guard let session, let builder else { return }
        isRunning = false
        statusMessage = nil
        liveTask?.cancel()
        liveTask = nil
        motion.stop()

        session.end()
        _ = await finish(builder)
        currentHR = nil

        let samples = motion.snapshot()
        let finalBreaths = bellyBreathing
            ? BreathingEstimator.breathsPerMinute(samples, windowSec: .greatestFiniteMagnitude)
            : nil
        capture = CaptureSummary(
            motionCount: samples.count,
            hrCount: hrSamples.count,
            bellyBreathing: bellyBreathing,
            finalBreaths: finalBreaths,
            pitchSeries: downsample(samples, maxPoints: 120)
        )
        log.debug("Captured \(samples.count) motion, \(self.hrSamples.count) HR; breaths=\(String(describing: finalBreaths))")
        teardown()
    }

    /// Recomputes the live breaths/min estimate every 2 s for belly sessions.
    private func startLiveLoop() {
        guard bellyBreathing else { return }
        liveTask = Task { @MainActor [weak self] in
            while let self, self.isRunning {
                self.liveBreaths = BreathingEstimator.breathsPerMinute(self.motion.snapshot())
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Drops references and marks the manager idle so a fresh `start()` can run.
    private func teardown() {
        isRunning = false
        liveTask?.cancel()
        liveTask = nil
        session = nil
        builder = nil
    }

    /// Ends collection and finishes the builder, returning the saved `HKWorkout`.
    private func finish(_ builder: HKLiveWorkoutBuilder) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { workout, _ in
                    continuation.resume(returning: workout)
                }
            }
        }
    }

    /// Evenly thins the pitch series to at most `maxPoints` for plotting.
    private func downsample(_ samples: [MotionSample], maxPoints: Int) -> [PitchPoint] {
        guard !samples.isEmpty else { return [] }
        let step = Swift.max(1, samples.count / maxPoints)
        var out: [PitchPoint] = []
        var i = 0
        while i < samples.count {
            out.append(PitchPoint(id: out.count, t: samples[i].t, pitch: samples[i].pitch))
            i += step
        }
        return out
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
            self.currentHR = bpm
            if let bpm, let sampleTime, let start = self.sessionStart {
                let t = sampleTime.timeIntervalSince(start)
                if self.hrSamples.last?.t != t {
                    self.hrSamples.append((t, bpm))
                }
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
