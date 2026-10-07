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
            // Never nil: nil is not "solid", it is .systemThickMaterial, which
            // washes the colour out (see ShieldLines.Material). `paint` is the
            // colour this material draws as `background`.
            backgroundBlurStyle: UIBlurEffect.Style(rawValue: p.material.rawValue),
            backgroundColor: color(p.paint),
            icon: UIImage(named: ShieldLines.icon(look.line)) ?? UIImage(named: "OttoShield"),
            title: .init(text: BlockShieldWords.title(for: name, look: look), color: color(p.text)),
            subtitle: .init(text: BlockShieldWords.subtitle(for: name, look: look, asked: asked,
                                                            notificationsAllowed: BlockStore.notificationsAllowed),
                            color: color(p.soft, alpha: p.softAlpha)),
            // iOS 26 draws this as Liquid Glass and mixes the label with half
            // the fill; a dark fill with a white label survives either way.
            primaryButtonLabel: .init(text: BlockShieldWords.primary(asked: asked), color: color(p.buttonText)),
            primaryButtonBackgroundColor: color(p.button),
            // A glass button whose own tint follows the phone's appearance and
            // what is behind it, so no fixed colour reads on it in both. The
            // system label colour follows the glass.
            secondaryButtonLabel: .init(text: BlockShieldWords.secondary, color: .label))
    }

    private func color(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
    }
}
