import SwiftUI
import SwiftData
import PhotosUI

/// **Create your profile**: a photo and a real @username, separate from the
/// nickname (Aziz, 2026-09-14: "your nickname and your username are two
/// different things"). One screen, three doors:
/// - the last onboarding step, right after Sign in;
/// - `FriendsIntroView`, the one-time prompt for people who finished
///   onboarding before Friends existed;
/// - the Friends tab and Save session, for anyone who still has none.
///
/// Required, per Aziz, with the one unavoidable exit: with no iCloud account a
/// username cannot be saved at all, so that case (and only that case) offers
/// "Continue without a profile". Mockup: `mockups/friends-v2.html`, sections
/// 1 and 2. Friends-gated.
struct CreateProfileView: View {
    @ObservedObject var model: CommunityModel
    /// The username typed earlier (onboarding's old field, or 1.0's cosmetic
    /// one), offered first. It was never reserved, so it may be taken.
    let suggested: String
    /// The nickname so far. Editable here so the difference is visible.
    let nickname: String
    /// Called with the claimed handle, or nil when the user continued without
    /// a profile (no-iCloud only).
    let onDone: (String?) -> Void

    @Environment(\.modelContext) private var context
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

    /// A profile already exists: same screen, edit wording.
    private var editing: Bool { !(model.profile?.username ?? "").isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(editing ? "Edit profile" : "Create your profile")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 12)
                Text("Your username is how friends find you. It's yours alone.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 6)

                photoPicker
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)

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
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                statusLine.padding(.top, 7)

                fieldLabel("Nickname")
                TextField("What friends call you", text: $name)
                    .textContentType(.nickname)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(14)
                    .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if model.phase == .unavailable {
                    Text("No iCloud on this iPhone. Usernames are saved to iCloud, so you can finish setting up now and create your profile once iCloud is on.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColor.calmAccent.opacity(0.45), lineWidth: 1))
                        .padding(.top, 20)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { claim() } label: {
                    Text(claiming ? "Saving…" : (editing ? "Save" : "Create profile"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(availability != .available || claiming)
                .saturation(availability == .available ? 1 : 0.2)
                .brightness(availability == .available ? 0 : -0.25)
                if model.phase == .unavailable {
                    Button("Continue without a profile") { onDone(nil) }
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(AppColor.backgroundPrimary.ignoresSafeArea(edges: .bottom))
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
            await model.load()
            // A reinstall or Edit profile already has a reserved handle and
            // name in iCloud; those win over anything typed locally.
            if handle.isEmpty { handle = model.profile?.username ?? "" }
            if handle.isEmpty { handle = Username.normalize(suggested) ?? "" }
            if name.isEmpty { name = model.profile?.displayName ?? "" }
            if name.isEmpty { name = nickname }
            if handle.isEmpty { focused = true } else { check() }
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
            if photo != nil {
                Button("Remove photo", role: .destructive) { photo = nil }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 96, height: 96).clipShape(Circle())
                    } else if let current = model.profile?.avatarURL {
                        PersonAvatar(name: name, size: 96, photoURL: current)
                    } else {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(AppColor.accentGold.opacity(0.7))
                            .frame(width: 96, height: 96)
                            .overlay(
                                VStack(spacing: 3) {
                                    Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                                    Text("Add photo").font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(AppColor.accentGoldText))
                    }
                }
                if photo != nil || model.profile?.avatarURL != nil {
                    Text("Change photo").font(AppFont.caption.weight(.semibold)).foregroundStyle(AppColor.accentGoldText)
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

    private func claim() {
        claiming = true
        Task { @MainActor in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard await model.claim(handle, displayName: trimmedName) else {
                claiming = false
                availability = await model.availability(of: handle)
                return
            }
            if let photo { await model.setAvatar(photo) }
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
/// onboarding before Friends existed. No skip (Aziz: the username is
/// required); the no-iCloud case is handled inside `CreateProfileView`.
struct FriendsIntroView: View {
    @ObservedObject var model: CommunityModel
    let suggested: String
    let nickname: String
    let onDone: () -> Void

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

                bullet("person.2", "See the sessions your friends share, and give them a 🙏.")
                bullet("camera", "Share yours with a selfie when you finish.")
                bullet("lock", "Any session can stay private. Heart rate and breathing never leave your phone.")

                Spacer()

                Button { creating = true } label: { Text("Pick your username") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .screenBackground()
            .navigationDestination(isPresented: $creating) {
                CreateProfileView(model: model, suggested: suggested, nickname: nickname) { _ in onDone() }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { Analytics.track(.friendsIntroShown) }
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
