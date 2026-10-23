import SwiftUI
import SwiftData
import AVKit

/// What friends shared (Melvin, 2026-10-23: "I'm trying to see their notes,
/// a picture from where they meditated, what type of meditation they did,
/// how they liked it"). Designed in the "808 Friends feed" canvas and
/// approved the same day, with Friends as the default and reactions only.
///
/// A post carries what the person chose to share from their session page:
/// the title, the length, the practice, the sound, how it felt out of ten, a
/// note for friends, and photos or videos. **Never the score, heart rate or
/// breath**: those are health data, and 5.1.3(ii) keeps health data out of
/// iCloud, which is where these posts live.

// MARK: - Your friends, at a glance

/// Faces on the grass, a gold ring on anyone who meditated today, each one
/// opening their page. "See all" opens the full list with how often each
/// meditates, which used to be this tab's whole body.
struct FriendFacesRow: View {
    @ObservedObject var model: CommunityModel

    private func meditatedToday(_ p: Profile) -> Bool {
        p.practice.lastSessionAt.map { Calendar.current.isDateInToday($0) } ?? false
    }

    var body: some View {
        let people = model.friends.compactMap { model.person($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GrassHeading(title: "Your friends")
                Spacer()
                NavigationLink(value: FriendsRoute.allFriends) {
                    Text("See all \(people.count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.skyDeep)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(AppColor.backgroundSecondary.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.tactile)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(people) { p in
                        NavigationLink(value: p.id) { face(p) }
                            .buttonStyle(.tactile)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            if people.contains(where: meditatedToday) {
                Text("A gold ring means they meditated today.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .onValley(soft: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func face(_ p: Profile) -> some View {
        let today = meditatedToday(p)
        return VStack(spacing: 5) {
            ProfilePortrait(photoURL: p.avatarURL, size: 56)
                .overlay(Circle().stroke(today ? AppColor.accentGold : AppColor.backgroundSecondary,
                                         lineWidth: 3))
            Text(p.displayName.isEmpty ? "@" + p.username : p.displayName)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .onValley()
                .lineLimit(1)
                .frame(width: 64)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((p.displayName.isEmpty ? p.username : p.displayName)
                            + (today ? ", meditated today" : ""))
    }
}

/// Every friend with how often they meditate, from "See all".
struct AllFriendsView: View {
    @ObservedObject var model: CommunityModel
    @Environment(\.tabBarClearance) private var tabBarClearance

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FriendsSky(height: proxy.safeAreaInsets.top + 56) { EmptyView() }
                    VStack(spacing: 0) {
                        ForEach(Array(model.friends.enumerated()), id: \.element) { i, id in
                            if let p = model.person(id) {
                                if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                                NavigationLink(value: id) {
                                    PersonRow(profile: p, subtitle: "@" + p.username, practice: practiceLine(p.practice),
                                              tag: model.joinedWithCode.contains(id) ? "Joined with your code" : nil) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(AppColor.skyDeep)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .whiteCard()
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 24 + tabBarClearance)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            .refreshable { await model.refresh() }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Your friends")
                    .font(DisplayFont.display(17, .heavy))
                    .onValley()
            }
        }
    }
}

// MARK: - The feed

/// "Latest from friends": every post by a friend or by me, newest practiced
/// first, with the line that says one of mine is still uploading.
struct FriendsFeedSection: View {
    @ObservedObject var model: CommunityModel
    @State private var reporting: Post?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GrassHeading(title: "Latest from friends")
            if !model.uploading.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(AppColor.skyDeep)
                    Text("Sharing your session…")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(AppColor.backgroundSecondary.opacity(0.92), in: Capsule())
            }
            if model.feed.isEmpty {
                Text("When a friend shares a session, it shows up here: where they meditated, what they did and how it felt.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .whiteCard(radius: 22)
            } else {
                ForEach(model.feed) { post in
                    FeedPostCard(post: post, model: model) { reporting = post }
                }
            }
        }
        .sheet(item: $reporting) { post in
            ReportSheet(target: .post(post.id), model: model)
        }
    }
}

/// One shared session in the feed: who and when, what they called it, the
/// three numbers, their note, their first photo, and the 🙏.
struct FeedPostCard: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onReport: () -> Void

    static let inset: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostHeader(post: post, model: model, onReport: onReport)
            NavigationLink {
                PostDetailView(postID: post.id, model: model)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text(post.title.isEmpty ? "Meditation" : post.title)
                        .font(DisplayFont.display(20, .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    PostStatsRow(post: post)
                    if !post.caption.isEmpty {
                        Text(post.caption)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let first = post.media.first {
                        PostMediaThumb(item: first, height: 250, fill: true)
                            .overlay(alignment: .topTrailing) {
                                if post.media.count > 1 {
                                    Text("1 of \(post.media.count)")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(.black.opacity(0.45), in: Capsule())
                                        .padding(10)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            ReactionLine(post: post, model: model)
        }
        .padding(Self.inset)
        .whiteCard(radius: 22)
    }
}

/// The avatar, the name and "Today at 6:48 AM · Rain", and the menu: Edit
/// and Delete on mine, Report on anyone else's (guideline 1.2).
struct PostHeader: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onReport: () -> Void

    @Environment(\.modelContext) private var context
    @State private var editing: EditTarget?
    private struct EditTarget: Identifiable { let id: UUID }

    private var author: Profile? { model.person(post.author) }
    private var isMine: Bool { post.author == model.myID }

    /// The session this post came from, when it is still on this phone. A
    /// post made on another device has nothing here to open, so Edit stays
    /// off the menu rather than opening an empty page.
    private var editableSessionID: UUID? {
        guard isMine, let sid = CommunityStore.sessionID(forPost: post.id) else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == sid })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0 ? sid : nil
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                PersonView(id: post.author, model: model)
            } label: {
                HStack(spacing: 11) {
                    ProfilePortrait(photoURL: author?.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PostWords.name(author))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(PostWords.whenAndWhere(post))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.tactile)
            Spacer(minLength: 0)
            Menu {
                if isMine {
                    if let sid = editableSessionID {
                        Button("Edit") { editing = EditTarget(id: sid) }
                    }
                    Button("Delete", role: .destructive) { Task { await model.deletePost(post.id) } }
                } else {
                    Button("Report", role: .destructive, action: onReport)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isMine ? "Edit or delete" : "Report")
        }
        .sheet(item: $editing) { target in
            SaveSessionView(sessionID: target.id, mode: .edit) { editing = nil }
        }
    }
}

/// Time, how it felt and the practice, side by side, each only when there is
/// one to show.
struct PostStatsRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column("Time", "\(post.minutes) min", ink: AppColor.measureInk)
            if let r = post.rating { column("How it felt", "\(r)/10", ink: AppColor.textPrimary) }
            if let t = post.technique, !t.isEmpty { column("Practice", t, ink: AppColor.textPrimary) }
        }
    }

    private func column(_ label: String, _ value: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 🙏, and who gave one. On my own post the pill only shows the count of
/// who gave one; nobody thanks themselves.
struct ReactionLine: View {
    let post: Post
    @ObservedObject var model: CommunityModel

    var body: some View {
        let who = model.reactions[post.id] ?? []
        let mine = model.hasReacted(to: post.id)
        let isMine = post.author == model.myID
        HStack(spacing: 10) {
            Button {
                Task { await model.toggleReaction(post.id) }
            } label: {
                Text("🙏")
                    .font(.system(size: 17))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background {
                        if mine {
                            Capsule().fill(AppColor.accentGold)
                                .shadow(color: AppColor.accentGoldShade, radius: 0, y: 3)
                        } else {
                            Capsule().fill(AppColor.skyWash)
                        }
                    }
                    .padding(.bottom, 3)
            }
            .buttonStyle(.tactile)
            .disabled(isMine)
            .accessibilityLabel(mine ? "Take back your nice session" : "Nice session")
            Text(PostWords.reactors(who, model: model, isMine: isMine))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// The words every post view shares, so the feed and the opened session can
/// never word the same post two ways.
@MainActor
enum PostWords {
    static func name(_ p: Profile?) -> String {
        if let n = p?.displayName, !n.isEmpty { return n }
        return p.map { "@" + $0.username } ?? "A friend"
    }

    /// "Today at 6:48 AM · Rain": Strava's line, with the sound where it puts
    /// the place.
    static func whenAndWhere(_ post: Post) -> String {
        let time = post.practicedAt.formatted(date: .omitted, time: .shortened)
        let day = SessionListSupport.relativeDay(post.practicedAt)
        return [day + " at " + time, post.sound].compactMap { $0 }.joined(separator: " · ")
    }

    static func reactors(_ ids: [String], model: CommunityModel, isMine: Bool) -> String {
        let names = ids.map { $0 == model.myID ? "You" : (model.person($0)?.displayName ?? "") }
            .filter { !$0.isEmpty }
        switch names.count {
        case 0: return isMine ? "No 🙏 yet" : "Be the first"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }
}

// MARK: - One shared session, opened

/// The whole post: every photo and video, full width and swipeable, then
/// who and when, the title, the four numbers, the note, and the 🙏 with who
/// gave one.
struct PostDetailView: View {
    let postID: String
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    /// A page pushed inside the Friends tab sits under the tab bar, whose
    /// inset does not reach it (see `tabBarClearance`).
    @Environment(\.tabBarClearance) private var tabBarClearance

    @State private var fetched: Post?
    @State private var page = 0
    @State private var viewerStart: ViewerStart?
    @State private var reporting = false
    private struct ViewerStart: Identifiable { let id: Int }

    private var post: Post? { model.feed.first { $0.id == postID } ?? fetched }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if let post {
                    VStack(spacing: 0) {
                        hero(post, top: proxy.safeAreaInsets.top)
                        sheet(post)
                    }
                } else {
                    ProgressView().tint(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 200)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fullScreenCover(item: $viewerStart) { start in
            if let post { PostMediaViewer(media: post.media, startIndex: start.id) }
        }
        .sheet(isPresented: $reporting) { ReportSheet(target: .post(postID), model: model) }
        .task {
            if model.feed.first(where: { $0.id == postID }) == nil {
                fetched = await model.fetchPost(postID)
            }
            await model.loadReactions(for: [postID])
        }
    }

    @ViewBuilder
    private func hero(_ post: Post, top: CGFloat) -> some View {
        if post.media.isEmpty {
            FriendsSky(height: top + 120) { EmptyView() }
        } else {
            TabView(selection: $page) {
                ForEach(post.media) { item in
                    Button { viewerStart = ViewerStart(id: item.index) } label: {
                        PostMediaThumb(item: item, height: 470, fill: true, corner: 0)
                    }
                    .buttonStyle(.plain)
                    .tag(item.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: post.media.count > 1 ? .always : .never))
            .frame(height: 470)
        }
    }

    private func sheet(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PostHeader(post: post, model: model) { reporting = true }
            Text(post.title.isEmpty ? "Meditation" : post.title)
                .font(DisplayFont.display(27, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                tile("home-time", "Time", "\(post.minutes) min", ink: AppColor.measureInk)
                if let r = post.rating { tile("home-rating", "How it felt", "\(r)/10") }
                if let t = post.technique, !t.isEmpty { tile("home-sessions", "Practice", t) }
                if let s = post.sound, !s.isEmpty { tile("sit-sound", "Sound", s) }
            }
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(ValleyGround.quiet).frame(height: 1)
            ReactionLine(post: post, model: model)
            Color.clear.frame(height: 30 + tabBarClearance)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.backgroundSecondary,
                    in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .padding(.top, post.media.isEmpty ? 0 : -28)
    }

    private func tile(_ art: String, _ label: String, _ value: String, ink: Color = AppColor.textPrimary) -> some View {
        HStack(spacing: 10) {
            SitArt(name: art, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - A friend's sessions, on their page

/// Everything a friend has shared, newest first, as a list or as their
/// photos (Melvin, 2026-10-23: "you can't even see what meditations they've
/// done"). Only for a friend, or for me: a stranger from search sees their
/// practice numbers and nothing they shared.
struct PersonSessions: View {
    let personID: String
    @ObservedObject var model: CommunityModel

    @State private var posts: [Post]?
    @State private var photos = false

    private var firstName: String {
        let name = model.person(personID)?.displayName ?? ""
        return personID == model.myID ? "Your" : (name.isEmpty ? "Their" : name + "'s")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GrassHeading(title: "\(firstName) sessions")
                Spacer()
                if let posts, posts.contains(where: { !$0.media.isEmpty }) {
                    Picker("Show", selection: $photos) {
                        Text("List").tag(false)
                        Text("Photos").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }
            if let posts {
                if posts.isEmpty {
                    Text("Nothing shared yet.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .whiteCard(radius: 22)
                } else if photos {
                    photoGrid(posts)
                } else {
                    list(posts)
                }
            } else {
                ProgressView().tint(AppColor.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
        .task(id: personID) {
            let found = await model.posts(by: personID)
            posts = found
            await model.loadReactions(for: found.map(\.id))
        }
    }

    private func list(_ posts: [Post]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                NavigationLink {
                    PostDetailView(postID: post.id, model: model)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if let first = post.media.first {
                            PostMediaThumb(item: first, height: 84, fill: false, fixedWidth: 64, corner: 12)
                        } else {
                            VStack(spacing: 0) {
                                Text("\(post.minutes)")
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                Text("min")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(AppColor.measureInk)
                            .frame(width: 64, height: 84)
                            .background(AppColor.skyWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(post.title.isEmpty ? "Meditation" : post.title)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(summary(post))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                            if !post.caption.isEmpty {
                                Text(post.caption)
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactile)
            }
        }
        .padding(.horizontal, 16)
        .whiteCard(radius: 22)
    }

    private func photoGrid(_ posts: [Post]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(posts.filter { !$0.media.isEmpty }) { post in
                NavigationLink {
                    PostDetailView(postID: post.id, model: model)
                } label: {
                    Color.clear
                        .aspectRatio(0.8, contentMode: .fit)
                        .overlay { PostMediaThumb(item: post.media[0], height: nil, fill: true, corner: 0) }
                        .clipped()
                }
                .buttonStyle(.tactile)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "Today · 20 min · felt 8/10 · Breath work".
    private func summary(_ post: Post) -> String {
        var parts = [SessionListSupport.relativeDay(post.practicedAt), "\(post.minutes) min"]
        if let r = post.rating { parts.append("felt \(r)/10") }
        if let t = post.technique, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Photos and videos

/// One photo or video's still. `fill` stretches it across the width it is
/// given at `height` (the feed and the opened session); otherwise it keeps
/// its own shape at `fixedWidth`.
struct PostMediaThumb: View {
    let item: Post.PostMedia
    var height: CGFloat?
    var fill = true
    var fixedWidth: CGFloat? = nil
    var corner: CGFloat = 16
    @State private var image: UIImage?

    var body: some View {
        AppColor.backgroundPrimary.opacity(0.6)
            .frame(width: fill ? nil : fixedWidth, height: height)
            .frame(maxWidth: fill ? .infinity : nil)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .overlay(alignment: .bottomLeading) {
                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .padding(9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .task(id: item.posterURL ?? item.url) {
                // The full photo when there is one (sharper on a big tile),
                // else the small poster; a video always shows its poster.
                let source = item.kind == .photo ? (item.url ?? item.posterURL) : (item.posterURL ?? item.url)
                image = source.flatMap { UIImage(contentsOfFile: $0.path) }
            }
            .accessibilityLabel(item.kind == .video ? "Video from the session" : "Photo from the session")
    }
}

/// Full screen, paged: photos fit the screen, videos play with sound. Only
/// for looking; nothing here saves or shares.
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
                    PostMediaPage(item: item, isCurrent: item.index == index).tag(item.index)
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
            .accessibilityLabel("Close")
            .padding(.top, 8).padding(.trailing, 16)
        }
    }
}

private struct PostMediaPage: View {
    let item: Post.PostMedia
    /// A paged TabView keeps its neighbours alive, so a video swiped past
    /// would otherwise keep playing behind the photo you moved on to.
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            switch item.kind {
            case .photo:
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            case .video:
                if let url = item.url { PostVideoPage(url: url, isCurrent: isCurrent) } else { ProgressView().tint(.white) }
            }
        }
        .task {
            if item.kind == .photo, let url = item.url ?? item.posterURL {
                image = UIImage(contentsOfFile: url.path)
            }
        }
    }
}

/// One player per video, made once (a player built in `body` is a new one on
/// every redraw), looping, playing only while its page is on screen. Its
/// sound holds the app's music, like a session's own video does.
private struct PostVideoPage: View {
    let url: URL
    let isCurrent: Bool
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player { VideoPlayer(player: player) } else { ProgressView().tint(.white) }
        }
        .task {
            if player == nil {
                let queue = AVQueuePlayer()
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
            }
            if isCurrent { player?.play(); AppAudio.shared.set(.video, true) }
        }
        .onChange(of: isCurrent) { _, current in
            if current { player?.play() } else { player?.pause() }
        }
        .onDisappear {
            player?.pause()
            AppAudio.shared.set(.video, false)
        }
    }
}
