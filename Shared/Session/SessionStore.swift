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

    /// Signs in with an Apple credential and marks onboarding complete. Account
    /// matching, in order (Phase-7 rule): (a) an existing User with this
    /// `appleUserID` → sign in as them; (b) else ADOPT the bootstrap User
    /// (`appleUserID == ""`) — fill in its identity so pre-account sessions +
    /// streak survive; (c) else create a new User. Never creates a second User
    /// while a bootstrap exists. Returns the signed-in User.
    @discardableResult
    static func signIn(appleUserID: String, email: String?, displayName: String?, in context: ModelContext) -> User {
        // a. Returning user? (Clear any pending soft-delete — signing back in
        // reactivates the account.)
        let byApple = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID == appleUserID })
        if let user = try? context.fetch(byApple).first {
            user.deletedAt = nil
            markOnboardingComplete(userID: user.id, in: context)
            try? context.save()
            return user
        }
        // b. Adopt the bootstrap row (Apple gives name/email only on first sign-in,
        // so only overwrite when provided).
        let bootstrapID = ""
        let byBootstrap = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID == bootstrapID })
        if let user = try? context.fetch(byBootstrap).first {
            user.appleUserID = appleUserID
            if let email { user.email = email }
            if let displayName { user.displayName = displayName }
            user.deletedAt = nil
            user.updatedAt = Date()
            markOnboardingComplete(userID: user.id, in: context)
            try? context.save()
            return user
        }
        // c. Fresh account.
        let user = User(appleUserID: appleUserID, email: email, displayName: displayName)
        context.insert(user)
        context.insert(Preferences(userID: user.id, onboardingComplete: true))
        try? context.save()
        return user
    }

    /// Dev/local-only path to leave onboarding without a real account (keeps the
    /// bootstrap User). Release builds gate on real sign-in.
    static func completeOnboardingWithoutSignIn(in context: ModelContext) {
        let user = currentUser(in: context)
        markOnboardingComplete(userID: user.id, in: context)
        try? context.save()
    }

    /// Signs out — re-gates to onboarding, preserving all data. Next sign-in
    /// re-adopts by appleUserID.
    static func signOut(in context: ModelContext) {
        for prefs in (try? context.fetch(FetchDescriptor<Preferences>())) ?? [] {
            prefs.onboardingComplete = false
            OnboardingResume.clear()
            prefs.updatedAt = Date()
        }
        try? context.save()
    }

    /// Soft-deletes the signed-in account (Apple requirement): stamps `deletedAt`
    /// and signs out. The launch-time `purgeExpired` hard-deletes after 30 days.
    static func softDeleteCurrentUser(now: Date = Date(), in context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let target = users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
        target?.deletedAt = now
        target?.updatedAt = now
        signOut(in: context)
    }

    /// Deletes one session and every row keyed to it (stats, reflection).
    /// Returns whether a session with that id existed.
    ///
    /// Sessions are immutable, and this is not an edit: it is the user
    /// removing a row they never meant to create (Melvin, 2026-09-15: "we
    /// create ones and immediately end them"). The Watch already refuses
    /// anything under `minDurationSec`; this covers the junk that clears the
    /// bar. Streak, awards and the sparkline all derive from the sessions at
    /// read time, so they correct themselves. What it does NOT touch: the
    /// workout and mindful minutes the Watch wrote into Health, which belong
    /// to the user's Health record, not to 808.
    @discardableResult
    static func deleteSession(id: UUID, in context: ModelContext) -> Bool {
        let sessions = (try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id }))) ?? []
        guard !sessions.isEmpty else { return false }
        for stats in (try? context.fetch(FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == id }))) ?? [] {
            context.delete(stats)
        }
        for r in (try? context.fetch(FetchDescriptor<SessionReflection>(predicate: #Predicate { $0.sessionID == id }))) ?? [] {
            context.delete(r)
        }
        for p in (try? context.fetch(FetchDescriptor<SessionPhoto>(predicate: #Predicate { $0.sessionID == id }))) ?? [] {
            context.delete(p)
        }
        for s in sessions { context.delete(s) }
        try? context.save()
        return true
    }

    /// Hard-deletes Users soft-deleted more than `days` ago and every row FK'd to
    /// them (Preferences, Sessions, MeditationStats). Run on app launch. We store
    /// no raw biometrics, so nothing to delete from HealthKit.
    static func purgeExpired(olderThanDays days: Int = 30, now: Date = Date(), in context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let expired = ((try? context.fetch(FetchDescriptor<User>())) ?? [])
            .filter { ($0.deletedAt ?? .distantFuture) <= cutoff }
        guard !expired.isEmpty else { return }

        let allStats = (try? context.fetch(FetchDescriptor<MeditationStats>())) ?? []
        let allReflections = (try? context.fetch(FetchDescriptor<SessionReflection>())) ?? []
        let allPhotos = (try? context.fetch(FetchDescriptor<SessionPhoto>())) ?? []
        for user in expired {
            let uid = user.id
            let sessions = (try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.userID == uid }))) ?? []
            let sessionIDs = Set(sessions.map(\.id))
            for stats in allStats {
                if let sid = stats.sessionID, sessionIDs.contains(sid) { context.delete(stats) }
            }
            for r in allReflections {
                if let sid = r.sessionID, sessionIDs.contains(sid) { context.delete(r) }
            }
            for p in allPhotos {
                if let sid = p.sessionID, sessionIDs.contains(sid) { context.delete(p) }
            }
            for session in sessions { context.delete(session) }
            for prefs in (try? context.fetch(FetchDescriptor<Preferences>(predicate: #Predicate { $0.userID == uid }))) ?? [] {
                context.delete(prefs)
            }
            context.delete(user)
        }
        try? context.save()
    }

    /// Sets `onboardingComplete` on the user's Preferences (creating the row if the
    /// bootstrap flow somehow hasn't yet).
    private static func markOnboardingComplete(userID: UUID, in context: ModelContext) {
        let d = FetchDescriptor<Preferences>(predicate: #Predicate { $0.userID == userID })
        if let prefs = try? context.fetch(d).first {
            prefs.onboardingComplete = true
            prefs.updatedAt = Date()
        } else {
            context.insert(Preferences(userID: userID, onboardingComplete: true))
        }
    }

    /// Persists a finished session + its stats in ONE save. Idempotent: never
    /// writes a second `MeditationStats`/`Session` for a `sessionID`; skips
    /// discarded, too-short, or result-less payloads. Returns the written
    /// `Session`, or `nil` if nothing was written. `frequencyID` is the sound
    /// preset that played (phone-side knowledge — the Watch never carries it).
    @discardableResult
    static func persist(_ payload: SessionPayload, frequencyID: String? = nil,
                        in context: ModelContext) -> Session? {
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
        // And bail if the SESSION is already written, which stats alone does
        // not catch: a sit the phone finished on its own (the Watch never
        // answered, the watchdog handed it over) has a Session row and no
        // stats, and a payload arriving late would otherwise insert a second
        // row under the same id. SwiftData enforces no uniqueness, by design
        // here, so nothing downstream would have complained.
        let sessionDescriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })
        if let existing = try? context.fetch(sessionDescriptor), !existing.isEmpty {
            return nil
        }

        let user = currentUser(in: context)

        let session = Session(
            id: payload.sessionID,
            userID: user.id,
            trackID: payload.trackID,
            mode: payload.mode,
            bellyBreathing: payload.bellyBreathing,
            frequencyID: frequencyID,
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
            breathDoorwayRate: result.breathDoorwayRate,
            breathDoorwayHeldSec: result.breathDoorwayHeldSec,
            breathDoorwayStartSec: result.breathDoorwayStartSec,
            breathClarityTimeseries: result.breathClarityTimeseries,
            hrvSDNNSamples: payload.hrv?.sessionValuesMs ?? [],
            hrvMeanSDNN: payload.hrv?.meanMs,
            hrvBaselineSDNN: payload.hrv?.baselineMeanMs,
            hrvBaselineSampleCount: payload.hrv?.baselineSampleCount ?? 0,
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

    /// Persists a session the **phone** ran on its own, with no Watch and so
    /// no measurements at all.
    ///
    /// It writes a `Session` and deliberately **no `MeditationStats`**. An
    /// empty stats row would say "we measured and found nothing", which is a
    /// different and untrue claim: nothing was measuring. Everything derived
    /// (the streak, the awards, the calendar, the session count) reads
    /// Sessions, so a phone sit counts everywhere it should and simply has no
    /// score.
    ///
    /// Idempotent on the session id, like `persist`, but keyed on the
    /// `Session` rather than its stats, because there are none.
    @discardableResult
    static func persistPhoneSession(id: UUID,
                                    startedAt: Date,
                                    mode: String,
                                    frequencyID: String? = nil,
                                    durationSec: Int,
                                    in context: ModelContext) -> Session? {
        guard durationSec >= minDurationSec else { return nil }

        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return nil }

        let user = currentUser(in: context)
        let session = Session(
            id: id,
            userID: user.id,
            trackID: nil,
            mode: mode,
            bellyBreathing: false,
            frequencyID: frequencyID,
            startedAt: startedAt,
            durationSec: durationSec,
            source: "phone"
        )
        context.insert(session)
        try? context.save()
        return session
    }


    /// The user's reflection for a session, if any.
    static func reflection(for sessionID: UUID, in context: ModelContext) -> SessionReflection? {
        try? context.fetch(FetchDescriptor<SessionReflection>(
            predicate: #Predicate { $0.sessionID == sessionID })).first
    }

    /// Saves (or updates) the reflection for a session — one row per session.
    @discardableResult
    static func saveReflection(sessionID: UUID, rating: Int?, note: String,
                               technique: String? = nil, techniqueNote: String = "",
                               in context: ModelContext) -> SessionReflection {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTechnique = techniqueNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = reflection(for: sessionID, in: context) {
            existing.rating = rating
            existing.note = trimmed
            existing.technique = technique
            existing.techniqueNote = trimmedTechnique
            existing.updatedAt = Date()
            try? context.save()
            return existing
        }
        let reflection = SessionReflection(sessionID: sessionID, rating: rating, note: trimmed,
                                           technique: technique, techniqueNote: trimmedTechnique)
        context.insert(reflection)
        try? context.save()
        return reflection
    }

    /// The Save session screen's fields: title, the public description and
    /// who can see it. Leaves the rating alone; the note is the PRIVATE note.
    @discardableResult
    /// `techniqueNote` is the words behind "Something else". Nil keeps what
    /// is already stored, which is what a caller that has no field for it
    /// means; a caller with the field passes its text, empty included, so
    /// clearing it sticks.
    static func saveSession(sessionID: UUID, title: String, publicNote: String, privateNote: String,
                            visibility: String, technique: String?, techniqueNote: String? = nil,
                            in context: ModelContext) -> SessionReflection {
        let existing = reflection(for: sessionID, in: context)
        let row = saveReflection(sessionID: sessionID, rating: existing?.rating, note: privateNote,
                                 technique: technique,
                                 techniqueNote: techniqueNote ?? existing?.techniqueNote ?? "",
                                 in: context)
        row.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        row.publicNote = publicNote.trimmingCharacters(in: .whitespacesAndNewlines)
        row.visibility = visibility
        row.updatedAt = Date()
        try? context.save()
        return row
    }

    // MARK: Photos

    /// The photo kept with a session, if one was taken. One per session.
    static func photo(for sessionID: UUID, in context: ModelContext) -> SessionPhoto? {
        try? context.fetch(FetchDescriptor<SessionPhoto>(
            predicate: #Predicate { $0.sessionID == sessionID })).first
    }

    /// Saves or replaces the session's photo. Takes encoded bytes, not an
    /// image, because Shared/ is compiled into the Watch target too and the
    /// resizing lives in the iOS app (`PostPhoto`). Retaking replaces in
    /// place, so a session never carries two.
    @discardableResult
    static func savePhoto(sessionID: UUID, jpeg: Data, thumbnail: Data, video: Data? = nil,
                          takenAt: Date = Date(), in context: ModelContext) -> SessionPhoto {
        if let existing = photo(for: sessionID, in: context) {
            existing.jpeg = jpeg
            existing.thumbnail = thumbnail
            existing.video = video
            existing.takenAt = takenAt
            try? context.save()
            return existing
        }
        let row = SessionPhoto(sessionID: sessionID, takenAt: takenAt, jpeg: jpeg,
                               thumbnail: thumbnail, video: video)
        context.insert(row)
        try? context.save()
        return row
    }

    static func removePhoto(for sessionID: UUID, in context: ModelContext) {
        for p in (try? context.fetch(FetchDescriptor<SessionPhoto>(
            predicate: #Predicate { $0.sessionID == sessionID }))) ?? [] {
            context.delete(p)
        }
        try? context.save()
    }

    /// "Morning meditation" and friends: Strava's default activity name, by
    /// the hour the session started.
    static func defaultTitle(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12:  return "Morning meditation"
        case 12..<17: return "Afternoon meditation"
        case 17..<22: return "Evening meditation"
        default:      return "Night meditation"
        }
    }

    /// All session start dates for the store (feeds `StreakCalculator`).
    static func sessionStartDates(in context: ModelContext) -> [Date] {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(descriptor))?.map(\.startedAt) ?? []
    }
}
