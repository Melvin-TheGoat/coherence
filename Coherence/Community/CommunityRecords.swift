import Foundation
import CloudKit

/// The six record types in the PUBLIC CloudKit database, as value types.
///
/// Design record: `COMMUNITY.md`. The shape follows one CloudKit constraint:
/// only a record's creator can modify it in the public database. So a
/// friendship is two edges (each person writes their own), a reaction is a
/// record the reactor owns, a block is a record the blocker owns, and nobody
/// ever needs to edit anyone else's row.
///
/// **What a post may carry is a rule, not a choice:** score, minutes, streak,
/// technique, photo, caption. Never a heart-rate, breath or stillness value,
/// never a curve. Guideline 5.1.3(ii) forbids health data in iCloud, and the
/// free tier locks the evidence; a post is the free share card's data and
/// nothing more. `CommunityStoreTests.test_postCarriesOnlyTheFreeCardFields`
/// pins the field list.
enum CommunityType {
    static let profile  = "Profile"
    static let edge     = "FriendEdge"
    static let post     = "Post"
    static let reaction = "Reaction"
    static let block    = "Block"
    static let report   = "Report"
}

/// Record names are deterministic wherever a second save should overwrite
/// rather than duplicate: one profile per iCloud user, one edge per direction
/// per pair, one reaction per person per post, one block per pair. Posts and
/// reports are genuinely many, so they get UUIDs.
enum CommunityNames {
    static func profile(user userRecordName: String) -> String { "profile-" + userRecordName }
    static func edge(from: String, to: String) -> String { "edge-" + from + "-" + to }
    static func reaction(post: String, by author: String) -> String { "react-" + post + "-" + author }
    static func block(from: String, to: String) -> String { "block-" + from + "-" + to }
}

struct Profile: Identifiable, Equatable {
    /// The record name, `CommunityNames.profile(user:)`.
    let id: String
    var username: String
    var displayName: String
    var firstSessionAt: Date?
    var createdAt: Date

    init(id: String, username: String, displayName: String, firstSessionAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.firstSessionAt = firstSessionAt
        self.createdAt = createdAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.profile,
              let username = record["username"] as? String else { return nil }
        self.init(id: record.recordID.recordName,
                  username: username,
                  displayName: record["displayName"] as? String ?? "",
                  firstSessionAt: record["firstSessionAt"] as? Date,
                  createdAt: record["createdAt"] as? Date ?? Date())
    }

    func apply(to record: CKRecord) {
        record["username"] = username
        record["displayName"] = displayName
        record["firstSessionAt"] = firstSessionAt
        record["createdAt"] = createdAt
    }
}

/// One direction of a friendship. `from` and `to` are profile record names.
struct FriendEdge: Identifiable, Equatable {
    let from: String
    let to: String
    var createdAt: Date

    var id: String { CommunityNames.edge(from: from, to: to) }

    init(from: String, to: String, createdAt: Date = Date()) {
        self.from = from; self.to = to; self.createdAt = createdAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.edge,
              let from = (record["from"] as? CKRecord.Reference)?.recordID.recordName,
              let to = (record["to"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(from: from, to: to, createdAt: record["createdAt"] as? Date ?? Date())
    }

    func apply(to record: CKRecord) {
        record["from"] = CommunityRecordValue.reference(from).ckValue
        record["to"] = CommunityRecordValue.reference(to).ckValue
        record["createdAt"] = createdAt
    }
}

struct Post: Identifiable, Equatable {
    let id: String
    let author: String
    var score: Int
    var minutes: Int
    var streak: Int
    var technique: String?
    var caption: String
    /// A local file URL for the photo (CloudKit hands assets back as files).
    var photoURL: URL?
    var practicedAt: Date
    var createdAt: Date

    /// The only fields a post may carry. Locked by test; if you find yourself
    /// adding one, read the rule at the top of this file first.
    static let fields = ["author", "score", "minutes", "streak", "technique", "caption", "photo", "practicedAt", "createdAt"]

    init(id: String = UUID().uuidString, author: String, score: Int, minutes: Int, streak: Int,
         technique: String? = nil, caption: String = "", photoURL: URL? = nil,
         practicedAt: Date, createdAt: Date = Date()) {
        self.id = id; self.author = author; self.score = score; self.minutes = minutes
        self.streak = streak; self.technique = technique; self.caption = caption
        self.photoURL = photoURL; self.practicedAt = practicedAt; self.createdAt = createdAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.post,
              let author = (record["author"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(id: record.recordID.recordName,
                  author: author,
                  score: record["score"] as? Int ?? 0,
                  minutes: record["minutes"] as? Int ?? 0,
                  streak: record["streak"] as? Int ?? 0,
                  technique: record["technique"] as? String,
                  caption: record["caption"] as? String ?? "",
                  photoURL: (record["photo"] as? CKAsset)?.fileURL,
                  practicedAt: record["practicedAt"] as? Date ?? Date(),
                  createdAt: record["createdAt"] as? Date ?? Date())
    }

    func apply(to record: CKRecord) {
        record["author"] = CommunityRecordValue.reference(author).ckValue
        record["score"] = score
        record["minutes"] = minutes
        record["streak"] = streak
        record["technique"] = technique
        record["caption"] = caption
        record["photo"] = photoURL.map { CKAsset(fileURL: $0) }
        record["practicedAt"] = practicedAt
        record["createdAt"] = createdAt
    }
}

struct Reaction: Identifiable, Equatable {
    let post: String
    let author: String
    var createdAt: Date

    var id: String { CommunityNames.reaction(post: post, by: author) }

    init(post: String, author: String, createdAt: Date = Date()) {
        self.post = post; self.author = author; self.createdAt = createdAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.reaction,
              let post = (record["post"] as? CKRecord.Reference)?.recordID.recordName,
              let author = (record["author"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(post: post, author: author, createdAt: record["createdAt"] as? Date ?? Date())
    }

    func apply(to record: CKRecord) {
        record["post"] = CommunityRecordValue.reference(post).ckValue
        record["author"] = CommunityRecordValue.reference(author).ckValue
        record["createdAt"] = createdAt
    }
}

struct Block: Identifiable, Equatable {
    let from: String
    let to: String

    var id: String { CommunityNames.block(from: from, to: to) }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.block,
              let from = (record["from"] as? CKRecord.Reference)?.recordID.recordName,
              let to = (record["to"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(from: from, to: to)
    }

    init(from: String, to: String) { self.from = from; self.to = to }

    func apply(to record: CKRecord) {
        record["from"] = CommunityRecordValue.reference(from).ckValue
        record["to"] = CommunityRecordValue.reference(to).ckValue
    }
}

struct Report: Identifiable, Equatable {
    enum Target: String { case post, profile }

    let id: String
    let reporter: String
    let target: String
    let targetType: Target
    var reason: String
    var createdAt: Date

    init(id: String = UUID().uuidString, reporter: String, target: String, targetType: Target,
         reason: String, createdAt: Date = Date()) {
        self.id = id; self.reporter = reporter; self.target = target
        self.targetType = targetType; self.reason = reason; self.createdAt = createdAt
    }

    func apply(to record: CKRecord) {
        record["reporter"] = CommunityRecordValue.reference(reporter).ckValue
        record["target"] = target
        record["targetType"] = targetType.rawValue
        record["reason"] = reason
        record["createdAt"] = createdAt
    }
}

/// A field value as the store talks about it, independent of CloudKit's
/// types, so the fake database in tests can compare values without NSPredicate
/// and the real one can build a predicate from the same description.
enum CommunityRecordValue: Equatable {
    case string(String)
    case reference(String)
    case date(Date)

    var ckValue: CKRecordValue {
        switch self {
        case .string(let s):    return s as NSString
        case .date(let d):      return d as NSDate
        case .reference(let name):
            return CKRecord.Reference(recordID: CKRecord.ID(recordName: name), action: .none)
        }
    }

    init?(_ raw: Any?) {
        switch raw {
        case let s as String:               self = .string(s)
        case let d as Date:                 self = .date(d)
        case let r as CKRecord.Reference:   self = .reference(r.recordID.recordName)
        default:                            return nil
        }
    }
}
