// camera_probe — offline prototype for camera-based session reading.
//
// Reads a propped-phone video of a meditation session and asks two questions:
//   1. Can we see stillness?  (frame-to-frame motion magnitude)
//   2. Can we see breathing?  (sub-pixel body shift oscillating at breath rate)
//
// No OpenCV, no Python deps: AVFoundation decodes, Vision finds the person,
// everything else is the same kind of windowed DFT scan SignalEngine uses, so
// whatever works here ports straight into the app.
//
// Build:  swiftc -O -o /tmp/camera_probe tools/camera_probe.swift
// Run:    /tmp/camera_probe <video.mov|signals.csv> [--fps 6] [--dump signals.csv]
//                           [--no-roi] [--table] [--grid 240]
//
// The decode is the slow part, so --dump writes the extracted per-frame signals
// to CSV; re-runs can then pass the CSV instead of the video and iterate on the
// analysis in seconds.
//
// ROI (default on for video input): a first, sparse pass runs Vision's human
// detector every few seconds and takes the MEDIAN box over the whole video, so
// one fixed torso rectangle is used for the entire extraction. A moving box
// would inject its own jitter into the sub-pixel shift signal, and a person
// meditating does not move enough to need tracking. Every signal is extracted
// twice, whole-frame and inside the box, so the CSV carries both and the
// analysis prints them side by side.

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import Vision

// MARK: - Extracted per-frame signals

struct FrameSample {
    let t: Double        // seconds from video start
    // Whole frame
    let motion: Double   // mean |luma diff| vs previous processed frame
    let dy: Double       // integrated vertical profile shift (downsampled px)
    let dx: Double       // integrated horizontal profile shift
    let luma: Double     // mean luma of the frame's central third
    // Inside the torso ROI (equal to the whole-frame values when no ROI)
    let rmotion: Double
    let rdy: Double
    let rdx: Double
    let rluma: Double
}

/// Normalized rectangle, origin TOP-left, in the raw (unrotated) buffer space.
struct ROI {
    var x: Double, y: Double, w: Double, h: Double
    /// Grown by `pad` of its own size on every side, clamped to the frame.
    func padded(_ pad: Double) -> ROI {
        let nx = max(0, x - w * pad), ny = max(0, y - h * pad)
        let nw = min(1 - nx, w * (1 + 2 * pad)), nh = min(1 - ny, h * (1 + 2 * pad))
        return ROI(x: nx, y: ny, w: nw, h: nh)
    }
}

// MARK: - Video extraction

/// Block-averaged luma grid plus row/column mean profiles over a sub-rectangle.
struct Grid {
    let w: Int, h: Int
    var px: [Double]

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
    /// Mean |difference| against another grid of the same shape, over a sub-rectangle.
    func meanAbsDiff(_ o: Grid, x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> Double {
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
}

func downsampleLuma(_ buffer: CVPixelBuffer, targetMax: Int) -> Grid? {
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
    var px = [Double](repeating: 0, count: gw * gh)
    for gy in 0..<gh {
        for gx in 0..<gw {
            var sum = 0
            for y in (gy * factor)..<((gy + 1) * factor) {
                let row = y * stride
                for x in (gx * factor)..<((gx + 1) * factor) { sum += Int(bytes[row + x]) }
            }
            px[gy * gw + gx] = Double(sum) / Double(factor * factor)
        }
    }
    return Grid(w: gw, h: gh, px: px)
}

/// 1-D optical-flow shift between two profiles: delta = sum(diff * grad) / sum(grad^2).
/// Precise for the tiny sub-pixel shifts breathing produces; margins excluded so
/// the frame edge (static background) doesn't vote.
func profileShift(_ prev: [Double], _ cur: [Double]) -> Double {
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

/// The raw buffers come out of the reader UNROTATED (sensor orientation); the
/// track's preferredTransform says how to turn them upright. Vision takes that
/// as an orientation hint and returns boxes in the raw buffer's space, which
/// is exactly the space the extraction grid lives in.
func orientation(for track: AVAssetTrack) -> CGImagePropertyOrientation {
    let t = track.preferredTransform
    if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
    if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
    if t.a == -1 && t.d == -1 { return .down }
    return .up
}

/// Sparse first pass: a human-rectangle detection every `everySec`, median
/// box over the video. Returns nil when the detector rarely finds anyone.
func detectTorsoBox(asset: AVURLAsset, track: AVAssetTrack, everySec: Double) -> ROI? {
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = false
    gen.maximumSize = CGSize(width: 720, height: 720)
    gen.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
    let orient = orientation(for: track)
    let dur = asset.duration.seconds

    var boxes: [CGRect] = []
    var attempts = 0
    var t = 2.0
    while t < dur - 2 {
        attempts += 1
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
            let req = VNDetectHumanRectanglesRequest()
            req.upperBodyOnly = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orient, options: [:])
            try? handler.perform([req])
            if let best = req.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) {
                boxes.append(best.boundingBox)
            }
        }
        t += everySec
    }
    FileHandle.standardError.write("  ROI: person found in \(boxes.count)/\(attempts) probes\n".data(using: .utf8)!)
    guard boxes.count >= 3, Double(boxes.count) / Double(max(1, attempts)) >= 0.3 else { return nil }

    func med(_ v: [CGFloat]) -> Double { let s = v.sorted(); return Double(s[s.count / 2]) }
    let x = med(boxes.map(\.minX)), y = med(boxes.map(\.minY))
    let w = med(boxes.map(\.width)), h = med(boxes.map(\.height))
    // Vision's origin is bottom-left; the grid's is top-left.
    return ROI(x: x, y: 1 - (y + h), w: w, h: h)
}

func extractSignals(url: URL, fps: Double, useROI: Bool, gridMax: Int) throws -> ([FrameSample], ROI?) {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw NSError(domain: "probe", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no video track"])
    }

    var roi: ROI? = nil
    if useROI {
        FileHandle.standardError.write("  pass 1: locating the person …\n".data(using: .utf8)!)
        roi = detectTorsoBox(asset: asset, track: track, everySec: 5)?.padded(0.12)
        if let r = roi {
            FileHandle.standardError.write(String(format: "  ROI (raw buffer, top-left origin): x %.3f y %.3f w %.3f h %.3f\n",
                                                  r.x, r.y, r.w, r.h).data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("  ROI: no stable person box; whole frame only\n".data(using: .utf8)!)
        }
    }

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.startReading()

    var samples: [FrameSample] = []
    var prev: Grid?
    var prevRow: [Double] = [], prevCol: [Double] = []
    var prevRRow: [Double] = [], prevRCol: [Double] = []
    var dyAcc = 0.0, dxAcc = 0.0, rdyAcc = 0.0, rdxAcc = 0.0
    var nextT = 0.0
    let step = 1.0 / fps

    while let sb = output.copyNextSampleBuffer() {
        let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        guard t >= nextT, let img = CMSampleBufferGetImageBuffer(sb) else { continue }
        nextT = t + step

        guard let grid = downsampleLuma(img, targetMax: gridMax) else { continue }
        let row = grid.rowProfile(), col = grid.colProfile()

        // ROI in grid cells (computed once the grid shape is known).
        var rx0 = 0, rx1 = grid.w, ry0 = 0, ry1 = grid.h
        if let r = roi {
            rx0 = Int(r.x * Double(grid.w)); rx1 = Int((r.x + r.w) * Double(grid.w))
            ry0 = Int(r.y * Double(grid.h)); ry1 = Int((r.y + r.h) * Double(grid.h))
        }
        let rrow = grid.rowProfile(x0: rx0, x1: rx1, y0: ry0, y1: ry1)
        let rcol = grid.colProfile(x0: rx0, x1: rx1, y0: ry0, y1: ry1)

        if let p = prev {
            let diff = grid.meanAbsDiff(p)
            let rdiff = grid.meanAbsDiff(p, x0: rx0, x1: rx1, y0: ry0, y1: ry1)
            dyAcc += profileShift(prevRow, row)
            dxAcc += profileShift(prevCol, col)
            rdyAcc += profileShift(prevRRow, rrow)
            rdxAcc += profileShift(prevRCol, rcol)

            // Central third mean luma: catches the chest moving toward the lens
            // as brightness change even when nothing translates. The ROI
            // version takes the middle third of the box.
            let luma = grid.meanLuma(x0: grid.w / 3, x1: 2 * grid.w / 3, y0: grid.h / 3, y1: 2 * grid.h / 3)
            let rw = rx1 - rx0, rh = ry1 - ry0
            let rluma = grid.meanLuma(x0: rx0 + rw / 3, x1: rx0 + 2 * rw / 3,
                                      y0: ry0 + rh / 3, y1: ry0 + 2 * rh / 3)
            samples.append(FrameSample(t: t, motion: diff, dy: dyAcc, dx: dxAcc, luma: luma,
                                       rmotion: rdiff, rdy: rdyAcc, rdx: rdxAcc, rluma: rluma))
        }
        prev = grid; prevRow = row; prevCol = col; prevRRow = rrow; prevRCol = rcol

        if samples.count % 300 == 0 && !samples.isEmpty {
            FileHandle.standardError.write("  … \(Int(t))s\n".data(using: .utf8)!)
        }
    }
    if reader.status == .failed {
        throw reader.error ?? NSError(domain: "probe", code: 2)
    }
    return (samples, roi)
}

// MARK: - CSV in/out

func dumpCSV(_ samples: [FrameSample], roi: ROI?, to path: String) throws {
    var out = ""
    if let r = roi {
        out += String(format: "# roi x=%.4f y=%.4f w=%.4f h=%.4f\n", r.x, r.y, r.w, r.h)
    }
    out += "t,motion,dy,dx,luma,rmotion,rdy,rdx,rluma\n"
    for s in samples {
        out += String(format: "%.3f,%.5f,%.5f,%.5f,%.3f,%.5f,%.5f,%.5f,%.3f\n",
                      s.t, s.motion, s.dy, s.dx, s.luma, s.rmotion, s.rdy, s.rdx, s.rluma)
    }
    try out.write(toFile: path, atomically: true, encoding: .utf8)
}

/// Accepts both the old 5-column CSV (ROI fields mirror whole-frame) and the
/// new 9-column one. Returns whether ROI columns were really present.
func loadCSV(_ path: String) throws -> ([FrameSample], Bool) {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var hasROI = false
    let samples: [FrameSample] = text.split(separator: "\n").compactMap { line in
        if line.hasPrefix("#") || line.hasPrefix("t,") { return nil }
        let f = line.split(separator: ",").compactMap { Double($0) }
        if f.count == 9 {
            hasROI = true
            return FrameSample(t: f[0], motion: f[1], dy: f[2], dx: f[3], luma: f[4],
                               rmotion: f[5], rdy: f[6], rdx: f[7], rluma: f[8])
        }
        guard f.count == 5 else { return nil }
        return FrameSample(t: f[0], motion: f[1], dy: f[2], dx: f[3], luma: f[4],
                           rmotion: f[1], rdy: f[2], rdx: f[3], rluma: f[4])
    }
    return (samples, hasROI)
}

// MARK: - Windowed spectral analysis

struct WindowRead {
    let t: Double            // window center
    let rate: Double         // breaths/min at the peak
    let clarity: Double      // peak power / band power
    let amplitude: Double    // rms of the band-passed window
    /// Top local maxima of the scan, clearest first, for the tracker.
    let peaks: [(rate: Double, clarity: Double)]
}

/// Subtract a centered moving average — the same cheap high-pass the wrist
/// engine uses. Postural/lighting drift lives below the breathing band and
/// otherwise owns every spectrum.
func highpass(_ x: [Double], samplesPerSec: Double, seconds: Double = 15) -> [Double] {
    let half = max(1, Int(seconds * samplesPerSec / 2))
    var out = [Double](repeating: 0, count: x.count)
    for i in 0..<x.count {
        let lo = max(0, i - half), hi = min(x.count - 1, i + half)
        var sum = 0.0
        for j in lo...hi { sum += x[j] }
        out[i] = x[i] - sum / Double(hi - lo + 1)
    }
    return out
}

/// Per-window DFT scan over one signal, SignalEngine-style: detrend, scan a
/// band of fractional rates, clarity = concentration at the winning peak.
/// A peak sitting on the low band edge is drift leakage, not a read; its
/// clarity is zeroed so it can never win.
func analyze(signal raw: [Double], times: [Double],
             windowSec: Double = 30, hopSec: Double = 5,
             loRate: Double = 3.5, hiRate: Double = 20.0) -> [WindowRead] {
    guard times.count > 4 else { return [] }
    let duration = times.last! - times.first!
    let dt = duration / Double(times.count - 1)
    let sr = 1.0 / dt
    let signal = highpass(raw, samplesPerSec: sr)
    let wn = Int(windowSec * sr), hop = Int(hopSec * sr)
    guard wn > 8, signal.count >= wn else { return [] }

    var reads: [WindowRead] = []
    var start = 0
    while start + wn <= signal.count {
        let seg = Array(signal[start..<start + wn])

        // Least-squares line out, so slow drift doesn't own the spectrum.
        let n = Double(wn)
        let xs = (0..<wn).map(Double.init)
        let mx = xs.reduce(0, +) / n, my = seg.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in 0..<wn { sxy += (xs[i] - mx) * (seg[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
        let slope = sxx > 0 ? sxy / sxx : 0
        let det = (0..<wn).map { seg[$0] - my - slope * (xs[$0] - mx) }

        func power(_ rate: Double) -> Double {
            let f = rate / 60.0
            var re = 0.0, im = 0.0
            for i in 0..<wn {
                let ph = 2 * Double.pi * f * Double(i) * dt
                re += det[i] * cos(ph); im += det[i] * sin(ph)
            }
            return re * re + im * im
        }

        // Fine scan finds the peak; the clarity denominator sums INDEPENDENT
        // bins (spacing 60/windowSec per min), otherwise the overlapping scan
        // points count the same power many times over and dilute every peak.
        var scanRates: [Double] = [], scanPow: [Double] = []
        var rate = loRate
        while rate <= hiRate { scanRates.append(rate); scanPow.append(power(rate)); rate += 0.1 }
        var total = 0.0
        let binStep = 60.0 / windowSec
        var bin = loRate
        while bin <= hiRate { total += power(bin); bin += binStep }
        let rms = (det.reduce(0) { $0 + $1 * $1 } / n).squareRoot()

        // Every local maximum is a candidate; a peak ON the low edge is drift
        // leakage and gets clarity 0. Keep the top few by power.
        var maxima: [(rate: Double, clarity: Double)] = []
        for k in scanRates.indices {
            let p = scanPow[k]
            let left = k == 0 ? -1.0 : scanPow[k - 1]
            let right = k == scanRates.count - 1 ? -1.0 : scanPow[k + 1]
            guard p > left && p >= right else { continue }
            let edge = scanRates[k] <= loRate + 0.15
            maxima.append((scanRates[k], edge ? 0 : (total > 0 ? p / total : 0)))
        }
        maxima.sort { $0.clarity > $1.clarity }
        let peaks = Array(maxima.prefix(trackPeaks))
        let best = peaks.first ?? (rate: loRate, clarity: 0)
        reads.append(WindowRead(t: times[start] + windowSec / 2,
                                rate: best.rate, clarity: best.clarity,
                                amplitude: rms, peaks: peaks))
        start += hop
    }
    return reads
}

// MARK: - Continuity tracking (ported from SignalEngine.trackRates)
//
// The true rate is the clearest peak in about half of windows and the second
// or third in most of the rest. Windows advance 5 s and span 30 s, so a real
// rhythm is nearly forced to repeat and a spurious peak is not; reading each
// window alone spends none of that redundancy. Candidates are POOLED across
// the camera's channels, so the path may switch from dy to luma to dx for
// free: they are three views of the same chest, not three hypotheses.

let trackJumpCost = 0.45   // score paid per breath/min of jump between windows
let trackPeaks = 3         // candidates kept per channel per window
let trackFloor = 0.10      // clarity below which a peak gets no state
let candidateMerge = 0.35  // breaths/min; closer than this is one peak twice

func trackRates(_ windows: [[(rate: Double, clarity: Double)]]) -> (rates: [Double], clarity: [Double]) {
    var dp: [[Double]] = [], back: [[(Int, Int)?]] = []
    for (i, cands) in windows.enumerated() {
        guard !cands.isEmpty else { dp.append([]); back.append([]); continue }
        let prev = (0..<i).reversed().first { !dp[$0].isEmpty }
        var row: [Double] = [], ptr: [(Int, Int)?] = []
        for c in cands {
            guard let p = prev else { row.append(c.clarity); ptr.append(nil); continue }
            var best = -Double.greatestFiniteMagnitude, arg = 0
            for (k, q) in windows[p].enumerated() {
                let v = dp[p][k] - trackJumpCost * abs(c.rate - q.rate)
                if v > best { best = v; arg = k }
            }
            row.append(c.clarity + best)
            ptr.append((p, arg))
        }
        dp.append(row); back.append(ptr)
    }
    var rates = [Double](repeating: 0, count: windows.count)
    var clar = [Double](repeating: 0, count: windows.count)
    guard let last = dp.indices.reversed().first(where: { !dp[$0].isEmpty }) else { return (rates, clar) }
    var i = last
    var j = dp[last].indices.max(by: { dp[last][$0] < dp[last][$1] }) ?? 0
    while true {
        rates[i] = windows[i][j].rate
        clar[i] = windows[i][j].clarity
        guard let step = back[i][j] else { break }
        (i, j) = step
    }
    return (rates, clar)
}

/// Pool one window's candidates from every channel: drop the floor, merge
/// near-duplicates keeping the clearer one.
func pool(_ reads: [WindowRead]) -> [(rate: Double, clarity: Double)] {
    var all = reads.flatMap { $0.peaks }.filter { $0.clarity >= trackFloor }
    all.sort { $0.clarity > $1.clarity }
    var out: [(rate: Double, clarity: Double)] = []
    for c in all where !out.contains(where: { abs($0.rate - c.rate) < candidateMerge }) { out.append(c) }
    return out
}

// MARK: - Reporting

struct ChannelSet {
    let name: String
    let channels: [(String, [Double])]
    let motion: [Double]
}

/// Runs every channel, picks the per-window winner by clarity, prints the
/// summary and (optionally) the full table. Returns the winner rates for
/// windows that cleared the bar, so sets can be compared.
@discardableResult
func report(_ set: ChannelSet, times: [Double], table: Bool) -> (clear: Int, total: Int, median: Double?) {
    var perChannel: [String: [WindowRead]] = [:]
    for (name, sig) in set.channels { perChannel[name] = analyze(signal: sig, times: times) }
    let count = perChannel.values.map(\.count).min() ?? 0
    let names = set.channels.map(\.0)

    // Track first, so the table can show it beside the per-window winner.
    var pooled: [[(rate: Double, clarity: Double)]] = []
    for w in 0..<count { pooled.append(pool(names.map { perChannel[$0]![w] })) }
    let tracked = trackRates(pooled)

    if table {
        print("\n== [\(set.name)] Breathing candidates (rate/min @ clarity), 30 s windows, 5 s hop")
        print("   t(min)   " + names.map { String(format: "%12@", $0 as NSString) }.joined() + "   winner        tracked")
    }
    var winnerRates: [Double] = []
    var trackedRates: [Double] = []
    for w in 0..<count {
        var line = String(format: "  %6.1f   ", perChannel[names[0]]![w].t / 60)
        var best: (String, WindowRead)? = nil
        for name in names {
            let r = perChannel[name]![w]
            line += String(format: "  %5.1f@%.2f", r.rate, r.clarity)
            if best == nil || r.clarity > best!.1.clarity { best = (name, r) }
        }
        if let b = best {
            line += String(format: "   %@ %5.1f@%.2f", b.0, b.1.rate, b.1.clarity)
            if b.1.clarity >= 0.30 { winnerRates.append(b.1.rate) }
        }
        let tr = tracked.rates[w], tc = tracked.clarity[w]
        line += String(format: "   %5.1f@%.2f", tr, tc)
        if tc >= 0.30 { trackedRates.append(tr) }
        if table { print(line) }
    }

    // The tracked curve at one-minute resolution, to eyeball against the
    // Watch's graph. Median of the windows centred in each minute.
    var perMinute: [Int: [Double]] = [:]
    for w in 0..<count where tracked.clarity[w] >= 0.30 {
        perMinute[Int(perChannel[names[0]]![w].t / 60), default: []].append(tracked.rates[w])
    }
    let minutes = perMinute.keys.sorted()
    let curve = minutes.map { m -> String in
        let v = perMinute[m]!.sorted(); return String(format: "%d:%.1f", m, v[v.count / 2])
    }
    print("== [\(set.name)] tracked, per minute (min:rate): " + curve.joined(separator: "  "))
    if !trackedRates.isEmpty {
        let ts = trackedRates.sorted()
        let jumps = zip(tracked.rates, tracked.rates.dropFirst()).map { abs($0 - $1) }
        let meanJump = jumps.isEmpty ? 0 : jumps.reduce(0, +) / Double(jumps.count)
        print(String(format: "== [%@] tracked: %d/%d readable (clarity ≥ 0.30), median %.1f/min, mean step %.2f/min",
                     set.name as NSString, trackedRates.count, count, ts[ts.count / 2], meanJump))
    }

    if winnerRates.isEmpty {
        print("== [\(set.name)] no window reached clarity 0.30 (\(count) windows)")
        return (0, count, nil)
    }
    let sorted = winnerRates.sorted()
    let median = sorted[sorted.count / 2]
    print(String(format: "== [%@] %d/%d windows clear (clarity ≥ 0.30), median winner rate %.1f/min",
                 set.name as NSString, winnerRates.count, count, median))
    return (winnerRates.count, count, median)
}

func printStillness(_ set: ChannelSet, times: [Double]) {
    let motion = set.motion
    let dt = (times.last! - times.first!) / Double(times.count - 1)
    let wn30 = Int(30.0 / dt)
    guard wn30 > 0 else { return }
    // Session floor = 10th percentile of 5 s means, so the bars read RELATIVE
    // to this setup's own noise floor rather than in absolute luma units, which
    // differ 2–3× between a 4K phone at 2 m and a 1080p phone at 0.5 m.
    let wn5 = max(1, Int(5.0 / dt))
    var fives: [Double] = []
    var s = 0
    while s + wn5 <= motion.count { fives.append(motion[s..<s + wn5].reduce(0, +) / Double(wn5)); s += wn5 }
    let floor = fives.sorted()[fives.count / 10]
    print(String(format: "\n== [%@] Stillness (mean |frame diff| per 30 s; floor %.4f = 10th pct of 5 s means)",
                 set.name as NSString, floor))
    var mStart = 0
    while mStart + wn30 <= motion.count {
        let seg = motion[mStart..<mStart + wn30]
        let mean = seg.reduce(0, +) / Double(seg.count)
        let center = times[mStart] + 15
        let ratio = floor > 0 ? mean / floor : 0
        print(String(format: "  %5.1f min  motion %.4f  x%4.1f %@", center / 60, mean, ratio,
                     String(repeating: "▇", count: min(40, Int(ratio * 4)))))
        mStart += wn30 * 2  // every other window; the CSV has everything
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: camera_probe <video.mov|signals.csv> [--fps 6] [--dump out.csv] [--no-roi] [--table] [--grid 240]")
    exit(1)
}
let input = args[1]
var fps = 6.0
var dumpPath: String?
var useROI = true
var table = false
var gridMax = 240
var i = 2
while i < args.count {
    switch args[i] {
    case "--fps" where i + 1 < args.count: fps = Double(args[i + 1]) ?? 6.0; i += 2
    case "--dump" where i + 1 < args.count: dumpPath = args[i + 1]; i += 2
    case "--no-roi": useROI = false; i += 1
    case "--table": table = true; i += 1
    case "--grid" where i + 1 < args.count: gridMax = Int(args[i + 1]) ?? 240; i += 2
    default: i += 1
    }
}

let samples: [FrameSample]
var hasROI = false
if input.lowercased().hasSuffix(".csv") {
    (samples, hasROI) = try loadCSV(input)
    print("loaded \(samples.count) samples from CSV\(hasROI ? " (with ROI columns)" : "")")
} else {
    print("decoding \(input) at ~\(fps) fps, grid \(gridMax) …")
    let t0 = Date()
    let (s, roi) = try extractSignals(url: URL(fileURLWithPath: input), fps: fps, useROI: useROI, gridMax: gridMax)
    samples = s
    hasROI = roi != nil
    print("decoded \(samples.count) samples in \(Int(-t0.timeIntervalSinceNow))s")
    if let path = dumpPath {
        try dumpCSV(samples, roi: roi, to: path)
        print("signals → \(path)")
    }
}

guard samples.count > 60 else { print("not enough samples"); exit(1) }

let times = samples.map(\.t)
let whole = ChannelSet(name: "whole frame",
                       channels: [("dy", samples.map(\.dy)), ("dx", samples.map(\.dx)), ("luma", samples.map(\.luma))],
                       motion: samples.map(\.motion))
printStillness(whole, times: times)
let w = report(whole, times: times, table: table)

if hasROI {
    let roiSet = ChannelSet(name: "torso ROI",
                            channels: [("dy", samples.map(\.rdy)), ("dx", samples.map(\.rdx)), ("luma", samples.map(\.rluma))],
                            motion: samples.map(\.rmotion))
    printStillness(roiSet, times: times)
    let r = report(roiSet, times: times, table: table)
    if let wm = w.median, let rm = r.median {
        print(String(format: "\n== ROI vs whole: clear %d→%d of %d, median %.1f→%.1f/min",
                     w.clear, r.clear, w.total, wm, rm))
    }
}
