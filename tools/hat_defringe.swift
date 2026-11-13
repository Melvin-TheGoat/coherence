// Takes the white paper back out of a hat's soft edge.
//
//     swiftc -O tools/hat_defringe.swift -o /tmp/hat_defringe
//     /tmp/hat_defringe --report in.png            # measure only
//     /tmp/hat_defringe in.png out.png [--threshold 18] [--skip-pale]
//     /tmp/hat_defringe --composite in.png out.png r g b   # flatten over a colour
//
// WHY (Melvin, 2026-11-13): "a faint thin white outline" round the wizard
// hat, the ensō, the top hat and the halo on Home. Every hat was generated on
// a white page and cut out by `tools/hat_extract.swift`, which keeps the
// cut's soft edge by ALPHA but leaves the edge pixels' COLOUR as the page:
// the outer two or three pixels of the wizard hat read (straight alpha)
// a39 (216,235,255), a100 (250,255,255), a137 (231,242,255) round a navy hat
// of about (64,80,123). Drawn over any sky darker than white, that is a thin
// pale line. The alpha ramp itself is right; only the colour is the paper.
//
// The fix keeps every alpha exactly and gives each edge pixel (within three
// pixels of transparency) the colour of the solid hat just inside it, when
// that pixel is lighter than the hat there by more than the threshold. Light
// that belongs to the hat (a star or a highlight reaching the edge) is lighter
// than its own solid neighbours too, so the reference is taken from the
// nearest solid pixels, which on a star are the star.
//
// `--skip-pale` is for the halo, whose own highlight is near white: the
// ellipses that cut it to its ring (hat_extract --ring) fall inside the soft
// glow it was painted with on white, so the hole's edges and part of its rim
// are a pale cream (about 255,235,190) round a gold ring (about 244,193,102),
// a light line against the sky. There the reference is the darkest quarter
// of the solid ring within 10 px (its gold, not its white highlight), and the
// rim blends into it over three pixels instead of being replaced.
//
// `--report` prints the measurement used before and after: of the visible
// edge pixels (alpha >= 8, within 3 px of transparency), how many are more
// than 40 levels of luminance lighter than the solid hat beside them, and the
// same count weighted by alpha (how visible the line is).
//
// Swift because this Mac has no numpy or PIL. Cover masks (`-cover*`) are
// alpha only and need nothing.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Img { var w: Int; var h: Int; var r: [Double]; var g: [Double]; var b: [Double]; var a: [Double] }

func load(_ path: String) -> Img {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
    let w = cg.width, h = cg.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var im = Img(w: w, h: h, r: .init(repeating: 0, count: w * h), g: .init(repeating: 0, count: w * h),
                 b: .init(repeating: 0, count: w * h), a: .init(repeating: 0, count: w * h))
    for i in 0..<(w * h) {
        let a = Double(raw[i * 4 + 3]); im.a[i] = a
        if a > 0 {
            im.r[i] = min(255, Double(raw[i * 4]) * 255 / a)
            im.g[i] = min(255, Double(raw[i * 4 + 1]) * 255 / a)
            im.b[i] = min(255, Double(raw[i * 4 + 2]) * 255 / a)
        }
    }
    return im
}

func save(_ im: Img, _ path: String, flattenOver bg: (Double, Double, Double)? = nil) {
    var raw = [UInt8](repeating: 0, count: im.w * im.h * 4)
    for i in 0..<(im.w * im.h) {
        let a = im.a[i] / 255
        if let bg {
            raw[i * 4] = UInt8((im.r[i] * a + bg.0 * (1 - a)).rounded())
            raw[i * 4 + 1] = UInt8((im.g[i] * a + bg.1 * (1 - a)).rounded())
            raw[i * 4 + 2] = UInt8((im.b[i] * a + bg.2 * (1 - a)).rounded())
            raw[i * 4 + 3] = 255
        } else {
            raw[i * 4] = UInt8((im.r[i] * a).rounded())
            raw[i * 4 + 1] = UInt8((im.g[i] * a).rounded())
            raw[i * 4 + 2] = UInt8((im.b[i] * a).rounded())
            raw[i * 4 + 3] = UInt8(im.a[i].rounded())
        }
    }
    let ctx = CGContext(data: &raw, width: im.w, height: im.h, bitsPerComponent: 8, bytesPerRow: im.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cg = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(path)") }
}

/// Chebyshev distance to the nearest (near-)transparent pixel, capped.
func distance(_ im: Img, cap: Int = 12) -> [Int] {
    let w = im.w, h = im.h
    var d = [Int](repeating: cap, count: w * h)
    var frontier: [Int] = []
    for i in 0..<(w * h) where im.a[i] < 8 { d[i] = 0; frontier.append(i) }
    var k = 0
    while !frontier.isEmpty && k < cap {
        k += 1
        var next: [Int] = []
        for i in frontier {
            let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                let j = yy * w + xx
                if d[j] > k { d[j] = k; next.append(j) }
            } }
        }
        frontier = next
    }
    // the image's own border counts as transparency
    for y in 0..<h { for x in 0..<w { d[y * w + x] = min(d[y * w + x], x + 1, y + 1, w - x, h - y) } }
    return d
}

func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.299 * r + 0.587 * g + 0.114 * b }

/// The solid hat nearest an edge pixel: alpha-weighted mean of pixels at
/// least 4 px inside, in the smallest radius that has some.
func reference(_ im: Img, _ d: [Int], _ x: Int, _ y: Int, skipPale: Bool = false) -> (Double, Double, Double)? {
    skipPale ? deepest(im, d, x, y) : nearest(im, d, x, y)
}

/// The alpha-weighted mean of the solid hat at least 4 px inside, in the
/// smallest radius that has some.
func nearest(_ im: Img, _ d: [Int], _ x: Int, _ y: Int) -> (Double, Double, Double)? {
    for rad in [4, 6, 8, 11] {
        var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0
        for dy in -rad...rad { for dx in -rad...rad {
            let xx = x + dx, yy = y + dy
            if xx < 0 || yy < 0 || xx >= im.w || yy >= im.h { continue }
            let j = yy * im.w + xx
            if d[j] >= 4 && im.a[j] >= 245 {
                let wgt = 1.0 / Double(1 + dx * dx + dy * dy)
                sr += im.r[j] * wgt; sg += im.g[j] * wgt; sb += im.b[j] * wgt; sw += wgt
            }
        } }
        if sw > 0 { return (sr / sw, sg / sw, sb / sw) }
    }
    return nil
}

/// For the halo: the mean of the darkest quarter of the solid ring within
/// 10 px, i.e. its gold rather than its white highlight.
func deepest(_ im: Img, _ d: [Int], _ x: Int, _ y: Int) -> (Double, Double, Double)? {
    var pts: [(Double, Int)] = []
    for dy in -10...10 { for dx in -10...10 {
        let xx = x + dx, yy = y + dy
        if xx < 0 || yy < 0 || xx >= im.w || yy >= im.h { continue }
        let j = yy * im.w + xx
        if d[j] >= 3 && im.a[j] >= 245 { pts.append((lum(im.r[j], im.g[j], im.b[j]), j)) }
    } }
    guard pts.count >= 8 else { return nil }
    pts.sort { $0.0 < $1.0 }
    let q = pts.prefix(max(1, pts.count / 4))
    let n = Double(q.count)
    return (q.map { im.r[$0.1] }.reduce(0, +) / n, q.map { im.g[$0.1] }.reduce(0, +) / n,
            q.map { im.b[$0.1] }.reduce(0, +) / n)
}

func report(_ im: Img, skipPale: Bool = false) -> (edge: Int, light: Int, weighted: Double) {
    let d = distance(im)
    var edge = 0, light = 0, weighted = 0.0
    for y in 0..<im.h { for x in 0..<im.w {
        let i = y * im.w + x
        guard im.a[i] >= 8, d[i] <= 3, let ref = reference(im, d, x, y, skipPale: skipPale) else { continue }
        edge += 1
        let diff = lum(im.r[i], im.g[i], im.b[i]) - lum(ref.0, ref.1, ref.2)
        if diff > 40 { light += 1; weighted += im.a[i] / 255 * diff / 255 }
    } }
    return (edge, light, weighted)
}

func defringe(_ im: Img, threshold: Double, skipPale: Bool) -> (Img, Int) {
    var out = im
    let d = distance(im)
    var changed = 0
    for y in 0..<im.h { for x in 0..<im.w {
        let i = y * im.w + x
        guard im.a[i] > 0, d[i] <= 3, let ref = reference(im, d, x, y, skipPale: skipPale) else { continue }
        let diff = lum(im.r[i], im.g[i], im.b[i]) - lum(ref.0, ref.1, ref.2)
        guard diff > threshold else { continue }
        // The halo's rim fades into its gold over three pixels; a paper
        // fringe is replaced outright.
        let t = skipPale ? [1.0, 1.0, 0.75, 0.45][d[i]] : 1.0
        out.r[i] = im.r[i] + (ref.0 - im.r[i]) * t
        out.g[i] = im.g[i] + (ref.1 - im.g[i]) * t
        out.b[i] = im.b[i] + (ref.2 - im.b[i]) * t
        changed += 1
    } }
    return (out, changed)
}

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--report" {
    for p in args.dropFirst(2) where p != "--skip-pale" {
        let r = report(load(p), skipPale: args.contains("--skip-pale"))
        print(String(format: "%@  edge %d  lighter %d (%.1f%%)  weighted %.1f",
                     (p as NSString).lastPathComponent, r.edge, r.light,
                     r.edge > 0 ? 100 * Double(r.light) / Double(r.edge) : 0, r.weighted))
    }
} else if args.count >= 7 && args[1] == "--composite" {
    save(load(args[2]), args[3], flattenOver: (Double(args[4])!, Double(args[5])!, Double(args[6])!))
} else if args.count >= 3 {
    var threshold = 18.0
    if let k = args.firstIndex(of: "--threshold"), k + 1 < args.count { threshold = Double(args[k + 1])! }
    let (out, n) = defringe(load(args[1]), threshold: threshold, skipPale: args.contains("--skip-pale"))
    save(out, args[2])
    print("\((args[2] as NSString).lastPathComponent): \(n) edge pixels recoloured")
} else {
    print("usage: hat_defringe [--report] in.png [out.png] [--threshold 18]")
}
