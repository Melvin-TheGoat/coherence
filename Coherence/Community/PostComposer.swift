import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// "Post to friends", opened from the results screen.
///
/// **BeReal rule (Aziz, 2026-09-14): no selfie, no post.** The photo is a
/// selfie of you, taken right now on the FRONT camera. No photo library, so
/// what friends see is you, meditating, today. Post stays disabled until it
/// exists, and `CommunityStore.post` refuses a draft without one.
///
/// A caption is optional. The first post ever asks for one Agree to a
/// one-line community rule: guideline 1.2 expects users to accept that
/// abusive content is not tolerated, and Aziz asked for it to be light.
struct PostComposerView: View {
    let seed: CommunityStore.Draft
    @EnvironmentObject private var model: CommunityModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [User]

    @AppStorage("community.rulesAgreed.v1") private var rulesAgreed = false
    @State private var caption = ""
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var cameraDenied = false
    #if DEBUG && targetEnvironment(simulator)
    /// The simulator has no camera. DEBUG simulator builds only: pick a
    /// stand-in from the library so the flow can be reviewed. Compiled out
    /// of every device build.
    @State private var simulatorPick: PhotosPickerItem?
    #endif
    @State private var showRules = false
    @State private var posting = false
    @State private var refusal: String?

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView().tint(AppColor.calmAccent)
                case .unavailable:
                    UnavailableCard()
                case .needsUsername:
                    ClaimUsernameView(model: model,
                                      suggested: users.first?.username ?? "",
                                      displayName: users.first?.displayName ?? "") { handle in
                        if let user = users.first { user.username = handle; try? context.save() }
                    }
                case .ready:
                    composer
                }
            }
            .screenBackground()
            .navigationTitle("Post to friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if model.phase == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(posting ? "Posting…" : "Post") { tapPost() }
                            .tint(AppColor.accentGoldText)
                            .disabled(posting || image == nil)
                    }
                }
            }
            .sheet(isPresented: $showRules) {
                CommunityRulesSheet {
                    rulesAgreed = true
                    showRules = false
                    submit()
                }
                .presentationDetents([.height(260)])
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(device: .front) { image = $0 }
                    .ignoresSafeArea()
            }
            .alert("Couldn't post that", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
                Button("OK") { refusal = nil }
            } message: { Text(refusal ?? "") }
            .task { await model.load() }
        }
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    selfieArea
                    HStack(spacing: 14) {
                        ScoreRing(score: Double(seed.score) / 100, size: 36, lineWidth: 3.5)
                        stat("\(seed.minutes) min", "Sat")
                        stat("\(seed.streak) day\(seed.streak == 1 ? "" : "s")", "Streak")
                        if let t = seed.technique, !t.isEmpty { stat(t, "Technique") }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                TextField("Say something, or don't", text: $caption, axis: .vertical)
                    .lineLimit(2...5)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(12)
                    .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: caption) { _, new in
                        if new.count > CommunityStore.captionLimit { caption = String(new.prefix(CommunityStore.captionLimit)) }
                    }
            }
            .padding(AppMetrics.screenPadding)
        }
        #if DEBUG && targetEnvironment(simulator)
        .onChange(of: simulatorPick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    image = ui
                }
                simulatorPick = nil
            }
        }
        #endif
    }

    /// The selfie: a tall tap target that opens the front camera, or the
    /// selfie itself with Retake. Nothing else can fill it.
    @ViewBuilder
    private var selfieArea: some View {
        if let image {
            ZStack(alignment: .bottomTrailing) {
                // The image lives in an overlay of a fixed-size frame: a
                // scaledToFill image as the frame's own content reports its
                // natural width and pushes the whole screen wider than the
                // phone (found in the simulator with a landscape photo).
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 360)
                    .overlay(Image(uiImage: image).resizable().scaledToFill())
                    .clipped()
                Button { openCamera() } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button { openCamera() } label: {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppColor.accentGoldText)
                    Text("Take your selfie")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(cameraDenied
                         ? "808 can't use the camera. Turn it on in Settings to post."
                         : "Show your friends you sat. A selfie is how every post starts.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .contentShape(Rectangle())
            }
            .buttonStyle(CardButtonStyle())
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottom) {
                PhotosPicker(selection: $simulatorPick, matching: .images) {
                    Text("Simulator: pick a stand-in")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(8)
                }
            }
            #endif
        }
    }

    private func openCamera() {
        #if targetEnvironment(simulator)
        return   // no camera; the DEBUG stand-in picker covers review
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true } else { cameraDenied = true }
                }
            }
        default:
            cameraDenied = true
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        #endif
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(AppFont.callout.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func tapPost() {
        if rulesAgreed { submit() } else { showRules = true }
    }

    private func submit() {
        posting = true
        Task {
            var draft = seed
            draft.caption = caption
            guard let image, let url = PostPhoto.prepare(image) else {
                refusal = "Take your selfie to post."
                posting = false
                return
            }
            draft.photoURL = url
            let ok = await model.post(draft)
            posting = false
            if ok { dismiss() }
        }
    }
}

/// The secondary style sits on the card's own colour, so inside the card the
/// photo buttons take the screen ground instead.
private struct PhotoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.medium))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(AppColor.backgroundPrimary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The rules, once, before the first post. Short, positive where it can be,
/// and explicit about what happens to what gets reported.
struct CommunityRulesSheet: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep it kind")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 8)
            Text("Post your own practice. Anything abusive or explicit gets taken down.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onAgree) { Text("Agree and post") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
    }
}

/// Photo preparation for upload: longest side 1080, JPEG, written to a temp
/// file for `CKAsset`. Roughly 200 KB a picture.
enum PostPhoto {
    static let maxSide: CGFloat = 1080

    static func prepare(_ image: UIImage) -> URL? {
        guard let data = jpeg(image) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("post-\(UUID().uuidString).jpg")
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    static func jpeg(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        resized(image).jpegData(compressionQuality: quality)
    }

    static func resized(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The system camera, opened on the front lens for the selfie. Needs
/// `NSCameraUsageDescription`, which names exactly this use.
struct CameraPicker: UIViewControllerRepresentable {
    var device: UIImagePickerController.CameraDevice = .rear
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(device) { picker.cameraDevice = device }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
