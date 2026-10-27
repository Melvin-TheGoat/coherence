import Foundation
import CloudKit

/// A query as the store describes it: a record type, equality or membership
/// filters, one sort, a limit. Small on purpose. The CloudKit database turns it
/// into an `NSPredicate`; the test fake evaluates it directly, so the store's
/// logic is tested without CloudKit and without trusting KVC on `CKRecord`.
struct CommunityQuery: Equatable {
    enum Filter: Equatable {
        case equals(String, CommunityRecordValue)
        case isIn(String, [CommunityRecordValue])
    }

    let type: String
    var filters: [Filter] = []
    var sortField: String? = nil
    var ascending: Bool = false
    var limit: Int = 100

    func matches(_ record: CKRecord) -> Bool {
        guard record.recordType == type else { return false }
        return filters.allSatisfy { filter in
            switch filter {
            case .equals(let field, let value):
                return CommunityRecordValue(record[field]) == value
            case .isIn(let field, let values):
                guard let v = CommunityRecordValue(record[field]) else { return false }
                return values.contains(v)
            }
        }
    }

    var predicate: NSPredicate {
        let parts: [NSPredicate] = filters.map { filter in
            switch filter {
            case .equals(let field, let value):
                return NSPredicate(format: "%K == %@", field, value.ckValue as! CVarArg)
            case .isIn(let field, let values):
                return NSPredicate(format: "%K IN %@", field, values.map(\.ckValue) as NSArray)
            }
        }
        return parts.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    var ckQuery: CKQuery {
        let q = CKQuery(recordType: type, predicate: predicate)
        if let sortField { q.sortDescriptors = [NSSortDescriptor(key: sortField, ascending: ascending)] }
        return q
    }
}

/// What the store needs from a database, and nothing CloudKit-specific beyond
/// `CKRecord` itself. `CloudKitCommunityDatabase` is the real one;
/// `FakeCommunityDatabase` (tests) is an in-memory dictionary.
protocol CommunityDatabase {
    /// The caller's iCloud user record name. Stable per user per container,
    /// opaque, and the root of every record name the user owns.
    func currentUserRecordName() async throws -> String
    func save(_ record: CKRecord) async throws -> CKRecord
    /// Saves a NEW record and fails with `CommunityError.alreadyExists` if one
    /// with that name is already on the server. Atomic on the server, which is
    /// what makes a username reservation a real lock rather than a check.
    func create(_ record: CKRecord) async throws -> CKRecord
    /// nil when no record has that name.
    func fetch(_ recordName: String) async throws -> CKRecord?
    func query(_ query: CommunityQuery) async throws -> [CKRecord]
    func delete(_ recordName: String) async throws
    /// Push alerts for Meditating together: an invite to me, an answer to my
    /// invite, a nudge to me. Best effort; a database that cannot push (the
    /// in-memory one) does nothing.
    func ensureGoalSubscriptions(me: String) async
    /// A push when someone joins with my invite code (2026-10-18).
    func ensureCodeJoinSubscription(me: String, codes: [String]) async
}

extension CommunityDatabase {
    func ensureGoalSubscriptions(me: String) async {}
    func ensureCodeJoinSubscription(me: String, codes: [String]) async {}
}

enum CommunityError: Error, Equatable {
    /// No iCloud account, or the app is running without a CloudKit container
    /// (simulator, unprovisioned build). The tab shows an honest card.
    case unavailable
    case usernameTaken
    case usernameInvalid
    case noProfile
    case blocked
    case alreadyExists
    /// Text the on-device filter refused (guideline 1.2).
    case contentBlocked
    /// A photo Sensitive Content Analysis flagged.
    case photoBlocked
    /// No invite code by that name (2026-10-18).
    case inviteCodeUnknown
    /// Someone entered their own invite code.
    case inviteCodeIsYours
}

extension CommunityError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:     return "iCloud isn't available on this iPhone."
        case .usernameTaken:   return "That username is taken."
        case .usernameInvalid: return "Letters, numbers, dots and underscores only."
        case .noProfile:       return "Create your profile first."
        case .blocked:         return "You can't do that with this person."
        case .alreadyExists:   return "That already exists."
        case .contentBlocked:  return "That has words 808 doesn't allow. Change it and try again."
        case .photoBlocked:    return "That photo can't be shared on 808. Take another."
        case .inviteCodeUnknown: return "That code doesn't match anyone. Check it and try again."
        case .inviteCodeIsYours: return "That's your own code. Send it to a friend."
        }
    }
}

/// The public database of the app's entitled container.
final class CloudKitCommunityDatabase: CommunityDatabase {
    private let container: CKContainer
    private var db: CKDatabase { container.publicCloudDatabase }

    init(container: CKContainer) { self.container = container }

    /// nil unless the process demonstrably holds a CloudKit container.
    ///
    /// `Persistence.mode == .cloudKit` was the only guard until 2026-09-15,
    /// and it is not proof: SwiftData resolves its container lazily and
    /// reported sync active on the side-by-side beta, which strips the
    /// iCloud entitlement, so `CKContainer.default()` trapped at launch
    /// (SIGTRAP in `CoherenceApp.init`, every open). `CloudEntitlement`
    /// reads the binary's own profile; `CKContainer.default()` runs only when
    /// that says a container is held (see CLAUDE.md, "Never construct a
    /// CKContainer from a guessed identifier").
    static func ifEntitled() -> CloudKitCommunityDatabase? {
        guard Persistence.mode == .cloudKit, CloudEntitlement.mayHoldContainer else { return nil }
        // `CKContainer.default()` is NOT the entitled container: Apple names
        // it after the bundle id ("iCloud." + bundle id). On the App Store
        // build the two coincide; on the side-by-side beta the bundle id ends
        // in ".dev" and default() asked CloudKit for a container that does not
        // exist ("couldn't get container configuration", 2026-09-16). SwiftData
        // reads the entitlement for the private database, so sync worked while
        // Friends failed. Use the entitled identifier whenever the profile
        // names one; default() only where no profile exists (a store build,
        // whose bundle id is the production one).
        let container = CloudEntitlement.container.map { CKContainer(identifier: $0) } ?? CKContainer.default()
        return CloudKitCommunityDatabase(container: container)
    }

    func currentUserRecordName() async throws -> String {
        guard try await container.accountStatus() == .available else { throw CommunityError.unavailable }
        return try await container.userRecordID().recordName
    }

    /// An upsert. `CKDatabase.save` refuses a freshly built record whose name
    /// already exists on the server ("record to insert already exists"),
    /// which re-sending a request, reacting twice or re-blocking all do. The
    /// in-memory test database never modelled that, so every test passed while
    /// the real one would have failed. `.allKeys` writes every field, which
    /// is what each caller intends: they build or fetch the whole record.
    func save(_ record: CKRecord) async throws -> CKRecord {
        let (saved, _) = try await db.modifyRecords(saving: [record], deleting: [],
                                                    savePolicy: .allKeys, atomically: false)
        guard let result = saved[record.recordID] else { return record }
        return try result.get()
    }

    func create(_ record: CKRecord) async throws -> CKRecord {
        // `.ifServerRecordUnchanged` on a record the server has never seen
        // fails with serverRecordChanged when someone else created it first.
        // Not atomic: the public database's default zone does not support
        // atomic modifies. The per-record result carries the conflict.
        do {
            let (saved, _) = try await db.modifyRecords(saving: [record], deleting: [],
                                                        savePolicy: .ifServerRecordUnchanged,
                                                        atomically: false)
            guard let result = saved[record.recordID] else { throw CommunityError.alreadyExists }
            return try result.get()
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw CommunityError.alreadyExists
        } catch let error as CKError where error.code == .partialFailure {
            // Only a conflict on THIS record means the name is taken. A network
            // or permission failure must surface as itself, not as "taken".
            let item = error.partialErrorsByItemID?[record.recordID] as? CKError
            if item?.code == .serverRecordChanged { throw CommunityError.alreadyExists }
            throw item ?? error
        }
    }

    func fetch(_ recordName: String) async throws -> CKRecord? {
        do {
            return try await db.record(for: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func query(_ query: CommunityQuery) async throws -> [CKRecord] {
        do {
            return try await runQuery(query)
        } catch let error as CKError where error.code == .unknownItem {
            // "Did not find record type": nobody has ever saved one, so
            // nothing matches. Development builds the type on first save.
            return []
        }
    }

    private func runQuery(_ query: CommunityQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var (matches, cursor) = try await db.records(matching: query.ckQuery, resultsLimit: query.limit)
        out += matches.compactMap { try? $0.1.get() }
        while let c = cursor, out.count < query.limit {
            (matches, cursor) = try await db.records(continuingMatchFrom: c, resultsLimit: query.limit - out.count)
            out += matches.compactMap { try? $0.1.get() }
        }
        return out
    }

    func delete(_ recordName: String) async throws {
        do {
            _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone is the outcome we wanted.
        }
    }

    /// Three query subscriptions, so CloudKit itself pushes the alert: no
    /// server of ours is involved (Meditating together, 2026-10-14). Until
    /// now the public database pushed nothing and Friends refreshed on a
    /// timer while open; a nudge has to reach a phone in a pocket.
    ///
    /// The alert text is a localization key in `Localizable.strings` with the
    /// writer's name as its argument (a subscription can only quote fields of
    /// the record it fires on, hence `fromName`). Saved once per person; a
    /// later save with the same ids replaces them, so calling this on every
    /// launch is harmless. Needs the queried fields QUERYABLE in Production
    /// (`CLOUDKIT_SETUP.md`), and notification permission to show anything.
    func ensureGoalSubscriptions(me: String) async {
        let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: me), action: .none)
        func sub(_ id: String, type: String, predicate: NSPredicate, key: String) -> CKQuerySubscription {
            let s = CKQuerySubscription(recordType: type, predicate: predicate,
                                        subscriptionID: id + "-" + me, options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            info.alertLocalizationKey = key
            info.alertLocalizationArgs = ["fromName"]
            info.soundName = "default"
            s.notificationInfo = info
            return s
        }
        let subs = [
            sub("goal-invite", type: CommunityType.goalMember,
                predicate: NSPredicate(format: "partner == %@ AND kind == %@", ref, "invite"),
                key: "GOAL_INVITE_ALERT"),
            sub("goal-accept", type: CommunityType.goalMember,
                predicate: NSPredicate(format: "partner == %@ AND kind == %@", ref, "accept"),
                key: "GOAL_ACCEPT_ALERT"),
            sub("goal-nudge", type: CommunityType.nudge,
                predicate: NSPredicate(format: "to == %@ AND kind == %@", ref, "nudge"),
                key: "GOAL_NUDGE_ALERT"),
            sub("goal-cheer", type: CommunityType.nudge,
                predicate: NSPredicate(format: "to == %@ AND kind == %@", ref, "cheer"),
                key: "GOAL_CHEER_ALERT"),
            // A week finished together, told by the friend who finished it
            // second (2026-10-27). The same type and indexes as a nudge.
            sub("goal-week", type: CommunityType.nudge,
                predicate: NSPredicate(format: "to == %@ AND kind == %@", ref, "week"),
                key: "GOAL_WEEK_ALERT"),
        ]
        do {
            _ = try await db.modifySubscriptions(saving: subs, deleting: [])
        } catch {
            // A missing record type or index in this environment, or no
            // network: the app still works, it just won't push until it can.
        }
    }

    /// "Sam joined 808 with your code": a push on an edge written to me
    /// carrying my code. Needs `FriendEdge.viaCode` QUERYABLE in Production
    /// (`CLOUDKIT_SETUP.md`, "Invite codes"). Saved again on every launch,
    /// which replaces it in place.
    func ensureCodeJoinSubscription(me: String, codes: [String]) async {
        let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: me), action: .none)
        // Every code I have sent, since each invite gets its own (2026-10-18).
        let sub = CKQuerySubscription(recordType: CommunityType.edge,
                                      predicate: NSPredicate(format: "to == %@ AND viaCode IN %@", ref, codes),
                                      subscriptionID: "code-join-" + me, options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.alertLocalizationKey = "CODE_JOIN_ALERT"
        info.alertLocalizationArgs = ["fromName"]
        info.soundName = "default"
        sub.notificationInfo = info
        _ = try? await db.modifySubscriptions(saving: [sub], deleting: [])
    }
}
