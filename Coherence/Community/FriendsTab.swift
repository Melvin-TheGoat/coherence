import SwiftUI
import SwiftData

/// Friends (COMMUNITY.md, mockup `mockups/friends.html`). Mutual friends,
/// requests behind a count, search by handle, an invite, and how often
/// someone meditates. No feed, no posts (Melvin, 2026-09-27: "get rid of the
/// feed, no more posting with photos/videos since its a big privacy policy
/// change"). The first open claims a real username; the tab is honest about
/// iCloud being unavailable rather than pretending to load.
///
/// **A screen now, not a tab** — presented as a full sheet from Home (a plus
/// or a button opens it; the tab bar itself is somebody else's to wire). The
/// type keeps its old name so every call site only needs the new `onClose`.
struct FriendsTab: View {
    @Environment(\.modelContext) private var context
    @Query private var users: [User]
    @EnvironmentObject private var model: CommunityModel
    /// Set while the onboarding tour shows this tab under its dim.
    @Environment(\.tourTab) private var tourTab
    /// Closes the screen when it is presented as a sheet. nil hides the
    /// button — a host that still wants this embedded in a tab bar passes
    /// nothing and gets exactly the old behaviour.
    var onClose: (() -> Void)? = nil
    /// "Not now" on Create your profile when this is a tab rather than a
    /// sheet: the host moves to Home. As a sheet, `onClose` does the job.
    var onDecline: (() -> Void)? = nil

    private var user: User? { users.first }
    @Environment(\.tabBarClearance) private var tabBarClearance

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
                                        .onValley()
                                        // Clear of the close button in the corner.
                                        .padding(.leading, onClose == nil ? 0 : 44)
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
                                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .padding(.horizontal, AppMetrics.screenPadding)
                                .padding(.bottom, 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .top)
                    .modifier(NoTopEdgeHaze())
                    .toolbar(.hidden, for: .navigationBar)
                case .needsUsername:
                    // Optional (Melvin, 2026-09-29): "Not now" leaves the
                    // screen, and it offers the profile again next time.
                    CreateProfileView(model: model,
                                      suggested: user?.username ?? "",
                                      nickname: user?.displayName ?? "") { handle in
                        if handle == nil { (onClose ?? onDecline)?() }
                    }
                case .ready:
                    FriendsHomeView(model: model, myDisplayName: user?.displayName ?? "",
                                    roomForClose: onClose != nil)
                }
            }
            // The valley, like Home, Profile and the guide (Aziz, 2026-09-22,
            // `mockups/friends-valley.html`). The last page left on plain
            // cream with brown ink.
            .background(ValleyGround.meadow.ignoresSafeArea())
            // The tab bar's inset does not reach inside this NavigationStack,
            // so the last row sat under the bar (see ProfileTab). Zero when
            // this is a sheet, which is what makes the close button below
            // land in the right place either way.
            .safeAreaPadding(.bottom, tabBarClearance)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                if let onClose { CloseCapsule(action: onClose) }
            }
        }
        .task {
            // The tour passing through is not somebody opening Friends, and
            // counting it would put every new install in the number.
            if tourTab == nil { Analytics.track(.friendsOpened) }
            await model.load()
            // Somebody opening Friends with a profile has taken it up, so
            // publishing may resume after a sign-out paused it (Melvin,
            // 2026-09-29). Covers the person who signed back in while iCloud
            // was off and so never met onboarding's profile step with it.
            if tourTab == nil, model.hasProfile { model.resumePublishing() }
        }
        .refreshesWhileShown(enabled: tourTab == nil) { await model.refresh(quiet: true) }
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

/// The close button for a screen presented as a sheet: a cream capsule, the
/// same material Cancel and Done wear everywhere else in the app (Save
/// session's X, the report sheet's Cancel). Top-left, clear of the status bar.
private struct CloseCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 34, height: 34)
                .background(AppColor.backgroundPrimary.opacity(0.94), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .padding(.leading, AppMetrics.screenPadding)
        .padding(.top, 8)
    }
}

// MARK: - The valley

/// Checks again every few seconds while a Friends screen is on screen and
/// the app is in front (Aziz, 2026-10-01: a request and an accept from the
/// other phone only showed after leaving the app and coming back). There
/// is no push from the public database, so this is how a request arriving,
/// an accept, or a friend's new session shows up while somebody watches.
/// Stops the moment the screen goes, and never runs in the background.
private struct RefreshesWhileShown: ViewModifier {
    let enabled: Bool
    let action: () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    static let every: Duration = .seconds(10)

    func body(content: Content) -> some View {
        content.task(id: enabled && scenePhase == .active) {
            guard enabled, scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.every)
                // A cancelled sleep throws and falls through; it must not
                // run the refresh on the way out.
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }
}

extension View {
    func refreshesWhileShown(enabled: Bool = true, _ action: @escaping () async -> Void) -> some View {
        modifier(RefreshesWhileShown(enabled: enabled, action: action))
    }
}

/// Meadow behind the status bar once the band has scrolled away. This page
/// has no navigation bar, so iOS has no top edge to fade, and without this
/// the feed's cards slid under the clock with nothing behind it. Invisible
/// while the sky is showing, which is the whole point of the band.
struct StatusBarScrim: ViewModifier {
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
    /// Draw the valley this tall and show only its top `height`: a short
    /// band then keeps the sky and hills at their natural size instead of
    /// squashing the whole scene, which ran the ridge line through the
    /// words. nil draws the scene at the band's own height.
    var sceneHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ValleyScene(progress: 0, showsFigure: false, clock: true)
            .frame(height: max(height, sceneHeight ?? height))
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .clipped()
            .fadesIntoMeadow()
            .overlay { content }
    }
}

// MARK: - Unavailable

/// Friends run on iCloud: the phone's iCloud account is who you are, and your
/// profile, username and friend list are records in 808's PUBLIC CloudKit
/// database, which Apple runs (808 has no server of its own). The card says
/// why, then exactly what to do
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
            // Not "your own iCloud account" (Melvin, 2026-09-29): a profile
            // is a record in 808's public iCloud database, readable by anyone
            // who looks the username up. The private database only syncs
            // sessions.
            Text("808 uses your iCloud account to know it's you. Your username, profile and friend list are kept in 808's public iCloud database, run by Apple, so friends can find you. 808 has no server of its own.")
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

/// The reward, stated once, on the claim screen and when there is nobody
/// here yet. The mechanics live in feature 4 (the grant); the copy is here so
/// the promise and the code ship in the same build.
private struct InviteRewardNote: View {
    /// While 808 is premium only, every member already sees every result, so
    /// banked sessions of evidence would be a reward with nothing in it
    /// (Melvin, 2026-09-29). The award is what a friend brings then.
    private var title: String {
        Monetization.premiumOnly ? "Bring a friend." : "Bring a friend, see the evidence."
    }
    private var detail: String {
        Monetization.premiumOnly
            ? "When a friend you invite accepts and finishes their first session, the Brought a friend award lands on your shelf."
            : "When a friend you invite accepts and finishes their first session, your next \(InviteReward.sessionsPerFriend) sessions show the full results: every curve and every reading."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.calmAccent)
            Text(detail)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColor.calmAccent.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Home

/// The main screen: your handle, search, and the friends you already have —
/// no feed, no posts (Melvin, 2026-09-27). Tapping a friend opens their page,
/// which is where "how often do they meditate" is read in full.
struct FriendsHomeView: View {
    @ObservedObject var model: CommunityModel
    let myDisplayName: String
    /// The screen is a sheet with a close button in the top-left corner.
    var roomForClose = false

    @State private var query = ""
    @State private var result: Profile?
    @State private var searched = false

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band(top: top)
                    VStack(alignment: .leading, spacing: 14) {
                        #if DEBUG
                        if model.testMode && !StoreShots.on { testModePill }
                        #endif
                        searchField
                        if searched { searchResult }
                        GrassHeading(title: "Friends")
                        friendsSection
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
            .modifier(StatusBarScrim(height: top, threshold: 100))
            .refreshable { await model.refresh() }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        // The band carries the title, so this page has no bar at all; the
        // pages pushed from it bring their own back button.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { id in
            PersonView(id: id, model: model)
        }
        .navigationDestination(for: FriendsRoute.self) { route in
            switch route {
            case .requests: RequestsView(model: model)
            }
        }
    }

    /// Every mutual friend, with how often they meditate — the thing that
    /// replaced the feed. Tapping one opens their page.
    @ViewBuilder
    private var friendsSection: some View {
        if model.friends.isEmpty {
            EmptyFriends(model: model, username: model.profile?.username ?? "")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.friends.enumerated()), id: \.element) { i, id in
                    if let p = model.person(id) {
                        if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                        NavigationLink(value: id) {
                            PersonRow(profile: p, subtitle: "@" + p.username, practice: practiceLine(p.practice)) {
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
        }
    }

    /// The title, your handle, Invite and Requests in the sky.
    ///
    /// **No row of friends' faces on the meadow any more** (Melvin,
    /// 2026-09-25: "the profile photos at the top are weird looking, get rid
    /// of them, and raise everything else up"). The band is only as tall as
    /// its words need, so the search and the friends list sit about 100pt
    /// higher. A friend's page is still a tap on their name below, or on
    /// your followers and following in Profile; Invite, which was the last
    /// face in that row, is a pill beside Requests.
    private func band(top: CGFloat) -> some View {
        // Cut at 62% of the scene: sky and hills, down to the near green
        // ridge, which runs straight into the page's own meadow.
        FriendsSky(height: top + 116, sceneHeight: (top + 116) / 0.62) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Friends")
                            .font(DisplayFont.display(30, .heavy))
                            .onValley()
                        if let handle = model.profile.map({ "@" + $0.username }), handle.count > 1 {
                            Text(handle)
                                .font(AppFont.caption.weight(.semibold))
                                .onValley(soft: true)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    // Clear of the close button, when this is a sheet from Home.
                    .padding(.leading, roomForClose ? 44 : 0)
                    // A long handle gives way before the pills do: it was the
                    // handle's width that pushed "Requests" onto two lines
                    // (Melvin, 2026-09-27, the last "s" alone underneath).
                    .layoutPriority(-1)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        inviteButton
                        requestsButton
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, top + 10)
                Spacer(minLength: 0)
            }
        }
    }

    /// Invite, a cream pill like Requests at rest: never gold, which is kept
    /// for a request somebody is waiting on.
    private var inviteButton: some View {
        ShareLink(item: InviteButton.message(for: model.profile?.username ?? "")) {
            Label("Invite", systemImage: "person.badge.plus")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(ValleyGround.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppColor.backgroundPrimary.opacity(0.94))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2))
                .padding(.bottom, 3)
        }
        .simultaneousGesture(TapGesture().onEnded { Analytics.track(.inviteShared) })
        .accessibilityLabel("Invite a friend")
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
    ///
    /// Pushed by VALUE, like the profiles inside it (2026-10-01). A
    /// destination-closure link here put Requests outside the stack's path,
    /// so tapping a person in it appended them to the path UNDER Requests:
    /// the page slid in, Requests came straight back on top, and Back
    /// revealed the profile. Every link in this stack goes by value.
    private var requestsButton: some View {
        NavigationLink(value: FriendsRoute.requests) {
            let waiting = !model.incoming.isEmpty
            Text(waiting
                 ? "\(model.incoming.count) request\(model.incoming.count == 1 ? "" : "s")"
                 : "Requests")
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
                    PersonRow(profile: result, subtitle: "@" + result.username,
                             practice: practiceLine(result.practice)) {
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

private struct EmptyFriends: View {
    @ObservedObject var model: CommunityModel
    let username: String

    var body: some View {
        VStack(spacing: 12) {
            Text("🙏").font(.system(size: 40)).padding(.top, 8)
            Text("No friends yet")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Search for someone by their @username, or invite a friend to 808.")
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

    /// While 808 is premium only, a lapsed membership meets the paywall at
    /// launch, so sessions "banked in case your membership lapses" could
    /// never be used. The award is the whole of it then (Melvin, 2026-09-29).
    private var detail: String {
        if Monetization.premiumOnly {
            return "You brought them here. The Brought a friend award is on your shelf."
        }
        return store.entitlements.paid
            ? "You brought them here. The Brought a friend award is on your shelf, and \(news.remaining) sessions of full evidence are banked in case your membership ever lapses."
            : "You brought them here. Your next \(news.remaining) sessions show the full evidence: every curve, every reading."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🙏").font(.system(size: 36)).padding(.top, 8)
            Text("\(news.friendName) sat their first session")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !Monetization.premiumOnly && !store.entitlements.paid {
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
        "Add me on 808 Meditate: @\(username)\n\(storeLink.absoluteString)"
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
                // An empty person, Instagram's default (Melvin, 2026-09-27:
                // "I dont want otto to be the default photo"): a white
                // silhouette whose shoulders run off the bottom of the circle.
                AppColor.hairline
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.66)
                    .offset(y: size * 0.16)
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
    /// How often they meditate (Melvin, 2026-09-27), under the handle:
    /// "5 sessions this week · 7 day streak", or nil to leave it off (a
    /// blocked person's row, say, where the fact is not the point).
    var practice: String? = nil
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
                if let practice {
                    Text(practice)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColor.calmAccent)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 12)
        .fullyTappable()
    }
}

/// "5 sessions this week · 7 day streak", or "Last meditated Tuesday" once
/// this week has been quiet, or "No sessions yet" for someone brand new.
/// What a friend's page and every row in the follow lists and search say
/// about how often they meditate — never a score, a heart rate, or a curve
/// (the rule at the top of `CommunityRecords.swift`).
func practiceLine(_ published: PracticeStats) -> String {
    // As they stand today, not as they were when last published.
    let stats = published.asSeen()
    guard stats.totalSessions > 0 else { return "No sessions yet" }
    if stats.sessions7d > 0 {
        var parts = ["\(stats.sessions7d) session\(stats.sessions7d == 1 ? "" : "s") this week"]
        if stats.currentStreak > 0 {
            parts.append("\(stats.currentStreak) day streak")
        }
        return parts.joined(separator: " · ")
    }
    guard let last = stats.lastSessionAt else { return "No sessions yet" }
    return "Last meditated " + SessionListSupport.relativeDay(last).lowercased()
}

/// The pages Friends pushes that are not a person. A value, not a
/// destination closure, so they share the stack's path with the profile ids.
enum FriendsRoute: Hashable {
    case requests
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
                    .onValley()
            }
        }
        // No navigationDestination here: FriendsHomeView's, further up the
        // same stack, already routes profile ids. A second one for the same
        // type makes SwiftUI pick one arbitrarily.
        .task { await model.loadBlocked() }
        .refreshesWhileShown { await model.refresh(quiet: true) }
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
                        PersonRow(profile: p, subtitle: "@" + p.username + subtitle,
                                 practice: practiceLine(p.practice)) { trailing(id) }
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

/// "12 friends" under a handle. Friends only, no followers or following
/// (Aziz, 2026-10-01: "only if they accept we are friends"): a request
/// nobody answered counts for nobody. Tapping it opens the list, in its OWN
/// sheet hung on this view, because the Profile tab and the person page both
/// already present sheets and stacking them on one view is the
/// only-one-presents trap.
struct FriendsLine: View {
    let count: Int
    /// Whose friends to open. Nil (a profile still loading) shows the number
    /// without making it tappable, rather than opening an empty list.
    var personID: String?

    @EnvironmentObject private var model: CommunityModel
    @State private var showing: FriendsList?

    var body: some View {
        let text = Text("\(count) ").font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
            + Text(count == 1 ? "friend" : "friends").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        Group {
            if let personID, count > 0 {
                Button { showing = FriendsList(person: personID) } label: { text }
                    .buttonStyle(.plain)
            } else {
                text
            }
        }
        .sheet(item: $showing) { list in
            FriendsListView(list: list, model: model)
        }
    }
}

struct FriendsList: Identifiable, Hashable {
    let person: String
    var id: String { person }
}

/// The people behind the count. Tapping one opens their page, inside this
/// sheet's own stack.
struct FriendsListView: View {
    let list: FriendsList
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String]?

    var body: some View {
        NavigationStack {
            Group {
                if let ids {
                    if ids.isEmpty {
                        Text("No friends yet.")
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
                                            PersonRow(profile: person, subtitle: "@" + person.username,
                                                     practice: practiceLine(person.practice)) { EmptyView() }
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
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { PersonView(id: $0, model: model) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
        .task { ids = await model.friendsList(of: list.person) }
    }
}

/// A person: header, how often they meditate, the relationship button, and
/// the menu guideline 1.2 checks for (Remove, Report, Block). No posts, no
/// feed (Melvin, 2026-09-27) — everything here is read off their public
/// `Profile` record, which is why it shows for a stranger from search just as
/// it does for a friend.
struct PersonView: View {
    let id: String
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss

    @State private var relationship: CommunityStore.Relationship = .none
    @State private var reportTarget: ReportSheet.Target?
    @State private var confirmBlock = false
    @State private var busy = false

    private var profile: Profile? { model.person(id) }
    private var isMe: Bool { id == model.myID }
    /// Someone I blocked: the page keeps their name and offers Unblock, and
    /// shows nothing else of theirs (no stats, no follow lists, no "since").
    private var blocked: Bool { model.isBlocked(id) }

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
                                .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 4))
                                .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
                                .offset(y: Self.portrait / 2 - 6)
                        }
                        .zIndex(1)
                    VStack(spacing: 12) {
                        identity
                        if !blocked { stats }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, -6)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            // Pull to see a request or an accept the other phone just made.
            .refreshable { await reload(); await model.loadFriendCount(id) }
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
                        if relationship == .friends && !blocked {
                            Button("Remove friend") { Task { await model.remove(id); await reload() } }
                        }
                        Button("Report", role: .destructive) { reportTarget = .profile(id) }
                        if blocked {
                            Button("Unblock") { Task { await model.unblock(id); await reload() } }
                        } else {
                            Button("Block", role: .destructive) { confirmBlock = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis").onValley()
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
            // True of a private, one-sided block (CommunityStore's header):
            // their requests never arrive and nothing tells them. It does
            // NOT say they can't find you: your profile stays public to
            // anyone with your username, them included.
            Text("They won't be able to reach you, and they won't be told. You won't see them in Friends. You can undo this from Friends → Requests → Blocked.")
        }
        .task { await reload(); await model.loadFriendCount(id) }
        .refreshesWhileShown { await reload(); await model.loadFriendCount(id) }
    }

    private func reload() async {
        await model.loadPerson(id)
        relationship = await model.relationship(with: id)
    }

    /// One white card, as on your own Profile: name, handle and since, the
    /// follow line, and the one button this relationship calls for.
    private var identity: some View {
        VStack(spacing: 5) {
            Text(profile?.displayName.isEmpty == false ? profile!.displayName : "@" + (profile?.username ?? ""))
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(["@" + (profile?.username ?? ""),
                  blocked ? nil : profile.map { "practicing since " + $0.createdAt.formatted(.dateTime.month(.abbreviated).year()) }]
                .compactMap { $0 }.joined(separator: " \u{00B7} "))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            if !blocked, let count = model.friendCounts[id] {
                FriendsLine(count: count, personID: id)
                    .padding(.top, 2)
            }
            if blocked {
                Text("Blocked")
                    .font(AppFont.caption.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().stroke(AppColor.textSecondary.opacity(0.35), lineWidth: 1))
                    .padding(.top, 8)
            } else if !isMe {
                relationshipButton.padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, Self.portrait / 2 + 12)
        .padding(.bottom, 16)
        .whiteCard(radius: 22)
    }

    /// How often they meditate, three numbers off their public
    /// `PracticeStats` (Melvin, 2026-09-27) — never a score, which this card
    /// carried nowhere even when it read from posts.
    private var stats: some View {
        let p = (profile?.practice ?? .empty).asSeen()
        return HStack(spacing: 0) {
            statColumn("\(p.currentStreak)", "day streak")
            statColumn("\(p.sessions7d)", "this week")
            statColumn("\(p.totalSessions)", "total")
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
    /// nil while choosing; true once saved (the sheet thanks them); false
    /// when it couldn't be sent, so they can try again.
    @State private var sent: Bool?
    @State private var sending = false

    /// About a profile, since there are no posts to report any more (Melvin,
    /// 2026-09-29: "Not a meditation" was a reason for a post).
    private let reasons = ["Pretending to be someone else", "Harassment or hate", "Nudity or violence", "Spam", "Something else"]

    var body: some View {
        NavigationStack {
            Group {
                if sent == true { thanks } else { form }
            }
            .screenBackground()
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if sent != true { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    /// Said once the report is in (App Review pass, 2026-09-30).
    private var thanks: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(OnboardingGreen.fill)
            Text("Thanks for telling us")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("A person reads every report, usually within a day.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 10)
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var form: some View {
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
                    Text("A person reads every report, usually within a day. People who keep doing it are removed. support@meditate808.com")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if sent == false {
                        Text("Couldn't send the report. Check your connection and try again.")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    Button {
                        sending = true
                        Task {
                            let ok = await model.report(target.record, as: target.kind,
                                                        reason: [reason, detail].filter { !$0.isEmpty }.joined(separator: ": "))
                            sending = false
                            withAnimation(.easeOut(duration: 0.2)) { sent = ok }
                        }
                    } label: { Text(sending ? "Sending…" : "Send report") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(reason.isEmpty || sending)
                    .opacity(reason.isEmpty ? 0.55 : 1)
                }
                .padding(AppMetrics.screenPadding)
            }
    }
}
