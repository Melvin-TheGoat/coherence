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
    /// Set while the onboarding tour shows this tab under its dim.
    @Environment(\.tourTab) private var tourTab

    private var user: User? { users.first }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView().tint(AppColor.calmAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    ScrollView {
                        VStack(spacing: 14) {
                            FriendsSky(height: 230) {
                                VStack(alignment: .leading) {
                                    Text("Friends")
                                        .font(DisplayFont.display(30, .heavy))
                                        .foregroundStyle(ValleyGround.ink)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppMetrics.screenPadding)
                                .padding(.top, 70)
                            }
                            #if DEBUG
                            testModeCard
                            #endif
                            UnavailableCard(model: model)
                                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .padding(.horizontal, AppMetrics.screenPadding)
                                .padding(.bottom, 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .top)
                    .modifier(NoTopEdgeHaze())
                    .toolbar(.hidden, for: .navigationBar)
                case .needsUsername:
                    CreateProfileView(model: model,
                                      suggested: user?.username ?? "",
                                      nickname: user?.displayName ?? "") { _ in }
                case .ready:
                    FeedView(model: model, myDisplayName: user?.displayName ?? "")
                }
            }
            // The valley, like Home, Profile and the guide (Aziz, 2026-09-22,
            // `mockups/friends-valley.html`). The last page left on plain
            // cream with brown ink.
            .background(ValleyGround.meadow.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            // The tour passing through is not somebody opening Friends, and
            // counting it would put every new install in the number.
            if tourTab == nil { Analytics.track(.friendsOpened) }
            await model.load()
        }
        .alert("Friends", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    #if DEBUG
    /// Friends with no iCloud, for a simulator. Development builds only.
    private var testModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test mode")
                .font(DisplayFont.display(17))
                .foregroundStyle(AppColor.textPrimary)
            Text("Development builds only. Friends runs on a fake database kept on this device, so the tab works without iCloud. Nothing leaves the phone and nothing is kept between launches.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn test mode on") { Task { await model.setTestMode(true) } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .card()
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 8)
    }

    #endif
}

// MARK: - The valley

/// Meadow behind the status bar once the band has scrolled away. This page
/// has no navigation bar, so iOS has no top edge to fade, and without this
/// the feed's cards slid under the clock with nothing behind it. Invisible
/// while the sky is showing, which is the whole point of the band.
private struct StatusBarScrim: ViewModifier {
    let height: CGFloat
    let threshold: CGFloat
    @State private var past = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                content.onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top > threshold
                } action: { _, now in
                    withAnimation(.easeOut(duration: 0.2)) { past = now }
                }
            } else {
                content
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: ValleyGround.meadow, location: 0),
                                   .init(color: ValleyGround.meadow, location: 0.7),
                                   .init(color: ValleyGround.meadow.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: height + 16)
                .ignoresSafeArea(edges: .top)
                .opacity(past ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// The strip of valley at the top of every Friends page: sky, ridges and the
/// near meadow, with whatever the page puts on it. The same scene Home,
/// Profile and the guide stand in, with nobody in it.
struct FriendsSky<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ValleyScene(progress: 0, showsFigure: false)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { content }
    }
}

/// Your friends standing on the meadow, the ones who posted a session today
/// glowing with Otto's own warm light (the approved mockup's one new idea).
/// It reads only who you are friends with and whether they posted today:
/// the feed is the only evidence 808 has that a friend sat, and nothing
/// from Block or Screen Time ever reaches it. The last face is Invite.
private struct FriendsOnTheMeadow: View {
    @ObservedObject var model: CommunityModel

    private var postedToday: Set<String> {
        Set(model.feed.filter { Calendar.current.isDateInToday($0.practicedAt) }.map(\.author))
    }

    /// Today's first, then everyone else, each in the order they were added.
    private var ordered: [String] {
        let lit = postedToday
        return model.friends.filter(lit.contains) + model.friends.filter { !lit.contains($0) }
    }

    var body: some View {
        let lit = postedToday
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ordered, id: \.self) { id in
                    NavigationLink(value: id) { face(id, lit: lit.contains(id)) }
                        .buttonStyle(CardButtonStyle())
                }
                ShareLink(item: InviteButton.message(for: model.profile?.username ?? "")) {
                    inviteFace
                }
                .buttonStyle(CardButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { Analytics.track(.inviteShared) })
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            // Room for the glow, which spills past the circle.
            .padding(.vertical, 8)
        }
    }

    private func face(_ id: String, lit: Bool) -> some View {
        let person = model.person(id)
        let name = person.map { $0.displayName.isEmpty ? "@" + $0.username : $0.displayName } ?? "Friend"
        return VStack(spacing: 4) {
            ProfilePortrait(photoURL: person?.avatarURL, size: 50)
                .overlay(Circle().stroke(lit ? AppColor.auraGlow : .white, lineWidth: 3))
                .shadow(color: lit ? AppColor.auraGlow.opacity(0.95) : .black.opacity(0.18),
                        radius: lit ? 9 : 3, y: lit ? 0 : 2)
            label(name)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lit ? "\(name), posted a session today" : name)
    }

    private var inviteFace: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColor.skyDeep)
                .frame(width: 50, height: 50)
                .background(AppColor.backgroundPrimary.opacity(0.94), in: Circle())
                .overlay(Circle().strokeBorder(AppColor.skyDeep.opacity(0.45),
                                               style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
            label("Invite")
        }
        .accessibilityLabel("Invite a friend")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .lineLimit(1)
            .frame(width: 60)
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
        "Tap iCloud, then Saved to iCloud (or See All), and make sure 808 is switched on.",
        "Come back here and tap Check again.",
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 8)
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
            } else if case .failed(let message) = model.unavailableReason {
                VStack(spacing: 10) {
                    Text("iCloud answered, but Friends couldn't load.")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        checking = true
                        Task { await model.load(); checking = false }
                    } label: {
                        Text(checking ? "Trying…" : "Try again")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(checking)
                }
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
            Text("When a friend you invite accepts and finishes their first session, your next \(InviteReward.sessionsPerFriend) sessions show the full results: every curve and every reading.")
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
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band(top: top)
                    VStack(alignment: .leading, spacing: 14) {
                        #if DEBUG
                        if model.testMode { testModePill }
                        #endif
                        searchField
                        if searched { searchResult }
                        if model.feed.isEmpty {
                            EmptyFeed(model: model, username: model.profile?.username ?? "")
                        } else {
                            ForEach(model.feed) { post in
                                PostCard(post: post, model: model) { reportTarget = .post(post.id) }
                            }
                            InviteButton(username: model.profile?.username ?? "", style: .quiet)
                                .padding(.top, 4)
                        }
                        // The bar is a safe-area inset so the scroll clears it
                        // on its own; this only clears the half of the plus
                        // that rises above it.
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 14)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            .modifier(StatusBarScrim(height: top, threshold: 160))
            .refreshable { await model.refresh() }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        // The band carries the title, so this page has no bar at all; the
        // pages pushed from it bring their own back button.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { id in
            PersonView(id: id, model: model)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, model: model)
        }
    }

    /// The title, your handle and requests in the sky; your friends standing
    /// on the meadow below them.
    private func band(top: CGFloat) -> some View {
        FriendsSky(height: top + 216) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Friends")
                            .font(DisplayFont.display(30, .heavy))
                            .foregroundStyle(ValleyGround.ink)
                        if let handle = model.profile.map({ "@" + $0.username }), handle.count > 1 {
                            Text(handle)
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(ValleyGround.inkSoft)
                        }
                    }
                    Spacer(minLength: 8)
                    requestsButton.padding(.top, 6)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, top + 10)
                Spacer(minLength: 0)
                FriendsOnTheMeadow(model: model)
                    .padding(.bottom, 4)
            }
        }
    }

    #if DEBUG
    private var testModePill: some View {
        HStack(spacing: 8) {
            Text("Test mode: a fake database on this device")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(ValleyGround.inkSoft)
            Spacer(minLength: 0)
            Button("Turn off") { Task { await model.setTestMode(false) } }
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.skyDeep)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
    }
    #endif

    /// Requests as a BUTTON.
    ///
    /// A waiting request used to be grey caption text floating above a search
    /// field, which made it the most missable thing in the product: this is the
    /// only screen in 808 where another person is waiting on the reader. It is
    /// gold when somebody is, the one gold thing in the sky, and a cream pill
    /// when nobody is, so the colour itself carries the news.
    private var requestsButton: some View {
        NavigationLink {
            RequestsView(model: model)
        } label: {
            let waiting = !model.incoming.isEmpty
            Text(waiting
                 ? "\(model.incoming.count) request\(model.incoming.count == 1 ? "" : "s")"
                 : "Requests")
                .font(.system(size: 13, weight: .bold, design: .rounded))
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColor.skyDeep)
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
        .padding(.horizontal, 16).padding(.vertical, 13)
        // A cream capsule: something you press, on the grass.
        .background(AppColor.backgroundPrimary.opacity(0.96), in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    @ViewBuilder
    private var searchResult: some View {
        Group {
            if let result {
                NavigationLink(value: result.id) {
                    PersonRow(profile: result, subtitle: "@" + result.username) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColor.skyDeep)
                    }
                }
                .buttonStyle(CardButtonStyle())
            } else {
                Text("Nobody with that name yet. Check the spelling, or invite them.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .whiteCard()
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
            Text("🙏").font(.system(size: 40)).padding(.top, 8)
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
        .padding(18)
        .whiteCard()
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
                    Text("\(news.remaining) sessions of evidence · starts with your next session")
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

    private var message: String { Self.message(for: username) }

    /// Aziz's wording (2026-09-14). The App Store link stays on its own line
    /// so the message still gets a friend to the download.
    static func message(for username: String) -> String {
        "Add me on 808 Meditate, the social media for meditation: @\(username)\n\(storeLink.absoluteString)"
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
        // Spacing (Melvin, 2026-09-18: "too crowded/dense, look at Strava").
        // The card used to bleed to both screen edges with 16pt inside it and
        // the photo running wall to wall, so nothing had air around it and
        // one card ran into the next. Now: an inset rounded card, one inset
        // constant for every child (`inset`), the photo inset and rounded
        // like the text, and a real gap between the groups. A feed is read at
        // arm's length while scrolling, so the white space is what separates
        // one person's sit from the next.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.inset).padding(.top, Self.inset)

            Text(post.title.isEmpty ? "Meditation" : post.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Self.inset).padding(.top, 14)

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Self.inset).padding(.top, 6)
            }

            // PHOTO FIRST, NUMBERS AFTER (2026-09-19). The four stats used to
            // sit in the middle of the card with the photo dangling off the
            // bottom, so the picture (the reason anybody stops scrolling) came
            // last and a row of figures interrupted the sentence somebody had
            // written. Who, what they called it, what it looked like, then the
            // numbers, then the reaction.
            if let url = post.photoURL {
                PostPhotoView(url: url)
                    .overlay(alignment: .bottomLeading) {
                        // The score rides on the photo, exactly as it does on a
                        // session card in the app. It leaves three columns that
                        // line up from card to card and keeps one amber object
                        // per post.
                        if post.score != nil { scoreCapsule.padding(11) }
                    }
                    .padding(.horizontal, Self.inset).padding(.top, 14)
            }

            HStack(spacing: 0) {
                if post.photoURL == nil, let score = post.score { stat("Score", "\(score)") }
                stat("Time", "\(post.minutes)m")
                stat("Day streak", "\(post.streak)")
                if let t = post.technique, !t.isEmpty { stat("Technique", t) }
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, 13)
            .overlay(alignment: .top) {
                Rectangle().fill(ValleyGround.quiet).frame(height: 1)
                    .padding(.horizontal, Self.inset)
            }

            footer
                .padding(.horizontal, Self.inset)
                .padding(.top, 16).padding(.bottom, Self.inset)
        }
        // White on the grass, like every card on the valley pages.
        .whiteCard(radius: 20)
    }

    /// One inset for every child of the card, so nothing sits closer to an
    /// edge than anything else.
    private static let inset: CGFloat = 18

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: post.author) {
                HStack(spacing: 12) {
                    PersonAvatar(name: author?.displayName, size: 42, photoURL: author?.avatarURL)
                    VStack(alignment: .leading, spacing: 3) {
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

    /// One column. Value over label, centred, equal width, so two posts line
    /// up down the feed the way two sessions line up in the app.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(DisplayFont.display(16, .heavy))
                .foregroundStyle(ValleyGround.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreCapsule: some View {
        Text(post.score.map(String.init) ?? "")
            .font(DisplayFont.display(16, .heavy))
            .foregroundStyle(AppColor.textOnAccent)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppColor.accentGold))
    }

    /// The pill on the left, just the emoji (Melvin, 2026-09-23: "It should
    /// not say 'nice session'. It should just show the prayer emoji inside
    /// the button, no text."); who gave one reads to its right, where the
    /// button used to sit. The button's job is now spoken through
    /// `accessibilityLabel` rather than read off the card.
    private var footer: some View {
        let who = model.reactions[post.id] ?? []
        let mine = model.hasReacted(to: post.id)
        return HStack(spacing: 10) {
            Button {
                Task { await model.toggleReaction(post.id) }
            } label: {
                // Full colour whether or not you have given one (Melvin,
                // 2026-09-23: faded, it read as unclickable). The pill's fill
                // says the state: sky before, gold once given.
                Text("🙏")
                    .font(.system(size: 17))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    // Filled, like every other button in the app: amber once
                    // you have given one, paper before. An outlined capsule
                    // was the last thin-line control in the product, and it
                    // made the one thing a reader can DO on this screen the
                    // quietest object on the card.
                    // Sky before (a choice), gold once given (the one gold
                    // thing on the card besides the score).
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
            .buttonStyle(.plain)
            .disabled(isMine)
            .accessibilityLabel("Nice session")

            Text(reactorLine(who))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
            Spacer()
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
        // fixed-size frame, so a wide image can never widen the card. Rounded
        // and inset by the caller, so it reads as one more element inside the
        // card rather than a band cut through it.
        AppColor.backgroundPrimary.opacity(0.4)
            .frame(maxWidth: .infinity)
            // 270, not 340. A selfie is 3:4, so at 340 a single post filled
            // the screen and the numbers under it were never on the same
            // screen as the picture they belong to.
            .frame(height: 270)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task { image = UIImage(contentsOfFile: url.path) }
    }
}

// MARK: - People

struct PersonAvatar: View {
    let name: String?
    var size: CGFloat = 30
    /// Their picture, when they have picked one. Otto otherwise.
    var photoURL: URL? = nil

    var body: some View {
        ProfilePortrait(photoURL: photoURL, size: size)
            .overlay(Circle().stroke(AppColor.accentGold, lineWidth: size > 40 ? 2 : 1.5))
    }
}

/// A person's picture, or Otto (Melvin, 2026-09-22: "can have otto be a
/// default if you dont want to pick anything"). One view, so a face is drawn
/// the same way on Profile, in the feed and on a person's page.
struct ProfilePortrait: View {
    var photoURL: URL?
    var size: CGFloat = 30

    @State private var photo: UIImage?

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                AppColor.sky
                OttoMark(size: size * 0.8, pose: .head)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: photoURL) {
            photo = photoURL.flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }
}

struct PersonRow<Trailing: View>: View {
    let profile: Profile
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(name: profile.displayName, size: 40, photoURL: profile.avatarURL)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 12)
        .fullyTappable()
    }
}

struct RequestsView: View {
    @ObservedObject var model: CommunityModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Sky behind the back button; the title rides beside it.
                    FriendsSky(height: proxy.safeAreaInsets.top + 56) { EmptyView() }
                    VStack(alignment: .leading, spacing: 8) {
                        if model.incoming.isEmpty && model.sent.isEmpty && model.blocked.isEmpty {
                            Text("No requests right now.")
                                .font(AppFont.callout)
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                                .whiteCard()
                        }
                        if !model.incoming.isEmpty {
                            GrassHeading(title: "Asking to be your friend")
                            group(model.incoming) { id in
                                smallButton("Accept", gold: true) { Task { await model.accept(id) } }
                            }
                        }
                        if !model.sent.isEmpty {
                            GrassHeading(title: "Sent").padding(.top, 6)
                            group(model.sent, subtitle: " \u{00B7} waiting") { id in
                                Button("Withdraw") { Task { await model.remove(id) } }
                                    .buttonStyle(.plain)
                                    .font(AppFont.caption.weight(.bold))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                        if !model.blocked.isEmpty {
                            GrassHeading(title: "Blocked").padding(.top, 6)
                            VStack(spacing: 0) {
                                ForEach(Array(model.blocked.enumerated()), id: \.element) { i, id in
                                    if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
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
                                    .padding(.vertical, 14)
                                }
                            }
                            .padding(.horizontal, 14)
                            .whiteCard()
                        }
                        InviteButton(username: model.profile?.username ?? "", style: .quiet)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // The title slot, not a leading item: iOS 26 wraps leading
            // toolbar items in a glass capsule, and a title in a button's
            // clothes reads as something to tap.
            ToolbarItem(placement: .principal) {
                Text("Requests")
                    .font(DisplayFont.display(19, .heavy))
                    .foregroundStyle(ValleyGround.ink)
            }
        }
        // No navigationDestination here: FeedView's, further up the same
        // stack, already routes profile ids. A second one for the same type
        // makes SwiftUI pick one arbitrarily.
        .task { await model.loadBlocked() }
    }

    /// One white card per group of people, rows on hairlines, rather than a
    /// card per person.
    private func group<Trailing: View>(_ ids: [String], subtitle: String = "",
                                       @ViewBuilder trailing: @escaping (String) -> Trailing) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                if let p = model.person(id) {
                    if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                    NavigationLink(value: id) {
                        PersonRow(profile: p, subtitle: "@" + p.username + subtitle) { trailing(id) }
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }
        .padding(.horizontal, 14)
        .whiteCard()
    }

    private func smallButton(_ title: String, gold: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(gold ? AppColor.textOnAccent : ValleyGround.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    if gold {
                        Capsule().fill(AppColor.accentGold)
                            .shadow(color: AppColor.accentGoldShade, radius: 0, y: 3)
                    } else {
                        Capsule().fill(AppColor.skyWash)
                    }
                }
                .padding(.bottom, gold ? 3 : 0)
        }
        .buttonStyle(.plain)
    }
}

/// "12 followers · 8 following" under a handle, the shape every social
/// profile uses (Melvin, 2026-09-18). Both numbers come from the edges that
/// already exist: following is who this person added, followers is who added
/// them, and a mutual pair is a friendship. Nothing new is stored.
///
/// Each half opens its list in its OWN sheet, hung on this view rather than
/// on the screen around it, because the Profile tab and the person page both
/// already present sheets and stacking them on one view is the
/// only-one-presents trap.
struct FollowLine: View {
    let followers: Int
    let following: Int
    /// Whose lists to open. Nil (a profile still loading) shows the numbers
    /// without making them tappable, rather than opening an empty list.
    var personID: String?

    @EnvironmentObject private var model: CommunityModel
    @State private var showing: FollowList?

    var body: some View {
        HStack(spacing: 6) {
            part(followers, followers == 1 ? "follower" : "followers", .followers)
            Text("·").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            part(following, "following", .following)
        }
        .sheet(item: $showing) { list in
            FollowListView(list: list, model: model)
        }
    }

    @ViewBuilder
    private func part(_ count: Int, _ label: String, _ which: FollowList.Which) -> some View {
        let text = Text("\(count) ").font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
            + Text(label).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        if let personID, count > 0 {
            Button { showing = FollowList(person: personID, which: which) } label: { text }
                .buttonStyle(.plain)
        } else {
            text
        }
    }
}

struct FollowList: Identifiable, Hashable {
    enum Which: String, Hashable { case followers, following }
    let person: String
    let which: Which
    var id: String { person + which.rawValue }
    var title: String { which == .followers ? "Followers" : "Following" }
}

/// The people behind one of the two numbers. Tapping one opens their page,
/// inside this sheet's own stack.
struct FollowListView: View {
    let list: FollowList
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String]?

    var body: some View {
        NavigationStack {
            Group {
                if let ids {
                    if ids.isEmpty {
                        Text(list.which == .followers
                             ? "Nobody yet. Invite someone to sit with you."
                             : "Nobody yet. Search for a friend by their username.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(AppMetrics.screenPadding)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(ids, id: \.self) { id in
                                    if let person = model.person(id) {
                                        NavigationLink(value: id) {
                                            PersonRow(profile: person, subtitle: "@" + person.username) { EmptyView() }
                                        }
                                        .buttonStyle(CardButtonStyle())
                                    }
                                }
                            }
                            .padding(AppMetrics.screenPadding)
                        }
                    }
                } else {
                    ProgressView().tint(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(list.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { PersonView(id: $0, model: model) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
        .task { ids = await model.follows(list) }
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

    private static let portrait: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Their portrait on the seam of the valley, the way your
                    // own sits on Profile.
                    FriendsSky(height: proxy.safeAreaInsets.top + 86) { EmptyView() }
                        .overlay(alignment: .bottom) {
                            ProfilePortrait(photoURL: profile?.avatarURL, size: Self.portrait)
                                .overlay(Circle().stroke(.white, lineWidth: 4))
                                .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
                                .offset(y: Self.portrait / 2 - 6)
                        }
                        .zIndex(1)
                    VStack(spacing: 12) {
                        identity
                        if relationship == .friends || isMe { stats }
                        if !posts.isEmpty {
                            HStack { GrassHeading(title: "Posts"); Spacer() }.padding(.top, 4)
                            ForEach(posts) { post in
                                PostCard(post: post, model: model) { reportTarget = .post(post.id) }
                            }
                        } else if relationship != .friends && !isMe {
                            VStack(spacing: 4) {
                                Text("Posts show once you are friends")
                                    .font(AppFont.callout.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("Their sessions appear here and in your feed.")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(18)
                            .background(AppColor.backgroundPrimary.opacity(0.94),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, -6)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                        Image(systemName: "ellipsis").foregroundStyle(ValleyGround.ink)
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
        .task { await reload(); await model.loadFollowCounts(id) }
    }

    private func reload() async {
        await model.loadPerson(id)
        relationship = await model.relationship(with: id)
        posts = await model.posts(by: id)
    }

    /// One white card, as on your own Profile: name, handle and since, the
    /// follow line, and the one button this relationship calls for.
    private var identity: some View {
        VStack(spacing: 5) {
            Text(profile?.displayName.isEmpty == false ? profile!.displayName : "@" + (profile?.username ?? ""))
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(["@" + (profile?.username ?? ""),
                  profile.map { "practicing since " + $0.createdAt.formatted(.dateTime.month(.abbreviated).year()) }]
                .compactMap { $0 }.joined(separator: " \u{00B7} "))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            if let counts = model.followCounts[id] {
                FollowLine(followers: counts.followers, following: counts.following, personID: id)
                    .padding(.top, 2)
            }
            if !isMe { relationshipButton.padding(.top, 8) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, Self.portrait / 2 + 12)
        .padding(.bottom, 16)
        .whiteCard(radius: 22)
    }

    /// One card, three numbers read off it, not three tiles.
    private var stats: some View {
        HStack(spacing: 0) {
            // A post's streak is the streak on the day it was sat. Only the
            // last day or so still describes today.
            statColumn(posts.first.flatMap { Date().timeIntervalSince($0.practicedAt) < 36 * 3600 ? "\($0.streak)" : nil } ?? "\u{2013}",
                       "streak")
            statColumn("\(posts.count)", "posts")
            // Only the sits something measured: a phone session has no score,
            // and counting it as a zero would drag an average nobody earned.
            let scores = posts.compactMap(\.score)
            statColumn(scores.isEmpty ? "\u{2013}" : "\(scores.reduce(0, +) / scores.count)", "avg score")
        }
        .padding(.vertical, 12)
        .whiteCard(radius: 18)
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DisplayFont.display(19, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
