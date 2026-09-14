import Foundation
import HealthKit

/// Exactly what 808 asks HealthKit for, in one place.
///
/// **Both targets ask for the same thing, and that is the point.** The Watch
/// and the phone each used to own their own list, which is the shape of a bug
/// that only shows up as missing data: the Watch asks for HRV, the phone does
/// not, and one type sits unauthorized while everything else works.
///
/// **Authorization is SHARED between an iOS app and its companion watchOS app,
/// and the system can only present the prompt on the iPhone** (Apple, WWDC 2016
/// session 209, still true). So the phone is the right place to ask, and the
/// Watch's request is the fallback for a Watch-first install.
///
/// Reading still happens only on the Watch. Holding authorization is not
/// reading: the iOS target queries no biometric data anywhere, which is the
/// architecture rule in CLAUDE.md and remains true.
enum HealthScope {

    /// Live heart rate (the deceleration signal), HRV SDNN (the dormant
    /// baseline pipeline), and workouts. Never `heartbeatSeries`: that one is
    /// genuinely unavailable to a third-party workout.
    static var read: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKObjectType.workoutType(),
        ]
    }

    /// The workout that keeps the Watch measuring, and the mindful minutes a
    /// session writes so 808 shows up in Health beside Apple's own.
    static var share: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        return types
    }

    /// Asks for the whole scope at once. Returns `true` when HealthKit is
    /// available and the prompt completed without error; the user's per-type
    /// answers are private to HealthKit and deliberately not reported.
    @discardableResult
    static func request(using store: HKHealthStore = HKHealthStore()) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }
}
