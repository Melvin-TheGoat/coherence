import Foundation

/// Points earned by meditating, spent on hats for Otto (Melvin, 2026-09-27:
/// "A store tab where you can buy Otto hats with points that you get from
/// meditating"). **One point per whole minute meditated.**
///
/// **Derived, never stored as a balance** — the same rule as the streak
/// (`StreakCalculator`) and Otto's glow (`OttoAura`): nothing here is
/// written to disk, so there is nothing to keep in sync or let go stale.
/// `earned` sums Sessions, `spent` sums the prices of owned hats read off
/// the current catalog, and `balance` is the difference, floored at zero so
/// the shop never shows a negative number.
///
/// **Hand-logged sessions earn nothing** (`Session.isLogged`, the "Record
/// one" flow for a sit done without the app). A typed-in session has no
/// instrument behind it, so paying it in points would make typing a bigger
/// number the way to buy a hat — the same reason a logged session never
/// opens Block's held apps.
enum OttoPoints {

    /// Whole minutes meditated, floored, over every session that was not
    /// hand-logged. `durationSec / 60` is Swift's integer division, which
    /// floors for non-negative values.
    static func earned(sessions: [Session]) -> Int {
        sessions.reduce(0) { total, session in
            guard !session.isLogged else { return total }
            return total + session.durationSec / 60
        }
    }

    /// The price of every hat actually owned, read off `catalog` by id.
    ///
    /// **Ownership is membership in `ownedHatIDs`, never a catalog lookup a
    /// later edit can undo.** A hat repriced after it was bought is charged
    /// at its price when this runs (there is no stored receipt to remember
    /// what was actually paid), and a hat removed from the catalog entirely
    /// costs nothing here, since there is nothing left to charge for it —
    /// either way, the id stays in `ownedHatIDs` and the hat stays owned.
    static func spent(ownedHatIDs: [String], catalog: [HatCatalog.Item] = HatCatalog.all) -> Int {
        let prices = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.price) })
        return ownedHatIDs.reduce(0) { $0 + (prices[$1] ?? 0) }
    }

    /// Earned minus spent, floored at zero. A repriced or delisted hat must
    /// never leave someone reading a negative balance.
    static func balance(sessions: [Session], ownedHatIDs: [String],
                        catalog: [HatCatalog.Item] = HatCatalog.all) -> Int {
        max(0, earned(sessions: sessions) - spent(ownedHatIDs: ownedHatIDs, catalog: catalog))
    }
}
