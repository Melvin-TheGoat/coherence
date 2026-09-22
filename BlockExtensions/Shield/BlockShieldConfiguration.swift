import UIKit
import ManagedSettings
import ManagedSettingsUI

/// What a held app shows (`mockups/block-v1.html`, section 2, first screen).
///
/// **Apple lets a shield carry an icon, a title, a line and two buttons, and
/// nothing else**, so everything Otto has to say lives in 808, reached by the
/// notification the "Ask Otto" button sends. After that tap the shield says
/// the notification is on its way, the way Brainrot's does.
final class BlockShieldConfiguration: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(named: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        make(named: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(named: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        make(named: webDomain.domain)
    }

    private func make(named name: String?) -> ShieldConfiguration {
        // Asked within the last two minutes: the notification is on its way.
        let asked = BlockStore.load().asks.last.map { Date().timeIntervalSince($0) < 120 } ?? false
        let ink = UIColor(named: "ShieldTextPrimary") ?? .darkText
        let soft = UIColor(named: "ShieldTextSecondary") ?? .gray
        let title = name.map { "Otto's holding \($0)" } ?? "Otto's holding this one"
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: UIColor(named: "ShieldBackgroundPrimary"),
            icon: UIImage(named: "OttoShield"),
            title: .init(text: title, color: ink),
            subtitle: .init(text: asked
                                ? "Otto's on his way. Tap the notification up top."
                                : "Meditate first, or ask him for a few minutes.",
                            color: soft),
            primaryButtonLabel: .init(text: asked ? "Send it again" : "Ask Otto", color: ink),
            primaryButtonBackgroundColor: UIColor(named: "ShieldAccentGold"),
            secondaryButtonLabel: .init(text: "Close", color: soft))
    }
}
