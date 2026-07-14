import Foundation
import HealthKit
import os

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
    /// Last error surfaced to the UI (nil when healthy). Phase 1 debug aid.
    @Published var statusMessage: String?

    private let store = HealthKitAuth.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "Workout")

    /// Starts a mind-and-body workout session and begins live collection.
    func start() {
        guard !isRunning else { return }
        statusMessage = nil

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

    /// Ends the session and tears down the builder. Phase 1 discards the result;
    /// RR-interval readback from the finished workout arrives in Phase 2.
    func end() {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.finishWorkout { _, _ in }
            Task { @MainActor in
                self?.currentHR = nil
                self?.teardown()
            }
        }
    }

    /// Drops references and marks the manager idle so a fresh `start()` can run.
    private func teardown() {
        isRunning = false
        session = nil
        builder = nil
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
