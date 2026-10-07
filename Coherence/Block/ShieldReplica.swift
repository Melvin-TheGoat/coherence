#if DEBUG
import SwiftUI
import UIKit

/// The Screen Time shield built the way iOS builds it, for a simulator that
/// cannot draw the real one (2026-10-07). Both stand-ins (`BlockTestShield`,
/// `ShieldReel`) draw this, so a contrast problem a phone shows, the
/// simulator shows too. The old SwiftUI stand-ins drew a solid colour and
/// plain text, which is why they never showed the washed-out labels.
///
/// Read out of `ScreenTimeUI.framework` (`STBlockingViewController`,
/// `NaturalBlockingUIStyling`) in the iOS 26.5 runtime, not guessed:
/// - the shield is a `UIVisualEffectView` whose `backgroundColor` is the
///   configured colour and whose effect is the configured blur, or
///   `UIBlurEffect(style: .systemThickMaterial)` when the blur is nil;
/// - the title and subtitle are plain labels in the configured colours;
/// - the primary button is `UIButton.Configuration.prominentGlass()`
///   (`filled()` before Liquid Glass), size `.large`, corners `.capsule`,
///   the configured fill as `background.backgroundColor`, the label colour
///   as `baseForegroundColor`;
/// - the secondary button is `.glass()`, same size and corners, label colour
///   as `baseForegroundColor`.
/// Checked against Apple's own controller (`ShieldRealHarness`): the same
/// label colours to within a level, in both appearances.
struct ShieldReplica: UIViewRepresentable {
    let palette: ShieldLines.Palette
    let icon: String
    let title: String
    let subtitle: String
    let primary: String
    let secondary: String
    var pressed = false
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    init(look: BlockShieldWords.Look, app: String?, asked: Bool, notificationsAllowed: Bool,
         pressed: Bool = false, onPrimary: @escaping () -> Void = {}, onSecondary: @escaping () -> Void = {}) {
        palette = look.palette
        icon = ShieldLines.icon(look.line)
        title = BlockShieldWords.title(for: app, look: look)
        subtitle = BlockShieldWords.subtitle(for: app, look: look, asked: asked,
                                             notificationsAllowed: notificationsAllowed)
        primary = BlockShieldWords.primary(asked: asked)
        secondary = BlockShieldWords.secondary
        self.pressed = pressed
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    func makeUIView(context: Context) -> ShieldReplicaView { ShieldReplicaView() }

    func updateUIView(_ view: ShieldReplicaView, context: Context) {
        view.apply(self)
    }
}

final class ShieldReplicaView: UIView {
    private let backdrop = UIVisualEffectView(effect: nil)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private var onPrimary: () -> Void = {}
    private var onSecondary: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
        }
        primaryButton.addAction(UIAction { [weak self] _ in self?.onPrimary() }, for: .touchUpInside)
        secondaryButton.addAction(UIAction { [weak self] _ in self?.onSecondary() }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel])
        text.axis = .vertical
        text.alignment = .center
        text.spacing = 8
        text.setCustomSpacing(14, after: iconView)
        let buttons = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttons.axis = .vertical
        buttons.spacing = 10
        for stack in [text, buttons] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            backdrop.contentView.addSubview(stack)
        }
        let guide = backdrop.contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 76),
            iconView.heightAnchor.constraint(equalToConstant: 76),
            text.centerYAnchor.constraint(equalTo: guide.centerYAnchor, constant: -30),
            text.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
            text.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
            buttons.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ r: ShieldReplica) {
        let p = r.palette
        onPrimary = r.onPrimary
        onSecondary = r.onSecondary
        // Exactly what BlockShieldConfiguration hands iOS, drawn the way iOS
        // draws it.
        backdrop.effect = UIBlurEffect(style: UIBlurEffect.Style(rawValue: p.material.rawValue) ?? .systemThickMaterial)
        backdrop.backgroundColor = UIColor(shieldHex: p.paint)
        iconView.image = UIImage(named: r.icon)
        titleLabel.text = r.title
        titleLabel.textColor = UIColor(shieldHex: p.text)
        subtitleLabel.text = r.subtitle
        subtitleLabel.textColor = UIColor(shieldHex: p.soft, alpha: p.softAlpha)

        var primary: UIButton.Configuration
        var secondary: UIButton.Configuration
        if #available(iOS 26.0, *) {
            primary = .prominentGlass()
            secondary = .glass()
        } else {
            primary = .filled()
            secondary = .filled()
        }
        primary.buttonSize = .large
        primary.cornerStyle = .capsule
        primary.title = r.primary
        primary.background.backgroundColor = UIColor(shieldHex: p.button)
        primary.baseForegroundColor = UIColor(shieldHex: p.buttonText)
        secondary.buttonSize = .large
        secondary.cornerStyle = .capsule
        secondary.title = r.secondary
        secondary.baseForegroundColor = .label
        primaryButton.configuration = primary
        secondaryButton.configuration = secondary
        primaryButton.isHighlighted = r.pressed
    }
}

extension UIColor {
    /// A `ShieldLines.Palette` colour (0xRRGGBB), as the Shield extension
    /// builds it.
    convenience init(shieldHex hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
    }
}

/// `PREVIEW_SHIELD_REPLICA=<colour index>` (DEBUG): one palette on the
/// stand-in, still, for a screenshot. `PREVIEW_SHIELD_LINE` picks the line.
struct ShieldReplicaPreview: View {
    private let look: BlockShieldWords.Look = {
        let env = ProcessInfo.processInfo.environment
        let l = Int(env["PREVIEW_SHIELD_LINE"] ?? "") ?? 0
        let c = Int(env["PREVIEW_SHIELD_REPLICA"] ?? "") ?? 0
        return .init(line: ShieldLines.all[l % ShieldLines.all.count],
                     palette: ShieldLines.palettes[c % ShieldLines.palettes.count])
    }()

    var body: some View {
        ShieldReplica(look: look, app: "Instagram", asked: false, notificationsAllowed: true)
            .ignoresSafeArea()
    }
}
#endif
