import Foundation

/// WatchConnectivity dictionary keys shared by both sides. The Codable
/// `SessionParams` / `SessionPayload` are JSON-encoded to `Data` under these keys.
enum WCKeys {
    /// Phone → Watch: JSON-encoded `SessionParams`.
    static let params = "params"
    /// Watch → Phone: JSON-encoded `SessionPayload`.
    static let payload = "payload"
    /// Phone → Watch: end the running session now (the phone's mid-session End
    /// button). Value is the session's UUID string, so a stale end can't stop a
    /// later session. The Watch still owns the authoritative finish + haptic.
    static let end = "end"
}
