// card_digitize — recover the wrist's breathing and stillness curves from a
// share-card image, as per-window numbers.
//
// The card is deterministic (ShareCard.swift): each curve is a 2 pt stroke in
// a 34 pt rect inset 8 %, 274 pt wide, breathing on an absolute 0–20 ruler
// and stillness on 0–1. Horizontal scale comes from the stroke's own extent.
// The vertical offset comes from the one number the panel prints: the mean
// breathing rate. Stillness sits one title-pitch above breathing.
//
// Build: swiftc -O -o /tmp/card_digitize tools/card_digitize.swift
// Run:   /tmp/card_digitize card.jpeg --mean 7.3 --session 600 [--out series.csv]

import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: card_digitize <image> --mean R --session S [--out csv]"); exit(1) }
var meanAnchor = 0.0, sessionSec = 0.0, outPath: String?, debugPath: String?
var i = 2
while i < args.count {
    switch args[i] {
    case "--mean": meanAnchor = Double(args[i + 1]) ?? 0; i += 2
    case "--session": sessionSec = Double(args[i + 1]) ?? 0; i += 2
    case "--out": outPath = args[i + 1]; i += 2
    case "--debug": debugPath = args[i + 1]; i += 2
    default: i += 1
    }
}
guard meanAnchor > 0, sessionSec > 0 else { print("need --mean and --session"); exit(1) }

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = img.width, H = img.height
var buf = [UInt8](repeating: 0, count: W * H * 4)
let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
func px(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let k = (y * W + x) * 4; return (Int(buf[k]), Int(buf[k + 1]), Int(buf[k + 2]))   // memory is top row first
}
func isTeal(_ x: Int, _ y: Int) -> Bool { let p = px(x, y); return p.g > 115 && p.g > p.r + 25 && p.b > p.r + 12 }
func isGold(_ x: Int, _ y: Int) -> Bool { let p = px(x, y); return p.r > 150 && p.g > 115 && p.b < 100 && p.r > p.b + 90 }

/// Rows containing at least `minPx` matching pixels, grouped into contiguous clusters.
func clusters(_ match: (Int, Int) -> Bool, minPx: Int, xRange: Range<Int>, yRange: Range<Int>) -> [(top: Int, bottom: Int, width: Int)] {
    var out: [(Int, Int, Int)] = []
    var cur: (Int, Int, Int)? = nil
    for y in yRange {
        var n = 0, xmin = Int.max, xmax = -1
        for x in xRange where match(x, y) { n += 1; xmin = min(xmin, x); xmax = max(xmax, x) }
        if n >= minPx {
            if var c = cur { c.1 = y; c.2 = max(c.2, xmax - xmin + 1); cur = c } else { cur = (y, y, xmax - xmin + 1) }
        } else if let c = cur, y - c.1 > 2 { out.append(c); cur = nil }
    }
    if let c = cur { out.append(c) }
    return out.map { (top: $0.0, bottom: $0.1, width: $0.2) }
}

// The curves span nearly the full content width; titles are short. Find the
// teal clusters (heart curve, "BREATHING" title, breathing curve) and gold
// ones (ring, "808", "STILLNESS" title, stillness curve, streak).
let full = 0..<W
let tealC = clusters(isTeal, minPx: 3, xRange: full, yRange: 0..<H)
let goldC = clusters(isGold, minPx: 3, xRange: full, yRange: 0..<H)
func wide(_ c: [(top: Int, bottom: Int, width: Int)]) -> [(top: Int, bottom: Int, width: Int)] { c.filter { $0.width > W / 2 } }
let tealCurves = wide(tealC)          // heart, breathing (in order)
let goldCurves = wide(goldC)          // stillness (the ring is round, not wide? it is ~40% wide)
guard let breath = tealCurves.last, let still = goldCurves.last(where: { $0.bottom < breath.top }) else {
    print("could not locate curves; teal wide: \(tealCurves), gold wide: \(goldCurves)"); exit(1)
}
// Titles: the narrow cluster just above each curve.
let breathTitle = tealC.last(where: { $0.bottom < breath.top && $0.width < W / 2 })!
let stillTitle = goldC.last(where: { $0.bottom < still.top && $0.width < W / 2 })!
let pitch = Double(breathTitle.top - stillTitle.top)

// Horizontal extent of the breathing stroke → scale (px per pt).
var xmin = Int.max, xmax = -1
for y in breath.top...breath.bottom { for x in full where isTeal(x, y) { xmin = min(xmin, x); xmax = max(xmax, x) } }
let s = Double(xmax - xmin + 1) / 276.0           // 274 pt rect + 2 × 1 pt round caps
let rectH = 34 * s, inset = rectH * 0.08, usable = rectH - 2 * inset
let minX = Double(xmin) + s, maxX = Double(xmax) - s

/// Per-column centre of the stroke, across the rect.
func trace(_ match: (Int, Int) -> Bool, rows: ClosedRange<Int>) -> [(xf: Double, y: Double)] {
    var out: [(Double, Double)] = []
    for x in Int(minX)...Int(maxX) {
        var ys: [Double] = []
        for y in rows where match(x, y) { ys.append(Double(y)) }
        guard !ys.isEmpty else { continue }
        out.append(((Double(x) - minX) / (maxX - minX), ys.reduce(0, +) / Double(ys.count)))
    }
    return out
}
print("teal clusters: \(tealC.map { "\($0.top)-\($0.bottom) w\($0.width)" })")
print("gold clusters: \(goldC.map { "\($0.top)-\($0.bottom) w\($0.width)" })")
print("breath curve rows \(breath.top)-\(breath.bottom), title rows \(breathTitle.top)-\(breathTitle.bottom); still curve \(still.top)-\(still.bottom), title \(stillTitle.top)-\(stillTitle.bottom)")
print("stroke x extent \(xmin)-\(xmax)")
let bTrace = trace(isTeal, rows: (breath.top - 4)...(breath.bottom + 4))
let sTrace = trace(isGold, rows: (still.top - 4)...(still.bottom + 4))

// Vertical anchor: mean of the drawn breathing curve equals the printed mean.
let meanY = bTrace.map(\.y).reduce(0, +) / Double(bTrace.count)
let bMaxY = meanY + inset + meanAnchor * usable / 20.0
let sMaxY = bMaxY - pitch
func breathValue(_ y: Double) -> Double { 20.0 * (bMaxY - inset - y) / usable }
func stillValue(_ y: Double) -> Double { (sMaxY - inset - y) / usable }

print(String(format: "image %dx%d  scale %.3f px/pt  rect %.1f px  breath rect bottom y=%.1f  pitch %.0f px",
             W, H, s, rectH, bMaxY, pitch))
let bv = bTrace.map { breathValue($0.y) }, sv = sTrace.map { stillValue($0.y) }
print(String(format: "breath: %d columns, min %.1f max %.1f mean %.2f (anchor %.1f)", bv.count, bv.min()!, bv.max()!, bv.reduce(0,+)/Double(bv.count), meanAnchor))
print(String(format: "stillness: %d columns, min %.2f max %.2f mean %.2f", sv.count, sv.min()!, sv.max()!, sv.reduce(0,+)/Double(sv.count)))

// Per minute of SESSION time (x fraction × session length).
func perMinute(_ t: [(xf: Double, y: Double)], _ f: (Double) -> Double, _ fmt: String) -> String {
    var m: [Int: [Double]] = [:]
    for p in t { m[Int(p.xf * sessionSec / 60), default: []].append(f(p.y)) }
    return m.keys.sorted().map { k in let v = m[k]!.sorted(); return String(format: "%d:" + fmt, k, v[v.count / 2]) }.joined(separator: "  ")
}
print("first columns (x, y): " + bTrace.prefix(6).map { String(format: "(%.2f,%.0f)", $0.xf, $0.y) }.joined(separator: " "))
print("last columns  (x, y): " + bTrace.suffix(4).map { String(format: "(%.2f,%.0f)", $0.xf, $0.y) }.joined(separator: " "))
if let debugPath {
    // Paint traced centres red, rect bounds green, onto a copy and save PNG.
    var out = buf
    func set(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        guard x >= 0, x < W, y >= 0, y < H else { return }
        let k = (y * W + x) * 4; out[k] = r; out[k + 1] = g; out[k + 2] = b; out[k + 3] = 255
    }
    for p in bTrace { let x = Int(minX + p.xf * (maxX - minX)); set(x, Int(p.y), 255, 0, 0) }
    for p in sTrace { let x = Int(minX + p.xf * (maxX - minX)); set(x, Int(p.y), 255, 0, 0) }
    for x in Int(minX)...Int(maxX) {
        set(x, Int(bMaxY), 0, 255, 0); set(x, Int(bMaxY - rectH), 0, 255, 0)
        set(x, Int(sMaxY), 0, 255, 0); set(x, Int(sMaxY - rectH), 0, 255, 0)
    }
    let dctx = CGContext(data: &out, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let dimg = dctx.makeImage()!
    let crop = dimg.cropping(to: CGRect(x: 0, y: Int(sMaxY - rectH) - 40, width: W, height: Int(bMaxY - sMaxY + rectH + 80)))!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: debugPath) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, crop, nil); CGImageDestinationFinalize(dest)
    print("debug → \(debugPath)")
}
print("breath per minute:    " + perMinute(bTrace, breathValue, "%.1f"))
print("stillness per minute: " + perMinute(sTrace, stillValue, "%.2f"))

if let outPath {
    var csv = "t_sec,breath,stillness\n"
    // Resample both to 5 s on session time.
    func at(_ t: [(xf: Double, y: Double)], _ xf: Double) -> Double? {
        var best: (Double, Double)? = nil
        for p in t { let d = abs(p.xf - xf); if best == nil || d < best!.0 { best = (d, p.y) } }
        return best.flatMap { $0.0 < 0.01 ? $0.1 : nil }
    }
    var t = 0.0
    while t <= sessionSec {
        let xf = t / sessionSec
        let b = at(bTrace, xf).map(breathValue), st = at(sTrace, xf).map(stillValue)
        csv += String(format: "%.0f,%@,%@\n", t, b.map { String(format: "%.2f", $0) } ?? "", st.map { String(format: "%.3f", $0) } ?? "")
        t += 5
    }
    try! csv.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("→ \(outPath)")
}
