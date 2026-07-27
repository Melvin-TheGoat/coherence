import SwiftUI
import SwiftData

/// Home. Greets the user, shows their practice at a glance (streak / totals),
/// a prominent Begin CTA, and recent sessions. Navigation to setup, results,
/// calendar, history, and settings.
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var users: [User]
    @Query private var reflections: [SessionReflection]

    @State private var showSetup = false
    @State private var showCalendar = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var openSession: SessionRef?
    #if DEBUG
    @State private var showBreathingPreview =
        ProcessInfo.processInfo.environment["PREVIEW_BREATHING"] == "1"
    #endif

    private struct SessionRef: Identifiable { let id: UUID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCard
                Button("Begin session") { showSetup = true }
                    .buttonStyle(PrimaryButtonStyle())
                if coordinator.lastSessionID != nil {
                    lastSessionCard
                }
                recent
                calendarCard
                #if DEBUG
                Button("Preview breathing screen") { showBreathingPreview = true }
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                #endif
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        #if DEBUG
        .fullScreenCover(isPresented: $showBreathingPreview) {
            SessionActiveView(bellyBreathing: true) { showBreathingPreview = false }
        }
        .onAppear {
            if let name = ProcessInfo.processInfo.environment["DEMO_NAME"] {
                let u = SessionStore.currentUser(in: context)
                if (u.displayName ?? "").isEmpty { u.displayName = name; try? context.save() }
            }
            if ProcessInfo.processInfo.environment["PREVIEW_RESULTS"] == "1", openSession == nil {
                openSession = SessionRef(id: DemoData.seedResults(in: context))
            }
        }
        #endif
        .sheet(isPresented: $showSetup) { SessionSetupView() }
        .sheet(isPresented: $showCalendar) { SessionHistoryView() }
        .sheet(isPresented: $showHistory) { NavigationStack { AllSessionsView() } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $openSession) { ref in SessionResultsView(sessionID: ref.id) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                LogoMark()
                    .frame(width: 48, height: 48)
                Spacer()
                HStack(spacing: 18) {
                    iconButton("calendar") { showCalendar = true }
                    iconButton("gearshape") { showSettings = true }
                }
            }
            Text(greeting)
                .font(AppFont.title)
                .italic()
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Your practice")
            HStack(spacing: 8) {
                StatTile(value: "\(streak.current)", label: "Day streak")
                divider
                StatTile(value: "\(streak.longest)", label: "Longest")
                divider
                StatTile(value: "\(sessions.count)", label: "Sessions")
            }
        }
        .card()
    }

    private var divider: some View {
        Rectangle().fill(AppColor.textSecondary.opacity(0.15)).frame(width: 1, height: 44)
    }

    private var lastSessionCard: some View {
        Button {
            if let id = coordinator.lastSessionID { openSession = SessionRef(id: id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last session saved").font(AppFont.callout.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Tap to see your evidence").font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppColor.accentGold)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Recent")
                Spacer()
                if !sessions.isEmpty {
                    Button("See all") { showHistory = true }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGold)
                }
            }
            if sessions.isEmpty {
                Text("No sessions yet — begin your first.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                ForEach(sessions.prefix(3)) { session in
                    Button { openSession = SessionRef(id: session.id) } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 14) {
            Image(systemName: session.bellyBreathing ? "wind" : "leaf")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColor.accentGold)
                .frame(width: 34, height: 34)
                .background(AppColor.accentGold.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.callout.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                Text("\(durationText(session.durationSec))\(session.bellyBreathing ? " · Belly breathing" : "")")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if let rating = ratingBySession[session.id] { RatingChip(rating: rating) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppColor.textSecondary)
        }
        .card(padding: 14)
    }

    private var ratingBySession: [UUID: Int] {
        SessionListSupport.ratingMap(reflections)
    }

    // MARK: - Calendar widget

    private var calendarCard: some View {
        let practiced = SessionCalendar.practicedDays(from: sessions.map(\.startedAt))
        let today = Date()
        let grid = SessionCalendar.monthGrid(containing: today)
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: today.formatted(.dateTime.month(.wide).year()))
                Spacer()
                Button("Open") { showCalendar = true }
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accentGold)
            }
            HStack(spacing: 0) {
                ForEach(weekdayInitials, id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 5) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { day in
                            dayCell(day,
                                    practiced: practiced.contains(cal.startOfDay(for: day)),
                                    inMonth: SessionCalendar.isSameMonth(day, as: today),
                                    isToday: cal.isDateInToday(day))
                        }
                    }
                }
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { showCalendar = true }
    }

    private func dayCell(_ day: Date, practiced: Bool, inMonth: Bool, isToday: Bool) -> some View {
        let n = Calendar.current.component(.day, from: day)
        return ZStack {
            if practiced {
                Circle().fill(AppColor.accentGold).frame(width: 30, height: 30)
            } else if isToday {
                Circle().stroke(AppColor.accentGold.opacity(0.6), lineWidth: 1).frame(width: 30, height: 30)
            }
            Text("\(n)")
                .font(.caption2.weight(practiced ? .bold : .regular))
                .foregroundStyle(practiced ? AppColor.textOnAccent
                                 : (inMonth ? AppColor.textPrimary : AppColor.textSecondary.opacity(0.35)))
        }
        .frame(maxWidth: .infinity, minHeight: 34)
    }

    private var weekdayInitials: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols                 // ["S","M",...] Sunday-first
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Helpers

    private var greeting: String {
        let base: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        case 17..<22: base = "Good evening"
        default: base = "Good night"
        }
        return firstName.map { "\(base), \($0)" } ?? base
    }

    private var firstName: String? {
        let name = users.first { $0.appleUserID != "" && $0.deletedAt == nil }?.displayName
            ?? users.first?.displayName
        guard let name, !name.isEmpty else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }

    private func durationText(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60) min" : "\(sec) sec"
    }
}
