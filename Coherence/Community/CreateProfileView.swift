import SwiftUI
import SwiftData
import PhotosUI

/// **Create your profile**: a photo and a real @username, separate from the
/// nickname (Aziz, 2026-09-14: "your nickname and your username are two
/// different things"). One screen, three doors:
/// - the last onboarding step, right after Sign in;
/// - `FriendsIntroView`, the one-time prompt for people who finished
///   onboarding before Friends existed;
/// - the Friends tab, for anyone who still has none. (Save session used to be
///   a fourth door, back when it could open Friends sharing; posting was
///   removed 2026-09-27 and took that door with it.)
///
/// **Optional** (Melvin, 2026-09-29, reversing "required, per Aziz"). Every
/// door offers "Not now": App Review 5.1.1 does not let an app require a
/// public profile its core function does not need, and a meditation timer
/// does not need one. Onboarding moves on exactly as it would after a
/// profile, the Friends screen closes, and the one-time intro never comes
/// back. With no iCloud the same exit reads "Continue without a profile".
///
/// **Claiming a handle needs the community rules agreed first** (guideline
/// 1.2): a required tick, a link to the Terms (section 6a), and one line
/// saying what anyone who looks the handle up will see. Mockup:
/// `mockups/friends-v2.html`, sections 1 and 2. Friends-gated.
struct CreateProfileView: View {
    @ObservedObject var model: CommunityModel
    /// The username typed earlier (onboarding's old field, or 1.0's cosmetic
    /// one), offered first. It was never reserved, so it may be taken.
    let suggested: String
    /// The nickname so far. Editable here so the difference is visible.
    let nickname: String
    /// Called with the claimed handle, or nil when the user chose "Not now"
    /// (or continued without iCloud).
    let onDone: (String?) -> Void

    /// When the community rules were agreed to on this phone, set when a
    /// handle is claimed with the box ticked. Edit profile reads it; a new
    /// profile never does. Cleared by sign-out and Delete account
    /// (`CommunityModel.signedOut`), so the next person agrees for themselves.
    static let rulesAcceptedKey = "friends.rulesAcceptedAt.v1"

    @Environment(\.modelContext) private var context
    /// Non-zero when this is the Friends TAB: the tab bar's raised plus
    /// stands above the bar, so the buttons sit higher to clear it.
    @Environment(\.tabBarClearance) private var tabBarClearance
    /// Set while the onboarding tour shows the Friends tab under its dim.
    /// The field is never focused then: the keyboard would come up over
    /// Otto's line and the tour's Next (Melvin, 2026-09-29).
    @Environment(\.tourTab) private var tourTab
    /// True anywhere inside onboarding, the tour included.
    @Environment(\.onboardingSharedGround) private var inOnboardingFlow
    @Query private var users: [User]

    @State private var handle = ""
    @State private var name = ""
    @State private var availability: CommunityModel.Availability?
    @State private var checking = false
    @State private var claiming = false
    @State private var photo: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var showCamera = false
    /// **A `PhotosPicker` placed AS a `Menu` item does not reliably present**
    /// (verified on-device and in the simulator, 2026-09-23: "choose from
    /// library doesn't work"). The Menu dismisses itself the instant an item
    /// is tapped, and that teardown races the picker's own presentation, so
    /// the system sheet silently never appears. "Take a photo" beside it
    /// never had this problem because it only sets a flag and lets a
    /// `.fullScreenCover` outside the Menu do the presenting. Same fix here:
    /// the Menu row only flips this, and `.photosPicker(isPresented:)` below
    /// (also outside the Menu) does the showing.
    @State private var showLibraryPicker = false
    @State private var suggestions: [String] = []
    @FocusState private var focused: Bool
    /// The nickname field has the keyboard. On a short screen the pinned
    /// buttons ride up with the keyboard and covered this field, so the page
    /// scrolls it into view (App Review pass, 2026-09-30).
    @FocusState private var nameFocused: Bool
    /// The community rules box (guideline 1.2). A new profile always starts
    /// unticked, whoever agreed on this phone before (Melvin, 2026-09-29: the
    /// box came up ticked for the next person to create a profile here).
    /// Only Edit profile starts ticked, and only when the rules were agreed
    /// on this phone (`seedAgreement`).
    @State private var agreed = false
    /// The box was tapped, so the screen never overrides the person's choice.
    @State private var agreementTouched = false
    /// The Terms, opened from the rules row. Presented from that row, not
    /// from this view, which already carries a camera cover and the photo
    /// picker (stacked presentations on one view are the only-one-presents
    /// trap).
    @State private var legalDoc: LegalDoc?
    /// "Remove photo" on a profile that already has one: the published photo
    /// comes down when the profile is saved (Melvin, 2026-09-29). It used to
    /// clear only a photo picked on this screen, so the one friends saw
    /// stayed up.
    @State private var removePublishedPhoto = false

    /// A profile already exists: same screen, edit wording.
    private var editing: Bool { !(model.profile?.username ?? "").isEmpty }

    /// Onboarding's own profile step, not the tour passing the Friends tab.
    private var onboardingStep: Bool { inOnboardingFlow && tourTab == nil }

    /// The photo friends currently see, unless it is on its way out.
    private var publishedPhoto: URL? { removePublishedPhoto ? nil : model.profile?.avatarURL }

    private var canSave: Bool { availability == .available && agreed && !claiming }

    /// In the valley (Melvin, 2026-09-27: "looks plain, make it on theme"):
    /// the words on a band of sky, the portrait sitting on the seam the way
    /// Profile seats it, and the two fields on one sand card on the grass.
    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    FriendsSky(height: top + 150, sceneHeight: (top + 150) / 0.62) {
                        VStack(spacing: 6) {
                            Text(editing ? "Edit profile" : "Create your profile")
                                .font(DisplayFont.display(28, .heavy))
                                .onValley()
                            Text("Your username is how friends find you. It's yours alone.")
                                .font(AppFont.callout)
                                .onValley(soft: true)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, top + 12)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .overlay(alignment: .bottom) {
                        photoPicker.offset(y: 62)
                    }
                    .zIndex(1)

                    VStack(alignment: .leading, spacing: 0) {
                        fieldLabel("Username")
                        HStack(spacing: 6) {
                            Text("@").foregroundStyle(AppColor.textSecondary)
                            TextField("username", text: $handle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .textContentType(.username)
                                .focused($focused)
                                .onChange(of: handle) { _, new in
                                    let cleaned = Username.normalize(new) ?? ""
                                    if cleaned != new { handle = cleaned }
                                    check()
                                }
                        }
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(14)
                        .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        statusLine.padding(.top, 7)

                        fieldLabel("Nickname")
                        TextField("What friends call you", text: $name)
                            .textContentType(.nickname)
                            .focused($nameFocused)
                            .id("nickname")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(14)
                            .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        rulesAgreement.padding(.top, 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 18)
                    .whiteCard(radius: 20)
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 104)

                    if model.phase == .unavailable {
                        Text("No iCloud on this iPhone. Usernames are saved to iCloud, so you can finish setting up now and create your profile once iCloud is on.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(14)
                            .whiteCard(radius: 16)
                            .padding(.horizontal, AppMetrics.screenPadding)
                            .padding(.top, 14)
                    }
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(ValleyGround.meadow.ignoresSafeArea())
            .onChange(of: nameFocused) { _, now in
                guard now else { return }
                Task {
                    // After the keyboard has risen, or the scroll aims at the
                    // old visible area.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo("nickname", anchor: .center) }
                }
            }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { claim() } label: {
                    Text(claiming ? "Saving…" : (editing ? "Save" : "Create profile"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .saturation(canSave || claiming ? 1 : 0.2)
                .brightness(canSave || claiming ? 0 : -0.25)
                // Friends is optional: every door that creates a profile can
                // also decline one. Edit profile has its own Cancel, except on
                // onboarding's profile step, where somebody who signed back in
                // meets the profile they already have and needs a way on that
                // changes nothing (Melvin, 2026-09-29).
                if !editing {
                    Button(model.phase == .unavailable ? "Continue without a profile" : "Not now") { notNow() }
                        .font(AppFont.callout.weight(.semibold))
                        .onValley()
                } else if onboardingStep {
                    Button("Continue") { keepAsItIs() }
                        .font(AppFont.callout.weight(.semibold))
                        .onValley()
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, tabBarClearance > 0 ? 32 : 8)
            .background(
                LinearGradient(stops: [.init(color: ValleyGround.meadow.opacity(0), location: 0),
                                       .init(color: ValleyGround.meadow, location: 0.4)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom))
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(device: .front) { photo = $0 }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    photo = ui
                }
                pick = nil
            }
        }
        .task {
            seedAgreement()
            await model.load()
            seedAgreement()
            // A reinstall or Edit profile already has a reserved handle and
            // name in iCloud; those win over anything typed locally.
            if handle.isEmpty { handle = model.profile?.username ?? "" }
            if handle.isEmpty { handle = Username.normalize(suggested) ?? "" }
            if name.isEmpty { name = model.profile?.displayName ?? "" }
            if name.isEmpty { name = nickname }
            if handle.isEmpty {
                if tourTab == nil { focused = true }
            } else {
                check()
            }
        }
    }

    // MARK: - Pieces

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.top, 22)
            .padding(.bottom, 7)
    }

    /// Profile photos come from the camera OR the library. The BeReal rule is
    /// for posts only: a profile picture is chosen, not proof of a session.
    private var photoPicker: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
            }
            // A plain Button, not a `PhotosPicker` menu item — see
            // `showLibraryPicker`'s doc comment for why the latter doesn't
            // reliably present.
            Button { showLibraryPicker = true } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
            if photo != nil || publishedPhoto != nil {
                Button("Remove photo", role: .destructive) {
                    photo = nil
                    if model.profile?.avatarURL != nil { removePublishedPhoto = true }
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 104, height: 104).clipShape(Circle())
                    } else if let current = publishedPhoto {
                        PersonAvatar(name: name, size: 104, photoURL: current)
                    } else {
                        // The empty person until they pick one, the default
                        // everywhere in the app, with a camera badge saying
                        // it can change.
                        ProfilePortrait(photoURL: nil, size: 104)
                    }
                }
                .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 4))
                .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.textOnAccent)
                        .frame(width: 32, height: 32)
                        .background(AppColor.accentGold, in: Circle())
                        .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 3))
                        .offset(x: 2, y: 2)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if handle.isEmpty {
                Text(" ")
            } else if checking {
                Text("Checking…").foregroundStyle(AppColor.textSecondary)
            } else {
                switch availability {
                case .available:
                    Text("✓ @\(handle) is available").foregroundStyle(AppColor.calmAccent)
                case .taken:
                    Text(suggestions.isEmpty
                         ? "@\(handle) is taken."
                         : "@\(handle) is taken. Try " + suggestions.map { "@" + $0 }.joined(separator: " or "))
                        .foregroundStyle(AppColor.textSecondary)
                case .invalid:
                    Text("Letters, numbers, dots and underscores only.").foregroundStyle(AppColor.textSecondary)
                case .notAllowed:
                    Text("That username isn't allowed on 808. Try another.").foregroundStyle(AppColor.textSecondary)
                case .failed(let why):
                    Text(why).foregroundStyle(AppColor.textSecondary)
                case .none:
                    Text(" ")
                }
            }
        }
        .font(AppFont.caption.weight(.semibold))
    }

    // MARK: - Actions

    private func check() {
        let current = handle
        guard !current.isEmpty else { availability = nil; suggestions = []; return }
        checking = true
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, current == handle else { return }
            let result = await model.availability(of: current)
            var free: [String] = []
            if result == .taken {
                for candidate in Self.alternatives(for: current) where free.count < 2 {
                    if await model.availability(of: candidate) == .available { free.append(candidate) }
                }
            }
            if current == handle { availability = result; suggestions = free; checking = false }
        }
    }

    /// Nearby handles to offer when one is taken: a dotted and an underscored
    /// 808 variant, then a two-digit suffix. Pure, so it is testable.
    static func alternatives(for handle: String) -> [String] {
        let base = String(handle.prefix(Username.maxLength - 4))
        return [base + ".808", base + "_808", base + "\(Int.random(in: 10...99))"]
            .compactMap(Username.normalize)
    }

    /// The community rules, agreed before a handle can be claimed
    /// (guideline 1.2, Melvin, 2026-09-29), with the one line that says what
    /// a handle makes public.
    private var rulesAgreement: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { agreed.toggle(); agreementTouched = true } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(agreed ? AppColor.skyDeep : AppColor.textSecondary)
                    Text("I agree to the community rules")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(agreed ? .isSelected : [])
            .accessibilityHint("Required to create a profile")

            Button("Read the community rules") { legalDoc = .terms }
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.leading, 30)

            Text("Anyone who looks up your @username sees your name, photo, streak, how often you meditate, and your friends.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $legalDoc) { LegalDocSheet(doc: $0) }
    }

    /// Edit profile starts ticked when the rules were agreed on this phone
    /// and the profile being edited exists. Run before and after loading,
    /// because the profile may only arrive with the load.
    private func seedAgreement() {
        guard !agreementTouched, editing,
              UserDefaults.standard.object(forKey: Self.rulesAcceptedKey) != nil else { return }
        agreed = true
    }

    /// "Continue" on onboarding's profile step for somebody who already has
    /// a profile: moves on with the profile exactly as it is, and lets it be
    /// published to again, since the person has taken it back up.
    private func keepAsItIs() {
        model.resumePublishing()
        onDone(model.profile?.username)
    }

    /// "Not now" (or, with no iCloud, "Continue without a profile"). It also
    /// retires the one-time Friends intro, so somebody who declined here is
    /// not asked again the moment onboarding ends.
    private func notNow() {
        UserDefaults.standard.set(true, forKey: FriendsIntroView.shownKey)
        onDone(nil)
    }

    private func claim() {
        guard agreed else { return }
        claiming = true
        Task { @MainActor in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard await model.claim(handle, displayName: trimmedName) else {
                claiming = false
                availability = await model.availability(of: handle)
                return
            }
            UserDefaults.standard.set(Date(), forKey: Self.rulesAcceptedKey)
            if let photo {
                await model.setAvatar(photo)
            } else if removePublishedPhoto {
                await model.clearAvatar()
            }
            if let user = users.first {
                user.username = handle
                if !trimmedName.isEmpty { user.displayName = trimmedName }
                try? context.save()
            }
            Analytics.track(.profileCreated(photo: photo != nil))
            claiming = false
            onDone(handle)
        }
    }
}

/// The one-time "Meditate with your friends" prompt for people who finished
/// onboarding before Friends existed. Shown at most once, and "Not now"
/// closes it (Melvin, 2026-09-29, reversing "no skip"): Friends is optional,
/// and the circle on Home still offers a profile whenever they want one.
struct FriendsIntroView: View {
    @ObservedObject var model: CommunityModel
    let suggested: String
    let nickname: String
    let onDone: () -> Void

    /// Set the first time the intro is on screen, and by any "Not now" on
    /// Create your profile, so it never comes back. Cleared by sign-out and
    /// Delete account (`CommunityModel.signedOut`), so the next person on
    /// the phone is asked once too.
    static let shownKey = "friends.introShown.v1"

    @State private var creating = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RadialGradient(colors: [AppColor.accentGold.opacity(0.28), .clear],
                                   center: .center, startRadius: 4, endRadius: 190)
                    HStack(spacing: -14) {
                        ForEach([nickname.isEmpty ? "You" : nickname, "M V", "J K"], id: \.self) { n in
                            PersonAvatar(name: n, size: 62)
                                .background(Circle().fill(AppColor.backgroundPrimary).padding(-4))
                        }
                    }
                }
                .frame(height: 220)

                Text("NEW IN 808")
                    .font(.system(size: 11, weight: .bold)).tracking(1.1)
                    .foregroundStyle(AppColor.accentGoldText)
                    .padding(.top, 8)
                Text("Meditate with your friends")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 6)

                bullet("person.2", "See how often your friends meditate, and follow along.")
                bullet("magnifyingglass", "Find them by @username, and let them find you.")
                bullet("lock", "No feed, no posts. Heart rate and breathing never leave your phone.")

                Spacer()

                Button { creating = true } label: { Text("Pick your username") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Not now") { markShown(); onDone() }
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .screenBackground()
            .navigationDestination(isPresented: $creating) {
                CreateProfileView(model: model, suggested: suggested, nickname: nickname) { _ in onDone() }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // Marked shown here, when it is actually on screen, not when it was
        // asked for (Melvin, 2026-09-29): a cover asked for while another
        // one is up never appears, and marking it then spent the one showing
        // on nothing.
        .onAppear {
            markShown()
            Analytics.track(.friendsIntroShown)
        }
    }

    private func markShown() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.accentGoldText)
                .frame(width: 22)
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
    }
}
