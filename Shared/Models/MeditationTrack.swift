import Foundation
import SwiftData

/// A playable meditation asset (guided / frequency / nature). Silence is a
/// *mode*, never a track row. `audioURL` holds the bundled filename.
@Model
final class MeditationTrack {
    var id: UUID = UUID()
    var type: String = "guided"
    var title: String = ""
    var trackDescription: String?
    var audioURL: String = ""
    var durationSec: Int?
    var sortOrder: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Computed accessor over the String-backed `type`.
    var typeValue: TrackType {
        get { TrackType(rawValue: type) ?? .guided }
        set { type = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        type: String = "guided",
        title: String = "",
        trackDescription: String? = nil,
        audioURL: String = "",
        durationSec: Int? = nil,
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.trackDescription = trackDescription
        self.audioURL = audioURL
        self.durationSec = durationSec
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
