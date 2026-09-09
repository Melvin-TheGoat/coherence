// camera_probe — offline prototype for camera-based session reading.
//
// Reads a propped-phone video of a meditation session and asks two questions:
//   1. Can we see stillness?  (global frame-to-frame motion magnitude)
//   2. Can we see breathing?  (sub-pixel body shift oscillating at breath rate)
//
// No OpenCV, no Python deps: AVFoundation decodes, everything else is the same
// kind of windowed DFT scan SignalEngine uses, so whatever works here ports
// straight into the app.
//
// Build:  swiftc -O -o /tmp/camera_probe tools/camera_probe.swift
// Run:    /tmp/camera_probe <video.mov|signals.csv> [--fps 6] [--dump signals.csv]
//
// The decode is the slow part, so --dump writes the extracted per-frame signals
// to CSV; re-runs can then pass the CSV instead of the video and iterate on the
// analysis in seconds.

import Foundation
import AVFoundation
import CoreVideo

// MARK: - Extracted per-frame signals

struct FrameSample {
    let t: Double        // seconds from video start
    let motion: Double   // mean |luma diff| vs previous processed frame
    let dy: Double       // integrated vertical profile shift (downsampled px)
    let dx: Double       // integrated horizontal profile shift
    let luma: Double     // mean luma of the frame's central third
}

// MARK: - Video extraction

/// Block-averaged luma grid plus its row/column mean profiles.
struct Grid {
    let w: Int, h: Int
    var px: [Double]
    var rowProfile: [Double] { (0..<h).map { y in (0..<w).reduce(0.0) { $0 + px[y * w + $1] } / Double(w) } }
    var colProfile: [Double] { (0..<w).map { x in (0..<h).reduce(0.0) { $0 + px[$1 * w + x] } / Double(h) } }
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
    let n = prev.count
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

func extractSignals(url: URL, fps: Double) throws -> [FrameSample] {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw NSError(domain: "probe", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no video track"])
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
    var dyAcc = 0.0, dxAcc = 0.0
    var nextT = 0.0
    let step = 1.0 / fps
    var decoded = 0

    while let sb = output.copyNextSampleBuffer() {
        decoded += 1
        let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        guard t >= nextT, let img = CMSampleBufferGetImageBuffer(sb) else { continue }
        nextT = t + step

        guard let grid = downsampleLuma(img, targetMax: 240) else { continue }
        let row = grid.rowProfile, col = grid.colProfile

        if let p = prev {
            var diff = 0.0
            for i in 0..<min(p.px.count, grid.px.count) { diff += abs(grid.px[i] - p.px[i]) }
            diff /= Double(grid.px.count)
            dyAcc += profileShift(prevRow, row)
            dxAcc += profileShift(prevCol, col)

            // Central third mean luma: catches the chest moving toward the lens
            // as brightness change even when nothing translates.
            var lsum = 0.0; var lcount = 0
            for y in grid.h / 3..<(2 * grid.h / 3) {
                for x in grid.w / 3..<(2 * grid.w / 3) { lsum += grid.px[y * grid.w + x]; lcount += 1 }
            }
            samples.append(FrameSample(t: t, motion: diff, dy: dyAcc, dx: dxAcc,
                                       luma: lsum / Double(max(1, lcount))))
        }
        prev = grid; prevRow = row; prevCol = col

        if samples.count % 300 == 0 && !samples.isEmpty {
            FileHandle.standardError.write("  … \(Int(t))s\n".data(using: .utf8)!)
        }
    }
    if reader.status == .failed {
        throw reader.error ?? NSError(domain: "probe", code: 2)
    }
    return samples
}

// MARK: - CSV in/out

func dumpCSV(_ samples: [FrameSample], to path: String) throws {
    var out = "t,motion,dy,dx,luma\n"
    for s in samples {
        out += String(format: "%.3f,%.5f,%.5f,%.5f,%.3f\n", s.t, s.motion, s.dy, s.dx, s.luma)
    }
    try out.write(toFile: path, atomically: true, encoding: .utf8)
}

func loadCSV(_ path: String) throws -> [FrameSample] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(separator: "\n").dropFirst().compactMap { line in
        let f = line.split(separator: ",").compactMap { Double($0) }
        guard f.count == 5 else { return nil }
        return FrameSample(t: f[0], motion: f[1], dy: f[2], dx: f[3], luma: f[4])
    }
}

// MARK: - Windowed spectral analysis

struct WindowRead {
    let t: Double            // window center
    let rate: Double         // breaths/min at the peak
    let clarity: Double      // peak power / band power
    let amplitude: Double    // rms of the band-passed window
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
        var bestRate = 0.0, bestPow = 0.0
        var rate = loRate
        while rate <= hiRate {
            let p = power(rate)
            if p > bestPow { bestPow = p; bestRate = rate }
            rate += 0.1
        }
        var total = 0.0
        let binStep = 60.0 / windowSec
        var bin = loRate
        while bin <= hiRate { total += power(bin); bin += binStep }
        let rms = (det.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
        let edgePeak = bestRate <= loRate + 0.15
        reads.append(WindowRead(t: times[start] + windowSec / 2,
                                rate: bestRate,
                                clarity: edgePeak ? 0 : (total > 0 ? bestPow / total : 0),
                                amplitude: rms))
        start += hop
    }
    return reads
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: camera_probe <video.mov|signals.csv> [--fps 6] [--dump out.csv]")
    exit(1)
}
let input = args[1]
var fps = 6.0
var dumpPath: String?
var i = 2
while i < args.count {
    switch args[i] {
    case "--fps" where i + 1 < args.count: fps = Double(args[i + 1]) ?? 6.0; i += 2
    case "--dump" where i + 1 < args.count: dumpPath = args[i + 1]; i += 2
    default: i += 1
    }
}

let samples: [FrameSample]
if input.lowercased().hasSuffix(".csv") {
    samples = try loadCSV(input)
    print("loaded \(samples.count) samples from CSV")
} else {
    print("decoding \(input) at ~\(fps) fps …")
    let t0 = Date()
    samples = try extractSignals(url: URL(fileURLWithPath: input), fps: fps)
    print("decoded \(samples.count) samples in \(Int(-t0.timeIntervalSinceNow))s")
    if let path = dumpPath {
        try dumpCSV(samples, to: path)
        print("signals → \(path)")
    }
}

guard samples.count > 60 else { print("not enough samples"); exit(1) }

let times = samples.map(\.t)
let channels: [(String, [Double])] = [
    ("dy",   samples.map(\.dy)),
    ("dx",   samples.map(\.dx)),
    ("luma", samples.map(\.luma)),
]

// Stillness first: the motion curve, summarized per 30 s.
let motion = samples.map(\.motion)
let motionReads = analyze(signal: motion, times: times)  // reuses the windower for centers
print("\n== Stillness (mean |frame diff| per 30 s window; lower = stiller)")
let wn30 = Int(30.0 / ((times.last! - times.first!) / Double(times.count - 1)))
var mStart = 0, mIdx = 0
while mStart + wn30 <= motion.count {
    let seg = motion[mStart..<mStart + wn30]
    let mean = seg.reduce(0, +) / Double(seg.count)
    let center = times[mStart] + 15
    print(String(format: "  %5.1f min  motion %.4f %@", center / 60, mean,
                 String(repeating: "▇", count: min(40, Int(mean * 400)))))
    mStart += wn30 * 2  // print every other window; the CSV has everything
    mIdx += 1
}
_ = motionReads

// Breathing: every channel, every window; then the per-window winner.
print("\n== Breathing candidates (rate/min @ clarity), 30 s windows, 5 s hop")
var perChannel: [String: [WindowRead]] = [:]
for (name, sig) in channels { perChannel[name] = analyze(signal: sig, times: times) }

let count = perChannel.values.map(\.count).min() ?? 0
print("   t(min)   " + channels.map { String(format: "%12@", $0.0 as NSString) }.joined() + "   winner")
var winnerRates: [Double] = []
for w in 0..<count {
    var line = String(format: "  %6.1f   ", perChannel["dy"]![w].t / 60)
    var best: (String, WindowRead)? = nil
    for (name, _) in channels {
        let r = perChannel[name]![w]
        line += String(format: "  %5.1f@%.2f", r.rate, r.clarity)
        if best == nil || r.clarity > best!.1.clarity { best = (name, r) }
    }
    if let b = best {
        line += String(format: "   %@ %5.1f@%.2f", b.0, b.1.rate, b.1.clarity)
        if b.1.clarity >= 0.30 { winnerRates.append(b.1.rate) }
    }
    print(line)
}

if !winnerRates.isEmpty {
    let sorted = winnerRates.sorted()
    let median = sorted[sorted.count / 2]
    print(String(format: "\n== Summary: %d/%d windows clear (clarity ≥ 0.30), median winner rate %.1f/min",
                 winnerRates.count, count, median))
} else {
    print("\n== Summary: no window reached clarity 0.30")
}
