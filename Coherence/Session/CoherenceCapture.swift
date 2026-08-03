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
/// The live preview view. One shared instance lives on the capture object so
/// screens can swap without re-attaching the layer to a running session
/// (re-attachment causes a visible glitch).
final class PPGPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

final class CoherenceCapture: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Camera + torch running, waiting for a steady finger. The 45 s
        /// window starts itself when the finger is detected, and RESTARTS
        /// from here if the finger comes off mid-read.
        case waiting
        case measuring
        case analyzing
        case done
        case failed(ReadFailure)
    }

    /// Why a read didn't produce a number. Typed, not a string, so the UI can
    /// coach the ACTUAL cause — "your finger slipped" and "no camera access"
    /// need completely different advice. A refused read is normal and common
    /// (see the field-calibration notes in CLAUDE.md); the screen that shows
    /// this should read as a nudge, never an error.
    enum ReadFailure: Equatable {
        /// Analyzer refused: pulse present but too noisy to trust.
        case unreadable
        /// Finger left the lens during the window.
        case fingerMoved
        /// Almost no usable frames — usually a finger that never covered the lens.
        case tooLittleSignal
        /// Camera permission denied or turned off.
        case noCameraAccess
        /// No usable camera hardware / capture couldn't start.
        case cameraUnavailable
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0          // 0–1 of the capture window
    @Published var fingerDetected = false
    @Published var pulseLevel: Double = 0        // live waveform hint for the UI
    @Published var snapshot: CoherenceAnalyzer.Snapshot?
    /// On-screen diagnostics (DEBUG builds surface these in the UI so device
    /// testing doesn't need Xcode's console).
    @Published var debugLive = ""                // live camera channel readout
    @Published var debugResult = ""              // per-gate verdict after a read

    /// Capture window. 45 s is the floor for resolving the ~0.1 Hz coherence
    /// rhythm (≈4.5 cycles); the analyzer needs ~30 s of usable beats inside it.
    let targetDuration: Double = 45

    /// For the live preview circle in the UI (PeaceMind-style: you can see
    /// what the camera sees while placing your finger). Shared instance —
    /// see PPGPreviewView.
    let previewView = PPGPreviewView()

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.lockout.coherence.ppg")
    private var device: AVCaptureDevice?
    private var samples: [Double] = []
    private var timestamps: [Double] = []
    private var startTime: CFTimeInterval?
    private var recentForLevel: [Double] = []
    private var coveredFrames = 0
    private var totalFrames = 0
    /// Queue-side state machine (the @Published phase mirrors it for the UI).
    private enum QState { case waiting, measuring, finished }
    private var qState: QState = .waiting
    /// Hysteresis state of the finger detector (enter strict, exit strict the
    /// other way) — kills the flicker of a borderline per-frame detector.
    private var isCovered = false
    private var uncoveredStreak = 0
    private var lastPublishedFinger: Bool?
    private var frameCounter = 0

    // MARK: - Lifecycle

    func start() {
        guard phase != .measuring, phase != .waiting else { return }
        snapshot = nil
        progress = 0
        // Attach the preview BEFORE the session runs — attaching to a running
        // session forces a reconfiguration and a visible stutter.
        if previewView.previewLayer.session == nil {
            previewView.previewLayer.session = session
            previewView.previewLayer.videoGravity = .resizeAspectFill
        }
        queue.async {
            self.resetWindow()
            self.qState = .waiting
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.queue.async {
                    granted ? self.configureAndRun()
                            : self.fail(.noCameraAccess)
                }
            }
        default:
            fail(.noCameraAccess)
        }
    }

    /// Explicitly begins the 45 s read (the Start button). The camera and
    /// torch are already live from `start()`; this locks exposure and opens
    /// the window. No-op unless we're in waiting.
    func beginMeasurement() {
        queue.async {
            guard self.qState == .waiting else { return }
            self.resetWindow()
            self.lockExposure(true)
            self.qState = .measuring
            DispatchQueue.main.async { self.phase = .measuring; self.progress = 0 }
        }
    }

    func cancel() {
        queue.async {
            self.qState = .finished          // stop any in-flight frames
            self.teardown()
            DispatchQueue.main.async { self.phase = .idle }
        }
    }

    // MARK: - Session setup (capture queue)

    private func configureAndRun() {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else {
            fail(.cameraUnavailable)
            return
        }
        device = cam

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .low                       // tiny frames, we only average them

        guard session.canAddInput(input) else { fail(.cameraUnavailable); return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { fail(.cameraUnavailable); return }
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
        DispatchQueue.main.async { self.phase = .waiting }
    }

    /// Clears the capture window (used on start and when the finger comes off
    /// mid-read — the measurement restarts rather than silently degrading).
    private func resetWindow() {
        samples = []; timestamps = []
        startTime = nil
        coveredFrames = 0; totalFrames = 0
        uncoveredStreak = 0
    }

    /// PPG needs a locked exposure: with the torch through a fingertip the
    /// auto-exposure keeps "correcting", and those swings dwarf the pulse.
    /// Locked when a read arms, released when it ends or resets.
    private func lockExposure(_ lock: Bool) {
        guard let cam = device else { return }
        try? cam.lockForConfiguration()
        if lock {
            if cam.isExposureModeSupported(.locked) { cam.exposureMode = .locked }
            if cam.isWhiteBalanceModeSupported(.locked) { cam.whiteBalanceMode = .locked }
        } else {
            if cam.isExposureModeSupported(.continuousAutoExposure) {
                cam.exposureMode = .continuousAutoExposure
            }
            if cam.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                cam.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
        cam.unlockForConfiguration()
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
        lockExposure(false)
        setTorch(on: false)
        if session.isRunning { session.stopRunning() }
    }

    #if DEBUG
    /// Jumps straight to a failure page (simctl: PREVIEW_READ_FAILURE=unreadable).
    func previewFailure(_ reason: ReadFailure) { phase = .failed(reason) }
    #endif

    private func fail(_ reason: ReadFailure) {
        teardown()
        DispatchQueue.main.async { self.phase = .failed(reason) }
    }

    // MARK: - Finish

    private func finishAndAnalyze() {
        teardown()
        DispatchQueue.main.async { self.phase = .analyzing }

        let duration = (timestamps.last ?? 0) - (timestamps.first ?? 0)
        guard duration > 0, samples.count > 10 else {
            fail(.tooLittleSignal)
            return
        }
        let coverage = totalFrames > 0 ? Double(coveredFrames) / Double(totalFrames) : 0
        guard coverage >= 0.7 else {
            fail(.fingerMoved)
            return
        }
        let effectiveRate = Double(samples.count - 1) / duration
        let result = CoherenceAnalyzer.analyze(ppg: samples, sampleRate: effectiveRate)
        #if DEBUG
        let verdict = CoherenceAnalyzer.diagnose(ppg: samples, sampleRate: effectiveRate)
            + String(format: " · coverage %.0f%%", coverage * 100)
            + (result.map { String(format: " · score %.2f", $0.coherenceScore) } ?? " · REFUSED")
        print("[coherence] " + verdict)
        DispatchQueue.main.async { self.debugResult = verdict }
        #endif

        DispatchQueue.main.async {
            if let result {
                self.snapshot = result
                self.phase = .done
            } else {
                self.phase = .failed(.unreadable)
            }
        }
    }
}

// MARK: - Frame reduction

extension CoherenceCapture: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard qState != .finished,
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

        // Finger detection with HYSTERESIS: strict to enter, strict the other
        // way to exit. A borderline per-frame detector flickered 30×/s, which
        // both glitched the UI and made the old 20-consecutive arming gate
        // unreachable.
        if isCovered {
            if r < 0.3 || r < 0.95 * g { isCovered = false }
        } else {
            if r > 0.4 && r > 1.05 * g && r > 1.15 * b { isCovered = true }
        }
        let covered = isCovered

        if covered { uncoveredStreak = 0 } else { uncoveredStreak += 1 }

        frameCounter += 1
        #if DEBUG
        if frameCounter % 30 == 0 {
            let line = String(format: "r %.2f · g %.2f · b %.2f · %@",
                              r, g, b, covered ? "finger ✓" : "no finger")
            print("[ppg] " + line + " state=\(qState)")
            DispatchQueue.main.async { self.debugLive = line }
        }
        #endif

        // Live pulse hint: deviation of the newest sample from the recent mean.
        recentForLevel.append(r)
        if recentForLevel.count > 45 { recentForLevel.removeFirst() }
        let mean = recentForLevel.reduce(0, +) / Double(recentForLevel.count)
        let level = min(1, abs(r - mean) * 40)

        // Publish only on change / at ~10 Hz — 30 publishes a second re-rendered
        // the screen constantly.
        if covered != lastPublishedFinger {
            lastPublishedFinger = covered
            DispatchQueue.main.async { self.fingerDetected = covered }
        }
        if frameCounter % 3 == 0 {
            DispatchQueue.main.async { self.pulseLevel = level }
        }

        let now = CACurrentMediaTime()

        switch qState {
        case .waiting:
            // Camera + torch live for placement; the read begins only when the
            // user taps Start (beginMeasurement).
            break

        case .measuring:
            // Finger clearly off for ~1.5 s → back to placement rather than
            // running a doomed timer to a guaranteed failure.
            if uncoveredStreak >= 45 {
                resetWindow()
                lockExposure(false)
                qState = .waiting
                DispatchQueue.main.async {
                    self.phase = .waiting
                    self.progress = 0
                }
                return
            }

            if startTime == nil { startTime = now }
            let t = now - (startTime ?? now)
            // NEGATED: with the torch shining through the fingertip, each
            // heartbeat pushes MORE blood in, absorbing more light — the pulse
            // is a dip in red, not a peak. Inverting makes the systolic dip
            // the sharp positive feature the analyzer's peak detector expects.
            samples.append(-r)
            timestamps.append(t)
            totalFrames += 1
            if covered { coveredFrames += 1 }

            if frameCounter % 3 == 0 {
                let progressNow = min(1, t / targetDuration)
                DispatchQueue.main.async { self.progress = progressNow }
            }

            if t >= targetDuration {
                qState = .finished
                finishAndAnalyze()
            }

        case .finished:
            break
        }
    }
}
