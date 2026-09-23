import Foundation

/// What the RUNNING binary is entitled to, read from its own embedded
/// provisioning profile rather than from what we believe we shipped.
///
/// Two crashes taught this (2026-09-12 and 2026-09-15, both the side-by-side
/// beta, which strips the iCloud entitlement on purpose): `CKContainer` traps
/// on a container the process does not hold, whether the identifier was
/// guessed or came from `CKContainer.default()`. `Persistence.mode` being
/// `.cloudKit` is NOT proof either; SwiftData resolves its container lazily
/// and reports sync active on a build that cannot sync.
///
/// Development, ad-hoc and TestFlight builds carry `embedded.mobileprovision`
/// and the answer is read from it. App Store builds carry no profile; they
/// are signed with exactly the entitlements the App ID holds, and the App ID
/// holds iCloud, so no profile means "trust the entitlement".
enum CloudEntitlement {
    /// The first iCloud container identifier the binary is entitled to, or
    /// nil when a profile is present and lists none.
    static var container: String? {
        // The build says so itself: the side-by-side beta strips the iCloud
        // entitlement from the BINARY, while its provisioning profile still
        // advertises the container its App ID may hold. Reading the profile
        // alone then hands back a container the process does not carry, and
        // `CKContainer(identifier:)` traps on exactly that (2026-09-22, the
        // third time this crash has arrived by a new road). Nothing at
        // runtime can read our own signed entitlements without private API,
        // so the build that removes them leaves this flag behind.
        if Bundle.main.object(forInfoDictionaryKey: "CloudKitDisabled") as? Bool == true { return nil }
        if let value = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerOverride") as? String,
           !value.isEmpty {
            return value
        }
        guard let entitlements = profileEntitlements else { return nil }
        guard let ids = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              let first = ids.first, !first.isEmpty
        else { return nil }
        return first
    }

    /// Whether constructing a `CKContainer` is safe in this process: a
    /// profile that names a container, or no profile at all (store build).
    static var mayHoldContainer: Bool {
        if Bundle.main.object(forInfoDictionaryKey: "CloudKitDisabled") as? Bool == true { return false }
        guard hasProfile else { return true }
        return container != nil
    }

    private static var hasProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    /// The Entitlements dictionary of the embedded profile, if any.
    private static var profileEntitlements: [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<plist"),
              let end = text.range(of: "</plist>")
        else { return nil }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["Entitlements"] as? [String: Any]
    }
}
