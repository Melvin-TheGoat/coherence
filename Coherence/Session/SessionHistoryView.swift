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


    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identity
                    VStack(alignment: .leading, spacing: 14) {
                        statsRow
                        scoresCard
                        awardsSection
                        logSection
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // The bar takes the sky's colour, otherwise there is a pale strip
            // above the scene with the gear floating in it and the gradient
            // starts a centimetre down the screen.
            .toolbarBackground(AppColor.sky, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)

            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    // MARK: - Identity

    private var currentUser: User? {
        users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
    }

    /// You, under the same sky Otto sits under on Home.
    ///
    /// It was a 64pt avatar on the left with three lines stacked beside it,
    /// which is the shape of a settings row, and a settings row is not a
    /// portrait. Centred at 86 with a white ring, everything that identifies
    /// you in one column beneath it, on the gradient Home uses, so the two
    /// tabs are visibly one app.
    private var identity: some View {
        let user = currentUser
        let friendsProfile = FeatureFlags.friends ? community.profile : nil
        let localName = user?.displayName?.isEmpty == false ? user!.displayName! : nil
        let name = localName ?? friendsProfile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName }
        // The reserved handle wins in Friends builds; the local one was cosmetic.
        let handle = Username.display(friendsProfile?.username ?? user?.username)
        return VStack(spacing: 3) {
            PersonAvatar(name: name, size: 86,
                         photoURL: FeatureFlags.friends ? community.profile?.avatarURL : nil)
                .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 5))
                .padding(.bottom, 9)
            Text(name ?? "Your practice")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            if let handle {
                Text(handle)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
            }
            if let since = user?.createdAt {
                Text("Practicing since \(since.formatted(.dateTime.month(.abbreviated).year()))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)
            }
            if FeatureFlags.friends, community.phase == .ready {
                FollowLine(followers: community.follow.followers,
                           following: community.follow.following,
                           personID: community.myID)
                    .padding(.top, 7)
            }
            if FeatureFlags.friends { profileActions.padding(.top, 13) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 2)
        .padding(.bottom, 24)
        .background {
            LinearGradient(colors: [AppColor.sky, AppColor.backgroundPrimary],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 38,
                                                  bottomTrailingRadius: 38,
                                                  style: .continuous))
        }
    }

    private func initials(_ name: String?) -> String {
        guard let name else { return "•" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    // MARK: - Profile actions (Friends)

    /// Edit profile (photo, nickname, @username) and Share profile (the
    /// invite), Strava's pair under the header.
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
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

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
    private var statsRow: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let hours = Double(sessions.reduce(0) { $0 + $1.durationSec }) / 3600
        return HStack(spacing: 0) {
            stat("\(streak.current)", "streak", AppColor.streakBlushText)
            divider
            stat("\(streak.longest)", "longest", AppColor.streakBlushText)
            divider
            stat("\(sessions.count)", "sits", AppColor.accentGoldText)
            divider
            stat(hours >= 10 ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours),
                 "practiced", AppColor.accentGoldText)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .fill(AppColor.backgroundSecondary)
                .shadow(color: AppColor.hairline, radius: 0, y: 2)
        )
    }

    private var divider: some View {
        Rectangle().fill(AppColor.hairline).frame(width: 1, height: 30)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The proof

    /// Your scores, one bar per sit.
    ///
    /// **This is the third home for this object and the first honest one.** It
    /// was a 46pt sparkline on Home directly above a calendar drawing thirty
    /// days, which is two things telling the same story at different
    /// resolutions; it was cut from there, and the commit claimed it "still
    /// lives on Profile", which it did not. Here it has the room to be read:
    /// twenty bars instead of seven points, with your average drawn across
    /// them so a single bar means something.
    ///
    /// Bars, not a line. A line implies the value between two sits, and there
    /// is no value between two sits: each one is a separate measurement of a
    /// separate morning. The average is the only continuous thing on the
    /// chart, so it is the only thing drawn as a line.
    private var scoresCard: some View {
        let map = SessionListSupport.scoreMap(allStats)
        let recent: [ScorePoint] = sessions
            .compactMap { session -> (date: Date, score: Double)? in
                guard let score = map[session.id] else { return nil }
                return (session.startedAt, score)
            }
            .prefix(16).reversed().enumerated()
            .map { ScorePoint(index: $0.offset, score: $0.element.score * 100, date: $0.element.date) }
        let average = recent.isEmpty ? 0 : recent.map(\.score).reduce(0, +) / Double(recent.count)
        let best = recent.map(\.score).max() ?? 0
        // `.ratio` sizes a bar against its category's step, and this chart's x
        // is a NUMBER, so the step is undefined and every bar drew at zero
        // width. Computed from the plot's own width instead, clamped so four
        // sits do not each become a paving slab.
        let barWidth = min(20.0, max(7.0, 286.0 / Double(max(recent.count, 1)) * 0.68))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your scores")
                Spacer()
                if recent.count >= 2 {
                    Text("last \(recent.count)")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            if recent.count < 2 {
                Text("Two sits and this fills in. Every bar is one morning, and the line is your average.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart {
                    ForEach(recent) { point in
                        // Fat and rounded. The default width draws hairline
                        // bars with wide gaps, which is a statistics plot; the
                        // rest of this app is made of solid round objects.
                        BarMark(x: .value("Sit", point.index),
                                y: .value("Score", point.score),
                                width: .fixed(barWidth))
                            .foregroundStyle(AppColor.accentGold)
                            .cornerRadius(7)
                    }
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(AppColor.calmAccent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) {
                        AxisGridLine().foregroundStyle(AppColor.hairline)
                        AxisValueLabel().foregroundStyle(AppColor.textSecondary)
                            .font(AppFont.caption)
                    }
                }
                .frame(height: 132)
                HStack(spacing: 0) {
                    proofStat("\(Int(average.rounded()))", "average", AppColor.calmAccent)
                    divider
                    proofStat("\(Int(best.rounded()))", "best", AppColor.accentGoldText)
                    divider
                    proofStat(SessionListSupport.duration(longestSit), "longest sit",
                              AppColor.accentGoldText)
                }
                .padding(.top, 2)
            }
        }
        .card(padding: 18)
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
                .font(.system(size: 18, weight: .bold, design: .rounded))
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

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: selectedDay.map { SessionListSupport.dayTitle($0) } ?? "All sessions")
                Spacer()
                if selectedDay != nil {
                    Button { selectedDay = nil } label: {
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
}
