import AVFoundation
import Combine
import UIKit

/// Camera-PPG capture for the coherence snapshot: back camera + torch, finger
/// over the lens, ~30 fps. Each frame is reduced to its mean red level; the
/// resulting waveform goes to `CoherenceAnalyzer` when the window completes.
///
/// This is the FIRST sensor code on the phone side — a deliberate exception
/// to "all sensing lives on the Watch" (documented in the roadmap, Phase 9).
/// Frames are reduced to one number each on the fly and never stored.
final class CoherenceCapture: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case measuring
        case analyzing
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0          // 0–1 of the capture window
    @Published var fingerDetected = false
    @Published var pulseLevel: Double = 0        // live waveform hint for the UI
    @Published var snapshot: CoherenceAnalyzer.Snapshot?

    /// Capture window. 45 s is the floor for resolving the ~0.1 Hz coherence
    /// rhythm (≈4.5 cycles); the analyzer needs ~30 s of usable beats inside it.
    let targetDuration: Double = 45

    /// For the live preview circle in the UI (PeaceMind-style: you can see
    /// what the camera sees while placing your finger).
    var previewSession: AVCaptureSession { session }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.lockout.coherence.ppg")
    private var device: AVCaptureDevice?
    private var samples: [Double] = []
    private var timestamps: [Double] = []
    private var startTime: CFTimeInterval?
    private var recentForLevel: [Double] = []
    private var coveredFrames = 0
    private var totalFrames = 0
    /// Set on the capture queue when the window completes; frames that arrive
    /// while the session is still spinning down are ignored.
    private var finished = false

    // MARK: - Lifecycle

    func start() {
        guard phase != .measuring else { return }
        snapshot = nil
        progress = 0
        queue.async {
            self.samples = []; self.timestamps = []
            self.startTime = nil; self.finished = false
            self.coveredFrames = 0; self.totalFrames = 0
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.queue.async {
                    granted ? self.configureAndRun()
                            : self.fail("Camera access is needed to read your pulse.")
                }
            }
        default:
            fail("Camera access is off. Enable it in Settings to measure.")
        }
    }

    func cancel() {
        queue.async {
            self.teardown()
            DispatchQueue.main.async { self.phase = .idle }
        }
    }

    // MARK: - Session setup (capture queue)

    private func configureAndRun() {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else {
            fail("No usable camera on this device.")
            return
        }
        device = cam

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .low                       // tiny frames, we only average them

        guard session.canAddInput(input) else { fail("Camera unavailable."); return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { fail("Camera unavailable."); return }
        session.addOutput(output)
        session.commitConfiguration()

        // Pin ~30 fps so the waveform is (near-)uniformly sampled.
        if let range = cam.activeFormat.videoSupportedFrameRateRanges.first {
            let fps = min(30, range.maxFrameRate)
            try? cam.lockForConfiguration()
            cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            cam.unlockForConfiguration()
        }

        session.startRunning()
        setTorch(on: true)
        DispatchQueue.main.async { self.phase = .measuring }
    }

    private func setTorch(on: Bool) {
        guard let cam = device, cam.hasTorch else { return }
        try? cam.lockForConfiguration()
        if on, cam.isTorchModeSupported(.on) {
            // Modest level: enough to transilluminate the fingertip, less heat.
            try? cam.setTorchModeOn(level: 0.6)
        } else {
            cam.torchMode = .off
        }
        cam.unlockForConfiguration()
    }

    private func teardown() {
        setTorch(on: false)
        if session.isRunning { session.stopRunning() }
    }

    private func fail(_ message: String) {
        teardown()
        DispatchQueue.main.async { self.phase = .failed(message) }
    }

    // MARK: - Finish

    private func finishAndAnalyze() {
        teardown()
        DispatchQueue.main.async { self.phase = .analyzing }

        let duration = (timestamps.last ?? 0) - (timestamps.first ?? 0)
        guard duration > 0, samples.count > 10 else {
            fail("Too little signal. Keep your finger flat on the camera and try again.")
            return
        }
        let coverage = totalFrames > 0 ? Double(coveredFrames) / Double(totalFrames) : 0
        guard coverage >= 0.7 else {
            fail("Your finger came off the camera during the read. Cover the "
                 + "camera and flash completely and try again.")
            return
        }
        let effectiveRate = Double(samples.count - 1) / duration
        let result = CoherenceAnalyzer.analyze(ppg: samples, sampleRate: effectiveRate)
        #if DEBUG
        let beats = CoherenceAnalyzer.beatTimes(ppg: samples, sampleRate: effectiveRate)
        print("[coherence] frames=\(samples.count) fps=\(String(format: "%.1f", effectiveRate)) "
              + "coverage=\(String(format: "%.2f", coverage)) beats=\(beats.count) "
              + "result=\(result.map { String(format: "score %.2f hr %.0f", $0.coherenceScore, $0.meanHR) } ?? "nil")")
        #endif

        DispatchQueue.main.async {
            if let result {
                self.snapshot = result
                self.phase = .done
            } else {
                self.phase = .failed(
                    "Couldn't get a clean read. Rest your fingertip flat over the "
                    + "camera and flash, press lightly, and hold still.")
            }
        }
    }
}

// MARK: - Frame reduction

extension CoherenceCapture: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !finished,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Stride-sample the frame; BGRA layout. One pass gives mean R/G/B.
        var rSum = 0, gSum = 0, bSum = 0, count = 0
        let step = 8
        var y = 0
        while y < height {
            var x = 0
            let row = y * rowBytes
            while x < width {
                let p = row + x * 4
                bSum += Int(ptr[p]); gSum += Int(ptr[p + 1]); rSum += Int(ptr[p + 2])
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return }
        let r = Double(rSum) / Double(count) / 255.0
        let g = Double(gSum) / Double(count) / 255.0
        let b = Double(bSum) / Double(count) / 255.0

        // A torch-lit fingertip floods the sensor with red. Deliberately loose
        // (a saturated frame lifts green too): red merely has to be high and
        // clearly the biggest channel. Drives coaching, not sample-keeping.
        let covered = r > 0.35 && r > 1.15 * g && r > 1.3 * b

        let now = CACurrentMediaTime()
        if startTime == nil { startTime = now }
        let t = now - (startTime ?? now)

        // Keep EVERY frame so the waveform stays uniformly sampled — gaps from
        // a flickery finger-detector were shredding the beat series. Coverage
        // is judged once, at the end.
        samples.append(r)
        timestamps.append(t)
        totalFrames += 1
        if covered { coveredFrames += 1 }

        // Live pulse hint: deviation of the newest sample from the recent mean.
        recentForLevel.append(r)
        if recentForLevel.count > 45 { recentForLevel.removeFirst() }
        let mean = recentForLevel.reduce(0, +) / Double(recentForLevel.count)
        let level = min(1, abs(r - mean) * 40)

        let progressNow = min(1, t / targetDuration)
        DispatchQueue.main.async {
            self.fingerDetected = covered
            self.pulseLevel = level
            self.progress = progressNow
        }

        if t >= targetDuration {
            finished = true
            finishAndAnalyze()
        }
    }
}
