#if DEBUG
import Foundation
import AVFoundation
import CoreVideo
import Vision
import UIKit
import os

/// Records the camera-vision signals alongside a normal Watch session, so every
/// test sit becomes a labelled pair: the camera's per-frame signals in one file
/// and the wrist's own per-window results in the file beside it.
///
/// This is the ground-truth collector the camera work is starved for, and it
/// is the capture path that would ship: the same four signals
/// `tools/camera_probe.swift` extracts offline, computed live on the luma plane
/// at ~10 fps, with a torso ROI from Vision fixed over the first 30 s. No frame
/// is ever stored; only the numbers leave this class.
///
/// Two phases, ONE camera session. `start()` runs the front camera in
/// PREVIEW: frames are watched for a person (`framed`, which drives the Begin
/// sheet's outline) and nothing is recorded. `arm(sessionID:sessionStartedAt:)`,
/// called on the Watch's started-ack, makes the next frame t = 0 and begins
/// the samples, so the two files line up without the offline lab having to
/// solve for an offset. The camera is never restarted between the phases:
/// that is what lets a person frame themselves before Begin and keep it.
///
/// DEBUG only, and behind Settings > "Camera capture (debug)".
final class CameraSignalRecorder: NSObject, ObservableObject {

    static let debugToggleKey = "debug.cameraCapture"

    struct Sample {
        let t: Double
        let motion: Double, dy: Double, dx: Double, luma: Double
        let rmotion: Double, rdy: Double, rdx: Double, rluma: Double
    }

    /// Normalized, origin top-left, in the (rotated-to-portrait) buffer's space.
    struct ROI: Equatable {
        var x: Double, y: Double, w: Double, h: Double
        func padded(_ pad: Double) -> ROI {
            let nx = max(0, x - w * pad), ny = max(0, y - h * pad)
            return ROI(x: nx, y: ny, w: min(1 - nx, w * (1 + 2 * pad)), h: min(1 - ny, h * (1 + 2 * pad)))
        }
    }

    /// Named by `arm`; nil while the camera is only previewing.
    private(set) var sessionID: UUID?
    private(set) var sessionStartedAt: Date?
    let captureSession = AVCaptureSession()

    @Published private(set) var frameCount = 0
    /// A person is in the frame: found in three of the last four detections
    /// (one a second while previewing). Drives the framing outline.
    @Published private(set) var framed = false
    @Published private(set) var roiFixed = false
    @Published private(set) var statusLine = "starting"

    private let queue = DispatchQueue(label: "com.lockout.meditate808.camera-signals", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private let log = Logger(subsystem: "com.lockout.meditate808", category: "camera")

    // Per-frame state, touched only on `queue`.
    private var armed = false
    private var stopped = false
    private var samples: [Sample] = []
    private var recorderStartedAt = Date()
    private var firstPTS: CMTime?
    private var lastFrameT = 0.0
    private var prev: LumaGrid?
    private var prevRow: [Double] = [], prevCol: [Double] = [], prevRRow: [Double] = [], prevRCol: [Double] = []
    private var dyAcc = 0.0, dxAcc = 0.0, rdyAcc = 0.0, rdxAcc = 0.0
    private var boxes: [CGRect] = []
    private var lastDetectT = -10.0
    private var roi: ROI?
    private var roiFixedAt: Double?
    private var exposureLocked = false
    /// Preview-phase detections, oldest first: when, and the box if a person
    /// was found. Kept so `arm` can fix the ROI from the last few seconds.
    private var previewHits: [(t: Double, box: CGRect?)] = []
    private var lastPreviewDetectT = -10.0
    private var framedOnQueue = false

    private static let gridMax = 240
    private static let fps = 10
    private static let detectEverySec = 5.0
    private static let detectUntilSec = 30.0
    private static let lockExposureAtSec = 3.0
    /// Previewing: a detection a second; framed on three hits in the last four.
    static let previewDetectEverySec = 1.0
    static let framingWindow = 4
    static let framingHits = 3
    /// Person boxes this recent at arm time fix the ROI from t = 0.
    static let previewROIWindowSec = 6.0
    static let previewROIMinimumBoxes = 3

    // MARK: Lifecycle

    /// Runs the camera in preview. Nothing is recorded until `arm`.
    func start() {
        // `PREVIEW_FRAMED=1`: the simulator has no camera, so Vision can never
        // find anyone; this shows the "in frame" state for screenshots.
        if ProcessInfo.processInfo.environment["PREVIEW_FRAMED"] == "1" { framed = true }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in self.statusLine = "permission denied" }
                return
            }
            self.queue.async {
                // Stopped while the permission prompt was up (the sheet was
                // dismissed): starting now would leave the camera running
                // with nothing left to stop it.
                guard !self.stopped else { return }
                self.configureAndRun()
            }
        }
    }

    private func configureAndRun() {
        let s = captureSession
        s.beginConfiguration()
        s.sessionPreset = .vga640x480
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: cam), s.canAddInput(input) else {
            s.commitConfiguration()
            Task { @MainActor in self.statusLine = "no front camera" }
            return
        }
        device = cam
        s.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard s.canAddOutput(output) else { s.commitConfiguration(); return }
        s.addOutput(output)
        // Buffers arrive rotated to portrait, so Vision's orientation is .up
        // and the grid's "vertical" really is the chest's up-and-down.
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            conn.isVideoMirrored = false
        }
        // 10 fps is plenty for a 3–26/min band and keeps the phone cool.
        if (try? cam.lockForConfiguration()) != nil {
            let d = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
            cam.activeVideoMinFrameDuration = d
            cam.activeVideoMaxFrameDuration = d
            cam.unlockForConfiguration()
        }
        s.commitConfiguration()
        s.startRunning()
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            self.statusLine = "previewing"
        }
    }

    /// The Watch's workout has begun: the next frame is t = 0 and recording
    /// starts. If a person was in frame over the last few seconds of preview,
    /// that median box becomes the ROI from the start instead of thirty
    /// seconds in; otherwise the in-session detection runs as it always has.
    /// Auto-exposure stays free until the usual three seconds after t = 0,
    /// so a preview that was still being aimed never locks a wrong scene.
    func arm(sessionID: UUID, sessionStartedAt: Date) {
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        queue.async {
            guard !self.armed, !self.stopped else { return }
            self.armed = true
            self.recorderStartedAt = Date()
            self.firstPTS = nil
            self.samples = []
            self.prev = nil
            self.prevRow = []; self.prevCol = []; self.prevRRow = []; self.prevRCol = []
            self.dyAcc = 0; self.dxAcc = 0; self.rdyAcc = 0; self.rdxAcc = 0
            self.boxes = []
            self.lastDetectT = -10
            self.exposureLocked = false
            let recent = self.previewHits
                .filter { self.lastFrameT - $0.t <= Self.previewROIWindowSec }
                .compactMap(\.box)
            if let r = Self.medianROI(recent, minimum: Self.previewROIMinimumBoxes) {
                self.roi = r
                self.roiFixedAt = 0
                Task { @MainActor in self.roiFixed = true }
            }
            Task { @MainActor in self.statusLine = "recording" }
        }
    }

    /// Stops the camera. Writes both files when a session was recorded; a
    /// preview that was never armed writes nothing. Safe to call twice.
    @discardableResult
    func stop(wrist: SessionPayload?) -> URL? {
        var snapshot: [Sample] = []
        var roiOut: ROI?
        var fixedAt: Double?
        var wasArmed = false
        queue.sync {
            stopped = true
            snapshot = samples
            roiOut = roi
            fixedAt = roiFixedAt
            wasArmed = armed
        }
        queue.async { if self.captureSession.isRunning { self.captureSession.stopRunning() } }
        Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false }
        guard wasArmed, let sessionID, let sessionStartedAt, !snapshot.isEmpty else {
            Task { @MainActor in self.statusLine = "off" }
            return nil
        }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("CameraCaptures", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = sessionID.uuidString

        var csv = "# session_id=\(base)\n"
        csv += String(format: "# session_started_at=%.3f\n", sessionStartedAt.timeIntervalSince1970)
        csv += String(format: "# recorder_started_at=%.3f\n", recorderStartedAt.timeIntervalSince1970)
        csv += "# fps=\(Self.fps) grid=\(Self.gridMax) camera=front preset=vga640x480\n"
        if let r = roiOut {
            csv += String(format: "# roi x=%.4f y=%.4f w=%.4f h=%.4f\n", r.x, r.y, r.w, r.h)
            csv += String(format: "# roi_fixed_at_sec=%.1f\n", fixedAt ?? -1)
        } else {
            csv += "# roi none\n"
        }
        csv += "t,motion,dy,dx,luma,rmotion,rdy,rdx,rluma\n"
        for s in snapshot {
            csv += String(format: "%.3f,%.5f,%.5f,%.5f,%.3f,%.5f,%.5f,%.5f,%.3f\n",
                          s.t, s.motion, s.dy, s.dx, s.luma, s.rmotion, s.rdy, s.rdx, s.rluma)
        }
        let csvURL = dir.appendingPathComponent("\(base).csv")
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)

        // The wrist's own per-window results, verbatim, beside the camera file.
        if let wrist {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .secondsSince1970
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(wrist) {
                try? data.write(to: dir.appendingPathComponent("\(base)_wrist.json"))
            }
        }
        log.info("camera capture written: \(snapshot.count) samples → \(csvURL.lastPathComponent)")
        Task { @MainActor in self.statusLine = "saved \(snapshot.count) frames" }
        return csvURL
    }

    // MARK: Per-frame

    private func process(_ buffer: CVPixelBuffer, pts: CMTime) {
        let raw = pts.seconds
        lastFrameT = raw
        guard armed else {
            previewDetect(buffer, at: raw)
            return
        }

        if firstPTS == nil { firstPTS = pts }
        let t = CMTimeSubtract(pts, firstPTS!).seconds

        // Let auto-exposure settle on the scene, then freeze it: an exposure
        // loop chasing the chest's brightness change would eat the luma signal.
        if !exposureLocked, t >= Self.lockExposureAtSec, let cam = device,
           (try? cam.lockForConfiguration()) != nil {
            if cam.isExposureModeSupported(.locked) { cam.exposureMode = .locked }
            if cam.isWhiteBalanceModeSupported(.locked) { cam.whiteBalanceMode = .locked }
            if cam.isFocusModeSupported(.locked) { cam.focusMode = .locked }
            cam.unlockForConfiguration()
            exposureLocked = true
        }

        // ROI: a detection every 5 s for the first 30 s, then the median box
        // fixed for the rest of the session (a moving box would inject its own
        // jitter into the sub-pixel shift signal). Skipped entirely when the
        // preview already fixed it at t = 0.
        if roi == nil, t < Self.detectUntilSec, t - lastDetectT >= Self.detectEverySec {
            lastDetectT = t
            if let box = Self.detectPerson(in: buffer) { boxes.append(box) }
        }
        if roi == nil, (t >= Self.detectUntilSec || boxes.count >= 6),
           let r = Self.medianROI(boxes, minimum: 3) {
            roi = r
            roiFixedAt = t
            Task { @MainActor in self.roiFixed = true }
        }

        guard let grid = LumaGrid.downsample(buffer, targetMax: Self.gridMax) else { return }
        let row = grid.rowProfile(), col = grid.colProfile()
        var rx0 = 0, rx1 = grid.w, ry0 = 0, ry1 = grid.h
        if let r = roi {
            rx0 = Int(r.x * Double(grid.w)); rx1 = Int((r.x + r.w) * Double(grid.w))
            ry0 = Int(r.y * Double(grid.h)); ry1 = Int((r.y + r.h) * Double(grid.h))
        }
        let rrow = grid.rowProfile(x0: rx0, x1: rx1, y0: ry0, y1: ry1)
        let rcol = grid.colProfile(x0: rx0, x1: rx1, y0: ry0, y1: ry1)

        if let p = prev, p.px.count == grid.px.count {
            let diff = grid.meanAbsDiff(p)
            let rdiff = grid.meanAbsDiff(p, x0: rx0, x1: rx1, y0: ry0, y1: ry1)
            dyAcc += LumaGrid.profileShift(prevRow, row)
            dxAcc += LumaGrid.profileShift(prevCol, col)
            rdyAcc += LumaGrid.profileShift(prevRRow, rrow)
            rdxAcc += LumaGrid.profileShift(prevRCol, rcol)
            let luma = grid.meanLuma(x0: grid.w / 3, x1: 2 * grid.w / 3, y0: grid.h / 3, y1: 2 * grid.h / 3)
            let rw = rx1 - rx0, rh = ry1 - ry0
            let rluma = grid.meanLuma(x0: rx0 + rw / 3, x1: rx0 + 2 * rw / 3, y0: ry0 + rh / 3, y1: ry0 + 2 * rh / 3)
            samples.append(Sample(t: t, motion: diff, dy: dyAcc, dx: dxAcc, luma: luma,
                                  rmotion: rdiff, rdy: rdyAcc, rdx: rdxAcc, rluma: rluma))
            if samples.count % 50 == 0 {
                let n = samples.count
                Task { @MainActor in self.frameCount = n }
            }
        }
        prev = grid; prevRow = row; prevCol = col; prevRRow = rrow; prevRCol = rcol
    }

    /// Previewing: is someone sitting in front of the camera? A detection a
    /// second, judged over the last four so one missed frame does not
    /// flicker the outline, and kept so `arm` can fix the ROI from them.
    private func previewDetect(_ buffer: CVPixelBuffer, at raw: Double) {
        guard raw - lastPreviewDetectT >= Self.previewDetectEverySec else { return }
        lastPreviewDetectT = raw
        previewHits.append((t: raw, box: Self.detectPerson(in: buffer)))
        if previewHits.count > 12 { previewHits.removeFirst(previewHits.count - 12) }
        let now = Self.isFramed(previewHits.map { $0.box != nil })
        if now != framedOnQueue {
            framedOnQueue = now
            Task { @MainActor in self.framed = now }
        }
    }

    // MARK: Rules (pure, so they can be tested without a camera)

    /// Three hits in the last four detections. Fewer than four so far can
    /// still qualify (three straight hits), so the outline answers within
    /// three seconds of the sheet appearing.
    static func isFramed(_ hits: [Bool]) -> Bool {
        hits.suffix(framingWindow).filter { $0 }.count >= framingHits
    }

    /// The median box of a set of detections, flipped from Vision's
    /// bottom-left origin and padded 12 %, or nil below `minimum` boxes. The
    /// median is what makes one wild detection harmless.
    static func medianROI(_ boxes: [CGRect], minimum: Int) -> ROI? {
        guard boxes.count >= max(1, minimum) else { return nil }
        func med(_ v: [CGFloat]) -> Double { let s = v.sorted(); return Double(s[s.count / 2]) }
        let x = med(boxes.map(\.minX)), y = med(boxes.map(\.minY))
        let w = med(boxes.map(\.width)), h = med(boxes.map(\.height))
        return ROI(x: x, y: 1 - (y + h), w: w, h: h).padded(0.12)   // Vision is bottom-left
    }

    /// The largest upper body Vision finds, in its bottom-left normalized space.
    private static func detectPerson(in buffer: CVPixelBuffer) -> CGRect? {
        let req = VNDetectHumanRectanglesRequest()
        req.upperBodyOnly = true
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform([req])
        return req.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        })?.boundingBox
    }
}

extension CameraSignalRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        process(buffer, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}

// MARK: - The signal maths, identical to tools/camera_probe.swift

/// Block-averaged luma grid plus row/column mean profiles over a sub-rectangle.
struct LumaGrid {
    let w: Int, h: Int
    var px: [Double]

    static func downsample(_ buffer: CVPixelBuffer, targetMax: Int) -> LumaGrid? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        let w = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let h = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let factor = max(1, (max(w, h) + targetMax - 1) / targetMax)
        let gw = w / factor, gh = h / factor
        guard gw > 0, gh > 0 else { return nil }
        var px = [Double](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                var sum = 0
                for y in (gy * factor)..<((gy + 1) * factor) {
                    let rowBase = y * stride
                    for x in (gx * factor)..<((gx + 1) * factor) { sum += Int(bytes[rowBase + x]) }
                }
                px[gy * gw + gx] = Double(sum) / Double(factor * factor)
            }
        }
        return LumaGrid(w: gw, h: gh, px: px)
    }

    func rowProfile(x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> [Double] {
        let xa = max(0, x0), xb = min(w, x1 ?? w), ya = max(0, y0), yb = min(h, y1 ?? h)
        guard xb > xa, yb > ya else { return [] }
        return (ya..<yb).map { y in
            var s = 0.0
            for x in xa..<xb { s += px[y * w + x] }
            return s / Double(xb - xa)
        }
    }
    func colProfile(x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> [Double] {
        let xa = max(0, x0), xb = min(w, x1 ?? w), ya = max(0, y0), yb = min(h, y1 ?? h)
        guard xb > xa, yb > ya else { return [] }
        return (xa..<xb).map { x in
            var s = 0.0
            for y in ya..<yb { s += px[y * w + x] }
            return s / Double(yb - ya)
        }
    }
    func meanAbsDiff(_ o: LumaGrid, x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> Double {
        let xa = max(0, x0), xb = min(w, x1 ?? w), ya = max(0, y0), yb = min(h, y1 ?? h)
        guard xb > xa, yb > ya, o.px.count == px.count else { return 0 }
        var s = 0.0
        for y in ya..<yb { for x in xa..<xb { s += abs(px[y * w + x] - o.px[y * w + x]) } }
        return s / Double((xb - xa) * (yb - ya))
    }
    func meanLuma(x0: Int, x1: Int, y0: Int, y1: Int) -> Double {
        let xa = max(0, x0), xb = min(w, x1), ya = max(0, y0), yb = min(h, y1)
        guard xb > xa, yb > ya else { return 0 }
        var s = 0.0
        for y in ya..<yb { for x in xa..<xb { s += px[y * w + x] } }
        return s / Double((xb - xa) * (yb - ya))
    }

    /// 1-D optical-flow shift between two profiles: sum(diff·grad) / sum(grad²).
    /// Sub-pixel, and the margins are excluded so the static frame edge
    /// doesn't vote.
    static func profileShift(_ prev: [Double], _ cur: [Double]) -> Double {
        let n = min(prev.count, cur.count)
        guard n > 8 else { return 0 }
        let lo = n / 10, hi = n - n / 10
        var num = 0.0, den = 0.0
        for i in max(1, lo)..<min(n - 1, hi) {
            let g = (prev[i + 1] - prev[i - 1]) / 2
            num += (cur[i] - prev[i]) * g
            den += g * g
        }
        return den > 1e-9 ? num / den : 0
    }
}
#endif
