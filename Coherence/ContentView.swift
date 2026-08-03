import SwiftUI
import SwiftData
import Charts

/// Home — the hybrid "proof + practice" screen (design review, 2026-08).
/// Top to bottom it answers the three questions in the order you ask them:
/// am I keeping my promise (streak headline + nudge), is it working (the gold
/// proof curve + evidence rows), what's next (Begin, pinned at the thumb).
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var users: [User]
    @Query private var reflections: [SessionReflection]
    @Query private var allStats: [MeditationStats]

    /// ONE sheet presenter for the whole screen. Stacking several
    /// `.sheet` modifiers on the same view silently breaks all but one of
    /// them (verified on-device: only Begin opened) — so every modal routes
    /// through this enum instead.
    @State private var sheet: HomeSheet?
    /// Set while the AFTER coherence read is up, so dismissing it opens results.
    @State private var resultsAfterMeasure: UUID?
    #if DEBUG
    @State private var showBreathingPreview =
        ProcessInfo.processInfo.environment["PREVIEW_BREATHING"] == "1"
    #endif

    private enum HomeSheet: Identifiable {
        case setup, journey, settings
        case results(UUID)
        case postMeasure(UUID)
        #if DEBUG
        case coherenceTest
        #endif

        var id: String {
            switch self {
            case .setup: return "setup"
            case .journey: return "journey"
            case .settings: return "settings"
            case .results(let id): return "results-\(id)"
            case .postMeasure(let id): return "post-\(id)"
            #if DEBUG
            case .coherenceTest: return "coherence-test"
            #endif
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                streakBlock
                calendarCard
                proofSection
                #if DEBUG
                debugButtons
                #endif
            }
            .padding(AppMetrics.screenPadding)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Begin session") { sheet = .setup }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(
                    LinearGradient(colors: [AppColor.backgroundPrimary.opacity(0),
                                            AppColor.backgroundPrimary],
                                   startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
                )
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
            if ProcessInfo.processInfo.environment["PREVIEW_BLOCKED"] == "1" {
                coordinator.startFailure = .heartRateUnavailable
            }
            if ProcessInfo.processInfo.environment["PREVIEW_HISTORY"] == "1" {
                DemoData.seedHistory(in: context)
            }
            if ProcessInfo.processInfo.environment["PREVIEW_RESULTS"] == "1", sheet == nil {
                sheet = .results(DemoData.seedResults(in: context))
            }
        }
        #endif
        // A session is running on the Watch — take over the phone for every mode.
        .fullScreenCover(item: Binding(get: { coordinator.active }, set: { _ in })) { session in
            SessionActiveView(bellyBreathing: session.bellyBreathing,
                              startedAt: session.startedAt,
                              plannedDurationSec: session.plannedDurationSec,
                              planChip: planChip(session)) {
                coordinator.endActiveSession()
            }
        }
        // The Watch refused to start — explain what to fix before anything else.
        .fullScreenCover(item: $coordinator.startFailure) { failure in
            PermissionBlockedView(failure: failure) { coordinator.startFailure = nil }
        }
        // Session over + coherence check opted in → the AFTER read, then results.
        .onChange(of: coordinator.postMeasure?.id) { _, id in
            guard let id else { return }
            resultsAfterMeasure = id
            sheet = .postMeasure(id)
            coordinator.postMeasure = nil     // consumed; the sheet owns it now
        }
        .sheet(item: $sheet, onDismiss: {
            // The AFTER read just closed (completed or skipped) — show the evidence.
            if let id = resultsAfterMeasure {
                resultsAfterMeasure = nil
                sheet = .results(id)
            }
        }) { which in
            switch which {
            case .setup:
                SessionSetupView()
            case .journey:
                JourneyView()
            case .settings:
                SettingsView()
            case .results(let id):
                SessionResultsView(sessionID: id)
            case .postMeasure(let id):
                CoherenceMeasureView(label: "After") { snap in
                    SessionStore.attachPostCoherence(sessionID: id, snapshot: snap, in: context)
                }
            #if DEBUG
            case .coherenceTest:
                CoherenceMeasureView()
            #endif
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                LogoMark()
                    .frame(width: 44, height: 44)
                Spacer()
                HStack(spacing: 18) {
                    iconButton("clock.arrow.circlepath") { sheet = .journey }
                    iconButton("gearshape") { sheet = .settings }
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
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Streak headline + proof curve

    private var streakBlock: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let scores = sparkScores
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Day streak")
            HStack(alignment: .lastTextBaseline) {
                Text("\(streak.current)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    statLine(value: "\(streak.longest)", label: "longest")
                    statLine(value: "\(sessions.count)", label: "sessions")
                }
            }
            if let nudge {
                Text(nudge)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.calmAccent)
            }
            if scores.count >= 2 {
                sparkline(scores)
                    .frame(height: 46)
                    .padding(.top, 6)
                Text("Practice score · last \(scores.count) sessions")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else if sessions.isEmpty {
                Text("Your first session draws the first point of your proof curve.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 6)
            }
        }
    }

    private func statLine(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            Text(value).font(AppFont.caption.weight(.bold)).foregroundStyle(AppColor.accentGold)
                .monospacedDigit()
        }
    }

    /// Overall scores of the most recent sessions, oldest → newest.
    private var sparkScores: [Double] {
        let map = SessionListSupport.scoreMap(allStats)
        return sessions.prefix(11).compactMap { map[$0.id] }.reversed()
    }

    /// The "streak on the line" nudge — only on days you haven't practiced yet.
    private var nudge: String? {
        let cal = Calendar.current
        let practicedToday = sessions.contains { cal.isDateInToday($0.startedAt) }
        guard !practicedToday else { return nil }
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        if streak.current > 1 {
            return "Nothing measured today — a \(streak.current)-day streak is on the line"
        }
        return sessions.isEmpty ? nil : "Nothing measured today"
    }

    private func sparkline(_ scores: [Double]) -> some View {
        Chart(Array(scores.enumerated()), id: \.offset) { i, score in
            AreaMark(x: .value("session", i), y: .value("score", score))
                .foregroundStyle(LinearGradient(colors: [AppColor.accentGold.opacity(0.22),
                                                         AppColor.accentGold.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("session", i), y: .value("score", score))
                .foregroundStyle(AppColor.accentGold)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            if i == scores.count - 1 {
                PointMark(x: .value("session", i), y: .value("score", score))
                    .foregroundStyle(AppColor.accentGold)
                    .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        let practiced = SessionCalendar.practicedDays(from: sessions.map(\.startedAt))
        let today = Date()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: today.formatted(.dateTime.month(.wide)))
                Spacer()
                Text("\(practicedThisMonth(practiced)) practiced days")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            MonthCalendar(monthAnchor: today, practiced: practiced) { _ in
                sheet = .journey
            }
        }
        .card(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture { sheet = .journey }
    }

    private func practicedThisMonth(_ practiced: Set<Date>) -> Int {
        let cal = Calendar.current
        return practiced.filter { cal.isDate($0, equalTo: Date(), toGranularity: .month) }.count
    }

    // MARK: - The proof

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: "The proof")
                Spacer()
                if !sessions.isEmpty {
                    Button("See all") { sheet = .journey }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGold)
                }
            }
            if sessions.isEmpty {
                Text("No sessions yet — your evidence starts with the first one.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                let scores = SessionListSupport.scoreMap(allStats)
                let stats = SessionListSupport.statsMap(allStats)
                let ratings = SessionListSupport.ratingMap(reflections)
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { i, session in
                        if i > 0 { Divider().overlay(AppColor.textSecondary.opacity(0.12)) }
                        Button { sheet = .results(session.id) } label: {
                            EvidenceRow(session: session,
                                        score: scores[session.id],
                                        subtitle: SessionListSupport.metricLine(session, stats: stats[session.id]),
                                        rating: ratings[session.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
            }
        }
    }

    // MARK: - DEBUG

    #if DEBUG
    private var debugButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Preview breathing screen") { showBreathingPreview = true }
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            Button("Test coherence measurement") { sheet = .coherenceTest }
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
    }
    #endif

    // MARK: - Helpers

    /// "Belly · 10 min · Deep Meditation" for the mid-session plan chip.
    private func planChip(_ session: SessionCoordinator.ActiveSession) -> String {
        var parts: [String] = []
        if session.bellyBreathing { parts.append("Belly") }
        if let planned = session.plannedDurationSec { parts.append("\(planned / 60) min") }
        else { parts.append("Open") }
        if let title = session.soundTitle { parts.append(title) }
        return parts.joined(separator: " · ")
    }

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
}
