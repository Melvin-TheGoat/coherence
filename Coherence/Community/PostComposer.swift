import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// The photo row on Save session (mockup `mockups/save-session-v7.html`): a
/// PORTRAIT tile with the explanation beside it. Portrait because a
/// front-camera shot is 3:4 and a landscape slot crops the face, which is the
/// one thing the picture is for.
///
/// **BeReal rule (Aziz, 2026-09-14): no selfie, no post.** Taken now, on the
/// front camera, no library. `CommunityStore.post` refuses a draft without
/// one. Since 2026-09-15 the photo is also OPTIONAL for a private session
/// (Aziz: "even if its a private one") and shows on the calendar, so the tile
/// is always present and only its urgency changes: gold when sharing needs
/// it, quiet when it is yours to skip.
///
/// The tile does not own the camera. Its parent does, because the pinned
/// button also opens it ("Take your selfie" is the primary action while the
/// shot is missing), and a screen with two owners of one sheet is the
/// dropped-presentation trap.
struct PhotoTile: View {
    let shown: UIImage?
    let required: Bool
    let onTap: () -> Void
    /// DEBUG simulator only: the simulator has no camera, so a stand-in can
    /// be picked from the library to review the flow. Compiled out of every
    /// device build.
    var onSimulatorPick: ((UIImage) -> Void)? = nil

    #if DEBUG && targetEnvironment(simulator)
    @State private var simulatorPick: PhotosPickerItem?
    #endif

    private let tileSize = CGSize(width: 78, height: 104)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                tile
                VStack(alignment: .leading, spacing: 3) {
                    if shown != nil {
                        Text(required ? "Your selfie" : "Your photo")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Retake")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.top, 3)
                    } else if required {
                        Text("Take your selfie")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Friends see you, right after you sat. Sharing needs one.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        Text("Add a photo")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Only you see it, on your calendar. Optional.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .bottomTrailing) {
            if shown == nil, onSimulatorPick != nil {
                PhotosPicker(selection: $simulatorPick, matching: .images) {
                    Text("Simulator stand-in")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .onChange(of: simulatorPick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    onSimulatorPick?(ui)
                }
                simulatorPick = nil
            }
        }
        #endif
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if let shown {
            // Overlay on a fixed frame, not the image as content: a
            // scaledToFill image reports its natural width and widens the
            // whole screen (found in the 2026-09-14 simulation).
            Color.clear
                .frame(width: tileSize.width, height: tileSize.height)
                .overlay(Image(uiImage: shown).resizable().scaledToFill())
                .clipShape(shape)
        } else {
            shape
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(required ? AppColor.accentGold.opacity(0.65) : AppColor.textSecondary.opacity(0.35))
                .frame(width: tileSize.width, height: tileSize.height)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(required ? AppColor.accentGoldText : AppColor.textSecondary)
                }
        }
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

    /// The calendar and row thumbnail, about 240 px on the long side. Small
    /// enough to live inline on the `SessionPhoto` row, so a month view never
    /// decodes a full-size image.
    static let thumbSide: CGFloat = 240

    static func thumbnail(_ image: UIImage, quality: CGFloat = 0.75) -> Data? {
        resized(image, to: thumbSide).jpegData(compressionQuality: quality)
    }

    /// Upload bytes already stored on a `SessionPhoto`: written to a temp
    /// file for `CKAsset`, the same shape `prepare(_:)` gives a fresh image.
    static func prepare(data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("post-\(UUID().uuidString).jpg")
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    static func resized(_ image: UIImage, to side: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > side else { return image }
        let scale = side / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Decoded thumbnails, cached by row so a calendar redraw does not decode
/// thirty JPEGs. Keyed on id plus the time the shot was taken, so a retake
/// is never served the old picture.
enum PhotoThumbs {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for photo: SessionPhoto) -> UIImage? {
        let key = "\(photo.id.uuidString)-\(photo.takenAt.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = photo.thumbnail, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The full-size picture, decoded on demand and not cached: it is shown
    /// on one screen at a time.
    static func full(_ photo: SessionPhoto) -> UIImage? {
        photo.jpeg.flatMap(UIImage.init(data:))
    }

    /// Session id → thumbnail, and practiced day → thumbnail (the latest sit
    /// that day), from the rows Home and Profile already query.
    static func maps(photos: [SessionPhoto], sessions: [Session],
                     calendar: Calendar = .current) -> (bySession: [UUID: UIImage], byDay: [Date: UIImage]) {
        let starts = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.startedAt) })
        var bySession: [UUID: UIImage] = [:]
        var byDay: [Date: (Date, UIImage)] = [:]
        for photo in photos {
            guard let sid = photo.sessionID, let started = starts[sid], let img = image(for: photo) else { continue }
            bySession[sid] = img
            let day = calendar.startOfDay(for: started)
            if let (when, _) = byDay[day], when > started { continue }
            byDay[day] = (started, img)
        }
        return (bySession, byDay.mapValues(\.1))
    }
}

extension PostPhoto {
    /// Upload size, 1080 on the long side. Kept as the original entry point.

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
