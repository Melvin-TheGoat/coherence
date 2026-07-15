import Foundation
import HealthKit
import os

/// Runs the on-wrist workout for a meditation session, publishes the live heart
/// rate, and on end reads back the beat-to-beat series. Watch-only.
///
/// Phase 1 proved live BPM. Phase 2 adds RR-interval readback: after the workout
/// finishes, query the recorded `HKHeartbeatSeriesSample` and convert per-beat
/// timestamps into RR intervals. Still NO timer, haptics, or persistence — those
/// arrive in later phases.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    /// Most recent heart rate in beats/min, or nil before the first sample.
    @Published var currentHR: Double?
    /// True while a workout session is actively collecting.
    @Published var isRunning = false
    /// Last error surfaced to the UI (nil when healthy). Debug aid.
    @Published var statusMessage: String?
    /// Cadence of the HR samples the live builder surfaced (option-4 measurement).
    @Published var samplingReport: String?
    /// Cadence of the HR samples HealthKit actually STORED for the workout —
    /// often denser than the live callback. Tests the "wait for it to populate"
    /// idea: a smoother trajectory, though never beat-to-beat / HRV.
    @Published var storedReport: String?

    private let store = HealthKitAuth.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Distinct timestamps of the HR samples the builder surfaced this session,
    /// used to measure how finely the Watch samples heart rate while seated.
    private var hrSampleTimes: [Date] = []

    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "Workout")

    /// Starts a mind-and-body workout session and begins live collection.
    func start() {
        guard !isRunning else { return }
        statusMessage = nil
        samplingReport = nil
        storedReport = nil
        hrSampleTimes = []

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
                        self.isRunning = true
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

    /// Ends the session and finishes the workout, then summarizes how finely the
    /// Watch sampled heart rate this session — the measurement that tells us
    /// whether averaged HR is dense enough for the option-4 trajectory.
    func end() async {
        guard let session, let builder else { return }
        isRunning = false
        statusMessage = nil

        session.end()
        let workout = await finish(builder)
        currentHR = nil
        teardown()

        guard let workout else {
            statusMessage = "Workout didn't finish"
            return
        }
        samplingReport = cadenceSummary("live", hrSampleTimes)
        let storedTimes = await storedHRSampleTimes(from: workout.startDate, to: workout.endDate)
        storedReport = cadenceSummary("stored", storedTimes)
    }

    /// Drops references and marks the manager idle so a fresh `start()` can run.
    private func teardown() {
        isRunning = false
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

    /// Summarizes the spacing between a set of HR sample timestamps: count, span,
    /// and mean/min/max gap between consecutive samples.
    private func cadenceSummary(_ label: String, _ times: [Date]) -> String {
        let sorted = times.sorted()
        guard sorted.count >= 2 else {
            return "\(label): \(sorted.count) samples — too few"
        }
        var gaps: [Double] = []
        gaps.reserveCapacity(sorted.count - 1)
        for i in 1..<sorted.count {
            gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]))
        }
        let span = sorted.last!.timeIntervalSince(sorted.first!)
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        return String(
            format: "%@: %d / %.0fs\n  gap ~%.1fs (min %.1f max %.1f)",
            label, sorted.count, span, mean, gaps.min() ?? 0, gaps.max() ?? 0
        )
    }

    /// The timestamps of every heart-rate measurement HealthKit STORED for the
    /// workout window, expanded from its series-backed samples. Denser than the
    /// live callback when the watch batched deliveries.
    private func storedHRSampleTimes(from start: Date, to end: Date) async -> [Date] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { (continuation: CheckedContinuation<[Date], Never>) in
            var times: [Date] = []
            var finished = false
            let query = HKQuantitySeriesSampleQuery(quantityType: hrType, predicate: predicate) { _, _, dateInterval, _, done, _ in
                if finished { return }
                if let dateInterval { times.append(dateInterval.start) }
                if done {
                    finished = true
                    continuation.resume(returning: times)
                }
            }
            store.execute(query)
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
            self.currentHR = bpm
            // Record each distinct sample timestamp to measure sampling cadence.
            if let sampleTime, self.hrSampleTimes.last != sampleTime {
                self.hrSampleTimes.append(sampleTime)
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
