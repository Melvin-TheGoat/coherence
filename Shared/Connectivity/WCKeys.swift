import Foundation

/// WatchConnectivity dictionary keys shared by both sides. The Codable
/// `SessionParams` / `SessionPayload` are JSON-encoded to `Data` under these keys.
enum WCKeys {
    /// Phone → Watch: JSON-encoded `SessionParams`.
    static let params = "params"
    /// Watch → Phone: JSON-encoded `SessionPayload`.
    static let payload = "payload"
}
