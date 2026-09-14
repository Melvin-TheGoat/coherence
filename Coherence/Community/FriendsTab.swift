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
                    UnavailableCard()
                case .needsUsername:
                    ClaimUsernameView(model: model,
                                      suggested: user?.username ?? "",
                                      displayName: user?.displayName ?? "") { handle in
                        // The local row follows the claimed handle so Settings
                        // and Profile show the real one.
                        if let user { user.username = handle; try? context.save() }
                    }
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

struct UnavailableCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 70)
            Text("Friends need iCloud")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Sign in to iCloud on this iPhone and 808 can find your friends and show what they post.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(AppMetrics.screenPadding)
    }
}

// MARK: - Claim a username

struct ClaimUsernameView: View {
    @ObservedObject var model: CommunityModel
    let suggested: String
    let displayName: String
    let onClaimed: (String) -> Void

    @State private var handle: String = ""
    @State private var availability: CommunityModel.Availability?
    @State private var checking = false
    @State private var claiming = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PersonAvatar(name: displayName, size: 64)
                    .padding(.top, 30)
                Text("Pick your @username")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                Text("This is how friends find you. Letters, numbers, dots and underscores.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    Text("@").foregroundStyle(AppColor.textSecondary)
                    TextField("username", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .onChange(of: handle) { _, new in
                            let cleaned = Username.normalize(new) ?? ""
                            if cleaned != new.lowercased().replacingOccurrences(of: "@", with: "") { handle = cleaned }
                            check()
                        }
                }
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .padding(14)
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.top, 8)

                Text(status)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(availability == .available ? AppColor.calmAccent : AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    claim()
                } label: {
                    Text(claiming ? "Claiming…" : (handle.isEmpty ? "Claim your name" : "Claim @\(handle)"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(availability != .available || claiming)
                .opacity(availability == .available ? 1 : 0.55)

                InviteRewardNote()
                    .padding(.top, 10)
            }
            .padding(AppMetrics.screenPadding)
        }
        .onAppear {
            handle = Username.normalize(suggested) ?? ""
            check()
            if handle.isEmpty { focused = true }
        }
    }

    private var status: String {
        if handle.isEmpty { return " " }
        if checking { return "Checking…" }
        switch availability {
        case .available:          return "@\(handle) is available"
        case .taken:              return "@\(handle) is taken"
        case .invalid:            return "Letters, numbers, dots and underscores only."
        case .failed(let why):    return why
        case .none:               return " "
        }
    }

    private func check() {
        let current = handle
        guard !current.isEmpty else { availability = nil; return }
        checking = true
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, current == handle else { return }
            let result = await model.availability(of: current)
            if current == handle { availability = result; checking = false }
        }
    }

    private func claim() {
        claiming = true
        Task {
            let ok = await model.claim(handle, displayName: displayName)
            claiming = false
            if ok { onClaimed(handle) } else { availability = await model.availability(of: handle) }
        }
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
                    ForEach(model.feed) { post in
                        PostCard(post: post, model: model) { reportTarget = .post(post.id) }
                    }
                    InviteButton(username: model.profile?.username ?? "", style: .quiet)
                        .padding(.top, 6)
                }
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

    static let storeLink = URL(string: "https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=invite&mt=8")!

    private var message: String {
        "I meditate with 808. It scores every session off your Apple Watch, and we can see each other's sits. Add me: @\(username)\n\(Self.storeLink.absoluteString)"
    }

    var body: some View {
        ShareLink(item: message) {
            Label("Invite a friend", systemImage: "square.and.arrow.up")
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

struct PostCard: View {
    let post: Post
    @ObservedObject var model: CommunityModel
    let onReport: () -> Void

    private var author: Profile? { model.person(post.author) }
    private var isMine: Bool { post.author == model.myID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NavigationLink(value: post.author) {
                    HStack(spacing: 8) {
                        PersonAvatar(name: author?.displayName, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(author?.displayName.isEmpty == false ? author!.displayName : (author.map { "@" + $0.username } ?? "Someone"))
                                .font(AppFont.callout.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text([author.map { "@" + $0.username }, SessionListSupport.relativeDay(post.practicedAt)].compactMap { $0 }.joined(separator: " · "))
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
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            if let url = post.photoURL {
                PostPhotoView(url: url)
            }

            HStack(spacing: 14) {
                ScoreRing(score: Double(post.score) / 100, size: 36, lineWidth: 3.5)
                stat("\(post.minutes) min", "Sat")
                stat("\(post.streak) day\(post.streak == 1 ? "" : "s")", "Streak")
                if let t = post.technique, !t.isEmpty { stat(t, "Technique") }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(AppFont.note)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }

            reactionRow
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(AppFont.callout.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var reactionRow: some View {
        let who = model.reactions[post.id] ?? []
        let mine = model.hasReacted(to: post.id)
        return HStack(spacing: 8) {
            Button {
                Task { await model.toggleReaction(post.id) }
            } label: {
                Text(mine ? "🙏 Nice sit · \(who.count)" : (who.isEmpty ? "🙏 Nice sit" : "🙏 Nice sit · \(who.count)"))
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(mine ? AppColor.accentGoldText : AppColor.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(Capsule().stroke(mine ? AppColor.accentGold : AppColor.textSecondary.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isMine)
            if !who.isEmpty, !mine || who.count > 1 {
                Text(names(who))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func names(_ ids: [String]) -> String {
        let others = ids.filter { $0 != model.myID }.compactMap { model.person($0)?.displayName }.filter { !$0.isEmpty }
        switch others.count {
        case 0: return ""
        case 1: return others[0]
        case 2: return "\(others[0]) and \(others[1])"
        default: return "\(others[0]) and \(others.count - 1) others"
        }
    }
}

private struct PostPhotoView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.opacity(0.4)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        .task { image = UIImage(contentsOfFile: url.path) }
    }
}

// MARK: - People

struct PersonAvatar: View {
    let name: String?
    var size: CGFloat = 30

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(AppColor.accentGoldText)
            .frame(width: size, height: size)
            .background(AppColor.accentGold.opacity(0.18), in: Circle())
            .overlay(Circle().stroke(AppColor.accentGold, lineWidth: size > 40 ? 2 : 1.5))
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
            PersonAvatar(name: profile.displayName, size: 34)
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
                if model.incoming.isEmpty && model.sent.isEmpty {
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
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { id in PersonView(id: id, model: model) }
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
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var busy = false

    private var profile: Profile? { model.person(id) }
    private var isMe: Bool { id == model.myID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    PersonAvatar(name: profile?.displayName, size: 56)
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
                        statTile(posts.first.map { "\($0.streak)" } ?? "–", "Streak")
                        statTile("\(posts.count)", "Posts")
                        statTile(posts.isEmpty ? "–" : "\(posts.map(\.score).reduce(0, +) / posts.count)", "Avg score")
                    }
                }

                if !isMe { relationshipButton }

                if !posts.isEmpty {
                    SectionHeader(title: "Posts").padding(.top, 6)
                    ForEach(posts) { post in
                        PostCard(post: post, model: model) { reporting = true }
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
                        Button("Report", role: .destructive) { reporting = true }
                        Button("Block", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $reporting) { ReportSheet(target: .profile(id), model: model) }
        .confirmationDialog("Block \(profile?.displayName ?? "this person")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await model.block(id); dismiss() }
            }
        } message: {
            Text("They will not see your posts or find you, and you will not see theirs. You can undo this from Settings.")
        }
        .task { await reload() }
    }

    private func reload() async {
        relationship = await model.relationship(with: id)
        posts = await model.posts(by: id)
        if let store = model.store, model.person(id) == nil,
           let p = try? await store.profile(named: id) {
            _ = p // cached through the model on the next refresh; header falls back to the handle
        }
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
