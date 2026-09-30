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
    /// One minute (Melvin, 2026-09-29; was 30 seconds). The Watch and the
    /// phone both read this, so a sit under a minute is never written.
    static let minDurationSec = 60

    /// The account this device writes to: the signed-in account when there
    /// is one, otherwise the bootstrap `User` (`appleUserID == ""`), created
    /// with its `Preferences` if there is none. A deleted row is never used.
    ///
    /// **It used to return the bootstrap row only** (Melvin, 2026-09-29,
    /// found in the pre-1.1 audit with a failing test). Sign in with Apple
    /// adopts that row, so the next session found no bootstrap, minted a
    /// second one and was filed under it, where Delete account never
    /// reached: the session survived the 30-day purge, on the phone and in
    /// private iCloud (5.1.1(v)). `adoptStraySessions` repairs installs that
    /// already did this.
    @discardableResult
    static func currentUser(in context: ModelContext) -> User {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        if let signedIn = signedInUser(among: users) { return signedIn }
        if let bootstrap = users.first(where: { $0.appleUserID == "" && $0.deletedAt == nil }) {
            return bootstrap
        }
        let user = User(appleUserID: "")
        let prefs = Preferences(userID: user.id)
        context.insert(user)
        context.insert(prefs)
        try? context.save()
        return user
    }

    /// The most recently signed-in account that has not been deleted. More
    /// than one exists only after signing out and in with another Apple ID;
    /// sign-in stamps `updatedAt`, so the latest wins.
    static func signedInUser(among users: [User]) -> User? {
        users.filter { $0.appleUserID != "" && $0.deletedAt == nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Files every session held by a live bootstrap row under `user`. Such
    /// sessions exist on installs that signed in before `currentUser` learned
    /// to prefer the signed-in account; left where they were, Delete account
    /// would never have reached them. Changes who owns a session, never what
    /// was measured. Run at sign-in and at launch (`repairOwnership`).
    static func adoptStraySessions(into user: User, in context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let strays = Set(users.filter { $0.appleUserID == "" && $0.deletedAt == nil && $0.id != user.id }.map(\.id))
        guard !strays.isEmpty else { return }
        for session in (try? context.fetch(FetchDescriptor<Session>())) ?? [] {
            if let owner = session.userID, strays.contains(owner) { session.userID = user.id }
        }
    }

    /// Launch-time repair of the ownership bug above, for installs that
    /// already filed sessions under a stray bootstrap row. A no-op once done.
    ///
    /// Also for an account deleted under 1.0, when only the signed-in row was
    /// stamped: a live bootstrap row created before that deletion belongs to
    /// the deleted account, so it takes the same deletion date and goes with
    /// it at the purge. Left live, its sessions would have outlived the
    /// deletion, and come back if the person started over.
    static func repairOwnership(in context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        for deleted in users where deleted.appleUserID != "" {
            guard let when = deleted.deletedAt else { continue }
            for stray in users where stray.appleUserID == "" && stray.deletedAt == nil
                && stray.createdAt < when {
                stray.deletedAt = when
                stray.updatedAt = when
            }
        }
        if let signedIn = signedInUser(among: users) {
            adoptStraySessions(into: signedIn, in: context)
        }
        try? context.save()
    }

    /// Signs in with an Apple credential and marks onboarding complete. Account
    /// matching, in order (Phase-7 rule): (a) an existing User with this
    /// `appleUserID` → sign in as them; (b) else ADOPT the bootstrap User
    /// (`appleUserID == ""`) — fill in its identity so pre-account sessions +
    /// streak survive; (c) else create a new User. Never creates a second User
    /// while a bootstrap exists. Returns the signed-in User.
    ///
    /// `completingOnboarding: false` is onboarding's own sign-in screen: it
    /// signs in WITHOUT marking onboarding complete, because doing so swaps
    /// `RootView` to the app at once and the rest of the flow (profile, tour,
    /// `finish()`, which writes the answers and schedules the reminder)
    /// never runs. Onboarding marks itself complete when it finishes.
    @discardableResult
    static func signIn(appleUserID: String, email: String?, displayName: String?,
                       completingOnboarding: Bool = true,
                       in context: ModelContext) -> User {
        // a. Returning user? (Clear any pending soft-delete: signing back in
        // reactivates an account an older build soft-deleted. Deletion is
        // immediate since 2026-09-29, so a deleted account has no row left
        // to find and this signs in a fresh one.)
        let byApple = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID == appleUserID })
        if let user = try? context.fetch(byApple).first {
            user.deletedAt = nil
            user.updatedAt = Date()
            adoptStraySessions(into: user, in: context)
            if completingOnboarding { markOnboardingComplete(userID: user.id, in: context) }
            try? context.save()
            return user
        }
        // b. Adopt the bootstrap row (Apple gives name/email only on first sign-in,
        // so only overwrite when provided). Never a deleted one: adopting it
        // would bring back an account its owner asked us to delete.
        let bootstrapID = ""
        let byBootstrap = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID == bootstrapID })
        if let user = ((try? context.fetch(byBootstrap)) ?? []).first(where: { $0.deletedAt == nil }) {
            user.appleUserID = appleUserID
            if let email { user.email = email }
            if let displayName { user.displayName = displayName }
            user.deletedAt = nil
            user.updatedAt = Date()
            if completingOnboarding { markOnboardingComplete(userID: user.id, in: context) }
            try? context.save()
            return user
        }
        // c. Fresh account.
        let user = User(appleUserID: appleUserID, email: email, displayName: displayName)
        context.insert(user)
        context.insert(Preferences(userID: user.id, onboardingComplete: completingOnboarding))
        adoptStraySessions(into: user, in: context)
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

    /// Deletes this phone's person, NOW (App Review 5.1.1(v), 2026-09-29):
    /// every User row, signed in or bootstrap, and everything that belongs
    /// to one: Preferences (owned hats, the worn hat, the invite reward),
    /// Sessions, their MeditationStats (the device-local "HealthLocal"
    /// store), SessionReflections and SessionPhotos. The synced rows leave
    /// the private iCloud database as the deletion syncs.
    ///
    /// **All of them, not only the rows keyed to a live user.** A phone
    /// holds one person's data, and every screen reads every Session with no
    /// owner filter, so a row left behind (an orphan, a stray bootstrap's)
    /// is exactly what used to come back after someone started over. Built
    /// tracks (`MeditationTrack`) are the app's catalog, not the person's,
    /// and stay.
    ///
    /// It used to stamp `deletedAt` and leave the purge to a launch 30 days
    /// later, with sign-in inside that window restoring everything. That is
    /// gone: deletion is immediate and cannot be undone. The per-person
    /// UserDefaults bookkeeping goes too (`forgetPersonOnDevice`).
    static func deleteAccountNow(now: Date = Date(), in context: ModelContext,
                                 defaults: UserDefaults = .standard) {
        hardDelete(users: (try? context.fetch(FetchDescriptor<User>())) ?? [], in: context)
        // Whatever no user owned: orphans, and rows under a user id that no
        // longer exists. `MeditationTrack` is deliberately not in this list.
        for row in (try? context.fetch(FetchDescriptor<MeditationStats>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<SessionReflection>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<SessionPhoto>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<Session>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<Preferences>())) ?? [] { context.delete(row) }
        try? context.save()
        forgetPersonOnDevice(now: now, defaults: defaults)
    }

    /// The UserDefaults that describe the person rather than the phone,
    /// cleared so a fresh start on this phone starts fresh: announced awards
    /// (or the next person's first award would never announce), Otto's glow
    /// start (restarted today), the session still owed a save screen and
    /// the Home toast, the onboarding resume record, and onboarding's
    /// hand-off to the setup sheet.
    ///
    /// **Not touched, on purpose:** StoreKit and every entitlement or paywall
    /// flag (a subscription belongs to the Apple ID, not to the account),
    /// Block and Screen Time state (the device's own authorization), the
    /// Friends pending-deletion retry, device settings (the Do Not Disturb
    /// shortcuts, the Watch link, the last sound chosen), the rating-prompt
    /// cooldown, one-time migrations, and DEBUG switches.
    static func forgetPersonOnDevice(now: Date = Date(), defaults: UserDefaults = .standard) {
        AwardsInbox.forgetAnnounced(now: now, in: defaults)
        defaults.removeObject(forKey: OttoAura.glowStartKey)
        OttoAura.markGlowStartIfNeeded(now: now, defaults: defaults)
        PendingSave.clear(in: defaults)
        SessionDetails.clear(in: defaults)
        OnboardingResume.clear(from: defaults)
        defaults.removeObject(forKey: OnboardingHandoff.key)
    }

    /// How builds before 2026-09-29 deleted an account: stamp `deletedAt` on
    /// every live user row and sign out, leaving `purgeExpired` to remove the
    /// rows 30 days later. The app no longer calls it (`deleteAccountNow`
    /// does); it stays so tests can build the soft-deleted rows an older
    /// build left on a phone, which `purgeExpired` still clears.
    static func softDeleteCurrentUser(now: Date = Date(), in context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        for user in users where user.deletedAt == nil {
            user.deletedAt = now
            user.updatedAt = now
        }
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
    ///
    /// Deletion is immediate since 2026-09-29 (`deleteAccountNow`); this still
    /// runs for the soft-deleted rows older builds left on phones.
    static func purgeExpired(olderThanDays days: Int = 30, now: Date = Date(), in context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let expired = ((try? context.fetch(FetchDescriptor<User>())) ?? [])
            .filter { ($0.deletedAt ?? .distantFuture) <= cutoff }
        guard !expired.isEmpty else { return }
        hardDelete(users: expired, in: context)
        try? context.save()
    }

    /// Deletes `users` and every row keyed to them: their Sessions, those
    /// sessions' stats, reflections and photos, and their Preferences. The
    /// one deletion body `purgeExpired` and `deleteAccountNow` share. Does
    /// not save.
    private static func hardDelete(users: [User], in context: ModelContext) {
        guard !users.isEmpty else { return }
        let allStats = (try? context.fetch(FetchDescriptor<MeditationStats>())) ?? []
        let allReflections = (try? context.fetch(FetchDescriptor<SessionReflection>())) ?? []
        let allPhotos = (try? context.fetch(FetchDescriptor<SessionPhoto>())) ?? []
        for user in users {
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

    /// What `store` did with a payload. The coordinator needs all three apart,
    /// because the Watch sends every payload TWICE (sendMessage for speed,
    /// transferUserInfo as the backstop): a second copy of a saved session
    /// comes back `.alreadyStored`, and reading that as "nothing written"
    /// used to put up the "couldn't read that one" screen after every Watch
    /// session.
    enum PersistOutcome {
        /// Written now: a new Session with its stats, or stats attached to a
        /// Session the phone had already written for the same sit.
        case saved(Session)
        /// This session's stats are already stored. A duplicate copy; do
        /// nothing with it.
        case alreadyStored
        /// Discarded, too short, or no result: nothing to write.
        case rejected

        var session: Session? {
            if case .saved(let session) = self { return session }
            return nil
        }
    }

    /// Persists a finished session + its stats in ONE save. Returns the
    /// written `Session`, or `nil` if nothing was written. See `store` for
    /// the three outcomes this flattens.
    @discardableResult
    static func persist(_ payload: SessionPayload, frequencyID: String? = nil,
                        in context: ModelContext) -> Session? {
        store(payload, frequencyID: frequencyID, in: context).session
    }

    /// Persists a finished session + its stats in ONE save. Idempotent: never
    /// writes a second `MeditationStats`/`Session` for a `sessionID`; rejects
    /// discarded, too-short, or result-less payloads. `frequencyID` is the
    /// sound preset that played (phone-side knowledge: the Watch never
    /// carries it).
    ///
    /// **A Session with no stats gets them attached rather than refused.**
    /// A Watch sit the phone took over (the Watch never confirmed in time, or
    /// End was tapped before it did) is written by the phone as a phone sit.
    /// If the Watch then ships its measurements for the same id, they belong
    /// to that sit, and throwing them away lost a measured session for
    /// nothing. The row keeps the phone's start and length (the sit the
    /// person actually did) and stops reading as unmeasured.
    static func store(_ payload: SessionPayload, frequencyID: String? = nil,
                      in context: ModelContext) -> PersistOutcome {
        guard !payload.discard,
              payload.durationSec >= minDurationSec,
              let result = payload.result else { return .rejected }

        // Idempotency: this session's stats are already written.
        let sid = payload.sessionID
        let statsDescriptor = FetchDescriptor<MeditationStats>(
            predicate: #Predicate { $0.sessionID == sid }
        )
        if let existing = try? context.fetch(statsDescriptor), !existing.isEmpty {
            return .alreadyStored
        }
        // A Session row with no stats: the phone wrote this sit itself. Attach
        // the measurements to it rather than insert a second row under the
        // same id (SwiftData enforces no uniqueness, by design here).
        let sessionDescriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })
        if let existing = try? context.fetch(sessionDescriptor).first {
            // A hand-recorded sit never carries a Watch's measurements.
            guard !existing.isLogged else { return .alreadyStored }
            if existing.source == "phone" { existing.source = "watch" }
            if existing.frequencyID == nil { existing.frequencyID = frequencyID }
            context.insert(makeStats(for: payload, result: result))
            try? context.save()
            return .saved(existing)
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
        let stats = makeStats(for: payload, result: result)
        context.insert(session)
        context.insert(stats)
        try? context.save()
        return .saved(session)
    }

    /// The stats row for a payload, one place for both the new-session and
    /// the attach path in `store`.
    private static func makeStats(for payload: SessionPayload, result: SignalResult) -> MeditationStats {
        MeditationStats(
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
                                    source: String = "phone",
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
            source: source
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

    /// A session may keep up to this many photos and videos (Melvin,
    /// 2026-09-23). Enforced in `addPhoto`, not in the schema.
    static let maxPhotosPerSession = 10

    /// Every item kept with a session, lowest `order` first. Empty when
    /// nothing was ever taken.
    static func photos(for sessionID: UUID, in context: ModelContext) -> [SessionPhoto] {
        let rows = (try? context.fetch(FetchDescriptor<SessionPhoto>(
            predicate: #Predicate { $0.sessionID == sessionID }))) ?? []
        return rows.sorted { $0.order < $1.order }
    }

    /// The FIRST item kept with a session, for callers that only ever show
    /// one: the calendar dot, `EvidenceRow`'s thumbnail, the results screen.
    /// `photos(for:in:)` is every item, in order.
    static func photo(for sessionID: UUID, in context: ModelContext) -> SessionPhoto? {
        photos(for: sessionID, in: context).first
    }

    /// Saves or replaces the session's FIRST photo (order 0), leaving any
    /// later items alone. Takes encoded bytes, not an image, because Shared/
    /// is compiled into the Watch target too and the resizing lives in the
    /// iOS app (`PostPhoto`). Kept for whoever still wants "replace the one
    /// photo in place"; a new item is `addPhoto`.
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

    /// Appends a new item after whatever the session already keeps. Returns
    /// nil, inserting nothing, once `maxPhotosPerSession` is reached.
    @discardableResult
    static func addPhoto(sessionID: UUID, jpeg: Data, thumbnail: Data, video: Data? = nil,
                         takenAt: Date = Date(), in context: ModelContext) -> SessionPhoto? {
        let existing = photos(for: sessionID, in: context)
        guard existing.count < maxPhotosPerSession else { return nil }
        let row = SessionPhoto(sessionID: sessionID, takenAt: takenAt, jpeg: jpeg,
                               thumbnail: thumbnail, video: video,
                               order: (existing.last?.order ?? -1) + 1)
        context.insert(row)
        try? context.save()
        return row
    }

    /// Removes every photo and video a session keeps.
    static func removePhoto(for sessionID: UUID, in context: ModelContext) {
        for p in (try? context.fetch(FetchDescriptor<SessionPhoto>(
            predicate: #Predicate { $0.sessionID == sessionID }))) ?? [] {
            context.delete(p)
        }
        try? context.save()
    }

    /// Removes ONE item by its own id, leaving the session's other photos
    /// and videos as they were.
    static func removePhotoItem(id: UUID, in context: ModelContext) {
        guard let row = try? context.fetch(FetchDescriptor<SessionPhoto>(
            predicate: #Predicate { $0.id == id })).first else { return }
        context.delete(row)
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
