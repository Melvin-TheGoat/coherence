import SwiftUI
import WatchConnectivity

/// Whether 808 can measure with an Apple Watch right now (Aziz, 2026-09-28,
/// `mockups/apple-watch/`). Read from the WatchConnectivity session
/// `SessionCoordinator` activates at launch; nothing is asked of anybody.
///
/// **Connected** means a Watch is paired to this iPhone AND 808 is installed
/// on it. Paired without 808 is "Not connected", with the steps to fix it.
/// No Watch paired shows nothing on the Ready screen: somebody without a
/// Watch is never told what they are missing.
@MainActor
final class WatchLink: ObservableObject {
    static let shared = WatchLink()

    enum Status: Equatable { case noWatch, notInstalled, connected }
    @Published private(set) var status: Status = .noWatch

    /// The switch's storage: the Ready screen's way to sit, `.watch` when
    /// the Watch measures (`SitKind`). One value, so the Meditate card, the
    /// switch and Settings can never disagree.
    static let choiceKey = "ready.sitKind"
    /// Set the first time the Watch actually runs a session for 808 (a start
    /// ack or a measured session landing, `noteConnected`), so the switch
    /// turns itself on once and then keeps the person's choice. Having 808
    /// installed on the Watch is NOT that: it says the app is there, never
    /// that it has ever answered.
    static let everConnectedKey = "watch.everConnected.v1"

    var connected: Bool { status == .connected }

    private init() { refresh() }

    /// Re-reads the Watch's state. Called at launch, whenever the Watch's
    /// pairing or install changes, and when a screen that shows it appears.
    func refresh() {
        #if DEBUG
        // `PREVIEW_WATCH=connected|notInstalled` shows the switch on a
        // simulator, which never has a Watch paired.
        switch ProcessInfo.processInfo.environment["PREVIEW_WATCH"] {
        case "connected": status = .connected; noteConnected(); return
        case "notInstalled": status = .notInstalled; return
        default: break
        }
        #endif
        let next: Status
        if WCSession.isSupported(), WCSession.default.activationState == .activated,
           WCSession.default.isPaired {
            next = WCSession.default.isWatchAppInstalled ? .connected : .notInstalled
        } else {
            next = .noWatch
        }
        if next != status { status = next }
    }

    /// The Watch has answered 808: a start ack arrived, or a measured
    /// session landed. Called by `SessionCoordinator` (and the DEBUG preview
    /// above), never by install state, so the switch cannot turn itself on
    /// before a real connection.
    func noteConnected() {
        let d = UserDefaults.standard
        guard let choice = WatchDefault.choiceOnConnect(everConnected: d.bool(forKey: Self.everConnectedKey)) else { return }
        d.set(true, forKey: Self.everConnectedKey)
        if choice { d.set(SitKind.watch.rawValue, forKey: Self.choiceKey) }
    }
}

/// The steps to connect an Apple Watch, from the Ready screen's Set up and
/// from Settings. The status line updates live, so the person sees the
/// check turn green the moment 808 can see the Watch.
struct WatchConnectSheet: View {
    @ObservedObject private var link = WatchLink.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let steps: [(String, String)] = [
        ("Pair your Watch with this iPhone", "In the Watch app on your iPhone, if it isn't already."),
        ("Put 808 on your Watch", "In the Watch app on your iPhone, open My Watch, find 808 and tap Install. Or turn on Automatic App Install."),
        ("Open 808 on your Watch once", "Allow Health access so it can read your heart rate."),
        ("Come back here", "The check turns green when 808 can see your Watch."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect your Apple Watch")
                    .font(DisplayFont.display(22, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Text("808 reads your heart rate, stillness and breathing while you meditate, then shows them after. Your phone works fine without it.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(AppColor.skyDeep))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.0)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(step.1)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            WatchStatusLine(status: link.status)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(22)
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { link.refresh() }
        // Back from the Watch app: the check should already be green.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.refresh() }
        }
    }
}

/// "Connected" with a green check, or what is missing.
struct WatchStatusLine: View {
    let status: WatchLink.Status

    var body: some View {
        HStack(spacing: 7) {
            switch status {
            case .connected:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(OnboardingGreen.fill)
                Text("Connected").foregroundStyle(OnboardingGreen.shade)
            case .notInstalled:
                Image(systemName: "circle.dashed").foregroundStyle(AppColor.textSecondary)
                Text("Watch paired, 808 not on it yet").foregroundStyle(AppColor.textSecondary)
            case .noWatch:
                Image(systemName: "circle.dashed").foregroundStyle(AppColor.textSecondary)
                Text("No Watch paired with this iPhone").foregroundStyle(AppColor.textSecondary)
            }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }
}
