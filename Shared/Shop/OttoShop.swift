import Foundation

/// Buying and wearing a hat: the two writes the Store tab makes, kept out of
/// the view so they are tested without SwiftUI. Both mutate the `Preferences`
/// row handed in; the caller (holding the `ModelContext`) saves it.
enum OttoShop {

    /// Buys `hatID` if it is not already owned and the balance covers its
    /// price. Returns whether the purchase went through; `prefs` is left
    /// untouched on a refusal (already owned, unknown id, or short of
    /// points), so a failed tap can never silently deduct anything.
    @discardableResult
    static func buy(_ hatID: String, prefs: Preferences, sessions: [Session],
                    catalog: [HatCatalog.Item] = HatCatalog.all) -> Bool {
        guard let item = HatCatalog.item(hatID) ?? catalog.first(where: { $0.id == hatID }) else { return false }
        var owned = prefs.ownedHatIDList
        guard !owned.contains(hatID) else { return false }
        let balance = OttoPoints.balance(sessions: sessions, ownedHatIDs: owned, catalog: catalog)
        guard balance >= item.price else { return false }
        owned.append(hatID)
        prefs.ownedHatIDList = owned
        prefs.updatedAt = Date()
        return true
    }

    /// Wears an owned hat, or clears one with `nil`. Refused for a hat not
    /// owned, so tapping a card you have not bought can never dress him in
    /// it as a side effect of previewing it.
    @discardableResult
    static func wear(_ hatID: String?, prefs: Preferences) -> Bool {
        guard let hatID else {
            prefs.wornHatIDValue = nil
            prefs.updatedAt = Date()
            return true
        }
        guard prefs.ownedHatIDList.contains(hatID) else { return false }
        prefs.wornHatIDValue = hatID
        prefs.updatedAt = Date()
        return true
    }
}
