import SwiftUI
import AVFoundation

/// Otto as a video clip with a transparent background (HEVC with alpha),
/// for moves the Rive rig cannot make. The first is the welcome wave
/// (Aziz, 2026-09-23): generated in Runway from his waving art on white, then
/// cut out by `tools/otto_video_key.swift`.
///
/// Shows the clip's first frame until `playing` turns true, then plays it
/// once and holds the last frame, or with `loops` plays it forever, which is
/// why a looping clip is cut to end where it begins.
///
/// **Not `AVPlayerLooper`.** It loops by swapping between copies of the item,
/// and at every swap the layer showed ONE EMPTY FRAME: Otto vanished for a
/// sixtieth of a second every loop, which is the "glitching" Aziz kept seeing
/// (found 2026-09-23 from a 60 fps recording: two frames differing by 38
/// grey levels, the empty meadow between them). One player on one item that
/// seeks back to zero at the end keeps the last frame on screen through the
/// seek instead. No audio track, so it never touches the
/// audio session. If the file is missing, the still `fallback` pose shows.
struct OttoClip: View {
    let name: String
    var playing: Bool
    var loops: Bool = false
    var fallback: OttoPose = .pleased
    /// Fill the frame, cropping the edges (a full-screen background clip),
    /// instead of fitting inside it.
    var fills: Bool = false

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "mov") {
            ClipPlayer(url: url, playing: playing, loops: loops, fills: fills)
                .accessibilityHidden(true)
        } else {
            Image(fallback.asset)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

private struct ClipPlayer: UIViewRepresentable {
    let url: URL
    let playing: Bool
    let loops: Bool
    let fills: Bool

    func makeUIView(context: Context) -> ClipView { ClipView(url: url, loops: loops, fills: fills) }

    func updateUIView(_ view: ClipView, context: Context) {
        if playing { view.play() }
    }

    static func dismantleUIView(_ view: ClipView, coordinator: ()) {
        view.player.pause()
    }
}

private final class ClipView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    let player: AVPlayer
    private var started = false
    private var endObserver: NSObjectProtocol?

    init(url: URL, loops: Bool, fills: Bool = false) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        // Stay on the last frame at the end; a loop then jumps back itself.
        player.actionAtItemEnd = loops ? .none : .pause
        if loops {
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player?.play()
            }
        }
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        playerLayer.isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        // BGRA keeps the alpha channel through to the layer.
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        playerLayer.player = player
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func play() {
        guard !started else { return }
        started = true
        player.play()
    }
}
