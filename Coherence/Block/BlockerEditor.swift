import SwiftUI
import FamilyControls

/// One blocker's settings, in Brainrot's shape (Aziz, 2026-09-22, with three
/// screenshots of Brainrot's editor: "make it more like this and also just use
/// current theme i dont like the current pastel brown in here").
/// `mockups/blocker-editor-v2.html` is the approved drawing.
///
/// Top to bottom, Brainrot's order: the blocker's symbol in a circle with a
/// pencil, its name, **All Day / Schedule / Daily Limit** as one control, the
/// apps, the hours or the limit, and Active Days as presets over seven circles.
/// Then one card for the three things only 808 has (how strict Otto is,
/// passes a day, the shortest session that opens the apps), which were three
/// separate sections before and most of why the old screen felt long.
///
/// **The ground is the valley**, the sky and grass Profile and Home stand in,
/// not the cream page with gold-tinted chips that read as pastel brown. Every
/// choice lights in `skyDeep`; the one gold object is Save.
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
    @State private var pickingSymbol = false
    @State private var editingTime: TimeEnd?
    @State private var editingLimit = false

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

    /// The meadow at its near edge, which the page continues under the band.
    private static let meadow = DayLight.at(0).field[1]
    private static let bandHeight: CGFloat = 132
    private static let circle: CGFloat = 88

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    band
                    VStack(alignment: .leading, spacing: 0) {
                        nameField.padding(.bottom, 12)
                        modeControl.padding(.bottom, 18)
                        if mode == .dailyLimit {
                            heading("Daily limit")
                            limitCard.padding(.bottom, 18)
                        }
                        heading("Blocked apps")
                        appsField.padding(.bottom, 18)
                        if mode == .schedule {
                            heading("Timeframe")
                            timeFields.padding(.bottom, 18)
                        }
                        heading("Active days")
                        dayPresets.padding(.bottom, 10)
                        dayCircles.padding(.bottom, 20)
                        rulesCard
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, Self.circle / 2 + 14)
                    // Room for the pinned footer, so the rules card can be
                    // scrolled clear of Save.
                    .padding(.bottom, isNew ? 120 : 150)
                    .animation(.spring(response: 0.36, dampingFraction: 0.88), value: mode)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            footer
        }
        .background(Self.meadow.ignoresSafeArea())
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
        .sheet(isPresented: $pickingSymbol) {
            SymbolPicker(selected: draft.displaySymbol) { draft.symbol = $0 }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTime) { end in
            TimeWheel(title: end == .start ? "From" : "Until",
                      minutes: hours(end),
                      isEnd: end == .end) { setHours(end, $0) }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $editingLimit) {
            LimitWheel(minutes: draft.dailyLimitMinutes ?? 30) { draft.dailyLimitMinutes = $0 }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(original.id) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Otto stops holding these apps.")
        }
    }

    // MARK: - The band and the mark

    /// The valley with nobody in it, and the blocker's symbol in a circle on
    /// the seam, the way Profile seats its portrait.
    private var band: some View {
        ValleyScene(progress: 0, showsFigure: false)
            .frame(height: Self.bandHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.white.opacity(0.78), in: Capsule())
                    .padding(.leading, AppMetrics.screenPadding)
                    .padding(.top, 16)
            }
            .overlay(alignment: .bottom) {
                mark.offset(y: Self.circle / 2)
            }
            .zIndex(1)
    }

    private var mark: some View {
        Button { pickingSymbol = true } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: draft.displaySymbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppColor.skyDeep)
                    .frame(width: Self.circle, height: Self.circle)
                    .background(AppColor.skyWash, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.meadowInk)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    .offset(x: 6, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change this blocker's symbol")
    }

    // MARK: - Brainrot's fields

    private var nameField: some View {
        TextField("Name", text: $draft.name)
            .font(DisplayFont.display(17, .heavy))
            .foregroundStyle(AppColor.textPrimary)
            .submitLabel(.done)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeControl: some View {
        Segmented(options: Mode.allCases, selected: mode, label: \.label, compact: false) { setMode($0) }
    }

    private var appsField: some View {
        Button(action: openPicker) {
            HStack(spacing: 10) {
                Text(appsLine)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hasApps ? AppColor.textPrimary : AppColor.meadowInk)
                Spacer(minLength: 8)
                if selection.isEmptySelection {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.meadowInk)
                } else {
                    PickedApps(selection: selection, hasApps: true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(minHeight: 54)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var timeFields: some View {
        HStack(spacing: 10) {
            timeField(.start)
            timeField(.end)
        }
    }

    private func timeField(_ end: TimeEnd) -> some View {
        Button { editingTime = end } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(end == .start ? "From" : "Until")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.meadowInk)
                Text(Self.clock(hours(end)))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }

    private static let limits = [15, 30, 60, 120]

    private var limitCard: some View {
        let current = draft.dailyLimitMinutes ?? 30
        let custom = !Self.limits.contains(current)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Self.limits, id: \.self) { value in
                    chip(Self.duration(value), on: current == value) { draft.dailyLimitMinutes = value }
                }
                chip(custom ? Self.duration(current) : "Custom", on: custom) { editingLimit = true }
            }
            Text("Counts your time in these apps today. Past the limit, Otto holds them until you meditate.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Brainrot's presets, lit only when the circles below match them
    /// exactly: tap a single day and the preset goes dark by itself, because
    /// the days no longer are any of them.
    private var dayPresets: some View {
        HStack(spacing: 8) {
            ForEach(DayPreset.allCases, id: \.self) { preset in
                let on = draft.weekdays == preset.days
                Button { draft.weekdays = preset.days } label: {
                    Text(preset.label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? .white : AppColor.meadowInk)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(on ? AppColor.skyDeep : .white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var dayCircles: some View {
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { weekday in
                let on = draft.weekdays.contains(weekday)
                Button {
                    // At least one day, or the blocker would never run.
                    if on, draft.weekdays.count > 1 { draft.weekdays.remove(weekday) }
                    else { draft.weekdays.insert(weekday) }
                } label: {
                    Text(Self.dayLetters[weekday - 1])
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(on ? .white : AppColor.meadowInk)
                        .frame(width: 42, height: 42)
                        .background(on ? AppColor.skyDeep : .white, in: Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: - 808's own three

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When Otto lets you in")
                .font(DisplayFont.display(15, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Segmented(options: BlockStrictness.allCases, selected: draft.strictness,
                      label: \.label, compact: true, track: BlockerEditor.quiet) {
                draft.strictness = $0
            }
            Text(draft.strictness.explanation)
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Strict takes no passes, so the row would be a setting for
            // nothing.
            if draft.strictness != .strict {
                ruleRow("Passes a day", value: draft.passesPerDay.map(String.init) ?? "No limit") {
                    ForEach([1, 2, 3], id: \.self) { n in
                        Button("\(n)") { draft.passesPerDay = n }
                    }
                    Button("No limit") { draft.passesPerDay = nil }
                }
            }
            ruleRow("A session that opens them", value: "\(draft.minimumMinutes) min") {
                ForEach([1, 2, 5, 10], id: \.self) { n in
                    Button("\(n) min") { draft.minimumMinutes = n }
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: draft.strictness)
    }

    private func ruleRow<Items: View>(_ title: String, value: String,
                                      @ViewBuilder items: () -> Items) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Self.quiet).frame(height: 1).padding(.bottom, 10)
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Menu { items() } label: {
                    HStack(spacing: 4) {
                        Text(value)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.skyDeep)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            // Screen Time refuses a window under fifteen minutes; say so
            // here rather than save a blocker that never holds.
            if let problem = draft.windowProblem {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
            Button(isNew ? "Save blocker" : "Save changes", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft.windowProblem != nil)
                .opacity(draft.windowProblem == nil ? 1 : 0.5)
            if !isNew {
                // A pill, because it is a control; the house rule is that a
                // capsule is something you press.
                Button("Delete blocker", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.white.opacity(0.85), in: Capsule())
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
        )
    }

    // MARK: - Pieces

    /// A section title on the grass. White with a soft shadow: ink on the
    /// meadow reads, but white is what the approved drawing uses and it keeps
    /// the fields, not the titles, as the objects on the page.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(DisplayFont.display(15, .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? .white : AppColor.meadowInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(on ? AppColor.skyDeep : Self.quiet,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private static let dayLetters = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    /// Tracks, unchosen chips and dividers on a white field. NOT the app's
    /// `hairline`, which is cream: on these white fields it read as the
    /// pastel brown this screen was rebuilt to lose.
    static let quiet = AppColor.meadowInk.opacity(0.11)

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: (minutes % 1440) / 60, minute: minutes % 60,
                                         second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Mode

    enum Mode: CaseIterable, Hashable {
        case allDay, schedule, dailyLimit
        var label: String {
            switch self {
            case .allDay: return "All Day"
            case .schedule: return "Schedule"
            case .dailyLimit: return "Daily Limit"
            }
        }
    }

    /// Derived from the blocker rather than stored, so a blocker saved by the
    /// old editor opens on the right segment.
    private var mode: Mode {
        if draft.dailyLimitMinutes != nil { return .dailyLimit }
        return draft.window == .allDay ? .allDay : .schedule
    }

    /// A daily limit counts minutes across the whole day, so it runs all day;
    /// a schedule that was never set starts on Brainrot's nine to five.
    private func setMode(_ new: Mode) {
        switch new {
        case .allDay:
            draft.dailyLimitMinutes = nil
            draft.window = .allDay
        case .schedule:
            draft.dailyLimitMinutes = nil
            if draft.window == .allDay { draft.window = .hours(start: 9 * 60, end: 17 * 60) }
        case .dailyLimit:
            draft.dailyLimitMinutes = draft.dailyLimitMinutes ?? 30
            draft.window = .allDay
        }
    }

    enum TimeEnd: Identifiable { case start, end; var id: Self { self } }

    private func hours(_ end: TimeEnd) -> Int {
        guard case .hours(let start, let finish) = draft.window else { return end == .start ? 9 * 60 : 17 * 60 }
        return end == .start ? start : finish
    }

    private func setHours(_ end: TimeEnd, _ value: Int) {
        guard case .hours(let start, let finish) = draft.window else { return }
        draft.window = end == .start ? .hours(start: value, end: finish) : .hours(start: start, end: value)
    }

    private enum DayPreset: CaseIterable {
        case weekdays, weekends, all
        var label: String {
            switch self {
            case .weekdays: return "Weekdays"
            case .weekends: return "Weekends"
            case .all: return "All"
            }
        }
        var days: Set<Int> {
            switch self {
            case .weekdays: return Set(2...6)
            case .weekends: return [1, 7]
            case .all: return Set(1...7)
            }
        }
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
        // The editor has no switch any more (Brainrot's has none): adding a
        // blocker means wanting it on. The tab's save still checks Block is
        // paid for and routes to the paywall when it is not.
        if isNew { saved.isOn = true }
        onSave(saved, selectionChanged ? selection : nil)
    }
}

// MARK: - The segmented control

/// Brainrot's segmented control in the valley's colours: a pale track, the
/// chosen segment solid sky with a lip under it, white text on it.
private struct Segmented<Option: Hashable>: View {
    let options: [Option]
    let selected: Option
    let label: (Option) -> String
    let compact: Bool
    var track: Color = .white.opacity(0.6)
    let pick: (Option) -> Void

    init(options: [Option], selected: Option, label: KeyPath<Option, String>, compact: Bool,
         track: Color = .white.opacity(0.6), pick: @escaping (Option) -> Void) {
        self.options = options
        self.selected = selected
        self.label = { $0[keyPath: label] }
        self.compact = compact
        self.track = track
        self.pick = pick
    }

    @Namespace private var lit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selected
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pick(option) }
                } label: {
                    Text(label(option))
                        .font(.system(size: compact ? 13 : 14, weight: .bold))
                        .foregroundStyle(on ? .white : AppColor.meadowInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 7 : 10)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                                    .fill(AppColor.skyDeep)
                                    .shadow(color: AppColor.skyDeepEdge, radius: 0, y: 2)
                                    .matchedGeometryEffect(id: "lit", in: lit)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(track, in: RoundedRectangle(cornerRadius: compact ? 13 : 18, style: .continuous))
    }
}

// MARK: - Sheets

/// The blocker's symbol, under the pencil. SF Symbols only: emoji arrive in a
/// palette that is not ours and cannot take the sky.
private struct SymbolPicker: View {
    let selected: String
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static let symbols = [
        "sun.max.fill", "sunrise.fill", "sunset.fill", "moon.stars.fill",
        "briefcase.fill", "book.fill", "graduationcap.fill", "hourglass",
        "bed.double.fill", "figure.walk", "dumbbell.fill", "leaf.fill",
        "flame.fill", "cup.and.saucer.fill", "iphone", "hand.raised.fill",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Pick a symbol")
                .font(DisplayFont.display(17, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Self.symbols, id: \.self) { name in
                    let on = name == selected
                    Button {
                        pick(name)
                        dismiss()
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(on ? .white : AppColor.skyDeep)
                            .frame(width: 56, height: 56)
                            .background(on ? AppColor.skyDeep : AppColor.skyWash, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.replacingOccurrences(of: ".fill", with: "")
                                            .replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            Spacer(minLength: 0)
        }
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
    }
}

/// One end of a schedule, on the wheel.
private struct TimeWheel: View {
    let title: String
    let minutes: Int
    let isEnd: Bool
    let set: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(DisplayFont.display(17, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button("Done") { commit() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColor.skyDeep)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 20)
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Spacer(minLength: 0)
        }
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
        .onAppear {
            // By clock time, not minutes added to midnight, for the same
            // daylight saving reason as `Blocker.clockTime`.
            date = Calendar.current.date(bySettingHour: (minutes % 1440) / 60, minute: minutes % 60,
                                         second: 0, of: Date()) ?? Date()
        }
    }

    private func commit() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Midnight as an end means the end of the day.
        set(isEnd && value == 0 ? 1440 : value)
        dismiss()
    }
}

/// A custom daily limit, hours and minutes on two wheels.
private struct LimitWheel: View {
    let minutes: Int
    let set: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 0
    @State private var mins = 30

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Daily limit")
                    .font(DisplayFont.display(17, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button("Done") {
                    // Five minutes at least: a zero limit would hold the apps
                    // from the first second, which is what All Day is for.
                    set(max(5, hours * 60 + mins))
                    dismiss()
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColor.skyDeep)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 20)
            HStack(spacing: 0) {
                Picker("Hours", selection: $hours) {
                    ForEach(0...8, id: \.self) { Text("\($0) h").tag($0) }
                }
                Picker("Minutes", selection: $mins) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { Text("\($0) min").tag($0) }
                }
            }
            .pickerStyle(.wheel)
            Spacer(minLength: 0)
        }
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
        .onAppear {
            hours = min(8, minutes / 60)
            mins = (minutes % 60) / 5 * 5
        }
    }
}
