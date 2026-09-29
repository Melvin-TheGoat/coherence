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
/// **What a post may carry is a rule, not a choice:** minutes, streak,
/// technique, photos and videos, caption. Never a score, and never a
/// heart-rate, breath or stillness value, never a curve. **Posts stopped
/// carrying a score on 2026-09-23**: it was derived from heart
/// rate, guideline 5.1.3(ii) forbids storing personal health information in
/// iCloud with no consent exception, and the public database has no consent
/// gate at all, so the founders took the zero-risk answer and dropped it.
/// The free tier locks the evidence besides; a post is the free share card's
/// data minus the one number that could be read as health data.
/// `CommunityStoreTests.test_postCarriesOnlyTheFreeCardFields` and
/// `.test_postNeverCarriesAScore` pin the field list.
enum CommunityType {
    static let profile  = "Profile"
    static let edge     = "FriendEdge"
    static let post     = "Post"
    static let reaction = "Reaction"
    static let block    = "Block"
    static let report   = "Report"
    /// A username reservation: record name `username-<handle>`, one field
    /// `profile` pointing at its owner. See `CommunityStore.claimUsername`.
    static let username = "Username"
}

/// Record names are deterministic wherever a second save should overwrite
/// rather than duplicate: one profile per iCloud user, one edge per direction
/// per pair, one reaction per person per post. Posts and reports are
/// genuinely many, so they get UUIDs.
///
/// **Blocks get UUIDs too, on purpose (2026-09-29, Melvin: "don't want others
/// to see who I blocked").** A Block is readable only by its creator, but a
/// name anyone can work out (`block-<from>-<to>`, built from two public
/// profile names) would still let anyone ask CloudKit whether that record
/// exists, by fetching it or by trying to create it, and learn who blocked
/// whom without reading a field. A random name gives nothing to ask for. It
/// also means nobody can create my block's name before I do and so stop me
/// blocking them. One block per pair is kept by the store instead
/// (`CommunityStore.block` looks before it writes). Blocks written by builds
/// before this change still carry the old `block-<from>-<to>` names; the
/// store finds and removes them the same way, by querying my own.
enum CommunityNames {
    static func profile(user userRecordName: String) -> String { "profile-" + userRecordName }
    static func edge(from: String, to: String) -> String { "edge-" + from + "-" + to }
    static func reaction(post: String, by author: String) -> String { "react-" + post + "-" + author }
    /// A fresh, unguessable name for a new Block record.
    static func newBlock() -> String { "block-" + UUID().uuidString }
    static func username(_ handle: String) -> String { "username-" + handle }
}

struct Profile: Identifiable, Equatable {
    /// The record name, `CommunityNames.profile(user:)`.
    let id: String
    var username: String
    var displayName: String
    var firstSessionAt: Date?
    var createdAt: Date
    /// The profile photo, as a local file (CloudKit hands assets back as
    /// files). Optional: initials stand in when there is none.
    var avatarURL: URL?
    /// How often this person meditates (Melvin, 2026-09-27: "see how often
    /// someone meditates"): sessions and minutes this week, the streak, the
    /// total, and when they last sat. Changes only through
    /// `CommunityStore.updatePracticeStats`, the same way the avatar changes
    /// only through `setAvatar`, so claiming or renaming a handle never
    /// resets it.
    var practice: PracticeStats = .empty

    init(id: String, username: String, displayName: String, firstSessionAt: Date? = nil,
         createdAt: Date = Date(), avatarURL: URL? = nil, practice: PracticeStats = .empty) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.firstSessionAt = firstSessionAt
        self.createdAt = createdAt
        self.avatarURL = avatarURL
        self.practice = practice
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.profile,
              let username = record["username"] as? String else { return nil }
        self.init(id: record.recordID.recordName,
                  username: username,
                  displayName: record["displayName"] as? String ?? "",
                  firstSessionAt: record["firstSessionAt"] as? Date,
                  createdAt: record["createdAt"] as? Date ?? Date(),
                  avatarURL: (record["avatar"] as? CKAsset)?.fileURL,
                  practice: PracticeStats(record: record))
    }

    /// Writes everything but the photo and the practice stats, which change
    /// through their own calls so a rename never re-uploads a photo or
    /// resets how often somebody meditates.
    func apply(to record: CKRecord) {
        record["username"] = username
        record["displayName"] = displayName
        record["firstSessionAt"] = firstSessionAt
        record["createdAt"] = createdAt
    }
}

/// The CloudKit side of `PracticeStats` (Shared, pure Foundation): five
/// fields on the Profile record, written together and only through
/// `CommunityStore.updatePracticeStats`. **New CloudKit fields — must be
/// promoted Development → Production before release** (see CLAUDE.md,
/// "ORG-ACCOUNT-DAY CHECKLIST"): `sessions7d`, `minutes7d`, `currentStreak`,
/// `totalSessions`, `lastSessionAt`.
extension PracticeStats {
    init(record: CKRecord) {
        self.init(sessions7d: record["sessions7d"] as? Int ?? 0,
                  minutes7d: record["minutes7d"] as? Int ?? 0,
                  currentStreak: record["currentStreak"] as? Int ?? 0,
                  totalSessions: record["totalSessions"] as? Int ?? 0,
                  lastSessionAt: record["lastSessionAt"] as? Date)
    }

    func apply(to record: CKRecord) {
        record["sessions7d"] = sessions7d
        record["minutes7d"] = minutes7d
        record["currentStreak"] = currentStreak
        record["totalSessions"] = totalSessions
        record["lastSessionAt"] = lastSessionAt
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
    /// One photo or video on a post, in the order it was added. Read-side
    /// only: `CommunityStore.post(_:)` writes the four parallel record
    /// fields directly from `CommunityStore.DraftMedia`, which is what
    /// guarantees they stay the same length and the same order as each
    /// other — a `PostMedia` decoded here just reflects whatever the four
    /// arrays on the record said, index by index.
    struct PostMedia: Identifiable, Equatable {
        enum Kind: String, Equatable { case photo, video }
        let index: Int
        var kind: Kind
        /// width / height of the ORIGINAL image or video frame, so the feed
        /// can lay the strip out before anything downloads.
        var aspect: Double
        /// The full-resolution file: the photo itself, or the video
        /// (CloudKit hands assets back as local files).
        var url: URL?
        /// A small JPEG for the feed's strip, so scrolling never downloads a
        /// whole video, or a full-size photo, just to draw a thumbnail.
        var posterURL: URL?
        var id: Int { index }
    }

    let id: String
    let author: String
    var minutes: Int
    var streak: Int
    var technique: String?
    /// The public description ("How did it go?"). Never the private notes.
    var caption: String
    /// Photos and videos, in the order they were added. Empty for a session
    /// with none (a photo was never required, and neither is this).
    var media: [PostMedia]
    var practicedAt: Date
    var createdAt: Date
    /// Strava's activity name: "Evening meditation", or whatever they typed.
    var title: String
    /// The sound played ("Rain", "Silence"), where Strava shows a location.
    var sound: String?

    /// The only fields a post may carry. Locked by test; if you find yourself
    /// adding one, read the rule at the top of this file first. **`score` is
    /// deliberately absent** (2026-09-23) even though the CloudKit record
    /// type still has the field from before that date; nothing here writes
    /// or reads it any more. The four `media*` fields are parallel arrays,
    /// one entry per item, in order: splitting them (rather than one array of
    /// structs) is what CloudKit's record fields can actually hold — an
    /// Asset List, two more Lists for the kind and the aspect ratio.
    static let fields = ["author", "minutes", "streak", "technique", "caption",
                         "media", "mediaPosters", "mediaKinds", "mediaAspects",
                         "practicedAt", "createdAt", "title", "sound"]

    init(id: String = UUID().uuidString, author: String, minutes: Int, streak: Int,
         technique: String? = nil, caption: String = "", media: [PostMedia] = [],
         practicedAt: Date, createdAt: Date = Date(), title: String = "", sound: String? = nil) {
        self.id = id; self.author = author; self.minutes = minutes
        self.streak = streak; self.technique = technique; self.caption = caption
        self.media = media; self.practicedAt = practicedAt; self.createdAt = createdAt
        self.title = title; self.sound = sound
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.post,
              let author = (record["author"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        let assets = (record["media"] as? [CKAsset]) ?? []
        let posters = (record["mediaPosters"] as? [CKAsset]) ?? []
        let kinds = (record["mediaKinds"] as? [String]) ?? []
        let aspects = (record["mediaAspects"] as? [Double]) ?? []
        var media: [PostMedia] = []
        for i in 0..<kinds.count {
            guard let kind = PostMedia.Kind(rawValue: kinds[i]) else { continue }
            media.append(PostMedia(index: i, kind: kind,
                                   aspect: i < aspects.count ? aspects[i] : 0.75,
                                   url: i < assets.count ? assets[i].fileURL : nil,
                                   posterURL: i < posters.count ? posters[i].fileURL : nil))
        }
        self.init(id: record.recordID.recordName,
                  author: author,
                  minutes: record["minutes"] as? Int ?? 0,
                  streak: record["streak"] as? Int ?? 0,
                  technique: record["technique"] as? String,
                  caption: record["caption"] as? String ?? "",
                  media: media,
                  practicedAt: record["practicedAt"] as? Date ?? Date(),
                  createdAt: record["createdAt"] as? Date ?? Date(),
                  title: record["title"] as? String ?? "",
                  sound: record["sound"] as? String)
    }

    /// Every field but the media ones, which `CommunityStore.post(_:)` writes
    /// separately: a draft with no media (an edit that only changes the
    /// caption, say) must leave a post's existing pictures untouched, the
    /// same rule the single-photo field followed.
    func apply(to record: CKRecord) {
        record["title"] = title
        record["sound"] = sound
        record["author"] = CommunityRecordValue.reference(author).ckValue
        record["minutes"] = minutes
        record["streak"] = streak
        record["technique"] = technique
        record["caption"] = caption
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

/// Someone I blocked. **Private to the blocker**: the `Block` record type is
/// readable only by its creator (Security Roles in `CLOUDKIT_SETUP.md`), and
/// the app only ever reads the blocks the current person wrote. See
/// `CommunityStore`'s header for what that means for the blocked person.
struct Block: Identifiable, Equatable {
    /// The record name: a UUID for every new block (`CommunityNames.newBlock`),
    /// or the old `block-<from>-<to>` for one written before 2026-09-29.
    let id: String
    let from: String
    let to: String

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.block,
              let from = (record["from"] as? CKRecord.Reference)?.recordID.recordName,
              let to = (record["to"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(id: record.recordID.recordName, from: from, to: to)
    }

    init(id: String = CommunityNames.newBlock(), from: String, to: String) {
        self.id = id; self.from = from; self.to = to
    }

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
