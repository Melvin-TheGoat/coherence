import SwiftUI
import AVFoundation
import AVKit

// MARK: - The Ready screen

/// The viewfinder that takes the sky while Timelapse is on (mockup 1C): the
/// clip's own 9:16 shape, mirrored on the front lens, a flip in the corner,
/// and dashed lines marking what a Friends feed card keeps when it crops a
/// tall clip to 4:5 (its middle 70 percent).
struct TimelapseViewfinder: View {
    @ObservedObject var recorder: TimelapseRecorder
    var width: CGFloat
    var showsFlip = true

    var body: some View {
        let height = width * 16 / 9
        ZStack {
            Color(red: 0.86, green: 0.82, blue: 0.76)
            if recorder.cameraLive {
                TimelapsePreview()
            } else {
                stand_in
            }
            // The feed's crop: a 4:5 card keeps the middle 70 percent.
            VStack {
                dash.padding(.top, height * 0.148)
                Spacer()
                dash.padding(.bottom, height * 0.148)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(AppColor.backgroundPrimary.opacity(0.95), lineWidth: 3))
        .shadow(color: Color(red: 0.08, green: 0.14, blue: 0.18).opacity(0.28), radius: 13, y: 10)
        .overlay(alignment: .topTrailing) {
            if showsFlip {
                Button { recorder.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.tactile)
                .padding(10)
                .accessibilityLabel(recorder.lens == .front ? "Use the back camera" : "Use the front camera")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timelapse viewfinder")
    }

    private var dash: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            .foregroundStyle(.white.opacity(0.7))
            .frame(height: 0.6)
            .padding(.horizontal, 10)
    }

    /// No camera to draw yet (starting up, or a simulator, which has none).
    @ViewBuilder
    private var stand_in: some View {
        #if DEBUG && targetEnvironment(simulator)
        Image(uiImage: SyntheticReel.frame(0.25)).resizable().scaledToFill()
        #else
        Image(systemName: "video.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
        #endif
    }
}

// MARK: - During the sit

/// What the sit shows while it films (mockup 2B, Melvin's pick): a red dot,
/// "Filming" with the opening lines, and a small round self-view that a tap
/// hides; a tap on the dot brings it back. iOS draws its own green camera
/// light too, so nobody is ever filmed without knowing.
struct FilmingIndicator: View {
    @ObservedObject var recorder: TimelapseRecorder
    let arriving: Bool
    let ink: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button { withAnimation(.easeInOut(duration: 0.3)) { recorder.selfViewHidden = false } } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(red: 0.878, green: 0.439, blue: 0.353))
                        .frame(width: 9, height: 9)
                    if arriving {
                        Text("Filming")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.62))
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 10).padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .animation(.easeInOut(duration: 0.7), value: arriving)
            .accessibilityLabel(recorder.selfViewHidden ? "Filming. Show yourself" : "Filming")
        }
    }
}

/// The small round self-view, bottom left, with "Hide" under it.
struct TimelapseSelfView: View {
    @ObservedObject var recorder: TimelapseRecorder
    let ink: Color

    var body: some View {
        if !recorder.selfViewHidden {
            Button { withAnimation(.easeInOut(duration: 0.3)) { recorder.selfViewHidden = true } } label: {
                VStack(spacing: 5) {
                    Group {
                        if recorder.cameraLive { TimelapsePreview() } else { stand_in }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColor.backgroundPrimary.opacity(0.9), lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
                    Text("Hide")
                        .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .accessibilityLabel("Hide your picture")
        }
    }

    @ViewBuilder
    private var stand_in: some View {
        #if DEBUG && targetEnvironment(simulator)
        Image(uiImage: SyntheticReel.frame(0.4)).resizable().scaledToFill()
        #else
        Color.black.opacity(0.3)
        #endif
    }
}

// MARK: - A looping, silent clip

/// A clip that plays by itself, muted, looping, for as long as it is on
/// screen: the timelapse on its page, and in the Friends feed (4A). Loops by
/// seeking back on its end, which keeps the last frame up through the seek
/// (the `OttoClip` lesson: `AVPlayerLooper` shows an empty frame at the
/// wrap). Does not play in Low Power Mode: the poster shows instead.
struct LoopingClip: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var url: URL?
        var token: NSObjectProtocol?

        func load(_ url: URL) {
            guard url != self.url else { return }
            self.url = url
            if let token { NotificationCenter.default.removeObserver(token) }
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .none
            // Never interrupts anything playing: a muted clip needs no audio.
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            player.preventsDisplaySleepDuringVideoPlayback = false
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                           object: player.currentItem, queue: .main) { _ in
                player.seek(to: .zero)
                player.play()
            }
            player.play()
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            playerLayer.player?.pause()
        }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.load(url)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.load(url) }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
    }

    static var allowed: Bool { !ProcessInfo.processInfo.isLowPowerModeEnabled }
}

/// The bytes of a stored clip as a temp file for as long as the view lives.
struct LoopingStoredClip: View {
    let item: SessionPhoto
    @State private var url: URL?

    var body: some View {
        ZStack {
            if let poster = PhotoThumbs.full(item) {
                Image(uiImage: poster).resizable().scaledToFill()
            }
            if let url, LoopingClip.allowed { LoopingClip(url: url) }
        }
        .onAppear {
            guard url == nil, let data = item.video else { return }
            url = SessionVideo.tempFile(data)
        }
        .onDisappear {
            if let url { try? FileManager.default.removeItem(at: url) }
            url = nil
        }
    }
}

// MARK: - On the session's page

/// The Timelapse card (mockups 3A, 3B, 5A): "Making your timelapse" with
/// honest progress while the clip is made, then the clip looping silent with
/// its speed line and ✕, Save and Share under it.
struct TimelapseCard: View {
    @ObservedObject var recorder: TimelapseRecorder
    let sessionID: UUID
    let item: SessionPhoto?
    let sessionSeconds: Double
    let onRemove: () -> Void

    /// Its own sheet and cover, not the page's: stacking several on one view
    /// is fragile, and only one presents (the HomeSheet lesson).
    @State private var playing: SessionPhoto?
    @State private var sharing: SessionPhoto?

    @State private var saving = false
    @State private var saved = false
    @State private var saveProblem: String?
    @State private var offerAutoSave = false

    private static let inset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Timelapse")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if item != nil {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(AppColor.backgroundPrimary, in: Circle())
                    }
                    .buttonStyle(.tactile)
                    .accessibilityLabel("Remove the timelapse")
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, 13)
            .padding(.bottom, 10)

            clip
                .padding(.horizontal, Self.inset)

            if item != nil {
                actions
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 12)
            }
            Color.clear.frame(height: 14)
        }
        .fullScreenCover(item: $playing) { item in TimelapsePlayerSheet(item: item) }
        .sheet(item: $sharing) { item in
            TimelapseShareSheet(recorder: recorder, item: item, sessionSeconds: sessionSeconds)
        }
        #if DEBUG
        .task(id: item?.id) {
            guard let item, TimelapsePreviewFlags.openShare else { return }
            TimelapsePreviewFlags.openShare = false
            try? await Task.sleep(for: .milliseconds(600))
            sharing = item
        }
        #endif
        .alert("Save them all automatically?", isPresented: $offerAutoSave) {
            Button("Save automatically") { answer(true) }
            Button("Not now", role: .cancel) { answer(false) }
        } message: {
            Text("New timelapses will go to Photos as soon as they are made. You can change this in Settings.")
        }
        .alert("Couldn't save it", isPresented: Binding(get: { saveProblem != nil },
                                                         set: { if !$0 { saveProblem = nil } })) {
            Button("OK") { saveProblem = nil }
        } message: { Text(saveProblem ?? "") }
    }

    @ViewBuilder
    private var clip: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if let item {
            Button { playing = item } label: {
                LoopingStoredClip(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(shape)
                    .overlay(alignment: .topLeading) {
                        Text(TimelapseRule.speedLine(sessionSeconds: sessionSeconds))
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.measureInk)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(AppColor.measure, in: Capsule())
                            .padding(10)
                    }
            }
            .buttonStyle(.tactile)
            .accessibilityLabel("Timelapse, \(TimelapseRule.speedLine(sessionSeconds: sessionSeconds)). Plays full screen")
        } else {
            VStack(spacing: 4) {
                SitArt(name: "sit-timelapse", size: 46)
                if recorder.failed.contains(sessionID) {
                    Text("The timelapse couldn't be made")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 8)
                    Text("Your session is saved as it was.")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    Text("Making your timelapse")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 8)
                    Text(TimelapseRule.makingLine(sessionSeconds: sessionSeconds))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    ProgressView(value: recorder.making[sessionID] ?? 0)
                        .tint(AppColor.skyDeep)
                        .frame(width: 180)
                        .padding(.top, 14)
                        .animation(.linear(duration: 0.2), value: recorder.making[sessionID] ?? 0)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(AppColor.skyWash, in: shape)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { Task { await save() } } label: {
                Label(saved ? "Saved to Photos" : (saving ? "Saving…" : "Save to Photos"),
                      systemImage: saved ? "checkmark" : "arrow.down.to.line")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.skyDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColor.skyWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.tactile)
            .disabled(saving || saved)
            Button { sharing = item } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.skyDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColor.skyWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.tactile)
        }
    }

    private func save() async {
        guard let item else { return }
        saving = true
        let ok = await recorder.saveToPhotos(item, sessionSeconds: sessionSeconds)
        saving = false
        guard ok else {
            saveProblem = "Allow 808 to add to Photos in Settings, then try again."
            return
        }
        withAnimation { saved = true }
        var auto = TimelapseAutoSave.load()
        if auto.afterManualSave() {
            auto.store()
            offerAutoSave = true
        }
    }

    private func answer(_ yes: Bool) {
        var auto = TimelapseAutoSave.load()
        auto.answer(yes)
        auto.store()
        Analytics.track(.timelapseAutoSaveAnswered(on: yes))
    }
}

// MARK: - Sharing

/// "Share your timelapse" (mockup 5B): Instagram first, then everything else.
/// Reel and Story save the marked copy and open Instagram until 808 has a
/// Meta app ID (`InstagramShare.metaAppID`); with one they hand the clip
/// straight to Instagram's own editor. More is iOS's share sheet.
struct TimelapseShareSheet: View {
    @ObservedObject var recorder: TimelapseRecorder
    let item: SessionPhoto
    let sessionSeconds: Double
    @Environment(\.dismiss) private var dismiss

    @State private var file: URL?
    @State private var working: InstagramShare.VideoDestination?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share your timelapse")
                    .font(DisplayFont.display(21, .heavy))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(TimelapseRule.speedLine(sessionSeconds: sessionSeconds)) · ready for Instagram")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, 22)

            VStack(spacing: 0) {
                row(title: "Instagram Reel", symbol: "film", destination: .reel)
                Divider().overlay(AppColor.hairline)
                row(title: "Instagram Story", symbol: "circle.dashed", destination: .story)
                Divider().overlay(AppColor.hairline)
                if let file {
                    ShareLink(item: file) {
                        rowLabel(title: "More", detail: "TikTok, Messages and more", symbol: "ellipsis")
                    }
                    .simultaneousGesture(TapGesture().onEnded { Analytics.track(.timelapseShared(to: "more")) })
                } else {
                    rowLabel(title: "More", detail: "Getting it ready…", symbol: "ellipsis").opacity(0.5)
                }
            }
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let hint {
                Text(hint)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .presentationDetents([.height(hint == nil ? 330 : 380)])
        .presentationDragIndicator(.visible)
        .task { file = await recorder.exportedCopy(of: item, sessionSeconds: sessionSeconds) }
    }

    private func row(title: String, symbol: String, destination: InstagramShare.VideoDestination) -> some View {
        Button {
            Task { await send(to: destination) }
        } label: {
            rowLabel(title: title,
                     detail: working == destination ? "Getting it ready…"
                        : (InstagramShare.hasDirectHandoff ? "Opens Instagram with it loaded"
                                                           : "Saves it to Photos, then opens Instagram"),
                     symbol: symbol)
        }
        .buttonStyle(.tactile)
        .disabled(working != nil || !InstagramShare.isInstalled)
        .opacity(InstagramShare.isInstalled ? 1 : 0.5)
    }

    private func rowLabel(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.skyDeep)
                .frame(width: 38, height: 38)
                .background(AppColor.skyWash, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.callout.weight(.bold)).foregroundStyle(AppColor.textPrimary)
                Text(detail).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func send(to destination: InstagramShare.VideoDestination) async {
        working = destination
        defer { working = nil }
        let url: URL?
        if let file { url = file } else { url = await recorder.exportedCopy(of: item, sessionSeconds: sessionSeconds) }
        guard let url else { hint = "That couldn't be prepared. Try again."; return }
        Analytics.track(.timelapseShared(to: destination.rawValue))
        let ok = await InstagramShare.shareVideo(url, to: destination)
        hint = ok
            ? (InstagramShare.hasDirectHandoff ? nil
               : "Saved to Photos. In Instagram, it's the newest item in your gallery.")
            : "Allow 808 to add to Photos in Settings to share it."
    }
}

extension InstagramShare {
    enum VideoDestination: String { case reel, story }

    /// The clip, toward a Reel or a Story.
    ///
    /// - With a Meta app ID: Meta's Sharing to Reels (`instagram-reels://share`)
    ///   and Sharing to Stories (`instagram-stories://share`), the video on the
    ///   pasteboard for five minutes. **Unverified until the app ID exists**:
    ///   the keys are Meta's documented ones, never run against Instagram.
    /// - Without one (today): save to Photos (add-only) and open Instagram,
    ///   the story camera for a Story, where the clip is the newest item in
    ///   the gallery. False means Photos access was refused.
    @MainActor
    static func shareVideo(_ url: URL, to destination: VideoDestination) async -> Bool {
        if hasDirectHandoff {
            guard let data = try? Data(contentsOf: url) else { return false }
            let scheme = destination == .reel ? "instagram-reels" : "instagram-stories"
            guard let open = URL(string: "\(scheme)://share?source_application=\(metaAppID)") else { return false }
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundVideo": data,
                  "com.instagram.sharedSticker.appID": metaAppID]],
                options: [.expirationDate: Date().addingTimeInterval(60 * 5)])
            await UIApplication.shared.open(open)
            return true
        }
        guard await TimelapseRecorder.saveVideoToPhotos(url) else { return false }
        let target = destination == .story ? "instagram://story-camera" : "instagram://app"
        if let open = URL(string: target), UIApplication.shared.canOpenURL(open) {
            await UIApplication.shared.open(open)
        }
        return true
    }
}

/// Plays a stored timelapse full screen, silent (it has no sound).
struct TimelapsePlayerSheet: View {
    let item: SessionPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            LoopingStoredClip(item: item)
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.tactile)
            .padding(.top, 8).padding(.trailing, 16)
        }
    }
}

#if DEBUG
/// `PREVIEW_TIMELAPSE=share`: the page opens its share sheet once the clip lands.
@MainActor
enum TimelapsePreviewFlags {
    static var openShare = false
}
#endif
