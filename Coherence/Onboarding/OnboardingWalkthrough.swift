import SwiftUI
import SwiftData
import WatchConnectivity

/// The walkthrough: the last stretch of onboarding, and since 2026-09-19 the
/// whole of it is the tour. Otto walks the reader through the real app, one
/// line a stop, and Let's go on the last stop finishes onboarding on Home. The
/// Watch connect screen, the two-minute practice sit and its demo results
/// further down this file are no longer routed to (two thirds of the people
/// who reached them left); the offer comes after the first real session, from
/// ContentView.
///
/// Nothing in here is a mock. The tour shows the actual `ContentView`, and the
/// screens it moves through are the real tabs with the reader's own (empty)
/// history in them. The no-invented-numbers rule matters most at the moment
/// of first trust.

// MARK: - 1 · The tour

/// What the tour can light, published as anchor preferences by `ContentView`
/// (Home's streak, guide and glow card) and `MainTabBar` (the plus and the
/// tabs). Harmless in the real app: nothing outside the tour reads the key.
enum TourTarget: Hashable {
    case streak, guide, glow
    case begin, block, friends, profile

    /// Round things get a round window: the plus, and the streak and guide
    /// circles stacked in the corner.
    var isRound: Bool { self == .begin || self == .streak || self == .guide }
}

struct TourTargetKey: PreferenceKey {
    static var defaultValue: [TourTarget: SwiftUI.Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: SwiftUI.Anchor<CGRect>],
                       nextValue: () -> [TourTarget: SwiftUI.Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The tab the tour is showing under its dim. `ContentView` shows it in place
/// of its own selection and holds back its modals and Otto's Home line while
/// it is set; `FriendsTab` does not count it as an open. Nil everywhere else.
private struct TourTabKey: EnvironmentKey {
    static let defaultValue: MainTab? = nil
}

extension EnvironmentValues {
    var tourTab: MainTab? {
        get { self[TourTabKey.self] }
        set { self[TourTabKey.self] = newValue }
    }
}

/// One stop of the tour: the tab it shows, what is lit, what Otto says, and
/// where he stands while he says it.
///
/// **Quick is the brief** (Melvin, 2026-09-22: "quickly show the user the
/// different screens, quickly being the name of the game, dont want to waste
/// time"). One sentence a stop, 74 characters at most so it fits his bubble,
/// and no more than six stops on any build. `TourStopTests` pins all of it,
/// along with the copy rules: no em dashes, no score, no Watch, no thanks.
struct TourStop: Equatable {
    enum Stand {
        /// Under the status bar, for a lit thing low on the screen.
        case top
        /// Just above the tab bar, and above the lit thing when that is in
        /// the bar. He stands beside the tab he is talking about, and the top
        /// of each screen, which is what makes it recognisable, stays clear.
        case bottom
    }

    let tab: MainTab
    /// Lit together, as one window.
    let targets: [TourTarget]
    let line: String
    let stand: Stand

    /// The stops, in order, for a build's switches. **It ends on Home**, with
    /// the plus lit, so finishing lifts the dim off the very screen the reader
    /// lands on instead of cutting from another tab to Home.
    static func all(block: Bool, friends: Bool) -> [TourStop] {
        var stops = [
            TourStop(tab: .home, targets: [.glow],
                     line: "This is home, where I glow brighter every day you meditate.",
                     stand: .top),
            TourStop(tab: .home, targets: [.streak, .guide],
                     line: "Your streak lives up here, and under it is my guide to meditating.",
                     stand: .bottom),
        ]
        if block {
            stops.append(TourStop(tab: .block, targets: [.block],
                                  line: "This is Block, where I hold the apps you pick until you've meditated.",
                                  stand: .bottom))
        }
        if friends {
            stops.append(TourStop(tab: .friends, targets: [.friends],
                                  line: "Bring your friends here, and cheer on each other's sessions.",
                                  stand: .bottom))
        }
        stops.append(TourStop(tab: .profile, targets: [.profile],
                              line: "I keep every session you do right here, with your minutes and awards.",
                              stand: .bottom))
        stops.append(TourStop(tab: .home, targets: [.begin],
                              line: "When you're ready, tap the plus: any length, any sound, or your own audio.",
                              stand: .bottom))
        return stops
    }
}

/// The whole screen dimmed except a rounded window over what is lit. Even-odd
/// fill: the outer rect and the window cancel, so the lit thing shows through
/// at full brightness. Animatable, so the window slides from one stop's
/// target to the next instead of jumping.
private struct SpotlightDim: Shape {
    var window: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(window.origin.x, window.origin.y),
                           AnimatablePair(AnimatablePair(window.width, window.height), radius))
        }
        set {
            window = CGRect(x: newValue.first.first, y: newValue.first.second,
                            width: newValue.second.first.first, height: newValue.second.first.second)
            radius = newValue.second.second
        }
    }

    func path(in bounds: CGRect) -> Path {
        var p = Path()
        p.addRect(bounds)
        if window.width > 0, window.height > 0 {
            p.addRoundedRect(in: window, cornerSize: CGSize(width: radius, height: radius),
                             style: .continuous)
        }
        return p
    }
}

/// The real app, dimmed, with Otto walking through it (Melvin, 2026-09-22:
/// "it should have otto somewhere talking, as though hes explaining the app,
/// and again should quickly show the user the different screens").
///
/// Each stop switches `ContentView` to the tab it is about (`tourTab`), opens
/// a window in the dim over the thing being talked about, and puts Otto's
/// line in his bubble. A tap anywhere moves on, and so does the Next pill,
/// which is there so nobody has to guess that a tap will do. Hit testing on
/// the app underneath is off: this is show, not touch.
///
/// **Otto never stands on what he is pointing at.** A stop names where he
/// stands (`TourStop.Stand`), and the floor he stands on is worked out from
/// the lit window itself, so a lit thing low on the screen always keeps him
/// above it, and a stop that asks for the top falls back to the bottom if its
/// target is not low. He never covers the tab bar either.
struct TourHomeScreen: View {
    let onContinue: () -> Void

    @State private var stop = 0
    /// When the stop last changed. A tap inside the change is ignored, so a
    /// doubled tap cannot skip a screen the reader never saw.
    @State private var changedAt = Date.distantPast
    /// Set by the last tap: the dim lifts off Home, then onboarding finishes.
    @State private var leaving = false
    /// The tab under the dim. Its own state, changed with animations off, so
    /// moving to the next stop switches tabs the way a tap on the bar does:
    /// at once. Inside the stop's animation the new tab cross-faded in with
    /// its layout animating, which read as a swipe and a flash (Melvin,
    /// 2026-09-23: "should just look like you tapped on the icons").
    @State private var shownTab: MainTab = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stops = TourStop.all(block: FeatureFlags.block, friends: FeatureFlags.friends)
    private var current: TourStop { stops[stop] }

    /// Every change of stop takes this long: the window slides, the tab
    /// cross-fades, and Otto's next line starts.
    private static let pace = 0.28

    var body: some View {
        ContentView()
            .environment(\.tourTab, shownTab)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlayPreferenceValue(TourTargetKey.self) { anchors in
                GeometryReader { proxy in
                    tourOverlay(anchors, proxy)
                }
            }
            .sensoryFeedback(.selection, trigger: stop)
    }

    // MARK: The overlay

    /// The lit window in reader space, and its corner radius.
    private struct Lit {
        let rect: CGRect
        let radius: CGFloat
    }

    private func litArea(_ anchors: [TourTarget: SwiftUI.Anchor<CGRect>], _ proxy: GeometryProxy) -> Lit? {
        let rects = current.targets.compactMap { anchors[$0].map { proxy[$0] } }
        guard let first = rects.first else { return nil }
        let round = current.targets.allSatisfy(\.isRound)
        let pad: CGFloat = current.targets.contains(.glow) ? 6 : 8
        let rect = rects.dropFirst().reduce(first) { $0.union($1) }
            .insetBy(dx: -pad, dy: -pad)
        let radius = round ? min(rect.width, rect.height) / 2
                           : current.targets.contains(.glow) ? AppMetrics.cardRadius + pad : 18
        return Lit(rect: rect, radius: radius)
    }

    @ViewBuilder
    private func tourOverlay(_ anchors: [TourTarget: SwiftUI.Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        let lit = litArea(anchors, proxy)
        // Nil until the anchors resolve, a frame after the tour appears.
        let low = lit.map { $0.rect.midY > proxy.size.height / 2 }
        // The top only for a lit thing that is low; otherwise the bottom,
        // which can never cover something at the top. Before the anchors
        // arrive the stop's own choice stands, so he does not hop on the
        // first frame.
        let stand: TourStop.Stand = current.stand == .top && low != false ? .top : .bottom
        // What he stands on: the top of the plus, which is the highest thing
        // in the tab bar, or the lit window when that is lower down.
        let plusTop = anchors[.begin].map { proxy[$0].minY } ?? proxy.size.height
        let ground = min(plusTop, low == true ? (lit?.rect.minY ?? plusTop) : plusTop) - 12
        // The dim ignores the safe area (it has to cover the status bar),
        // which puts its origin ABOVE the reader's by the top inset. The
        // window is measured in reader space, so it shifts down by that inset
        // or the cutout lands above the thing it frames (Aziz, 2026-08-29).
        let inset = proxy.safeAreaInsets
        let window = lit?.rect.offsetBy(dx: inset.leading, dy: inset.top) ?? .zero
        // At the top of Home the streak and guide circles hold the corner, and
        // he stops short of them: a bubble half over a circle leaves a sliver
        // of its label peeking out from under the bubble.
        let corner = stand == .top && !current.targets.contains(.streak)
            ? anchors[.streak].map { max(0, proxy.size.width - proxy[$0].minX - 8) } : nil

        ZStack {
            SpotlightDim(window: window, radius: lit?.radius ?? 0)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .ignoresSafeArea()

            if let lit {
                RoundedRectangle(cornerRadius: lit.radius, style: .continuous)
                    .stroke(AppColor.accentGold.opacity(0.9), lineWidth: 2)
                    .frame(width: lit.rect.width, height: lit.rect.height)
                    .position(x: lit.rect.midX, y: lit.rect.midY)
                    .shadow(color: AppColor.accentGold.opacity(0.45), radius: 10)
            }

            VStack(spacing: 0) {
                if stand == .top {
                    narrator
                        .padding(.top, 8)
                        .padding(.trailing, corner ?? 0)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    narrator.padding(.bottom, max(0, proxy.size.height - ground))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(leaving ? 0 : 1)
        // A tap anywhere moves on, the lit window included.
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
    }

    private var narrator: some View {
        TourNarrator(line: current.line, step: stop, steps: stops.count, onNext: advance)
            .transition(.opacity)
    }

    private func advance() {
        guard !leaving, Date().timeIntervalSince(changedAt) > Self.pace else { return }
        changedAt = Date()
        if stop < stops.count - 1 {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { shownTab = stops[stop + 1].tab }
            // The window and the line still ease to the next stop, a turn of
            // the run loop later, so their animation cannot carry the tab
            // switch with it.
            DispatchQueue.main.async {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.pace)) { stop += 1 }
                // A bubble changing is silent to VoiceOver, so the new line is read.
                AccessibilityNotification.Announcement("Otto says: \(current.line)").post()
            }
        } else if reduceMotion {
            leaving = true
            onContinue()
        } else {
            // The dim lifts first, so the last thing seen is Home itself,
            // which is exactly where finishing lands.
            withAnimation(.easeOut(duration: 0.25)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onContinue() }
        }
    }
}

/// Otto, small, with his line typed into his bubble, and under it where the
/// tour has got to and the one thing to press.
///
/// **He is the talking art, and he jiggles as each line starts**, the same
/// squash and wobble he gives on Home when he is tapped, so a new line reads
/// as him saying it rather than as a caption changing beside a picture.
private struct TourNarrator: View {
    let line: String
    let step: Int
    let steps: Int
    let onNext: () -> Void

    @State private var speaking = false
    @State private var pokes = 0
    /// The bubble hugs its words, so the row under it takes its width from
    /// the bubble rather than from the screen.
    @State private var bubbleWidth: CGFloat = 0

    private var isLast: Bool { step == steps - 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(OttoPose.talking.asset)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 92)
                .ottoJiggle(pokes)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                // Cream, filled: an outline alone reads as glass over the
                // dimmed screen, and the words would sit on whatever is behind.
                OttoSpeech(text: line, tail: .leading, size: 17,
                           ink: AppColor.textPrimary,
                           stroke: AppColor.backgroundPrimary,
                           fill: AppColor.backgroundPrimary,
                           speaking: $speaking)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bubbleWidth = $0 }

                // Under the bubble, edge to edge with it: the dots start where
                // its body starts, past the point, and Next ends where it ends.
                HStack(spacing: 12) {
                    progress
                    Spacer(minLength: 0)
                    next
                }
                .padding(.leading, 11)
                .frame(width: max(bubbleWidth, 200))
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        // A soft shade under him. Whatever the dim leaves legible behind
        // him (a card's label, a button's words) otherwise peeks out round
        // his edges and reads as part of what he is saying.
        .background {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .padding(-18)
                .blur(radius: 22)
                .allowsHitTesting(false)
        }
        .task(id: line) { pokes += 1 }
    }

    /// Where the tour has got to: a dot a stop, the current one drawn long.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == step ? 0.95 : 0.35))
                    .frame(width: i == step ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(steps)")
    }

    /// A cream pill, not gold: it is a control, and the gold on this screen
    /// is the ring around what is lit.
    private var next: some View {
        Button(action: onNext) {
            HStack(spacing: 5) {
                Text(isLast ? "Let's go" : "Next")
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColor.backgroundPrimary, in: Capsule())
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(isLast ? "Let's go" : "Next")
    }
}

// MARK: - Getting 808 onto the Watch (right after the gate)

/// Instructions, immediately after "yes, I have a Watch" (Aziz, 2026-08-28:
/// "that is not clear"). The walkthrough's live check comes later; this screen
/// exists because a first-time user has no reason to know the Watch app
/// installs itself alongside the phone app, and the walkthrough's connect
/// screen is a worse place to learn it for the first time while a practice is
/// waiting on you.
///
/// Instructional only, no live WCSession check, deliberately: at this point in
/// onboarding the user may be mid-commute with the Watch at home, and a check
/// that can fail here would turn information into a gate. The real gate stays
/// in `WatchConnectScreen`, where the practice actually needs the Watch.
struct WatchSetupScreen: View {
    let onContinue: () -> Void

    @State private var probe = WatchProbe()

    var body: some View {
        OnboardingScreen(section: .body,
                         title: "808 goes on your Watch by itself.",
                         subtitle: "Installing 808 on this iPhone puts it on your Watch too. This screen watches for it, so you can see it arrive.",
                         // Naming the state in the button means the tap is
                         // never a guess. It still advances either way: a Watch
                         // can be paired later, and stranding someone on a
                         // setup screen is worse than letting them go on.
                         ctaTitle: probe.ready ? "It's there. Continue" : "Continue anyway",
                         onContinue: onContinue) {
            VStack(spacing: 12) {
                // LIVE, not instructions alone. This screen's whole job is to
                // get 808 onto the wrist, and until 2026-09-12 it had no idea
                // whether that happened: it said "it should already be waiting
                // there" and let everyone through. The live data showed people
                // finishing onboarding and hitting `watchAppNotInstalled` or
                // `watchNotPaired` within a minute of tapping Begin, which is
                // this screen's failure arriving late and out of context.
                WatchStatusRows(probe: probe)
                step(1, "Put your Watch on",
                     "Wear it snug on your wrist. The sensors need skin contact to read your heart.")
                step(2, "Check your Watch for the 808 app",
                     "Press the side crown to see your apps. 808 installs itself alongside the iPhone app, so it should already be waiting there.")
                step(3, "Not there? Install it from this iPhone",
                     "Open the Watch app on this iPhone, scroll down to Available Apps, and tap Install next to 808.")
            }
        }
        .task { await probe.monitor() }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(n)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentGoldText)
                .frame(width: 30, height: 30)
                .background(AppColor.accentGold.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

// MARK: - 2 · Connect the Watch

/// The honest gate before the practice. Reads what WatchConnectivity already
/// knows and names the actual problem when there is one, the same reporting
/// the session preflight does.
/// What WatchConnectivity already knows about the wrist, watched live.
///
/// Shared by every screen that asks about the Watch, because the app kept
/// telling people the same thing in three different states of knowledge: the
/// setup screen guessed, the connect screen checked, and the session preflight
/// checked again and reported the failure minutes later. One reader, one truth.
@Observable
final class WatchProbe {
    var paired = false
    var installed = false
    /// No honest read has landed yet. Buttons that depend on the answer stay
    /// disabled through this, because acting on unformed state misleads.
    var checking = true
    /// This device can never pair a Watch (an iPad running the iPhone app in
    /// compatibility mode, which is a real way reviewers test).
    var unsupported = false

    var ready: Bool { paired && installed }

    /// Reads the session state every half second until both are true or the
    /// caller's `.task` cancels. Re-entrant calls overlap harmlessly: every
    /// writer writes the same truth.
    @MainActor
    func monitor() async {
        // Touching WCSession.default on an unsupported device is
        // documented-invalid, so answer from `unsupported` instead.
        guard WCSession.isSupported() else {
            unsupported = true
            checking = false
            return
        }
        let wc = WCSession.default
        if wc.activationState != .activated { wc.activate() }
        for tick in 0..<120 {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                paired = wc.isPaired
                installed = wc.isWatchAppInstalled
            }
            if tick >= 1 { checking = false }
            if ready { checking = false; return }
            try? await Task.sleep(for: .seconds(0.5))
        }
        checking = false
    }
}

/// The two facts, with the fix for whichever one is missing.
struct WatchStatusRows: View {
    let probe: WatchProbe

    var body: some View {
        VStack(spacing: 12) {
            row(ok: probe.paired, label: "Apple Watch paired",
                hint: probe.paired || probe.checking ? nil :
                    "No Watch is paired with this iPhone yet. Pair one in the Watch app, and this ticks by itself.")
            // Only one problem at a time. Telling someone with no paired Watch
            // to go install an app on it names the second blocker while the
            // first is still standing.
            row(ok: probe.installed, label: "808 installed on the Watch",
                hint: probe.installed || probe.checking || !probe.paired ? nil :
                    "Open the Watch app on this iPhone, scroll to 808, and tap Install.")
        }
    }

    private func row(ok: Bool, label: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 19))
                    .foregroundStyle(ok ? AppColor.accentGold : AppColor.textSecondary.opacity(0.5))
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
            }
            if let hint {
                Text(hint)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.leading, 30)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct WatchConnectScreen: View {
    let onReady: () -> Void
    /// No Watch reachable after trying: the practice is skipped, never faked.
    let onSkip: () -> Void

    @State private var probe = WatchProbe()
    /// Failed "Check again" taps. The walkthrough is the product's first
    /// proof, so there is no standing skip (Aziz, 2026-08-28: "we really want
    /// the user to experience that"). But a user whose Watch is at home on the
    /// charger CANNOT pass this screen, and an onboarding that hard-blocks on
    /// external state is a stranding, so an escape appears after three failed
    /// checks. Default path: do the practice. Escape: earned by trying.
    @State private var failedChecks = 0

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Put your Watch on.",
                         subtitle: "Your first session is measured from your wrist, so make sure it's snug and awake.",
                         ctaTitle: probe.ready ? "It's on. Let's begin" : "Check again",
                         ctaEnabled: !probe.checking,
                         skipTitle: "My Watch isn't with me. Continue",
                         onSkip: (failedChecks >= 3 || probe.unsupported) ? onSkip : nil,
                         onContinue: {
                             if probe.ready { onReady() } else { failedChecks += 1; refresh() }
                         }) {
            WatchStatusRows(probe: probe)
        }
        // Live, not one-shot. The first build read WCSession once with a 3 s
        // window, and activation routinely settles slower than that on a
        // fresh launch (the same race the first-Begin path documents), so the
        // rows sat unchecked against a paired Watch and read as broken
        // (Aziz, 2026-08-28: "make sure the checkboxes are actually
        // functional"). This watches for as long as the screen is up and the
        // rows tick the moment the system reports them.
        .task { await probe.monitor() }
    }

    private func refresh() {
        Task { @MainActor in await probe.monitor() }
    }
}

// MARK: - 3 · The two-minute practice

/// A real session: the coordinator launches the Watch workout with a
/// two-minute plan and wrist pacing, the phone shows the paced orb, and the Watch taps
/// the rhythm. When the payload lands and persists, a Done state offers the
/// results rather than jumping there: arriving somewhere you tapped to go
/// beats being teleported (Aziz, 2026-08-29).
struct GuidedBreathScreen: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    /// Fires with the persisted sessionID once the Watch ships the result.
    let onScored: (UUID) -> Void
    /// The session could not run (Watch declined, took it off, etc.).
    let onSkip: () -> Void

    private static let practiceSeconds = 120

    private enum Stage: Equatable { case intro, starting, breathing, finishing, done(UUID), unreadable }
    @State private var stage: Stage = .intro
    @State private var startedAt: Date?

    // The orb. 6 s in, 6 s out — the same resonance pace the Watch taps.
    @State private var inhale = false
    /// The intro's preview orb, breathing on its own clock.
    @State private var introInhale = false
    @State private var introLabelOpacity = 1.0
    @State private var label = "Breathe in"
    @State private var remaining = practiceSeconds

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch stage {
            case .intro:
                VStack(spacing: 22) {
                    // The orb they are about to follow, already breathing at
                    // the real pace. A rehearsal, not a decoration: by the
                    // time they tap Start they have seen a full breath cycle
                    // (Aziz, 2026-08-29: the old screen was "just a bunch of
                    // text").
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.onboardingSage.opacity(0.5),
                                                          Color.onboardingSage.opacity(0.04)],
                                                 center: .center, startRadius: 4, endRadius: 84))
                            .frame(width: 152, height: 152)
                        Circle()
                            .stroke(Color.onboardingSage.opacity(0.45), lineWidth: 1.5)
                            .frame(width: 152, height: 152)
                        Text(introInhale ? "in" : "out")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                            .opacity(introLabelOpacity)
                    }
                    .scaleEffect(introInhale ? 1.0 : 0.68)
                    .animation(.easeInOut(duration: 6), value: introInhale)

                    Text("Two minutes.\nJust breathe.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    // Posture before pace: it changes the reading. Seated and
                    // still is what the sensors want, and telling people after
                    // the fact would be telling them why their number was low.
                    VStack(spacing: 10) {
                        introRow(icon: "figure.mind.and.body",
                                 title: "Sit tall",
                                 detail: "Upright somewhere comfortable. Shoulders soft, hands resting in your lap.")
                        introRow(icon: "circle.dashed",
                                 title: "Six in, six out",
                                 detail: "Follow the circle on the next screen: it swells as you breathe in, settles as you breathe out.")
                        introRow(icon: "waveform.path.ecg",
                                 title: "808 measures it landing",
                                 detail: "Slow breathing helps your body settle. Your Watch reads what that looks like.")
                    }
                }
                .onAppear { introBreathing() }
            case .starting:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large).tint(AppColor.accentGold)
                    Text("Waking your Watch…")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                }
            case .breathing:
                VStack(spacing: 30) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.onboardingSage.opacity(0.55),
                                                          Color.onboardingSage.opacity(0.05)],
                                                 center: .center, startRadius: 6, endRadius: 130))
                            .frame(width: 240, height: 240)
                        Circle()
                            .stroke(Color.onboardingSage.opacity(0.45), lineWidth: 1.5)
                            .frame(width: 240, height: 240)
                        Text(timeString)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                    }
                    .scaleEffect(inhale ? 1.0 : 0.62)
                    .animation(.easeInOut(duration: 6), value: inhale)

                    Text(label)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.opacity)
                }
            case .finishing:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large).tint(AppColor.accentGold)
                    Text("Your Watch is scoring it…")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                }
            case .unreadable:
                VStack(spacing: 14) {
                    Image(systemName: "wind")
                        .font(.system(size: 38))
                        .foregroundStyle(AppColor.textSecondary)
                    Text("We didn't get a score back.")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("That happens: the Watch may have been mid-session, off the wrist, or out of reach. Real sessions retry all of this automatically, so keep going.")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            case .done:
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.accentGold)
                    Text("Done.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("That was two minutes of measured practice. Your Watch read your heart and your stillness the whole way, and listened for your breath.")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }

            Spacer()

            if stage == .intro {
                OnboardingCTA(title: "Start breathing") { start() }
            }
            if case .done(let id) = stage {
                OnboardingCTA(title: "Let's see your results") { onScored(id) }
            }
            if stage == .unreadable {
                OnboardingCTA(title: "Continue") { onSkip() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        // The payload landed and was persisted: this is the real sessionID.
        // Land on Done rather than jumping: the results are a reveal the user
        // taps into, not a redirect.
        .onChange(of: coordinator.lastSessionID) { _, id in
            if let id { withAnimation(.easeOut(duration: 0.3)) { stage = .done(id) } }
        }
        // The Watch answered, but the read was unusable (too short, no
        // signal). Waiting longer will not improve it; be honest instead.
        .onChange(of: coordinator.lastDiscardedID) { _, id in
            if id != nil, stage == .finishing || stage == .breathing {
                withAnimation { stage = .unreadable }
            }
        }
        // The Watch refused (no HR, permissions, out of reach). The honest
        // path forward is the same one the app takes: say so, move on.
        .fullScreenCover(item: Binding(get: { coordinator.startFailure },
                                       set: { coordinator.startFailure = $0 })) { failure in
            PermissionBlockedView(failure: failure) {
                coordinator.startFailure = nil
                onSkip()
            }
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func start() {
        stage = .starting
        // The Watch plays no haptics at all (Melvin, 2026-09-01): a buzzing
        // wrist reads as an interruption in a product about settling down, and
        // the orb on this screen already carries the rhythm.
        coordinator.begin(mode: "silence", trackID: nil,
                          plannedDurationSec: Self.practiceSeconds,
                          hapticsEnabled: true)
        // Wait for the Watch's ACK, not the phone-side launch callback: the
        // callback fires seconds early, and on a cold Watch tens of seconds
        // early, which started the phone's orb and countdown long before the
        // wrist was measuring anything (Aziz, 2026-08-31). The coordinator's
        // start watchdog turns a missing ack into `startFailure`, which the
        // cover below already handles.
        Task { @MainActor in
            for _ in 0..<160 {          // up to ~80 s for a cold Watch launch
                if coordinator.startAcked { breathe(); return }
                if coordinator.startFailure != nil { return }
                try? await Task.sleep(for: .seconds(0.5))
            }
            if stage == .starting { onSkip() }   // never started; don't strand them
        }
    }

    private func breathe() {
        stage = .breathing
        startedAt = Date()
        // Two clocks on purpose. The breath loop wakes every 6 s to turn the
        // orb, and the first build also updated the countdown there, so the
        // number stepped 45 → 39 → 33 and read as broken (Aziz, 2026-08-29).
        // The countdown is its own 1 s ticker off the wall clock.
        Task { @MainActor in
            var overrunSec = 0
            while stage == .breathing {
                // The coordinator's clock, not a local one: it re-anchors to
                // the Watch's reported workout start, so this countdown reads
                // the same seconds the wrist is counting.
                if let anchor = coordinator.active?.startedAt ?? startedAt {
                    remaining = max(0, Self.practiceSeconds - Int(Date().timeIntervalSince(anchor)))
                }
                // The Watch ends the session itself at 0:00; once the live
                // session drops, we are waiting on the payload.
                if coordinator.active == nil && remaining <= 2 {
                    stage = .finishing
                    finishingWatchdog()
                }
                // The countdown reaching zero while the coordinator still
                // thinks a session is live means the Watch ran something else
                // (a stale command) or the link died. Waiting cannot fix
                // either; the breathing screen must never be a place someone
                // can live (it was, 2026-08-31).
                if remaining <= 0 {
                    overrunSec += 1
                    if overrunSec > 40 { withAnimation { stage = .unreadable }; return }
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
        }
        Task { @MainActor in
            var goingIn = true
            inhale = true
            while stage == .breathing {
                withAnimation { label = goingIn ? "Breathe in" : "and out" }
                goingIn.toggle()
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                inhale.toggle()
            }
        }
    }

    private func introRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColor.accentGoldText)
                .frame(width: 30, height: 30)
                .background(AppColor.accentGold.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(AppColor.backgroundSecondary.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    /// The preview orb breathes until the intro is left; `stage` changes end
    /// it. The word swap is SEQUENCED, not cross-faded: a cross-fade shows
    /// both words superimposed at half opacity mid-transition (Aziz,
    /// 2026-08-29), so the label fades fully out, swaps, and fades back in.
    private func introBreathing() {
        Task { @MainActor in
            introInhale = true
            while stage == .intro {
                try? await Task.sleep(for: .seconds(5.6))
                guard !Task.isCancelled, stage == .intro else { return }
                withAnimation(.easeOut(duration: 0.2)) { introLabelOpacity = 0 }
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, stage == .intro else { return }
                introInhale.toggle()
                withAnimation(.easeIn(duration: 0.3)) { introLabelOpacity = 1 }
            }
        }
    }

    /// "Your Watch is scoring it…" must not be a place someone can live.
    /// The payload normally lands seconds after the session ends; if half a
    /// minute passes with nothing (a stale Watch session, a discarded read,
    /// a dropped link), say so honestly and let the flow continue. The score
    /// was never the toll for finishing onboarding.
    private func finishingWatchdog() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, stage == .finishing else { return }
            withAnimation { stage = .unreadable }
        }
    }
}

// MARK: - 4 · The scored result

/// The real results screen for the session they just breathed, read to the
/// user one element at a time (Aziz, 2026-08-29): the score first, then each
/// curve, everything else dimmed, with a plain-words explanation of what the
/// lit thing measures and why it matters to meditation. The screen underneath
/// is the app itself, driven through `resultsTourStage`, so what the tour
/// explains is exactly what every later session shows.
///
/// Copy rules bind here harder than anywhere: these are the first claims 808
/// makes about the user's own body. Heart rate is an averaged trend, never
/// beat-to-beat. Stillness is motion, not attention: we say what settling
/// LOOKS like, we never assert what their mind did. Breathing may legitimately
/// be unread in 45 seconds, so its copy works for both outcomes.
struct WalkthroughResultsScreen: View {
    let sessionID: UUID
    let onContinue: () -> Void

    /// nil = the tour is over; the screen is theirs to scroll.
    @State private var stage: ResultsTourStage? = .score

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                SessionResultsView(sessionID: sessionID)
            }
            .environment(\.resultsTourStage, stage)
            .allowsHitTesting(stage == nil)
            .safeAreaInset(edge: .bottom) {
                if stage == nil {
                    OnboardingCTA(title: "Continue", action: onContinue)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .background(
                            LinearGradient(colors: [AppColor.backgroundPrimary.opacity(0),
                                                    AppColor.backgroundPrimary],
                                           startPoint: .top, endPoint: .center)
                            .ignoresSafeArea()
                        )
                }
            }

            if let stage {
                explainerCard(stage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: stage)
    }

    private func explainerCard(_ stage: ResultsTourStage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(for: stage))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(body(for: stage))
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(ResultsTourStage.allCases, id: \.rawValue) { st in
                    Capsule()
                        .fill(st == stage ? AppColor.accentGold
                                          : AppColor.textSecondary.opacity(0.3))
                        .frame(width: st == stage ? 18 : 6, height: 6)
                }
                Spacer()
            }
            .padding(.top, 2)

            OnboardingCTA(title: stage == ResultsTourStage.allCases.last ? "Got it" : "Next") {
                advance(from: stage)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(AppColor.backgroundSecondary.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppColor.accentGold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func advance(from current: ResultsTourStage) {
        stage = ResultsTourStage(rawValue: current.rawValue + 1)   // nil after the last
    }

    private func title(for stage: ResultsTourStage) -> String {
        switch stage {
        case .score:     return "Your score."
        case .heart:     return "Your heart."
        case .stillness: return "Your stillness."
        case .breathing: return "Your breath."
        }
    }

    private func body(for stage: ResultsTourStage) -> String {
        switch stage {
        // Aziz's wording (2026-08-31), trimmed from a longer draft that read as
        // generated. Full sentences, half the length, same four facts.
        case .score:
            return "This number shows how deep your body settled and how long it stayed there and is measured off your wrist. A two-minute demo caps the score low, and real sits score higher."
        case .heart:
            return "When you settle, your heart slows. This curve shows where it started, where it landed, and the minute it turned."
        case .stillness:
            return "A settling mind shows up as a settling body. This shows how still you were from minute to minute."
        case .breathing:
            return "Your breath is read from tiny wrist movements. Slow it toward six a minute and your heart follows. When 808 can't read a clear rhythm, it says so instead of guessing."
        }
    }
}
