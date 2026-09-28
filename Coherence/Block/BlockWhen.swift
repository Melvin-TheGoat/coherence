import SwiftUI

/// When Otto holds a blocker's apps, as one plain choice (Melvin, 2026-09-27:
/// "Add a blocker should just be one thing, not three options ... it should
/// basically look identical to how it did in the onboarding ... by default
/// its set to all day so the user can set it in one click").
///
/// The onboarding's "When should I hold them?" and the Block tab's editor both
/// draw `BlockWhenPicker` over this, so the two can never offer different
/// things. It replaced the editor's All Day / Schedule / Daily Limit control.
enum BlockWhen: Hashable, CaseIterable {
    case allDay, mornings, weekdays, nightOwl, custom

    /// Night owl's hours (Melvin, 2026-09-27): 6 pm until 6 am, every day,
    /// the evening scroll and the phone in bed. It runs past midnight, which
    /// `BlockWindow.hours` already means by an end before the start.
    static let nightOwlWindow = BlockWindow.hours(start: 18 * 60, end: 6 * 60)

    var title: String {
        switch self {
        case .allDay: return "All day, until I meditate"
        case .mornings: return "Mornings, 6 to 10"
        case .weekdays: return "Weekdays, 9 to 5"
        case .nightOwl: return "Night owl, 6 pm to 6 am"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .allDay: return BlockerKind.mindfulDay.defaultSymbol
        case .mornings: return BlockerKind.mindfulMorning.defaultSymbol
        case .weekdays: return BlockerKind.focusHours.defaultSymbol
        case .nightOwl: return BlockerKind.windDown.defaultSymbol
        case .custom: return "clock"
        }
    }

    /// A new blocker is named after its choice, so two of them in the list
    /// read as different things without a name field to fill in.
    var blockerName: String {
        switch self {
        case .allDay: return "All day"
        case .mornings: return "Mornings"
        case .weekdays: return "Work hours"
        case .nightOwl: return "Night owl"
        case .custom: return "My hours"
        }
    }

    /// Which choice a saved blocker is. Anything with hours that are not one
    /// of the two presets reads as Custom, which shows those hours.
    static func of(_ blocker: Blocker) -> BlockWhen {
        switch blocker.window {
        case .allDay:
            return blocker.weekdays == Set(1...7) ? .allDay : .custom
        case .hours:
            let morning = Blocker.preset(.mindfulMorning), work = Blocker.preset(.focusHours)
            if blocker.window == morning.window && blocker.weekdays == morning.weekdays { return .mornings }
            if blocker.window == work.window && blocker.weekdays == work.weekdays { return .weekdays }
            if blocker.window == nightOwlWindow && blocker.weekdays == Set(1...7) { return .nightOwl }
            return .custom
        }
    }
}

/// The custom hours and days, kept apart from the choice so switching away
/// from Custom and back does not lose what was set.
struct BlockHours: Equatable {
    /// Minutes after midnight. An end at or before the start is the next day.
    var start = 20 * 60
    var end = 22 * 60
    var days: Set<Int> = Set(1...7)
    /// "From [time] until I meditate": no end but a session (or midnight).
    var untilMeditate = false

    init() {}

    init(_ blocker: Blocker) {
        switch blocker.window {
        case .hours(let s, let e):
            start = s
            end = e
        case .allDay:
            // All day on only some days reads as Custom, so its hours must be
            // the whole day: the 8 pm to 10 pm default here used to be saved
            // over it the moment anything else on the blocker was changed.
            if BlockWhen.of(blocker) == .custom {
                start = 0
                end = 24 * 60
            }
        }
        days = blocker.weekdays
        untilMeditate = blocker.untilSession == true
    }

    /// The end actually saved: midnight when the end is a session.
    var effectiveEnd: Int { untilMeditate ? 24 * 60 : end }
}

extension Blocker {
    /// Writes a choice onto the blocker. It always runs from the clock, never
    /// from a daily limit: picking any choice clears a limit the old editor
    /// may have set.
    mutating func apply(_ when: BlockWhen, hours: BlockHours) {
        dailyLimitMinutes = nil
        untilSession = when == .custom && hours.untilMeditate ? true : nil
        switch when {
        case .allDay:
            window = .allDay
            weekdays = Set(1...7)
        case .mornings:
            let p = Blocker.preset(.mindfulMorning)
            window = p.window
            weekdays = p.weekdays
        case .weekdays:
            let p = Blocker.preset(.focusHours)
            window = p.window
            weekdays = p.weekdays
        case .nightOwl:
            window = BlockWhen.nightOwlWindow
            weekdays = Set(1...7)
        case .custom:
            // Midnight to midnight is the whole day: saved as one, so it
            // reads back as "All day" on the days picked, as it was set.
            if !hours.untilMeditate && hours.start == 0 && hours.effectiveEnd == 24 * 60 {
                window = .allDay
            } else {
                window = .hours(start: hours.start, end: hours.effectiveEnd)
            }
            weekdays = hours.days
        }
    }
}

/// The five choices as the onboarding's white plates, and under Custom the
/// hours and the days.
struct BlockWhenPicker: View {
    @Binding var choice: BlockWhen
    @Binding var hours: BlockHours

    var body: some View {
        VStack(spacing: 10) {
            ForEach(BlockWhen.allCases, id: \.self) { option in
                OnboardingOption(label: option.title, icon: option.icon,
                                 selected: choice == option) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { choice = option }
                }
            }
            if choice == .custom {
                customHours
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Custom reads as a sentence (Aziz, 2026-09-28): "From [time] until
    /// [time]", or "From [time] until I meditate".
    private var customHours: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                endChoice("Until a time", on: !hours.untilMeditate) { hours.untilMeditate = false }
                endChoice("Until I meditate", on: hours.untilMeditate) { hours.untilMeditate = true }
            }
            HStack(alignment: .top, spacing: 12) {
                clock("From", minutes: $hours.start, isEnd: false)
                if hours.untilMeditate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Until")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                        Label("I meditate", systemImage: "figure.mind.and.body")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.vertical, 7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    clock("Until", minutes: $hours.end, isEnd: true)
                }
            }
            if hours.untilMeditate {
                Text("Held from then until you finish a session, or midnight at the latest.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(DayChoice.allCases, id: \.self) { d in
                    let on = hours.days == d.days
                    Button { hours.days = d.days } label: {
                        Text(d.label)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(on ? AppColor.textOnAccent : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(on ? AppColor.accentGold : AppColor.textSecondary.opacity(0.10),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let problem = problem {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.streakBlushText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// What Screen Time would refuse, said here rather than after Save.
    private var problem: String? {
        var probe = Blocker.preset(.custom)
        probe.window = .hours(start: hours.start, end: hours.effectiveEnd)
        return probe.windowProblem
    }

    private func endChoice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(on ? AppColor.textOnAccent : AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? AppColor.accentGold : AppColor.textSecondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func clock(_ title: String, minutes: Binding<Int>, isEnd: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
            DatePicker(title, selection: Binding(
                get: {
                    // By clock time, not minutes added to midnight, so a day
                    // that changes the clocks still reads 8:00 as 8:00.
                    let m = minutes.wrappedValue % 1440
                    return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    // Midnight as an end means the end of the day.
                    minutes.wrappedValue = isEnd && value == 0 ? 1440 : value
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(AppColor.accentGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum DayChoice: CaseIterable {
        case everyDay, weekdays, weekends
        var label: String {
            switch self {
            case .everyDay: return "Every day"
            case .weekdays: return "Weekdays"
            case .weekends: return "Weekends"
            }
        }
        var days: Set<Int> {
            switch self {
            case .everyDay: return Set(1...7)
            case .weekdays: return Set(2...6)
            case .weekends: return [1, 7]
            }
        }
    }
}
