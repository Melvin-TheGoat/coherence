import Foundation
import HealthKit

/// HealthKit authorization for the Watch. All HealthKit code lives in the Watch
/// target — the iOS target only calls `startWatchApp` (Phase 4) and reads no
/// biometric data.
///
/// Minimal scope for the motion-based model: heart-rate READ (the deceleration
/// signal) + workout SHARE (to run the `.mindAndBody` session that keeps the app
/// active and streams HR). No HRV / heartbeat-series — those were for the dropped
/// coherence path.
enum HealthKitAuth {

    /// The single store instance the Watch uses for auth and workouts.
    static let store = HKHealthStore()

    /// Types we READ: live heart rate and workouts.
    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKObjectType.workoutType(),
        ]
    }

    /// Types we SHARE (write): the workout we record during a session.
    private static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    /// Requests authorization. Returns `true` if HealthKit is available and the
    /// prompt completed without error. The user's per-type grant/deny choices are
    /// private to HealthKit and deliberately not surfaced here.
    @discardableResult
    static func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }
}
