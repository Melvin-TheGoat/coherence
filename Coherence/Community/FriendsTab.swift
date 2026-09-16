import SwiftUI
import SwiftData

/// The Friends tab (COMMUNITY.md, mockup `mockups/friends.html`). Mutual
/// friends, a feed of what they posted, one reaction per post, requests
/// behind a count, search by handle, and an invite. No comments, no public
/// counts. The first open claims a real username; the tab is honest about
/// iCloud being unavailable rather than pretending to load.
struct FriendsTab: View {
    @Environment(\.modelContext) private var context
    @Query private var users: [User]
    @EnvironmentObject private var model: CommunityModel

    private var user: User? { users.first }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView().tint(AppColor.calmAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    UnavailableCard(model: model)
                case .needsUsername:
                    CreateProfileView(model: model,
                                      suggested: user?.username ?? "",
                                      nickname: user?.displayName ?? "") { _ in }
                case .ready:
                    FeedView(model: model, myDisplayName: user?.displayName ?? "")
                }
            }
            .screenBackground()
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            Analytics.track(.friendsOpened)
            await model.load()
        }
        .alert("Friends", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }
}

// MARK: - Unavailable

/// Friends live in the user's iCloud account: no server, so iCloud IS the
/// identity and the storage. The card says why, then exactly what to do
/// (Melvin, 2026-09-15: "there's no instructions for this"), and checks
/// again on request. iOS offers no public link straight to the iCloud
/// settings page; "Open Settings" lands one tap away from it.
struct UnavailableCard: View {
    @ObservedObject var model: CommunityModel
    @State private var checking = false

    private let steps = [
        "Open Settings and tap your name at the top. If it says Sign in to your iPhone, tap that.",
        "Sign in with your Apple Account.",
        "Under iCloud, make sure iCloud Drive is on.",
        "Come back here and tap Check again.",
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 40)
            Text("Friends need iCloud")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Your friends, your posts and your username are kept in your own iCloud account. 808 has no server of its own, so there is nowhere else to keep them.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if model.unavailableReason == .noContainer {
                Text("This build of 808 can't reach iCloud. The App Store version can.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentGoldText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(AppFont.caption.weight(.bold))
                                .foregroundStyle(AppColor.accentGoldText)
                                .frame(width: 18, height: 18)
                                .background(AppColor.accentGold.opacity(0.15), in: Circle())
                            Text(step)
                                .font(AppFont.callout)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))

                VStack(spacing: 10) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        checking = true
                        Task { await model.load(); checking = false }
                    } label: {
                        Text(checking ? "Checking…" : "Check again")
                    }
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .disabled(checking)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(AppMetrics.screenPadding)
    }
}

/// The reward, stated once, on the claim screen and the empty feed. The
/// mechanics live in feature 4 (the grant); the copy is here so the promise
/// and the code ship in the same build.
private struct InviteRewardNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bring a friend, see the evidence.")
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.calmAccent)
            Text("When a friend you invite accepts and finishes their first session, your next 10 sessions show the full results: every curve and every reading.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColor.calmAccent.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Feed

struct FeedView: View {
    @ObservedObject var model: CommunityModel
    let myDisplayName: String

    @State private var query = ""
    @State private var result: Profile?
    @State private var searched = false
    @State private var reportTarget: ReportSheet.Target?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                searchField
                if searched { searchResult }
                if model.feed.isEmpty {
                    EmptyFeed(model: model, username: model.profile?.username ?? "")
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.feed) { post in
                            PostCard(post: post, model: model) { reportTarget = .post(post.id) }
                        }
                    }
                    InviteButton(username: model.profile?.username ?? "", style: .quiet)
                        .padding(.top, 6)
                }
                // Clears the raised plus and the tab bar. The feed's last
                // item (the invite) sat under them with nowhere left to
                // scroll, found walking the flow in the simulator.
                Color.clear.frame(height: 72)
            }
            .padding(AppMetrics.screenPadding)
        }
        .refreshable { await model.refresh() }
        .navigationDestination(for: String.self) { id in
            PersonView(id: id, model: model)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, model: model)
        }
    }

    private var header: some View {
        HStack {
            Text(model.profile.map { "@" + $0.username } ?? "")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            NavigationLink {
                RequestsView(model: model)
            } label: {
                Text(model.incoming.isEmpty ? "Requests" : "\(model.incoming.count) request\(model.incoming.count == 1 ? "" : "s")")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(model.incoming.isEmpty ? AppColor.textSecondary : AppColor.accentGoldText)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColor.textSecondary)
            TextField("Find a friend by @username", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .submitLabel(.search)
                .onSubmit { search() }
                .onChange(of: query) { _, new in if new.isEmpty { searched = false; result = nil } }
            if !query.isEmpty {
                Button { query = ""; searched = false; result = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @ViewBuilder
    private var searchResult: some View {
        if let result {
            NavigationLink(value: result.id) {
                PersonRow(profile: result, subtitle: "@" + result.username) { EmptyView() }
            }
            .buttonStyle(CardButtonStyle())
        } else {
            Text("Nobody with that name yet. Check the spelling, or invite them.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func search() {
        let q = query
        guard Username.normalize(q) != nil else { return }
        Task {
            result = await model.search(q)
            searched = true
        }
    }
}

private struct EmptyFeed: View {
    @ObservedObject var model: CommunityModel
    let username: String

    var body: some View {
        VStack(spacing: 12) {
            Text("🙏").font(.system(size: 40)).padding(.top, 40)
            Text("Nobody here yet")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Your feed shows the sessions your friends post. Ask someone to sit with you.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            InviteButton(username: username, style: .gold)
                .padding(.top, 8)
            if !model.sent.isEmpty {
                Text("\(model.sent.count) request\(model.sent.count == 1 ? "" : "s") waiting for an answer")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            InviteRewardNote().padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The reward landing

/// Shown once when a friend you invited has accepted and sat their first
/// session (`CommunityModel.checkRewards`). Names the friend, states the
/// grant, and nothing more.
struct InviteRewardSheet: View {
    let news: CommunityModel.RewardNews
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🙏").font(.system(size: 36)).padding(.top, 8)
            Text("\(news.friendName) sat their first session")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(store.entitlements.paid
                 ? "You brought them here. The Brought a friend award is on your shelf, and \(news.remaining) sessions of full evidence are banked in case your membership ever lapses."
                 : "You brought them here. Your next \(news.remaining) sessions show the full evidence: every curve, every reading.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !store.entitlements.paid {
                HStack(spacing: 8) {
                    Image(systemName: "person.2").foregroundStyle(AppColor.calmAccent)
                    Text("\(news.remaining) sessions of evidence · starts with your next sit")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.calmAccent)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColor.calmAccent.opacity(0.5), lineWidth: 1))
            }
            Spacer(minLength: 0)
            Button("Nice") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
    }
}

// MARK: - Invite

/// The system share sheet with the App Store link and the handle to search.
/// No install-time attribution exists without a universal link; the accepted
/// request is the attribution (COMMUNITY.md).
struct InviteButton: View {
    enum Style { case gold, quiet }
    let username: String
    let style: Style
    var title: String = "Invite a friend"

    static let storeLink = URL(string: "https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=invite&mt=8")!

    private var message: String {
        // Aziz's wording (2026-09-14). The App Store link stays on its own
        // line so the message still gets a friend to the download.
        "Add me on 808 Meditate, the social media for meditation: @\(username)\n\(Self.storeLink.absoluteString)"
    }

    var body: some View {
        ShareLink(item: message) {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .modifier(InviteStyle(style: style))
        .simultaneousGesture(TapGesture().onEnded { Analytics.track(.inviteShared) })
    }

    private struct InviteStyle: ViewModifier {
        let style: Style
        func body(content: Content) -> some View {
            switch style {
            case .gold:  content.buttonStyle(PrimaryButtonStyle())
            case .quiet: content.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Post card

/// A friend's session, in Strava's activity-card shape (mockup v2, section
/// 4): who and when (with the sound where Strava shows a place), a bold
/// title, the description, stats with the label above the number, the selfie
/// full width, and a footer with who gave 🙏. Edge to edge like Strava's feed.
struct PostCard: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onReport: () -> Void

    private var author: Profile? { model.person(post.author) }
    private var isMine: Bool { post.author == model.myID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            Text(post.title.isEmpty ? "Meditation" : post.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 16)

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.horizontal, 16).padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 26) {
                stat("Score", "\(post.score)")
                stat("Time", "\(post.minutes)m")
                stat("Streak", "\(post.streak) day\(post.streak == 1 ? "" : "s")")
                if let t = post.technique, !t.isEmpty { stat("Technique", t) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)

            if let url = post.photoURL {
                PostPhotoView(url: url)
            }

            footer
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(AppColor.backgroundSecondary)
        .padding(.horizontal, -AppMetrics.screenPadding)
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: post.author) {
                HStack(spacing: 10) {
                    PersonAvatar(name: author?.displayName, size: 38, photoURL: author?.avatarURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(whenAndWhere)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(CardButtonStyle())
            Spacer()
            Menu {
                if isMine {
                    Button("Delete post", role: .destructive) { Task { await model.deletePost(post.id) } }
                } else {
                    Button("Report", role: .destructive, action: onReport)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
    }

    private var displayName: String {
        if let name = author?.displayName, !name.isEmpty { return name }
        return author.map { "@" + $0.username } ?? "Someone"
    }

    /// "Today at 7:12 AM · Rain": Strava's date line, with the sound where it
    /// puts the location.
    private var whenAndWhere: String {
        let time = post.practicedAt.formatted(date: .omitted, time: .shortened)
        let day = SessionListSupport.relativeDay(post.practicedAt)
        return [day + " at " + time, post.sound].compactMap { $0 }.joined(separator: " · ")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var footer: some View {
        let who = model.reactions[post.id] ?? []
        let mine = model.hasReacted(to: post.id)
        return HStack(spacing: 10) {
            Text(reactorLine(who))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Button {
                Task { await model.toggleReaction(post.id) }
            } label: {
                HStack(spacing: 5) {
                    Text("🙏").font(.system(size: 17)).grayscale(mine ? 0 : 1).opacity(mine ? 1 : 0.7)
                    Text("Nice sit")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(mine ? AppColor.accentGoldText : AppColor.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().stroke(mine ? AppColor.accentGold : AppColor.textSecondary.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isMine)
        }
    }

    private func reactorLine(_ ids: [String]) -> String {
        let names = ids.map { $0 == model.myID ? "You" : (model.person($0)?.displayName ?? "") }.filter { !$0.isEmpty }
        switch names.count {
        case 0: return isMine ? "No 🙏 yet" : "Be the first to give a 🙏"
        case 1: return names[0] + " gave a 🙏"
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }
}

private struct PostPhotoView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        // Same rule as the composer: the photo fills an overlay of a
        // fixed-size frame, so a wide image can never widen the card.
        AppColor.backgroundPrimary.opacity(0.4)
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task { image = UIImage(contentsOfFile: url.path) }
    }
}

// MARK: - People

struct PersonAvatar: View {
    let name: String?
    var size: CGFloat = 30
    /// The profile photo when there is one; initials otherwise.
    var photoURL: URL? = nil
    @State private var photo: UIImage?

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                AppColor.accentGold.opacity(0.18)
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGoldText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppColor.accentGold, lineWidth: size > 40 ? 2 : 1.5))
        .task(id: photoURL) {
            photo = photoURL.flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }

    private var initials: String {
        guard let name, !name.isEmpty else { return "•" }
        return name.split(separator: " ").prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
    }
}

struct PersonRow<Trailing: View>: View {
    let profile: Profile
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            PersonAvatar(name: profile.displayName, size: 34, photoURL: profile.avatarURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName.isEmpty ? "@" + profile.username : profile.displayName)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 9)
        .fullyTappable()
    }
}

struct RequestsView: View {
    @ObservedObject var model: CommunityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.incoming.isEmpty && model.sent.isEmpty && model.blocked.isEmpty {
                    Text("No requests right now.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                }
                if !model.incoming.isEmpty {
                    SectionHeader(title: "Incoming")
                    ForEach(model.incoming, id: \.self) { id in
                        if let p = model.person(id) {
                            NavigationLink(value: id) {
                                PersonRow(profile: p, subtitle: "@" + p.username) {
                                    Button("Accept") { Task { await model.accept(id) } }
                                        .buttonStyle(.plain)
                                        .font(AppFont.caption.weight(.bold))
                                        .foregroundStyle(AppColor.accentGoldText)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .overlay(Capsule().stroke(AppColor.accentGold, lineWidth: 1))
                                }
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
                if !model.sent.isEmpty {
                    SectionHeader(title: "Sent").padding(.top, 14)
                    ForEach(model.sent, id: \.self) { id in
                        if let p = model.person(id) {
                            NavigationLink(value: id) {
                                PersonRow(profile: p, subtitle: "@" + p.username + " · waiting") {
                                    Text("SENT").font(.system(size: 10, weight: .bold)).tracking(0.8)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
                if !model.blocked.isEmpty {
                    SectionHeader(title: "Blocked").padding(.top, 14)
                    ForEach(model.blocked, id: \.self) { id in
                        HStack {
                            Text(model.person(id).map { $0.displayName.isEmpty ? "@" + $0.username : $0.displayName } ?? "Someone")
                                .font(AppFont.callout.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Button("Unblock") { Task { await model.unblock(id) } }
                                .buttonStyle(.plain)
                                .font(AppFont.caption.weight(.bold))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        // No navigationDestination here: FeedView's, further up the same
        // stack, already routes profile ids. A second one for the same type
        // makes SwiftUI pick one arbitrarily.
        .task { await model.loadBlocked() }
    }
}

/// A person: header, three numbers from their posts (friends only), the
/// relationship button, and the menu guideline 1.2 checks for (Remove,
/// Report, Block).
struct PersonView: View {
    let id: String
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss

    @State private var relationship: CommunityStore.Relationship = .none
    @State private var posts: [Post] = []
    @State private var reportTarget: ReportSheet.Target?
    @State private var confirmBlock = false
    @State private var busy = false

    private var profile: Profile? { model.person(id) }
    private var isMe: Bool { id == model.myID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    PersonAvatar(name: profile?.displayName, size: 56, photoURL: profile?.avatarURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile?.displayName.isEmpty == false ? profile!.displayName : "@" + (profile?.username ?? ""))
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(["@" + (profile?.username ?? ""),
                              profile.map { "practicing since " + $0.createdAt.formatted(.dateTime.month(.abbreviated).year()) }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)

                if relationship == .friends || isMe {
                    HStack(spacing: 6) {
                        // A post's streak is the streak on the day it was sat.
                        // Only the last day or so still describes today.
                        statTile(posts.first.flatMap { Date().timeIntervalSince($0.practicedAt) < 36 * 3600 ? "\($0.streak)" : nil } ?? "–",
                                 "Streak")
                        statTile("\(posts.count)", "Posts")
                        statTile(posts.isEmpty ? "–" : "\(posts.map(\.score).reduce(0, +) / posts.count)", "Avg score")
                    }
                }

                if !isMe { relationshipButton }

                if !posts.isEmpty {
                    SectionHeader(title: "Posts").padding(.top, 6)
                    ForEach(posts) { post in
                        PostCard(post: post, model: model) { reportTarget = .post(post.id) }
                    }
                } else if relationship != .friends && !isMe {
                    Text("Posts show once you are friends.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if relationship == .friends {
                            Button("Remove friend") { Task { await model.remove(id); await reload() } }
                        }
                        Button("Report", role: .destructive) { reportTarget = .profile(id) }
                        Button("Block", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .sheet(item: $reportTarget) { target in ReportSheet(target: target, model: model) }
        .confirmationDialog("Block \(profile?.displayName ?? "this person")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await model.block(id); dismiss() }
            }
        } message: {
            Text("They will not see your posts or find you, and you will not see theirs. You can undo this from Friends → Requests → Blocked.")
        }
        .task { await reload() }
    }

    private func reload() async {
        await model.loadPerson(id)
        relationship = await model.relationship(with: id)
        posts = await model.posts(by: id)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(AppColor.textPrimary)
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.9).foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var relationshipButton: some View {
        switch relationship {
        case .none:
            Button { act { await model.request(id) } } label: { Text(busy ? "Sending…" : "Add friend") }
                .buttonStyle(PrimaryButtonStyle())
        case .requested:
            Button { act { await model.remove(id) } } label: { Text("Request sent · tap to withdraw") }
                .buttonStyle(SecondaryButtonStyle())
        case .incoming:
            Button { act { await model.accept(id) } } label: { Text(busy ? "Accepting…" : "Accept request") }
                .buttonStyle(PrimaryButtonStyle())
        case .friends:
            Text("Friends ✓")
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().stroke(AppColor.textSecondary.opacity(0.35), lineWidth: 1))
        }
    }

    private func act(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); await reload(); busy = false }
    }
}

// MARK: - Report

struct ReportSheet: View {
    enum Target: Identifiable {
        case post(String), profile(String)
        var id: String {
            switch self { case .post(let s): "post-" + s; case .profile(let s): "profile-" + s }
        }
        var record: String { switch self { case .post(let s), .profile(let s): s } }
        var kind: Report.Target { switch self { case .post: .post; case .profile: .profile } }
    }

    let target: Target
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = ""
    @State private var detail: String = ""

    private let reasons = ["Not a meditation", "Harassment or hate", "Nudity or violence", "Spam", "Something else"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's wrong with it?")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(reasons, id: \.self) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r).font(AppFont.callout).foregroundStyle(AppColor.textPrimary)
                                Spacer()
                                Image(systemName: reason == r ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reason == r ? AppColor.accentGold : AppColor.textSecondary)
                            }
                            .padding(12)
                            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                    TextField("Anything else we should know (optional)", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(12)
                        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("A person reads every report, usually within a day. Reported posts come down; people who keep doing it are removed. support@meditate808.com")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Button {
                        Task {
                            await model.report(target.record, as: target.kind,
                                               reason: [reason, detail].filter { !$0.isEmpty }.joined(separator: ": "))
                            dismiss()
                        }
                    } label: { Text("Send report") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(reason.isEmpty)
                    .opacity(reason.isEmpty ? 0.55 : 1)
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
