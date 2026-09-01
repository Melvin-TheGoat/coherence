import SwiftUI
import SwiftData
import WatchConnectivity

/// The walkthrough: the last stretch of onboarding, placed just before the
/// paywall (Melvin's structure, 2026-08-25). Show the real home screen with
/// notes, connect the Watch, run a real two-minute paced breathing session
/// with the wrist tapping the rhythm, then land on the real results screen.
/// By the time the offer appears they have their own score on their own body.
///
/// Nothing in here is a mock. The tour shows the actual `ContentView`, the
/// practice runs through the actual `SessionCoordinator` and Watch pipeline,
/// and the score is whatever `SignalEngine` measured. The no-invented-numbers
/// rule matters most at the moment of first trust.

// MARK: - 1 · The home tour

/// The home screen's tour targets, published as anchor preferences by
/// `ContentView` and read here. Harmless in the real app: nothing outside the
/// tour ever reads the key.
enum TourTarget: Hashable { case streak, guide, begin }

struct TourTargetKey: PreferenceKey {
    static var defaultValue: [TourTarget: SwiftUI.Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: SwiftUI.Anchor<CGRect>],
                       nextValue: () -> [TourTarget: SwiftUI.Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The whole screen dimmed except a rounded window over the target. Even-odd
/// fill: the outer rect and the inner rounded rect cancel, so the target shows
/// through at full brightness.
private struct SpotlightDim: Shape {
    var window: CGRect?
    func path(in bounds: CGRect) -> Path {
        var p = Path()
        p.addRect(bounds)
        if let w = window {
            p.addRoundedRect(in: w, cornerSize: CGSize(width: 18, height: 18))
        }
        return p
    }
}

/// The real home screen, dimmed under a sequence of notes. Hit testing is off:
/// this is show, not touch, and Begin here would start a session the flow is
/// about to start properly anyway.
struct TourHomeScreen: View {
    let onContinue: () -> Void

    @State private var stop = 0

    private struct Note {
        let title: String
        let body: String
        /// The element this note is about. The spotlight opens over it and the
        /// card takes the opposite half of the screen.
        let target: TourTarget
    }

    private let notes: [Note] = [
        .init(title: "This is home.",
              body: "Your streak lives at the top, and every practiced day lands a dot on the calendar. It fills in as you show up.",
              target: .streak),
        .init(title: "One button starts everything.",
              body: "Begin session tells your Watch to start measuring. Play any audio you like from any app, or nothing at all. 808 measures either way.",
              target: .begin),
        .init(title: "The guide is always here.",
              body: "How to meditate, plainly explained, easiest first. Every session you finish comes back as a score and the story of what your body did.",
              target: .guide),
    ]

    var body: some View {
        ContentView()
            .allowsHitTesting(false)
            // The dim with a hole in it. The tour's first build dimmed the
            // whole screen flat and pinned every note to the bottom, which
            // both hid the Begin button under the note describing it and
            // highlighted nothing (Aziz, 2026-08-28: "make sure the box is
            // not covering the thing it's trying to highlight, and then
            // actually highlight that portion"). ContentView publishes the
            // real frames, so the spotlight is on the actual element at any
            // screen size, not a guessed rectangle.
            .overlayPreferenceValue(TourTargetKey.self) { anchors in
                GeometryReader { proxy in
                    let target = anchors[notes[stop].target]
                        .map { proxy[$0].insetBy(dx: -8, dy: -6) }
                    // The dim ignores the safe area (it must cover the status
                    // bar), which moves its origin ABOVE the reader's by the
                    // top inset. The window is measured in reader space, so it
                    // must shift down by that inset or the cutout lands above
                    // the element it frames — exactly the "the lit region is
                    // above the button" bug (Aziz, 2026-08-29).
                    let inset = proxy.safeAreaInsets
                    let window = target.map { $0.offsetBy(dx: inset.leading, dy: inset.top) }
                    ZStack {
                        SpotlightDim(window: window)
                            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                            .ignoresSafeArea()
                        if let target {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColor.accentGold.opacity(0.85), lineWidth: 1.5)
                                .frame(width: target.width, height: target.height)
                                .position(x: target.midX, y: target.midY)
                                .shadow(color: AppColor.accentGold.opacity(0.35), radius: 10)
                        }
                        // The card takes whichever half the target is not in,
                        // so it can never cover the thing it is pointing at.
                        VStack {
                            if let target, target.midY > proxy.size.height / 2 {
                                noteCard
                                Spacer()
                            } else {
                                Spacer()
                                noteCard
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: stop)
                }
            }
    }

    private var noteCard: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text(notes[stop].title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(notes[stop].body)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        ForEach(notes.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == stop ? AppColor.accentGold
                                                : AppColor.textSecondary.opacity(0.3))
                                .frame(width: i == stop ? 18 : 6, height: 6)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)

                    OnboardingCTA(title: stop < notes.count - 1 ? "Next" : "Continue") {
                        if stop < notes.count - 1 {
                            withAnimation(.easeOut(duration: 0.25)) { stop += 1 }
                        } else {
                            onContinue()
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .background(AppColor.backgroundPrimary.opacity(0.97),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppColor.accentGold.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .padding(.top, 8)
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

    var body: some View {
        OnboardingScreen(section: .body,
                         title: "808 goes on your Watch by itself.",
                         subtitle: "Installing 808 on this iPhone puts it on your Watch too. Take a second to make sure it's there, since that's where every session is measured.",
                         ctaTitle: "Got it",
                         onContinue: onContinue) {
            VStack(spacing: 12) {
                step(1, "Put your Watch on",
                     "Wear it snug on your wrist. The sensors need skin contact to read your heart.")
                step(2, "Check your Watch for the 808 app",
                     "Press the side crown to see your apps. 808 installs itself alongside the iPhone app, so it should already be waiting there.")
                step(3, "Not there? Install it from this iPhone",
                     "Open the Watch app on this iPhone, scroll down to Available Apps, and tap Install next to 808.")
            }
        }
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
struct WatchConnectScreen: View {
    let onReady: () -> Void
    /// No Watch reachable after trying: the practice is skipped, never faked.
    let onSkip: () -> Void

    @State private var paired = false
    @State private var installed = false
    @State private var checking = true
    /// Failed "Check again" taps. The walkthrough is the product's first
    /// proof, so there is no standing skip (Aziz, 2026-08-28: "we really want
    /// the user to experience that"). But a user whose Watch is at home on the
    /// charger CANNOT pass this screen, and an onboarding that hard-blocks on
    /// external state is a stranding, so an escape appears after three failed
    /// checks. Default path: do the practice. Escape: earned by trying.
    @State private var failedChecks = 0

    private var ready: Bool { paired && installed }

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Put your Watch on.",
                         subtitle: "The next two minutes are measured from your wrist, so make sure it's snug and awake.",
                         ctaTitle: ready ? "It's on. Let's breathe" : "Check again",
                         ctaEnabled: !checking,
                         skipTitle: "My Watch isn't with me. Continue",
                         onSkip: failedChecks >= 3 ? onSkip : nil,
                         onContinue: {
                             if ready { onReady() } else { failedChecks += 1; refresh() }
                         }) {
            VStack(spacing: 12) {
                row(ok: paired, label: "Apple Watch paired")
                row(ok: installed, label: "808 installed on the Watch",
                    hint: installed ? nil :
                        "Open the Watch app on this iPhone, scroll to 808, and tap Install.")
            }
        }
        // Live, not one-shot. The first build read WCSession once with a 3 s
        // window, and activation routinely settles slower than that on a
        // fresh launch (the same race the first-Begin path documents), so the
        // rows sat unchecked against a paired Watch and read as broken
        // (Aziz, 2026-08-28: "make sure the checkboxes are actually
        // functional"). This watches for as long as the screen is up and the
        // rows tick the moment the system reports them.
        .task { await monitor() }
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

    private func refresh() {
        Task { @MainActor in await monitor() }
    }

    /// Reads the session state every half second while the screen is up,
    /// stopping once both rows are green. `.task` cancels it on disappear.
    /// Re-entrant calls (the Check again button) just overlap harmlessly:
    /// every writer writes the same truth.
    @MainActor
    private func monitor() async {
        let wc = WCSession.default
        if wc.activationState != .activated { wc.activate() }
        for tick in 0..<120 {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                paired = WCSession.isSupported() && wc.isPaired
                installed = wc.isWatchAppInstalled
            }
            // The first honest read is in: let the button enable. Before it,
            // "Check again" against unformed state would only mislead.
            if tick >= 1 { checking = false }
            if paired && installed { checking = false; return }
            try? await Task.sleep(for: .seconds(0.5))
        }
        checking = false
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
                                 detail: "Slow breathing settles the nervous system. You'll see it in your score.")
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
                    Text("That was two minutes of measured practice. Your Watch read your heart, your stillness and your breath the whole way through.")
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
        .onboardingGround(.body, ambient: false)
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
        // No wrist pacing in the demo (Aziz, 2026-08-31): the taps were the
        // buggiest part of the first runs, and the orb on this screen already
        // carries the rhythm. `paceBreathing` stays in the contract for any
        // future use; the demo just stops asking for it. The end-of-session
        // haptic stays, it marks the finish.
        coordinator.begin(mode: "silence", trackID: nil,
                          plannedDurationSec: Self.practiceSeconds,
                          hapticsEnabled: true, paceBreathing: false)
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
        case .score:     return "This is your practice score."
        case .heart:     return "Your heart, across the sit."
        case .stillness: return "How still your body was."
        case .breathing: return "Your breath, read from your wrist."
        }
    }

    private func body(for stage: ResultsTourStage) -> String {
        switch stage {
        case .score:
            return "One number for how deep your body settled and how long it stayed there. It comes entirely from what your Watch measured, so it can't be flattered. If yours reads low, that's mostly the clock: this demo session was very short, and the score pays for time held. Your real sits will score higher."
        case .heart:
            return "When attention settles, heart rate drifts down. This curve is that drift: where your heart started, where it landed, and the minute it turned. Watching it fall across a session is the plainest evidence meditation gives."
        case .stillness:
            return "Read from the motion sensors, scored from zero to one. A settling mind shows up as a settling body, which is why every tradition starts by sitting still: stillness is the part of concentration the body can show."
        case .breathing:
            return "Read from the tiny wrist movements breathing makes. Slowing your breath toward six a minute is the fastest lever you have: the heart settles behind it. When 808 can't read a clear rhythm it says so rather than guessing, so a reading here always means something."
        }
    }
}
