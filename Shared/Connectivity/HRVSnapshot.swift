import Foundation

/// One session's HRV reading, plus the baseline it should be read against.
///
/// **This is SDNN, not heart coherence.** Apple computes SDNN on the Watch and
/// hands it over as a finished number; it needs none of the beat-to-beat access
/// that coherence needs and that a third-party workout cannot get. Never
/// present this as coherence, and never compare it to the RMSSD the camera path
/// used to produce: different statistic, different instrument, different scale.
///
/// A single sample is enough to be useful, because the claim is a comparison
/// against the user's own history rather than a curve. That matters: Apple
/// generates these opportunistically, so a short session may produce exactly
/// one, or none at all.
struct HRVSnapshot: Codable, Equatable {

    /// SDNN values recorded inside the session window, in milliseconds, in the
    /// order they were measured. May be empty: that is a normal outcome, not an
    /// error, and the UI must survive it.
    let sessionValuesMs: [Double]

    /// Mean SDNN over the user's recent history, excluding this session.
    /// Nil when they have too little history to compare against.
    let baselineMeanMs: Double?

    /// How many historical samples the baseline was averaged from. Shown to
    /// nobody; it exists so a baseline built from two samples can be treated
    /// with the suspicion it deserves.
    let baselineSampleCount: Int

    /// How the numbers were found, for on-device debugging without Xcode.
    /// Follows the `bellyDiagnostics` precedent that cracked belly breathing.
    let diagnostic: String?

    init(sessionValuesMs: [Double],
         baselineMeanMs: Double?,
         baselineSampleCount: Int,
         diagnostic: String? = nil) {
        self.sessionValuesMs = sessionValuesMs
        self.baselineMeanMs = baselineMeanMs
        self.baselineSampleCount = baselineSampleCount
        self.diagnostic = diagnostic
    }

    /// The session's own SDNN, or nil when the Watch produced nothing.
    var meanMs: Double? {
        guard !sessionValuesMs.isEmpty else { return nil }
        return sessionValuesMs.reduce(0, +) / Double(sessionValuesMs.count)
    }

    /// Session mean minus baseline. Positive means HRV was higher than usual,
    /// which is the direction settling moves it.
    var deltaMs: Double? {
        guard let meanMs, let baselineMeanMs else { return nil }
        return meanMs - baselineMeanMs
    }

    /// Whether there is enough here to say anything out loud. A baseline built
    /// from fewer than five samples is not a baseline, it is two numbers and an
    /// opinion.
    var isComparable: Bool {
        meanMs != nil && baselineMeanMs != nil && baselineSampleCount >= 5
    }
}
