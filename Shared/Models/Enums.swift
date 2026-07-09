import Foundation

// String-backed enums. All persisted properties store the rawValue String
// (CloudKit-safe primitives); models expose computed accessors that map to
// these enums. Unknown/legacy strings fall back to a sensible default rather
// than trapping.

enum Theme: String, CaseIterable, Codable {
    case system
    case light
    case dark
}

enum TrackType: String, CaseIterable, Codable {
    case guided
    case frequency
    case nature
}

enum SessionMode: String, CaseIterable, Codable {
    case guided
    case frequency
    case nature
    case silence
}
