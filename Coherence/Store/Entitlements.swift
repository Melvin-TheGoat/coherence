import Foundation

/// Which share-card design is in use.
///
/// Skins change the card's ground and nothing else. They must never change
/// which DATA appears on the card, or a cosmetic becomes a second entitlement
/// axis by accident and the "free gives you the score" rule stops being one
/// rule. The visual definition of each skin lives in `ShareCard.swift`.
enum CardSkin: String, CaseIterable, Identifiable {
    case midnight, goldLeaf, still, ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .goldLeaf: return "Gold Leaf"
        case .still:    return "Still"
        case .ember:    return "Ember"
        }
    }

    /// The one skin free 808 ships with.
    static let free: CardSkin = .midnight
}

/// What this person may see.
///
/// **The rule, and the only one anybody needs to remember: free gives you the
/// score, paid gives you the evidence behind it.** A new feature sorts itself
/// by asking whether it is the readout or the reasoning.
///
/// Views ask THIS, never `store.entitled` directly. Where the free tier sits is
/// a product decision that will move, and when it moves it should move in one
/// file rather than in fifteen `if` statements.
struct Entitlements {
    let paid: Bool

    /// The three signal curves on the results screen.
    var curves: Bool { paid }
    /// Metric tiles, the resonance chip, and the per-curve readings. Anything
    /// that puts a measured NUMBER in front of the user.
    var metrics: Bool { paid }
    /// The guided journey, the only content 808 owns. Nature, frequency and
    /// silence are free, and so is outside audio.
    var guidedTrack: Bool { paid }
    /// Curves drawn inside the share card. Locked for the same reason the
    /// in-app curves are: otherwise screenshotting your own card is the way
    /// around the lock.
    var shareCurves: Bool { paid }

    func canUse(_ skin: CardSkin) -> Bool { paid || skin == .free }

    /// Everything unlocked. The state the app is in whenever it cannot sell.
    static let unlocked = Entitlements(paid: true)

    /// The rule, as a pure function, so it can be tested without a live
    /// StoreKit session. `Store.entitlements` is this and nothing else.
    static func resolve(state: Store.State, entitled: Bool) -> Entitlements {
        Entitlements(paid: state != .ready || entitled)
    }
}

extension Store {

    /// Free is the floor, not a failure state.
    ///
    /// **Read the condition carefully before changing it.** While the store
    /// cannot sell (`.loading`, `.unavailable`) EVERYONE is treated as paid.
    /// That is what keeps the whole pre-billing beta unlocked with no flag to
    /// remember, and it means a network hiccup can never downgrade someone who
    /// already paid. StoreKit caches entitlements on device, so a real payer
    /// stays entitled offline; a user we simply cannot classify yet must never
    /// be classified as free.
    ///
    /// Simplifying this to `entitled` alone would strip every beta tester of
    /// their curves the moment products go live, before anyone has had the
    /// chance to buy. This is the same reasoning the old `RootView.locked`
    /// carried, and it survives the move.
    #if DEBUG
    /// **REVIEW BUILD SWITCH. Set back to `false` before committing.**
    ///
    /// True makes every DEBUG build run as a FREE user, so the locked screens
    /// can be looked at by tapping the app icon rather than by remembering a
    /// launch argument. It exists because the locked screens are otherwise
    /// unreachable off the App Store: no products load on a development build,
    /// so the store reports `.unavailable` and everyone is correctly treated
    /// as paid.
    ///
    /// DEBUG-only, so it can never reach TestFlight or the App Store. It can
    /// absolutely confuse the other developer, which is why it is one named
    /// constant at the top of the file rather than a condition buried below.
    ///
    /// Flipped to true 2026-08-24 for Aziz's on-device design review of the
    /// free tier, and back to false before the branch was pushed. Flip it (or
    /// launch with PREVIEW_FREE=1) to review the locked screens; the paywall's
    /// buy button then simulates the purchase, and Settings > "Free tier
    /// (debug)" switches back to free.
    static let previewFreeByDefault = false
    #endif

    var entitlements: Entitlements {
        #if DEBUG
        // `PREVIEW_FREE=1` forces the free tier for one launch; `PREVIEW_PAID=1`
        // overrides the review switch above so a preview build can still be
        // checked as a paying user without rebuilding. `previewEntitled` is the
        // review build's simulated purchase: on a build with no products the
        // buy button cannot run StoreKit, so without it the whole
        // lock → trial → unlock loop was unreviewable ("when i click to buy
        // the free trial, it doesnt actually unlock the graphs", Aziz,
        // 2026-08-24). Settings carries the switch to go back to free.
        let env = ProcessInfo.processInfo.environment
        if env["PREVIEW_PAID"] == "1" { return .unlocked }
        if previewEntitled { return .unlocked }
        if env["PREVIEW_FREE"] == "1" || Store.previewFreeByDefault {
            return Entitlements(paid: false)
        }
        #endif
        return Entitlements.resolve(state: state, entitled: entitled)
    }
}
