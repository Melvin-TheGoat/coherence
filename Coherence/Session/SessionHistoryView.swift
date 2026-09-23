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
    /// The week the log is showing. Starts on the one today is in.
    @State private var weekStart = SessionCalendar.weekStart(for: Date())
    /// Set while the week picker is up.
    @State private var pickingWeek = false
    /// Which way the next week arrives from. Set BEFORE the week changes.
    @State private var back = false


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
        // **A day tapped on Home opens the week it is in**, rather than
        // filtering the log to that one day as it used to. The log is a week
        // now, so a one-day filter inside it would be a second, invisible
        // scope on top of the visible one. The day is consumed: Home's tap
        // chooses a week and the week's own controls take it from there.
        .onChange(of: selectedDay) { _, day in
            guard let day else { return }
            go(to: SessionCalendar.weekStart(for: day, calendar: calendar))
            selectedDay = nil
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

    /// You, on a white card with your picture on its seam.
    ///
    /// **Any picture you like, and Otto when you have not picked one**
    /// (Melvin, 2026-09-22: "the profile photo just a picture of whatever you
    /// want, either a selfie or from your library, and then can have otto be
    /// a default"). It was Otto for everybody for a day (Aziz, 2026-09-21:
    /// "no more pfp and make the sloth in the circle"), which told people
    /// apart by name and handle alone.
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

            ProfilePortrait(photoURL: friendsProfile?.avatarURL, size: 78)
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
            Text("Friends see your name, your streak and the sessions you post. Everything else stays here.")
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

    // MARK: - The log, one week at a time

    /// The sessions in the week on screen, newest first.
    private var weekSessions: [Session] {
        sessions.filter { SessionCalendar.isIn(week: weekStart, $0.startedAt, calendar: calendar) }
    }

    /// True when the week on screen is the one today is in, which is as far
    /// forward as the log can go.
    private var atCurrentWeek: Bool {
        weekStart >= SessionCalendar.weekStart(for: Date(), calendar: calendar)
    }

    /// **The card IS the week** (Aziz, 2026-09-21: "the list but you see it
    /// based off a weekly basis and then theres a calendar option to change
    /// the specifc week seamlessly").
    ///
    /// It replaced a stack of nineteen full-width cards, each with a 98pt
    /// picture panel that drew Otto whenever there was no selfie. Nineteen
    /// identical sloths down a page is wallpaper: nothing is scannable
    /// because every row weighs exactly what every other row weighs.
    ///
    /// A week rather than a month because a week is the unit this product
    /// already thinks in (one rest day per seven, Home's seven-day strip),
    /// and because a week of sessions fits on a screen without scrolling.
    private var logSection: some View {
        let visible = weekSessions
        let scores = SessionListSupport.scoreMap(allStats)
        // Reach, read off the reflection each session carries. Only when
        // there is somebody to share with: "Only you" on every row of a
        // build with no Friends tab is a label answering nobody's question.
        let reach: [UUID: Bool] = FeatureFlags.friends
            ? Dictionary(reflections.compactMap { r -> (UUID, Bool)? in
                guard let id = r.sessionID else { return nil }
                return (id, r.visibility == "friends")
              }, uniquingKeysWith: { a, _ in a })
            : [:]
        let thumbs = photoThumbs

        return VStack(spacing: 0) {
            weekHeader(count: visible.count,
                       minutes: visible.reduce(0) { $0 + $1.durationSec } / 60)

            // **One block, sliding as one thing.** The rows are given the
            // week's identity so SwiftUI replaces them wholesale instead of
            // diffing Tuesday against Tuesday, and the ZStack lets the
            // outgoing week leave across the incoming one rather than being
            // stacked under it. The card's height animates with them.
            //
            // NOT a paging `TabView`, which is the obvious tool and the
            // wrong one: paging forces every page to a single height, and a
            // week of one session is a fifth the height of a week of six.
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if visible.isEmpty {
                        // Four words and no advice. An empty week is a week
                        // you asked to see, not a failing, and the arrows
                        // are right there. No summary line either: "0
                        // sessions, 0 min" is a scoreboard of nothing.
                        Text(sessions.isEmpty
                             ? "No sessions yet. Tap the plus to start one."
                             : "No sessions this week.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .overlay(alignment: .top) { rowRule }
                    } else {
                        ForEach(visible) { session in
                            NavigationLink {
                                SessionResultsView(sessionID: session.id)
                            } label: {
                                MinutesRow(session: session,
                                           score: scores[session.id],
                                           thumbnail: thumbs[session.id],
                                           // **Only the shared ones are
                                           // marked.** Every row carried
                                           // "Only you" at first, which is
                                           // nine identical capsules down
                                           // one card: the same repetition
                                           // that got Otto taken off these
                                           // rows. A chip earns its space
                                           // when it marks the exception,
                                           // and posting is the exception.
                                           shared: reach[session.id] == true ? true : nil)
                                    .overlay(alignment: .top) { rowRule }
                            }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = session.id } label: {
                                    Label("Delete session", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .id(weekStart)
                .transition(.asymmetric(
                    insertion: .move(edge: back ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: back ? .trailing : .leading).combined(with: .opacity)))
            }
            // Clipped to the card, or a week slides out across the grass.
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
            // **The animation is named here, on the week, not left to the
            // `withAnimation` that changes it.** This card already sits
            // inside `rising`, whose `.animation(_:value: settled)` governs
            // the subtree, and the transition arrived with no animation at
            // all: three screenshots across a deliberately three-second
            // spring were byte-identical. An inner scope keyed to the week
            // wins back its own motion.
            .animation(Self.weekSpring, value: weekStart)
        }
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
        .shadow(color: AppColor.hairline, radius: 0, y: 2)
        .deleteSessionDialog(pending: $pendingDelete)
        // The whole card swipes, because it is the gesture anybody tries
        // first and the arrows are small. Committed past a third of the
        // width so a diagonal scroll never changes the week under you.
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    if value.translation.width < -60 { step(1) }
                    if value.translation.width > 60 { step(-1) }
                }
        )
        .sheet(isPresented: $pickingWeek) {
            WeekPicker(selected: weekStart,
                       practiced: SessionCalendar.practicedDays(from: sessions.map(\.startedAt),
                                                                calendar: calendar),
                       calendar: calendar) { picked in
                go(to: picked)
            }
            .presentationDetents([.height(352)])
            .presentationDragIndicator(.visible)
        }
    }

    /// A hairline between rows, drawn as an overlay on the row rather than a
    /// divider between them, so a row that leaves takes its own line with it
    /// and the list never flashes a double rule mid-animation.
    private var rowRule: some View {
        Rectangle().fill(AppColor.hairline).frame(height: 1)
    }

    /// Arrows, the week's name, and the two numbers a week is worth.
    private func weekHeader(count: Int, minutes: Int) -> some View {
        HStack(spacing: 8) {
            weekArrow("chevron.left", enabled: true) { step(-1) }

            Button { pickingWeek = true } label: {
                // **The name travels with its rows.** It cross-faded at
                // first, and a cross-fade between two pieces of TEXT is two
                // weeks legible on top of each other for the length of the
                // animation, which reads as a rendering fault rather than a
                // change. Given the same identity and the same transition as
                // the list, the whole card moves as one object.
                //
                // The fixed height is what keeps the arrows still: without
                // it the middle grows and shrinks as the summary line comes
                // and goes, and the two buttons bob with it.
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(SessionCalendar.weekTitle(weekStart, calendar: calendar))
                            .font(DisplayFont.display(16, .heavy))
                            .foregroundStyle(AppColor.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if count > 0 {
                        // The only two numbers a week is worth, and the line
                        // the chart above is made of.
                        (Text("\(count) session\(count == 1 ? "" : "s") · ")
                            .foregroundStyle(AppColor.textSecondary)
                         + Text("\(minutes) min").foregroundStyle(AppColor.accentGoldText).bold())
                            .font(AppFont.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .id(weekStart)
                .transition(.asymmetric(
                    insertion: .move(edge: back ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: back ? .trailing : .leading).combined(with: .opacity)))
                .frame(height: 38)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(CardButtonStyle())

            // Dimmed on the current week because there is nothing ahead of
            // today, and awake the moment you step back.
            weekArrow("chevron.right", enabled: !atCurrentWeek) { step(1) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .animation(Self.weekSpring, value: weekStart)
    }

    private func weekArrow(_ symbol: String, enabled: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppColor.backgroundPrimary, in: Circle())
        }
        .buttonStyle(CardButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.32)
    }

    /// The one spring the week travels on, named once so the header, the
    /// rows and the card's height cannot disagree about how fast a week
    /// changes.
    static let weekSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// One week forward or back.
    private func step(_ weeks: Int) {
        guard weeks < 0 || !atCurrentWeek else { return }
        go(to: SessionCalendar.week(weeks, from: weekStart, calendar: calendar))
    }

    /// Land on a week, sliding from the direction travelled.
    ///
    /// The direction is set BEFORE the week changes, so a jump three months
    /// back through the picker still reads as going backwards rather than as
    /// a cut. `selectedDay` is cleared on the way: a day highlighted inside
    /// a week you have left is a filter nobody can see.
    private func go(to start: Date) {
        guard start != weekStart else { return }
        back = start < weekStart
        withAnimation(Self.weekSpring) {
            weekStart = start
            selectedDay = nil
        }
    }
}

/// A session as a length, first (Aziz, 2026-09-22: "implement c").
///
/// The amber puck stands where the repeated Otto used to, so the row still
/// has an object on the left but it is the one fact a phone sit can report.
/// **It is the soft amber, not the accent**: seven saturated gold pucks down
/// a page would spend the one-gold-per-section rule seven times and leave
/// nothing on the screen emphasised. A tint is a material; the accent is a
/// decision.
private struct MinutesRow: View {
    let session: Session
    let score: Double?
    var thumbnail: UIImage? = nil
    var shared: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text("\(max(1, session.durationSec / 60))")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("MIN")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .opacity(0.75)
            }
            .foregroundStyle(AppColor.accentGoldText)
            .frame(width: 44, height: 44)
            .background(AppColor.accentGold.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SessionListSupport.relativeDay(session.startedAt))
                        .font(DisplayFont.display(15))
                        .foregroundStyle(AppColor.textPrimary)
                    if let shared { ReachChip(shared: shared) }
                }
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// What was playing, and the score if the session has one. **A phone sit
    /// is simply short a clause**, never "no score": naming the absence would
    /// be the row telling somebody what they are missing.
    private var subtitle: String {
        var parts: [String] = [SoundCatalog.title(for: session.frequencyID) ?? "Silence"]
        if let score { parts.append("scored \(Int(score * 100))") }
        return parts.joined(separator: " · ")
    }
}

/// Pick a WEEK, not a day.
///
/// **This is a picker, not a month view.** The repo deleted `MonthCalendar`
/// on purpose and the rule stands: a grid of dots as a STATUS display answers
/// "did I show up" at a resolution nobody needs, and it draws days that have
/// not happened yet. This grid exists only while you are choosing, it selects
/// rows rather than days, and its dots are there to answer the one question a
/// person actually arrives with, which is "which week was that".
private struct WeekPicker: View {
    let selected: Date
    let practiced: Set<Date>
    let calendar: Calendar
    let pick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var month: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(monthTitle)
                    .font(DisplayFont.display(17, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                arrow("chevron.left") { shiftMonth(-1) }
                arrow("chevron.right") { shiftMonth(1) }
            }
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            ForEach(Array(SessionCalendar.monthGrid(containing: month, calendar: calendar)
                            .enumerated()), id: \.offset) { _, week in
                weekRow(week)
            }

            Button {
                pick(SessionCalendar.weekStart(for: Date(), calendar: calendar))
                dismiss()
            } label: {
                Text("Jump to this week")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.accentGoldText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(CardButtonStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .onAppear { month = selected }
    }

    /// The whole row is one target, and it lights as one object, because the
    /// thing being chosen is the week and not a day inside it.
    private func weekRow(_ week: [Date]) -> some View {
        let start = week[0]
        let isSelected = start == selected
        return Button {
            pick(start)
            dismiss()
        } label: {
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 3) {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(calendar.isDateInToday(day)
                                             ? AppColor.accentGoldText : AppColor.textPrimary)
                        Circle()
                            .fill(practiced.contains(day) ? AppColor.accentGold : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .opacity(SessionCalendar.isSameMonth(day, as: month, calendar: calendar) ? 1 : 0.3)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppColor.backgroundSecondary : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? AppColor.accentGold : .clear, lineWidth: 2)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
    }

    private func arrow(_ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 28, height: 28)
                .background(AppColor.backgroundSecondary, in: Circle())
        }
        .buttonStyle(CardButtonStyle())
    }

    private func shiftMonth(_ by: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            month = calendar.date(byAdding: .month, value: by, to: month) ?? month
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = calendar.isDate(month, equalTo: Date(), toGranularity: .year)
            ? "MMMM" : "MMMM yyyy"
        return f.string(from: month)
    }

    /// Ordered from the calendar's own first weekday, so the letters sit over
    /// the columns they name in every locale.
    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + first) % 7] }
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
