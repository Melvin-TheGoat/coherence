// Cuts a hat out of a picture of Otto wearing it, and records exactly where
// it sits on him (Melvin, 2026-09-27). The hats had been drawn as product
// shots, seen from below with their undersides showing, and read as pasted on
// his forehead. Now each is generated ON him, from a fixed reference
// (mockups/otto-hats/otto-reference.png: OttoAura4 on the app's cream at a
// known size), and this tool takes back only what changed.
//
//   swiftc -O -o /tmp/hat_extract tools/hat_extract.swift
//   /tmp/hat_extract render.webp Shared/Assets.xcassets/OttoAura4.imageset/OttoAura4.png out.png
//
// How:
//   1. Register. The generator keeps his framing but not to the pixel, so it
//      searches scale and offset for the placement of the reference Otto that
//      best matches the render's BODY (below the eyes, which no hat touches).
//   2. Mask. A render pixel is hat when it is not background AND either lies
//      outside his registered silhouette (the hat's brim and crown) or, inside
//      it, differs strongly from the reference's own pixel there (the band
//      across his forehead). Fur the generator redrew a little differently
//      stays under the threshold.
//   3. Clean. Specks go, and pixels over the background are un-mixed from the
//      cream so the edge carries no paper.
//   4. Place. It prints the hat's box in Otto's canvas units (the 664 x 744
//      canvas every aura drawing shares), which is where HatArt draws it.
import AppKit
import CoreGraphics
import CoreImage
import Foundation
import Vision

let a = CommandLine.arguments
guard a.count >= 4 else { print("hat_extract render otto.png out.png [--inside T]"); exit(1) }
var insideT = 55
if let i = a.firstIndex(of: "--inside"), i + 1 < a.count { insideT = Int(a[i + 1]) ?? 55 }
/// Crowns sit low with his tuft poking out above them: trim fur off the top.
let trimTop = a.contains("--trim-top")
/// A halo's middle is not hat, whatever shows through it.
let noFill = a.contains("--no-fill")
/// A floating thing casts no shadow on him (the halo).
let noShadow = a.contains("--no-shadow")
/// A halo: keep the ring and nothing inside it (see the ring branch).
let ring = a.contains("--ring")
/// How close a colour must be to count as redrawn fur when trimming edges.
/// Hats far from his colours (black, blue, green) can take a looser trim.
var trimTol = 30.0
if let i = a.firstIndex(of: "--trim-tol"), i + 1 < a.count { trimTol = Double(a[i + 1]) ?? 30 }

struct Bitmap {
    let w: Int, h: Int
    var px: [UInt8]
    init(_ path: String) {
        let img = NSImage(contentsOfFile: path)!
        var rect = CGRect(origin: .zero, size: img.size)
        let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        w = cg.width; h = cg.height
        px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    // Row 0 is the TOP, as images are read.
    func at(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
        let i = (y * w + x) * 4
        return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), Int(px[i + 3]))
    }
}

var render = Bitmap(a[1])
let otto = Bitmap(a[2])
let W = render.w, H = render.h
let cream = (252, 248, 240)

// The reference's own layout (otto_reference: a 1024 pt canvas, Otto 860 pt
// tall, 20 pt off the bottom, centred), scaled to the render's size.
let k = Double(W) / 1024.0
let baseH = 860.0 * k
let baseW = baseH * Double(otto.w) / Double(otto.h)
let baseX = (Double(W) - baseW) / 2
let baseBottom = Double(H) - 20.0 * k

/// The reference pixel (composited on cream) and its alpha at a render point,
/// for Otto placed at scale `s` about his bottom centre, shifted by (dx, dy).
func refAt(_ x: Int, _ y: Int, s: Double, dx: Double, dy: Double) -> (Int, Int, Int, Double) {
    let w = baseW * s, h = baseH * s
    let left = baseX + (baseW - w) / 2 + dx
    let top = baseBottom - h + dy
    let u = (Double(x) - left) / w, v = (Double(y) - top) / h
    guard u >= 0, u < 1, v >= 0, v < 1 else { return (cream.0, cream.1, cream.2, 0) }
    let (r, g, b, al) = otto.at(Int(u * Double(otto.w)), Int(v * Double(otto.h)))
    let aa = Double(al) / 255
    // premultiplied: composite over cream
    return (r + Int(Double(cream.0) * (1 - aa)), g + Int(Double(cream.1) * (1 - aa)),
            b + Int(Double(cream.2) * (1 - aa)), aa)
}

func error(s: Double, dx: Double, dy: Double, step: Int) -> Int {
    var e = 0
    let y0 = Int(Double(H) * 0.50), y1 = Int(Double(H) * 0.93)
    for y in stride(from: y0, to: y1, by: step) {
        for x in stride(from: Int(baseX), to: Int(baseX + baseW), by: step) {
            let (r, g, b, _) = render.at(x, y)
            let (rr, rg, rb, _) = refAt(x, y, s: s, dx: dx, dy: dy)
            e += abs(r - rr) + abs(g - rg) + abs(b - rb)
        }
    }
    return e
}

// Coarse, then fine.
var best = (s: 1.0, dx: 0.0, dy: 0.0, e: Int.max)
for s in stride(from: 0.92, through: 1.08, by: 0.02) {
    for dx in stride(from: -48.0, through: 48, by: 6) {
        for dy in stride(from: -48.0, through: 48, by: 6) {
            let e = error(s: s, dx: dx, dy: dy, step: 14)
            if e < best.e { best = (s, dx, dy, e) }
        }
    }
}
let coarse = best
best.e = Int.max
for s in stride(from: coarse.s - 0.02, through: coarse.s + 0.02, by: 0.004) {
    for dx in stride(from: coarse.dx - 6, through: coarse.dx + 6, by: 1) {
        for dy in stride(from: coarse.dy - 6, through: coarse.dy + 6, by: 1) {
            let e = error(s: s, dx: dx, dy: dy, step: 5)
            if e < best.e { best = (s, dx, dy, e) }
        }
    }
}

// Otto's silhouette at the registered placement, grown by 3 px so the soft
// edge of his fur is never mistaken for a brim.
var inside = [Bool](repeating: false, count: W * H)
for y in 0..<H { for x in 0..<W {
    if refAt(x, y, s: best.s, dx: best.dx, dy: best.dy).3 > 0.5 { inside[y * W + x] = true }
} }
var grown = inside
for y in 3..<(H - 3) { for x in 3..<(W - 3) where inside[y * W + x] {
    for oy in -3...3 { for ox in -3...3 { grown[(y + oy) * W + x + ox] = true } }
} }

// What is not background, from Vision's subject mask: soft at the edge and
// whole across pale parts (a cream pom-pom is nearly the paper's colour).
var fg = [Float](repeating: 0, count: W * H)
do {
    let img = NSImage(contentsOfFile: a[1])!
    var r = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    let req = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cg)
    try handler.perform([req])
    if let obs = req.results?.first {
        let buf = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        let mw = CVPixelBufferGetWidth(buf), mh = CVPixelBufferGetHeight(buf)
        let rowBytes = CVPixelBufferGetBytesPerRow(buf)
        let base = CVPixelBufferGetBaseAddress(buf)!
        for y in 0..<H { for x in 0..<W {
            let mx = x * mw / W, my = y * mh / H
            fg[y * W + x] = base.advanced(by: my * rowBytes + mx * 4).assumingMemoryBound(to: Float.self).pointee
        } }
        CVPixelBufferUnlockBaseAddress(buf, .readOnly)
    }
} catch { print("vision failed: \(error)") }

/// The difference between render and reference at a point, over a 5 x 5
/// neighbourhood, so a strand of fur redrawn a pixel over is not a hat.
func smoothDiff(_ x: Int, _ y: Int) -> Int {
    var sr = 0, sg = 0, sb = 0, tr = 0, tg = 0, tb = 0, n = 0
    for oy in -2...2 { for ox in -2...2 {
        let xx = min(max(x + ox, 0), W - 1), yy = min(max(y + oy, 0), H - 1)
        let (r, g, b, _) = render.at(xx, yy)
        let (rr, rg, rb, _) = refAt(xx, yy, s: best.s, dx: best.dx, dy: best.dy)
        sr += r; sg += g; sb += b; tr += rr; tg += rg; tb += rb; n += 1
    } }
    return (abs(sr - tr) + abs(sg - tg) + abs(sb - tb)) / n
}

enum Kind { case hat, shadow(Double), fur }
/// Over his fur, what a render pixel is, judged on 5 x 5 averages: the same
/// colour at the same brightness is fur, the same colour darker is shadow, and
/// anything else is hat (a very dark pixel is hat even in fur colours: the
/// black and brown hats).
func furKind(_ x: Int, _ y: Int) -> Kind {
    var sr = 0.0, sg = 0.0, sb = 0.0, tr = 0.0, tg = 0.0, tb = 0.0
    for oy in -2...2 { for ox in -2...2 {
        let xx = min(max(x + ox, 0), W - 1), yy = min(max(y + oy, 0), H - 1)
        let (r, g, b, _) = render.at(xx, yy)
        let (rr, rg, rb, _) = refAt(xx, yy, s: best.s, dx: best.dx, dy: best.dy)
        sr += Double(r); sg += Double(g); sb += Double(b)
        tr += Double(rr); tg += Double(rg); tb += Double(rb)
    } }
    let q = [sr / max(tr, 1), sg / max(tg, 1), sb / max(tb, 1)]
    let spread = q.max()! - q.min()!, mean = (q[0] + q[1] + q[2]) / 3
    // Fur the generator redrew a few pixels off: the render's colour matches
    // his own fur somewhere close by, just not on this exact pixel. (The tan
    // strip under every brim was his face, shifted.) Tight tolerance, so a
    // straw brim is not mistaken for his face.
    guard spread < 0.12 else { return .hat }
    if mean >= 0.93 && mean < 1.12 { return .fur }
    if mean > 0.55 && mean < 0.93 { return .shadow(min(0.5, (1 - mean) * 1.6)) }
    return .hat
}

/// Fur the generator redrew a few pixels off: the render's colour matches his
/// own fur somewhere close by, just not on this exact pixel. Used only to trim
/// a hat's edges (see below), never inside it, because a straw or brown weave
/// is close enough to his fur to be eaten.
func nearFur(_ x: Int, _ y: Int) -> Bool {
    var sr = 0.0, sg = 0.0, sb = 0.0
    for oy in -1...1 { for ox in -1...1 {
        let (r, g, b, _) = render.at(min(max(x + ox, 0), W - 1), min(max(y + oy, 0), H - 1))
        sr += Double(r); sg += Double(g); sb += Double(b)
    } }
    let (ar, ag, ab) = (sr / 9, sg / 9, sb / 9)
    for oy in stride(from: -16, through: 16, by: 2) { for ox in stride(from: -16, through: 16, by: 2) {
        let xx = min(max(x + ox, 0), W - 1), yy = min(max(y + oy, 0), H - 1)
        let (rr, rg, rb, al) = refAt(xx, yy, s: best.s, dx: best.dx, dy: best.dy)
        guard al > 0.9 else { continue }
        if abs(ar - Double(rr)) + abs(ag - Double(rg)) + abs(ab - Double(rb)) < trimTol { return true }
    } }
    return false
}

// His eye line in the render: nothing below it can be hat.
let eyeY = Int(baseBottom + best.dy - baseH * best.s * (1 - 0.33))

var mask = [Bool](repeating: false, count: W * H)
for y in 0..<min(H, eyeY + Int(0.12 * Double(H))) { for x in 0..<W {
    guard fg[y * W + x] > 0.25 else { continue }
    if !grown[y * W + x] {
        mask[y * W + x] = true
    } else if y < eyeY {
        if smoothDiff(x, y) > insideT { mask[y * W + x] = true }
    }
} }

// Close small gaps (a weave's dark lines, a ribbon's shading): grow by 4,
// then shrink by 4, inside his silhouette only.
func grow(_ m: [Bool], _ r: Int) -> [Bool] {
    var o = m
    for y in 0..<H { for x in 0..<W where m[y * W + x] {
        for oy in -r...r { for ox in -r...r {
            let xx = x + ox, yy = y + oy
            if xx >= 0 && xx < W && yy >= 0 && yy < H { o[yy * W + xx] = true }
        } }
    } }
    return o
}
func shrink(_ m: [Bool], _ r: Int) -> [Bool] {
    var o = m
    for y in 0..<H { for x in 0..<W where m[y * W + x] {
        outer: for oy in -r...r { for ox in -r...r {
            let xx = x + ox, yy = y + oy
            if xx < 0 || xx >= W || yy < 0 || yy >= H || !m[yy * W + xx] { o[y * W + x] = false; break outer }
        } }
    } }
    return o
}
let closed = shrink(grow(mask, 4), 4)
for i in 0..<(W * H) where closed[i] && grown[i] && i / W < eyeY { mask[i] = true }

// Keep the big pieces: the hat is one or two islands; specks are fur noise
// and the render's own grain.
var label = [Int](repeating: 0, count: W * H)
var sizes: [Int] = [0]
for start in 0..<(W * H) where mask[start] && label[start] == 0 {
    let id = sizes.count
    var stack = [start]; label[start] = id; var n = 0
    while let p = stack.popLast() {
        n += 1
        let x = p % W, y = p / W
        for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        where nx >= 0 && nx < W && ny >= 0 && ny < H {
            let q = ny * W + nx
            if mask[q] && label[q] == 0 { label[q] = id; stack.append(q) }
        }
    }
    sizes.append(n)
}
let biggest = sizes.max() ?? 0
let keepIDs = Set(sizes.indices.filter { $0 > 0 && sizes[$0] >= max(400, biggest / 12) })
for i in 0..<(W * H) where mask[i] && !keepIDs.contains(label[i]) { mask[i] = false }

// Fill small holes inside the hat (weave gaps the difference missed).
var outside = [Bool](repeating: false, count: W * H)
var stack: [Int] = []
for x in 0..<W { stack.append(x); stack.append((H - 1) * W + x) }
for y in 0..<H { stack.append(y * W); stack.append(y * W + W - 1) }
while let p = stack.popLast() {
    if outside[p] || mask[p] { continue }
    outside[p] = true
    let x = p % W, y = p / W
    if x > 0 { stack.append(p - 1) }; if x < W - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - W) }; if y < H - 1 { stack.append(p + W) }
}
for i in 0..<(W * H) where !noFill && !mask[i] && !outside[i] {
    // A hole: hat unless it is plain background (the halo's middle).
    let (r, g, b, _) = render.at(i % W, i / W)
    if abs(r - cream.0) + abs(g - cream.1) + abs(b - cream.2) > 36 || grown[i] { mask[i] = true }
}

// MARK: - Keep only hat over his head (v2, 2026-09-28)
//
// v1 judged each pixel against the reference pixel at the SAME spot, and the
// generator redraws his forehead under a brim (cream skin where the drawing
// has brown fur, fur a few pixels over), so a ragged band of face survived
// under every brim (Melvin: "white space, messed up cropping"). v2 asks a
// different question: which does this colour look more like, HIS palette
// (anywhere on his head, at any shading) or THIS hat's (sampled where only
// hat can be: off his silhouette)? Then the lower edge is smoothed into one
// curve and a soft contact shadow is drawn under it, instead of keeping the
// render's own ragged shadowed fur.

func q5(_ r: Int, _ g: Int, _ b: Int) -> Int { (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3) }
func unq(_ k: Int) -> (Double, Double, Double) {
    (Double((k >> 10) & 31) * 8 + 4, Double((k >> 5) & 31) * 8 + 4, Double(k & 31) * 8 + 4)
}
// His palette: every opaque colour in the reference's upper body.
var ottoBins = Set<Int>()
for y in 0..<Int(Double(otto.h) * 0.6) { for x in 0..<otto.w {
    let (r, g, b, al) = otto.at(x, y)
    // Not his pupils or nostrils: no hat ever covers his eyes, and near
    // black is exactly what a black hat is made of (the Ensō Hat).
    if al > 240 && max(r, g, b) >= 60 { ottoBins.insert(q5(r, g, b)) }
} }
let ottoPal = ottoBins.map(unq)

// This hat's palette: solid pixels off his silhouette, away from any edge.
var hatCount: [Int: Int] = [:]
for y in 1..<(H - 1) { for x in 1..<(W - 1) {
    let i = y * W + x
    guard mask[i], !grown[i], fg[i] > 0.95,
          mask[i - 1], mask[i + 1], mask[i - W], mask[i + W] else { continue }
    let (r, g, b, _) = render.at(x, y)
    hatCount[q5(r, g, b), default: 0] += 1
} }
let hatPal = hatCount.filter { $0.value >= 3 }.map { unq($0.key) }
print("palettes: otto \(ottoPal.count) colours, hat \(hatPal.count)")

/// The nearest a palette comes to `c`, letting each palette colour darken
/// or lighten within `lo...hi` (shade on a hat, shadow on his face).
func nearest(_ c: (Double, Double, Double), _ pal: [(Double, Double, Double)],
             _ lo: Double, _ hi: Double) -> Double {
    var best = Double.infinity
    for p in pal {
        let pp = p.0 * p.0 + p.1 * p.1 + p.2 * p.2
        let k = pp < 1 ? 1 : min(hi, max(lo, (c.0 * p.0 + c.1 * p.1 + c.2 * p.2) / pp))
        let d = abs(c.0 - k * p.0) + abs(c.1 - k * p.1) + abs(c.2 - k * p.2)
        if d < best { best = d }
    }
    return best
}
var debugAt: [(Int, Int)] = []
if let i = a.firstIndex(of: "--debug"), i + 1 < a.count {
    debugAt = a[i + 1].split(separator: ";").compactMap {
        let v = $0.split(separator: ",").compactMap { Int($0) }
        return v.count == 2 ? (v[0], v[1]) : nil
    }
}
/// How dark his colours may be shaded and still count as him. 0.4 catches
/// the deep shadow under a brim; a black hat needs 0.7, or its weave reads
/// as his fur in shade (the Ensō Hat).
var ottoFloor = 0.4
if let i = a.firstIndex(of: "--otto-floor"), i + 1 < a.count { ottoFloor = Double(a[i + 1]) ?? 0.4 }
/// The smallest separate piece kept. A crown whose render drew his tuft a
/// little off his outline needs more (the Leaf Crown: 1500).
var minPiece = 300
if let i = a.firstIndex(of: "--min-piece"), i + 1 < a.count { minPiece = Int(a[i + 1]) ?? 300 }
var bias = 1.0
if let i = a.firstIndex(of: "--bias"), i + 1 < a.count { bias = Double(a[i + 1]) ?? 1 }

/// Over his head, whether a pixel's colour (3 x 3 average) is nearer this
/// hat's palette than his own.
func looksLikeHat(_ xx: Int, _ yy: Int) -> Bool {
    var c = (0.0, 0.0, 0.0)
    for oy in -1...1 { for ox in -1...1 {
        let (r, g, b, _) = render.at(min(max(xx + ox, 0), W - 1), min(max(yy + oy, 0), H - 1))
        c.0 += Double(r) / 9; c.1 += Double(g) / 9; c.2 += Double(b) / 9
    } }
    let dO = nearest(c, ottoPal, ottoFloor, 1.08)
    let dH = nearest(c, hatPal, 0.7, 1.2)
    if debugAt.contains(where: { abs($0.0 - xx) < 1 && abs($0.1 - yy) < 1 }) {
        print(String(format: "debug (%d,%d) c=(%.0f,%.0f,%.0f) dOtto=%.1f dHat=%.1f", xx, yy, c.0, c.1, c.2, dO, dH))
    }
    return dH < dO * bias
}

var keep = [Bool](repeating: false, count: W * H)
if ring {
    // A halo: the ring and nothing inside it. Seen from the front a ring is
    // thicker at the bottom than the top, so no ellipse describes its hole.
    // The render's hole is clean on the right (paper shows through) and
    // filled with glow on the left, so each row's hole is read on the right
    // and mirrored about the ring's centre. The drip under it goes by the
    // ring's lower edge, fitted from columns well away from the middle.
    var minX = W, maxX = 0, rowWidth = [Int](repeating: 0, count: H)
    var rowMin = [Int](repeating: W, count: H), rowMax = [Int](repeating: -1, count: H)
    for y in 0..<H { for x in 0..<W where mask[y * W + x] {
        minX = min(minX, x); maxX = max(maxX, x)
        rowMin[y] = min(rowMin[y], x); rowMax[y] = max(rowMax[y], x)
    } }
    for y in 0..<H where rowMax[y] >= 0 { rowWidth[y] = rowMax[y] - rowMin[y] }
    let widest = rowWidth.max() ?? 0
    let wideRows = (0..<H).filter { rowWidth[$0] >= widest - 2 }
    let yc = Double(wideRows.reduce(0, +)) / Double(max(1, wideRows.count))
    let cx = Double(minX + maxX) / 2, rx = Double(maxX - minX) / 2 + 0.5
    var ryBs: [Double] = []
    for x in minX...maxX {
        let u = (Double(x) - cx) / rx
        guard abs(u) > 0.4, abs(u) < 0.9 else { continue }
        guard let low = (0..<H).last(where: { mask[$0 * W + x] }) else { continue }
        ryBs.append((Double(low) - yc) / (1 - u * u).squareRoot())
    }
    ryBs.sort()
    let ryB = ryBs.isEmpty ? 0 : ryBs[ryBs.count / 2]
    print(String(format: "ring: centre (%.0f, %.0f), %.0f wide, lower radius %.0f", cx, yc, rx, ryB))
    // The outer edge: top from the highest ring pixel, bottom from the fit.
    let ryT = yc - Double((0..<H).first(where: { rowMax[$0] >= 0 }) ?? 0) + 0.5
    func outerTop(_ x: Double) -> Double { let u = (x - cx) / rx; return yc - ryT * max(0, 1 - u * u).squareRoot() }
    func outerBot(_ x: Double) -> Double { let u = (x - cx) / rx; return yc + ryB * max(0, 1 - u * u).squareRoot() }
    // The hole, read three quarters across on the right, where it is clean:
    // the band's thickness at the top, at the bottom, and at the far end.
    let colX = Int(cx + 0.5 * rx)
    var tT = 0, tB = 0, tR = 0
    while Int(outerTop(Double(colX))) + tT < H, mask[(Int(outerTop(Double(colX))) + tT) * W + colX] { tT += 1 }
    while Int(outerBot(Double(colX))) - tB > 0, mask[(Int(outerBot(Double(colX))) - tB) * W + colX] { tB += 1 }
    while maxX - tR > Int(cx), mask[Int(yc) * W + maxX - tR] { tR += 1 }
    let rxi = rx - Double(tR)
    let topI = outerTop(Double(colX)) + Double(tT), botI = outerBot(Double(colX)) - Double(tB)
    let ui = (Double(colX) - cx) / rxi
    let yci = (topI + botI) / 2
    let ryi = (botI - topI) / 2 / max(0.05, 1 - ui * ui).squareRoot()
    print(String(format: "ring: band %d top, %d bottom, %d end; hole %.0f x %.0f at y %.0f", tT, tB, tR, rxi, ryi, yci))
    for yy in 0..<H { for xx in 0..<W where mask[yy * W + xx] {
        let x = Double(xx), y = Double(yy)
        if abs(x - cx) <= rx && y > outerBot(x) + 2 { continue }
        let ix = (x - cx) / rxi, iy = (y - yci) / ryi
        if ix * ix + iy * iy < 1 { continue }
        keep[yy * W + xx] = true
    } }
    // Where the ring's front passes his tuft the render mixed the two (a
    // drip, a bite out of the band). A ring's front band looks the same all
    // along it, so the middle of the band is rebuilt from the band just
    // either side of the tuft, at the same depth into the band, blended
    // across by position.
    func innerBot(_ x: Double) -> Double {
        let u = (x - cx) / rxi
        return abs(u) < 1 ? yci + ryi * (1 - u * u).squareRoot() : yc
    }
    let span = 0.42 * rx
    let xl = cx - span, xr = cx + span
    let snapshot = render.px, fgSnap = fg
    for xx in Int(xl.rounded(.up))...Int(xr.rounded(.down)) {
        let x = Double(xx)
        let top = innerBot(x), bot = outerBot(x) + 2
        guard bot > top else { continue }
        let w = (x - xl) / (xr - xl)
        for yy in Int(top.rounded(.up))...Int(bot) where yy >= 0 && yy < H {
            let t = (Double(yy) - top) / (bot - top)
            func sample(_ sx: Double) -> (Double, Double, Double, Double) {
                let st = innerBot(sx), sb = outerBot(sx) + 2
                let fy = min(Double(H - 2), max(0, st + t * (sb - st)))
                let y0 = Int(fy), f = fy - Double(y0)
                let j0 = y0 * W + Int(sx.rounded()), j1 = j0 + W
                func mix(_ c: Int) -> Double {
                    Double(snapshot[j0 * 4 + c]) * (1 - f) + Double(snapshot[j1 * 4 + c]) * f
                }
                return (mix(0), mix(1), mix(2), Double(fgSnap[j0]) * (1 - f) + Double(fgSnap[j1]) * f)
            }
            let l = sample(xl), r = sample(xr)
            let i = yy * W + xx
            render.px[i * 4] = UInt8((l.0 * (1 - w) + r.0 * w).rounded())
            render.px[i * 4 + 1] = UInt8((l.1 * (1 - w) + r.1 * w).rounded())
            render.px[i * 4 + 2] = UInt8((l.2 * (1 - w) + r.2 * w).rounded())
            fg[i] = Float(l.3 * (1 - w) + r.3 * w)
            grown[i] = false
            keep[i] = fg[i] > 0.02
        }
    }
} else {
    for yy in 0..<H { for xx in 0..<W where mask[yy * W + xx] {
        let i = yy * W + xx
        if !grown[i] { keep[i] = true; continue }
        if looksLikeHat(xx, yy) { keep[i] = true }
    } }
}

// Opening inside his silhouette takes off thin teeth of face the classifier
// let through; then the big pieces only; then closing fills weave gaps, but
// never past what the render actually drew.
func openInside(_ m: [Bool], _ r: Int) -> [Bool] {
    let o = grow(shrink(m, r), r)
    return (0..<(W * H)).map { grown[$0] ? o[$0] && m[$0] : m[$0] }
}
if !ring {
    keep = openInside(keep, 2)
    // And hair-thin lines anywhere (a strand of his outline the render drew
    // just off his silhouette): an opening of one takes lines two pixels
    // wide and leaves every real edge where it was.
    let opened = grow(shrink(keep, 1), 1)
    for i in 0..<(W * H) where keep[i] && !opened[i] { keep[i] = false }
}
do {
    var lab = [Int](repeating: 0, count: W * H)
    var sz: [Int] = [0]
    for st in 0..<(W * H) where keep[st] && lab[st] == 0 {
        let id = sz.count
        var stack = [st]; lab[st] = id; var n = 0
        while let p = stack.popLast() {
            n += 1
            let x = p % W, y = p / W
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            where nx >= 0 && nx < W && ny >= 0 && ny < H {
                let q = ny * W + nx
                if keep[q] && lab[q] == 0 { lab[q] = id; stack.append(q) }
            }
        }
        sz.append(n)
    }
    // Only specks go. Whatever the classifier kept over his head is hat
    // coloured, and a seam of edge pixels along his outline can cut a
    // cone's whole middle off from its brim, so a relative size test (v1's)
    // threw real hat away.
    let ok = Set(sz.indices.filter { $0 > 0 && sz[$0] >= minPiece })
    for i in 0..<(W * H) where keep[i] && !ok.contains(lab[i]) { keep[i] = false }
}
if !ring {
    let closedKeep = shrink(grow(keep, 5), 5)
    for i in 0..<(W * H) where closedKeep[i] && mask[i] { keep[i] = true }
    // Holes the hat encloses are hat (a pale star, a light patch of weave),
    // as long as the render drew something there.
    var out = [Bool](repeating: false, count: W * H)
    var st: [Int] = []
    for x in 0..<W { st.append(x); st.append((H - 1) * W + x) }
    for y in 0..<H { st.append(y * W); st.append(y * W + W - 1) }
    while let p = st.popLast() {
        if out[p] || keep[p] { continue }
        out[p] = true
        let x = p % W, y = p / W
        if x > 0 { st.append(p - 1) }; if x < W - 1 { st.append(p + 1) }
        if y > 0 { st.append(p - W) }; if y < H - 1 { st.append(p + W) }
    }
    for i in 0..<(W * H) where !keep[i] && !out[i] && mask[i] { keep[i] = true }
}

// One clean lower edge over his head: in each column, the lowest pixel with
// solid hat above it, then a running median across columns, and nothing
// below that line survives.
var edge = [Int](repeating: -1, count: W)
if !ring {
    for x in 0..<W {
        var y = H - 1
        while y >= 4 {
            let i = y * W + x
            if keep[i] && grown[i] && (1...4).allSatisfy({ keep[(y - $0) * W + x] }) { edge[x] = y; break }
            y -= 1
        }
    }
    var smooth = edge
    for x in 0..<W where edge[x] >= 0 {
        let vals = (max(0, x - 9)...min(W - 1, x + 9)).compactMap { edge[$0] >= 0 ? edge[$0] : nil }.sorted()
        smooth[x] = vals[vals.count / 2]
    }
    edge = smooth
    for yy in 0..<H { for xx in 0..<W where keep[yy * W + xx] && grown[yy * W + xx] {
        if edge[xx] >= 0 && yy > edge[xx] { keep[yy * W + xx] = false }
    } }
}

// The contact shadow: a soft dark band under that edge, on his head only.
let shadowDepth = Int(0.014 * Double(H))
var shade = [Double](repeating: 0, count: W * H)
if !ring && !noShadow {
    for x in 0..<W where edge[x] >= 0 {
        for d in 1...shadowDepth {
            let y = edge[x] + d
            guard y < H else { break }
            let i = y * W + x
            guard inside[i], !keep[i] else { continue }
            let t = 1 - Double(d) / Double(shadowDepth)
            shade[i] = 0.34 * pow(t, 1.7)
        }
    }
}

// A picture of the decisions, for tuning (--map out.png): the render dimmed,
// red where the first mask had it, green where it was kept, blue tint over
// his registered silhouette.
if let i = a.firstIndex(of: "--map"), i + 1 < a.count {
    var m = [UInt8](repeating: 255, count: W * H * 4)
    for p in 0..<(W * H) {
        let (r, g, b, _) = render.at(p % W, p / W)
        var c = (Double(r) * 0.5, Double(g) * 0.5, Double(b) * 0.5)
        if grown[p] { c.2 += 60 }
        if mask[p] && !keep[p] { c.0 += 110 }
        if keep[p] { c.1 += 110 }
        m[p * 4] = UInt8(min(255, c.0)); m[p * 4 + 1] = UInt8(min(255, c.1)); m[p * 4 + 2] = UInt8(min(255, c.2))
    }
    let mc = CGContext(data: &m, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    try! NSBitmapImageRep(cgImage: mc.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: a[i + 1]))
}

// MARK: - Layers (v3, 2026-09-28, --layers)
//
// Melvin: the brims "dont actually wrap around his head ... theres like empty
// space between the sides of his head and where the hat starts", and on the
// wizard and bucket hats "you can see some of his head poking through the
// upper sides". Both come from one fact: the render drew his head fuller than
// his real drawing, so no single picture laid over him can fit. A real hat
// sits in three depths, so the cut is split into three pictures of one box:
//   front  the hat above its front edge (crown, band, the brim over his
//          forehead), drawn OVER him, with the contact shadow;
//   back   the whole hat plus its inside filled in between the brim's sides,
//          drawn BEHIND him, so wherever his real head is narrower than the
//          render's the hat's inside shows instead of sky;
//   cover  where his own drawing is hidden: his head above the front edge,
//          which the hat squashes, so fur never pokes out past the crown.
// The front edge is a smooth curve fitted over the middle of his forehead and
// held flat past his head's sides.
let layered = a.contains("--layers")
var frontEdge = [Double](repeating: Double(H), count: W)
var fillPx = [UInt32](repeating: 0, count: W * H)    // 0 = none, else 0xRRGGBB + 1
var cover = [Double](repeating: 0, count: W * H)
var fillFade = [Double](repeating: 1, count: W * H)
if layered && !ring {
    let edged = (0..<W).filter { edge[$0] >= 0 }.map { edge[$0] }.sorted()
    guard !edged.isEmpty else { print("no front edge"); exit(1) }
    let edgeRow = edged[edged.count / 2]
    let headCols = (0..<W).filter { inside[edgeRow * W + $0] }
    let hx0 = headCols.min() ?? 0, hx1 = headCols.max() ?? W - 1
    let hc = Double(hx0 + hx1) / 2, hw = Double(hx1 - hx0)
    var pts = (0..<W).filter { edge[$0] >= 0 && abs(Double($0) - hc) < 0.32 * hw }
        .map { (Double($0) - hc, Double(edge[$0])) }
    func fit(_ p: [(Double, Double)]) -> (Double, Double, Double) {
        var s = [Double](repeating: 0, count: 5), t = [Double](repeating: 0, count: 3)
        for (x, y) in p {
            var xp = 1.0
            for k in 0..<5 { s[k] += xp; if k < 3 { t[k] += xp * y }; xp *= x }
        }
        let m = [[s[0], s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]
        func det(_ q: [[Double]]) -> Double {
            q[0][0] * (q[1][1] * q[2][2] - q[1][2] * q[2][1])
                - q[0][1] * (q[1][0] * q[2][2] - q[1][2] * q[2][0])
                + q[0][2] * (q[1][0] * q[2][1] - q[1][1] * q[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-9 else { return (t[0] / max(1, s[0]), 0, 0) }
        func col(_ c: Int) -> [[Double]] { (0..<3).map { r in (0..<3).map { $0 == c ? t[r] : m[r][$0] } } }
        return (det(col(0)) / d, det(col(1)) / d, det(col(2)) / d)
    }
    var coef = fit(pts)
    for _ in 0..<2 {
        pts = pts.filter { abs($0.1 - (coef.0 + coef.1 * $0.0 + coef.2 * $0.0 * $0.0)) < 8 }
        coef = fit(pts)
    }
    for x in 0..<W {
        let xc = min(max(Double(x), Double(hx0)), Double(hx1)) - hc
        frontEdge[x] = coef.0 + coef.1 * xc + coef.2 * xc * xc
    }
    print(String(format: "front edge: head %d...%d, edge %.0f at the middle, %.0f / %.0f at its sides",
                 hx0, hx1, frontEdge[Int(hc)], frontEdge[hx0], frontEdge[hx1]))

    // The hat's inside, between the brim's inner edges, row by row, in the
    // brim's own colours darkened as its underside is.
    // Averaged over fifteen rows as well as six columns: one row's sample
    // alone drew the inside as horizontal streaks.
    func sample(_ xs: [Int], _ y: Int) -> (Double, Double, Double)? {
        var c = (0.0, 0.0, 0.0), n = 0.0
        for yy in max(0, y - 7)...min(H - 1, y + 7) {
            for x in xs where x >= 0 && x < W && keep[yy * W + x] {
                let (r, g, b, _) = render.at(x, yy)
                c.0 += Double(r); c.1 += Double(g); c.2 += Double(b); n += 1
            }
        }
        guard n > 0, xs.contains(where: { $0 >= 0 && $0 < W && keep[y * W + $0] }) else { return nil }
        return (c.0 / n, c.1 / n, c.2 / n)
    }
    let firstRow = max(0, Int(frontEdge.min() ?? 0))
    for y in firstRow..<H {
        var L = -1, R = W
        for x in 0..<Int(hc) where keep[y * W + x] && Double(y) > frontEdge[x] { L = x }
        for x in stride(from: W - 1, to: Int(hc), by: -1) where keep[y * W + x] && Double(y) > frontEdge[x] { R = x }
        // A row the brim reaches on one side only (its tips are rarely level)
        // is filled from that side to his middle.
        let leftSample = L >= 0 ? sample(Array((L - 5)...L), y) : nil
        let rightSample = R < W ? sample(Array(R...(R + 5)), y) : nil
        guard let either = leftSample ?? rightSample else { continue }
        let lc = leftSample ?? either, rc = rightSample ?? either
        let from = leftSample != nil ? L : Int(hc), to = rightSample != nil ? R : Int(hc)
        guard to - from > 2 else { continue }
        L = from; R = to
        for x in (L + 1)..<R where !keep[y * W + x] && Double(y) > frontEdge[x] {
            let t = Double(x - L) / Double(R - L), dark = 0.82
            let mr: Double = (lc.0 * (1 - t) + rc.0 * t) * dark
            let mg: Double = (lc.1 * (1 - t) + rc.1 * t) * dark
            let mb: Double = (lc.2 * (1 - t) + rc.2 * t) * dark
            let r = UInt32(max(0, min(255, mr))), g = UInt32(max(0, min(255, mg)))
            let b = UInt32(max(0, min(255, mb)))
            fillPx[y * W + x] = (r << 16 | g << 8 | b) + 1
        }
    }

    // The inside ends at the hat's back rim, which curves UP behind his head
    // from each brim tip (seen from a little above, the back of a brim sits
    // higher than its sides). Below that curve there is no hat: a fill cut
    // off square, or faded, showed its edge beside a narrower head.
    let leftTip = (0..<H).last { y in (0..<Int(hc)).contains { keep[y * W + $0] && Double(y) > frontEdge[$0] } }
    let rightTip = (0..<H).last { y in ((Int(hc) + 1)..<W).contains { keep[y * W + $0] && Double(y) > frontEdge[$0] } }
    if let lt = leftTip ?? rightTip, let rt = rightTip ?? leftTip {
        let span = max(1, hw / 2 + 40)
        let rise = 0.55 * (Double(min(lt, rt)) - frontEdge[Int(hc)])
        for x in 0..<W {
            let u = min(1, abs(Double(x) - hc) / span)
            let tip = x < Int(hc) ? Double(lt) : Double(rt)
            let rim = tip - rise * (1 - u * u)
            for y in 0..<H where fillPx[y * W + x] != 0 {
                let below = Double(y) - rim
                if below > 0 { fillFade[y * W + x] = max(0, 1 - below / 3) }
            }
        }
    }

    // Stop hiding him a few pixels ABOVE the hat's real bottom in each
    // column: the fitted edge can sit a little below it, and hiding fur the
    // hat does not reach shows the sky as a pale line along the band.
    // The hat's VISIBLE bottom in a column is where its first real gap
    // starts, reading down from its top: the brim's underside can sit lower
    // in the same column with forehead between, and hiding fur down to it
    // left holes along the edge.
    var coverLimit = frontEdge
    var visibleBottom = frontEdge
    for x in 0..<W {
        guard let top = (0..<H).first(where: { keep[$0 * W + x] }) else { continue }
        var y = top, gap = 0, bottom = top
        while y < H && Double(y) <= frontEdge[x] {
            if keep[y * W + x] { gap = 0; bottom = y } else {
                gap += 1
                if gap >= 4 { break }
            }
            y += 1
        }
        // Six pixels up, inside solid hat: the line steps column to column,
        // and a step reaching the slanted edge left a speck of sky.
        visibleBottom[x] = min(frontEdge[x], Double(bottom))
        coverLimit[x] = visibleBottom[x] - 6
    }
    let margin = 24
    var rowGrown = [Bool](repeating: false, count: W * H)
    for y in 0..<H {
        var last = -10_000
        var next = [Int](repeating: 10_000, count: W)
        var n = 10_000
        for x in stride(from: W - 1, through: 0, by: -1) { if inside[y * W + x] { n = x }; next[x] = n }
        for x in 0..<W {
            if inside[y * W + x] { last = x }
            if x - last <= margin || next[x] - x <= margin { rowGrown[y * W + x] = true }
        }
    }
    for x in 0..<W {
        var last = -10_000
        var next = [Int](repeating: 10_000, count: H)
        var n = 10_000
        for y in stride(from: H - 1, through: 0, by: -1) { if rowGrown[y * W + x] { n = y }; next[y] = n }
        for y in 0..<H {
            if rowGrown[y * W + x] { last = y }
            guard y - last <= margin || next[y] - y <= margin else { continue }
            let above = coverLimit[x] - Double(y)
            // Near the front edge the weave has notches; hiding his fur
            // behind a notch shows the sky through it as a dotted pale line.
            // So close to the edge he is hidden only where the hat is.
            // The same for the hat's own soft edge: its outermost pixels are
            // half see-through, and fur hidden behind them shows as specks.
            let i = y * W + x
            let solid = keep[i] && x > 0 && x < W - 1 && y > 0 && y < H - 1
                && keep[i - 1] && keep[i + 1] && keep[i - W] && keep[i + W]
            if above > 0 && (above > 14 || solid) { cover[i] = min(1, above / 4) }
        }
    }

    // The contact shadow lies on his forehead, under the front edge, across
    // his head only.
    for i in 0..<(W * H) { shade[i] = 0 }
    if !noShadow {
        for x in hx0...hx1 {
            // From the hat's VISIBLE bottom, not the fitted curve: where the
            // brim sits a pixel or two above the curve, starting at the
            // curve left an unshaded sliver of forehead, a pale dotted line.
            for d in 1...shadowDepth {
                let y = Int(visibleBottom[x].rounded()) + d
                guard y >= 0, y < H else { continue }
                let i = y * W + x
                guard inside[i], !keep[i] || Double(y) > frontEdge[x] else { continue }
                let t = 1 - Double(d) / Double(shadowDepth)
                shade[i] = 0.34 * pow(t, 1.7)
            }
        }
    }
}

// Bounding box, of everything any layer draws.
var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H { for x in 0..<W {
    let i = y * W + x
    guard keep[i] || shade[i] > 0.01 || fillPx[i] != 0 || cover[i] > 0.01 else { continue }
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
guard maxX > minX else { print("no hat found"); exit(1) }
minX = max(0, minX - 2); minY = max(0, minY - 2); maxX = min(W - 1, maxX + 2); maxY = min(H - 1, maxY + 2)
let cw = maxX - minX + 1, ch = maxY - minY + 1

enum Part { case whole, front, back, cover }
func picture(_ part: Part) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: cw * ch * 4)
    for y in minY...maxY { for x in minX...maxX {
        let i = y * W + x
        let o = ((y - minY) * cw + (x - minX)) * 4
        if part == .cover {
            let al = cover[i]
            guard al > 0.01 else { continue }
            out[o] = UInt8(255 * al); out[o + 1] = UInt8(255 * al); out[o + 2] = UInt8(255 * al)
            out[o + 3] = UInt8(255 * al)
            continue
        }
        // How much of this pixel belongs to the front: all of it above the
        // edge, fading out over two pixels below it.
        let frontShare = part == .front ? min(1, max(0, (frontEdge[x] + 2 - Double(y)) / 2)) : 1
        guard keep[i] else {
            if part == .back, fillPx[i] != 0 {
                let v = fillPx[i] - 1, al = fillFade[i]
                guard al > 0.01 else { continue }
                out[o] = UInt8(Double(v >> 16 & 255) * al); out[o + 1] = UInt8(Double(v >> 8 & 255) * al)
                out[o + 2] = UInt8(Double(v & 255) * al); out[o + 3] = UInt8(255 * al)
                continue
            }
            guard part != .back else { continue }
            let al = shade[i]
            guard al > 0.01 else { continue }
            out[o] = UInt8(20 * al); out[o + 1] = UInt8(12 * al); out[o + 2] = UInt8(6 * al)
            out[o + 3] = UInt8(al * 255)
            continue
        }
        let (r, g, b, _) = render.at(x, y)
        var alpha = 1.0
        if !grown[i] { alpha = Double(min(1, max(0, fg[i]))) }
        var edgePx = false
        for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        where nx >= 0 && nx < W && ny >= 0 && ny < H && !keep[ny * W + nx] && fillPx[ny * W + nx] == 0 {
            edgePx = true
        }
        if edgePx { alpha *= 0.55 }
        func un(_ c: Int, _ bgc: Int) -> Int {
            guard alpha > 0.01, alpha < 0.999 else { return c }
            return max(0, min(255, Int((Double(c) - Double(bgc) * (1 - alpha)) / alpha)))
        }
        let (ur, ug, ub) = grown[i] ? (r, g, b) : (un(r, cream.0), un(g, cream.1), un(b, cream.2))
        alpha *= frontShare
        guard alpha > 0.004 else { continue }
        out[o] = UInt8(Double(ur) * alpha); out[o + 1] = UInt8(Double(ug) * alpha)
        out[o + 2] = UInt8(Double(ub) * alpha); out[o + 3] = UInt8(alpha * 255)
    } }
    return out
}
func write(_ px: [UInt8], _ path: String) {
    var px = px
    let ctx = CGContext(data: &px, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}
write(picture(.whole), a[3])
if layered && !ring {
    let base = a[3].hasSuffix(".png") ? String(a[3].dropLast(4)) : a[3]
    write(picture(.front), base + "-front.png")
    write(picture(.back), base + "-back.png")
    write(picture(.cover), base + "-cover.png")
}

// The box in Otto's canvas units (his drawing's own pixels, 664 x 744).
let ow = baseW * best.s, oh = baseH * best.s
let oleft = baseX + (baseW - ow) / 2 + best.dx
let otop = baseBottom - oh + best.dy
func cu(_ x: Int) -> Double { (Double(x) - oleft) / ow * Double(otto.w) }
func cv(_ y: Int) -> Double { (Double(y) - otop) / oh * Double(otto.h) }
print(String(format: "registered s=%.3f dx=%.0f dy=%.0f | canvas box x=%.1f y=%.1f w=%.1f h=%.1f",
             best.s, best.dx, best.dy, cu(minX), cv(minY), cu(maxX + 1) - cu(minX), cv(maxY + 1) - cv(minY)))
