import Foundation
import SwiftData

/// A photo or video kept with a session. Several are allowed (Melvin,
/// 2026-09-23: "you should be able to share multiple photos or videos"),
/// ordered by `order`, appended by `SessionStore.addPhoto` and removed one
/// at a time by `SessionStore.removePhotoItem`.
///
/// Aziz, 2026-09-15: "you should still have an option to take pictures after
/// the meditation even if its a private one and then those pictures can be
/// shown in the calendar." Until then the selfie existed only as the picture
/// on a Friends post, uploaded and forgotten. Now it is the person's own
/// record of having sat, kept with their sessions, and sharing is one more
/// thing that can be done with it.
///
/// Lives in the SYNCED store, not the health one: a photo is not health data,
/// so it may ride the user's private iCloud like the sessions do, survive a
/// new phone with them, and die with the account. `jpeg` is external storage
/// (about 200 KB at 1080 px); `thumbnail` is small enough to sit inline and is
/// what the calendar and the rows draw, so a month view never decodes a
/// full-size image.
///
/// CloudKit-safe like every model here: every property optional or defaulted,
/// the session a plain `UUID?`, ordering and the 10-item cap enforced in
/// `SessionStore`, not in the schema. `order` is defaulted so every row saved
/// before it existed reads as 0, which is still a valid, sortable order.
@Model
final class SessionPhoto {
    var id: UUID = UUID()
    var sessionID: UUID?
    var takenAt: Date = Date()
    @Attribute(.externalStorage) var jpeg: Data?
    /// About 240 px on the long side. Drawn on the calendar and in rows, and
    /// on the feed's media strip (a small download for a post that may carry
    /// several).
    var thumbnail: Data?
    /// A video, when they picked one (Melvin, 2026-09-22: any photo and any
    /// video, shared or private). `jpeg` then holds its first frame, so the
    /// calendar, the rows and the results screen draw it without knowing
    /// there is a film behind it. Exported small before it is stored.
    @Attribute(.externalStorage) var video: Data?
    /// Position among a session's items, lowest first. `SessionStore.photo`
    /// (the single-item callers: the calendar dot, `EvidenceRow`, the results
    /// screen) reads whichever item has the lowest order.
    var order: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), sessionID: UUID? = nil, takenAt: Date = Date(),
         jpeg: Data? = nil, thumbnail: Data? = nil, video: Data? = nil,
         order: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.takenAt = takenAt
        self.jpeg = jpeg
        self.thumbnail = thumbnail
        self.video = video
        self.order = order
        self.createdAt = createdAt
    }
}
