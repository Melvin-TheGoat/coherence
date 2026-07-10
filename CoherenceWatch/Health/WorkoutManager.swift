import Foundation
import HealthKit

/// Runs the on-wrist workout for a meditation session and publishes the live
/// heart rate. Watch-only.
///
/// Phase 1 scope: start an `HKWorkoutSession` + `HKLiveWorkoutBuilder`
/// (`.mindAndBody`) and surface the most recent BPM. Deliberately NO timer, NO
/// haptics, NO RR-interval readback, NO persistence — those arrive in later
/// phases. This phase exists to prove permissions + entitlements + an on-device
/// workout only.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    /// Most recent heart rate in beats/min, or nil before the first sample.
    @Published var currentHR: Double?
    /// True while a workout session is actively collecting.
    @Published var isRunning = false

    private let store = HealthKitAuth.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Starts a mind-and-body workout session and begins live collection.
    func start() {
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
            builder.beginCollection(withStart: startDate) { [weak self] _, _ in
                Task { @MainActor in self?.isRunning = true }
            }
        } catch {
            isRunning = false
        }
    }

    /// Ends the session and tears down the builder. Phase 1 discards the result;
    /// RR-interval readback from the finished workout arrives in Phase 2.
    func end() {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.finishWorkout { _, _ in }
            Task { @MainActor in
                self?.isRunning = false
                self?.currentHR = nil
                self?.session = nil
                self?.builder = nil
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
    ) {}

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in self.isRunning = false }
    }
}
