import SwiftUI
import AVFoundation

/// 808's own camera, BeReal-shaped (mockup `mockups/save-session-v5.html`,
/// "The camera, v5"): pure black, the mark centred at the top, a rounded
/// viewfinder that is not full bleed, and exactly one control on the bottom
/// bar, an unfilled white ring. No flip, because the rule is a selfie of you
/// meditating and a control the store would then refuse is a broken promise
/// (Aziz, 2026-09-15). No library, because it has to be now. No gold, because
/// on a photo screen an accent ring reads as a record button.
///
/// Replaces Apple's `UIImagePickerController` for the selfie: that sheet
/// carried Apple's chrome, a library button and a "Use Photo" step in Apple's
/// voice, and looked like a different app because it was one.
struct SelfieCamera: View {
    let onPhoto: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = SelfieCameraModel()
    @State private var captured: UIImage?
    @State private var flashOn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .frame(height: 44)
                viewfinder
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                bottomBar
                    .frame(height: 132)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("808")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if captured == nil, camera.canFlash {
                Button { flashOn.toggle() } label: {
                    Image(systemName: flashOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack(alignment: .bottom) {
            if let captured {
                // The shot fills the same frame the preview did, so review is
                // a continuation of the same screen, not a new page.
                Color.black.overlay(Image(uiImage: captured).resizable().scaledToFill())
            } else {
                switch camera.state {
                case .denied:
                    deniedCard
                case .unavailable:
                    unavailableCard
                case .idle, .running:
                    CameraPreview(session: camera.session)
                }
            }
            if captured == nil, camera.state == .running {
                Text("You, right after you sat")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .clipShape(shape)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let captured {
            HStack(spacing: 12) {
                Button { self.captured = nil } label: {
                    Text("Retake")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    onPhoto(captured)
                    dismiss()
                } label: {
                    Text("Use this one")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
        } else {
            Button {
                Task {
                    if let image = await camera.capture(flash: flashOn) { captured = image }
                }
            } label: {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                    .overlay {
                        // The ring fills for the instant the shutter is held,
                        // which is the only feedback a silent camera gives.
                        if camera.capturing { Circle().fill(.white).padding(4) }
                    }
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running || camera.capturing)
            .opacity(camera.state == .running ? 1 : 0.35)
        }
    }

    private var deniedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.7))
            Text("808 can't use the camera")
                .font(AppFont.headline).foregroundStyle(.white)
            Text("Turn it on in Settings to take your selfie.")
                .font(AppFont.caption).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    private var unavailableCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.7))
            Text("No camera on this device")
                .font(AppFont.headline).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }
}

// MARK: - Capture model

/// Front camera only, portrait only (the app is portrait only), mirrored so
/// what you see is what you get: `AVCapturePhotoOutput` does not mirror the
/// front camera by default, and an un-mirrored selfie reads as someone else.
@MainActor
final class SelfieCameraModel: ObservableObject {
    enum State: Equatable { case idle, running, denied, unavailable }

    @Published private(set) var state: State = .idle
    @Published private(set) var capturing = false
    @Published private(set) var canFlash = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.lockout.meditate808.selfie")
    private var configured = false
    private var delegate: PhotoDelegate?

    func start() {
        #if targetEnvironment(simulator)
        state = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configureAndRun() } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
        #endif
    }

    func stop() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        state = .idle
    }

    private func configureAndRun() {
        let session = self.session
        let output = self.output
        queue.async { [weak self] in
            var ok = true
            if !(self?.configured ?? false) {
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input), session.canAddOutput(output) {
                    session.addInput(input)
                    session.addOutput(output)
                    if let connection = output.connection(with: .video) {
                        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = true
                        }
                    }
                } else {
                    ok = false
                }
                session.commitConfiguration()
            }
            if ok { session.startRunning() }
            let flash = output.supportedFlashModes.contains(.on)
            Task { @MainActor in
                self?.configured = ok
                self?.canFlash = flash
                self?.state = ok ? .running : .unavailable
            }
        }
    }

    func capture(flash: Bool) async -> UIImage? {
        guard state == .running, !capturing else { return nil }
        capturing = true
        defer { capturing = false }
        let settings = AVCapturePhotoSettings()
        if canFlash { settings.flashMode = flash ? .on : .off }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let delegate = PhotoDelegate { image in
                continuation.resume(returning: image)
            }
            self.delegate = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                done(nil); return
            }
            done(image)
        }
    }
}

/// The live preview. Mirrored by AVFoundation's default for a front camera,
/// which is the mirror people expect from a selfie.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
