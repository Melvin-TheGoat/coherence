import XCTest
@testable import Coherence

/// `HRVSnapshot`'s arithmetic and, more importantly, its refusals.
///
/// The whole reason HRV is worth reading is that a single SDNN sample means
/// something when compared to the user's own history. That makes the guards
/// here load-bearing: they decide when we're allowed to say anything at all.
final class HRVSnapshotTests: XCTestCase {

    private func snap(_ session: [Double],
                      baseline: Double? = nil,
                      n: Int = 0) -> HRVSnapshot {
        HRVSnapshot(sessionValuesMs: session, baselineMeanMs: baseline, baselineSampleCount: n)
    }

    // MARK: - The empty case is normal, not an error

    func test_noSamples_yieldsNilRatherThanZero() {
        // Apple generates SDNN opportunistically, so a short session producing
        // nothing is an expected outcome. Reporting 0 ms would be a false
        // reading, and 0 is a physiologically impossible SDNN.
        let s = snap([])
        XCTAssertNil(s.meanMs)
        XCTAssertNil(s.deltaMs)
        XCTAssertFalse(s.isComparable)
    }

    func test_meanIsAveragedAcrossSamples() {
        XCTAssertEqual(snap([40, 50, 60]).meanMs!, 50, accuracy: 0.001)
        XCTAssertEqual(snap([42]).meanMs!, 42, accuracy: 0.001)
    }

    // MARK: - The comparison, which is the actual product claim

    func test_deltaIsSessionMinusBaseline_positiveMeaningCalmer() {
        // Settling raises HRV, so a positive delta is the good direction. If
        // this ever flips sign the copy above it becomes a lie.
        let s = snap([60], baseline: 45, n: 20)
        XCTAssertEqual(s.deltaMs!, 15, accuracy: 0.001)

        let worse = snap([30], baseline: 45, n: 20)
        XCTAssertEqual(worse.deltaMs!, -15, accuracy: 0.001)
    }

    func test_deltaIsNilWithoutABaseline() {
        // A first-ever session has no history to compare against, and inventing
        // a comparison is the one thing this product cannot do.
        XCTAssertNil(snap([55], baseline: nil, n: 0).deltaMs)
    }

    // MARK: - When we're allowed to speak

    func test_notComparableOnAThinBaseline() {
        // Four samples is not a baseline. The threshold exists so a user's
        // second-ever session can't be told their HRV is "up 12 ms" against
        // a mean of two numbers.
        XCTAssertFalse(snap([55], baseline: 45, n: 4).isComparable)
        XCTAssertTrue(snap([55], baseline: 45, n: 5).isComparable)
    }

    func test_notComparableWhenTheSessionItselfIsEmpty() {
        // Plenty of history, nothing measured today.
        XCTAssertFalse(snap([], baseline: 45, n: 100).isComparable)
    }

    // MARK: - Contract

    func test_survivesEncodingRoundTrip() {
        // It crosses WatchConnectivity as JSON. A belly payload was once
        // silently dropped because a non-finite Double made the encoder throw,
        // so the transfer contract gets a test.
        let original = HRVSnapshot(sessionValuesMs: [41.2, 58.9],
                                   baselineMeanMs: 46.5,
                                   baselineSampleCount: 31,
                                   diagnostic: "live=1 total=2")
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(HRVSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_payloadWithoutHRVStillDecodes() {
        // Backward compatibility: a Watch on an older build sends no `hrv` key,
        // and the phone must not reject the whole session over it.
        let json = """
        {"sessionID":"\(UUID().uuidString)","startedAt":0,"mode":"silence",
         "bellyBreathing":false,"durationSec":120,"discard":false}
        """.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(SessionPayload.self, from: json)
        XCTAssertNotNil(decoded, "a payload with no hrv key must still decode")
        XCTAssertNil(decoded?.hrv)
    }
}
