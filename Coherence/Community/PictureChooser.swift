import SwiftUI
import PhotosUI

/// The pictures 808 offers to anyone without a photo they want to use
/// (Melvin, 2026-10-19). Friends is a list of faces, and twenty grey
/// silhouettes in a row tell nobody who is who. Otto comes from his own head
/// art; the rest were drawn as one clay sheet so they share a style, and the
/// five animals were redrawn in Otto's style (`mockups/pfp-presets/`).
///
/// **A preset is uploaded exactly like a photo** (`CommunityModel.setAvatar`):
/// the public Profile record needs no new field, and friends on an older
/// version of 808 see the picture too.
struct AvatarPreset: Identifiable, Hashable {
    let id: String
    let label: String

    /// Bundled as `avatar-<id>.jpg` (`Coherence/Community/AvatarPresets/`),
    /// 384 px: the largest place a portrait is drawn is 124 pt.
    var image: UIImage? { UIImage(named: "avatar-\(id).jpg") }

    static let all: [AvatarPreset] = [
        .init(id: "otto", label: "Otto"),
        .init(id: "mountains", label: "Mountains at sunrise"),
        .init(id: "moon-lake", label: "Moon over a lake"),
        .init(id: "starry-tree", label: "A tree under the stars"),
        .init(id: "wave", label: "A wave"),
        .init(id: "dunes", label: "Dunes at sunset"),
        .init(id: "misty-pines", label: "Pines in the mist"),
        .init(id: "waterfall", label: "A waterfall"),
        .init(id: "lotus", label: "A lotus"),
        .init(id: "bonsai", label: "A bonsai"),
        .init(id: "dandelion", label: "A dandelion"),
        .init(id: "raked-sand", label: "Raked sand"),
        .init(id: "cairn", label: "Stacked stones"),
        .init(id: "singing-bowl", label: "A singing bowl"),
        .init(id: "candle", label: "A candle"),
        .init(id: "matcha", label: "A cup of matcha"),
        .init(id: "frog", label: "A frog"),
        .init(id: "red-panda", label: "A red panda"),
        .init(id: "turtle", label: "A turtle"),
        .init(id: "owl", label: "An owl"),
        .init(id: "cat", label: "A cat"),
    ]
}

/// When Friends asks someone who already has a profile, and no picture, to
/// pick one (`mockups/pfp-prompt`, screen 4). "Not now" means never again;
/// "Remind me tomorrow" brings it back from the next calendar day on, the
/// next time Friends opens. Swiping the sheet away counts as tomorrow: it is
/// the gentler reading of a choice nobody made. Pure, so it is testable.
enum PicturePrompt {
    static let neverKey = "friends.picturePrompt.never.v1"
    static let remindKey = "friends.picturePrompt.remindAfter.v1"

    static func due(hasPicture: Bool, never: Bool, remindAfter: Date?, now: Date = Date()) -> Bool {
        guard !hasPicture, !never else { return false }
        if let remindAfter, now < remindAfter { return false }
        return true
    }

    static func due(hasPicture: Bool, defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        due(hasPicture: hasPicture, never: defaults.bool(forKey: neverKey),
            remindAfter: defaults.object(forKey: remindKey) as? Date, now: now)
    }

    /// The start of the next calendar day.
    static func tomorrow(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }

    static func remindTomorrow(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(tomorrow(after: now), forKey: remindKey)
    }

    static func neverAgain(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: neverKey)
    }

    /// Sign-out and Delete account: the next person on this phone is asked
    /// for themselves.
    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: neverKey)
        defaults.removeObject(forKey: remindKey)
    }
}

/// Choose your picture: a selfie, a photo from the library, or one of 808's
/// presets (`mockups/pfp-prompt`, screens 2 and 4). The sheet's own content,
/// so the camera and the library picker are presented from here, never from
/// the screen underneath, which already carries presentations of its own.
struct PictureChooser: View {
    enum Mode {
        /// Create (or edit) your profile.
        case create
        /// Asked once of a profile that has no picture, from Friends.
        case prompt
    }

    let mode: Mode
    /// Edit profile with a picture already set: offers Remove.
    var canRemove = false
    let onPicked: (UIImage) -> Void
    var onRemove: (() -> Void)? = nil
    var onRemindTomorrow: (() -> Void)? = nil
    var onNotNow: (() -> Void)? = nil

    @State private var chosen: AvatarPreset?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pick: PhotosPickerItem?
    /// The prompt shows four presets and "+17" until that is tapped.
    @State private var expanded = false

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var presets: [AvatarPreset] {
        mode == .prompt && !expanded ? Array(AvatarPreset.all.prefix(4)) : AvatarPreset.all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    sourceButtons.padding(.top, 20)
                    Text("Or pick one of ours")
                        .font(AppFont.callout.weight(.heavy))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 26)
                    grid.padding(.top, 14)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 26)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            footer
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 8)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(device: .front) { onPicked($0) }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    onPicked(ui)
                }
                pick = nil
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch mode {
        case .create:
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your picture")
                    .font(DisplayFont.display(24, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Friends see it next to your name.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .prompt:
            HStack(alignment: .bottom, spacing: 10) {
                Image("OttoHead")
                    .resizable().scaledToFit()
                    .frame(width: 60)
                    .accessibilityHidden(true)
                Text("Pick a picture so your friends know it's you.")
                    .font(AppFont.body.weight(.heavy))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .background(AppColor.hairline, in: RoundedRectangle(cornerRadius: 18, style: .continuous).offset(y: 2))
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 10) {
            if hasCamera {
                sourceButton("Take a selfie", symbol: "camera") { showCamera = true }
            }
            sourceButton(hasCamera ? "From Photos" : "Choose from Photos", symbol: "photo.on.rectangle") {
                showLibrary = true
            }
        }
    }

    private func sourceButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(AppFont.callout.weight(.heavy))
                .foregroundStyle(AppColor.textPrimary)
                .labelStyle(SkyIconLabel())
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(AppColor.hairline, in: RoundedRectangle(cornerRadius: 16, style: .continuous).offset(y: 3))
        }
        .buttonStyle(.tactile)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
            ForEach(presets) { preset in
                Button { chosen = preset } label: { presetCircle(preset) }
                    .buttonStyle(.tactile)
                    .accessibilityLabel(preset.label)
                    .accessibilityAddTraits(chosen == preset ? .isSelected : [])
            }
            if mode == .prompt && !expanded {
                Button { withAnimation(.easeOut(duration: 0.25)) { expanded = true } } label: {
                    Text("+\(AvatarPreset.all.count - 4)")
                        .font(AppFont.caption.weight(.heavy))
                        .foregroundStyle(AppColor.skyDeep)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .foregroundStyle(AppColor.hairline))
                }
                .buttonStyle(.tactile)
                .accessibilityLabel("See all \(AvatarPreset.all.count) pictures")
            }
        }
    }

    private func presetCircle(_ preset: AvatarPreset) -> some View {
        Group {
            if let image = preset.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AppColor.backgroundSecondary
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
        .overlay {
            if chosen == preset {
                Circle().stroke(OnboardingGreen.fill, lineWidth: 3).padding(-5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if chosen == preset {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(OnboardingGreen.fill, in: Circle())
                    .overlay(Circle().stroke(AppColor.backgroundPrimary, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
        }
        .padding(5)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                if let image = chosen?.image { onPicked(image) }
            } label: {
                Text("Use this picture")
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(chosen == nil)
            .saturation(chosen == nil ? 0.35 : 1)
            .opacity(chosen == nil ? 0.6 : 1)

            switch mode {
            case .create:
                if canRemove, let onRemove {
                    Button("Remove picture", role: .destructive) { onRemove() }
                        .buttonStyle(.tactile)
                        .font(AppFont.callout.weight(.semibold))
                        .padding(.vertical, 6)
                }
            case .prompt:
                HStack(spacing: 10) {
                    Button { onRemindTomorrow?() } label: {
                        Text("Remind me tomorrow")
                            .font(AppFont.callout.weight(.heavy))
                            .foregroundStyle(AppColor.skyDeep)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.tactile)
                    Button { onNotNow?() } label: {
                        Text("Not now")
                            .font(AppFont.callout.weight(.heavy))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// A label whose icon is drawn in the sky blue that marks choosing.
private struct SkyIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(AppColor.skyDeep)
            configuration.title
        }
    }
}
