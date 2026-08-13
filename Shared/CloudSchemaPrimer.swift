#if DEBUG
import Foundation
import SwiftData

/// Creates the CloudKit **Development** schema completely, before anyone
/// promotes it to Production.
///
/// **The trap this exists for.** CloudKit builds the Development schema lazily
/// from records the app actually writes, and a nil attribute writes no field.
/// Five synced models carry 13 optional fields between them, so ordinary use
/// leaves most of them out of the schema. Deploy that to Production and those
/// fields do not exist there, permanently, until somebody notices and
/// redeploys. Production schema changes are additive and manual: there is no
/// lazy creation on that side. So the failure surfaces later, on a user's
/// device, as a sync that quietly drops half a row.
///
/// Core Data exposes `initializeCloudKitSchema()` for exactly this. SwiftData
/// does not surface it, so we do the same job the honest way: write one row of
/// every synced model with **every** attribute non-nil, let it sync, and every
/// field comes into being.
///
/// Order of operations:
///   1. Debug build on a real device signed into iCloud.
///   2. Settings, "Prime CloudKit schema". Wait for sync (seconds to a minute).
///   3. CloudKit Console, Development: confirm 5 record types, all fields.
///   4. Deploy Schema Changes to Production.
///   5. Settings, "Remove primer rows". Deleting records never removes fields,
///      so the schema survives the cleanup.
///
/// `MeditationStats` is deliberately absent: health results are device-local
/// under App Review 5.1.3(ii) and must never reach iCloud.
enum CloudSchemaPrimer {

    /// Marks every row this file creates, so cleanup can find them and no real
    /// row is ever at risk.
    static let marker = "cloudkit-schema-primer"

    /// One row per synced model, every optional populated.
    static func prime(in context: ModelContext) {
        let now = Date()
        let userID = UUID()
        let trackID = UUID()
        let sessionID = UUID()

        let user = User(id: userID)
        user.appleUserID = marker
        user.email = "primer@\(marker).invalid"
        user.displayName = marker
        user.marketingOptIn = true
        user.createdAt = now
        user.updatedAt = now
        user.deletedAt = now          // the one field nothing else ever writes
        context.insert(user)

        let prefs = Preferences(userID: userID)
        prefs.onboardingComplete = true
        prefs.defaultDurationSec = 600
        prefs.remindersEnabled = true
        prefs.reminderTime = now
        prefs.theme = "dark"
        prefs.hapticsEnabled = true
        prefs.createdAt = now
        prefs.updatedAt = now
        context.insert(prefs)

        let track = MeditationTrack(id: trackID)
        track.type = "guided"
        track.title = marker
        track.trackDescription = marker
        track.audioURL = marker
        track.durationSec = 600
        track.sortOrder = -1
        track.isActive = false
        track.createdAt = now
        track.updatedAt = now
        context.insert(track)

        let session = Session(id: sessionID)
        session.userID = userID
        session.trackID = trackID
        session.mode = "frequency"
        session.bellyBreathing = true
        session.frequencyID = marker
        session.startedAt = now
        session.durationSec = 1
        session.createdAt = now
        context.insert(session)

        let reflection = SessionReflection(sessionID: sessionID)
        reflection.rating = 7
        reflection.note = marker
        reflection.technique = marker
        reflection.techniqueNote = marker
        reflection.createdAt = now
        reflection.updatedAt = now
        context.insert(reflection)

        try? context.save()
    }

    /// Deletes only what `prime` created. Every row is matched on the marker,
    /// so a real row can never be caught by this even if the ids collide.
    @discardableResult
    static func removePrimedRows(in context: ModelContext) -> Int {
        var removed = 0

        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let primerUserIDs = Set(users.filter { $0.appleUserID == marker }.map(\.id))
        for user in users where user.appleUserID == marker {
            context.delete(user); removed += 1
        }

        let prefs = (try? context.fetch(FetchDescriptor<Preferences>())) ?? []
        for p in prefs where p.userID.map(primerUserIDs.contains) == true {
            context.delete(p); removed += 1
        }

        let tracks = (try? context.fetch(FetchDescriptor<MeditationTrack>())) ?? []
        for t in tracks where t.title == marker {
            context.delete(t); removed += 1
        }

        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let primerSessionIDs = Set(
            sessions.filter { $0.frequencyID == marker }.map(\.id))
        for s in sessions where s.frequencyID == marker {
            context.delete(s); removed += 1
        }

        let reflections = (try? context.fetch(FetchDescriptor<SessionReflection>())) ?? []
        for r in reflections
        where r.note == marker || r.sessionID.map(primerSessionIDs.contains) == true {
            context.delete(r); removed += 1
        }

        try? context.save()
        return removed
    }

    /// How many primer rows are currently present, for the Settings readout.
    static func primedRowCount(in context: ModelContext) -> Int {
        let users = ((try? context.fetch(FetchDescriptor<User>())) ?? [])
            .filter { $0.appleUserID == marker }.count
        let tracks = ((try? context.fetch(FetchDescriptor<MeditationTrack>())) ?? [])
            .filter { $0.title == marker }.count
        let sessions = ((try? context.fetch(FetchDescriptor<Session>())) ?? [])
            .filter { $0.frequencyID == marker }.count
        return users + tracks + sessions
    }
}
#endif
