import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// The selfie a Friends post is built on.
///
/// **BeReal rule (Aziz, 2026-09-14): no selfie, no post.** Taken right now on
/// the FRONT camera, no photo library, so what friends see is you, meditating,
/// today. `CommunityStore.post` refuses a draft without one. An edit to a post
/// that already has a selfie may keep it (`existingURL`).
struct SelfieCapture: View {
    @Binding var image: UIImage?
    var existingURL: URL? = nil
    var height: CGFloat = 320

    @State private var showCamera = false
    @State private var cameraDenied = false
    @State private var existing: UIImage?
    #if DEBUG && targetEnvironment(simulator)
    /// The simulator has no camera. DEBUG simulator builds only: pick a
    /// stand-in from the library so the flow can be reviewed. Compiled out
    /// of every device build.
    @State private var simulatorPick: PhotosPickerItem?
    #endif

    var body: some View {
        Group {
            if let shown = image ?? existing {
                ZStack(alignment: .bottomTrailing) {
                    // The image lives in an overlay of a fixed-size frame: a
                    // scaledToFill image as the frame's own content reports its
                    // natural width and pushes the screen wider than the phone.
                    Color.clear
                        .frame(maxWidth: .infinity).frame(height: height)
                        .overlay(Image(uiImage: shown).resizable().scaledToFill())
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
                             ? "808 can't use the camera. Turn it on in Settings to share."
                             : "Friends see you, right after you sat.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height * 0.8)
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
        .background(AppColor.backgroundSecondary)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(device: .front) { image = $0 }
                .ignoresSafeArea()
        }
        .task(id: existingURL) {
            if let url = existingURL { existing = UIImage(contentsOfFile: url.path) }
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

    var hasSelfie: Bool { image != nil || existingURL != nil }

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
