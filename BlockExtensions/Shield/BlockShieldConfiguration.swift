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
        let look = BlockShieldWords.look()
        let p = look.palette
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: color(p.background),
            icon: UIImage(named: "OttoShield"),
            title: .init(text: BlockShieldWords.title(for: name, look: look), color: color(p.text)),
            subtitle: .init(text: BlockShieldWords.subtitle(for: name, look: look, asked: asked,
                                                            notificationsAllowed: BlockStore.notificationsAllowed),
                            color: color(p.soft, alpha: p.softAlpha)),
            primaryButtonLabel: .init(text: BlockShieldWords.primary(asked: asked), color: color(p.buttonText)),
            primaryButtonBackgroundColor: color(p.button),
            secondaryButtonLabel: .init(text: BlockShieldWords.secondary, color: color(p.soft, alpha: p.softAlpha)))
    }

    private func color(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
    }
}
