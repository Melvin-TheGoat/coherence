import SwiftUI
import SwiftData

/// **Profile** — the far-right tab (2026-09-12): the person, then what they
/// have done. Identity on top (initials, name, handle, practicing since), the
/// four stats, the awards shelf, and the full log. Settings sits in the gear.
///
/// This was Journey. Its month picker moved to Home, whose calendar now opens
/// this tab filtered to the tapped day, so nothing was lost; the calendar just
/// stopped appearing twice.
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
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    if FeatureFlags.friends { profileActions }
                    statsRow
                    awardsSection
                    logSection
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
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

    private var identity: some View {
        let user = currentUser
        let friendsProfile = FeatureFlags.friends ? community.profile : nil
        let localName = user?.displayName?.isEmpty == false ? user!.displayName! : nil
        let name = localName ?? friendsProfile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName }
        // The reserved handle wins in Friends builds; the local one was cosmetic.
        let handle = Username.display(friendsProfile?.username ?? user?.username)
        return HStack(spacing: 14) {
            PersonAvatar(name: name, size: 64,
                         photoURL: FeatureFlags.friends ? community.profile?.avatarURL : nil)
            VStack(alignment: .leading, spacing: 3) {
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
                }
                if FeatureFlags.friends, community.phase == .ready {
                    FollowLine(followers: community.follow.followers,
                               following: community.follow.following,
                               personID: community.myID)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
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
        HStack(spacing: 8) {
            Button { editingProfile = true } label: { Label("Edit profile", systemImage: "pencil") }
                .buttonStyle(SecondaryButtonStyle())
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

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Awards · \(earned.count) of \(items.count)")
                Spacer()
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
                        VStack(spacing: 6) {
                            AwardBadge(award: item.award, earned: item.isEarned, size: 54)
                            Text(item.award.title)
                                .font(.system(size: 9.5, weight: .medium))
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
    }

    // MARK: - Stats

    private var statsRow: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let hours = Double(sessions.reduce(0) { $0 + $1.durationSec }) / 3600
        return HStack(spacing: 8) {
            stat("\(streak.current)", "streak")
            stat("\(streak.longest)", "longest")
            stat("\(sessions.count)", "sessions")
            stat(hours >= 10 ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours), "practiced")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentGoldText)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

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
