#if DEBUG
import SwiftUI
import UIKit

#if targetEnvironment(simulator)
/// Apple's own shield, run in the simulator (DEBUG, simulator only).
/// `PREVIEW_SHIELD_REAL=<colour index>` loads `ScreenTimeUI.framework`, builds
/// its `STBlockingViewController` from the framework's own storyboard and
/// hands it a configuration encoded the way `ManagedSettingsUI` encodes ours
/// (`NSKeyedArchiver` colours, an archived `UIBlurEffect`, PNG icon data).
/// It is the real view code, so what it draws is what a phone draws.
/// Private API, compiled out of every build that is not a DEBUG simulator build.
struct ShieldRealHarness: UIViewControllerRepresentable {
    struct Colors {
        var background: UIColor
        var blur: UIBlurEffect.Style?
        var title: UIColor
        var subtitle: UIColor
        var button: UIColor
        var buttonText: UIColor
        var secondary: UIColor
    }
    let colors: Colors
    let icon: String
    let title: String
    let subtitle: String
    let primary: String
    let secondary: String

    func makeUIViewController(context: Context) -> UIViewController {
        guard dlopen("/System/Library/PrivateFrameworks/ScreenTimeUI.framework/ScreenTimeUI", RTLD_NOW) != nil,
              let vcClass = NSClassFromString("STBlockingViewController"),
              let configClass = NSClassFromString("MOShieldConfiguration") as? NSObject.Type,
              let labelClass = NSClassFromString("MOShieldLabel") as? NSObject.Type else {
            return failed("ScreenTimeUI did not load")
        }
        let bundle = Bundle(for: vcClass)
        let storyboard = UIStoryboard(name: "BlockingUI-Translucent-iOS", bundle: bundle)
        guard let vc = storyboard.instantiateInitialViewController() else { return failed("no storyboard") }

        func data(_ c: UIColor) -> Data { (try? NSKeyedArchiver.archivedData(withRootObject: c, requiringSecureCoding: true)) ?? Data() }
        func label(_ text: String, _ c: UIColor) -> NSObject {
            typealias Init = @convention(c) (AnyObject, Selector, NSString, NSData) -> NSObject
            let sel = NSSelectorFromString("initWithText:colorData:")
            let obj = labelClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
            let imp = unsafeBitCast(labelClass.instanceMethod(for: sel), to: Init.self)
            return imp(obj, sel, text as NSString, data(c) as NSData)
        }
        let k = colors
        let effect = k.blur.map { try? NSKeyedArchiver.archivedData(withRootObject: UIBlurEffect(style: $0), requiringSecureCoding: true) } ?? nil
        typealias ConfigInit = @convention(c) (AnyObject, Selector, NSData?, NSData?, NSData?, NSObject?, NSObject?,
                                               NSObject?, NSData?, NSObject?, NSArray?) -> NSObject
        let csel = NSSelectorFromString("initWithBackgroundColorData:backgroundEffectData:iconData:title:subtitle:primaryButtonLabel:primaryButtonColorData:secondaryButtonLabel:secondaryButtonSubmenuItems:")
        let cobj = configClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        let cimp = unsafeBitCast(configClass.instanceMethod(for: csel), to: ConfigInit.self)
        let config = cimp(cobj, csel, data(k.background) as NSData, effect as NSData?,
                          UIImage(named: icon)?.pngData() as NSData?,
                          label(title, k.title),
                          label(subtitle, k.subtitle),
                          label(primary, k.buttonText),
                          data(k.button) as NSData,
                          label(secondary, k.secondary), nil)
        vc.loadViewIfNeeded()
        typealias Update = @convention(c) (AnyObject, Selector, NSObject, NSString?, NSString?) -> Void
        let usel = NSSelectorFromString("_updateAppearanceWithCustomConfiguration:defaultMessageFormatKey:defaultMessageArgument:")
        guard vc.responds(to: usel) else { return failed("no update selector") }
        let uimp = unsafeBitCast(vc.method(for: usel), to: Update.self)
        uimp(vc, usel, config, nil, nil)
        // The controller starts with its text and buttons faded out and shows
        // them when the system presents it.
        typealias Show = @convention(c) (AnyObject, Selector, Bool, AnyObject?) -> Void
        let ssel = NSSelectorFromString("showWithAnimation:completionHandler:")
        if vc.responds(to: ssel) {
            unsafeBitCast(vc.method(for: ssel), to: Show.self)(vc, ssel, false, nil)
        }
        for name in ["_restoreTextAndButtons", "_hideHourglass"] where vc.responds(to: NSSelectorFromString(name)) {
            vc.perform(NSSelectorFromString(name))
        }
        NSLog("Shield harness: %@ view %@", String(describing: type(of: vc)), String(describing: vc.view))
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    private func failed(_ why: String) -> UIViewController {
        let vc = UIViewController()
        let l = UILabel()
        l.text = "Shield harness: \(why)"
        l.frame = CGRect(x: 20, y: 200, width: 350, height: 40)
        vc.view.addSubview(l)
        NSLog("Shield harness: %@", why)
        return vc
    }
}

#endif

/// `PREVIEW_SHIELD_REAL=<colour index>`; `PREVIEW_SHIELD_LINE` picks the line.
struct ShieldRealPreview: View {
    var body: some View {
        #if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        let l = Int(env["PREVIEW_SHIELD_LINE"] ?? "") ?? 0
        let c = Int(env["PREVIEW_SHIELD_REAL"] ?? "") ?? 0
        let look = BlockShieldWords.Look(line: ShieldLines.all[l % ShieldLines.all.count],
                                         palette: ShieldLines.palettes[c % ShieldLines.palettes.count])
        ShieldRealHarness(colors: Self.colors(look.palette, index: c), icon: ShieldLines.icon(look.line),
                          title: BlockShieldWords.title(for: "Instagram", look: look),
                          subtitle: BlockShieldWords.subtitle(for: "Instagram", look: look, asked: false,
                                                              notificationsAllowed: true),
                          primary: BlockShieldWords.primary(asked: false),
                          secondary: BlockShieldWords.secondary)
            .ignoresSafeArea()
        #else
        Text("The shield harness runs on the simulator only.")
        #endif
    }

    #if targetEnvironment(simulator)
    static func colors(_ p: ShieldLines.Palette, index c: Int) -> ShieldRealHarness.Colors {
        let env = ProcessInfo.processInfo.environment
        // Exactly what BlockShieldConfiguration hands iOS.
        var colors = ShieldRealHarness.Colors(
            background: UIColor(shieldHex: p.paint),
            blur: UIBlurEffect.Style(rawValue: p.material.rawValue),
            title: UIColor(shieldHex: p.text), subtitle: UIColor(shieldHex: p.soft, alpha: p.softAlpha),
            button: UIColor(shieldHex: p.button), buttonText: UIColor(shieldHex: p.buttonText),
            secondary: .label)
        if let raw = env["PREVIEW_SHIELD_BLUR"] {
            colors.blur = Int(raw).flatMap(UIBlurEffect.Style.init(rawValue:))
        }
        // SH_SPEC: ten ';'-separated specs, one per colour index, each
        // "paint,blur,title,subtitle,fill,label,close"; colours are hex
        // (optionally @alpha) or a system name (label, secondaryLabel,
        // systemBackground). Empty fields keep the palette's own.
        if let spec = env["SH_SPEC"]?.split(separator: ";", omittingEmptySubsequences: false),
           c < spec.count {
            let f = spec[c].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            func col(_ s: String) -> UIColor? {
                switch s {
                case "": return nil
                case "label": return .label
                case "secondaryLabel": return .secondaryLabel
                case "systemBackground": return .systemBackground
                default:
                    let parts = s.split(separator: "@")
                    guard let hex = UInt32(parts[0], radix: 16) else { return nil }
                    return UIColor(shieldHex: hex, alpha: parts.count > 1 ? Double(parts[1]) ?? 1 : 1)
                }
            }
            if f.count > 0, let v = col(f[0]) { colors.background = v }
            if f.count > 1, !f[1].isEmpty { colors.blur = Int(f[1]).flatMap(UIBlurEffect.Style.init(rawValue:)) }
            if f.count > 2, let v = col(f[2]) { colors.title = v }
            if f.count > 3, let v = col(f[3]) { colors.subtitle = v }
            if f.count > 4, let v = col(f[4]) { colors.button = v }
            if f.count > 5, let v = col(f[5]) { colors.buttonText = v }
            if f.count > 6, let v = col(f[6]) { colors.secondary = v }
        }
        return colors
    }
    #endif
}
#endif
