import SwiftUI

/// Root-level behaviour for the paywall-after-the-first-meditation flow, kept
/// off `ContentView`'s modifier chain (it has hit the type-checker limit
/// before; see the FriendsHooks note in CLAUDE.md).
///
/// Two moments: the first Home after onboarding opens the setup sheet, since
/// the tour ended on a Begin; and a free user leaving the covered results
/// screen meets the paywall.
struct FirstSessionHooks: ViewModifier {
    @ObservedObject var offer: FirstSessionOffer
    let paid: Bool
    let onOpenSetup: () -> Void
    let onPaywallDue: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if OnboardingHandoff.takeSetupRequest() {
                    // Let the root transition from onboarding finish first.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        onOpenSetup()
                    }
                }
            }
            .onChange(of: offer.due) { _, due in
                guard due else { return }
                if paid {
                    // Nothing to sell; close the grant quietly.
                    offer.markShown()
                } else {
                    onPaywallDue()
                }
            }
    }
}

extension View {
    func firstSessionHooks(offer: FirstSessionOffer, paid: Bool,
                           onOpenSetup: @escaping () -> Void,
                           onPaywallDue: @escaping () -> Void) -> some View {
        modifier(FirstSessionHooks(offer: offer, paid: paid,
                                   onOpenSetup: onOpenSetup, onPaywallDue: onPaywallDue))
    }
}
