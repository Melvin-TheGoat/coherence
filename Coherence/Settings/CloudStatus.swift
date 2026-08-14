#if DEBUG
import Foundation
import CloudKit

/// Answers the two questions that decide whether sync can work at all, and that
/// the app was previously unable to answer on a device: which container the
/// binary is actually entitled to, and whether this iPhone has an iCloud
/// account CloudKit will accept.
///
/// A wrong container and a signed-out phone produce the same symptom, an empty
/// CloudKit Console, so guessing between them costs a build each time.
struct CloudStatus: Equatable {
    var container: String
    var account: String

    static let unknown = CloudStatus(container: "reading…", account: "reading…")

    static func read() async -> CloudStatus {
        let identifier = entitledContainer ?? "none in entitlements"
        guard let entitled = entitledContainer else {
            return CloudStatus(container: identifier, account: "n/a")
        }
        let container = CKContainer(identifier: entitled)
        do {
            switch try await container.accountStatus() {
            case .available:                    return .init(container: identifier, account: "available")
            case .noAccount:                    return .init(container: identifier, account: "NOT SIGNED IN")
            case .restricted:                   return .init(container: identifier, account: "restricted")
            case .couldNotDetermine:            return .init(container: identifier, account: "could not determine")
            case .temporarilyUnavailable:       return .init(container: identifier, account: "temporarily unavailable")
            @unknown default:                   return .init(container: identifier, account: "unknown")
            }
        } catch {
            return .init(container: identifier, account: "error: \(error.localizedDescription)")
        }
    }

    /// Read from the binary's own entitlements rather than hardcoded, so this
    /// reports what actually shipped and not what we believe shipped.
    private static var entitledContainer: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "CloudKitContainerOverride") as? String, !value.isEmpty
        else {
            return "iCloud." + (Bundle.main.bundleIdentifier ?? "")
        }
        return value
    }
}
#endif
