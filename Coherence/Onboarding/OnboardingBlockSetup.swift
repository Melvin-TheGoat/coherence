import SwiftUI
import FamilyControls

// Block's setup, in onboarding (Melvin, 2026-09-23): "user should set up what
// they want to block in the onboarding; should set up schedule in onboarding;
// least friction possible for all of this: user should basically be able to
// thoughtlessly click continue continue continue without thinking."
//
// Two screens, right after the wall, on Block builds only (`FeatureFlags
// .block`; see `Step.blockApps` / `.blockSchedule` in `OnboardingView`). Both
// work on the SAME "Mindful day" blocker `BlockController` already seeds for
// everyone — neither screen invents a second one. Since 2026-10-13 at least
// one app is required (see `BlockAppsScreen`); taking the preselected
// schedule is still the thoughtless path through the second screen.

/// Screen: which apps Otto holds. In the onboarding's own look (Melvin,
/// 2026-09-27: it "looks different than the rest of the onboarding, like i
/// want the text to type in like it did before"): the title in the sky and
/// Otto, seated and writing, saying his line a letter at a time, the way the
/// personalize screen does.
///
/// **Picking at least one app is required** (Melvin and Aziz, 2026-10-13:
/// "we want it mandatory that you block at least one app from the
/// onboarding"). There is no "Not now". The one way through without a pick
/// is declining Apple's Screen Time prompt: App Review 5.1.1(iv) and
/// 5.1.2(i) forbid requiring a system permission, and a declined permission
/// must never be a dead end. Closing the picker with nothing ticked keeps
/// them here, with Otto saying so.
///
/// Apple lets 808 show, never read, which apps someone uses most, and the
/// picker can only be preselected with apps they picked before, so the
/// suggestion is Otto's line and the picker's footer (the top-apps view is
/// the next build: BACKLOG.md).
///
/// The same screen is Home's one-time ask for members with nothing held
/// (`context: .home`, `BlockAppsAskView`): titled for that, with "Not now",
/// because they are already in the app.
struct BlockAppsScreen: View {
    enum Context { case onboarding, home }
    var context: Context = .onboarding
    /// Apps were picked: onboarding goes on to the schedule; Home is done.
    let onContinue: () -> Void
    /// Nothing will be held: Screen Time was declined, or Home's "Not now".
    /// Onboarding skips the schedule screen, which would ask when to hold
    /// apps nobody picked.
    var onSkip: (() -> Void)? = nil

    @ObservedObject private var block = BlockController.shared
    @EnvironmentObject private var store: Store
    @State private var picking = false
    /// Nothing ticked when the picker opens (Melvin, 2026-09-27: "it
    /// shouldnt by default select all apps, it shouldnt select any"). It
    /// used to open on whatever Mindful day already held, which on a phone
    /// that had been through onboarding before was everything.
    @State private var selection = FamilyActivitySelection()
    @State private var selectionChanged = false
    @State private var stage: Stage = .asking
    /// How many times the picker closed with nothing ticked. Otto's line
    /// alternates on it, so a second empty close still visibly answers
    /// (the bubble retypes only when its words change).
    @State private var emptyCloses = 0

    private enum Stage { case asking, nothingPicked, declined, done }

    /// In Apple's picker, under its list.
    static let pickerTip = "Start with the app you open most without thinking. You can change it any time in 808's Block tab."

    private var title: String {
        context == .home ? "Pick one app for me to hold" : "Which apps steal your time?"
    }

    private var line: String {
        switch stage {
        case .asking:
            return context == .home
                ? "I'll hold it each day until you've meditated. Start with the one you open without thinking."
                : "Start with the one you open without thinking. For most people that's Instagram, TikTok or YouTube."
        case .nothingPicked:
            // Melvin, 2026-10-13: "It should say like hold on you have to
            // pick one".
            return emptyCloses.isMultiple(of: 2)
                ? "Still nothing picked. Just one app is enough to start."
                : "Hold on, you have to pick at least one. Even a small one works."
        case .declined:
            return "No problem. You can set this up later in the Block tab."
        case .done:
            return "Done. I'll hold it each day until you've meditated."
        }
    }

    private var cta: String {
        switch stage {
        case .asking, .nothingPicked: return "Choose apps"
        case .declined: return "Continue"
        case .done: return "Got it"
        }
    }

    var body: some View {
        IntroScreen(progress: 1,
                    title: title,
                    titleSize: 30,
                    subtitle: line,
                    cta: cta,
                    standing: false,
                    showsProgress: false,
                    // Home only: they are already in the app, so this asks.
                    secondary: context == .home && (stage == .asking || stage == .nothingPicked)
                        ? (title: "Not now", action: onSkip ?? onContinue) : nil,
                    onContinue: primary) { _ in EmptyView() }
        .familyActivityPicker(footerText: Self.pickerTip,
                              isPresented: $picking,
                              selection: Binding(get: { selection },
                                                 set: { selection = $0; selectionChanged = true }))
        .onChange(of: picking) { was, now in
            guard was, !now else { return }
            #if DEBUG && targetEnvironment(simulator)
            // The simulator's picker has nothing real to offer; opening and
            // closing it is the whole review, so any close counts. Simulator
            // only: on a phone the picker is real, and Block's test mode
            // (often left on in 808 Beta) must not wave an empty close
            // through, which is how Melvin got past this on 2026-10-13.
            if block.testMode { saveSelection(); return }
            #endif
            if selectionChanged, !selection.isEmptySelection {
                saveSelection()
            } else {
                emptyCloses += 1
                stage = .nothingPicked
                if Tactile.hapticsOn {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
        }
        // Asked here counts as asked: Home's one-time ask never repeats it.
        .onAppear { BlockAppsPrompt.markAsked() }
    }

    private func primary() {
        switch stage {
        case .asking, .nothingPicked: chooseApps()
        case .declined: (onSkip ?? onContinue)()
        case .done: onContinue()
        }
    }

    private func chooseApps() {
        Task {
            if !block.authorized, !(await block.requestAuthorization()) {
                stage = .declined
                return
            }
            selectionChanged = false
            picking = true
        }
    }

    private func saveSelection() {
        guard var mindfulDay = block.state.blockers.first(where: { $0.kind == .mindfulDay }) else {
            onContinue()
            return
        }
        if context == .home {
            // No schedule screen follows here: Mindful day keeps its own
            // hours (all day, until you meditate) and switches on, for
            // someone Block is open to (`BlockAccess`).
            mindfulDay.isOn = BlockAccess.allowed(store.entitlements)
            block.save(mindfulDay, selection: selection)
            stage = .done
        } else {
            block.save(mindfulDay, selection: selection)
            onContinue()
        }
    }
}

/// Home's one-time ask (`BlockAppsPrompt`): the apps screen standing in the
/// daytime valley, Otto seated where the scene seats him.
struct BlockAppsAskView: View {
    /// `.onboarding` only for the Settings rehearsal (`BlockAppsRehearsal`).
    var context: BlockAppsScreen.Context = .home
    let onDone: () -> Void

    var body: some View {
        ZStack {
            ValleyScene(progress: 0)
                .ignoresSafeArea()
            BlockAppsScreen(context: context, onContinue: onDone, onSkip: onDone)
                .keepsDarkStatusBar()
        }
        // The meadow's footnote ink (white with a shadow) for "Not now".
        .environment(\.onboardingSharedGround, true)
        .followsStatusBarRule()
    }
}

#if DEBUG
/// Settings > Block (debug) > "Onboarding's app pick" (Melvin, 2026-10-13:
/// "i dont want to have to go through onboarding again"). The onboarding
/// version of the screen (no "Not now", an empty close stops you), with a
/// close button the real one does not have. A pick is saved to Mindful day
/// exactly as onboarding saves it, then the screen closes where onboarding
/// would go on to the schedule.
struct BlockAppsRehearsal: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BlockAppsAskView(context: .onboarding) { dismiss() }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ValleyGround.ink)
                        .frame(width: 38, height: 38)
                        .background(AppColor.backgroundSecondary.opacity(0.9), in: Circle())
                }
                .buttonStyle(.tactile)
                .accessibilityLabel("Close")
                .padding(.trailing, 18)
                .padding(.top, 8)
            }
            // Otto's line ticks as it types, as it does in onboarding.
            .environment(\.typingHaptics, true)
    }
}
#endif

/// Screen: when Otto holds them. The question screens' layout (the title in
/// the sky, white plates, Otto writing in the corner), over `BlockWhenPicker`,
/// the same choices the Block tab's editor offers. "All day, until I
/// meditate" is preselected, so Continue alone is enough; Custom takes any
/// hours and days (Melvin, 2026-09-27: "put one more button that is custom,
/// allows them to set when they want"). Every choice is applied to the SAME
/// Mindful day blocker: choosing one never creates a second blocker.
struct BlockScheduleScreen: View {
    let onContinue: () -> Void

    @ObservedObject private var block = BlockController.shared
    @EnvironmentObject private var store: Store
    @Environment(\.onboardingBack) private var back
    @State private var choice: BlockWhen = .allDay
    @State private var hours = BlockHours()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
            }
            .frame(height: 40)

            ScrollView {
                VStack(spacing: 0) {
                    CornerQuestionTitle("When should I hold them?", size: 28)
                        .padding(.top, 30)

                    BlockWhenPicker(choice: $choice, hours: $hours)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", enabled: windowOK, action: save)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
    }

    private var windowOK: Bool {
        var probe = Blocker.preset(.custom)
        probe.apply(choice, hours: hours)
        return probe.windowProblem == nil
    }

    /// Saves the window on the same Mindful day blocker and switches it on
    /// (for someone Block is open to; see `BlockAccess`),
    /// through `BlockController.save`, the commit path the Block tab itself
    /// uses, which registers the DeviceActivity schedules and reconciles the
    /// shields. `save` already refuses to leave a blocker on with no apps, so
    /// someone who tapped "Not now" on the apps screen lands here, picks a
    /// schedule, and Mindful day simply stays off and waiting, the same as it
    /// is for anyone who has never opened the Block tab.
    private func save() {
        if let i = block.state.blockers.firstIndex(where: { $0.kind == .mindfulDay }) {
            var blocker = block.state.blockers[i]
            blocker.apply(choice, hours: hours)
            // Block is paid (`Entitlements.block`). The same check the Block
            // tab makes before switching one on: without it, the schedule is
            // still saved and the blocker waits, off, for a plan.
            blocker.isOn = BlockAccess.allowed(store.entitlements)
            block.save(blocker, selection: nil)
        }
        onContinue()
    }
}
