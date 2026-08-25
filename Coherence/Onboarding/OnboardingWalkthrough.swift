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

/// The real home screen, dimmed under a sequence of notes. Hit testing is off:
/// this is show, not touch, and Begin here would start a session the flow is
/// about to start properly anyway.
struct TourHomeScreen: View {
    let onContinue: () -> Void

    @State private var stop = 0

    private struct Note {
        let title: String
        let body: String
    }

    private let notes: [Note] = [
        .init(title: "This is home.",
              body: "Your streak lives at the top, and every practiced day lands a dot on the calendar. It fills in as you show up."),
        .init(title: "One button starts everything.",
              body: "Begin session tells your Watch to start measuring. Play any audio you like from any app, or nothing at all. 808 measures either way."),
        .init(title: "The guide is always here.",
              body: "How to meditate, plainly explained, easiest first. Every session you finish comes back as a score and the story of what your body did."),
    ]

    var body: some View {
        ZStack {
            ContentView()
                .allowsHitTesting(false)

            // The dim: enough that the notes own the screen, light enough
            // that the app underneath reads as real, because it is.
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack {
                Spacer()
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
            }
        }
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

    private var ready: Bool { paired && installed }

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Put your Watch on.",
                         subtitle: "The next two minutes are measured from your wrist, so make sure it's snug and awake.",
                         ctaTitle: ready ? "It's on. Let's breathe" : "Check again",
                         ctaEnabled: !checking,
                         skipTitle: "I'll do this later",
                         onSkip: onSkip,
                         onContinue: { ready ? onReady() : refresh() }) {
            VStack(spacing: 12) {
                row(ok: paired, label: "Apple Watch paired")
                row(ok: installed, label: "808 installed on the Watch",
                    hint: installed ? nil :
                        "Open the Watch app on this iPhone, scroll to 808, and tap Install.")
            }
        }
        .onAppear(perform: refresh)
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
        checking = true
        // Activation settles async on first launch; poll briefly rather than
        // reporting a state WCSession hasn't finished forming.
        Task { @MainActor in
            let wc = WCSession.default
            if wc.activationState != .activated { wc.activate() }
            for _ in 0..<10 {
                if wc.activationState == .activated { break }
                try? await Task.sleep(for: .seconds(0.3))
            }
            paired = WCSession.isSupported() && wc.isPaired
            installed = wc.isWatchAppInstalled
            checking = false
        }
    }
}

// MARK: - 3 · The two-minute practice

/// A real session: the coordinator launches the Watch workout with a 120 s
/// plan and wrist pacing, the phone shows the paced orb, and the Watch taps
/// the rhythm. When the payload lands and persists, the flow moves itself to
/// the results.
struct GuidedBreathScreen: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    /// Fires with the persisted sessionID once the Watch ships the result.
    let onScored: (UUID) -> Void
    /// The session could not run (Watch declined, took it off, etc.).
    let onSkip: () -> Void

    private static let practiceSeconds = 120

    private enum Stage { case intro, starting, breathing, finishing }
    @State private var stage: Stage = .intro
    @State private var startedAt: Date?

    // The orb. 6 s in, 6 s out — the same resonance pace the Watch taps.
    @State private var inhale = false
    @State private var label = "Breathe in"
    @State private var remaining = practiceSeconds

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch stage {
            case .intro:
                VStack(spacing: 14) {
                    Text("Two minutes.\nJust breathe.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Six seconds in, six seconds out. Your Watch taps your wrist with the rhythm, so you can close your eyes. Slow breathing like this settles the nervous system, and 808 will measure it happening.")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
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
            }

            Spacer()

            if stage == .intro {
                OnboardingCTA(title: "Start breathing") { start() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body, ambient: false)
        // The payload landed and was persisted: this is the real sessionID.
        .onChange(of: coordinator.lastSessionID) { _, id in
            if let id { onScored(id) }
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
        coordinator.begin(mode: "silence", trackID: nil,
                          plannedDurationSec: Self.practiceSeconds,
                          hapticsEnabled: true, paceBreathing: true)
        // The coordinator flips `active` when the Watch acks the start; ride it.
        Task { @MainActor in
            for _ in 0..<120 {          // up to ~60 s for a cold Watch launch
                if coordinator.active != nil { breathe(); return }
                if coordinator.startFailure != nil { return }
                try? await Task.sleep(for: .seconds(0.5))
            }
            if stage == .starting { onSkip() }   // never started; don't strand them
        }
    }

    private func breathe() {
        stage = .breathing
        startedAt = Date()
        Task { @MainActor in
            var goingIn = true
            inhale = true
            while stage == .breathing {
                withAnimation { label = goingIn ? "Breathe in" : "and out" }
                goingIn.toggle()
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                inhale.toggle()
                if let s = startedAt {
                    remaining = max(0, Self.practiceSeconds - Int(Date().timeIntervalSince(s)))
                }
                // The Watch ends the session itself at 2:00; once the live
                // session drops, we are waiting on the payload.
                if coordinator.active == nil && remaining <= 2 {
                    stage = .finishing
                }
            }
        }
    }
}

// MARK: - 4 · The scored result

/// The real results screen for the session they just breathed, with one
/// walkthrough note on top and Continue pinned underneath. Everything in
/// between (score, verdict, graphs, rating, share) is the app itself.
struct WalkthroughResultsScreen: View {
    let sessionID: UUID
    let onContinue: () -> Void

    @State private var noteShown = true

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                SessionResultsView(sessionID: sessionID)
            }
            .safeAreaInset(edge: .bottom) {
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

            if noteShown {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This is what every session gives you.")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Your score, what your heart and body did minute by minute, a place to say how it felt, and a card you can share. Scroll through it. It's yours.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") {
                        withAnimation(.easeOut(duration: 0.25)) { noteShown = false }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.accentGoldText)
                }
                .padding(18)
                .background(AppColor.backgroundSecondary.opacity(0.97),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColor.accentGold.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
