// Finds, and takes out, the white paper left in a cut-out (the companions,
// Otto's stills and bodies, anything drawn by an image model on white and cut).
//
//     swiftc -O tools/paper_check.swift -o /tmp/paper_check
//     /tmp/paper_check check in.png [--overlay out.png] [--verbose] [--scale s] [keeps]
//     /tmp/paper_check fix   in.png out.png [--scale s] [keeps]
//     keeps: --keep x,y,w,h:reason (left exactly as drawn)
//            --keep-strands x,y,w,h:reason (a stage-1 cobweb: strands and edges
//            kept, a paper patch caught between the strands still taken out)
//
// Distances are tuned on the 2x masters (1328 wide) and scale with the width;
// pass --scale for a crop (a rig body at 1x canvas is --scale 0.5).
// `check` prints "paper regions N (notches, pockets, px), fringe N px | what was
// kept and why"; the overlay paints paper magenta, fringe yellow and every
// kept pale region cyan, over grey. `fix` runs check, cleans, checks again.
//
// WHY (Melvin, 2026-11-13): "white in the enclosed corners of the dragon's
// tail curl, and a lot of white in the corners and between the feathers of
// the phoenix ... it looks really bad when you notice it." The companions'
// stages 2 to 7 were defringed with `otto_defringe --no-holes`, and the
// paper survived in three shapes:
//
// 1. NOTCHES. The model paints a soft warm light on the paper where it meets
//    the drawing, so the concave corners between two spikes or feathers come
//    out of the cut as opaque blobs of (255, 250, 214): whiter than the art
//    beside them and touching the outside.
// 2. POCKETS. Paper within 4 px of the outside but not touching it (between
//    two feathers that nearly meet), and on stage 1 the paper the cobweb was
//    drawn across, kept as an opaque white patch between the strands.
// 3. FRINGE. Edge pixels, opaque or soft, still carrying part of the page.
//
// THE RULE. A connected region of whitish pixels (darkest channel >= 196,
// spread <= 64, brightest >= 235) is PAPER unless:
//   - it falls in a --keep box (with its reason);
//   - it is an eye white or catch-light: it touches true black (< 50) or a
//     fifth or more of the drawing round it is dark (luma < 70, iris/pupil);
//   - it is more than 4 px from the outside (alpha < 128). Every interior
//     whitish region found on the companions was drawing (highlights, toe
//     beans, an eye white split by a lash, the tiger's forehead marking, the
//     red panda's face mask), and every paper region sat within 4 px of an
//     edge, except stage 1's cobweb patches, which --keep-strands catches;
//   - it sits inside pale drawing: its ring (the opaque, non-whitish pixels
//     3 to 7 px out, past the paper's own soft gradient) is 40% or more cream,
//     or under 30 levels darker than the region (cheek fur, the red panda's
//     white ear rims, the tiger's ruff), and that ring is big enough to judge;
//   - it is a thin stroke inside a --keep-strands box (a web strand).
// FRINGE is a pixel within 4 px of the outside that sits on the line between
// the solid art just inside it and the paper's tone with 15% or more paper,
// or is lighter than that art by more than 30 levels with the gain in its
// darkest channel (whitening, not a coloured rim light). Art that is itself
// pale (cream, white fur) is never un-mixed.
//
// THE FIX keeps every alpha of real drawing. Paper regions go (a darkest
// channel >= 196 can hold at most a quarter of any coloured art), the stepped
// cut is rounded to a 1 px soft edge, then every fringe pixel is un-mixed
// against the art just inside it and the paper's own warm tone (estimated from
// the paper regions; un-mixing against pure 255 left the warm page as a faint
// tinted film), its white share swapped for the art's colour. Three rounds,
// since clearing a notch exposes a new edge; faint specks left floating go.
//
// Swift because this Mac has no numpy or PIL.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Img { var w: Int; var h: Int; var px: [Double] }  // straight alpha, 0...255

func load(_ path: String) -> Img {
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
        let a = Double(raw[i * 4 + 3]); px[i * 4 + 3] = a
        for c in 0..<3 { px[i * 4 + c] = a > 0 ? min(255, Double(raw[i * 4 + c]) * 255 / a) : 0 }
    }
    return Img(w: w, h: h, px: px)
}

func save(_ img: Img, _ path: String) {
    var raw = [UInt8](repeating: 0, count: img.w * img.h * 4)
    for i in 0..<(img.w * img.h) {
        let a = max(0, min(255, img.px[i * 4 + 3].rounded()))
        raw[i * 4 + 3] = UInt8(a)
        for c in 0..<3 { raw[i * 4 + c] = UInt8(max(0, min(255, (img.px[i * 4 + c] * a / 255).rounded()))) }
    }
    let ctx = CGContext(data: &raw, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: arguments

var args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first, mode == "check" || mode == "fix" else {
    print("usage: paper_check check in.png [--overlay out.png] [--verbose] [--keep x,y,w,h:reason]...\n       paper_check fix in.png out.png [--keep ...]")
    exit(1)
}
args.removeFirst()
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
/// `--keep box:reason` keeps everything in the box as drawn. `--keep-strands
/// box:reason` (a stage-1 cobweb) keeps the box's edges and thin strokes as
/// drawn, but still takes out a paper blob caught inside it.
struct Keep { var x: Int, y: Int, w: Int, h: Int, reason: String, strands: Bool }
var keeps: [Keep] = []
for (flag, strands) in [("--keep", false), ("--keep-strands", true)] {
    while let k = option(flag) {
        let parts = k.split(separator: ":", maxSplits: 1)
        let n = parts[0].split(separator: ",").map { Int($0)! }
        keeps.append(Keep(x: n[0], y: n[1], w: n[2], h: n[3], reason: parts.count > 1 ? String(parts[1]) : "kept by hand", strands: strands))
    }
}
let overlayPath = option("--overlay")
let verbose = args.contains("--verbose"); args.removeAll { $0 == "--verbose" }
/// Scale of the art against the 2x masters (1328 wide): distances scale with it.
let scaleArg = option("--scale")
guard args.count >= (mode == "fix" ? 2 : 1) else { print("missing paths"); exit(1) }

var img = load(args[0])
let w = img.w, h = img.h, n = w * h
let s = scaleArg.map { Double($0)! } ?? max(0.25, Double(w) / 1328)
func sc(_ v: Double) -> Int { max(1, Int((v * s).rounded())) }

func a(_ i: Int) -> Double { img.px[i * 4 + 3] }
func rgb(_ i: Int) -> (Double, Double, Double) { (img.px[i * 4], img.px[i * 4 + 1], img.px[i * 4 + 2]) }
func luma(_ c: (Double, Double, Double)) -> Double { 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2 }
func lo(_ c: (Double, Double, Double)) -> Double { min(c.0, c.1, c.2) }
func hi(_ c: (Double, Double, Double)) -> Double { max(c.0, c.1, c.2) }
func inKeep(_ i: Int, strands: Bool? = nil) -> Keep? {
    let x = i % w, y = i / w
    return keeps.first { (strands == nil || $0.strands == strands!) && x >= $0.x && x < $0.x + $0.w && y >= $0.y && y < $0.y + $0.h }
}

/// Chessboard steps from any `seed` pixel, up to `limit`.
func steps(from seed: [Bool], limit: Int) -> [Int] {
    var d = [Int](repeating: Int.max, count: n)
    var q: [Int] = []; q.reserveCapacity(n / 4)
    for i in 0..<n where seed[i] { d[i] = 0; q.append(i) }
    var head = 0
    while head < q.count {
        let i = q[head]; head += 1
        guard d[i] < limit else { continue }
        let x = i % w, y = i / w
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
            let j = yy * w + xx
            if d[j] == Int.max { d[j] = d[i] + 1; q.append(j) }
        } }
    }
    return d
}

// MARK: regions of whitish pixels

struct Region {
    var pixels: [Int]
    var verdict: String      // "notch", "pocket", or a kept reason
    var paper: Bool
    var ring: (Double, Double, Double)
}

func whitish(_ i: Int) -> Bool {
    guard a(i) >= 16 else { return false }
    let c = rgb(i)
    return lo(c) >= 196 && hi(c) - lo(c) <= 64 && hi(c) >= 235
}

func regions() -> [Region] {
    var white = [Bool](repeating: false, count: n)
    for i in 0..<n { white[i] = whitish(i) }
    var label = [Int](repeating: -1, count: n)
    var stampNear = [Int](repeating: -1, count: n), stampRing = [Int](repeating: -1, count: n)
    // How far each pixel is from the outside (alpha below half).
    let outDist = steps(from: (0..<n).map { a($0) < 128 }, limit: sc(4) + 1)
    var out: [Region] = []
    for start in 0..<n where white[start] && label[start] < 0 {
        var comp = [start]; label[start] = start
        var k = 0
        while k < comp.count {
            let i = comp[k]; k += 1
            let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                let j = yy * w + xx
                if white[j] && label[j] < 0 { label[j] = start; comp.append(j) }
            } }
        }
        var touchesOut = false, touchesBlack = false
        let nearOut = comp.contains { outDist[$0] <= sc(4) }
        var minx = w, maxx = 0, miny = h, maxy = 0
        // The drawing that rings it: a band from 3 to 7 px out (2x master),
        // past the paper's own soft gradient, opaque and not whitish.
        var ringSet: [Int] = []
        let rNear = sc(2), rFar = sc(7)
        for i in comp {
            let x = i % w, y = i / w
            minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, y); maxy = max(maxy, y)
            for dy in -rNear...rNear { for dx in -rNear...rNear {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                let j = yy * w + xx
                stampNear[j] = start
                if abs(dx) <= 1 && abs(dy) <= 1 && a(j) < 128 && label[j] != start { touchesOut = true }
                if a(j) > 200 && hi(rgb(j)) < 50 { touchesBlack = true }
            } }
        }
        for i in comp {
            let x = i % w, y = i / w
            for dy in -rFar...rFar { for dx in -rFar...rFar {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                let j = yy * w + xx
                guard stampNear[j] != start, stampRing[j] != start else { continue }
                stampRing[j] = start
                if a(j) >= 250 && !white[j] { ringSet.append(j) }
            } }
        }
        var rr = 0.0, rg = 0.0, rb = 0.0, pale = 0, dark = 0
        var ringLumas: [Double] = []
        for j in ringSet {
            let c = rgb(j); rr += c.0; rg += c.1; rb += c.2
            ringLumas.append(luma(c))
            if lo(c) >= 175 { pale += 1 }
            if luma(c) < 70 { dark += 1 }
        }
        let darkShare = ringSet.isEmpty ? 0 : Double(dark) / Double(ringSet.count)
        // Texture: how far each pixel sits from its four neighbours, on
        // average. Paper is a smooth wash; fur and markings are strands.
        var rough = 0.0, roughN = 0
        for i in comp {
            let x = i % w, y = i / w
            guard x > 0, x < w - 1, y > 0, y < h - 1 else { continue }
            let nb = [i - 1, i + 1, i - w, i + w]
            guard nb.allSatisfy({ label[$0] == start }) else { continue }
            let m = nb.reduce(0.0) { $0 + luma(rgb($1)) } / 4
            rough += abs(luma(rgb(i)) - m); roughN += 1
        }
        rough = roughN > 0 ? rough / Double(roughN) : 0
        let rn = Double(max(1, ringSet.count))
        let ring = (rr / rn, rg / rn, rb / rn)
        ringLumas.sort()
        let ringLuma = ringLumas.isEmpty ? 0 : ringLumas[ringLumas.count / 2]
        let paleShare = ringSet.isEmpty ? 0 : Double(pale) / rn
        var cl = 0.0
        for i in comp { cl += luma(rgb(i)) }
        cl /= Double(comp.count)
        // A stroke: nothing of it survives one erosion (no pixel whose 3x3
        // is all in the region), and it is long.
        var core = 0
        for i in comp {
            let x = i % w, y = i / w
            var all = true
            for dy in -1...1 { for dx in -1...1 {
                let xx = x + dx, yy = y + dy
                if xx < 0 || xx >= w || yy < 0 || yy >= h || label[yy * w + xx] != start { all = false }
            } }
            if all { core += 1 }
        }
        let long = max(maxx - minx, maxy - miny) + 1
        let stroke = Double(core) <= Double(comp.count) * 0.08 && long >= sc(14)

        var verdict: String, paper = false
        if let k = inKeep(comp[0], strands: false) {
            verdict = "kept: \(k.reason)"
        } else if touchesBlack || darkShare >= 0.2 {
            verdict = "kept: eye white or catch-light (ringed by iris/pupil, dark \(Int(100 * darkShare))%)"
        } else if !stroke && cl - ringLuma >= 50 && inKeep(comp[0], strands: true) != nil {
            // Stage 1: the paper the cobweb was drawn across, kept as an
            // opaque white patch between the strands.
            paper = true
            verdict = "cobweb patch"
        } else if !nearOut {
            // Every paper region found on the companions (2026-11-13) sat
            // within 4 px of the outside; the interior ones were highlights,
            // toe beans, an eye white split by a lash, a forehead marking.
            verdict = "kept: inside the drawing, away from every edge (lift \(Int(cl - ringLuma)))"
        } else if Double(ringSet.count) >= max(12 * s * s, min(Double(comp.count) / 3, 200 * s * s)) && (paleShare >= 0.4 || cl - ringLuma < 30) {
            verdict = "kept: pale drawing (cream ring \(Int(100 * paleShare))%, lift \(Int(cl - ringLuma)))"
        } else if stroke, let k = inKeep(comp[0], strands: true) {
            verdict = "kept: \(k.reason) (thin strand)"
        } else {
            paper = true
            verdict = touchesOut ? "notch" : "pocket"
        }
        if verbose {
            print(String(format: "  %@ %5dpx at %d,%d %dx%d lift %.0f cream %.0f%% dark %.0f%% rough %.2f ring %d", verdict, comp.count,
                         minx, miny, maxx - minx + 1, maxy - miny + 1, cl - ringLuma, 100 * paleShare, 100 * darkShare, rough, ringSet.count))
        }
        out.append(Region(pixels: comp, verdict: verdict, paper: paper, ring: ring))
    }
    return out
}

// MARK: fringe

/// The solid art just inside each edge pixel, or nil.
func artInside(_ i: Int, depth: [Int], minDepth: Int, win: Int) -> (Double, Double, Double)? {
    let x = i % w, y = i / w
    for md in [minDepth, max(2, minDepth / 2), 1] {
        var f = (0.0, 0.0, 0.0), ws = 0.0
        for dy in -win...win { for dx in -win...win {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
            let j = yy * w + xx
            guard depth[j] != Int.max, depth[j] >= md, !whitish(j) else { continue }
            let wt = 1 / (1 + Double(dx * dx + dy * dy))
            let c = rgb(j); f.0 += c.0 * wt; f.1 += c.1 * wt; f.2 += c.2 * wt; ws += wt
        } }
        if ws > 0 { return (f.0 / ws, f.1 / ws, f.2 / ws) }
    }
    return nil
}

/// The page as the model painted it beside the drawing: a warm white, not
/// 255. Un-mixing against pure white left the warm paper as a faint tinted
/// film at a fifth of its alpha (a dark line on the night valley).
var paperTone = (255.0, 249.0, 234.0)

/// Share of art (vs paper) in `c` on the line art -> paper, and how far off the line it is.
func unmix(_ c: (Double, Double, Double), art f: (Double, Double, Double)) -> (t: Double, miss: Double)? {
    let P = paperTone
    let dr = P.0 - f.0, dg = P.1 - f.1, db = P.2 - f.2
    let dd = dr * dr + dg * dg + db * db
    guard dd > 45 * 45 else { return nil }    // the art itself is pale: nothing to un-mix
    let t = max(0, min(1, ((P.0 - c.0) * dr + (P.1 - c.1) * dg + (P.2 - c.2) * db) / dd))
    let mr = t * f.0 + (1 - t) * P.0, mg = t * f.1 + (1 - t) * P.1, mb = t * f.2 + (1 - t) * P.2
    let miss = ((c.0 - mr) * (c.0 - mr) + (c.1 - mg) * (c.1 - mg) + (c.2 - mb) * (c.2 - mb)).squareRoot()
    return (t, miss)
}

struct Fringe { var i: Int; var art: (Double, Double, Double); var t: Double; var onLine: Bool }

func fringe(keptMask: [Bool]) -> [Fringe] {
    let opaque = (0..<n).map { a($0) >= 250 }
    let depth = steps(from: opaque.map { !$0 }, limit: sc(10))
    // The edge is where the drawing falls below half alpha; every softer
    // pixel is itself edge (distance 0).
    let out = steps(from: (0..<n).map { a($0) < 128 }, limit: sc(4) + 1)
    var list: [Fringe] = []
    for i in 0..<n where a(i) >= 16 && out[i] <= sc(4) && !keptMask[i] {
        if inKeep(i) != nil { continue }
        let c = rgb(i)
        guard lo(c) >= 150 else { continue }
        guard let f = artInside(i, depth: depth.map { $0 == Int.max ? Int.max : $0 }, minDepth: sc(6), win: sc(8)) else { continue }
        guard lo(f) < 175 else { continue }   // pale art (cream, white fur): not paper
        if let u = unmix(c, art: f), u.miss < 30, u.t <= 0.85 {
            list.append(Fringe(i: i, art: f, t: u.t, onLine: true)); continue
        }
        if luma(c) - luma(f) > 30 && lo(c) - lo(f) > 30 {
            list.append(Fringe(i: i, art: f, t: 1, onLine: false))
        }
    }
    return list
}

// MARK: run

func analyse() -> (regions: [Region], fringe: [Fringe], kept: [Bool]) {
    let rs = regions()
    var kept = [Bool](repeating: false, count: n)
    for r in rs where !r.paper { for i in r.pixels { kept[i] = true } }
    var paperMask = [Bool](repeating: false, count: n)
    for r in rs where r.paper { for i in r.pixels { paperMask[i] = true } }
    let fr = fringe(keptMask: kept).filter { !paperMask[$0.i] }
    return (rs, fr, kept)
}

func summary(_ name: String, _ r: (regions: [Region], fringe: [Fringe], kept: [Bool])) -> String {
    let notches = r.regions.filter { $0.verdict == "notch" }
    let pockets = r.regions.filter { $0.paper && $0.verdict != "notch" }
    let paperPx = (notches + pockets).reduce(0) { $0 + $1.pixels.count }
    var keptReasons: [String: Int] = [:]
    for x in r.regions where !x.paper && x.pixels.count > 6 {
        let reason = x.verdict.components(separatedBy: " (").first ?? x.verdict
        keptReasons[reason, default: 0] += 1
    }
    let kr = keptReasons.sorted { $0.key < $1.key }.map { "\($0.value)x \($0.key)" }.joined(separator: "; ")
    return "\(name): paper regions \(notches.count + pockets.count) (\(notches.count) notches, \(pockets.count) pockets, \(paperPx)px), fringe \(r.fringe.count)px | \(kr)"
}

let name = (args[0] as NSString).lastPathComponent

if mode == "check" {
    let r = analyse()
    print(summary(name, r))
    if let o = overlayPath {
        // The image over mid grey, paper regions magenta, fringe yellow, kept pale regions cyan.
        var ov = Img(w: w, h: h, px: [Double](repeating: 0, count: n * 4))
        for i in 0..<n {
            let al = a(i) / 255
            for c in 0..<3 { ov.px[i * 4 + c] = img.px[i * 4 + c] * al + 70 * (1 - al) }
            ov.px[i * 4 + 3] = 255
        }
        func paint(_ i: Int, _ c: (Double, Double, Double)) {
            ov.px[i * 4] = c.0; ov.px[i * 4 + 1] = c.1; ov.px[i * 4 + 2] = c.2
        }
        for x in r.regions where !x.paper && x.pixels.count > 6 { for i in x.pixels { paint(i, (0, 200, 220)) } }
        for f in r.fringe { paint(f.i, (255, 230, 0)) }
        for x in r.regions where x.paper {
            for i in x.pixels {
                paint(i, (255, 0, 255))
                // a ring so a few pixels still show at a glance
                let xx = i % w, yy = i / w
                for d in [-3, 3] {
                    if xx + d >= 0 && xx + d < w { let j = yy * w + xx + d; if a(j) < 8 { paint(j, (255, 0, 255)) } }
                    if yy + d >= 0 && yy + d < h { let j = (yy + d) * w + xx; if a(j) < 8 { paint(j, (255, 0, 255)) } }
                }
            }
        }
        save(ov, o)
    }
    exit(0)
}

// fix: run up to three rounds, since clearing a pocket can expose new edges.
var before = analyse()
// The paper's own colour: the brighter half of every paper region's pixels.
do {
    var lum: [(Double, (Double, Double, Double))] = []
    for r in before.regions where r.paper { for i in r.pixels where a(i) >= 200 { let c = rgb(i); lum.append((luma(c), c)) } }
    if lum.count >= 20 {
        lum.sort { $0.0 > $1.0 }
        let top = lum.prefix(max(10, lum.count / 2))
        let k = Double(top.count)
        paperTone = (top.reduce(0) { $0 + $1.1.0 } / k, top.reduce(0) { $0 + $1.1.1 } / k, top.reduce(0) { $0 + $1.1.2 } / k)
    }
    print(String(format: "paper tone %.0f,%.0f,%.0f", paperTone.0, paperTone.1, paperTone.2))
}
print("before " + summary(name, before))
for round in 1...3 {
    let r = round == 1 ? before : analyse()
    if r.regions.allSatisfy({ !$0.paper }) && r.fringe.isEmpty { break }
    // 1. Paper regions go.
    var removed = [Bool](repeating: false, count: n)
    for reg in r.regions where reg.paper {
        // Every pixel of a paper region is page (darkest channel >= 196 can
        // carry at most a quarter of any coloured art): it goes, and the
        // fringe pass below gives the new edge its soft, un-mixed pixels
        // against the art just inside it. Un-mixing the region against the
        // average of its ring left a translucent lip of the wrong feather's
        // colour along every cut (2026-11-13).
        for i in reg.pixels { img.px[i * 4 + 3] = 0; removed[i] = true }
        // A cobweb patch is paper in shade as well as in light: the grey
        // part of the same page (darkest >= 190, neutral, within the cobweb
        // box, joined to the white part) goes with it.
        if reg.verdict == "cobweb patch" {
            var q = reg.pixels, head = 0
            var depth = [Int: Int](); for i in q { depth[i] = 0 }
            while head < q.count {
                let i = q[head]; head += 1
                guard depth[i]! < sc(20) else { continue }
                let x = i % w, y = i / w
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                    let j = yy * w + xx
                    guard !removed[j], a(j) >= 16, inKeep(j, strands: true) != nil else { continue }
                    let c = rgb(j)
                    guard lo(c) >= 190, hi(c) - lo(c) <= 45 else { continue }
                    removed[j] = true; img.px[j * 4 + 3] = 0; depth[j] = depth[i]! + 1; q.append(j)
                } }
            }
        }
    }
    // Islands: a speck of drawing left inside a hole the paper made (a
    // shadow in the page) goes too.
    do {
        var seen = [Bool](repeating: false, count: n)
        for st in 0..<n where !seen[st] && !removed[st] && a(st) >= 16 {
            var comp = [st]; seen[st] = true; var k = 0; var bordersHole = false; var big = false
            while k < comp.count {
                let i = comp[k]; k += 1
                if comp.count > sc(60) * 3 { big = true; break }
                let x = i % w, y = i / w
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                    let j = yy * w + xx
                    if removed[j] { bordersHole = true }
                    if !seen[j] && !removed[j] && a(j) >= 16 { seen[j] = true; comp.append(j) }
                } }
            }
            if big {
                // mark the rest of this large component seen without walking it again
                var q = comp, h2 = 0
                while h2 < q.count { let i = q[h2]; h2 += 1; let x = i % w, y = i / w
                    for dy in -1...1 { for dx in -1...1 { let xx = x + dx, yy = y + dy
                        guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                        let j = yy * w + xx
                        if !seen[j] && !removed[j] && a(j) >= 16 { seen[j] = true; q.append(j) } } } }
                continue
            }
            if bordersHole && comp.count <= sc(60) * 3 { for i in comp { img.px[i * 4 + 3] = 0; removed[i] = true } }
        }
    }
    // The cut follows the paper's threshold contour, so it steps. Round it:
    // a kept pixel touching a removed one keeps at most the share of its
    // 3x3 that is still drawing (a soft 1 px edge), never more alpha than it had.
    var soft: [(Int, Double)] = []
    for i in 0..<n where !removed[i] && a(i) > 0 {
        let x = i % w, y = i / w
        var touch = false, keep = 0, tot = 0
        for dy in -1...1 { for dx in -1...1 {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
            let j = yy * w + xx
            tot += 1
            if removed[j] { touch = true } else if a(j) >= 128 { keep += 1 }
        } }
        if touch { soft.append((i, min(a(i), 255 * Double(keep) / Double(tot)))) }
    }
    for (i, al) in soft { img.px[i * 4 + 3] = al }
    // 2 and 3. Fringe, recomputed on the cleared image.
    let fr = analyse().fringe
    for f in fr {
        let i = f.i, c = rgb(i)
        if f.onLine {
            let t = f.t < 0.06 ? 0 : f.t
            img.px[i * 4 + 3] = a(i) * t
            let ff = [f.art.0, f.art.1, f.art.2], cc = [c.0, c.1, c.2], pp = [paperTone.0, paperTone.1, paperTone.2]
            if t > 0 { for k in 0..<3 { img.px[i * 4 + k] = max(0, min(255, cc[k] + (1 - t) * (ff[k] - pp[k]))) } }
        } else {
            img.px[i * 4] = f.art.0; img.px[i * 4 + 1] = f.art.1; img.px[i * 4 + 2] = f.art.2
        }
    }
}
// Specks: anything faint that no longer touches the drawing.
let solid = (0..<n).map { a($0) >= 40 }
let near = steps(from: solid, limit: 2)
for i in 0..<n where a(i) > 0 && a(i) < 40 && near[i] > 1 { img.px[i * 4 + 3] = 0 }
save(img, args[1])
print("after  " + summary(name, analyse()))
