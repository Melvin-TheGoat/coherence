import XCTest
import HealthKit
@testable import Coherence

/// The scope is the promise. The privacy policy, the Info.plist strings and
/// the App Privacy labels all enumerate these exact types, so a type added
/// here without updating those is a false statement to the user, and a type
/// silently dropped is a signal that stops arriving with no error anywhere.
final class HealthScopeTests: XCTestCase {

    func test_readScopeIsExactlyHeartRateHRVAndWorkouts() {
        XCTAssertEqual(HealthScope.read, [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKObjectType.workoutType(),
        ])
    }

    /// `heartbeatSeries` is the beat-to-beat series the dropped coherence path
    /// needed. A third-party workout cannot get it (verified on device), and
    /// asking would put a permission in front of the user that buys nothing.
    func test_neverAsksForTheHeartbeatSeries() {
        let series = HKObjectType.seriesType(forIdentifier: HKDataTypeIdentifierHeartbeatSeries)
        XCTAssertNotNil(series)
        XCTAssertFalse(HealthScope.read.contains(series!))
    }

    func test_shareScopeIsWorkoutsAndMindfulMinutes() {
        var expected: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            expected.insert(mindful)
        }
        XCTAssertEqual(HealthScope.share, expected)
    }

    /// Reading stays on the Watch. Holding authorization is not reading, but
    /// the moment the phone queries a sample the architecture note in
    /// CLAUDE.md stops being true and the privacy policy needs rewriting.
    func test_theiOSTargetQueriesNoHealthData() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let phone = root.appendingPathComponent("Coherence")
        let queries = ["HKSampleQuery", "HKAnchoredObjectQuery", "HKStatisticsQuery",
                       "HKObserverQuery", "HKQuantitySeriesSampleQuery", "HKWorkoutSession"]
        let files = FileManager.default.enumerator(at: phone, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "found no iOS sources to scan")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            // The AirPods probe (Coherence/AirPods/, 2026-09-14) is the one
            // deliberate exception: a DEBUG-only hardware spike for the
            // no-Watch path that reads AirPods heart rate on the phone. The
            // exemption is exactly as wide as `#if DEBUG`: every file in that
            // folder must open with it and close with `#endif`, so the Release
            // binary still contains no HealthKit read on iOS.
            if file.path.contains("/Coherence/AirPods/") {
                let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertTrue(trimmed.hasPrefix("#if DEBUG"),
                              "\(file.lastPathComponent) must start with #if DEBUG")
                XCTAssertTrue(trimmed.hasSuffix("#endif"),
                              "\(file.lastPathComponent) must end with #endif")
                continue
            }
            for query in queries {
                XCTAssertFalse(source.contains(query),
                               "\(file.lastPathComponent) reads HealthKit (\(query)); "
                               + "all biometric reads belong to the Watch target")
            }
        }
    }
}
