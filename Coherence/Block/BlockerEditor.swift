import SwiftUI
import FamilyControls

/// One blocker's settings, as ONE simple screen (Melvin, 2026-09-27: "Add a
/// blocker should just be one thing, not three options 'all day' vs schedule
/// vs daily limit. And it should basically look identical to how it did in
/// the onboarding, super simple and easy to understand, and by default its
/// set to all day so the user can set it in one click.")
///
/// This REPLACES Brainrot's segmented All Day / Schedule / Daily Limit
/// editor (2026-09-22, `mockups/blocker-editor-v2.html`) with the onboarding's
/// own screen (`BlockScheduleScreen` in `OnboardingBlockSetup.swift`): the
/// same title style, the same `BlockWhenPicker` over `BlockWhen`'s
/// choices (`Coherence/Block/BlockWhen.swift`), All day preselected. Onboarding
/// and this editor now draw the identical picker, so they can never disagree
/// about what a blocker can be set to.
///
/// **What this does NOT touch: how Block behaves.** Same windows, weekdays,
/// `Blocker.sessionMinutes`, "Not now", the same Mindful day blocker
/// onboarding seeds. Only the picking got simpler: no name field, no mode
/// segments, no per-blocker symbol picker, no daily-limit wheel. A blocker
/// made here is named and symbolled after the choice
/// (`BlockWhen.blockerName` / `.icon`), the way onboarding already does it.
struct BlockerEditor: View {
    let original: Blocker
    let isNew: Bool
    /// Open the app picker as the sheet arrives: the switch was flipped on a
    /// blocker with no apps yet.
    let pickOnAppear: Bool
    @ObservedObject var block: BlockController
    let onSave: (Blocker, FamilyActivitySelection?) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Blocker
    @State private var selection: FamilyActivitySelection
    @State private var selectionChanged = false
    @State private var picking = false
    @State private var confirmDelete = false
    @State private var choice: BlockWhen
    @State private var hours: BlockHours
    /// An OLD daily limit (the only survivor of the deleted All Day /
    /// Schedule / Daily Limit control) is kept as is until a `BlockWhen`
    /// choice is tapped, which drops it for good: this screen has no way
    /// back into a limit. New blockers never start with one.
    @State private var keepsLimit: Bool

    init(original: Blocker, isNew: Bool, pickOnAppear: Bool, block: BlockController,
         onSave: @escaping (Blocker, FamilyActivitySelection?) -> Void,
         onDelete: @escaping (UUID) -> Void) {
        self.original = original
        self.isNew = isNew
        self.pickOnAppear = pickOnAppear
        self.block = block
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: original)
        _selection = State(initialValue: BlockStore.selection(for: original.id))
        _choice = State(initialValue: BlockWhen.of(original))
        _hours = State(initialValue: BlockHours(original))
        _keepsLimit = State(initialValue: original.dailyLimitMinutes != nil)
    }

    /// The meadow at its near edge, so the footer's fade lands on the same
    /// green the valley's own grass ends in.
    private static let meadow = DayLight.at(0).field[1]

    var body: some View {
        ZStack(alignment: .bottom) {
            ValleyScene(progress: 0, showsFigure: false)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Text("Which apps steal your time?")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 46)

                    appsPlate

                    VStack(spacing: 14) {
                        Text("When should I hold them?")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)

                        if keepsLimit {
                            OnboardingOption(label: "Daily limit, \(Self.duration(dailyLimitMinutes))",
                                             selected: true) {}
                                .accessibilityHint("This blocker's old daily limit. Pick a time below to replace it.")
                        }

                        BlockWhenPicker(choice: whenChoice, hours: $hours)
                    }
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, isNew ? 120 : 150)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .overlay(alignment: .topLeading) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(AppColor.backgroundSecondary.opacity(0.78), in: Capsule())
                .padding(.leading, AppMetrics.screenPadding)
                .padding(.top, 16)
        }
        .familyActivityPicker(isPresented: $picking, selection: Binding(
            get: { selection },
            set: { selection = $0; selectionChanged = true }))
        // After the sheet has settled: presenting Apple's picker while this
        // sheet is still animating in can drop it.
        .task {
            guard pickOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            openPicker()
        }
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(original.id) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Otto stops holding these apps.")
        }
    }

    // MARK: - The apps plate

    /// White, radius 12, 16pt padding: the onboarding answer plate's own
    /// look (`OnboardingOption`). Its trailing content differs (the picked
    /// apps' own icons, not a checkbox), so it is its own small view rather
    /// than a literal `OnboardingOption`.
    private var appsPlate: some View {
        Button(action: openPicker) {
            HStack(spacing: 12) {
                Text(appsLine)
                    .font(AppFont.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 8)
                if selection.isEmptySelection {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    PickedApps(selection: selection, hasApps: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
    }

    private var hasApps: Bool { selectionChanged ? !selection.isEmptySelection : draft.hasApps }

    private var appsLine: String {
        if !selection.isEmptySelection {
            let n = selection.pickedCount
            return n == 1 ? "1 app" : "\(n) apps"
        }
        return hasApps ? "Your apps" : "Choose apps"
    }

    // MARK: - The schedule

    /// Tapping any of the four choices drops a kept daily limit for good:
    /// there is no path back to one on this screen.
    private var whenChoice: Binding<BlockWhen> {
        Binding(get: { choice }, set: { choice = $0; keepsLimit = false })
    }

    private var dailyLimitMinutes: Int { original.dailyLimitMinutes ?? 30 }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// What Screen Time would refuse, said here rather than after Save. A
    /// kept daily limit always runs all day, so it never has this problem.
    private var appliedProblem: String? {
        guard !keepsLimit else { return nil }
        var probe = Blocker.preset(.custom)
        probe.apply(choice, hours: hours)
        return probe.windowProblem
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            // Screen Time refuses a window under fifteen minutes; say so
            // here rather than save a blocker that never holds.
            if let problem = appliedProblem {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(AppColor.backgroundSecondary, in: Capsule())
            }
            Button(isNew ? "Save blocker" : "Save changes", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appliedProblem != nil)
                .opacity(appliedProblem == nil ? 1 : 0.5)
            if !isNew {
                // A pill, because it is a control; the house rule is that a
                // capsule is something you press.
                Button("Delete blocker", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(AppColor.backgroundSecondary.opacity(0.85), in: Capsule())
            }
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Self.meadow.opacity(0), Self.meadow, Self.meadow],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                // Fades never catch touches: the clear top would swallow taps
                // on whatever scrolls under it.
                .allowsHitTesting(false)
        )
    }

    // MARK: - Actions

    private func openPicker() {
        Task {
            if !block.authorized {
                guard await block.requestAuthorization() else { return }
            }
            picking = true
        }
    }

    private func save() {
        var saved = draft
        if !keepsLimit {
            saved.apply(choice, hours: hours)
        }
        // A new blocker is named and symbolled after the choice, the way
        // onboarding's own Mindful day already is; an existing one keeps
        // whatever it was called and marked with.
        if isNew {
            saved.name = choice.blockerName
            saved.symbol = choice.icon
        }
        if selectionChanged { saved.hasApps = !selection.isEmptySelection }
        // Adding a blocker means wanting it on. The tab's save still checks
        // Block is paid for and routes to the paywall when it is not.
        if isNew { saved.isOn = true }
        onSave(saved, selectionChanged ? selection : nil)
    }
}
