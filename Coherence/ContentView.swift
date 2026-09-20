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
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var users: [User]
    @Query private var reflections: [SessionReflection]
    @Query private var allStats: [MeditationStats]
    @Query private var prefsRows: [Preferences]
    @Query private var photos: [SessionPhoto]
    @EnvironmentObject private var community: CommunityModel
    @EnvironmentObject private var store: Store

    @State private var tab: MainTab = .home
    /// A day tapped on Home's calendar. Profile opens with its log filtered
    /// to it, which is what the old month picker was for.
    @State private var profileDay: Date?
    /// A recent-session row awaiting the delete confirmation.
    @State private var pendingDelete: UUID?

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
    /// A session that finished while the app was away and still owes the
    /// person a Save session screen (`PendingSave`). Recomputed on every
    /// return to the foreground, because that is the moment they picked the
    /// phone up after sitting.
    @State private var resumeSave: UUID?
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
        /// A session the Watch ended without a score (too short, unreadable).
        case discarded(SessionCoordinator.Discard)
        /// The offer, after the first meditation (2026-09-15). Opens when a
        /// free user leaves the first results screen.
        case paywall

        var id: String {
            switch self {
            case .setup: return "setup"
            case .settings: return "settings"
            case .results(let id): return "results-\(id)"
            case .save(let id): return "save-\(id)"
            case .discarded(let d): return "discarded-\(d.id)"
            case .paywall: return "paywall"
            }
        }
    }

    /// The plan the post-session paywall preselects. Monthly, since the
    /// 7-day trial renews into it.
    @State private var paywallPlan: SubscriptionPlan = .monthly
    @ObservedObject private var firstOffer = FirstSessionOffer.shared

    /// One cover at a time; anything asked for while one is up waits its turn.
    private func present(_ next: HomeSheet) {
        if sheet == nil { sheet = next } else { pendingSheet = next }
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
        .modifier(DiscardHook(discard: coordinator.lastDiscard,
                              sessionActive: coordinator.active != nil) { d in
            if sheet == nil { sheet = .discarded(d) } else { pendingSheet = .discarded(d) }
        })
        .firstSessionHooks(offer: firstOffer, paid: store.entitlements.paid,
                           onOpenSetup: { present(.setup) },
                           onPaywallDue: { present(.paywall) })
        .modifier(FriendsHooks(community: community,
                               users: users,
                               sessionActive: coordinator.active != nil,
                               awardShowing: !unlockQueue.isEmpty,
                               lastSessionID: coordinator.lastSessionID,
                               resumeSessionID: resumeSave) { id in
            if sheet == nil { sheet = .save(id) } else { pendingSheet = .save(id) }
        })
        // Picking the phone up after a sit IS the moment to grade it, and by
        // then the app has usually been suspended or killed, so nothing is
        // left in memory to act on. Read the waiting session off disk instead.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { readPendingSave() }
        }
        .onAppear { readPendingSave() }
        .onChange(of: prefsRows.compactMap(\.evidenceGrantSince).min()) { _, _ in refreshAwards() }
        #if DEBUG
        .fullScreenCover(isPresented: $showBreathingPreview) {
            SessionActiveView(startedAt: Date().addingTimeInterval(-90),
                              plannedDurationSec: 600,
                              planChip: "10 min") { showBreathingPreview = false }
        }
        .onAppear(perform: debugPreviewHooks)
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
                    PendingSave.clear()
                    resumeSave = nil
                    pendingSheet = .results(id)
                    sheet = nil
                }
            case .discarded(let discard):
                SessionTooShortView(discard: discard,
                                    onStartAgain: { pendingSheet = .setup; sheet = nil },
                                    onDone: { sheet = nil })
            case .paywall:
                // The same screen and ladder onboarding used to end on. Both
                // exits (bought, or declined down to free) close the grant:
                // from here the free tier applies, including to the session
                // they just left.
                PaywallScreen(placement: "first_session", plan: $paywallPlan) { _ in
                    firstOffer.markShown()
                    sheet = nil
                }
            }
        }
    }

    #if DEBUG
    /// The simulator review hooks (`PREVIEW_*`, `DEMO_*`). A function rather
    /// than an inline closure: as one expression on the body's chain it sent
    /// the type checker over its time limit (2026-09-15).
    private func debugPreviewHooks() {
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
            if let secs = ProcessInfo.processInfo.environment["PREVIEW_TOO_SHORT"].flatMap(Int.init), sheet == nil {
                sheet = .discarded(.init(id: UUID(), durationSec: secs))
            }
            if ProcessInfo.processInfo.environment["PREVIEW_SAVE"] == "1", sheet == nil {
                sheet = .save(DemoData.seedResults(in: context))
            }
            if ProcessInfo.processInfo.environment["PREVIEW_FIRST_PAYWALL"] == "1", sheet == nil {
                sheet = .paywall
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

    // MARK: - Home

    /// Top to bottom it answers the questions in the order you ask them: am I
    /// keeping my promise (streak headline + nudge), is it working (the gold
    /// proof curve), what has this month looked like, what did the last few
    /// sessions say. Starting one is the plus on the bar.
    private var homeTab: some View {
        // The scroll view runs up under the status bar and the scene is
        // padded down by the inset, so the sky is the first thing on the
        // screen. A background inside a scroll view cannot escape the safe
        // area on its own (tried first: the band behind the clock stayed
        // paper and the sky began under it as a hard line).
        GeometryReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ottoScene(topInset: proxy.safeAreaInsets.top)
                streakPill
                    .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.streak: $0] }
                VStack(alignment: .leading, spacing: 20) {
                    if let nudge {
                        Text(nudge)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.calmAccent)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    calendarCard
                    proofSection
                    #if DEBUG
                    debugButtons
                    #endif
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - The scene

    /// Otto, under a sky, above a horizon (2026-09-19, Aziz: Otto replaces the
    /// flower and becomes the main thing about the app).
    ///
    /// The reference is Finch, the only app in this category to have made a
    /// mascot work at scale, and the pattern under it is not "put a mascot on
    /// the screen". **The mascot sits somewhere.** Finch's bird stands on
    /// grass under a sky, and the interface floats around him. A character on
    /// a flat card is a sticker; a character on a horizon is somebody's
    /// morning. One gradient and one hairline buy the whole difference.
    ///
    /// The 808 mark is gone from here. It does not disappear from the product,
    /// it stops being the greeting: a mark identifies a company and a face
    /// greets a person, and this is the screen somebody opens before they have
    /// woken up properly.
    /// `topInset` is the status bar's height, padded INSIDE this view so the
    /// sky behind it covers that band too. Padding it from outside left the
    /// band above the gradient, which is the bug this fixes.
    private func ottoScene(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(DisplayFont.display(24, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            OttoMark(size: 168, pose: .meditating)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    // What stops him floating. Fades at both ends so it reads
                    // as ground rather than as a rule under a heading.
                    LinearGradient(colors: [.clear, AppColor.textPrimary.opacity(0.10),
                                            AppColor.textPrimary.opacity(0.10), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                        .padding(.horizontal, 26)
                }
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 8 + topInset)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Under the status bar too: `homeTab` lets the scroll view ignore
            // the top safe area and pads the scene by the inset (Melvin,
            // 2026-09-20: "the top of the home page is cut off, the color
            // suddenly cuts into a whiter color").
            LinearGradient(colors: [AppColor.sky, AppColor.backgroundPrimary],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 38,
                                                  bottomTrailingRadius: 38,
                                                  style: .continuous))
        }
    }

    /// The streak, as a capsule straddling the bottom edge of the scene.
    ///
    /// It used to be a 54pt number under a heading, which made it the loudest
    /// thing on Home. It is not what the app is for. Sitting on the seam it
    /// joins the scene to the content below it and gets to be small, and best
    /// and total ride along behind a divider instead of stacking in a corner.
    private var streakPill: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        return HStack(spacing: 9) {
            Text("\(streak.current)")
                .font(DisplayFont.display(25, .heavy))
                .foregroundStyle(AppColor.streakBlushText)
                .monospacedDigit()
            // "day streak", the words it had before the revamp. "mornings"
            // counted days as mornings, which is not what a streak is and
            // read as nonsense at 0 (Melvin, 2026-09-20).
            Text("day streak")
                .font(DisplayFont.display(16))
                .foregroundStyle(AppColor.streakBlushText)
            Rectangle().fill(AppColor.hairline).frame(width: 1, height: 18)
            Text("best \(streak.longest)  ·  \(sessions.count) sessions")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background {
            Capsule()
                .fill(AppColor.backgroundSecondary)
                .shadow(color: AppColor.hairline, radius: 0, y: 3)
        }
        .frame(maxWidth: .infinity)
        .offset(y: -21)
        .padding(.bottom, -21)
    }

    // MARK: - Awards

    /// Derived from history on every check, so nothing needs backfilling: a
    /// user with months of sessions simply has the awards those sessions earned.
    /// The session waiting to be graded, if it is still there. A session can
    /// be deleted from its results screen, so the stored id is checked against
    /// storage before a sheet is opened on it; a dangling id clears itself.
    private func readPendingSave() {
        guard FeatureFlags.friends, let id = PendingSave.read() else { resumeSave = nil; return }
        guard sessions.contains(where: { $0.id == id }) else {
            PendingSave.clear()
            resumeSave = nil
            return
        }
        resumeSave = id
    }

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
            friendBroughtAt: prefsRows.compactMap(\.evidenceGrantSince).min())
            .filter { !FeatureFlags.hiddenAwardIDs.contains($0.award.id) }

        // First run swallows everything already earned. Melvin and Aziz have
        // months of history and would otherwise meet a dozen unlock screens in
        // a row, which would cheapen the one that matters.
        AwardsInbox.seedIfNeeded(with: earned)
        unlockQueue = AwardsInbox.pending(from: earned)
        for award in unlockQueue { Analytics.track(.awardUnlocked(id: award.id)) }
    }

    // MARK: - Header
    //
    // There isn't one any more. The greeting and the 808 mark used to stack
    // above the streak; the greeting moved into the scene and the mark left
    // Home altogether (2026-09-19). A mark identifies a company and a face
    // greets a person, and this is the screen somebody opens before they are
    // properly awake. The flower is gone from the product entirely as of
    // 2026-09-19: Otto's head signs onboarding, the share card, the Watch and
    // the one award whose face is the mark, and `LogoMark` is deleted.

    // MARK: - Streak

    private func statLine(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            Text(value).font(AppFont.caption.weight(.bold)).foregroundStyle(AppColor.accentGoldText)
                .monospacedDigit()
        }
    }

    // The practice sparkline lived here and is gone with the old home. It
    // drew seven scores at 46 points tall directly above a calendar drawing
    // thirty days, so two objects were telling the same story at different
    // resolutions and the smaller one won the better position. The calendar is
    // the one people read without a label. Score history still lives on
    // Profile, where somebody has gone looking for it.

    /// The line under the pill on a day with nothing measured yet. It shows
    /// only when there IS something to lose, so it can never read as a scold
    /// on somebody's first morning.
    private var nudge: String? {
        let cal = Calendar.current
        let practicedToday = sessions.contains { cal.isDateInToday($0.startedAt) }
        guard !practicedToday else { return nil }
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        if streak.restDayUsed {
            return "Yesterday was your rest day. Sit today and your \(streak.current)-day streak carries on."
        }
        if streak.current > 1 {
            return "Nothing measured today. Your \(streak.current)-day streak is on the line."
        }
        return sessions.isEmpty ? nil : "Nothing measured today"
    }

    private var calendarCard: some View {
        let practiced = SessionCalendar.practicedDays(from: sessions.map(\.startedAt))
        let byDay = FeatureFlags.friends ? PhotoThumbs.maps(photos: photos, sessions: sessions).byDay : [:]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "This week")
                Spacer()
                Text("\(practicedThisWeek(practiced)) of 7")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            WeekStrip(practiced: practiced, photos: byDay) { day in
                profileDay = day
                tab = .profile
            }
        }
        .card(padding: 18)
    }

    /// Days sat in the last seven, which is the window the strip draws. Not
    /// the calendar week, for the reason `WeekStrip` gives.
    private func practicedThisWeek(_ practiced: Set<Date>) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - 6, to: today) }
            .filter { practiced.contains($0) }.count
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
                let thumbs = FeatureFlags.friends ? PhotoThumbs.maps(photos: photos, sessions: sessions).bySession : [:]
                VStack(spacing: 12) {
                    ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { _, session in
                        Button { sheet = .results(session.id) } label: {
                            EvidenceRow(session: session,
                                        score: scores[session.id],
                                        stats: stats[session.id],
                                        rating: ratings[session.id],
                                        thumbnail: thumbs[session.id])
                        }
                        .buttonStyle(CardButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = session.id } label: {
                                Label("Delete session", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
                .deleteSessionDialog(pending: $pendingDelete)
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
    let awardShowing: Bool
    let lastSessionID: UUID?
    /// A session read back off disk because the app was not running when it
    /// landed. Same destination as `lastSessionID`, different road in.
    let resumeSessionID: UUID?
    let openSave: (UUID) -> Void

    /// A landed session waiting for the screen to be free. Presenting while
    /// the live-session cover is still animating away, or while an award
    /// unlock (which fires on the same new session) is up, makes SwiftUI drop
    /// the presentation, and a dropped item presentation can leave the root's
    /// sheet stuck. So it waits for both, plus the dismissal animation.
    @State private var pendingSave: UUID?

    private struct Gate: Equatable { let pending: UUID?; let busy: Bool }

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
                    get: { community.phase == .needsUsername && !sessionActive && !awardShowing },
                    set: { _ in })) {
                    FriendsIntroView(model: community,
                                     suggested: users.first?.username ?? "",
                                     nickname: users.first?.displayName ?? "") {}
                }
                // Strava's flow: the session ends on Save session, then results.
                .onChange(of: lastSessionID) { _, id in
                    if let id { pendingSave = id }
                }
                // The same sheet, for a session that finished while the app
                // was suspended or dead. Both roads meet at the gate below,
                // so the presentation rules are stated once.
                .onChange(of: resumeSessionID) { _, id in
                    if let id { pendingSave = id }
                }
                .onAppear { if let resumeSessionID { pendingSave = resumeSessionID } }
                .task(id: Gate(pending: pendingSave, busy: sessionActive || awardShowing)) {
                    guard let id = pendingSave, !sessionActive, !awardShowing else { return }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled, pendingSave == id else { return }
                    pendingSave = nil
                    openSave(id)
                }
        } else {
            content
        }
    }
}


/// Opens "Too short to score" once the live-session cover has gone. The payload
/// that says so arrives the same moment the cover is torn down, and presenting
/// during that animation is the dropped-presentation trap (see FriendsHooks).
private struct DiscardHook: ViewModifier {
    let discard: SessionCoordinator.Discard?
    let sessionActive: Bool
    let open: (SessionCoordinator.Discard) -> Void

    @State private var shown: UUID?

    private struct Gate: Equatable { let id: UUID?; let busy: Bool }

    func body(content: Content) -> some View {
        content.task(id: Gate(id: discard?.id, busy: sessionActive)) {
            guard let d = discard, d.id != shown, !sessionActive else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            shown = d.id
            open(d)
        }
    }
}
