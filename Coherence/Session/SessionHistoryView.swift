import SwiftUI
import SwiftData
import Charts

/// **Profile** — the far-right tab: the person, then the proof, then what they
/// have done. A portrait under the sky, the four totals, your scores over
/// time, the month, the awards shelf, and the full log. Settings in the gear.
///
/// **This is where the long view lives, and that is the whole division of
/// labour between the two tabs.** Home answers "how am I doing today": one
/// week, the last three sits, a streak. Profile answers "how am I doing", and
/// every object on it covers more than a week. Both the month calendar and the
/// score history were removed from Home on the understanding that they lived
/// here, and for a while neither actually did.
///
/// Reads storage independently via `@Query`, so it refreshes live when a new
/// session lands from the Watch. Screens pass only IDs/dates; models are immutable.
struct ProfileTab: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var allStats: [MeditationStats]
    @Query private var reflections: [SessionReflection]
    @Query private var users: [User]
    @Query private var prefsRows: [Preferences]
    @Query private var photos: [SessionPhoto]
    @EnvironmentObject private var community: CommunityModel
    @EnvironmentObject private var store: Store

    /// Session id → the photo taken after it, for the rows. Empty with
    /// Friends off, so the Release build draws the rows it always did.
    private var photoThumbs: [UUID: UIImage] {
        FeatureFlags.friends ? PhotoThumbs.maps(photos: photos, sessions: sessions).bySession : [:]
    }
    @State private var editingProfile = false

    /// A practiced day tapped on Home — filters the log below.
    @Binding var selectedDay: Date?
    let openSettings: () -> Void
    /// A log row awaiting the delete confirmation.
    @State private var pendingDelete: UUID?
    /// Set one frame after the page arrives, which is what the cards rise on.
    @State private var settled = false


    private let calendar = Calendar.current

    /// Profile is the same place as Home and the sit, from a little further
    /// back: a short band of the valley with nobody in it, and your practice
    /// on the grass below.
    ///
    /// **The scene scrolls with the page rather than staying pinned.** Home
    /// learned this the hard way: a background half sky and half grass shows
    /// a band of sky behind the cards the moment anything moves. The page is
    /// grass, the band rides on top of it, and pulling down stretches the sky
    /// instead of tearing it.
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let band = proxy.safeAreaInsets.top + proxy.size.height * 0.20
                ScrollView {
                    VStack(spacing: 0) {
                        profileScene(width: proxy.size.width, height: band,
                                     topInset: proxy.safeAreaInsets.top)
                            .overlay(alignment: .topTrailing) {
                                gearButton(top: proxy.safeAreaInsets.top)
                            }
                        VStack(alignment: .leading, spacing: 12) {
                            identityCard.rising(settled, 0)
                            statsRow.rising(settled, 1)
                            minutesCard.rising(settled, 2)
                            awardsSection.rising(settled, 3)
                            logSection.rising(settled, 4)
                        }
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .background(Self.meadow.ignoresSafeArea())
            }
            .navigationBarHidden(true)
        }
        // The page settles rather than appearing all at once: the valley is
        // already there when the tab opens and the five cards come up out of
        // the grass under it, 55ms apart.
        //
        // **Once per launch, not once per visit.** The tab keeps its state,
        // so `settled` stays true after the first look and coming back to
        // Profile is instant. A page that re-assembles itself every time you
        // tap the tab is a page that feels slow by the third visit.
        //
        // **The sky band never moves.** A scene that slides in behind cards
        // that are also sliding reads as the whole screen lurching; the
        // ground is the fixed thing here and the contents are what arrive.
        // The delay lives in each card's own animation (see `rising`), so the
        // flag is flipped plainly: one `withAnimation` around all five would
        // move them together, which is a screen appearing, not settling.
        //
        // **On the NEXT runloop turn, not inside `onAppear`.** An
        // `.animation(value:)` animates every animatable change in its
        // subtree at the instant the value flips, and flipping it during the
        // first layout pass caught the cards' own width settling under the
        // GeometryReader: the text re-wrapped as they widened, so "Only you"
        // arrived as "Onlyyou" and the chart's axis crossed its header.
        // Letting the layout finish first leaves the animation nothing to
        // carry but the opacity and the offset, which is all it was for.
        .onAppear {
            guard !settled else { return }
            DispatchQueue.main.async { settled = true }
        }
    }

    /// The same daylight Home uses, so the two tabs are one place.
    private static let day = DayLight.at(0)
    /// The meadow at its near edge, which the page continues.
    private static var meadow: Color { day.field[1] }

    /// The valley with nobody in it. Otto is the portrait on this page, and
    /// drawing him in the band as well would put two of him on one screen.
    private func profileScene(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        ValleyScene(progress: 0, showsFigure: false)
            .frame(width: width, height: height)
    }

    /// A frosted circle on the sky, the material every floating control uses.
    ///
    /// **It rides on the scene rather than floating over the page.** Pinned
    /// to the screen it sat on top of whatever card was passing under it, and
    /// on a page of white cards on grass it collided with the stats row's
    /// last number. A control that overlaps the content it is not about is
    /// worse than one you scroll back up to reach, and scrolling back to the
    /// top of your own profile is one flick.
    private func gearButton(top: CGFloat) -> some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppColor.backgroundPrimary.opacity(0.92)))
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        }
        .padding(.trailing, AppMetrics.screenPadding)
        .padding(.top, top + 6)
        .accessibilityLabel("Settings")
    }

    // MARK: - Identity

    private var currentUser: User? {
        users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
    }

    /// You, on a white card with Otto's head on its seam.
    ///
    /// **There is no photo of you here** (Aziz, 2026-09-21: "no more pfp and
    /// make the sloth in the circle"). Otto's head is the portrait, on your
    /// page and on everybody else's, which means people are told apart by
    /// name and handle and by their own face in the selfie on each post.
    /// When that stops being enough, the fix is already built: draw each
    /// person's Otto at THEIR aura stage.
    ///
    /// The circle sits on the card's edge rather than on the scene, because
    /// on grass a circle needs a white ring to read as a portrait instead of
    /// a hole.
    private var identityCard: some View {
        let user = currentUser
        let friendsProfile = FeatureFlags.friends ? community.profile : nil
        let localName = user?.displayName?.isEmpty == false ? user!.displayName! : nil
        let name = localName ?? friendsProfile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName }
        let handle = Username.display(friendsProfile?.username ?? user?.username)

        return ZStack(alignment: .top) {
            VStack(spacing: 3) {
                Text(name ?? "Your practice")
                    .font(DisplayFont.display(22, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Text([handle, user.map {
                        "practicing since " + $0.createdAt.formatted(.dateTime.month(.abbreviated).year())
                     }].compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                if FeatureFlags.friends { profileActions.padding(.top, 10) }
                if FeatureFlags.friends { whoCanSee.padding(.top, 12) }
                if FeatureFlags.friends, community.phase == .ready {
                    FollowLine(followers: community.follow.followers,
                               following: community.follow.following,
                               personID: community.myID)
                        .padding(.top, 11)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 2)

            OttoMark(size: 62, pose: .head)
                .frame(width: 78, height: 78)
                .background(Circle().fill(AppColor.sky))
                .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 4))
                .offset(y: -39)
        }
        // Room for the half of the circle that hangs into the scene.
        .padding(.top, 39)
    }

    /// The page answers who can see it, in the place you would ask.
    ///
    /// Sage rather than amber: this is a fact about the app, not a score and
    /// not a warning. It only draws with Friends on, because with Friends off
    /// nothing is public and the sentence would answer a question the build
    /// does not raise.
    private var whoCanSee: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.calmAccent)
                .padding(.top, 1)
            Text("Friends see your name, your streak and the sessions you post. Everything marked Only you stays here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(AppColor.calmAccent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }


    private var profileActions: some View {
        // Capsules that fit their words, side by side and centred under the
        // name. Full-width slabs made a portrait look like a settings screen
        // with two rows of buttons under the avatar.
        HStack(spacing: 9) {
            Button { editingProfile = true } label: { Label("Edit profile", systemImage: "pencil") }
                .buttonStyle(PillButtonStyle())
            // Only a reserved handle is worth sending: an empty or cosmetic
            // one would invite a friend to search for nothing.
            if let handle = community.profile?.username, !handle.isEmpty {
                InviteButton(username: handle, style: .quiet, title: "Share profile")
            }
        }
        .sheet(isPresented: $editingProfile) {
            NavigationStack {
                CreateProfileView(model: community,
                                  suggested: community.profile?.username ?? currentUser?.username ?? "",
                                  nickname: currentUser?.displayName ?? "") { _ in editingProfile = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingProfile = false } } }
            }
        }
    }

    // MARK: - Otto
    //
    // Otto is NOT on this screen (Melvin, 2026-09-18: "the profile page is
    // too crowded, i dont think otto should be in there"). Its door is the
    // results screen, where a person is looking at the sit they want
    // explained and the question has a subject. A row here asked the
    // question with nothing in front of it, and cost the screen a section.
    // `OttoView()` still opens on the last ten sessions when it is opened
    // with no session id, so nothing about the general chat is lost.

    // MARK: - Awards

    /// Derived on every render rather than stored: the rules read the same
    /// history the rest of this screen is already showing, so a shelf can
    /// never disagree with the sessions below it.
    private var awardProgress: [AwardEngine.Earned] {
        let scores = Dictionary(allStats.compactMap { st -> (UUID, Double)? in
            guard let id = st.sessionID, let s = st.overallScore else { return nil }
            return (id, s)
        }, uniquingKeysWith: { a, _ in a })

        return AwardEngine.evaluate(
            sessions: sessions.map {
                .init(startedAt: $0.startedAt,
                      durationSec: $0.durationSec,
                      overallScore: scores[$0.id])
            },
            accountCreatedAt: users.first?.createdAt,
            friendBroughtAt: prefsRows.compactMap(\.evidenceGrantSince).min())
            .filter { !FeatureFlags.hiddenAwardIDs.contains($0.award.id) }
            // **An UNEARNED score award is hidden while the phone cannot
            // score** (Aziz, 2026-09-21: "we dont wanna worry about any of
            // the watch stuff"). A sit started here writes no stats, so the
            // three `.depth` awards are unreachable for almost everybody
            // now, and three permanently grey trophies on the shelf is the
            // screen telling somebody what they are missing.
            //
            // Hidden, not DELETED, and the distinction is the whole point:
            // a wrist-started session still scores, so anyone who earns one
            // keeps it, sees the unlock, and finds it on this shelf
            // afterwards. Nothing is taken away; an unreachable ask is
            // simply not displayed.
            .filter { $0.isEarned || $0.award.group != .depth }
    }

    private var awardsSection: some View {
        let items = awardProgress
        let earned = items.filter(\.isEarned)

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionHeader(title: "Awards")
                Spacer()
                Text("\(earned.count) of \(items.count)")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                NavigationLink {
                    AwardsView(earned: items)
                } label: {
                    Text("See all")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGoldText)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(CardButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items.prefix(8)) { item in
                        VStack(spacing: 7) {
                            AwardBadge(award: item.award, earned: item.isEarned, size: 62)
                            Text(item.award.title)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(item.isEarned
                                                 ? AppColor.textPrimary : AppColor.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 62)
                    }
                }
                // The card's own inset, given back to the content, so the
                // first badge lines up with the header above it.
                .padding(.horizontal, 18)
                // Room for a raised badge's shadow, which the scroll view
                // clips at its own bounds.
                .padding(.vertical, 6)
            }
            // **Bled to the card's edges, and NOT `scrollClipDisabled`.**
            // It was, so the shelf drew straight past the card and the last
            // badge sat on the grass outside it. A horizontal scroll has to
            // clip somewhere, and the only honest place is the edge of the
            // thing it lives in: badges now slide under the card's rim.
            .padding(.horizontal, -18)
            .padding(.vertical, -4)

            // The "Next: <award>" progress card was CUT (Melvin, same
            // pass): on a screen that already shows the streak, the four
            // stats, the shelf and every session, one more bar reads as
            // another thing undone. The shelf itself already shows what is
            // unearned, and "See all" carries the progress for anyone who
            // wants it.
        }
        // On a card like everything else on this screen. It was loose on the
        // paper, which made the only row of colour on Profile read as
        // decoration sitting behind the content rather than part of it.
        .card(padding: 18)
    }

    // MARK: - Stats

    /// Four numbers, one card.
    ///
    /// They were four separate rounded cards with gaps between them, which is
    /// four objects saying one thing. Hairline dividers instead, and the
    /// colours follow the app's grammar rather than all being gold: **blush is
    /// the streak, amber is what you scored and did.**
    /// The four facts a phone can report on its own, in Home's tile
    /// vocabulary: a small coloured glyph, the number in ink, the word under
    /// it. They were four coloured numbers on a cream slab, which on grass
    /// read as a receipt.
    private var statsRow: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let hours = Double(sessions.reduce(0) { $0 + $1.durationSec }) / 3600
        return HStack(spacing: 0) {
            stat("flame.fill", "\(streak.current)", "day streak", AppColor.streakBlushText)
            stat("trophy.fill", "\(streak.longest)", "longest", AppColor.accentGoldText)
            stat("figure.mind.and.body", "\(sessions.count)", "sessions", AppColor.calmAccent)
            stat("clock.fill",
                 hours >= 10 ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours),
                 "practiced", AppColor.textSecondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
    }

    private var divider: some View {
        Rectangle().fill(AppColor.hairline).frame(width: 1, height: 30)
    }

    private func stat(_ symbol: String, _ value: String,
                      _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(DisplayFont.display(20, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The proof

    // MARK: - The proof

    /// Your minutes, one bar per session.
    ///
    /// **This was Your scores until the baseline dropped the Watch** (Aziz,
    /// 2026-09-21: "we dont wanna worry about any of the watch stuff"). A
    /// phone sit measures nothing, so a score chart would be an empty frame
    /// on most people's page. Length is what a phone can honestly report,
    /// and the research this app is built on says consistency predicts
    /// improvement while session length does not, so a chart of minutes is
    /// a record rather than a target.
    ///
    /// **Amber stays.** It has always meant the measured quantity of a
    /// session, which with a Watch is its score and without one is its
    /// length. The instrument changed, not the colour's meaning.
    ///
    /// Bars, not a line. A line implies the value between two sessions and
    /// there is no value between two sessions: each is a separate morning.
    /// The average is the only continuous thing here, so it is the only line.
    private var minutesCard: some View {
        let recent: [MinutePoint] = sessions
            .prefix(16).reversed().enumerated()
            .map { MinutePoint(index: $0.offset,
                               minutes: Double($0.element.durationSec) / 60,
                               date: $0.element.startedAt) }
        let average = recent.isEmpty ? 0 : recent.map(\.minutes).reduce(0, +) / Double(recent.count)
        let longest = recent.map(\.minutes).max() ?? 0
        // `.ratio` sizes a bar against its category's step, and this chart's
        // x is a NUMBER, so the step is undefined and every bar drew at zero
        // width. Computed from the plot's own width instead, clamped so four
        // sessions do not each become a paving slab.
        let barWidth = min(20.0, max(7.0, 286.0 / Double(max(recent.count, 1)) * 0.68))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your minutes")
                if FeatureFlags.friends { ReachChip(shared: false) }
                Spacer()
                if recent.count >= 2 {
                    Text("last \(recent.count)")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            if recent.count < 2 {
                Text("Two sessions and this fills in. Every bar is one, and the line is your average.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart {
                    ForEach(recent) { point in
                        // Fat and rounded. The default width draws hairline
                        // bars with wide gaps, which is a statistics plot;
                        // the rest of this app is solid round objects.
                        // Grown from the floor on arrival, which is the one
                        // place a chart may animate: the bars are rising to
                        // the height they will keep, not cycling. The domain
                        // is pinned below so the axis cannot grow with them,
                        // which would read as the numbers changing.
                        BarMark(x: .value("Session", point.index),
                                y: .value("Minutes", point.minutes * (settled ? 1 : 0)),
                                width: .fixed(barWidth))
                            .foregroundStyle(AppColor.accentGold)
                            .cornerRadius(7)
                    }
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(AppColor.calmAccent.opacity(settled ? 1 : 0))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                // The domain is pinned so the axis cannot grow with the
                // bars, which would read as the numbers changing rather
                // than the chart arriving.
                .chartYScale(domain: 0...(max(longest, average) * 1.12 + 0.5))
                // **No animation of its own.** It had one, a slightly slower
                // spring than the card's, and an `.animation(value:)` drives
                // every animatable change in its subtree, the position the
                // card's own rise was already moving it to included. So the
                // chart slid up a beat behind its card and the y-axis label
                // crossed the header. The bars grow on the card's spring
                // (see `rising`), which is one curve for one object.
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(AppColor.hairline)
                        AxisValueLabel().foregroundStyle(AppColor.textSecondary)
                            .font(AppFont.caption)
                    }
                }
                .frame(height: 128)
                HStack(spacing: 0) {
                    proofStat("\(Int(average.rounded()))m", "average", AppColor.calmAccent)
                    divider
                    proofStat("\(Int(longest.rounded()))m", "longest", AppColor.accentGoldText)
                    divider
                    proofStat("\(sessions.count)", "in total", AppColor.textPrimary)
                }
                .padding(.top, 2)
            }
        }
        .card(padding: 18)
    }

    /// One bar: a single session's length, in the order it happened.
    private struct MinutePoint: Identifiable {
        let index: Int
        let minutes: Double
        let date: Date
        var id: Int { index }
    }

    /// One bar: a single sit's score, in the order it happened.
    private struct ScorePoint: Identifiable {
        let index: Int
        let score: Double
        let date: Date
        var id: Int { index }
    }

    private var longestSit: Int {
        sessions.map(\.durationSec).max() ?? 0
    }

    private func proofStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(DisplayFont.display(19, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The month
    //
    // THERE ISN'T ONE ANY MORE (Aziz, 2026-09-19: "a bit cramped, get rid of
    // the calendar"). It was restored to Profile hours earlier, so this is
    // worth being exact about rather than quietly reverting.
    //
    // **808 now has no month view at all.** The week strip on Home is the
    // only calendar in the product. That is defensible and it is a real
    // trade: a month of dots answers "did I show up" at a resolution nobody
    // needs, the week answers it for the days that are still winnable, and
    // "Your scores" answers the long question better than a dot grid ever
    // did, because it carries how the sits WENT and not only that they
    // happened. Profile was carrying two objects about the same thirty days.
    //
    // The cost, named: the photo-in-the-calendar idea (Aziz, 2026-09-15,
    // "those pictures can be shown in the calendar") loses its home here.
    // Every photo still appears, larger, on its own session card, which is
    // where somebody is actually looking at that sit.
    //
    // `MonthCalendar` is DELETED rather than left in DesignKit. An unused
    // view rots, and this one was already orphaned once this week by a commit
    // that moved it off Home and claimed it lived here.

    // MARK: - Log

    private var logSection: some View {
        let visible = selectedDay.map { day in
            sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        } ?? sessions
        let scores = SessionListSupport.scoreMap(allStats)
        let stats = SessionListSupport.statsMap(allStats)
        let ratings = SessionListSupport.ratingMap(reflections)
        // Reach, read off the reflection each session carries. Only when
        // there is somebody to share with: "Only you" on every row of a
        // build with no Friends tab is a label answering nobody's question.
        let reach: [UUID: Bool] = FeatureFlags.friends
            ? Dictionary(reflections.compactMap { r -> (UUID, Bool)? in
                guard let id = r.sessionID else { return nil }
                return (id, r.visibility == "friends")
              }, uniquingKeysWith: { a, _ in a })
            : [:]

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: selectedDay.map { SessionListSupport.dayTitle($0) } ?? "All sessions")
                    .contentTransition(.opacity)
                    .id(selectedDay ?? .distantPast)
                    .transition(.opacity)
                Spacer()
                if selectedDay != nil {
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            selectedDay = nil
                        }
                    } label: {
                        Text("Clear")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            if visible.isEmpty {
                Text(sessions.isEmpty
                     ? "No sessions yet. Tap the plus to start one."
                     : "No sessions that day.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 12)
            } else {
                let thumbs = photoThumbs
                VStack(spacing: 12) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { _, session in
                        NavigationLink {
                            SessionResultsView(sessionID: session.id)
                        } label: {
                            EvidenceRow(session: session,
                                        score: scores[session.id],
                                        stats: stats[session.id],
                                        rating: ratings[session.id],
                                        thumbnail: thumbs[session.id],
                                        shared: FeatureFlags.friends
                                            ? (reach[session.id] ?? false) : nil)
                        }
                        .buttonStyle(CardButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = session.id } label: {
                                Label("Delete session", systemImage: "trash")
                            }
                        }
                        // A deleted sit closes the gap it leaves instead of
                        // the list snapping shut under the finger.
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
                .deleteSessionDialog(pending: $pendingDelete)
                // Filtering to a day, and clearing it, is a change of
                // CONTENTS rather than a change of screen: the rows that
                // stay keep their place and the rest fade out around them.
                // A slide here would read as navigation to somewhere else.
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedDay)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: visible.count)
    }
}


/// Cards come up out of the grass, one after another.
///
/// The delay is in the ANIMATION rather than in a timer, so a card that is
/// already up when the next one starts is never re-laid-out, and turning the
/// page around (leaving the tab mid-flight) simply reverses whatever has run.
/// 55ms apart is enough to read as a sequence and short enough that the last
/// card is up in under half a second, which is the whole budget: a Profile
/// tab that takes a beat to assemble itself is slower than one that does not.
private extension View {
    func rising(_ settled: Bool, _ index: Int) -> some View {
        opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.9)
                        .delay(Double(index) * 0.055),
                       value: settled)
    }
}
