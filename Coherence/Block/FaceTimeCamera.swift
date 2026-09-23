import SwiftUI
import AVFoundation

/// The front camera behind Otto's FaceTime screen (`InterventionView.swift`).
/// Live preview only: nothing is captured, recorded, or saved anywhere, which
/// is exactly what `NSCameraUsageDescription` promises for this screen.
///
/// Starts the moment the screen appears, not on Accept, because the incoming
/// state wants your own camera live behind the ringing card, the way iOS
/// shows your own camera behind an incoming FaceTime call. It keeps running
/// through both the ringing and answered states and stops when the screen
/// goes away.
@MainActor
final class FrontCamera: ObservableObject {
    let session = AVCaptureSession()
    @Published var running = false

    private var started = false

    /// Asks for the camera once. A denied or restricted status, or no
    /// camera at all (the simulator has none), leaves `running` false for
    /// good, and every caller falls back gracefully rather than showing a
    /// black void.
    func start() async {
        guard !started else { return }
        started = true

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
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
        guard authorized, let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()

        // Blocks for up to a second: run it off the main actor, or every
        // tap on the screen while it starts up feels dead.
        let session = self.session
        await Task.detached { session.startRunning() }.value
        running = session.isRunning
    }

    func stop() {
        guard started else { return }
        started = false
        running = false
        let session = self.session
        Task.detached { session.stopRunning() }
    }
}

/// The live preview layer, mirrored like FaceTime's own self-view.
///
/// Named apart from `SelfieCamera.swift`'s own private `CameraPreview`
/// (that one is file-scoped, so the two would otherwise collide the
/// moment either is made visible outside its file).
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

    private func mirror(_ view: PreviewView) {
        guard let connection = view.preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
