// Cuts sprites out of a sheet drawn on white.
//
//     swiftc -O tools/sprite_cut.swift -o /tmp/sprite_cut
//     /tmp/sprite_cut sheet.png out-dir name:mode:x0,y0,x1,y1 [name:mode:... ]
//     /tmp/sprite_cut sheet.png out-dir --row A:solid:y0,y1:x0,x1,x2,x3,x4
//
// Two modes, because a sheet mixes two kinds of thing:
//   solid  a creature with light parts touching the paper (a cream belly, a
//          beige wing). The paper is FLOODED away from the region's border
//          through near-white pixels, so a light part that is not paper
//          stays opaque; only pixels within 2 px of the paper are
//          un-composited, which keeps the antialiased edge.
//   light  a glow or a halo drawn as light on white (the mandala). Every
//          pixel is un-composited off the white ("colour to alpha"), so it
//          stays translucent light over any background.
//
// `--row` cuts one row of an animation strip: the frames between the x
// cuts, all cropped to the SAME box (the union of the row), so the body sits
// in the same place in every frame and the flap does not jitter.
//
// Swift because this Mac has no numpy or PIL. Written for Otto's bugs, the
// birds and the grasshopper (2026-09-23).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Img { var w: Int; var h: Int; var px: [UInt8] }

func load(_ path: String) -> Img {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Img(w: w, h: h, px: px)
}

func save(_ w: Int, _ h: Int, _ straight: [UInt8], _ path: String) {
    var pre = straight
    for i in stride(from: 0, to: pre.count, by: 4) {
        let a = Int(pre[i + 3])
        for c in 0..<3 { pre[i + c] = UInt8((Int(pre[i + c]) * a + 127) / 255) }
    }
    let ctx = CGContext(data: &pre, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(d)
}

let args = Array(CommandLine.arguments.dropFirst())
let img = load(args[0])
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// Straight RGBA of a region, matted per mode.
func matte(x0: Int, y0: Int, x1: Int, y1: Int, light: Bool) -> (w: Int, h: Int, px: [UInt8]) {
    let w = x1 - x0, h = y1 - y0
    var out = [UInt8](repeating: 0, count: w * h * 4)
    func src(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let o = ((y0 + y) * img.w + (x0 + x)) * 4
        return (Int(img.px[o]), Int(img.px[o + 1]), Int(img.px[o + 2]))
    }
    func c2a(_ r: Int, _ g: Int, _ b: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let a = Double(255 - min(r, g, b)) / 255
        if a < 2.0 / 255 { return (0, 0, 0, 0) }
        func un(_ c: Int) -> UInt8 { UInt8(max(0, min(255, ((Double(c) - 255 * (1 - a)) / a).rounded()))) }
        return (un(r), un(g), un(b), UInt8((a * 255).rounded()))
    }
    if light {
        for y in 0..<h { for x in 0..<w {
            let (r, g, b) = src(x, y); let o = (y * w + x) * 4
            let p = c2a(r, g, b); out[o] = p.0; out[o + 1] = p.1; out[o + 2] = p.2; out[o + 3] = p.3
        } }
        return (w, h, out)
    }
    // Flood the paper in from the region's border.
    var bg = [Bool](repeating: false, count: w * h)
    func paper(_ i: Int) -> Bool {
        let (r, g, b) = src(i % w, i / w)
        return min(r, g, b) >= 236 && max(r, g, b) - min(r, g, b) <= 16
    }
    var stack: [Int] = []
    func seed(_ i: Int) { if !bg[i] && paper(i) { bg[i] = true; stack.append(i) } }
    for x in 0..<w { seed(x); seed((h - 1) * w + x) }
    for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
    while let i = stack.popLast() {
        let x = i % w, y = i / w
        if x > 0 { seed(i - 1) }; if x < w - 1 { seed(i + 1) }
        if y > 0 { seed(i - w) }; if y < h - 1 { seed(i + w) }
    }
    // Distance (up to 2) from the paper, for the edge.
    for y in 0..<h { for x in 0..<w {
        let i = y * w + x, o = i * 4
        if bg[i] { continue }
        var nearPaper = false
        for dy in -2...2 { for dx in -2...2 {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < w, ny < h, bg[ny * w + nx] { nearPaper = true }
        } }
        let (r, g, b) = src(x, y)
        if nearPaper {
            let p = c2a(r, g, b)
            // An edge pixel darker than the paper by a lot is simply opaque.
            if p.3 > 200 { out[o] = UInt8(r); out[o + 1] = UInt8(g); out[o + 2] = UInt8(b); out[o + 3] = 255 }
            else { out[o] = p.0; out[o + 1] = p.1; out[o + 2] = p.2; out[o + 3] = p.3 }
        } else {
            out[o] = UInt8(r); out[o + 1] = UInt8(g); out[o + 2] = UInt8(b); out[o + 3] = 255
        }
    } }
    return (w, h, out)
}

func bbox(_ w: Int, _ h: Int, _ px: [UInt8]) -> (Int, Int, Int, Int)? {
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 6 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    return x1 < 0 ? nil : (x0, y0, x1, y1)
}

func crop(_ w: Int, _ px: [UInt8], _ b: (Int, Int, Int, Int), margin: Int = 3) -> (Int, Int, [UInt8]) {
    let (bx0, by0, bx1, by1) = b
    let cx0 = bx0 - margin, cy0 = by0 - margin
    let cw = bx1 - bx0 + 1 + 2 * margin, ch = by1 - by0 + 1 + 2 * margin
    var out = [UInt8](repeating: 0, count: cw * ch * 4)
    let h = px.count / 4 / w
    for y in 0..<ch { for x in 0..<cw {
        let sx = cx0 + x, sy = cy0 + y
        guard sx >= 0, sy >= 0, sx < w, sy < h else { continue }
        for c in 0..<4 { out[(y * cw + x) * 4 + c] = px[(sy * w + sx) * 4 + c] }
    } }
    return (cw, ch, out)
}

var i = 2
while i < args.count {
    if args[i] == "--frames" {
        // name:mode:cellWidth:x0,y0,x1,y1;x0,y0,x1,y1;...  Each frame is matted
        // in its own region (so a wing from the row below never gets in), and
        // all are cropped to one box measured from their CELL's left edge and
        // the sheet's top, since the sheet draws every frame at the same spot
        // of an equal-width cell.
        let parts = args[i + 1].split(separator: ":").map(String.init)
        // cell width, or 0 to align every frame on its RIGHTMOST pixel (a
        // bird facing right keeps its beak where it is while its wings move,
        // and the sheet's columns are not an even grid).
        let name = parts[0], light = parts[1] == "light", cell = Int(parts[2])!
        let regions = parts[3].split(separator: ";").map { $0.split(separator: ",").compactMap { Int($0) } }
        var mats: [(r: [Int], w: Int, h: Int, px: [UInt8])] = []
        var anchors: [Int] = []
        var union: (Int, Int, Int, Int)? = nil
        for r in regions {
            let m = matte(x0: r[0], y0: r[1], x1: r[2], y1: r[3], light: light)
            mats.append((r, m.w, m.h, m.px))
            if let b = bbox(m.w, m.h, m.px) {
                let ox = cell > 0 ? r[0] - (r[0] / cell) * cell : -b.2   // region left, from its anchor
                anchors.append(ox)
                let g = (b.0 + ox, b.1 + r[1], b.2 + ox, b.3 + r[1])
                union = union.map { (min($0.0, g.0), min($0.1, g.1), max($0.2, g.2), max($0.3, g.3)) } ?? g
            }
        }
        let u = union!
        let margin = 3
        let cw = u.2 - u.0 + 1 + 2 * margin, ch = u.3 - u.1 + 1 + 2 * margin
        for (f, m) in mats.enumerated() {
            var out = [UInt8](repeating: 0, count: cw * ch * 4)
            let ox = anchors[f]
            for y in 0..<ch { for x in 0..<cw {
                // back to this frame's region-local pixel
                let lx = x + u.0 - margin - ox, ly = y + u.1 - margin - m.r[1]
                guard lx >= 0, ly >= 0, lx < m.w, ly < m.h else { continue }
                for c in 0..<4 { out[(y * cw + x) * 4 + c] = m.px[(ly * m.w + lx) * 4 + c] }
            } }
            save(cw, ch, out, (outDir as NSString).appendingPathComponent("\(name)\(f + 1).png"))
            print("\(name)\(f + 1): \(cw)x\(ch)")
        }
        i += 2
    } else if args[i] == "--row" {
        // name:mode:y0,y1:x0,x1,...
        let parts = args[i + 1].split(separator: ":").map(String.init)
        let name = parts[0], light = parts[1] == "light"
        let ys = parts[2].split(separator: ",").compactMap { Int($0) }
        let xs = parts[3].split(separator: ",").compactMap { Int($0) }
        var frames: [(Int, Int, [UInt8])] = []
        var union: (Int, Int, Int, Int)? = nil
        for f in 0..<(xs.count - 1) {
            let m = matte(x0: xs[f], y0: ys[0], x1: xs[f + 1], y1: ys[1], light: light)
            frames.append((m.w, m.h, m.px))
            if let b = bbox(m.w, m.h, m.px) {
                union = union.map { (min($0.0, b.0), min($0.1, b.1), max($0.2, b.2), max($0.3, b.3)) } ?? b
            }
        }
        for (f, fr) in frames.enumerated() {
            let (cw, ch, px) = crop(fr.0, fr.2, union!)
            save(cw, ch, px, (outDir as NSString).appendingPathComponent("\(name)\(f + 1).png"))
            print("\(name)\(f + 1): \(cw)x\(ch)")
        }
        i += 2
    } else {
        // name:mode:x0,y0,x1,y1
        let parts = args[i].split(separator: ":").map(String.init)
        let r = parts[2].split(separator: ",").compactMap { Int($0) }
        let m = matte(x0: r[0], y0: r[1], x1: r[2], y1: r[3], light: parts[1] == "light")
        if let b = bbox(m.w, m.h, m.px) {
            let (cw, ch, px) = crop(m.w, m.px, b)
            save(cw, ch, px, (outDir as NSString).appendingPathComponent("\(parts[0]).png"))
            print("\(parts[0]): \(cw)x\(ch)")
        }
        i += 1
    }
}
