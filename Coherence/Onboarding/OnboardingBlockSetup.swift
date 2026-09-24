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

/// Screen: which apps Otto holds. "Choose apps" asks for Screen Time access
/// if 808 doesn't have it yet, then opens Apple's own picker right away.
/// There is no error state and no dead end: a refusal, a failure, or picking
/// nothing all just move on to the schedule, the same as tapping "Not now".
struct BlockAppsScreen: View {
    let onContinue: () -> Void

    @ObservedObject private var block = BlockController.shared
    @Environment(\.onboardingBack) private var back
    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false
    @State private var picking = false
    @State private var selection: FamilyActivitySelection
    @State private var selectionChanged = false

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        // Whatever Mindful day already holds, so re-opening the picker (a
        // resumed onboarding, or Back and forward again) shows what was
        // actually picked rather than starting over blank.
        let mindfulDayID = BlockController.shared.state.blockers.first { $0.kind == .mindfulDay }?.id
        _selection = State(initialValue: mindfulDayID.map { BlockController.shared.selection(for: $0) }
                            ?? FamilyActivitySelection())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
            }
            .frame(height: 40)

            Spacer(minLength: 8)

            OttoSpeech(text: "Which apps steal your time? I'll hold them until you've meditated.",
                       speaking: $speaking)
                .opacity(appeared ? 1 : 0)

            OttoInMeadow(pose: .talking, talking: speaking, rig: rig)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                OnboardingCTA(title: "Choose apps", action: chooseApps)
                Button(action: onContinue) {
                    Text("Not now").modifier(FootnoteInk())
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
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
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
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

/// Screen: when Otto holds them. "All day, until I meditate" — Mindful day's
/// own schedule — is preselected, so Continue alone is enough. The two
/// alternatives are schedules `BlockModel` already knows (`mindfulMorning`,
/// `focusHours`), read off their presets rather than restated here, and
/// applied to the SAME blocker: choosing one never creates a second blocker,
/// it just changes when Mindful day runs.
struct BlockScheduleScreen: View {
    let onContinue: () -> Void

    @ObservedObject private var block = BlockController.shared
    @Environment(\.onboardingBack) private var back
    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false
    @State private var choice: Choice = .allDay

    private enum Choice: CaseIterable, Hashable {
        case allDay, mornings, weekdays

        var title: String {
            switch self {
            case .allDay: return "All day, until I meditate"
            case .mornings: return "Mornings, 6 to 10"
            case .weekdays: return "Weekdays, 9 to 5"
            }
        }

        var icon: String {
            switch self {
            case .allDay: return BlockerKind.mindfulDay.defaultSymbol
            case .mornings: return BlockerKind.mindfulMorning.defaultSymbol
            case .weekdays: return BlockerKind.focusHours.defaultSymbol
            }
        }

        var window: BlockWindow {
            switch self {
            case .allDay: return .allDay
            case .mornings: return Blocker.preset(.mindfulMorning).window
            case .weekdays: return Blocker.preset(.focusHours).window
            }
        }

        var weekdays: Set<Int> {
            self == .weekdays ? Blocker.preset(.focusHours).weekdays : Set(1...7)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
            }
            .frame(height: 40)

            OttoSpeech(text: "When should I hold them?", speaking: $speaking)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)

            OttoInMeadow(pose: .talking, talking: speaking, rig: rig)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 10) {
                ForEach(Choice.allCases, id: \.self) { option in
                    OnboardingOption(label: option.title, icon: option.icon,
                                     selected: choice == option) { choice = option }
                }
            }
            .padding(.top, 20)
            .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: save)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }

    /// Saves the window on the same Mindful day blocker and switches it on,
    /// through `BlockController.save` — the commit path the Block tab itself
    /// uses, which registers the DeviceActivity schedules and reconciles the
    /// shields. `save` already refuses to leave a blocker on with no apps, so
    /// someone who tapped "Not now" on the apps screen lands here, picks a
    /// schedule, and Mindful day simply stays off and waiting, the same as it
    /// is for anyone who has never opened the Block tab.
    private func save() {
        if let i = block.state.blockers.firstIndex(where: { $0.kind == .mindfulDay }) {
            var blocker = block.state.blockers[i]
            blocker.window = choice.window
            blocker.weekdays = choice.weekdays
            blocker.isOn = true
            block.save(blocker, selection: nil)
        }
        onContinue()
    }
}
