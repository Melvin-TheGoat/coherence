import SwiftUI
import AVFoundation

/// Otto as a video clip with a transparent background (HEVC with alpha),
/// for moves the Rive rig cannot make. The first is the welcome wave
/// (Aziz, 2026-09-23): generated in Runway from his waving art on white, then
/// cut out by `tools/otto_video_key.swift`.
///
/// Shows the clip's first frame until `playing` turns true, then plays it
/// once and holds the last frame, or with `loops` plays it forever with no
/// seam (`AVPlayerLooper`), which is why a looping clip is cut between two
/// frames where the pose matches. No audio track, so it never touches the
/// audio session. If the file is missing, the still `fallback` pose shows.
struct OttoClip: View {
    let name: String
    var playing: Bool
    var loops: Bool = false
    var fallback: OttoPose = .pleased

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "mov") {
            ClipPlayer(url: url, playing: playing, loops: loops)
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

    func makeUIView(context: Context) -> ClipView { ClipView(url: url, loops: loops) }

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
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var started = false

    init(url: URL, loops: Bool) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        if loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            player.actionAtItemEnd = .pause
        }
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        playerLayer.isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
        // BGRA keeps the alpha channel through to the layer.
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        playerLayer.player = player
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func play() {
        guard !started else { return }
        started = true
        player.play()
    }
}
