// Lifts a glass thing off a black background and keeps it see-through
// (Melvin, 2026-10-26: the Astronaut Helmet as "one of those actual glass
// domes around his head"). Every other hat is generated ON Otto and cut back
// out by hat_extract.swift, but glass over his face cannot be cut out that
// way: what shows through it is his face as the generator redrew it, which
// would be baked into the hat and sit over a different face at every look.
// So the dome is generated empty, on black, and here:
//
//   1. Glass is un-composited from black. A pixel of glass on black is only
//      the light the glass adds, so its alpha is its brightest channel and
//      its colour that light at full strength. Drawn over him, it adds the
//      same highlights and his face shows through.
//   2. The collar is opaque: in each column, the solid colour from the
//      bottom of the picture up to the dome's black inside, kept at full
//      strength inside its edge, with no glass under it.
//   3. The dome's outline above the collar is fitted with a circle, and the
//      box printed puts that circle at --centre and --radius in Otto's
//      664 x 744 canvas, the units `HatArt.placement` is in.
//
//   swiftc -O -o /tmp/glass_extract tools/glass_extract.swift
//   /tmp/glass_extract dome.png out.png --centre 330.5,185 --radius 205
//
// Options: --gain G (alpha x G, for highlights too faint over his fur),
// --tint A (a faint sky-blue film of alpha A inside the dome, so the glass
// reads where the render was pure black), --floor F (render black, 0..255).
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 3 else { print("glass_extract dome.png out.png [--centre x,y --radius r]"); exit(1) }
func opt(_ name: String) -> String? {
    a.firstIndex(of: name).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
}
let gain = opt("--gain").flatMap(Double.init) ?? 1
let tint = opt("--tint").flatMap(Double.init) ?? 0
let floorV = opt("--floor").flatMap(Double.init) ?? 10
let centre = opt("--centre").map { $0.split(separator: ",").compactMap { Double($0) } } ?? [330.5, 185]
let radius = opt("--radius").flatMap(Double.init) ?? 205

let img = NSImage(contentsOfFile: a[1])!
var rect = CGRect(origin: .zero, size: img.size)
let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let W = cg.width, H = cg.height
var px = [UInt8](repeating: 0, count: W * H * 4)
CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    .draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
// Row 0 is the TOP.
func rgb(_ i: Int) -> (Double, Double, Double) {
    (Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2]))
}
let lum = (0..<(W * H)).map { i -> Double in let c = rgb(i); return max(c.0, c.1, c.2) }

// MARK: Glass, un-composited from black.
var alpha = [Double](repeating: 0, count: W * H)
var prem = [(Double, Double, Double)](repeating: (0, 0, 0), count: W * H)
for i in 0..<(W * H) {
    let c = rgb(i)
    func lift(_ v: Double) -> Double { max(0, v - floorV) * 255 / (255 - floorV) }
    let l = (lift(c.0), lift(c.1), lift(c.2))
    let al = max(l.0, l.1, l.2) / 255
    let g = min(1, al * gain)
    // Premultiplied colour keeps the light; scaling alpha by the gain keeps
    // its hue and brightens what it adds.
    let k = al > 0 ? g / al : 0
    alpha[i] = g
    prem[i] = (min(255, l.0 * k), min(255, l.1 * k), min(255, l.2 * k))
}

// MARK: The object.
var minX = W, maxX = -1, minY = H, maxY = -1
for y in 0..<H { for x in 0..<W where alpha[y * W + x] > 0.06 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
guard maxX > minX else { print("nothing on the black"); exit(1) }
let midY = (minY + maxY) / 2

// MARK: The collar: in each column, from the object's bottom up through
// solid colour. Above the collar sits the dome's black inside (or the black
// beside it), which stops the climb; the dome's glowing rim touches the
// collar's ends, so a bright-piece search took the whole dome with it.
var collar = [Bool](repeating: false, count: W * H)
var tops = [Int](repeating: -1, count: W)
let maxClimb = Int(Double(maxY - minY) * 0.45)
for x in minX...maxX {
    var y = maxY
    while y > midY, lum[y * W + x] <= 60 { y -= 1 }
    // Only columns whose lowest lit pixel is down where the collar ends: the
    // dome's glowing rim also lights columns beside the collar, much higher
    // up, and climbing it made a strip of rim opaque.
    guard y > max(midY, maxY - Int(Double(maxY - minY) * 0.2)) else { continue }
    let bottom = y
    while y > bottom - maxClimb, lum[(y - 1) * W + x] > 45 { y -= 1 }
    tops[x] = y
}
// The collar's top is one smooth curve, fitted (a parabola) to the middle
// of the collar, where the dome's black inside sits right above it and every
// climb stops on the edge. Near its ends the dome's lit rim comes down onto
// the collar and the climb runs up it; those columns take the curve, and no
// column's top is above it. Without this the ends of the collar carried a
// block of rim drawn opaque, with a hard vertical seam beside it.
var smoothTops = tops
do {
    let cols = (minX...maxX).filter { tops[$0] >= 0 }
    if cols.count > 20 {
        let span = cols.last! - cols.first!
        let mid = cols.filter { $0 >= cols.first! + span / 5 && $0 <= cols.last! - span / 5 }
        var sums = [Double](repeating: 0, count: 7)   // x^0..x^4 and the y terms
        var sy = [Double](repeating: 0, count: 3)
        let c0 = Double(cols.first! + cols.last!) / 2, sc = Double(max(1, span)) / 2
        for x in mid {
            let u = (Double(x) - c0) / sc, y = Double(tops[x])
            var pw = 1.0
            for k in 0..<5 { sums[k] += pw; pw *= u }
            sy[0] += y; sy[1] += y * u; sy[2] += y * u * u
        }
        var m = [[sums[0], sums[1], sums[2], sy[0]], [sums[1], sums[2], sums[3], sy[1]], [sums[2], sums[3], sums[4], sy[2]]]
        for c in 0..<3 {
            let p = (c..<3).max { abs(m[$0][c]) < abs(m[$1][c]) }!
            m.swapAt(c, p)
            for r in 0..<3 where r != c {
                let f = m[r][c] / m[c][c]
                for k in c..<4 { m[r][k] -= f * m[c][k] }
            }
        }
        let q = (m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2])
        for x in cols {
            let u = (Double(x) - c0) / sc
            let curve = Int((q.0 + q.1 * u + q.2 * u * u).rounded())
            smoothTops[x] = max(tops[x], curve)
        }
    }
}
var collarTop = maxY, cx0 = W, cx1 = -1
for x in minX...maxX where smoothTops[x] >= 0 {
    var y = maxY
    while y > midY, lum[y * W + x] <= 60 { y -= 1 }
    // At the collar's rounded ends a neighbour's top can sit below this
    // column's bottom; such a column is past the end of the collar.
    guard smoothTops[x] <= y else { continue }
    for yy in smoothTops[x]...y { collar[yy * W + x] = true }
    collarTop = min(collarTop, smoothTops[x]); cx0 = min(cx0, x); cx1 = max(cx1, x)
}
print("collar: x \(cx0)...\(cx1), top \(collarTop)")
// Full strength inside the collar. Its outermost two pixels are the render's
// own antialiasing against black, so they are un-mixed from black: alpha is
// the pixel's brightness against the collar's just inside it. Drawn opaque,
// they were a dark hairline round the collar.
var cover = [Double](repeating: 0, count: W * H)
var edgeLight = [Bool](repeating: false, count: W * H)
do {
    var inner = collar
    for _ in 0..<2 {
        let was = inner
        for y in 0..<H { for x in 0..<W where was[y * W + x] {
            let i = y * W + x
            if x == 0 || y == 0 || x == W - 1 || y == H - 1 || !was[i - 1] || !was[i + 1] || !was[i - W] || !was[i + W] {
                inner[i] = false
            }
        } }
    }
    for i in 0..<(W * H) where collar[i] {
        if inner[i] { cover[i] = 1; continue }
        let x = i % W, y = i / W
        var ref = 0.0
        for oy in -4...4 { for ox in -4...4 {
            let xx = x + ox, yy = y + oy
            guard xx >= 0, xx < W, yy >= 0, yy < H, inner[yy * W + xx] else { continue }
            ref = max(ref, lum[yy * W + xx])
        } }
        cover[i] = ref > 0 ? min(1, lum[i] / ref) : 1
        edgeLight[i] = ref > 0
    }
}

// MARK: The dome's circle, from its outline above the collar.
var pts: [(Double, Double)] = []
for y in minY..<max(minY + 1, collarTop - 8) {
    var l = -1, r = -1
    for x in 0..<W where alpha[y * W + x] > 0.15 { if l < 0 { l = x }; r = x }
    if l >= 0, r - l > 20 { pts.append((Double(l), Double(y))); pts.append((Double(r), Double(y))) }
}
// Kasa fit: x^2 + y^2 + D x + E y + F = 0.
var m = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 3)
for (x, y) in pts {
    let row = [x, y, 1.0], rhs = -(x * x + y * y)
    for i in 0..<3 { for j in 0..<3 { m[i][j] += row[i] * row[j] }; m[i][3] += row[i] * rhs }
}
for c in 0..<3 {
    let p = (c..<3).max { abs(m[$0][c]) < abs(m[$1][c]) }!
    m.swapAt(c, p)
    for r in 0..<3 where r != c {
        let f = m[r][c] / m[c][c]
        for k in c..<4 { m[r][k] -= f * m[c][k] }
    }
}
let D = m[0][3] / m[0][0], E = m[1][3] / m[1][1], F = m[2][3] / m[2][2]
let ccx = -D / 2, ccy = -E / 2, cr = (ccx * ccx + ccy * ccy - F).squareRoot()
print(String(format: "dome circle: centre (%.1f, %.1f) radius %.1f from %d outline points", ccx, ccy, cr, pts.count))

// MARK: Compose and crop.
// Two layers: the collar (opaque, inside its soft edge) and the glass (cut
// away under the collar, since what the render shows there is collar).
var collarL = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: W * H)
var glassL = collarL
for y in 0..<H { for x in 0..<W {
    let i = y * W + x
    let k = cover[i]
    let c = rgb(i)
    // An un-mixed edge pixel over black already IS its colour times its
    // alpha.
    collarL[i] = edgeLight[i] ? (c.0, c.1, c.2, k) : (k * c.0, k * c.1, k * c.2, k)
    // The film: inside the circle, above the collar.
    let dx = Double(x) - ccx, dy = Double(y) - ccy
    let film = (dx * dx + dy * dy < cr * cr) ? tint : 0
    var al = alpha[i], p = prem[i]
    if film > 0 {
        // Light over a pale blue film, both over his face.
        let fc = (200.0, 226.0, 255.0)
        p = (p.0 + fc.0 * film * (1 - al), p.1 + fc.1 * film * (1 - al), p.2 + fc.2 * film * (1 - al))
        al = al + film * (1 - al)
    }
    glassL[i] = ((1 - k) * p.0, (1 - k) * p.1, (1 - k) * p.2, (1 - k) * al)
} }
// Under the collar there is no glass at all, its un-mixed edge included:
// what the render shows there is collar, and taken as glass too it drew a
// faint white outline of the collar.
for i in 0..<(W * H) where collar[i] { glassL[i] = (0, 0, 0, 0) }
var finalP = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: W * H)
var fx0 = W, fx1 = -1, fy0 = H, fy1 = -1
for i in 0..<(W * H) {
    let c = collarL[i], g = glassL[i]
    let f = (c.0 + (1 - c.3) * g.0, c.1 + (1 - c.3) * g.1, c.2 + (1 - c.3) * g.2, c.3 + (1 - c.3) * g.3)
    finalP[i] = f
    if f.3 > 0.02 { fx0 = min(fx0, i % W); fx1 = max(fx1, i % W); fy0 = min(fy0, i / W); fy1 = max(fy1, i / W) }
}
let pad = 4
let x0 = max(0, fx0 - pad), x1 = min(W - 1, fx1 + pad)
let y0 = max(0, fy0 - pad), y1 = min(H - 1, fy1 + pad)
let ow = x1 - x0 + 1, oh = y1 - y0 + 1
var outPx = [UInt8](repeating: 0, count: ow * oh * 4)
for y in y0...y1 { for x in x0...x1 {
    let f = finalP[y * W + x]
    let o = ((y - y0) * ow + (x - x0)) * 4
    outPx[o] = UInt8(min(255, max(0, f.0)).rounded())
    outPx[o + 1] = UInt8(min(255, max(0, f.1)).rounded())
    outPx[o + 2] = UInt8(min(255, max(0, f.2)).rounded())
    outPx[o + 3] = UInt8(min(255, max(0, f.3 * 255)).rounded())
} }
let ctx = CGContext(data: &outPx, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))

// MARK: Where it sits on him.
let k = radius / cr
let bx = centre[0] - (ccx - Double(x0)) * k, by = centre[1] - (ccy - Double(y0)) * k
print(String(format: "%d x %d | canvas box x=%.1f y=%.1f w=%.1f h=%.1f", ow, oh, bx, by, Double(ow) * k, Double(oh) * k))
