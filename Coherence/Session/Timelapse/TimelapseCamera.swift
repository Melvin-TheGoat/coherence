import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import os

/// The camera behind a session timelapse: one `AVCaptureSession`, front or
/// back, run on its own serial queue and never on the main thread (the
/// lesson of the 2026-10-06 freeze, `FrontCameraEngine`). Frames arrive from
/// an `AVCaptureVideoDataOutput` and only the few the reel wants are kept, as
/// small portrait JPEGs on disk under the session's id: **nothing is recorded
/// at full rate, and there is no microphone**, so no second permission and
/// nothing that could touch the session's own sound.
///
/// Separate from `FrontCameraEngine` (Otto's video call), which is front-only
/// and has no output: a call and a sit never run at once.
final class TimelapseCamera: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = TimelapseCamera()
    static let log = Logger(subsystem: "com.lockout.meditate808", category: "Timelapse")

    let session = AVCaptureSession()
    /// Configuration, start and stop. Never the main thread.
    private let queue = DispatchQueue(label: "com.lockout.meditate808.timelapse-camera")
    /// Frames, and everything about the reel. Its own queue so writing a
    /// JPEG never holds up a configuration change.
    private let frameQueue = DispatchQueue(label: "com.lockout.meditate808.timelapse-frames")

    // Touched on `queue` only.
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private var outputAdded = false
    private var pressureObservation: NSKeyValueObservation?

    // Touched on `frameQueue` only.
    private var plan: TimelapseReelPlan?
    private var reelDir: URL?
    private var reelStart: Date?
    private var files: [URL] = []
    private var counter = 0
    private var paused = false
    private var lens: TimelapseLens = .front
    private lazy var ci = CIContext(options: [.cacheIntermediates: false])
    #if DEBUG
    private var wroteFacts = false
    #endif

    /// The size of every kept still: 9:16 portrait, the clip's shape. About
    /// 90 KB at this quality.
    static let frameWidth = 720
    static let frameHeight = 1280

    // MARK: - Configuration

    static func device(for lens: TimelapseLens) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                position: lens == .front ? .front : .back)
    }

    func hasCamera(_ lens: TimelapseLens) async -> Bool {
        await withCheckedContinuation { c in
            queue.async { c.resume(returning: Self.device(for: lens) != nil) }
        }
    }

    /// Puts this lens on the session (swapping out the other one), with the
    /// frame output and its rotation set for portrait.
    func configure(_ lens: TimelapseLens) async -> Bool {
        await withCheckedContinuation { c in
            queue.async { [self] in
                c.resume(returning: configureOnQueue(lens))
            }
        }
    }

    private func configureOnQueue(_ lens: TimelapseLens) -> Bool {
        if let input, input.device.position == (lens == .front ? .front : .back) { return true }
        guard let device = Self.device(for: lens),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        let began = Date()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input { session.removeInput(input) }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(newInput) else {
            if let input { session.addInput(input) }
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !outputAdded, session.canAddOutput(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(output)
            outputAdded = true
        }
        // Portrait, and mirrored for the front lens, set on the connection so
        // the pixels themselves arrive that way. `keep` still trusts the
        // pixels over this (the selfie lesson): a landscape buffer is turned.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = lens.mirrored
            }
        }
        frameQueue.async { [self] in self.lens = lens }
        observePressure(on: device)
        Self.log.info("configured \(lens.rawValue, privacy: .public) in \(Date().timeIntervalSince(began), format: .fixed(precision: 2))s")
        return true
    }

    func startRunning() async -> Bool {
        await withCheckedContinuation { c in
            queue.async { [self] in
                if !session.isRunning { session.startRunning() }
                c.resume(returning: session.isRunning)
            }
        }
    }

    func stopRunning() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            Self.log.info("stopped")
            Task { @MainActor in self.releaseRetired() }
        }
    }

    /// The lowest frame rate the format allows, at least `fps`, while filming;
    /// the format's own rate otherwise, so the viewfinder moves smoothly.
    func setFilmingRate(_ filming: Bool) {
        queue.async { [self] in
            guard let device = input?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if filming {
                let lowest = device.activeFormat.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? 5
                let rate = max(lowest, 5)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(rate))
            } else {
                device.activeVideoMinFrameDuration = .invalid
            }
        }
    }

    /// Serious: sample half as often. Critical: stop keeping frames and let
    /// the session carry on; the clip covers what was filmed.
    private func observePressure(on device: AVCaptureDevice) {
        pressureObservation = device.observe(\.systemPressureState, options: [.new]) { [weak self] device, _ in
            guard let self else { return }
            let level = device.systemPressureState.level
            self.frameQueue.async {
                switch level {
                case .serious: self.plan?.slowDown()
                case .critical, .shutdown: self.paused = true
                default: break
                }
            }
            Self.log.info("system pressure \(level.rawValue, privacy: .public)")
        }
    }

    // MARK: - The reel

    /// Starts keeping frames for a session. `dir` is created empty.
    func beginReel(in dir: URL, plannedSeconds: Double?) {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        frameQueue.async { [self] in
            plan = TimelapseReelPlan(plannedSeconds: plannedSeconds)
            reelDir = dir
            reelStart = Date()
            files = []
            counter = 0
            paused = false
        }
    }

    /// Stops keeping frames and hands back what was kept, in order.
    func endReel() async -> [URL] {
        await withCheckedContinuation { c in
            frameQueue.async { [self] in
                let kept = files
                plan = nil
                reelDir = nil
                reelStart = nil
                files = []
                c.resume(returning: kept)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard var plan, let reelDir, let reelStart, !paused,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = Date().timeIntervalSince(reelStart)
        guard plan.wants(at: t) else { return }
        var image = CIImage(cvPixelBuffer: pixels)
        #if DEBUG
        writeFactsOnce(image: image, connection: connection, dir: reelDir)
        #endif
        // Trust the pixels, not the connection: a landscape buffer was not
        // rotated, so turn it upright here (and mirror the front lens, which
        // then was not mirrored either).
        if image.extent.width > image.extent.height {
            image = image.oriented(lens.mirrored ? .leftMirrored : .right)
        }
        guard let data = Self.jpeg(of: image, context: ci) else { return }
        let url = reelDir.appendingPathComponent(String(format: "f-%06d.jpg", counter))
        counter += 1
        guard (try? data.write(to: url)) != nil else { return }
        files.append(url)
        let dropped = plan.keep(at: t)
        for i in dropped.reversed() where i < files.count {
            try? FileManager.default.removeItem(at: files[i])
            files.remove(at: i)
        }
        self.plan = plan
    }

    /// Scaled to fill 720 by 1280 and cropped to it, then JPEG.
    static func jpeg(of image: CIImage, context: CIContext) -> Data? {
        let w = CGFloat(frameWidth), h = CGFloat(frameHeight)
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let scale = max(w / e.width, h / e.height)
        var scaled = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sx = (scaled.extent.width - w) / 2, sy = (scaled.extent.height - h) / 2
        scaled = scaled.cropped(to: CGRect(x: sx, y: sy, width: w, height: h))
            .transformed(by: CGAffineTransform(translationX: -sx, y: -sy))
        return context.jpegRepresentation(of: scaled, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
    }

    #if DEBUG
    /// The front camera has lied about its rotation once (the selfie lesson),
    /// so a DEBUG build with `TIMELAPSE_DEBUG=1` writes the first raw frame
    /// and what the connection claimed to Documents/TimelapseDebug, for
    /// `devicectl device copy from --domain-type appDataContainer`.
    private func writeFactsOnce(image: CIImage, connection: AVCaptureConnection, dir: URL) {
        guard !wroteFacts, ProcessInfo.processInfo.environment["TIMELAPSE_DEBUG"] == "1" else { return }
        wroteFacts = true
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let out = docs.appendingPathComponent("TimelapseDebug", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let facts = """
        lens \(lens.rawValue)
        pixels \(Int(image.extent.width))x\(Int(image.extent.height))
        connection videoRotationAngle \(connection.videoRotationAngle)
        connection isVideoMirrored \(connection.isVideoMirrored)
        """
        try? facts.write(to: out.appendingPathComponent("facts.txt"), atomically: true, encoding: .utf8)
        if let raw = ci.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) {
            try? raw.write(to: out.appendingPathComponent("raw.jpg"))
        }
    }
    #endif

    // MARK: - Previews

    /// Preview views whose screen has gone, kept until the session is still
    /// (the `FrontCameraEngine.retire` lesson: freeing a preview layer while
    /// the session starts or stops holds the main thread).
    @MainActor private var retired: [UIView] = []

    @MainActor
    func retire(_ view: UIView) {
        retired.append(view)
        queue.async { [self] in
            guard !session.isRunning else { return }
            Task { @MainActor in self.releaseRetired() }
        }
    }

    @MainActor
    private func releaseRetired() {
        retired.removeAll()
    }
}

/// The live picture: the viewfinder on the Ready screen and the small
/// self-view during the sit. The front lens is mirrored, like the selfie
/// camera and the clip itself.
struct TimelapsePreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = TimelapseCamera.shared.session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        TimelapseCamera.shared.retire(uiView)
    }
}
