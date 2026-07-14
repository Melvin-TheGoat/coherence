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
    /// The beat-to-beat readback from the most recent session (Phase 2 debug UI).
    @Published var captured: CapturedSeries?

    private let store = HealthKitAuth.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "Workout")

    /// Starts a mind-and-body workout session and begins live collection.
    func start() {
        guard !isRunning else { return }
        statusMessage = nil

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

    /// Ends the session, finishes the workout, then reads back the recorded
    /// heartbeat series as RR intervals. Returns nil (and sets `statusMessage`)
    /// when no series was recorded — the make-or-break outcome of this phase.
    @discardableResult
    func end() async -> CapturedSeries? {
        guard let session, let builder else { return nil }
        isRunning = false
        statusMessage = nil
        captured = nil

        session.end()
        let workout = await finish(builder)
        currentHR = nil
        teardown()

        guard let workout else {
            statusMessage = "Workout didn't finish"
            return nil
        }

        guard let series = await heartbeatSeries(for: workout) else {
            log.error("No HKHeartbeatSeriesSample in \(workout.startDate)–\(workout.endDate)")
            statusMessage = "NO SERIES"
            return nil
        }

        let readback = await readIntervals(from: series)
        let result = CapturedSeries(
            rrIntervals: readback.rr,
            healthkitUUID: series.uuid.uuidString,
            beatCount: readback.count
        )
        captured = result
        log.debug("Captured \(result.beatCount) beats, \(result.rrIntervals.count) RR intervals")
        if result.beatCount == 0 { statusMessage = "NO SERIES" }
        return result
    }

    /// Drops references and marks the manager idle so a fresh `start()` can run.
    private func teardown() {
        isRunning = false
        session = nil
        builder = nil
    }

    // MARK: - Readback

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

    /// Finds the heartbeat series recorded during the workout. HealthKit can lag
    /// a second or two persisting the series after `finishWorkout`, so retry a
    /// few times before concluding there is none.
    private func heartbeatSeries(for workout: HKWorkout, attempts: Int = 5) async -> HKHeartbeatSeriesSample? {
        for attempt in 0..<attempts {
            if let series = await querySeries(from: workout.startDate, to: workout.endDate) {
                return series
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return nil
    }

    /// One-shot query for the most recent heartbeat series in a date window.
    private func querySeries(from start: Date, to end: Date) async -> HKHeartbeatSeriesSample? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKHeartbeatSeriesSample])?.first)
            }
            store.execute(query)
        }
    }

    /// Enumerates the series beat-by-beat, converting time-since-series-start
    /// values into RR intervals (seconds). Intervals that span a recorded gap are
    /// dropped so downstream analysis never sees a bogus multi-second interval.
    private func readIntervals(from series: HKHeartbeatSeriesSample) async -> (rr: [Double], count: Int) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(rr: [Double], count: Int), Never>) in
            var previous: TimeInterval?
            var rr: [Double] = []
            var count = 0
            var finished = false

            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                if finished { return }
                if error != nil || done {
                    finished = true
                    continuation.resume(returning: (rr, count))
                    return
                }
                count += 1
                if let previous, !precededByGap {
                    rr.append(timeSinceStart - previous)
                }
                previous = timeSinceStart
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
        let bpm = workoutBuilder
            .statistics(for: hrType)?
            .mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.currentHR = bpm }
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
