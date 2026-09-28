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
// everyone — neither screen invents a second one. Picking no apps and taking
// the preselected schedule is a valid, thoughtless path all the way through:
// Mindful day is left exactly as waiting as it is for someone who never opens
// the Block tab at all.

/// Screen: which apps Otto holds. In the onboarding's own look (Melvin,
/// 2026-09-27: it "looks different than the rest of the onboarding, like i
/// want the text to type in like it did before"): the title in the sky and
/// Otto, seated and writing, saying his line a letter at a time, the way the
/// personalize screen does. "Choose apps" asks for Screen Time access if 808
/// doesn't have it yet, then opens Apple's own picker. There is no error
/// state and no dead end: a refusal, a failure, or picking nothing all just
/// move on to the schedule, the same as tapping "Not now".
struct BlockAppsScreen: View {
    let onContinue: () -> Void

    @ObservedObject private var block = BlockController.shared
    @State private var picking = false
    /// Nothing ticked when the picker opens (Melvin, 2026-09-27: "it
    /// shouldnt by default select all apps, it shouldnt select any"). It
    /// used to open on whatever Mindful day already held, which on a phone
    /// that had been through onboarding before was everything.
    @State private var selection = FamilyActivitySelection()
    @State private var selectionChanged = false

    var body: some View {
        IntroScreen(progress: 1,
                    title: "Which apps steal your time?",
                    titleSize: 30,
                    subtitle: "I'll hold them until you've meditated.",
                    cta: "Choose apps",
                    standing: false,
                    showsProgress: false,
                    secondary: (title: "Not now", action: onContinue),
                    onContinue: chooseApps) { _ in EmptyView() }
        .familyActivityPicker(isPresented: $picking, selection: Binding(
            get: { selection },
            set: { selection = $0; selectionChanged = true }))
        .onChange(of: picking) { was, now in
            guard was, !now else { return }
            #if DEBUG
            // The simulator's picker has nothing real to offer; opening and
            // closing it is the whole review, so any close counts.
            if block.testMode { saveSelection(); return }
            #endif
            guard selectionChanged, !selection.isEmptySelection else { return }
            saveSelection()
        }
    }

    private func chooseApps() {
        Task {
            if !block.authorized, !(await block.requestAuthorization()) {
                onContinue()
                return
            }
            picking = true
        }
    }

    private func saveSelection() {
        guard let mindfulDay = block.state.blockers.first(where: { $0.kind == .mindfulDay }) else {
            onContinue()
            return
        }
        block.save(mindfulDay, selection: selection)
        onContinue()
    }
}

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
    @Environment(\.onboardingBack) private var back
    @State private var choice: BlockWhen = .allDay
    @State private var hours = BlockHours()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
                // Otto's corner (`SeatedClipLayer.cornerWidth`).
                Color.clear.frame(width: SeatedClipLayer.cornerWidth)
            }
            .frame(height: 40)

            ScrollView {
                VStack(spacing: 0) {
                    Text("When should I hold them?")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
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

    /// Saves the window on the same Mindful day blocker and switches it on,
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
            blocker.isOn = true
            block.save(blocker, selection: nil)
        }
        onContinue()
    }
}
