import SwiftUI
import SwiftData
import Charts

/// The app after onboarding: five tabs on a bottom bar (Melvin, 2026-09-12,
/// "the layout most apps use, so people open it and instantly understand").
/// Home is the streak, the proof curve and this month's calendar; Guide is
/// the how-to; the raised gold plus starts a session; Friends is the feed
/// of what friends posted; Profile is the person, their stats, awards and
/// full log.
///
/// This view still owns every app-wide modal (the live session cover, a start
/// failure, an award unlock, the setup sheet, results, settings), exactly as
/// it did when it was only Home. Tabs are content; the modals are the app.
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var users: [User]
    @Query private var reflections: [SessionReflection]
    @Query private var allStats: [MeditationStats]
    @Query private var prefsRows: [Preferences]
    @EnvironmentObject private var community: CommunityModel

    @State private var tab: MainTab = .home
    /// A day tapped on Home's calendar. Profile opens with its log filtered
    /// to it, which is what the old month picker was for.
    @State private var profileDay: Date?

    /// ONE sheet presenter for the whole screen. Stacking several
    /// `.sheet` modifiers on the same view silently breaks all but one of
    /// them (verified on-device: only Begin opened) — so every modal routes
    /// through this enum instead.
    @State private var sheet: HomeSheet?
    /// Presented once the current sheet is down. Setting `sheet` while one is
    /// already up drops the new one on the floor.
    @State private var pendingSheet: HomeSheet?
    /// Awards earned but not yet celebrated, oldest first. Announced one at a
    /// time: two unlock screens racing each other would cheapen both.
    @State private var unlockQueue: [AwardEngine.Earned] = []
    #if DEBUG
    @State private var showBreathingPreview =
        ProcessInfo.processInfo.environment["PREVIEW_BREATHING"] == "1"
    #endif

    private enum HomeSheet: Identifiable {
        case setup, settings
        case results(UUID)
        /// Save session (Friends): opens when a live session lands, then
        /// chains into its results.
        case save(UUID)

        var id: String {
            switch self {
            case .setup: return "setup"
            case .settings: return "settings"
            case .results(let id): return "results-\(id)"
            case .save(let id): return "save-\(id)"
            }
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .home:
                homeTab
            case .guide:
                GuideView(embedded: true) { sheet = .setup }
                    .onAppear { Analytics.track(.guideOpened) }
            case .friends:
                if FeatureFlags.friends { FriendsTab() } else { SearchTab() }
            case .profile:
                ProfileTab(selectedDay: $profileDay) { sheet = .settings }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                // The Watch announced End; the payload is seconds behind. The
                // live screen is already down — this is the handoff's face.
                if coordinator.receivingFromWatch {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small).tint(AppColor.calmAccent)
                        Text("Receiving from your Watch…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(AppColor.backgroundSecondary.opacity(0.92), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                MainTabBar(selection: $tab) { sheet = .setup }
            }
            .animation(.easeOut(duration: 0.25), value: coordinator.receivingFromWatch)
        }
        .screenBackground()
        .fullScreenCover(item: Binding(
            get: { unlockQueue.first },
            set: { _ in })) { item in
            AwardUnlockView(item: item) {
                AwardsInbox.markAnnounced(item.award.id)
                unlockQueue.removeFirst()
            }
        }
        .onAppear(perform: refreshAwards)
        .onChange(of: sessions.count) { _, _ in refreshAwards() }
        .modifier(FriendsHooks(community: community,
                               users: users,
                               sessionActive: coordinator.active != nil,
                               lastSessionID: coordinator.lastSessionID) { id in
            if sheet == nil { sheet = .save(id) } else { pendingSheet = .save(id) }
        })
        .onChange(of: prefsRows.first?.evidenceGrantSince) { _, _ in refreshAwards() }
        #if DEBUG
        .fullScreenCover(isPresented: $showBreathingPreview) {
            SessionActiveView(startedAt: Date().addingTimeInterval(-90),
                              plannedDurationSec: 600,
                              planChip: "10 min") { showBreathingPreview = false }
        }
        .onAppear {
            if let name = ProcessInfo.processInfo.environment["DEMO_NAME"] {
                let u = SessionStore.currentUser(in: context)
                if (u.displayName ?? "").isEmpty { u.displayName = name; try? context.save() }
            }
            // Store screenshots of the Profile tab: the handle is optional in
            // onboarding, so a seeded profile has none unless asked for here.
            if let handle = ProcessInfo.processInfo.environment["DEMO_USERNAME"] {
                let u = SessionStore.currentUser(in: context)
                if (u.username ?? "").isEmpty { u.username = Username.normalize(handle); try? context.save() }
            }
            if ProcessInfo.processInfo.environment["PREVIEW_BLOCKED"] == "1" {
                coordinator.startFailure = .heartRateUnavailable
            }
            if ProcessInfo.processInfo.environment["PREVIEW_HISTORY"] == "1" {
                DemoData.seedHistory(in: context)
            }
            if ProcessInfo.processInfo.environment["PREVIEW_NOISY"] == "1" {
                DemoData.seedNoisyBad(in: context)
            }
            if ProcessInfo.processInfo.environment["PREVIEW_RESULTS"] == "1", sheet == nil {
                sheet = .results(DemoData.seedResults(in: context))
            }
            if ProcessInfo.processInfo.environment["PREVIEW_SAVE"] == "1", sheet == nil {
                sheet = .save(DemoData.seedResults(in: context))
            }
            if let which = ProcessInfo.processInfo.environment["PREVIEW_TAB"] {
                switch which {
                case "guide": tab = .guide
                case "friends", "search": tab = .friends
                case "profile": tab = .profile
                default: tab = .home
                }
            }
        }
        #endif
        // A session is running on the Watch — take over the phone for every mode.
        .fullScreenCover(item: Binding(get: { coordinator.active }, set: { _ in })) { session in
            SessionActiveView(startedAt: session.startedAt,
                              plannedDurationSec: session.plannedDurationSec,
                              planChip: planChip(session)) {
                coordinator.endActiveSession()
            }
        }
        // The Watch refused to start — explain what to fix before anything else.
        .fullScreenCover(item: $coordinator.startFailure) { failure in
            PermissionBlockedView(failure: failure) { coordinator.startFailure = nil }
        }
        // Full-screen, not a sheet: a sheet keeps the presenting screen visible
        // in the strip above it, and on a dark theme that strip reads as a
        // rendering glitch (Melvin hit it while screenshotting). Every
        // destination carries its own Done or Cancel, so nothing needs the
        // swipe-down affordance.
        .fullScreenCover(item: $sheet, onDismiss: {
            if let next = pendingSheet { pendingSheet = nil; sheet = next }
        }) { which in
            switch which {
            case .setup:
                SessionSetupView()
            case .settings:
                SettingsView()
            case .results(let id):
                SessionResultsView(sessionID: id)
            case .save(let id):
                SaveSessionView(sessionID: id, mode: .new) {
                    pendingSheet = .results(id)
                    sheet = nil
                }
            }
        }
    }

    // MARK: - Home

    /// Top to bottom it answers the questions in the order you ask them: am I
    /// keeping my promise (streak headline + nudge), is it working (the gold
    /// proof curve), what has this month looked like, what did the last few
    /// sessions say. Starting one is the plus on the bar.
    private var homeTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                streakBlock
                    .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.streak: $0] }
                calendarCard
                proofSection
                #if DEBUG
                debugButtons
                #endif
            }
            .padding(AppMetrics.screenPadding)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Awards

    /// Derived from history on every check, so nothing needs backfilling: a
    /// user with months of sessions simply has the awards those sessions earned.
    private func refreshAwards() {
        let scores = Dictionary(allStats.compactMap { st -> (UUID, Double)? in
            guard let id = st.sessionID, let s = st.overallScore else { return nil }
            return (id, s)
        }, uniquingKeysWith: { a, _ in a })

        let earned = AwardEngine.evaluate(
            sessions: sessions.map {
                .init(startedAt: $0.startedAt,
                      durationSec: $0.durationSec,
                      overallScore: scores[$0.id])
            },
            accountCreatedAt: users.first?.createdAt,
            friendBroughtAt: prefsRows.first?.evidenceGrantSince)
            .filter { !FeatureFlags.hiddenAwardIDs.contains($0.award.id) }

        // First run swallows everything already earned. Melvin and Aziz have
        // months of history and would otherwise meet a dozen unlock screens in
        // a row, which would cheapen the one that matters.
        AwardsInbox.seedIfNeeded(with: earned)
        unlockQueue = AwardsInbox.pending(from: earned)
        for award in unlockQueue { Analytics.track(.awardUnlocked(id: award.id)) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogoMark()
                .frame(width: 44, height: 44)
            Text(greeting)
                .font(AppFont.title)
                .italic()
                .foregroundStyle(AppColor.textPrimary)
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
            // The sparkline is FREE (Aziz, 2026-08-24, reversing the first
            // build). It draws overall scores, and every history row below it
            // already shows each session's score to a free user, so locking
            // the line was locking arithmetic on free numbers, not evidence.
            // The rule survives intact: the score is free, the measurements
            // behind it are not.
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
            Text(value).font(AppFont.caption.weight(.bold)).foregroundStyle(AppColor.accentGoldText)
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
            return "Nothing measured today. Your \(streak.current)-day streak is on the line."
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
                .foregroundStyle(AppColor.accentGoldText)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            if i == scores.count - 1 {
                PointMark(x: .value("session", i), y: .value("score", score))
                    .foregroundStyle(AppColor.accentGoldText)
                    .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }

    // MARK: - Calendar

    /// This month only. Tapping a dotted day opens Profile with the log
    /// filtered to it; the month picker that used to live on Journey is gone
    /// because this card took its job.
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
            MonthCalendar(monthAnchor: today, practiced: practiced) { day in
                profileDay = day
                tab = .profile
            }
        }
        .card(padding: 14)
    }

    private func practicedThisMonth(_ practiced: Set<Date>) -> Int {
        let cal = Calendar.current
        return practiced.filter { cal.isDate($0, equalTo: Date(), toGranularity: .month) }.count
    }

    // MARK: - The proof

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: "Recent")
                Spacer()
                if !sessions.isEmpty {
                    Button { profileDay = nil; tab = .profile } label: {
                        Text("See all")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            if sessions.isEmpty {
                Text("No sessions yet. Your evidence starts with the first one.")
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
                        .buttonStyle(CardButtonStyle())
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
        }
    }
    #endif

    // MARK: - Helpers

    /// "Belly · 10 min · Deep Meditation" for the mid-session plan chip.
    private func planChip(_ session: SessionCoordinator.ActiveSession) -> String {
        var parts: [String] = []
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


/// Everything Friends adds to the app's root, in one modifier so the root
/// view's chain stays small enough to type-check, and so a switched-off
/// Friends is one `guard` away from nothing.
private struct FriendsHooks: ViewModifier {
    @ObservedObject var community: CommunityModel
    let users: [User]
    let sessionActive: Bool
    let lastSessionID: UUID?
    let openSave: (UUID) -> Void

    func body(content: Content) -> some View {
        if FeatureFlags.friends {
            content
                // The invite reward landing: a brought friend sat once.
                .sheet(item: $community.rewardNews) { news in
                    InviteRewardSheet(news: news).presentationDetents([.medium])
                }
                // People who finished onboarding before Friends: one required
                // prompt to create a profile, whenever iCloud says they have none.
                .fullScreenCover(isPresented: Binding(
                    get: { community.phase == .needsUsername && !sessionActive },
                    set: { _ in })) {
                    FriendsIntroView(model: community,
                                     suggested: users.first?.username ?? "",
                                     nickname: users.first?.displayName ?? "") {}
                }
                // Strava's flow: the session ends on Save session, then results.
                .onChange(of: lastSessionID) { _, id in
                    if let id { openSave(id) }
                }
        } else {
            content
        }
    }
}
