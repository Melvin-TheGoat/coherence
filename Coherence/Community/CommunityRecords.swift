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
    /// One person's half of a shared goal (Meditating together, 2026-10-14).
    /// See `GoalHalf`.
    static let goalMember = "GoalMember"
    /// A nudge or a high five from one friend to another, once a day.
    static let nudge = "Nudge"
    /// An invite code (2026-10-18): record name `invitecode-<CODE>`, one
    /// field `profile` pointing at its owner, like a username reservation.
    /// See `InviteCode` and `CommunityStore.newInviteCode`.
    static let inviteCode = "InviteCode"
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
    /// My half of a goal: one per person per goal, so a second save
    /// overwrites rather than duplicates.
    static func goalMember(goal: String, member: String) -> String { "goal-" + goal + "-" + member }
    /// At most one nudge from me to them per day, by construction.
    static func nudge(from: String, to: String, day: String) -> String { "nudge-" + from + "-" + to + "-" + day }
    /// A week finished together, told to the friend: one per week, so
    /// telling it twice is a no-op. `first` is the week's first day key.
    static func weekDone(from: String, to: String, first: String) -> String {
        "nudge-week-" + from + "-" + to + "-" + first
    }
    /// An invite code, by its canonical form (`InviteCode.normalize`).
    static func inviteCode(_ code: String) -> String { "invitecode-" + code }
}

/// One person's half of a shared goal (Meditating together, 2026-10-14).
///
/// Shaped by the same constraint as a friendship: only a record's creator can
/// modify it in the public database, so each person writes their own half
/// and nobody edits the other's. The inviter's half is the invite; the
/// invitee's half, written when they say yes (or "Not now"), is the answer.
///
/// - `days` is THIS person's qualifying days since the goal began
///   (`GoalDay`, `"yyyy-MM-dd:minutes"`), kept current by
///   `CommunityStore.publishGoalDays`. Only days and minutes, never a score,
///   a heart rate or anything measured off the body (the rule at the top of
///   this file). They are published only while somebody is in a goal, and
///   only from the goal's start.
/// - `startDay` is set by the person who accepts: their local today, which
///   becomes the first day of week one for both.
/// - `kind` is "invite" on the inviter's half, and "accept" or "decline"
///   ("Not now") on the answer, so the push subscriptions can tell an invite
///   from an acceptance and never announce a "Not now" as a yes.
/// - `endedAt` on either half ends the goal for both.
///
/// **New CloudKit record type, must be promoted to Production with its
/// indexes before release** (`CLOUDKIT_SETUP.md`, "Meditating together").
struct GoalHalf: Identifiable, Equatable {
    enum Kind: String { case invite, accept, decline }

    let goal: String
    let member: String
    let partner: String
    var kind: Kind
    var target: Int
    var startDay: String?
    var days: [GoalDay]
    var endedAt: Date?
    var declinedAt: Date?
    var createdAt: Date
    /// The writer's display name, for the push alert ("Maya wants to
    /// meditate with you"): a subscription's notification can only quote
    /// fields of the record it fires on.
    var fromName: String

    var id: String { CommunityNames.goalMember(goal: goal, member: member) }

    init(goal: String, member: String, partner: String, kind: Kind, target: Int,
         startDay: String? = nil, days: [GoalDay] = [], endedAt: Date? = nil,
         declinedAt: Date? = nil, createdAt: Date = Date(), fromName: String = "") {
        self.goal = goal; self.member = member; self.partner = partner; self.kind = kind
        self.target = target; self.startDay = startDay; self.days = days; self.endedAt = endedAt
        self.declinedAt = declinedAt; self.createdAt = createdAt; self.fromName = fromName
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.goalMember,
              let goal = record["goal"] as? String,
              let member = (record["member"] as? CKRecord.Reference)?.recordID.recordName,
              let partner = (record["partner"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(goal: goal, member: member, partner: partner,
                  kind: Kind(rawValue: record["kind"] as? String ?? "") ?? .invite,
                  target: min(max(record["target"] as? Int ?? SharedGoal.defaultTarget, 1), 7),
                  startDay: record["startDay"] as? String,
                  days: ((record["days"] as? [String]) ?? []).compactMap(GoalDay.init(encoded:)),
                  endedAt: record["endedAt"] as? Date,
                  declinedAt: record["declinedAt"] as? Date,
                  createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
                  fromName: record["fromName"] as? String ?? "")
    }

    func apply(to record: CKRecord) {
        record["goal"] = goal
        record["member"] = CommunityRecordValue.reference(member).ckValue
        record["partner"] = CommunityRecordValue.reference(partner).ckValue
        record["kind"] = kind.rawValue
        record["target"] = target
        record["startDay"] = startDay
        record["days"] = days.map(\.encoded)
        record["endedAt"] = endedAt
        record["declinedAt"] = declinedAt
        record["createdAt"] = createdAt
        record["fromName"] = fromName
    }

    /// The pair as I see it, from my half and theirs (either may be missing).
    static func pair(mine: GoalHalf?, theirs: GoalHalf?, me: String) -> GoalPair? {
        guard let any = mine ?? theirs else { return nil }
        let partner = any.member == me ? any.partner : any.member
        let inviteHalf = [mine, theirs].compactMap { $0 }.first { $0.kind == .invite }
        let invite = inviteHalf ?? any
        let answer = [mine, theirs].compactMap { $0 }.first { $0.kind != .invite }
        let state: GoalPair.State
        // No invite half means it was withdrawn (or its writer deleted their
        // account), possibly in the same moment the friend said yes: an
        // answer on its own is a goal that no longer exists, never a running
        // one (found in review, 2026-10-18).
        if inviteHalf == nil || mine?.endedAt != nil || theirs?.endedAt != nil || answer?.kind == .decline {
            state = .over
        } else if answer != nil, answer?.startDay != nil {
            state = .active
        } else {
            state = invite.member == me ? .waitingForThem : .waitingForMe
        }
        return GoalPair(id: any.goal, partner: partner, target: invite.target,
                        startDay: answer?.startDay, state: state,
                        myDays: mine?.days ?? [], theirDays: theirs?.days ?? [],
                        invitedByMe: invite.member == me,
                        createdAt: invite.createdAt)
    }
}

/// A nudge ("Meditate today?") or a high five ("You both hit it") from one
/// friend to another, at most one a day (`CommunityNames.nudge`). The push
/// alert quotes `fromName`. **New CloudKit record type** (see `GoalHalf`).
struct Nudge: Identifiable, Equatable {
    /// `week`: sent by the phone of whoever finished a shared week second,
    /// so the other gets a push (2026-10-27). Never shown as a nudge.
    enum Kind: String { case nudge, cheer, week }

    /// The `day` a `week` record carries. Builds before 1.4.1 read every
    /// Nudge as a nudge or a high five and show only those from the last
    /// two days, so a day that is never recent keeps them from showing a
    /// week record as one. The week itself is in the record's name.
    static let weekRecordDay = "0000-01-01"

    let from: String
    let to: String
    let day: String
    var kind: Kind
    var fromName: String
    var createdAt: Date

    var id: String { CommunityNames.nudge(from: from, to: to, day: day) }

    init(from: String, to: String, day: String, kind: Kind = .nudge, fromName: String = "", createdAt: Date = Date()) {
        self.from = from; self.to = to; self.day = day; self.kind = kind
        self.fromName = fromName; self.createdAt = createdAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.nudge,
              let from = (record["from"] as? CKRecord.Reference)?.recordID.recordName,
              let to = (record["to"] as? CKRecord.Reference)?.recordID.recordName,
              let day = record["day"] as? String else { return nil }
        self.init(from: from, to: to, day: day,
                  kind: Kind(rawValue: record["kind"] as? String ?? "") ?? .nudge,
                  fromName: record["fromName"] as? String ?? "",
                  createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date())
    }

    func apply(to record: CKRecord) {
        record["from"] = CommunityRecordValue.reference(from).ckValue
        record["to"] = CommunityRecordValue.reference(to).ckValue
        record["day"] = day
        record["kind"] = kind.rawValue
        record["fromName"] = fromName
        record["createdAt"] = createdAt
    }
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
    /// This person's newest invite code, canonical (`InviteCode`), once they
    /// have one. Set only through `CommunityStore.newInviteCode`, never by
    /// `apply`, so a rename keeps it.
    var inviteCode: String?
    /// Every code they have sent, newest last (Aziz, 2026-10-18: each invite
    /// gets its own code). Any of them still finds them. Older profiles have
    /// only `inviteCode`.
    var inviteCodes: [String] = []
    /// All the codes that find this person.
    var allInviteCodes: Set<String> { Set(inviteCodes + [inviteCode].compactMap { $0 }) }
    /// People who joined with my code and whom my app has since answered
    /// with its own edge (`CommunityStore.answerCodeJoins`). From then on the
    /// friendship is an ordinary one, so removing or blocking them sticks:
    /// the code on their edge no longer counts. Written only by that call.
    var answeredJoins: [String] = []

    init(id: String, username: String, displayName: String, firstSessionAt: Date? = nil,
         createdAt: Date = Date(), avatarURL: URL? = nil, practice: PracticeStats = .empty,
         inviteCode: String? = nil, inviteCodes: [String] = [], answeredJoins: [String] = []) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.firstSessionAt = firstSessionAt
        self.createdAt = createdAt
        self.avatarURL = avatarURL
        self.practice = practice
        self.inviteCode = inviteCode
        self.inviteCodes = inviteCodes
        self.answeredJoins = answeredJoins
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
                  practice: PracticeStats(record: record),
                  inviteCode: record["inviteCode"] as? String,
                  inviteCodes: record["inviteCodes"] as? [String] ?? [],
                  answeredJoins: record["answeredJoins"] as? [String] ?? [])
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
    /// The invite code this edge was written with (2026-10-18): the code of
    /// `to`, whose yes it carries, so the pair are friends without `to`
    /// answering (`CommunityStore.codeFriends`). Nil on an ordinary request.
    var viaCode: String?
    /// The writer's name, for the push to `to` ("Sam joined 808 with your
    /// code"): a subscription can only quote fields of its own record.
    var fromName: String?

    var id: String { CommunityNames.edge(from: from, to: to) }

    init(from: String, to: String, createdAt: Date = Date(), viaCode: String? = nil, fromName: String? = nil) {
        self.from = from; self.to = to; self.createdAt = createdAt
        self.viaCode = viaCode; self.fromName = fromName
    }

    init?(record: CKRecord) {
        guard record.recordType == CommunityType.edge,
              let from = (record["from"] as? CKRecord.Reference)?.recordID.recordName,
              let to = (record["to"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        self.init(from: from, to: to, createdAt: record["createdAt"] as? Date ?? Date(),
                  viaCode: record["viaCode"] as? String, fromName: record["fromName"] as? String)
    }

    func apply(to record: CKRecord) {
        record["from"] = CommunityRecordValue.reference(from).ckValue
        record["to"] = CommunityRecordValue.reference(to).ckValue
        record["createdAt"] = createdAt
        // Only on a code edge: an ordinary request carries neither field.
        if let viaCode { record["viaCode"] = viaCode }
        if let fromName { record["fromName"] = fromName }
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
        // A Reference, as the schema has always defined it (CLOUDKIT_SETUP.md).
        // Written as a String from 2026-09-14, which CloudKit refused with
        // "invalid attempt to set value type STRING for field 'target'", so
        // every report failed; found on two phones 2026-10-01. A field's type
        // can never change once in Production, so the app had to match.
        record["target"] = CommunityRecordValue.reference(target).ckValue
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
