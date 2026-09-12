import Foundation

/// The handle people will find each other by once friends exist. Until a
/// backend can enforce uniqueness it is cosmetic, which is why it is optional
/// everywhere it is asked for (5.1.1: nothing the core function does not need
/// may be required).
enum Username {
    static let maxLength = 20

    /// Lowercase; letters, digits, underscore and dot only; a leading "@"
    /// stripped; clipped to `maxLength`. Empty in means nil out, so callers
    /// never store "" as a handle.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("@") { s.removeFirst() }
        s = String(s.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "." })
        s = String(s.prefix(maxLength))
        return s.isEmpty ? nil : s
    }

    /// "@melvin", or nil when there is no handle to show.
    static func display(_ handle: String?) -> String? {
        guard let handle, !handle.isEmpty else { return nil }
        return "@" + handle
    }
}
