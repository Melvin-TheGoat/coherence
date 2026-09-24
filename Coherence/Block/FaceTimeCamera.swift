import SwiftUI
import AVFoundation
import os

/// The front camera behind Otto's FaceTime screen (`InterventionView.swift`).
/// Live preview only: nothing is captured, recorded, or saved anywhere, which
/// is exactly what `NSCameraUsageDescription` promises for this screen.
///
/// Starts the moment the screen appears, not on Accept, because the incoming
/// state wants your own camera live behind the ringing card, the way iOS
/// shows your own camera behind an incoming FaceTime call. It keeps running
/// through both the ringing and answered states and stops when the screen
/// goes away.
///
/// **One session for every FaceTime screen, and every call on it made on one
/// serial queue, never the main thread** (2026-09-23, after Melvin's phone
/// froze for seconds while he tapped Otto's notification over and over).
/// Each screen used to build its own session and configure it on the main
/// thread, so a second call arriving while the first was still stopping
/// fought it for the camera with the interface waiting on the result. Now
/// the screens share `FrontCameraEngine.shared`, count themselves in and out
/// (`holders`), and the session stops only when the last one leaves.
@MainActor
final class FrontCamera: ObservableObject {
    var session: AVCaptureSession { FrontCameraEngine.shared.session }
    /// Configured and allowed, so a preview can attach: the preview layer is
    /// attached BEFORE the session starts, the order Apple's own camera
    /// sample uses, so attaching never reconfigures a running session.
    @Published var ready = false

    private var started = false
    private var holding = false
    private static var holders = 0

    /// Asks for the camera once. A denied or restricted status, or no
    /// camera at all (the simulator has none), leaves `ready` false for
    /// good, and every caller falls back gracefully rather than showing a
    /// black void.
    func start() async {
        guard !started else { return }
        started = true
        FrontCameraEngine.log.info("start requested")

        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil else {
            return
        }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard authorized, started else { return }

        holding = true
        Self.holders += 1
        guard await FrontCameraEngine.shared.configure(), started else { return }
        ready = true
        // One frame for the preview to attach before the session starts.
        try? await Task.sleep(for: .milliseconds(60))
        guard started else { return }
        let running = await FrontCameraEngine.shared.startRunning()
        if !running, started { ready = false }
    }

    func stop() {
        guard started else { return }
        started = false
        ready = false
        FrontCameraEngine.log.info("stop requested")
        guard holding else { return }
        holding = false
        Self.holders -= 1
        if Self.holders == 0 { FrontCameraEngine.shared.stopRunning() }
    }
}

/// The session and the one queue it is touched on. `configured` is read and
/// written on `queue` only.
final class FrontCameraEngine: @unchecked Sendable {
    static let shared = FrontCameraEngine()
    static let log = Logger(subsystem: "com.lockout.meditate808", category: "FrontCamera")

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.lockout.meditate808.front-camera")
    private var configured = false

    /// Adds the front camera once, for the life of the app.
    func configure() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !configured,
                   let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device) {
                    let began = Date()
                    session.beginConfiguration()
                    if session.canAddInput(input) {
                        session.addInput(input)
                        configured = true
                    }
                    session.commitConfiguration()
                    Self.log.info("configured in \(Date().timeIntervalSince(began), format: .fixed(precision: 2))s")
                }
                continuation.resume(returning: configured)
            }
        }
    }

    func startRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let began = Date()
                if !session.isRunning { session.startRunning() }
                Self.log.info("running=\(self.session.isRunning) after \(Date().timeIntervalSince(began), format: .fixed(precision: 2))s")
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    func stopRunning() {
        queue.async { [self] in
            let began = Date()
            if session.isRunning { session.stopRunning() }
            Self.log.info("stopped after \(Date().timeIntervalSince(began), format: .fixed(precision: 2))s")
        }
    }
}

/// The live preview layer, mirrored like FaceTime's own self-view.
///
/// Named apart from `SelfieCamera.swift`'s own private `CameraPreview`
/// (that one is file-scoped, so the two would otherwise collide the
/// moment either is made visible outside its file).
///
/// **The FaceTime screen keeps ONE of these for both of its states**, and
/// Accept only moves and shrinks it. Swapping the full-screen preview for a
/// second, smaller one attached a new layer to a running session, which
/// makes the session rebuild its video path while the interface waits:
/// the blank seconds between Accept and Otto (Melvin, 2026-09-23).
struct FaceTimeCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        mirror(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // The connection isn't guaranteed to exist yet when `makeUIView`
        // runs (the session may still be mid-configuration), so this is
        // re-asserted on every update rather than once.
        mirror(uiView)
    }

    /// Writes only what differs: a connection setter can make the session
    /// reconfigure, and this runs on every SwiftUI update of the screen.
    private func mirror(_ view: PreviewView) {
        guard let connection = view.preview.connection, connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
        if !connection.isVideoMirrored { connection.isVideoMirrored = true }
    }
}
