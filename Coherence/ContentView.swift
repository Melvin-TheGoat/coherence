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
    /// Block (2026-09-22): the blockers, the passes, and the "Ask Otto" that
    /// opens one of his screens.
    @ObservedObject private var block = BlockController.shared
    /// "Okay, let's meditate" on one of Otto's screens starts a session the
    /// moment his screen is down, so two covers never overlap. nil: nothing
    /// waiting; 0: open-ended; otherwise a timed session of that many minutes.
    @State private var startAfterOtto: Int?

    @State private var tab: MainTab = .home
    /// The tab the onboarding tour is showing under its dim (`TourHomeScreen`).
    /// While it is set it stands in for `tab`, Otto's Home line steps aside
    /// for the tour's narrator, and this view holds back the modals that could
    /// otherwise open over the tour. Nil everywhere else.
    @Environment(\.tourTab) private var tourTab
    /// Which of Otto's lines is showing on Home; a tap on him advances it.
    @State private var ottoLineIndex = 0
    /// Bumped by every tap on Otto, which jiggles him (`OttoJiggle`).
    #if DEBUG
    /// Settings > Testing > Otto's state: 0 follows the real history, 1 to 7
    /// shows that drawing, so every state can be looked at on a phone.
    @AppStorage(DebugOtto.stageKey) private var debugOttoStage = 0
    #endif
    @State private var ottoPokes = 0
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
    /// A session that finished while the app was away (`PendingSave`).
    /// Recomputed on every return to the foreground, because that is the
    /// moment they picked the phone up after sitting.
    @State private var landedWhileAway: UUID?
    /// The glow a landed session just earned, playing on Home.
    @State private var auraGain: AuraGain?
    /// The level the card shows while that plays, counting up to the real
    /// one. nil is the real one.
    @State private var auraCount: Int?
    /// The session the toast above the tab bar is offering to fill in.
    @State private var detailsFor: UUID?
    #if DEBUG
    /// `PREVIEW_BREATHING=<seconds elapsed>` opens the sit at that moment, so
    /// the valley's whole arc can be reviewed without waiting ten minutes for
    /// the sun to set. Any non-zero value works; 1 is the arrival frame.
    @State private var sitPreviewElapsed =
        ProcessInfo.processInfo.environment["PREVIEW_BREATHING"].flatMap(Double.init)
    /// `PREVIEW_UNBLOCK_GALLERY=1` opens the unblock-screens gallery, and
    /// `PREVIEW_INTERVENTION_HOWLONG=1` opens the how-long ("Not now")
    /// screen directly, both without a tap: a way to reach either from a
    /// cabled DEBUG install with no Simulator UI automation.
    @State private var unblockPreview: UnblockDebugPreview?
    #endif

    private enum HomeSheet: Identifiable {
        case setup, settings
        /// The how-to guide, opened from its circle under the streak on Home
        /// (Melvin, 2026-09-21: the Guide tab makes way for Block).
        case guide
        case results(UUID)
        /// Save session (Friends): opens when a live session lands, then
        /// chains into its results.
        case save(UUID)
        /// A session the Watch ended without a score (too short, unreadable).
        case discarded(SessionCoordinator.Discard)
        /// The offer, after the first meditation (2026-09-15). Opens when a
        /// free user leaves the first results screen.
        case paywall
        /// One of Otto's twenty screens, from "Otto wants a word".
        case intervention(InterventionKind)
        /// The free-week offer, from switching a blocker on. Block is paid.
        case blockPaywall

        var id: String {
            switch self {
            case .setup: return "setup"
            case .settings: return "settings"
            case .guide: return "guide"
            case .results(let id): return "results-\(id)"
            case .save(let id): return "save-\(id)"
            case .discarded(let d): return "discarded-\(d.id)"
            case .paywall: return "paywall"
            case .intervention(let kind): return "intervention-\(kind.rawValue)"
            case .blockPaywall: return "blockPaywall"
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

    /// The tab bar's measured height, handed to the tabs as
    /// `tabBarClearance` for the pages pushed inside them.
    @State private var tabBarHeight: CGFloat = 0

    /// The tab on screen: the tour's while it runs, the person's otherwise.
    private var shownTab: MainTab { tourTab ?? tab }

    /// The bar reads what is on screen, so the tour's tab shows as selected;
    /// a tap writes the person's own selection.
    private var tabSelection: Binding<MainTab> {
        Binding(get: { shownTab }, set: { tab = $0 })
    }

    var body: some View {
        Group {
            switch shownTab {
            case .home:
                homeTab
            case .guide:
                GuideView(embedded: true) { sheet = .setup }
                    .onAppear { Analytics.track(.guideOpened) }
            case .block:
                BlockTab(block: block, entitlements: store.entitlements) { present(.blockPaywall) }
            case .friends:
                if FeatureFlags.friends { FriendsTab() } else { SearchTab() }
            case .profile:
                // Same destination Home's own rows open, through this
                // view's single sheet presenter (Melvin, 2026-09-23: a
                // session opened from Profile's week list must show the
                // same screen Home shows for it).
                ProfileTab(selectedDay: $profileDay,
                           openSession: { id in sheet = FeatureFlags.friends ? .save(id) : .results(id) }) {
                    sheet = .settings
                }
            }
        }
        // On the tabs only, not on the sheets presented further down this
        // chain: a sheet covers the bar, so its pages need no clearance.
        .environment(\.tabBarClearance, tabBarHeight)
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
                if shownTab == .home, let id = detailsFor, auraGain == nil { detailsToast(id) }
                MainTabBar(selection: tabSelection) { sheet = .setup }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
            }
            .animation(.easeOut(duration: 0.25), value: coordinator.receivingFromWatch)
            .animation(.easeOut(duration: 0.25), value: detailsFor)
        }
        .screenBackground()
        .fullScreenCover(item: Binding(
            get: { tourTab == nil ? unlockQueue.first : nil },
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
        .modifier(RootHooks(community: community, users: users,
                            sessionActive: coordinator.active != nil,
                            awardShowing: !unlockQueue.isEmpty,
                            touring: tourTab != nil,
                            lastSessionID: coordinator.lastSessionID,
                            resumedID: landedWhileAway,
                            onLanded: celebrate))
        .modifier(BlockHooks(block: block,
                             sessionActive: coordinator.active != nil,
                             awardShowing: !unlockQueue.isEmpty,
                             lastSessionID: coordinator.lastSessionID,
                             sessions: sessions,
                             scenePhase: scenePhase,
                             pick: { InterventionPicker.pick(interventionContext, recent: block.recentInterventions) },
                             present: { present(.intervention($0)) }))
        // Picking the phone up after a sit IS the moment to grade it, and by
        // then the app has usually been suspended or killed, so nothing is
        // left in memory to act on. Read the waiting session off disk instead.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { readLandedSession(); readDetailsPrompt() }
        }
        .onAppear { readLandedSession(); readDetailsPrompt() }
        .onChange(of: prefsRows.compactMap(\.evidenceGrantSince).min()) { _, _ in refreshAwards() }
        #if DEBUG
        .fullScreenCover(item: Binding(get: { sitPreviewElapsed.map { SitPreview(elapsed: $0) } },
                                       set: { _ in sitPreviewElapsed = nil })) { preview in
            SessionActiveView(startedAt: Date().addingTimeInterval(-preview.elapsed),
                              plannedDurationSec: 600,
                              planChip: "10 min · Silence") { sitPreviewElapsed = nil }
        }
        .fullScreenCover(item: $unblockPreview) { which in
            switch which {
            case .gallery:
                NavigationStack { InterventionGalleryView() }
            case .howLong:
                // Otto's own "Not now" flow, jumped straight to the how-long
                // step: nothing here is real, same as the gallery's rows.
                InterventionView(kind: .standing, context: InterventionContext(hour: 9, streak: 6,
                                                                                aura: .progressing,
                                                                                friendWhoSat: nil),
                                 block: block,
                                 onMeditate: { _ in unblockPreview = nil },
                                 onClose: { unblockPreview = nil },
                                 rehearsal: true, startOnHowLong: true)
            case .kind(let kind):
                // Exactly what tapping that kind's row in the gallery opens.
                InterventionView(kind: kind, context: InterventionContext(hour: 9, streak: 6,
                                                                           aura: .progressing,
                                                                           friendWhoSat: "Sam"),
                                 block: block,
                                 onMeditate: { _ in unblockPreview = nil },
                                 onClose: { unblockPreview = nil },
                                 rehearsal: true)
            }
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
            if let minutes = startAfterOtto {
                startAfterOtto = nil
                beginFromOtto(minutes: minutes == 0 ? nil : minutes)
                return
            }
            if let next = pendingSheet { pendingSheet = nil; sheet = next }
        }) { which in
            switch which {
            case .setup:
                SessionSetupView()
            case .settings:
                SettingsView()
            case .guide:
                GuideView { pendingSheet = .setup; sheet = nil }
                    .onAppear { Analytics.track(.guideOpened) }
            case .results(let id):
                SessionResultsView(sessionID: id)
            case .save(let id):
                SaveSessionView(sessionID: id, mode: .edit) {
                    SessionDetails.clear(id)
                    detailsFor = nil
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
            case .intervention(let kind):
                InterventionView(kind: kind, context: interventionContext, block: block,
                                 onMeditate: { minutes in
                                     startAfterOtto = minutes ?? 0
                                     sheet = nil
                                 },
                                 onClose: { sheet = nil })
                    .onAppear { block.noteInterventionShown(kind) }
            case .blockPaywall:
                PaywallScreen(placement: "block", plan: $paywallPlan) { _ in sheet = nil }
            }
        }
    }

    /// What Otto knows when he asks: the hour, the streak, his own glow, and
    /// a friend who meditated today, so each of his screens only says what is
    /// true.
    private var interventionContext: InterventionContext {
        let dates = sessions.map(\.startedAt)
        let friend: String? = {
            guard FeatureFlags.friends else { return nil }
            let today = community.feed.first {
                Calendar.current.isDateInToday($0.practicedAt) && $0.author != community.myID
            }
            guard let author = today?.author,
                  let name = community.person(author)?.displayName,
                  let first = name.split(separator: " ").first else { return nil }
            return String(first)
        }()
        return InterventionContext(hour: Calendar.current.component(.hour, from: Date()),
                                   streak: StreakCalculator.streak(from: dates).current,
                                   aura: auraStage,
                                   friendWhoSat: friend)
    }

    /// "Okay, let's meditate": the session starts at once, with the sound
    /// they last chose on the Ready screen (Melvin, 2026-09-22: straight into
    /// the session, one less tap between them and their apps).
    private func beginFromOtto(minutes: Int?) {
        var soundID = UserDefaults.standard.string(forKey: "sessionSoundID") ?? ""
        // The guided journey is paid; a free person starts in silence rather
        // than being handed a track the Ready screen would have locked.
        if GuidedCatalog.preset(id: soundID) != nil, !store.entitlements.guidedTrack { soundID = "" }
        let id = soundID.isEmpty ? nil : soundID
        coordinator.begin(mode: SoundCatalog.mode(for: id),
                          trackID: nil,
                          plannedDurationSec: minutes.map { $0 * 60 },
                          hapticsEnabled: prefsRows.first?.hapticsEnabled ?? true,
                          soundID: id)
    }

    #if DEBUG
    /// The simulator review hooks (`PREVIEW_*`, `DEMO_*`). A function rather
    /// than an inline closure: as one expression on the body's chain it sent
    /// the type checker over its time limit (2026-09-15).
    private func debugPreviewHooks() {
            // PREVIEW_AURA=<from>:<to> replays a landed session's glow on
            // Home, without waiting a day for a real one to earn it.
            if let raw = ProcessInfo.processInfo.environment["PREVIEW_AURA"] {
                let parts = raw.split(separator: ":").compactMap { Int($0) }
                let from = parts.first ?? 40
                let to = parts.count > 1 ? parts[1] : from + 10
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    tab = .home
                    ottoLineIndex = 0
                    ottoPokes += 1
                    auraGain = AuraGain(sessionID: UUID(), from: from, to: to)
                    // The toast the real flow raises, on the newest session.
                    if FeatureFlags.friends, let newest = sessions.first {
                        SessionDetails.set(newest.id)
                        detailsFor = newest.id
                    }
                    await countGlow(from: from, to: to)
                }
            }
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
            // PREVIEW_SETUP=1 opens the Ready screen, so its layout can be
            // checked on any simulator without tapping the plus.
            if ProcessInfo.processInfo.environment["PREVIEW_SETUP"] == "1", sheet == nil {
                sheet = .setup
            }
            // PREVIEW_AWARD=<award id> (e.g. streak-3) announces that award,
            // so the unlock screen can be reviewed without earning it.
            if let id = ProcessInfo.processInfo.environment["PREVIEW_AWARD"],
               let award = Award.all.first(where: { $0.id == id }) ?? Award.all.first,
               unlockQueue.isEmpty {
                unlockQueue = [AwardEngine.Earned(award: award, earnedAt: Date(),
                                                  progress: 1, progressText: nil)]
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
            // PREVIEW_INTERVENTION=<kind> (e.g. faceTime) opens that one of
            // Otto's screens; any other value opens a picked one.
            if let raw = ProcessInfo.processInfo.environment["PREVIEW_INTERVENTION"], sheet == nil {
                sheet = .intervention(InterventionKind(rawValue: raw)
                                      ?? InterventionPicker.pick(interventionContext, recent: []))
            }
            // PREVIEW_UNBLOCK_GALLERY=1 opens the unblock-screens gallery
            // (Settings > DEBUG) directly; PREVIEW_INTERVENTION_HOWLONG=1
            // opens the how-long ("Not now") screen directly. Both a way in
            // with no tap, for a cabled DEBUG install with no UI automation.
            if ProcessInfo.processInfo.environment["PREVIEW_UNBLOCK_GALLERY"] == "1", unblockPreview == nil {
                unblockPreview = .gallery
            }
            if ProcessInfo.processInfo.environment["PREVIEW_INTERVENTION_HOWLONG"] == "1", unblockPreview == nil {
                unblockPreview = .howLong
            }
            // PREVIEW_UNBLOCK_KIND=<kind> opens that kind exactly as tapping
            // its row in the gallery would (rehearsal mode): a way to prove
            // any one of the twenty renders correctly with no tap.
            if let raw = ProcessInfo.processInfo.environment["PREVIEW_UNBLOCK_KIND"], unblockPreview == nil,
               let kind = InterventionKind(rawValue: raw) {
                unblockPreview = .kind(kind)
            }
            if let which = ProcessInfo.processInfo.environment["PREVIEW_TAB"] {
                switch which {
                case "block": tab = FeatureFlags.block ? .block : .guide
                case "guide": tab = .guide
                case "friends", "search": tab = .friends
                case "profile": tab = .profile
                default: tab = .home
                }
            }
        
    }
    #endif

    // MARK: - Home

    /// Home is the valley (Melvin, 2026-09-21, with Brainrot's home screen as
    /// the reference and Aziz's sit and Ready screens as the theme): Otto in
    /// the middle of the meadow at his aura stage, what he has to say in a
    /// bubble over his head, the streak in the corner, and everything else on
    /// cream cards resting on the grass below him.
    ///
    /// **It is Aziz's `ValleyScene`, not a copy of it**, at the top of its
    /// day, so Home, Ready and the sit are one place and Otto never changes
    /// picture between them. The page under the scene is the meadow's own
    /// bottom colour, so the grass runs on behind the cards.
    private var homeTab: some View {
        GeometryReader { proxy in
            // 80 percent, not 74 (Melvin, 2026-09-23): the bubble has to start
            // below the guide circle, so Otto sits lower to leave it room,
            // and the cards under him move down with him.
            let sceneHeight = proxy.safeAreaInsets.top + proxy.size.height * 0.80
            ScrollView {
                VStack(spacing: 0) {
                    homeScene(width: proxy.size.width, height: sceneHeight,
                              topInset: proxy.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 16) {
                        auraCard
                            .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.glow: $0] }
                        statTiles
                        calendarCard
                        proofSection
                        #if DEBUG
                        debugButtons
                        #endif
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    // The cards rise onto the near meadow, just under his
                    // cushion, rather than waiting below a field of empty
                    // grass: Brainrot puts its number straight under the brain.
                    .padding(.top, -sceneHeight * 0.17)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            // The page is grass. The sky that shows when the top is pulled
            // down scrolls WITH the scene (see `homeScene`): a background
            // pinned half sky and half grass showed a band of sky behind the
            // cards as soon as the page moved.
            .background(Self.meadow.ignoresSafeArea())
        }
    }

    /// Home follows the real time of day (Melvin, 2026-09-23), so its
    /// greeting's ink and the grass under the cards follow it too.
    private static var homeDay: DayLight { DayLight.now }
    /// The meadow's colour at its near edge, which the page continues.
    private static var meadow: Color { homeDay.field[1] }

    /// The valley with Otto in it, and the three things laid on the sky.
    private func homeScene(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        let size = CGSize(width: width, height: height)
        let ink = Self.homeDay.ink
        let ottoTop = SitLayout.ottoTop(in: size)
        let ottoSize = 186 * SitLayout.scale(in: size)
        return ZStack(alignment: .top) {
            ValleyScene(progress: 0, aura: auraStage, jiggle: ottoPokes, clock: true)
                .frame(width: width, height: height)

            // The greeting, centred, where Brainrot writes its name. The
            // streak sits in the corner beside it, a flame and a number.
            VStack(spacing: 2) {
                Text(greeting)
                    .font(DisplayFont.display(24, .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(AppFont.caption)
                    .foregroundStyle(ink.opacity(0.7))
            }
            .padding(.horizontal, 84)
            .frame(maxWidth: .infinity)
            .padding(.top, topInset + 10)

            // The streak, and under it the guide in the same circle
            // (Melvin, 2026-09-21: the Guide leaves the tab bar for Block).
            VStack(spacing: 10) {
                streakBadge
                    .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.streak: $0] }
                guideBadge
                    .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.guide: $0] }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, AppMetrics.screenPadding)
            .padding(.top, topInset + 6)

            // The glow a landed session just earned. Under his bubble, so
            // the sparks pass behind the words rather than across them.
            if let gain = auraGain {
                AuraGainBurst(gain: max(0, gain.to - gain.from), size: ottoSize)
                    .position(x: width / 2, y: ottoTop + ottoSize * 0.42)
                    .id(gain.sessionID)
            }

            // What he says, pinned by its bottom to just above his head, the
            // way the Ready screen pins its line, so the tail lands on him on
            // every phone. Not during the onboarding tour, where he is the one
            // walking the reader through, and two of his bubbles would talk
            // over each other. Its TOP is held below the streak and guide
            // circles (6 + 54 + 10 + 54, and 8 of air): a long line used to
            // grow up into the corner and cover the guide (Melvin,
            // 2026-09-23).
            let bubbleTop = topInset + 132
            if tourTab == nil {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Dark ink at every hour: the bubble is cream even at night.
                    OttoSpeech(text: ottoLines[ottoLineIndex % ottoLines.count],
                               tail: .bottom, size: 17,
                               ink: DayLight.at(0).ink, stroke: DayLight.at(0).ink.opacity(0.38),
                               fill: AppColor.backgroundPrimary.opacity(0.78),
                               speaking: .constant(false))
                }
                .frame(width: min(width - 56, 330), height: max(0, ottoTop - 8 - bubbleTop))
                .padding(.top, bubbleTop)
            }

            // Tapping him jiggles him and changes what he says.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: ottoSize, height: ottoSize)
                .position(x: width / 2, y: ottoTop + ottoSize / 2)
                .onTapGesture {
                    ottoLineIndex += 1
                    ottoPokes += 1
                }
                .accessibilityElement()
                .accessibilityLabel("Otto")
                .accessibilityHint("Says something new")
                .accessibilityAddTraits(.isButton)
        }
        .frame(width: width, height: height)
        // Sky above the scene for a pull past the top.
        .background(alignment: .top) {
            Self.homeDay.sky[0]
                .frame(height: 1000)
                .offset(y: -1000)
        }
    }

    /// What Otto says, written by rules from the same facts the pill and the
    /// nudge read, never generated. The first line is the one that matters
    /// today; a tap cycles through the rest, then through `OttoSayings`,
    /// twenty-five lines of his own and of famous meditators, started at a
    /// different one each day.
    ///
    /// Nothing here mentions a score, a doorway or a Watch (Melvin,
    /// 2026-09-22): a session on the phone is the product, and there are
    /// endless ways to meditate, so he never prescribes one.
    private var ottoLines: [String] {
        let cal = Calendar.current
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let practicedToday = sessions.contains { cal.isDateInToday($0.startedAt) }
        var lines: [String] = []
        // A sit has just landed and his glow is climbing: that is the news.
        if let gain = auraGain {
            if sessions.count <= 1 {
                lines.append("That's your first one. Look what it did to me.")
            } else if gain.to > gain.from {
                lines.append(OttoAura.Stage(level: gain.to) > OttoAura.Stage(level: gain.from)
                             ? "Look at me now. That's what showing up does."
                             : "That's today done. I'm brighter for it.")
            } else {
                lines.append("Twice in one day. I'm already glowing from the first.")
            }
        }
        // Holding apps is the most useful thing he can say (Block, 2026-09-22).
        if FeatureFlags.block, !block.holding().isEmpty {
            lines.append("I'm holding your apps. A short session and they're yours.")
        }
        // His mood leads when it is the news: a sad Otto who says nothing
        // about it reads as a bug, and a glowing one has earned a word.
        switch auraStage {
        case .withered where !practicedToday:
            lines.append("I've been feeling a bit flat. One session today and I'll perk right up.")
        case .faded where !practicedToday:
            lines.append("It's been a few days. One short session and I'll be back on my feet.")
        case .bright, .radiant:
            lines.append("Feel that? You keep showing up, and it shows on me.")
        case .nirvana:
            lines.append("I'm glowing. That's what showing up day after day does.")
        default:
            break
        }
        if sessions.isEmpty {
            lines.append("Your first session starts at the plus. I'll be right here.")
        } else if practicedToday {
            lines.append(streak.current > 1 ? "Day \(streak.current). You already sat today, so today is done."
                                             : "You meditated today. That's the part that counts.")
            lines.append("Nothing more to do here. Come back tomorrow and we'll keep it going.")
        } else if streak.restDayUsed {
            lines.append("Rest day yesterday. Sit today and your \(streak.current)-day streak carries on.")
        } else if streak.current > 1 {
            lines.append("Day \(streak.current). Sit whenever you're ready, I'll be here.")
            if streak.current == streak.longest, streak.current >= 3 {
                lines.append("\(streak.current) in a row is your longest yet. No rush today either.")
            }
        } else {
            lines.append("Whenever you're ready. One session is all today asks.")
        }
        return lines + OttoSayings.forDay(Date())
    }

    /// The level the card is showing: the real one, or the one climbing to it
    /// after a sit.
    private var shownAuraLevel: Int { auraCount ?? auraLevel }

    /// The prompt that replaces the screen a session used to open into
    /// (Melvin, 2026-09-22, picking B from `mockups/after-session.html`):
    /// above the tab bar, and **it never fades**. The only ways out are the
    /// X and filling the session in, because a toast that disappears is one
    /// most people would never once use.
    private func detailsToast(_ id: UUID) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Add how that felt")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Photos, notes, and who can see it")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.accentGoldText)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .overlay(alignment: .topLeading) {
            Button {
                SessionDetails.clear(id)
                detailsFor = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(AppColor.backgroundSecondary, in: Circle())
                    .overlay(Circle().strokeBorder(AppColor.backgroundPrimary, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .offset(x: -7, y: -7)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .contentShape(Rectangle())
        .onTapGesture { present(.save(id)) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Otto's stage today, from the same session dates as the streak. It
    /// follows the climbing level during a celebration, so he brightens as
    /// the bar fills rather than a moment later.
    private var auraStage: OttoAura.Stage {
        #if DEBUG
        // OTTO_AURA=<0...100> shows a stage on a simulator with no history.
        if let raw = ProcessInfo.processInfo.environment["OTTO_AURA"], let level = Int(raw) {
            return OttoAura.Stage(level: level)
        }
        // Settings > Testing > Otto's state, for a phone with a real history.
        if let forced = OttoAura.Stage(rawValue: debugOttoStage) { return forced }
        #endif
        return OttoAura.Stage(level: shownAuraLevel)
    }

    /// Otto's level today, 0 to 100, for the bar under his name.
    private var auraLevel: Int {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["OTTO_AURA"], let level = Int(raw) {
            return min(max(level, 0), 100)
        }
        if let forced = OttoAura.Stage(rawValue: debugOttoStage) { return DebugOtto.level(for: forced) }
        #endif
        // A "Not now" that went unanswered costs glow (Melvin, 2026-09-22).
        // The windows come from the phone's own Screen Time state and are
        // never sent anywhere.
        return OttoAura.level(from: sessions.map(\.startedAt),
                              notNow: FeatureFlags.block ? block.notNowWindows : [])
    }

    /// The streak in the corner, Brainrot's flame and number, on the same
    /// frosted cream as the Ready screen's rows.
    private var streakBadge: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        return VStack(spacing: 0) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColor.streakBlushText)
            Text("\(streak.current)")
                .font(DisplayFont.display(16, .heavy))
                .foregroundStyle(AppColor.streakBlushText)
                .monospacedDigit()
        }
        .frame(width: 54, height: 54)
        .background(AppColor.backgroundPrimary.opacity(0.85), in: Circle())
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.current) day streak")
    }

    /// The how-to guide, in the streak's circle so the two read as a pair.
    private var guideBadge: some View {
        Button { sheet = .guide } label: {
            VStack(spacing: 1) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.calmAccent)
                Text("Guide")
                    .font(.system(size: 10, weight: .bold))
                    // Daytime ink always: it sits on a cream circle at every hour.
                    .foregroundStyle(DayLight.at(0).ink.opacity(0.8))
            }
            .frame(width: 54, height: 54)
            .background(AppColor.backgroundPrimary.opacity(0.85), in: Circle())
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How to meditate guide")
    }

    /// How bright Otto is, as a percentage, and the bar that fills as the
    /// practice keeps up.
    ///
    /// **A percentage, not a mood** (Melvin, 2026-09-22: "Otto is curious"
    /// did not say anything). It carried no number at first so it could not
    /// be read as a session's score; the score is on its way out, and a
    /// number says plainly how much glow there is to keep. The stage names
    /// still steer what he says and what VoiceOver calls him.
    private var auraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Otto's glow")
                    .font(DisplayFont.display(20, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 8)
                Text("\(shownAuraLevel)%")
                    .font(DisplayFont.display(22, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.trace)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColor.auraGlow, AppColor.auraRing],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, geo.size.width * CGFloat(shownAuraLevel) / 100))
                        .animation(.easeOut(duration: 0.12), value: shownAuraLevel)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            Text(nudge ?? "Each day you meditate, his glow grows.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .card(padding: 18)
        .accessibilityElement(children: .combine)
    }

    /// Brainrot's three tiles, in 808's facts: the best streak (the current
    /// one is in the corner), the sessions, and the time sat.
    private var statTiles: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let seconds = sessions.reduce(0) { $0 + $1.durationSec }
        return HStack(spacing: 10) {
            statTile(icon: "trophy.fill", tint: AppColor.accentGoldText,
                     value: "\(streak.longest)", label: streak.longest == 1 ? "best day" : "best streak")
            statTile(icon: "figure.mind.and.body", tint: AppColor.calmAccent,
                     value: "\(sessions.count)", label: sessions.count == 1 ? "session" : "sessions")
            statTile(icon: "clock.fill", tint: AppColor.textSecondary,
                     value: Self.sat(seconds), label: "meditated")
        }
    }

    private func statTile(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 26)
            Text(value)
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .fill(AppColor.backgroundSecondary)
                .shadow(color: AppColor.hairline, radius: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    /// "45m", "2h 10m": the time sat, in the fewest characters that read.
    static func sat(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Awards

    /// Derived from history on every check, so nothing needs backfilling: a
    /// user with months of sessions simply has the awards those sessions earned.
    /// A session that landed while 808 was closed, if it is still there. A
    /// session can be deleted, so the stored id is checked against storage
    /// first; a dangling id clears itself.
    private func readLandedSession() {
        guard let id = PendingSave.read() else { landedWhileAway = nil; return }
        guard sessions.contains(where: { $0.id == id }) else {
            PendingSave.clear()
            landedWhileAway = nil
            return
        }
        landedWhileAway = id
    }

    // MARK: - A session landed

    /// What happens after a sit (Melvin, 2026-09-22): Home, and Otto's glow
    /// rising, with no screen to fill in first. The Save session screen and
    /// the results screen used to open here, one after the other.
    private func celebrate(_ id: UUID) {
        PendingSave.clear()
        landedWhileAway = nil
        tab = .home
        guard let landed = sessions.first(where: { $0.id == id }) else { return }
        // The prompt to fill it in waits for the glow to finish; the toast
        // itself is hidden while `auraGain` is set.
        if FeatureFlags.friends {
            SessionDetails.set(id)
            detailsFor = id
        }
        let windows = FeatureFlags.block ? block.notNowWindows : []
        let dates = sessions.map(\.startedAt)
        let before = OttoAura.level(from: dates.filter { $0 != landed.startedAt }, notNow: windows)
        let after = OttoAura.level(from: dates, notNow: windows)
        ottoLineIndex = 0
        ottoPokes += 1
        auraGain = AuraGain(sessionID: id, from: before, to: after)
        Task { await countGlow(from: before, to: after) }
    }

    /// The bar and its number climb to what the sit earned, then the card
    /// goes back to reading the real level.
    @MainActor private func countGlow(from: Int, to: Int) async {
        auraCount = from
        try? await Task.sleep(for: .milliseconds(260))
        let steps = 22
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else { return }
            auraCount = from + Int((Double(to - from) * Double(step) / Double(steps)).rounded())
        }
        try? await Task.sleep(for: .milliseconds(1800))
        guard !Task.isCancelled else { return }
        auraCount = nil
        auraGain = nil
    }

    /// The toast's session, if there still is one. A deleted session clears
    /// it, the same check `readLandedSession` does.
    private func readDetailsPrompt() {
        guard FeatureFlags.friends, let id = SessionDetails.read() else { detailsFor = nil; return }
        guard sessions.contains(where: { $0.id == id }) else {
            SessionDetails.clear(id)
            detailsFor = nil
            return
        }
        detailsFor = id
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
            return "Rest day yesterday. Sit today and your \(streak.current)-day streak carries on."
        }
        if streak.current > 1 {
            return "Meditate today and your \(streak.current)-day streak keeps going."
        }
        return nil
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
                let ratings = SessionListSupport.ratingMap(reflections)
                VStack(spacing: 12) {
                    ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { _, session in
                        // The session's own page, which is where everything
                        // about it is said now. Its measurements, when a
                        // Watch took any, are one tap further in.
                        Button { sheet = FeatureFlags.friends ? .save(session.id) : .results(session.id) } label: {
                            EvidenceRow(session: session,
                                        score: scores[session.id],
                                        rating: ratings[session.id])
                        }
                        .buttonStyle(CardButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = session.id } label: {
                                Label("Delete session", systemImage: "trash")
                            }
                        }
                    }
                }
                .deleteSessionDialog(pending: $pendingDelete)
            }
        }
        // One card for the header and the rows: on the grass a bare header
        // and a gold "See all" would be text on a painting.
        .card(padding: 18)
    }

    // MARK: - DEBUG

    #if DEBUG
    private var debugButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Preview the sit") { sitPreviewElapsed = 1 }
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
    }
    #endif

    // MARK: - Helpers

    /// "Belly · 10 min · Deep Meditation" for the mid-session plan chip.
    /// The chip on the sit's arrival frame. It states the two facts somebody
    /// might doubt at the moment they close their eyes: how long this runs,
    /// and what is about to play.
    ///
    /// nil when there is nothing worth saying. An open-ended silent sit is
    /// the default, and a chip reading "Open" over a valley is jargon in a
    /// gold capsule.
    private func planChip(_ session: SessionCoordinator.ActiveSession) -> String? {
        var parts: [String] = []
        if let planned = session.plannedDurationSec { parts.append("\(planned / 60) min") }
        if let title = session.soundTitle { parts.append(title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    /// The onboarding tour is showing this screen. Both of these wait for it
    /// to finish: the tour's Friends stop loads the tab, and a reward or the
    /// profile prompt opening then would cover the tour.
    let touring: Bool

    func body(content: Content) -> some View {
        if FeatureFlags.friends {
            content
                // The invite reward landing: a brought friend sat once.
                .sheet(item: Binding(get: { touring ? nil : community.rewardNews },
                                     set: { community.rewardNews = $0 })) { news in
                    InviteRewardSheet(news: news).presentationDetents([.medium])
                }
                // People who finished onboarding before Friends: one required
                // prompt to create a profile, whenever iCloud says they have none.
                .fullScreenCover(isPresented: Binding(
                    get: { community.phase == .needsUsername && !sessionActive && !awardShowing && !touring },
                    set: { _ in })) {
                    FriendsIntroView(model: community,
                                     suggested: users.first?.username ?? "",
                                     nickname: users.first?.displayName ?? "") {}
                }
        } else {
            content
        }
    }
}

/// Friends and the end of a session, in ONE modifier on the root.
///
/// Not two: ContentView's chain is at the type checker's limit, and adding a
/// second `.modifier(...)` to it is what tipped it over (2026-09-22).
private struct RootHooks: ViewModifier {
    @ObservedObject var community: CommunityModel
    let users: [User]
    let sessionActive: Bool
    let awardShowing: Bool
    /// The onboarding tour is on screen (`ContentView.tourTab`).
    let touring: Bool
    let lastSessionID: UUID?
    let resumedID: UUID?
    let onLanded: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(FriendsHooks(community: community, users: users,
                                   sessionActive: sessionActive, awardShowing: awardShowing,
                                   touring: touring))
            .modifier(SessionLandedHooks(sessionActive: sessionActive,
                                         awardShowing: awardShowing || touring,
                                         lastSessionID: lastSessionID,
                                         resumedID: resumedID,
                                         onLanded: onLanded))
    }
}

/// What a landed session earned, while Home is showing it.
struct AuraGain: Equatable {
    let sessionID: UUID
    let from: Int
    let to: Int
}

/// A sit has landed and the screen is free: Home, and Otto's glow rising
/// (Melvin, 2026-09-22). Nothing opens after a session any more. The Save
/// session screen and the results screen used to, one behind the other, which
/// put two forms between a person and the thing they just did.
///
/// **It waits for the covers.** Acting while the live-session cover is still
/// animating away, or while an award unlock (which fires on the same new
/// session) is up, means the celebration plays behind a full-screen cover
/// where nobody sees it.
private struct SessionLandedHooks: ViewModifier {
    let sessionActive: Bool
    let awardShowing: Bool
    let lastSessionID: UUID?
    /// A session read back off disk because the app was not running when it
    /// landed. Same destination, different road in.
    let resumedID: UUID?
    let onLanded: (UUID) -> Void

    @State private var pending: UUID?

    private struct Gate: Equatable { let pending: UUID?; let busy: Bool }

    func body(content: Content) -> some View {
        content
            .onChange(of: lastSessionID) { _, id in if let id { pending = id } }
            .onChange(of: resumedID) { _, id in if let id { pending = id } }
            .onAppear { if let resumedID { pending = resumedID } }
            .task(id: Gate(pending: pending, busy: sessionActive || awardShowing)) {
                guard let id = pending, !sessionActive, !awardShowing else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, pending == id else { return }
                pending = nil
                onLanded(id)
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

#if DEBUG
/// Identifies one moment of the sit for the simulator preview hook.
struct SitPreview: Identifiable {
    let elapsed: Double
    var id: Double { elapsed }
}

/// `PREVIEW_UNBLOCK_GALLERY` / `PREVIEW_INTERVENTION_HOWLONG` /
/// `PREVIEW_UNBLOCK_KIND=<kind>`: which of Otto's unblock screens to open
/// with no tap. `.kind` opens one intervention kind exactly the way tapping
/// its row in the gallery would (rehearsal mode, no tap needed to prove it).
enum UnblockDebugPreview: Identifiable {
    case gallery, howLong
    case kind(InterventionKind)

    var id: String {
        switch self {
        case .gallery: return "gallery"
        case .howLong: return "howLong"
        case .kind(let kind): return "kind-\(kind.rawValue)"
        }
    }
}
#endif
