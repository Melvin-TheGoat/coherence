import Foundation
import SwiftData

/// iOS-side persistence for the session pipeline — pure functions over a passed-in
/// `ModelContext`.
///
/// The Watch never calls these (all writes happen on the phone, per the target
/// boundary), but the type lives in `Shared` so it compiles into the test target
/// for headless verification. The iOS `SessionCoordinator` (WatchConnectivity +
/// `startWatchApp`) is the only caller.
///
/// Streak is NOT written here — it's derived at read time from Session dates via
/// `StreakCalculator`.
enum SessionStore {

    /// Sessions shorter than this are treated as accidental and never written.
    static let minDurationSec = 30

    /// The single bootstrap `User` (`appleUserID == ""`), created with its
    /// `Preferences` on first call. Never creates a second User while
    /// `appleUserID` is `""` — Phase 7 sign-in adopts this row instead.
    @discardableResult
    static func currentUser(in context: ModelContext) -> User {
        let bootstrapID = ""
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.appleUserID == bootstrapID }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let user = User(appleUserID: "")
        let prefs = Preferences(userID: user.id)
        context.insert(user)
        context.insert(prefs)
        try? context.save()
        return user
    }

    /// Persists a finished session + its stats in ONE save. Idempotent: never
    /// writes a second `MeditationStats`/`Session` for a `sessionID`; skips
    /// discarded, too-short, or result-less payloads. Returns the written
    /// `Session`, or `nil` if nothing was written.
    @discardableResult
    static func persist(_ payload: SessionPayload, in context: ModelContext) -> Session? {
        guard !payload.discard,
              payload.durationSec >= minDurationSec,
              let result = payload.result else { return nil }

        // Idempotency: bail if a Stats already exists for this session.
        let sid = payload.sessionID
        let statsDescriptor = FetchDescriptor<MeditationStats>(
            predicate: #Predicate { $0.sessionID == sid }
        )
        if let existing = try? context.fetch(statsDescriptor), !existing.isEmpty {
            return nil
        }

        let user = currentUser(in: context)

        let session = Session(
            id: payload.sessionID,
            userID: user.id,
            trackID: payload.trackID,
            mode: payload.mode,
            bellyBreathing: payload.bellyBreathing,
            startedAt: payload.startedAt,
            durationSec: payload.durationSec
        )
        let stats = MeditationStats(
            sessionID: payload.sessionID,
            heartRateTimeseries: result.heartRateTimeseries,
            meanHR: result.meanHR,
            startHR: result.startHR,
            endHR: result.endHR,
            hrDecline: result.hrDecline,
            stillnessTimeseries: result.stillnessTimeseries,
            stillnessScore: result.stillnessScore,
            stillnessMethod: result.stillnessMethod,
            breathingRateTimeseries: result.breathingRateTimeseries,
            breathDepthTimeseries: result.breathDepthTimeseries,
            meanBreathingRate: result.meanBreathingRate,
            breathingRegularity: result.breathingRegularity,
            resonanceMatchScore: result.resonanceMatchScore,
            overallScore: result.overallScore,
            windowSec: result.windowSec,
            hopSec: result.hopSec,
            algorithmVersion: result.algorithmVersion
        )
        context.insert(session)
        context.insert(stats)
        try? context.save()
        return session
    }

    /// All session start dates for the store (feeds `StreakCalculator`).
    static func sessionStartDates(in context: ModelContext) -> [Date] {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(descriptor))?.map(\.startedAt) ?? []
    }
}
