import SwiftUI
import SwiftData
import PhotosUI

/// "Post to friends", opened from the results screen. A photo (camera or
/// library, optional), a caption (optional), and the stat strip the post will
/// carry, which is the free share card's data and nothing measured (see
/// `CommunityRecords.swift`). The first post ever shows the community rules
/// and asks for an Agree, which is what guideline 1.2 reviewers look for.
struct PostComposerView: View {
    let seed: CommunityStore.Draft
    @EnvironmentObject private var model: CommunityModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [User]

    @AppStorage("community.rulesAgreed.v1") private var rulesAgreed = false
    @State private var caption = ""
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
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
                            .disabled(posting)
                    }
                }
            }
            .sheet(isPresented: $showRules) {
                CommunityRulesSheet {
                    rulesAgreed = true
                    showRules = false
                    submit()
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image = $0 }
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
                    photoArea
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

                SectionHeader(title: "What goes out").padding(.top, 6)
                Text("Your score, minutes, streak, technique, the photo and the caption. Your heart rate, breath and stillness readings stay on your phone.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppMetrics.screenPadding)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    image = ui
                }
                pickerItem = nil
            }
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let image {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 240).clipped()
                Button { self.image = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                        .buttonStyle(PhotoButtonStyle())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(PhotoButtonStyle())
                }
                Text("A photo is optional.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(12)
        }
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
            if let image {
                guard let url = PostPhoto.prepare(image) else {
                    refusal = "That photo couldn't be read. Try another."
                    posting = false
                    return
                }
                draft.photoURL = url
            }
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
            Text("Before your first post")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 8)
            rule("Post your own practice.")
            rule("Be kind. No harassment, no hate.")
            rule("No nudity, no violence.")
            rule("Anything reported comes down, and people who keep doing it are removed.")
            Spacer(minLength: 0)
            Button(action: onAgree) { Text("Agree and post") }
                .buttonStyle(PrimaryButtonStyle())
            Button("Not now") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark").foregroundStyle(AppColor.calmAccent).padding(.top, 2)
            Text(text).font(AppFont.callout).foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

/// The system camera. Needs `NSCameraUsageDescription`, which names exactly
/// this use.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
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
