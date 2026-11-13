import SwiftUI
import SwiftData
import AVKit

/// The Friends feed (Melvin, 2026-11-13, `mockups/friends-v3.html`, style A).
///
/// Friends has its own tab again, and the tab is a feed of your friends'
/// sessions, Strava's shape: who and when, a bold title, Time · Streak ·
/// Sound, a photo when they took one, and kudos. **Never a score, a heart
/// rate or anything measured** (5.1.3), and no leaderboard.
///
/// It replaced the friends list as the first screen; the list and search
/// moved one tap in, behind "N friends" in the header
/// (`FriendsDirectoryView`). The feed is loaded on its own path
/// (`CommunityModel.refreshFeed`) so a missing Post index can never take the
/// friends list down with it.

// MARK: - Pure helpers (tested)

/// Posts grouped by the day they were practiced, newest first, the way the
/// feed draws them.
enum FeedDays {
    struct Day: Identifiable, Equatable {
        let start: Date
        let title: String
        let posts: [Post]
        var id: Date { start }
    }

    static func group(_ posts: [Post], now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let byDay = Dictionary(grouping: posts) { calendar.startOfDay(for: $0.practicedAt) }
        return byDay.keys.sorted(by: >).map { day in
            Day(start: day, title: title(for: day, now: now, calendar: calendar),
                posts: (byDay[day] ?? []).sorted { $0.practicedAt > $1.practicedAt })
        }
    }

    static func title(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: y) {
            return "Yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day)
    }
}

/// The small chip on every post: whether 808 timed it, or it was typed in
/// with Record one.
enum PostChip {
    static func label(logged: Bool) -> String { logged ? "Logged" : "✓ Timed in 808" }
}

/// The "Aziz meditated. Your turn." strip: a running goal whose partner has
/// meditated today when I have not.
enum YourTurn {
    static func pick(_ goals: [GoalPair], today: String) -> GoalPair? {
        goals.first { g in
            g.state == .active
                && g.theirDays.contains { $0.day == today }
                && !g.myDays.contains { $0.day == today }
        }
    }
}

/// A friend's Otto on their avatar: which of the seven glow stills, and
/// whether its ring is lit, from what their profile publishes about how
/// often they meditate. Only sessions, never a score.
enum FeedBadge {
    /// Plain values rather than `PracticeStats`, which the test target
    /// compiles a second copy of (the Shared/ trap).
    static func stage(sessions7d: Int, lastSessionAt: Date?, now: Date = Date()) -> Int {
        guard let last = lastSessionAt else { return 3 }
        if now.timeIntervalSince(last) > 3 * 86_400 { return 2 }
        switch sessions7d {
        case 0: return 3
        case 1...2: return 4
        case 3...4: return 5
        case 5...6: return 6
        default: return 7
        }
    }

    /// Meditated in the last day and a half.
    static func glowing(lastSessionAt: Date?, now: Date = Date()) -> Bool {
        guard let last = lastSessionAt else { return false }
        return now.timeIntervalSince(last) < 36 * 3_600
    }
}

/// Who gave kudos, in words: "You, Aziz and Melvin".
enum KudosLine {
    static func text(names: [String], mine: Bool, isMyPost: Bool) -> String {
        var list = names
        if mine { list.insert("You", at: 0) }
        switch list.count {
        case 0: return isMyPost ? "No kudos yet" : "Double tap to give kudos"
        case 1: return list[0]
        case 2: return "\(list[0]) and \(list[1])"
        case 3: return "\(list[0]), \(list[1]) and \(list[2])"
        default: return "\(list[0]), \(list[1]) and \(list.count - 2) others"
        }
    }
}

// MARK: - The feed

struct FeedOpen: Hashable { let id: String }

struct FriendsHomeView: View {
    @ObservedObject var model: CommunityModel
    let myDisplayName: String
    /// The screen is a sheet with a close button in the top-left corner.
    var roomForClose = false

    @EnvironmentObject private var slam: KudosSlam
    @State private var reportTarget: ReportSheet.Target?
    @State private var openPost: FeedOpen?
    @State private var startingGoal = false

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band(top: top)
                    VStack(alignment: .leading, spacing: 14) {
                        #if DEBUG
                        if model.testMode && !StoreShots.on { testModePill }
                        #endif
                        if !model.uploading.isEmpty { postingPill }
                        if let goal = YourTurn.pick(model.goals, today: DayKey.key(Date())) {
                            YourTurnStrip(model: model, goal: goal)
                        }
                        if !model.togetherGoals.isEmpty {
                            TogetherSection(model: model) {
                                Analytics.track(.goalStartOpened(source: "together_add"))
                                startingGoal = true
                            }
                        }
                        feedSection
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 14)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            .modifier(StatusBarScrim(height: top, threshold: 100))
            .refreshable { await model.refresh() }
            #if DEBUG
            // PREVIEW_FEED_SCROLL=<n> scrolls to the nth post; PREVIEW_POST=<n>
            // opens it. For screenshots without a finger.
            .task(id: model.feed.count) {
                let env = ProcessInfo.processInfo.environment
                guard !model.feed.isEmpty else { return }
                try? await Task.sleep(for: .seconds(1))
                if let n = env["PREVIEW_FEED_SCROLL"].flatMap(Int.init), n < model.feed.count {
                    reader.scrollTo(model.feed[n].id, anchor: .top)
                }
                if let n = env["PREVIEW_POST"].flatMap(Int.init), n < model.feed.count, openPost == nil {
                    openPost = FeedOpen(id: model.feed[n].id)
                }
            }
            #endif
            }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { id in
            PersonView(id: id, model: model)
        }
        .navigationDestination(for: FriendsRoute.self) { route in
            switch route {
            case .requests: RequestsView(model: model)
            case .directory: FriendsDirectoryView(model: model)
            }
        }
        .navigationDestination(for: GoalRoute.self) { route in
            switch route {
            case .goal(let id): GoalDetailView(model: model, goalID: id)
            case .invite(let id): GoalInviteDetailView(model: model, goalID: id)
            }
        }
        .navigationDestination(item: $openPost) { open in
            PostDetailView(model: model, postID: open.id)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, model: model)
        }
        .sheet(isPresented: $startingGoal) { GoalStartFlow(model: model) }
        .modifier(PicturePromptHook(model: model, blocked: startingGoal || reportTarget != nil))
        .onAppear { model.markNewsSeen() }
        .onChange(of: model.unseenCount) { _, n in if n > 0 { model.markNewsSeen() } }
        #if DEBUG
        .task { await previewKudos() }
        #endif
    }

    @ViewBuilder
    private var feedSection: some View {
        if model.friends.isEmpty && model.feed.isEmpty {
            EmptyFriends(model: model, username: model.profile?.username ?? "")
        } else if model.feed.isEmpty {
            EmptyFeed(model: model, failed: model.feedFailed)
        } else {
            ForEach(FeedDays.group(model.feed)) { day in
                GrassHeading(title: day.title)
                ForEach(day.posts) { post in
                    PostCard(post: post, model: model,
                             onOpen: { openPost = FeedOpen(id: post.id) },
                             onReport: { reportTarget = .post(post.id) })
                        .id(post.id)
                }
            }
            InviteCodeButton(model: model, style: .wide, source: "feed")
                .padding(.top, 6)
        }
    }

    /// The title, your handle and "N friends", Requests and Invite, in the sky.
    private func band(top: CGFloat) -> some View {
        FriendsSky(height: top + 116, sceneHeight: (top + 116) / 0.62) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Friends")
                            .font(DisplayFont.display(30, .heavy))
                            .onValley()
                        HStack(spacing: 6) {
                            if let handle = model.profile.map({ "@" + $0.username }), handle.count > 1 {
                                Text(handle)
                                    .font(AppFont.caption.weight(.semibold))
                                    .onValley(soft: true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            NavigationLink(value: FriendsRoute.directory) {
                                HStack(spacing: 3) {
                                    Text(model.friends.isEmpty ? "Find friends"
                                         : "\(model.friends.count) friend\(model.friends.count == 1 ? "" : "s")")
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                                }
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ValleyGround.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(AppColor.backgroundPrimary.opacity(0.94))
                                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1))
                            }
                            .buttonStyle(.tactile)
                            .fixedSize()
                        }
                    }
                    .padding(.leading, roomForClose ? 44 : 0)
                    .layoutPriority(-1)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        requestsButton
                        InviteCodeButton(model: model, source: "header")
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, top + 10)
                Spacer(minLength: 0)
            }
        }
    }

    /// Gold when somebody is waiting on the reader, a cream pill otherwise.
    /// Pushed by value, like every link in this stack (2026-10-01).
    private var requestsButton: some View {
        NavigationLink(value: FriendsRoute.requests) {
            let count = model.incoming.count + model.goalInvites.count
            let waiting = count > 0
            Text(waiting ? "\(count) request\(count == 1 ? "" : "s")" : "Requests")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(waiting ? AppColor.textOnAccent : ValleyGround.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if waiting {
                        Capsule().fill(AppColor.accentGold)
                            .shadow(color: AppColor.accentGoldShade, radius: 0, y: 3)
                    } else {
                        Capsule().fill(AppColor.backgroundPrimary.opacity(0.94))
                            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    }
                }
                .padding(.bottom, 3)
        }
    }

    /// A post still uploading after its session page closed
    /// (`CommunityModel.postInBackground`).
    private var postingPill: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(AppColor.skyDeep)
            Text(model.uploading.count == 1 ? "Posting your session…"
                                            : "Posting \(model.uploading.count) sessions…")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(ValleyGround.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
    }

    #if DEBUG
    private var testModePill: some View {
        HStack(spacing: 8) {
            Text("Test mode: a fake database on this device")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(ValleyGround.inkSoft)
            Spacer(minLength: 0)
            Button("Turn off") { Task { await model.setTestMode(false) } }
                .buttonStyle(.tactile)
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.skyDeep)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
    }

    /// `PREVIEW_KUDOS=1` replays the slam on the first friend's post, over
    /// and over, so it can be reviewed and screen recorded without a finger.
    /// `PREVIEW_KUDOS_SLOW=<n>` plays it n times slower.
    private func previewKudos() async {
        guard ProcessInfo.processInfo.environment["PREVIEW_KUDOS"] == "1" else { return }
        for round in 0..<40 {
            try? await Task.sleep(for: .seconds(round == 0 ? 1.6 : 2.4 * KudosSlam.slow))
            guard !Task.isCancelled else { return }
            guard let post = model.feed.first(where: { $0.author != model.myID }), let me = model.myID else { continue }
            let emoji = Kudos.choices[round % Kudos.choices.count]
            // The preview takes mine back first so the count visibly ticks
            // up every time.
            let others = (model.reactions[post.id] ?? []).filter { $0.author != me }
            model.previewSetKudos(others, on: post.id)
            slam.fire(postID: post.id, emoji: emoji) {
                model.previewSetKudos(others + [Reaction(post: post.id, author: me, emoji: emoji)], on: post.id)
            }
        }
    }
    #endif
}

/// "Aziz meditated. Your turn." The one nudge worth its space: somebody you
/// made a promise to already went today. Gone the moment you meditate.
struct YourTurnStrip: View {
    @ObservedObject var model: CommunityModel
    let goal: GoalPair

    var body: some View {
        let name = (model.person(goal.partner)?.displayName).flatMap { $0.split(separator: " ").first.map(String.init) } ?? "Your friend"
        let week = goal.thisWeek(today: DayKey.key(Date()))
        HStack(spacing: 12) {
            ProfilePortrait(photoURL: model.person(goal.partner)?.avatarURL, size: 38)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) meditated. Your turn.")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let week {
                    Text("Your goal this week: you \(week.mine), \(name) \(week.theirs) of \(goal.target)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button {
                Analytics.track(.goalMeditateTapped)
                NotificationCenter.default.post(name: .openMeditate, object: nil)
            } label: {
                Text("Meditate")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(OnboardingGreen.fill)
                        .shadow(color: OnboardingGreen.shade, radius: 0, y: 2))
            }
            .buttonStyle(.tactileMain)
        }
        .padding(12)
        .whiteCard(radius: 18)
    }
}

private struct EmptyFeed: View {
    @ObservedObject var model: CommunityModel
    let failed: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("🧘").font(.system(size: 40)).padding(.top, 8)
            Text("Your friends' sessions show up here")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(failed ? "Couldn't load sessions just now. Pull down to try again."
                        : "When a friend posts after meditating, you'll see it here and can give them kudos.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            InviteCodeButton(model: model, style: .wide, source: "empty_feed")
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .whiteCard()
    }
}

// MARK: - A post

/// A friend's session, Strava's activity card (style A): avatar with their
/// Otto, name and when, the chip, a bold title, Time · Streak · Sound, the
/// photo inset in the card, then kudos. A post with no photo is the stats
/// card alone and still reads as a whole post.
///
/// Double tap anywhere gives 🙏 with the slam (`KudosSlam`); a single tap
/// opens the full post.
struct PostCard: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onOpen: () -> Void
    let onReport: () -> Void

    @EnvironmentObject private var slam: KudosSlam
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmBlock = false
    /// The header, title and stats, measured, so the photo can be capped.
    @State private var aboveHeight: CGFloat = 150

    static let inset: CGFloat = 16

    private var isMine: Bool { post.author == model.myID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PostHeader(post: post, model: model, onReport: onReport, onBlock: { confirmBlock = true })
                    .padding(.horizontal, Self.inset).padding(.top, Self.inset)
                Text(post.title.isEmpty ? "Meditation" : post.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .padding(.horizontal, Self.inset).padding(.top, 12)
                PostStats(post: post)
                    .padding(.horizontal, Self.inset).padding(.top, 12)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aboveHeight = $0 }
            if let first = post.media.first {
                // Never more than twice the words above it (Melvin,
                // 2026-11-13): a tall selfie made every post enormous.
                PostPhotoView(item: first, extra: post.media.count - 1,
                              maxHeight: max(140, aboveHeight * 2))
                    .padding(.horizontal, Self.inset).padding(.top, 14)
            }
            KudosRow(post: post, model: model, context: "feed")
                .padding(.horizontal, Self.inset).padding(.top, 14).padding(.bottom, Self.inset)
        }
        .whiteCard(radius: 20)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTap() }
        .onTapGesture { onOpen() }
        .accessibilityAction(named: "Give kudos") { doubleTap() }
        .confirmationDialog(blockTitle, isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await model.block(post.author) } }
        } message: {
            Text("They won't be told. You won't see each other's sessions, and they can't send you a request.")
        }
    }

    private var blockTitle: String {
        "Block \(model.person(post.author)?.displayName ?? "this person")?"
    }

    private func doubleTap() {
        guard !isMine else { return }
        let emoji = model.myKudos(on: post.id) ?? Kudos.standard
        KudosSlam.give(model: model, slam: slam, postID: post.id, emoji: emoji, via: "double_tap",
                       context: "feed", reduceMotion: reduceMotion)
    }
}

/// Avatar with their Otto, name, when and the sound, the chip, and the ⋯ menu.
struct PostHeader: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onReport: () -> Void
    let onBlock: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var author: Profile? { model.person(post.author) }
    private var isMine: Bool { post.author == model.myID }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NavigationLink(value: post.author) {
                HStack(spacing: 11) {
                    FeedAvatar(profile: isMine ? (model.profile ?? author) : author, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isMine ? "You" : displayName)
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(when)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                            ChipView(logged: post.logged)
                        }
                    }
                }
            }
            .buttonStyle(CardButtonStyle())
            Spacer(minLength: 4)
            Menu {
                if isMine {
                    if let onEdit { Button("Edit post", action: onEdit) }
                    Button("Delete post", role: .destructive) {
                        if let onDelete { onDelete() } else { Task { await model.deletePost(post.id) } }
                    }
                } else {
                    Button("Report post", role: .destructive, action: onReport)
                    Button("Block \(author?.displayName.isEmpty == false ? author!.displayName : "this person")",
                           role: .destructive, action: onBlock)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
    }

    private var displayName: String {
        if let name = author?.displayName, !name.isEmpty { return name }
        return author.map { "@" + $0.username } ?? "Someone"
    }

    /// "Today, 7:12 AM · Rain".
    private var when: String {
        let time = post.practicedAt.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(post.practicedAt) ? "Today"
            : Calendar.current.isDateInYesterday(post.practicedAt) ? "Yesterday"
            : post.practicedAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(day), \(time)"
    }
}

/// "✓ Timed in 808" or "Logged".
struct ChipView: View {
    let logged: Bool
    var body: some View {
        Text(PostChip.label(logged: logged))
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(logged ? AppColor.textSecondary : AppColor.skyDeep)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(logged ? AppColor.trace : AppColor.skyWash))
    }
}

/// Time · Streak · Sound, value over label, three equal columns.
struct PostStats: View {
    let post: Post
    var body: some View {
        HStack(spacing: 0) {
            column("\(post.minutes) min", "Time")
            divider
            column(post.streak > 0 ? "🔥 \(post.streak)" : "1", "Day streak")
            divider
            column(post.sound ?? post.technique ?? "Silence", "Sound")
        }
    }

    private var divider: some View {
        Rectangle().fill(ValleyGround.quiet).frame(width: 1, height: 28)
    }

    private func column(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(DisplayFont.display(16, .heavy))
                .foregroundStyle(ValleyGround.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, label == "Time" ? 0 : 12)
    }
}

/// Their face, with their Otto as a small badge, ringed in glow when they
/// have meditated lately (the mockup's "bright gold when they are glowing,
/// faint when they are not").
struct FeedAvatar: View {
    let profile: Profile?
    var size: CGFloat = 44

    var body: some View {
        let practice = profile?.practice ?? .empty
        let glowing = FeedBadge.glowing(lastSessionAt: practice.lastSessionAt)
        let badge = size * 0.48
        ProfilePortrait(photoURL: profile?.avatarURL, size: size)
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(AppColor.sky)
                    SitArt(name: "OttoAura\(FeedBadge.stage(sessions7d: practice.sessions7d, lastSessionAt: practice.lastSessionAt))", size: badge * 1.05)
                        .offset(y: badge * 0.12)
                }
                .frame(width: badge, height: badge)
                .clipShape(Circle())
                .overlay(Circle().stroke(glowing ? AppColor.accentGold : AppColor.hairline,
                                         lineWidth: glowing ? 2.2 : 1.5))
                .shadow(color: glowing ? AppColor.accentGold.opacity(0.55) : .clear, radius: 4)
                .offset(x: badge * 0.28, y: badge * 0.2)
            }
            .padding(.trailing, badge * 0.28)
            .accessibilityHidden(true)
    }
}

/// A post's picture inside the card: its own shape, clamped so a tall
/// selfie never runs the card off the screen, rounded and inset like the
/// words. "+2" when there are more, which the full post shows.
struct PostPhotoView: View {
    let item: Post.PostMedia
    var extra: Int = 0
    var full = false
    /// The tallest the photo may be in the feed; it crops to fill instead.
    var maxHeight: CGFloat? = nil
    @State private var image: UIImage?
    @State private var width: CGFloat = 0

    var body: some View {
        let aspect = CGFloat(item.aspect > 0 ? item.aspect : 0.75)
        let shown = full ? aspect : min(max(aspect, 0.8), 1.6)
        let natural = width > 0 ? width / shown : nil
        Color(AppColor.trace)
            .frame(maxWidth: .infinity)
            .frame(height: natural.map { min($0, maxHeight ?? .infinity) })
            .aspectRatio(natural == nil ? shown : nil, contentMode: .fit)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(10)
                }
            }
            .task(id: item.posterURL) {
                let url = full ? (item.url ?? item.posterURL) : (item.posterURL ?? item.url)
                image = url.flatMap { UIImage(contentsOfFile: $0.path) }
            }
            .accessibilityLabel("Photo")
    }
}

// MARK: - Kudos

/// One chip per kudos given, with its count, mine lit; a + to pick one; and
/// who gave them, in words. On my own post the chips only count.
struct KudosRow: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    /// Which copy of the row this is ("feed" or "detail"), so the slam lands
    /// on the one on screen.
    let context: String

    @EnvironmentObject private var slam: KudosSlam
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMine: Bool { post.author == model.myID }

    var body: some View {
        let list = model.reactions[post.id] ?? []
        let mine = model.myKudos(on: post.id)
        let counts = Kudos.choices.compactMap { e -> (String, Int)? in
            let n = list.filter { $0.emoji == e }.count
            return n > 0 ? (e, n) : nil
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ForEach(counts, id: \.0) { emoji, n in
                    Button { tapChip(emoji, mine: mine) } label: {
                        HStack(spacing: 4) {
                            Text(emoji).font(.system(size: 16))
                            Text("\(n)")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(n)))
                                .foregroundStyle(mine == emoji ? AppColor.skyDeep : ValleyGround.ink)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(mine == emoji ? AppColor.skyWash : AppColor.backgroundPrimary))
                        .overlay(Capsule().stroke(mine == emoji ? AppColor.skyDeep : ValleyGround.quiet,
                                                 lineWidth: mine == emoji ? 1.6 : 1))
                    }
                    .buttonStyle(.tactile)
                    .disabled(isMine)
                    .accessibilityLabel("\(emoji) \(n)")
                }
                if !isMine {
                    Menu {
                        ForEach(Kudos.choices, id: \.self) { e in
                            Button(e) { give(e, via: "picker") }
                        }
                    } label: {
                        Text(counts.isEmpty ? "🙏 Give kudos" : "＋")
                            .font(.system(size: counts.isEmpty ? 14 : 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.skyDeep)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(AppColor.backgroundPrimary))
                            .overlay(Capsule().stroke(ValleyGround.quiet, lineWidth: 1))
                    }
                    .accessibilityLabel("Give kudos")
                }
                Spacer(minLength: 0)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.7), value: list)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                slam.targets[post.id + "|" + context] = $0
            }
            Text(KudosLine.text(names: list.filter { $0.author != model.myID }.map(name),
                                mine: mine != nil, isMyPost: isMine))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
    }

    private func name(_ r: Reaction) -> String {
        let n = model.person(r.author)?.displayName ?? ""
        return n.isEmpty ? (model.person(r.author).map { "@" + $0.username } ?? "Someone") : n
    }

    private func tapChip(_ emoji: String, mine: String?) {
        if mine == emoji { Task { await model.removeKudos(post.id) } } else { give(emoji, via: "picker") }
    }

    private func give(_ emoji: String, via: String) {
        KudosSlam.give(model: model, slam: slam, postID: post.id, emoji: emoji, via: via,
                       context: context, reduceMotion: reduceMotion)
    }
}

// MARK: - The slam

/// Kudos land with weight (Melvin, 2026-11-13): the emoji appears huge over
/// the screen, hangs, then SLAMS down onto the post's kudos row, squashing on
/// impact with a burst and a heavy haptic, and the count ticks up as it
/// lands. Drawn by `KudosSlamLayer` over the whole Friends stack from one
/// clock, so every frame is a pure function of time.
@MainActor
final class KudosSlam: ObservableObject {
    struct Shot: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let start: Date
        /// Where the row is, in global space.
        let target: CGRect
    }

    @Published var shot: Shot?
    /// The kudos rows on screen, by "post|context", in global space.
    var targets: [String: CGRect] = [:]

    /// How much slower than life to play it (`PREVIEW_KUDOS_SLOW`, DEBUG).
    static var slow: Double {
        #if DEBUG
        return Double(ProcessInfo.processInfo.environment["PREVIEW_KUDOS_SLOW"] ?? "") ?? 1
        #else
        return 1
        #endif
    }

    /// The timeline, in seconds at normal speed.
    static let appear = 0.16, hang = 0.30, impact = 0.52, done = 1.05

    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    /// Gives kudos with the slam: the model is told at impact, so the count
    /// ticks up as the emoji lands. Under Reduce Motion it is given at once.
    static func give(model: CommunityModel, slam: KudosSlam, postID: String, emoji: String, via: String,
                     context: String, reduceMotion: Bool) {
        let apply = { Task { await model.giveKudos(postID, emoji: emoji, via: via) } }
        if reduceMotion {
            if Tactile.hapticsOn { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            _ = apply()
            return
        }
        slam.fire(postID: postID, emoji: emoji, context: context) { _ = apply() }
    }

    func fire(postID: String, emoji: String, context: String = "feed", onImpact: @escaping () -> Void) {
        guard let target = targets[postID + "|" + context] ?? targets[postID + "|feed"] else { onImpact(); return }
        heavy.prepare()
        let shot = Shot(emoji: emoji, start: Date(), target: target)
        self.shot = shot
        let slow = Self.slow
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.impact * slow))
            if Tactile.hapticsOn { heavy.impactOccurred(intensity: 1) }
            onImpact()
            try? await Task.sleep(for: .seconds((Self.done - Self.impact) * slow + 0.05))
            if self.shot?.id == shot.id { self.shot = nil }
        }
    }
}

/// Draws the slam. Placed over the whole stack, ignoring the safe area, so
/// global coordinates are its own after one offset.
struct KudosSlamLayer: View {
    @ObservedObject var slam: KudosSlam
    @State private var origin: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            if let shot = slam.shot {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(shot.start) / KudosSlam.slow
                    canvas(shot: shot, t: t, size: geo.size)
                }
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func canvas(shot: KudosSlam.Shot, t: Double, size: CGSize) -> some View {
        let f = SlamFrame.at(t: t, from: CGPoint(x: size.width / 2, y: size.height * 0.42),
                             to: CGPoint(x: shot.target.minX - origin.x + 26, y: shot.target.midY - origin.y))
        ZStack {
            // The light that goes up as it appears, dimming the feed behind.
            Color.black.opacity(f.dim)
            // The ring and the burst at the impact point.
            if f.burst > 0 {
                Circle()
                    .stroke(AppColor.accentGold.opacity(0.7 * (1 - f.burst)), lineWidth: 3 * (1 - f.burst) + 0.5)
                    .frame(width: 20 + 90 * f.burst, height: 20 + 90 * f.burst)
                    .position(f.impactPoint)
                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10 * 2 * .pi + 0.3
                    let r = 14 + 62 * f.burst
                    Group {
                        if i % 3 == 0 {
                            Text(shot.emoji).font(.system(size: 13))
                        } else {
                            Circle().fill(i % 2 == 0 ? AppColor.accentGold : AppColor.skyDeep)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .position(x: f.impactPoint.x + cos(angle) * r, y: f.impactPoint.y + sin(angle) * r * 0.8)
                    .opacity(1 - f.burst)
                    .scaleEffect(1 - 0.5 * f.burst)
                }
            }
            Text(shot.emoji)
                .font(.system(size: 64))
                .shadow(color: .black.opacity(0.25 * f.shadow), radius: 18 * f.shadow, y: 12 * f.shadow)
                .scaleEffect(x: f.scale * f.squashX, y: f.scale * f.squashY, anchor: .bottom)
                .rotationEffect(.degrees(f.rotation))
                .position(f.point)
                .opacity(f.opacity)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One frame of the slam, pure: where the emoji is, how big, how turned and
/// squashed, and how far the burst has spread. Tested for its landmarks.
struct SlamFrame: Equatable {
    var point: CGPoint
    var impactPoint: CGPoint
    var scale: CGFloat
    var squashX: CGFloat
    var squashY: CGFloat
    var rotation: Double
    var opacity: Double
    var dim: Double
    var shadow: Double
    var burst: Double

    /// Scale of the 64pt glyph: huge while it hangs, row-sized on landing.
    static let bigScale: CGFloat = 3.6
    static let landScale: CGFloat = 0.36

    static func at(t: Double, from: CGPoint, to: CGPoint) -> SlamFrame {
        let appear = KudosSlam.appear, hang = KudosSlam.hang, impact = KudosSlam.impact, done = KudosSlam.done
        var f = SlamFrame(point: from, impactPoint: to, scale: bigScale, squashX: 1, squashY: 1, rotation: -10,
                          opacity: 1, dim: 0.12, shadow: 1, burst: 0)
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        if t < appear {
            // Pops in: from small, overshooting a little.
            let p = clamp(t / appear)
            let back = 1 + 2.4 * pow(p - 1, 3) + 1.4 * pow(p - 1, 2)
            f.scale = 0.4 + (bigScale - 0.4) * CGFloat(back)
            f.opacity = p
            f.dim = 0.12 * p
            f.rotation = -22 + 12 * p
        } else if t < hang {
            // Hangs, breathing in, tilting back to wind up.
            let p = clamp((t - appear) / (hang - appear))
            f.scale = bigScale * CGFloat(1 + 0.06 * sin(p * .pi))
            f.rotation = -10 - 6 * p
        } else if t < impact {
            // The slam: accelerating down onto the row, shrinking as it goes.
            let p = clamp((t - hang) / (impact - hang))
            let e = p * p * p
            f.point = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
            f.scale = bigScale + (landScale - bigScale) * CGFloat(e)
            f.rotation = -16 + 24 * e
            f.dim = 0.12 * (1 - p)
            f.shadow = 1 - p
        } else {
            // Impact: squash, rebound past round, settle, and fade into the
            // row, which now shows the kudos itself.
            let p = clamp((t - impact) / (done - impact))
            f.point = to
            f.dim = 0
            f.shadow = 0
            f.burst = clamp((t - impact) / 0.42)
            let squash = exp(-7 * p) * cos(p * 3.2 * .pi)
            f.squashX = CGFloat(1 + 0.38 * squash)
            f.squashY = CGFloat(1 - 0.34 * squash)
            f.scale = landScale * CGFloat(1 + 0.25 * sin(min(p * 2.2, 1) * .pi) * (1 - p))
            f.rotation = 8 * (1 - p) * cos(p * 4 * .pi)
            f.opacity = p < 0.55 ? 1 : max(0, 1 - (p - 0.55) / 0.45)
        }
        return f
    }
}

// MARK: - The full post

/// A post at full size: every photo full width, the stats, all the kudos and
/// who gave which. Its ⋯ holds Report and Block, or Edit and Delete on your
/// own (`mockups/friends-v3.html`, the post detail).
struct PostDetailView: View {
    @ObservedObject var model: CommunityModel
    let postID: String

    @EnvironmentObject private var slam: KudosSlam
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var reportTarget: ReportSheet.Target?
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var editing: EditTarget?
    @State private var viewer: ViewerStart?

    private struct EditTarget: Identifiable { let id: UUID }
    private struct ViewerStart: Identifiable { let id: Int }

    /// The live post, or the last copy seen, so a feed reload in flight
    /// never blanks the page under the reader.
    @State private var lastSeen: Post?
    @Environment(\.tabBarClearance) private var tabBarClearance
    private var post: Post? { model.feed.first { $0.id == postID } ?? lastSeen }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FriendsSky(height: proxy.safeAreaInsets.top + 56) { EmptyView() }
                    if let post {
                        content(post).padding(.horizontal, AppMetrics.screenPadding).padding(.top, 14)
                    } else {
                        Text("This session isn't shared any more.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .whiteCard()
                            .padding(AppMetrics.screenPadding)
                    }
                }
                .padding(.bottom, 30 + tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .onAppear { lastSeen = model.feed.first { $0.id == postID } ?? lastSeen }
        .onChange(of: model.feed) { _, feed in
            if let live = feed.first(where: { $0.id == postID }) { lastSeen = live }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $reportTarget) { target in ReportSheet(target: target, model: model) }
        .sheet(item: $editing) { target in
            SaveSessionView(sessionID: target.id, mode: .edit) { editing = nil }
        }
        .fullScreenCover(item: $viewer) { start in
            PostMediaViewer(media: post?.media ?? [], startIndex: start.id)
        }
        .confirmationDialog("Block \(post.flatMap { model.person($0.author)?.displayName } ?? "this person")?",
                            isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                guard let author = post?.author else { return }
                Task { await model.block(author); lastSeen = nil; dismiss() }
            }
        } message: {
            Text("They won't be told. You won't see each other's sessions, and they can't send you a request.")
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) {
                Task { await model.deletePost(postID); lastSeen = nil; dismiss() }
            }
        } message: {
            Text("Friends won't see it any more. The session stays in your history.")
        }
    }

    @ViewBuilder
    private func content(_ post: Post) -> some View {
        let mine = post.author == model.myID
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                PostHeader(post: post, model: model,
                           onReport: { reportTarget = .post(post.id) },
                           onBlock: { confirmBlock = true },
                           onEdit: editableSessionID(post).map { sid in { editing = EditTarget(id: sid) } },
                           onDelete: { confirmDelete = true })
                Text(post.title.isEmpty ? "Meditation" : post.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 14)
                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 6)
                }
                PostStats(post: post).padding(.top, 14)
                ForEach(post.media) { item in
                    PostPhotoView(item: item, full: true)
                        .overlay {
                            if item.kind == .video {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 4)
                            }
                        }
                        .padding(.top, 14)
                        .onTapGesture { viewer = ViewerStart(id: item.index) }
                }
                KudosRow(post: post, model: model, context: "detail").padding(.top, 16)
            }
            .padding(PostCard.inset)
            .whiteCard(radius: 20)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !mine else { return }
                KudosSlam.give(model: model, slam: slam, postID: post.id,
                               emoji: model.myKudos(on: post.id) ?? Kudos.standard,
                               via: "double_tap", context: "detail", reduceMotion: reduceMotion)
            }

            let list = model.reactions[post.id] ?? []
            if !list.isEmpty {
                GrassHeading(title: "Kudos")
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                        HStack(spacing: 12) {
                            ProfilePortrait(photoURL: r.author == model.myID ? model.profile?.avatarURL
                                            : model.person(r.author)?.avatarURL, size: 34)
                            Text(r.author == model.myID ? "You" : (model.person(r.author)?.displayName ?? "Someone"))
                                .font(AppFont.callout.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Text(r.emoji).font(.system(size: 22))
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 14)
                .whiteCard()
            }
        }
    }

    /// The session behind my post, when this phone still has it.
    private func editableSessionID(_ post: Post) -> UUID? {
        guard post.author == model.myID, let sid = CommunityStore.sessionID(forPost: post.id) else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == sid })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0 ? sid : nil
    }
}

/// Every picture on a post, full screen and paged. Only for looking: nothing
/// here saves or shares.
struct PostMediaViewer: View {
    let media: [Post.PostMedia]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(media: [Post.PostMedia], startIndex: Int) {
        self.media = media
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(media) { item in
                    MediaPage(item: item, isCurrent: item.index == index).tag(item.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.tactile)
            .padding(.top, 8).padding(.trailing, 16)
        }
    }
}

private struct MediaPage: View {
    let item: Post.PostMedia
    let isCurrent: Bool
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if item.kind == .video, let player {
                VideoPlayer(player: player)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            if item.kind == .video, let url = item.url {
                if player == nil { player = AVPlayer(url: url) }
                if isCurrent { player?.play() }
            } else if let url = item.url ?? item.posterURL {
                image = UIImage(contentsOfFile: url.path)
            }
        }
        .onChange(of: isCurrent) { _, current in if current { player?.play() } else { player?.pause() } }
        .onDisappear { player?.pause() }
    }
}
