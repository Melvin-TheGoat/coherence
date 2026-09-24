import SwiftUI
import AVFoundation

/// Otto as a video clip with a transparent background (HEVC with alpha),
/// for moves the Rive rig cannot make. The first is the welcome wave
/// (Aziz, 2026-09-23): generated in Runway from his waving art on white, then
/// cut out by `tools/otto_video_key.swift`.
///
/// Shows the clip's first frame until `playing` turns true, plays it once,
/// and holds on its last frame. No audio track, so it never touches the
/// audio session. If the file is missing, the still `fallback` pose shows.
struct OttoClip: View {
    let name: String
    var playing: Bool
    var fallback: OttoPose = .pleased

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "mov") {
            ClipPlayer(url: url, playing: playing)
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

    func makeUIView(context: Context) -> ClipView { ClipView(url: url) }

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

    init(url: URL) {
        player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
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
