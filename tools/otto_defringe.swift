// Takes the white paper back out of an Otto cut-out.
//
//     swiftc -O tools/otto_defringe.swift -o /tmp/otto_defringe
//     /tmp/otto_defringe in.png out.png [--rim 3] [--floor 0] [--no-holes] [--report]
//
// WHY (Melvin, 2026-09-23): "you can see a little white space between his
// arm and his head, so its obvious its cropped out ... you can see it
// slightly around his legs, arms, top of his head in the tufts of his hair."
// Every Otto was drawn by an image model on white paper and cut out, and two
// things of the paper survived every cut:
//
// 1. PAPER TRAPPED INSIDE HIM. The cutters fill enclosed regions so his cream
//    face and belly come in, and that also fills the paper caught between an
//    arm and his head, between two tufts, between his legs, with opaque
//    white. Paper is the sheet's white, often warmed a little by the soft
//    light the model paints round him (every channel >= 224); his cream
//    never reaches that (it tops out near 208 in its darkest channel,
//    measured on all seven stages), so paper-pale that he encloses is a hole,
//    with two exceptions: the whites of his eyes, which always touch true
//    black (a pupil), and, at stages 6 and 7, a highlight on his muzzle just
//    as pale as paper, which is ringed by cream where a gap is ringed by fur.
//
// 2. A RIM OF PAPER ROUND HIM. An edge pixel that was half fur and half
//    paper was kept fully opaque, so he wears a pale outline on any colour
//    darker than white. Each opaque pixel near his edge is treated as a mix
//    of the fur just inside it and white: the share of white becomes
//    transparency and the colour is un-mixed back to fur. Where the fur
//    itself is pale (claws, cream), there is nothing to un-mix and the pixel
//    is left alone, which is what keeps his claws solid.
//
// Everything he is (fur, face, eyes, the light around him from stage 5 up)
// is untouched away from those two places.
//
// Swift because this Mac has no numpy or PIL.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGBA {
    var w: Int, h: Int
    var px: [Double]   // straight alpha, 0...255, 4 per pixel
}

func load(_ path: String) -> RGBA {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
    let w = cg.width, h = cg.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var px = [Double](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        let a = Double(raw[i * 4 + 3])
        px[i * 4 + 3] = a
        for c in 0..<3 { px[i * 4 + c] = a > 0 ? min(255, Double(raw[i * 4 + c]) * 255 / a) : 0 }
    }
    return RGBA(w: w, h: h, px: px)
}

func save(_ img: RGBA, _ path: String) {
    var raw = [UInt8](repeating: 0, count: img.w * img.h * 4)
    for i in 0..<(img.w * img.h) {
        let a = max(0, min(255, img.px[i * 4 + 3].rounded()))
        raw[i * 4 + 3] = UInt8(a)
        for c in 0..<3 { raw[i * 4 + c] = UInt8(max(0, min(255, (img.px[i * 4 + c] * a / 255).rounded()))) }
    }
    let ctx = CGContext(data: &raw, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let report = args.contains("--report"); args.removeAll { $0 == "--report" }
/// Lit art (a wheel, swirls or a halo drawn in) has pale light that is not
/// paper: clean the rim only.
let noHoles = args.contains("--no-holes"); args.removeAll { $0 == "--no-holes" }
/// How far in from his edge a pixel can still carry paper. Scale it with the
/// art: 2 to 3 at the sheet's own size, more for an image scaled up after.
let rim = Int(option("--rim") ?? "3")!
/// Clear anything fainter than this that is not touching him: the invisible
/// specks un-compositing leaves. 0 keeps them (the stills with light).
let floorAlpha = Double(option("--floor") ?? "0")!
guard args.count >= 2 else { print("usage: otto_defringe in.png out.png [--rim 3] [--floor 0] [--no-holes] [--report]"); exit(1) }

var img = load(args[0])
let w = img.w, h = img.h, n = w * h
func a(_ i: Int) -> Double { img.px[i * 4 + 3] }
func rgb(_ i: Int) -> (Double, Double, Double) { (img.px[i * 4], img.px[i * 4 + 1], img.px[i * 4 + 2]) }
func neighbours8(_ i: Int) -> [Int] {
    let x = i % w, y = i / w
    var out: [Int] = []
    for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
        let xx = x + dx, yy = y + dy
        if xx >= 0, xx < w, yy >= 0, yy < h { out.append(yy * w + xx) }
    } }
    return out
}

// MARK: 1. Paper trapped inside him

var paper = [Bool](repeating: false, count: n)
for i in 0..<n where a(i) > 200 {
    let (r, g, b) = rgb(i)
    let lo = min(r, g, b), hi = max(r, g, b)
    paper[i] = lo >= 224 && hi - lo <= 40
}
// Measured on every Otto cut (seven aura bodies, nine poses), 2026-09-23:
// every eye white and catch-light touches TRUE black (a pupil, below 50 in
// every channel); no gap does. His dark eye patch is not true black, and the
// white wedge between his raised arm and his head touches only that, which
// is why an earlier "near-black" test kept it. Every gap is ringed by under
// 10% cream; every highlight on his face by over 55%.
var label = [Int](repeating: -1, count: n)
var holes = 0, kept = 0, cleared = 0
for start in 0..<n where !noHoles && paper[start] && label[start] < 0 {
    var comp: [Int] = [start]; label[start] = start
    var k = 0
    while k < comp.count {
        let i = comp[k]; k += 1
        for j in neighbours8(i) where paper[j] && label[j] < 0 { label[j] = start; comp.append(j) }
    }
    var touchesBlack = false
    outer: for i in comp {
        let x = i % w, y = i / w
        for dy in -2...2 { for dx in -2...2 {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
            let j = yy * w + xx
            let (r, g, b) = rgb(j)
            if a(j) > 200 && max(r, g, b) < 50 { touchesBlack = true; break outer }
        } }
    }
    // What rings it, four steps out.
    var ring = Set<Int>(), frontier = Set(comp), inComp = Set(comp)
    var touchesOutside = false
    for _ in 0..<4 {
        var next = Set<Int>()
        for i in frontier { for j in neighbours8(i) where !inComp.contains(j) && !ring.contains(j) {
            if a(j) < 8 { touchesOutside = true; continue }
            ring.insert(j); next.insert(j)
        } }
        frontier = next
    }
    let cream = ring.filter { j in let (r, g, b) = rgb(j); return min(r, g, b) >= 175 }.count
    let creamShare = ring.isEmpty ? 0 : Double(cream) / Double(ring.count)
    let hole = !touchesBlack && (touchesOutside || creamShare < 0.4)
    if report {
        print(String(format: "%@ %5dpx at %d,%d black=%d outside=%d cream %.0f%%", hole ? "hole" : "kept",
                     comp.count, comp[0] % w, comp[0] / w, touchesBlack ? 1 : 0, touchesOutside ? 1 : 0, 100 * creamShare))
    }
    if hole {
        holes += 1; cleared += comp.count
        for i in comp { img.px[i * 4 + 3] = 0 }
    } else {
        kept += 1
    }
}

// MARK: 2. The rim

// Opaque pixels: steps in from anything not opaque. Everything else: steps
// out from the opaque body. Both 8-way, both only as far as they matter.
func steps(from seeds: [Bool], limit: Int) -> [Int] {
    var d = [Int](repeating: Int.max, count: n)
    var q: [Int] = []
    for i in 0..<n where seeds[i] { d[i] = 0; q.append(i) }
    var head = 0
    while head < q.count {
        let i = q[head]; head += 1
        guard d[i] < limit else { continue }
        for j in neighbours8(i) where d[j] == Int.max { d[j] = d[i] + 1; q.append(j) }
    }
    return d
}
let opaque = (0..<n).map { a($0) >= 250 }
let distIn = steps(from: opaque.map { !$0 }, limit: rim + 8)   // for opaque pixels
let distOut = steps(from: opaque, limit: 3)                   // for the soft edge outside

var out = img
var unmixed = 0
let win = rim + 6
for i in 0..<n {
    let isRim = opaque[i] && distIn[i] >= 1 && distIn[i] <= rim
    let isSoftEdge = !opaque[i] && a(i) >= 8 && distOut[i] <= 2
    guard isRim || isSoftEdge else { continue }
    // The fur just inside, nearest first: deeper than the rim if there is
    // any (a thin tuft may have none), else anything opaque two steps in.
    let x = i % w, y = i / w
    var f = (0.0, 0.0, 0.0), wsum = 0.0
    for minDepth in [rim + 1, 2, 1] {
        for dy in -win...win { for dx in -win...win {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
            let j = yy * w + xx
            guard opaque[j], distIn[j] >= minDepth else { continue }
            let wt = 1 / (1 + Double(dx * dx + dy * dy))
            let (r, g, b) = rgb(j)
            f.0 += r * wt; f.1 += g * wt; f.2 += b * wt; wsum += wt
        } }
        if wsum > 0 { break }
    }
    guard wsum > 0 else { continue }
    let fr = f.0 / wsum, fg = f.1 / wsum, fb = f.2 / wsum
    let dr = 255 - fr, dg = 255 - fg, db = 255 - fb
    let dd = dr * dr + dg * dg + db * db
    guard dd > 45 * 45 else { continue }   // pale fur (claws, cream): nothing to un-mix
    let (r, g, b) = rgb(i)
    let t = max(0, min(1, ((255 - r) * dr + (255 - g) * dg + (255 - b) * db) / dd))
    guard t < 0.97 else { continue }        // no paper in it
    // Only a pixel that really is fur and white. Rim LIGHT (the orange drawn
    // on stages 6 and 7) is not on that line, and is left as drawn.
    let mr = t * fr + (1 - t) * 255, mg = t * fg + (1 - t) * 255, mb = t * fb + (1 - t) * 255
    let miss = ((r - mr) * (r - mr) + (g - mg) * (g - mg) + (b - mb) * (b - mb)).squareRoot()
    guard miss < 28 else { continue }
    unmixed += 1
    out.px[i * 4 + 3] = a(i) * t
    // The white share swapped for the fur's own colour.
    out.px[i * 4] = max(0, min(255, r + (1 - t) * (fr - 255)))
    out.px[i * 4 + 1] = max(0, min(255, g + (1 - t) * (fg - 255)))
    out.px[i * 4 + 2] = max(0, min(255, b + (1 - t) * (fb - 255)))
}

// Specks of colour at an alpha nobody can see, left by un-compositing the
// paper's noise. Only for bodies with no light round them (`--floor`).
if floorAlpha > 0 {
    for i in 0..<n where out.px[i * 4 + 3] < floorAlpha && !(distOut[i] <= 1) { out.px[i * 4 + 3] = 0 }
}

save(out, args[1])
print("\(args[0].split(separator: "/").last ?? ""): holes \(holes) (\(cleared)px), whites kept \(kept), rim pixels un-mixed \(unmixed)")
