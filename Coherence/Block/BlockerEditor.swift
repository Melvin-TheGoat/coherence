import SwiftUI
import FamilyControls

/// One blocker's settings (`mockups/block-v1.html`, section 1, second screen):
/// Melvin's three (how often, when, which apps) and the three added in the
/// design (how strict, passes a day, the shortest session that counts).
///
/// Everything is a draft until Save. The apps are picked in Apple's own
/// picker, and what comes back is tokens: 808 never learns which apps.
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
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    days
                    when
                    apps
                    strictness
                    if draft.strictness != .strict { passes }
                    minimum
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            Button(isNew ? "Save blocker" : "Save", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 12)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .familyActivityPicker(isPresented: $picking, selection: Binding(
            get: { selection },
            set: { selection = $0; selectionChanged = true }))
        .onAppear {
            if pickOnAppear { openPicker() }
        }
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(original.id) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Otto stops holding these apps.")
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(OttoPose.head.asset)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            TextField("Name", text: $draft.name)
                .font(DisplayFont.display(24))
                .foregroundStyle(AppColor.textPrimary)
                .submitLabel(.done)
            Toggle("", isOn: $draft.isOn)
                .labelsHidden()
                .tint(AppColor.accentGold)
        }
    }

    private var days: some View {
        section("How often") {
            HStack(spacing: 6) {
                // Monday first, the way people say a week.
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                    let on = draft.weekdays.contains(weekday)
                    Button {
                        if on, draft.weekdays.count > 1 { draft.weekdays.remove(weekday) }
                        else { draft.weekdays.insert(weekday) }
                    } label: {
                        Text(Self.initial(weekday))
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(AppColor.textPrimary)
                            .background(chipFill(on), in: Circle())
                            .overlay(Circle().stroke(on ? AppColor.accentGold : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var when: some View {
        if draft.dailyLimitMinutes != nil {
            section("Held after") {
                chips([15, 30, 45, 60, 90], selected: draft.dailyLimitMinutes ?? 30,
                      label: { "\($0) min a day" }) { draft.dailyLimitMinutes = $0 }
            }
        } else {
            section("When") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        chip("All day", on: draft.window == .allDay) { draft.window = .allDay }
                        chip("Set hours", on: draft.window != .allDay) {
                            if draft.window == .allDay { draft.window = .hours(start: 6 * 60, end: 10 * 60) }
                        }
                    }
                    if case .hours(let start, let end) = draft.window {
                        HStack(spacing: 10) {
                            DatePicker("From", selection: minutesBinding(start, isEnd: false) { draft.window = .hours(start: $0, end: end) },
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("to")
                                .foregroundStyle(AppColor.textSecondary)
                            DatePicker("To", selection: minutesBinding(end, isEnd: true) { draft.window = .hours(start: start, end: $0) },
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .tint(AppColor.accentGold)
                    }
                }
            }
        }
    }

    private var apps: some View {
        section("Apps Otto holds") {
            HStack {
                PickedApps(selection: selection,
                           hasApps: selectionChanged ? !selection.isEmptySelection : draft.hasApps)
                Spacer()
                Button(selection.isEmptySelection && !draft.hasApps ? "Choose" : "Change") { openPicker() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.accentGoldText)
            }
            .padding(14)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var strictness: some View {
        section("How strict") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(BlockStrictness.allCases, id: \.self) { level in
                        chip(level.label, on: draft.strictness == level) { draft.strictness = level }
                    }
                }
                Text(draft.strictness.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var passes: some View {
        section("Passes a day") {
            HStack(spacing: 8) {
                ForEach([1, 2, 3], id: \.self) { n in
                    chip("\(n)", on: draft.passesPerDay == n) { draft.passesPerDay = n }
                }
                chip("No limit", on: draft.passesPerDay == nil) { draft.passesPerDay = nil }
            }
        }
    }

    private var minimum: some View {
        section("A session that counts") {
            chips([1, 2, 5, 10], selected: draft.minimumMinutes, label: { "\($0) min" }) {
                draft.minimumMinutes = $0
            }
        }
    }

    private var deleteButton: some View {
        Button("Delete this blocker", role: .destructive) { confirmDelete = true }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DisplayFont.display(16))
                .foregroundStyle(AppColor.textPrimary)
            content()
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(chipFill(on), in: Capsule())
                .overlay(Capsule().stroke(on ? AppColor.accentGold : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chips(_ values: [Int], selected: Int, label: @escaping (Int) -> String,
                       set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                chip(label(value), on: value == selected) { set(value) }
            }
        }
    }

    private func chipFill(_ on: Bool) -> Color {
        on ? AppColor.accentGold.opacity(0.18) : AppColor.backgroundSecondary
    }

    private static func initial(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }

    /// Minutes from midnight as a clock time today, and back.
    private func minutesBinding(_ minutes: Int, isEnd: Bool, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: minutes % 1440,
                                      to: Calendar.current.startOfDay(for: Date())) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                // Midnight as an end means the end of the day.
                set(isEnd && value == 0 ? 1440 : value)
            })
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
        let name = saved.name.trimmingCharacters(in: .whitespaces)
        saved.name = name.isEmpty ? Blocker.preset(saved.kind).name : name
        if selectionChanged { saved.hasApps = !selection.isEmptySelection }
        onSave(saved, selectionChanged ? selection : nil)
    }
}
