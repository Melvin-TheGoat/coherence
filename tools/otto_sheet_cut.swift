// Cuts a sheet of Ottos on white into one transparent PNG each (2026-10-06,
// the blocker's thirteen Ottos). Finds each figure by itself (rows of ink,
// then columns of ink inside each row, gaps under `merge` px joined so a
// sparkle stays with its Otto), then takes alpha as the larger of Apple's
// subject mask (keeps the cream belly and eye whites solid where they touch
// the paper) and the ink's own darkness against white (keeps sparkles, a
// sweat drop, a glow). Colour is un-mixed from white by that alpha, so edges
// carry no white fringe.
//
//   swiftc -O tools/otto_sheet_cut.swift -o /tmp/otto_sheet_cut
//   /tmp/otto_sheet_cut sheet.png outdir [pad]
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

let a = CommandLine.arguments
let src = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!, 0, nil)!
let outDir = a[2]
let pad = a.count > 3 ? Int(a[3])! : 14
let W = src.width, H = src.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: W, height: H))
func ink(_ x: Int, _ y: Int) -> Bool { let i = (y * W + x) * 4; return min(px[i], px[i+1], px[i+2]) < 232 }

func runs(_ counts: [Int], minCount: Int, merge: Int) -> [(Int, Int)] {
    var out: [(Int, Int)] = []; var s = -1
    for (i, c) in counts.enumerated() {
        if c >= minCount { if s < 0 { s = i } } else if s >= 0 { out.append((s, i - 1)); s = -1 }
    }
    if s >= 0 { out.append((s, counts.count - 1)) }
    var merged: [(Int, Int)] = []
    for r in out { if let l = merged.last, r.0 - l.1 < merge { merged[merged.count - 1].1 = r.1 } else { merged.append(r) } }
    return merged
}
let rowCounts = (0..<H).map { y in (0..<W).reduce(0) { $0 + (ink($1, y) ? 1 : 0) } }
let rows = runs(rowCounts, minCount: 3, merge: 30).filter { $0.1 - $0.0 > 80 }
var boxes: [(Int, Int, Int, Int)] = []
for (y0, y1) in rows {
    let colCounts = (0..<W).map { x in (y0...y1).reduce(0) { $0 + (ink(x, $1) ? 1 : 0) } }
    // Tight runs, then anything narrow (a sparkle, a sweat drop) joins the
    // nearest figure, so two Ottos close together never merge.
    var cols = runs(colCounts, minCount: 1, merge: 8)
    var figs = cols.filter { $0.1 - $0.0 > 90 }
    for bit in cols where bit.1 - bit.0 <= 90 {
        guard let k = figs.indices.min(by: { i, j in
            min(abs(bit.0 - figs[i].1), abs(figs[i].0 - bit.1)) < min(abs(bit.0 - figs[j].1), abs(figs[j].0 - bit.1)) }) else { continue }
        figs[k] = (min(figs[k].0, bit.0), max(figs[k].1, bit.1))
    }
    cols = figs
    for (x0, x1) in cols {
        boxes.append((max(0, x0 - pad), max(0, y0 - pad), min(W - 1, x1 + pad), min(H - 1, y1 + pad)))
    }
}
print("figures:", boxes.count)
let cictx = CIContext()
for (n, b) in boxes.enumerated() {
    let (x0, y0, x1, y1) = b
    let cw = x1 - x0 + 1, ch = y1 - y0 + 1
    let crop = src.cropping(to: CGRect(x: x0, y: y0, width: cw, height: ch))!
    // Subject mask at crop size.
    var mask = [Float](repeating: 0, count: cw * ch)
    let req = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: crop)
    if (try? handler.perform([req])) != nil, let obs = req.results?.first,
       let buf = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) {
        let ci = CIImage(cvPixelBuffer: buf)
        var m = [Float](repeating: 0, count: cw * ch)
        cictx.render(ci, toBitmap: &m, rowBytes: cw * 4, bounds: CGRect(x: 0, y: 0, width: cw, height: ch),
                     format: .Rf, colorSpace: nil)
        mask = m
    }
    // Paper the edge can reach: near white, or the near-white yellow of a
    // painted glow. Anything it cannot reach is Otto and stays solid, which
    // covers what the subject mask misses (a whole body behind a camera, a
    // bright cheek highlight).
    var reach = [Bool](repeating: false, count: cw * ch)
    func paper(_ x: Int, _ y: Int) -> Bool {
        let i = ((y0 + y) * W + (x0 + x)) * 4
        let r = Int(px[i]), g = Int(px[i+1]), bl = Int(px[i+2])
        return min(r, g, bl) >= 228 || (r >= 244 && g >= 232 && bl >= 150)
    }
    var stack: [Int] = []
    for x in 0..<cw { stack.append(x); stack.append((ch - 1) * cw + x) }
    for y in 0..<ch { stack.append(y * cw); stack.append(y * cw + cw - 1) }
    while let k = stack.popLast() {
        if reach[k] { continue }
        let x = k % cw, y = k / cw
        guard paper(x, y) else { continue }
        reach[k] = true
        if x > 0 { stack.append(k - 1) }; if x < cw - 1 { stack.append(k + 1) }
        if y > 0 { stack.append(k - cw) }; if y < ch - 1 { stack.append(k + cw) }
    }
    // Grow "reachable" by one pixel so the antialiased rim is un-mixed too.
    var near = reach
    for y in 0..<ch { for x in 0..<cw where !reach[y * cw + x] {
        if (x > 0 && reach[y*cw+x-1]) || (x < cw-1 && reach[y*cw+x+1]) || (y > 0 && reach[(y-1)*cw+x]) || (y < ch-1 && reach[(y+1)*cw+x]) { near[y*cw+x] = true }
    }}
    var out = [UInt8](repeating: 0, count: cw * ch * 4)
    for y in 0..<ch { for x in 0..<cw {
        let si = ((y0 + y) * W + (x0 + x)) * 4
        let r = Double(px[si]), g = Double(px[si+1]), bl = Double(px[si+2])
        let dark = (255 - min(r, g, bl)) / 255
        let inkA = max(0, (dark - 0.03) / 0.97)
        let mv = Double(mask[y * cw + x])  // render(toBitmap:) rows are top-down
        let al = near[y * cw + x] ? min(1, max(mv, inkA)) : 1
        let oi = (y * cw + x) * 4
        if al < 0.004 { continue }
        func un(_ c: Double) -> UInt8 { UInt8(max(0, min(255, (c - 255 * (1 - al)) / al)).rounded()) }
        // premultiplied out
        out[oi] = UInt8((Double(un(r)) * al).rounded()); out[oi+1] = UInt8((Double(un(g)) * al).rounded())
        out[oi+2] = UInt8((Double(un(bl)) * al).rounded()); out[oi+3] = UInt8((al * 255).rounded())
    }}
    let oc = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let path = "\(outDir)/otto-\(n + 1).png"
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, oc.makeImage()!, nil); CGImageDestinationFinalize(d)
    print(n + 1, "box", x0, y0, cw, ch)
}
