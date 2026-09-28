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

let render = Bitmap(a[1])
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
let keep = Set(sizes.indices.filter { $0 > 0 && sizes[$0] >= max(400, biggest / 12) })
for i in 0..<(W * H) where mask[i] && !keep.contains(label[i]) { mask[i] = false }

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

// What each hat pixel over his fur is (see furKind), then the edges trimmed:
// up from the bottom of each column, redrawn face fur is dropped until the
// first pixel that is really hat (the tan strip under every brim); and, for a
// crown, down from the top likewise (his tuft poking out above it).
var kind = [Kind?](repeating: nil, count: W * H)
for i in 0..<(W * H) where mask[i] && grown[i] { kind[i] = furKind(i % W, i / W) }
for x in 0..<W {
    var y = min(H - 1, eyeY + Int(0.12 * Double(H)))
    while y > 0 {
        let i = y * W + x
        if mask[i], grown[i], case .hat? = kind[i] {
            if nearFur(x, y) { kind[i] = .fur } else { break }
        }
        y -= 1
    }
    if trimTop {
        var y = 0
        while y < eyeY {
            let i = y * W + x
            if mask[i], case .hat? = kind[i] ?? .hat {
                if nearFur(x, y) { kind[i] = .fur; if !grown[i] { mask[i] = false } } else { break }
            }
            y += 1
        }
    }
}

// Bounding box.
var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H { for x in 0..<W where mask[y * W + x] {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
guard maxX > minX else { print("no hat found"); exit(1) }
minX = max(0, minX - 2); minY = max(0, minY - 2); maxX = min(W - 1, maxX + 2); maxY = min(H - 1, maxY + 2)
let cw = maxX - minX + 1, ch = maxY - minY + 1

var out = [UInt8](repeating: 0, count: cw * ch * 4)
for y in minY...maxY { for x in minX...maxX where mask[y * W + x] {
    let (r, g, b, _) = render.at(x, y)
    var alpha = 1.0
    if !grown[y * W + x] {
        // Over the paper: Vision's soft edge is the alpha.
        alpha = Double(min(1, max(0, fg[y * W + x])))
    }
    // Feather the edge by one pixel.
    var edge = false
    for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    where nx >= 0 && nx < W && ny >= 0 && ny < H && !mask[ny * W + nx] { edge = true }
    if edge { alpha *= 0.55 }
    func un(_ c: Int, _ bgc: Int) -> Int {
        guard alpha > 0.01, alpha < 0.999 else { return c }
        return max(0, min(255, Int((Double(c) - Double(bgc) * (1 - alpha)) / alpha)))
    }
    var (ur, ug, ub) = grown[y * W + x] ? (r, g, b) : (un(r, cream.0), un(g, cream.1), un(b, cream.2))
    if grown[y * W + x] {
        // Over his fur: hat, the hat's shadow, or fur the generator only
        // redrew. Fur is dropped (his own drawing is under it, whichever of
        // the thirteen looks he is in); a shadow becomes see-through dark, so
        // it shades a grey Otto as well as a golden one.
        switch kind[y * W + x] ?? .hat {
        case .fur: continue
        case .shadow(let dark):
            if noShadow { continue }
            (ur, ug, ub) = (20, 12, 6); alpha = min(alpha, dark)
        case .hat: break
        }
    }
    let o = ((y - minY) * cw + (x - minX)) * 4
    out[o] = UInt8(Double(ur) * alpha); out[o + 1] = UInt8(Double(ug) * alpha)
    out[o + 2] = UInt8(Double(ub) * alpha); out[o + 3] = UInt8(alpha * 255)
} }
let ctx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))

// The box in Otto's canvas units (his drawing's own pixels, 664 x 744).
let ow = baseW * best.s, oh = baseH * best.s
let oleft = baseX + (baseW - ow) / 2 + best.dx
let otop = baseBottom - oh + best.dy
func cu(_ x: Int) -> Double { (Double(x) - oleft) / ow * Double(otto.w) }
func cv(_ y: Int) -> Double { (Double(y) - otop) / oh * Double(otto.h) }
print(String(format: "registered s=%.3f dx=%.0f dy=%.0f | canvas box x=%.1f y=%.1f w=%.1f h=%.1f",
             best.s, best.dx, best.dy, cu(minX), cv(minY), cu(maxX + 1) - cu(minX), cv(maxY + 1) - cv(minY)))
