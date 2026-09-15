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
    /// A post needs its selfie (Aziz, 2026-09-14: "like BeReal").
    case selfieRequired
    /// Text the on-device filter refused (guideline 1.2).
    case contentBlocked
    /// A photo Sensitive Content Analysis flagged.
    case photoBlocked
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
        case .selfieRequired:  return "Take your selfie to post."
        case .contentBlocked:  return "That has words 808 doesn't allow. Change it and try again."
        case .photoBlocked:    return "That photo can't be shared on 808. Take another."
        }
    }
}

/// The public database of the app's entitled container.
final class CloudKitCommunityDatabase: CommunityDatabase {
    private let container: CKContainer
    private var db: CKDatabase { container.publicCloudDatabase }

    init(container: CKContainer) { self.container = container }

    /// nil unless the process demonstrably holds a CloudKit container.
    /// `Persistence.cloudKit()` already proved that by building the synced
    /// store; a guessed identifier traps, so nothing here guesses one
    /// (see CLAUDE.md, "Never construct a CKContainer from a guessed
    /// identifier").
    static func ifEntitled() -> CloudKitCommunityDatabase? {
        guard Persistence.mode == .cloudKit else { return nil }
        return CloudKitCommunityDatabase(container: CKContainer.default())
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
}
