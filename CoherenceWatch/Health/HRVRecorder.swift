import Foundation
import HealthKit
import os

/// Collects Apple's HRV (SDNN) samples for one session, plus the user's recent
/// baseline to read them against. Watch-only, like every other sensor path.
///
/// **Two collection routes on purpose, and both are needed.**
///
/// A live anchored query runs for the length of the session and catches samples
/// as HealthKit writes them. Then `snapshot(end:)` runs a second, one-shot
/// query over the same window after a short settle, because the Watch can write
/// a sample for the session several seconds *after* the workout has ended, and a
/// query fired the instant we stop would miss it and report zero.
///
/// A false zero here is the expensive failure. It would read as "HRV doesn't
/// work on the Watch", which is exactly the wrong conclusion we already drew
/// once by confusing SDNN with beat-to-beat coherence. The diagnostic string
/// records which route found what, so a zero can be trusted as a real zero.
@MainActor
final class HRVRecorder {

    private let store = HealthKitAuth.store
    private let type = HKQuantityType(.heartRateVariabilitySDNN)
    private let unit = HKUnit.secondUnit(with: .milli)
    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "HRV")

    /// Keyed by sample UUID so the live and catch-up routes can be merged
    /// without double-counting the samples both of them see.
    private var found: [UUID: HKQuantitySample] = [:]
    private var liveCount = 0
    private var query: HKAnchoredObjectQuery?
    private var reference: Date?

    /// How long the system is given to flush a session's sample before we look.
    private static let settle: Duration = .seconds(3)

    /// How far back the baseline reaches. Long enough to survive a quiet week,
    /// short enough that it tracks a changing body.
    private static let baselineDays: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Lifecycle

    func start(reference: Date) {
        stop()
        found = [:]
        liveCount = 0
        self.reference = reference

        let predicate = HKQuery.predicateForSamples(withStart: reference, end: nil,
                                                    options: .strictStartDate)
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate,
                                      anchor: nil, limit: HKObjectQueryNoLimit) {
            [weak self] _, samples, _, _, _ in
            self?.absorb(samples, live: true)
        }
        q.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.absorb(samples, live: true)
        }
        store.execute(q)
        query = q
    }

    func stop() {
        if let query { store.stop(query) }
        query = nil
    }

    private nonisolated func absorb(_ samples: [HKSample]?, live: Bool) {
        guard let samples else { return }
        Task { @MainActor in
            for case let s as HKQuantitySample in samples where self.found[s.uuid] == nil {
                self.found[s.uuid] = s
                if live { self.liveCount += 1 }
            }
        }
    }

    // MARK: - Result

    /// Ends collection and returns what the session produced. Never nil: an
    /// empty reading is a real answer and the diagnostic explains it.
    func snapshot(end: Date) async -> HRVSnapshot {
        guard let reference else {
            return HRVSnapshot(sessionValuesMs: [], baselineMeanMs: nil,
                               baselineSampleCount: 0, diagnostic: "no session start")
        }

        // Let the system finish writing before deciding there is nothing there.
        try? await Task.sleep(for: Self.settle)
        stop()

        let live = liveCount
        let catchUp = await query(from: reference, to: end.addingTimeInterval(120))
        for s in catchUp where found[s.uuid] == nil { found[s.uuid] = s }

        // Order by measurement time, not by which route found them.
        let session = found.values
            .filter { $0.startDate >= reference && $0.startDate <= end.addingTimeInterval(120) }
            .sorted { $0.startDate < $1.startDate }
        let values = session.map { $0.quantity.doubleValue(for: unit) }

        let history = await query(from: reference.addingTimeInterval(-Self.baselineDays),
                                  to: reference)
        let baselineValues = history.map { $0.quantity.doubleValue(for: unit) }
        let baseline = baselineValues.isEmpty
            ? nil : baselineValues.reduce(0, +) / Double(baselineValues.count)

        let diagnostic = "live=\(live) total=\(values.count) "
            + "vals=\(values.map { String(format: "%.0f", $0) }.joined(separator: ","))"
            + " base=\(baseline.map { String(format: "%.1f", $0) } ?? "nil")/\(baselineValues.count)"
        log.debug("HRV \(diagnostic)")

        return HRVSnapshot(sessionValuesMs: values,
                           baselineMeanMs: baseline,
                           baselineSampleCount: baselineValues.count,
                           diagnostic: diagnostic)
    }

    private func query(from: Date, to: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to,
                                                    options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                     ascending: true)]) { _, samples, error in
                if let error { self.log.error("HRV query failed: \(error.localizedDescription)") }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }
}
