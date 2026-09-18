// camera_expand — offline probe: does the body's OUTLINE breathe where the
// luma-grid SHIFT signal does not?
//
// The shipped recorder asks "did the torso box slide?" (nine numbers a frame
// from a 240-px brightness grid). Quiet breathing does not slide anything; the
// chest gets a little wider. This tool asks the question a person watching the
// video asks: how wide is the body at chest height and at belly height, and
// how high do the shoulders sit, frame by frame.
//
//   swiftc -O -o /tmp/camera_expand tools/camera_expand.swift
//   /tmp/camera_expand video.mov --out signals.csv [--fps 10] [--quality balanced|accurate|fast]
//
// Per decimated frame, Vision's person segmentation gives a SOFT mask (0..1
// per pixel). From it, in upright space:
//   wupper, wchest, wbelly  soft body width (sum of mask along a row, mean over
//                           a band of rows) in three bands below the shoulder
//                           line. Width is immune to sway: both edges move the
//                           same way and cancel; a breath moves them apart.
//   shoulder                mean sub-pixel top edge of the mask over the
//                           shoulder columns, negated so a rising shoulder is
//                           a rising number.
//   area                    mask sum from the shoulder line down.
// The bands are fixed ONCE from the median profile over the whole video (same
// reason the probe fixes its ROI: a band that follows the body injects its own
// jitter). The old nine columns are computed too, so one CSV carries both the
// shift signals and the expansion signals and camera_lab.py can race them.
//
// Output header lines carry the band rows so a run is reproducible, and the
// columns are: t,motion,dy,dx,luma,rmotion,rdy,rdx,rluma,wupper,wchest,wbelly,shoulder,area

import AVFoundation
import Vision
import CoreImage

// MARK: - Luma grid (the probe's shift signals, kept for the A/B)

struct Grid {
    let w: Int, h: Int
    var px: [Double]
    func rowProfile(x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> [Double] {
        let xa = max(0, x0), xb = min(w, x1 ?? w), ya = max(0, y0), yb = min(h, y1 ?? h)
        guard xb > xa, yb > ya else { return [] }
        return (ya..<yb).map { y in var s = 0.0; for x in xa..<xb { s += px[y * w + x] }; return s / Double(xb - xa) }
    }
    func colProfile(x0: Int = 0, x1: Int? = nil, y0: Int = 0, y1: Int? = nil) -> [Double] {
        let xa = max(0, x0), xb = min(w, x1 ?? w), ya = max(0, y0), yb = min(h, y1 ?? h)
        guard xb > xa, yb > ya else { return [] }
        return (xa..<xb).map { x in var s = 0.0; for y in ya..<yb { s += px[y * w + x] }; return s / Double(yb - ya) }
    }
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
    guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer) else { return nil }
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

func orientation(for track: AVAssetTrack) -> CGImagePropertyOrientation {
    let t = track.preferredTransform
    if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
    if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
    if t.a == -1 && t.d == -1 { return .down }
    return .up
}

// MARK: - Person mask, upright

struct Mask {
    let w: Int, h: Int
    var v: [Float]   // row-major, 0..1
}

/// Reads a one-component float mask out of Vision's pixel buffer and turns it
/// upright. Vision returns the mask in the RAW buffer's space (it honours the
/// orientation hint for detection, not for output), so a portrait phone video
/// stored as landscape-with-a-rotation comes back landscape and is rotated
/// here. The dims check guards the other possibility.
func uprightMask(_ pb: CVPixelBuffer, raw: (w: Int, h: Int), orient: CGImagePropertyOrientation) -> Mask? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let mw = CVPixelBufferGetWidth(pb), mh = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
    let fmt = CVPixelBufferGetPixelFormatType(pb)
    var m = [Float](repeating: 0, count: mw * mh)
    if fmt == kCVPixelFormatType_OneComponent32Float {
        for y in 0..<mh {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<mw { m[y * mw + x] = row[x] }
        }
    } else {
        for y in 0..<mh {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<mw { m[y * mw + x] = Float(row[x]) / 255 }
        }
    }
    // Is the mask in raw space (same aspect as the raw buffer) or already upright?
    let rawAspect = Double(raw.w) / Double(raw.h), maskAspect = Double(mw) / Double(mh)
    let inRawSpace = abs(rawAspect - maskAspect) < abs(1 / rawAspect - maskAspect)
    let rot: CGImagePropertyOrientation = inRawSpace ? orient : .up
    switch rot {
    case .right:  // raw row 0 is the RIGHT side of upright; raw col 0 is the TOP
        var u = [Float](repeating: 0, count: mw * mh)
        let uw = mh, uh = mw
        for Y in 0..<uh { for X in 0..<uw { u[Y * uw + X] = m[(mh - 1 - X) * mw + Y] } }
        return Mask(w: uw, h: uh, v: u)
    case .left:   // raw row 0 is the LEFT side; raw col 0 is the BOTTOM
        var u = [Float](repeating: 0, count: mw * mh)
        let uw = mh, uh = mw
        for Y in 0..<uh { for X in 0..<uw { u[Y * uw + X] = m[X * mw + (mw - 1 - Y)] } }
        return Mask(w: uw, h: uh, v: u)
    case .down:
        var u = [Float](repeating: 0, count: mw * mh)
        for Y in 0..<mh { for X in 0..<mw { u[Y * mw + X] = m[(mh - 1 - Y) * mw + (mw - 1 - X)] } }
        return Mask(w: mw, h: mh, v: u)
    default:
        return Mask(w: mw, h: mh, v: m)
    }
}

/// Per-row soft width (sum of mask along the row) and per-column sub-pixel
/// top edge (first 0.5 crossing, interpolated; NaN when the column has no body).
func profiles(_ m: Mask) -> (rowWidth: [Double], colTop: [Double]) {
    var rw = [Double](repeating: 0, count: m.h)
    for y in 0..<m.h { var s: Float = 0; for x in 0..<m.w { s += m.v[y * m.w + x] }; rw[y] = Double(s) }
    var ct = [Double](repeating: .nan, count: m.w)
    for x in 0..<m.w {
        var prev: Float = 0
        for y in 0..<m.h {
            let cur = m.v[y * m.w + x]
            if cur >= 0.5 {
                let f = (0.5 - prev) / max(1e-6, cur - prev)   // fraction into this row
                ct[x] = y == 0 ? 0 : Double(y - 1) + Double(f)
                break
            }
            prev = cur
        }
    }
    return (rw, ct)
}

// MARK: - Extraction

struct Frame {
    let t: Double
    let motion: Double, dy: Double, dx: Double, luma: Double
    let rmotion: Double, rdy: Double, rdx: Double, rluma: Double
    let rowWidth: [Double], colTop: [Double]
}

func median(_ a: [Double]) -> Double {
    let s = a.filter { !$0.isNaN }.sorted()
    return s.isEmpty ? .nan : s[s.count / 2]
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: camera_expand <video> --out signals.csv [--fps 10] [--quality balanced|accurate|fast] [--grid 240]")
    exit(1)
}
var fps = 10.0, outPath = "expand.csv", gridMax = 240
var quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced
var i = 2
while i < args.count {
    switch args[i] {
    case "--fps" where i + 1 < args.count: fps = Double(args[i + 1]) ?? 10; i += 2
    case "--out" where i + 1 < args.count: outPath = args[i + 1]; i += 2
    case "--grid" where i + 1 < args.count: gridMax = Int(args[i + 1]) ?? 240; i += 2
    case "--quality" where i + 1 < args.count:
        quality = args[i + 1] == "accurate" ? .accurate : args[i + 1] == "fast" ? .fast : .balanced; i += 2
    default: i += 1
    }
}

let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
guard let track = asset.tracks(withMediaType: .video).first else { print("no video track"); exit(1) }
let orient = orientation(for: track)
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()

let t0 = Date()
var frames: [Frame] = []
var prev: Grid?
var prevRow: [Double] = [], prevCol: [Double] = []
var dyAcc = 0.0, dxAcc = 0.0
var nextT = 0.0
let step = 1.0 / fps
var maskDims = (0, 0), rawDims = (0, 0)
var missed = 0

while let sb = output.copyNextSampleBuffer() {
    let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    guard t >= nextT, let img = CMSampleBufferGetImageBuffer(sb) else { continue }
    nextT = t + step
    rawDims = (CVPixelBufferGetWidth(img), CVPixelBufferGetHeight(img))

    let req = VNGeneratePersonSegmentationRequest()
    req.qualityLevel = quality
    req.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
    let handler = VNImageRequestHandler(cvPixelBuffer: img, orientation: orient, options: [:])
    try? handler.perform([req])
    guard let pb = req.results?.first?.pixelBuffer,
          let mask = uprightMask(pb, raw: rawDims, orient: orient) else { missed += 1; continue }
    if maskDims == (0, 0) {
        maskDims = (mask.w, mask.h)
        FileHandle.standardError.write("  raw \(rawDims.0)x\(rawDims.1) orient \(orient.rawValue), mask upright \(mask.w)x\(mask.h)\n".data(using: .utf8)!)
    }
    let (rw, ct) = profiles(mask)

    guard let grid = downsampleLuma(img, targetMax: gridMax) else { continue }
    let row = grid.rowProfile(), col = grid.colProfile()
    var motion = 0.0
    if let p = prev {
        motion = grid.meanAbsDiff(p)
        dyAcc += profileShift(prevRow, row)
        dxAcc += profileShift(prevCol, col)
    }
    let luma = grid.meanLuma(x0: grid.w / 3, x1: 2 * grid.w / 3, y0: grid.h / 3, y1: 2 * grid.h / 3)
    prev = grid; prevRow = row; prevCol = col
    // ROI versions are filled after the bands are known (they need the mask's
    // body box); placeholders here keep the struct simple.
    frames.append(Frame(t: t, motion: motion, dy: dyAcc, dx: dxAcc, luma: luma,
                        rmotion: motion, rdy: dyAcc, rdx: dxAcc, rluma: luma,
                        rowWidth: rw, colTop: ct))
    if frames.count % 600 == 0 {
        FileHandle.standardError.write("  … \(Int(t))s (\(Int(-t0.timeIntervalSinceNow))s elapsed)\n".data(using: .utf8)!)
    }
}
if reader.status == .failed { print("reader failed: \(reader.error?.localizedDescription ?? "?")"); exit(1) }
guard frames.count > 60 else { print("not enough frames (\(frames.count)), \(missed) without a mask"); exit(1) }

// MARK: - Bands from the median profile

let mh = frames[0].rowWidth.count, mw = frames[0].colTop.count
let medWidth = (0..<mh).map { y in median(frames.map { $0.rowWidth[y] }) }
let medTop = (0..<mw).map { x in median(frames.map { $0.colTop[x] }) }
let maxW = medWidth.max() ?? 0
guard maxW > 0 else { print("no body found in the median profile"); exit(1) }
// Shoulder line: first row from the top where the body is at least 60% of its
// widest (the head is narrower). Bottom: last row at 30% (or the frame edge).
let shoulderRow = medWidth.firstIndex(where: { $0 >= 0.6 * maxW }) ?? 0
let bottomRow = medWidth.lastIndex(where: { $0 >= 0.3 * maxW }) ?? (mh - 1)
let bodyH = Double(max(1, bottomRow - shoulderRow))
func band(_ a: Double, _ b: Double) -> Range<Int> {
    let lo = min(mh - 1, shoulderRow + Int(a * bodyH)), hi = min(mh, shoulderRow + Int(b * bodyH))
    return lo..<max(lo + 1, hi)
}
let upper = band(0.00, 0.12), chest = band(0.15, 0.40), belly = band(0.45, 0.75)
// Shoulder columns: columns whose median top edge lies within the shoulder band
// (head columns rise far above it; background columns have no top at all).
let shoulderCols = (0..<mw).filter { x in
    let t = medTop[x]; return !t.isNaN && t >= Double(shoulderRow) - 0.08 * bodyH && t <= Double(shoulderRow) + 0.15 * bodyH
}
FileHandle.standardError.write(String(format: "  bands (upright mask rows): shoulder %d, bottom %d, upper %d-%d, chest %d-%d, belly %d-%d, shoulder cols %d; median widths upper %.1f chest %.1f belly %.1f px\n",
                                      shoulderRow, bottomRow, upper.lowerBound, upper.upperBound, chest.lowerBound, chest.upperBound,
                                      belly.lowerBound, belly.upperBound, shoulderCols.count,
                                      median(Array(medWidth[upper])), median(Array(medWidth[chest])), median(Array(medWidth[belly]))).data(using: .utf8)!)

// Body box in upright mask space -> ROI for the old signals, in the luma grid's
// raw space. The grid is raw (unrotated); map the upright box back.
let bodyCols = (0..<mw).filter { !medTop[$0].isNaN }
let bx0 = Double(bodyCols.first ?? 0) / Double(mw), bx1 = Double((bodyCols.last ?? mw - 1) + 1) / Double(mw)
let by0 = Double(shoulderRow) / Double(mh), by1 = Double(bottomRow + 1) / Double(mh)
// upright normalized (x0,y0,x1,y1) -> raw normalized, inverse of the mask rotation
func rawRect() -> (x0: Double, x1: Double, y0: Double, y1: Double) {
    switch orient {
    case .right: return (x0: by0, x1: by1, y0: 1 - bx1, y1: 1 - bx0)
    case .left:  return (x0: 1 - by1, x1: 1 - by0, y0: bx0, y1: bx1)
    case .down:  return (x0: 1 - bx1, x1: 1 - bx0, y0: 1 - by1, y1: 1 - by0)
    default:     return (x0: bx0, x1: bx1, y0: by0, y1: by1)
    }
}
let rr = rawRect()

// MARK: - Second pass over the stored profiles for the band signals
// (and a second decode for the ROI shift signals, so the A/B is honest: the
// old signals get the same body box the new ones use).

var wupper: [Double] = [], wchest: [Double] = [], wbelly: [Double] = [], shoulder: [Double] = [], area: [Double] = []
for f in frames {
    wupper.append(f.rowWidth[upper].reduce(0, +) / Double(upper.count))
    wchest.append(f.rowWidth[chest].reduce(0, +) / Double(chest.count))
    wbelly.append(f.rowWidth[belly].reduce(0, +) / Double(belly.count))
    let tops = shoulderCols.map { f.colTop[$0] }.filter { !$0.isNaN }
    shoulder.append(tops.isEmpty ? .nan : -(tops.reduce(0, +) / Double(tops.count)))
    area.append(f.rowWidth[shoulderRow...bottomRow].reduce(0, +))
}
// Fill NaN shoulders with the previous value so the column is continuous.
for k in 1..<shoulder.count where shoulder[k].isNaN { shoulder[k] = shoulder[k - 1] }
if shoulder.first?.isNaN == true { shoulder[0] = shoulder.first(where: { !$0.isNaN }) ?? 0 }

FileHandle.standardError.write("  pass 2: ROI shift signals in the body box …\n".data(using: .utf8)!)
let reader2 = try AVAssetReader(asset: asset)
let output2 = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
output2.alwaysCopiesSampleData = false
reader2.add(output2); reader2.startReading()
var rm: [Double] = [], rdy: [Double] = [], rdx: [Double] = [], rl: [Double] = []
var p2: Grid?; var pRow: [Double] = [], pCol: [Double] = []; var rdyAcc = 0.0, rdxAcc = 0.0
nextT = 0.0
while let sb = output2.copyNextSampleBuffer(), rm.count < frames.count {
    let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    guard t >= nextT, let img = CMSampleBufferGetImageBuffer(sb) else { continue }
    nextT = t + step
    guard let grid = downsampleLuma(img, targetMax: gridMax) else { continue }
    let x0 = Int(rr.x0 * Double(grid.w)), x1 = Int(rr.x1 * Double(grid.w))
    let y0 = Int(rr.y0 * Double(grid.h)), y1 = Int(rr.y1 * Double(grid.h))
    let row = grid.rowProfile(x0: x0, x1: x1, y0: y0, y1: y1), col = grid.colProfile(x0: x0, x1: x1, y0: y0, y1: y1)
    var motion = 0.0
    if let p = p2 {
        motion = grid.meanAbsDiff(p, x0: x0, x1: x1, y0: y0, y1: y1)
        rdyAcc += profileShift(pRow, row); rdxAcc += profileShift(pCol, col)
    }
    let w = x1 - x0, h = y1 - y0
    rl.append(grid.meanLuma(x0: x0 + w / 3, x1: x0 + 2 * w / 3, y0: y0 + h / 3, y1: y0 + 2 * h / 3))
    rm.append(motion); rdy.append(rdyAcc); rdx.append(rdxAcc)
    p2 = grid; pRow = row; pCol = col
}
// The two decodes should line up frame for frame; if pass 2 fell short, pad.
while rm.count < frames.count { rm.append(rm.last ?? 0); rdy.append(rdy.last ?? 0); rdx.append(rdx.last ?? 0); rl.append(rl.last ?? 0) }

// MARK: - CSV

var csv = ""
csv += String(format: "# fps=%.1f quality=%d grid=%d\n", fps, quality.rawValue, gridMax)
csv += String(format: "# roi x=%.4f y=%.4f w=%.4f h=%.4f\n", rr.x0, rr.y0, rr.x1 - rr.x0, rr.y1 - rr.y0)
csv += "# bands upright_mask=\(mw)x\(mh) shoulder=\(shoulderRow) bottom=\(bottomRow) upper=\(upper.lowerBound)-\(upper.upperBound) chest=\(chest.lowerBound)-\(chest.upperBound) belly=\(belly.lowerBound)-\(belly.upperBound) shoulder_cols=\(shoulderCols.count)\n"
csv += "t,motion,dy,dx,luma,rmotion,rdy,rdx,rluma,wupper,wchest,wbelly,shoulder,area\n"
for (k, f) in frames.enumerated() {
    csv += String(format: "%.3f,%.5f,%.5f,%.5f,%.3f,%.5f,%.5f,%.5f,%.3f,%.4f,%.4f,%.4f,%.4f,%.2f\n",
                  f.t, f.motion, f.dy, f.dx, f.luma, rm[k], rdy[k], rdx[k], rl[k],
                  wupper[k], wchest[k], wbelly[k], shoulder[k], area[k])
}
try csv.write(toFile: outPath, atomically: true, encoding: .utf8)
print("\(frames.count) frames (\(missed) without a mask) in \(Int(-t0.timeIntervalSinceNow))s → \(outPath)")
