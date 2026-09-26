// Cuts tab bar art (or anything painted on cream paper) off a ChatGPT sheet.
// Built for the Ink tab bar (2026-09-26); every cut in Coherence/TabBar/ink-*
// came out of this.
//
//     swiftc -O tools/sheet_cut.swift -o /tmp/sheet_cut
//     /tmp/sheet_cut cut   sheet.png x y w h floor out.png     # an icon
//     ENCLOSED=1 /tmp/sheet_cut cut ...                        # keep enclosed white (a plus)
//     /tmp/sheet_cut wash  sheet.png x y w h out.png           # a wash, drawing painted out
//     /tmp/sheet_cut crop  sheet.png x y w h out.png           # to look at a region
//     /tmp/sheet_cut check cut.png r g b out.png               # a cut flattened on a colour
//     /tmp/sheet_cut amask cut.png gain out.png                # its alpha, amplified
//
// `cut` un-mixes the drawing from the paper (the median of the crop's edge),
// so watercolour stays as see-through as it was painted and reproduces the
// sheet exactly on paper of the same colour. Two rules learned cutting it:
//   * ONLY INK DARKER THAN THE PAPER COUNTS. GIMP's colour-to-alpha also
//     counts pixels LIGHTER than the paper, and near white that divides by
//     (255 - paper), so a compression block two levels lighter came out a
//     third opaque. A plus's white is kept by ENCLOSED=1 instead: anything
//     the paper cannot reach from the crop's edge stays opaque.
//   * A CGContext hands back PREMULTIPLIED colour. `load` un-premultiplies;
//     without it every check of a see-through cut looks grey and dark.
// `floor` (0.035 for the ink sheet) clears the paper's own grain; `despeck`
// then drops faint pixels with no real ink within 4 px.
//
// `wash` lifts a selected-state watercolour wash: the drawing on it (dark,
// or not blue) is marked a hole, widened 3 px past its soft edge, and
// filled from the surrounding wash coarse to fine (push-pull), in
// premultiplied colour so wash and transparent paper mix correctly.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Img { var w: Int; var h: Int; var px: [UInt8] }  // RGBA8, straight alpha
func load(_ path: String) -> Img {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    // The context hands back premultiplied colour; everything here is straight.
    for i in 0..<(w*h) {
        let a = Int(px[i*4+3])
        if a > 0 && a < 255 { for c in 0..<3 { px[i*4+c] = UInt8(min(255, (Int(px[i*4+c]) * 255 + a/2) / a)) } }
    }
    return Img(w: w, h: h, px: px)
}
func save(_ im: Img, _ path: String) {
    // Straight alpha in, premultiplied for CoreGraphics.
    var pm = im.px
    for i in 0..<(im.w * im.h) {
        let a = Int(pm[i*4+3])
        for c in 0..<3 { pm[i*4+c] = UInt8((Int(pm[i*4+c]) * a + 127) / 255) }
    }
    let ctx = CGContext(data: &pm, width: im.w, height: im.h, bitsPerComponent: 8, bytesPerRow: im.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cg = ctx.makeImage()!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, cg, nil)
    CGImageDestinationFinalize(dst)
}
func crop(_ im: Img, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Img {
    var out = Img(w: w, h: h, px: [UInt8](repeating: 0, count: w * h * 4))
    for yy in 0..<h { for xx in 0..<w {
        let sx = x + xx, sy = y + yy
        guard sx >= 0, sy >= 0, sx < im.w, sy < im.h else { continue }
        for c in 0..<4 { out.px[(yy*w+xx)*4+c] = im.px[(sy*im.w+sx)*4+c] } } }
    return out
}
/// Median colour of a crop's outer frame: the paper under this drawing.
func paper(_ im: Img, frame: Int = 3) -> (Double, Double, Double) {
    var r = [Int](), g = [Int](), b = [Int]()
    for y in 0..<im.h { for x in 0..<im.w where x < frame || y < frame || x >= im.w-frame || y >= im.h-frame {
        let i = (y*im.w+x)*4; r.append(Int(im.px[i])); g.append(Int(im.px[i+1])); b.append(Int(im.px[i+2])) } }
    r.sort(); g.sort(); b.sort()
    return (Double(r[r.count/2]), Double(g[g.count/2]), Double(b[b.count/2]))
}
/// Colour to alpha against the paper (GIMP's rule), with a floor that
/// clears the paper's own grain.
func unpaper(_ im: Img, bg: (Double, Double, Double), floor t0: Double) -> Img {
    var out = im
    let b = [bg.0, bg.1, bg.2]
    for i in 0..<(im.w * im.h) {
        var a = 0.0
        for c in 0..<3 {
            let v = Double(im.px[i*4+c])
            // Only ink DARKER than the paper counts. Paper a shade lighter
            // than the median is paper, not white paint: counting it made
            // compression blocks near white explode into visible alpha.
            if v < b[c] { a = max(a, (b[c] - v) / b[c]) }
        }
        let a2 = max(0, min(1, (a - t0) / (1 - t0)))
        if a2 <= 0 { for c in 0..<4 { out.px[i*4+c] = 0 }; continue }
        for c in 0..<3 {
            let v = Double(im.px[i*4+c])
            let f = (v - (1 - a2) * b[c]) / a2
            out.px[i*4+c] = UInt8(max(0, min(255, f.rounded())))
        }
        out.px[i*4+3] = UInt8((a2 * 255).rounded())
    }
    return out
}
/// Clears faint pixels with no real ink near them (compression blocks).
func despeck(_ im: Img, radius r: Int, keep: Double) -> Img {
    var out = im
    let k = UInt8(keep * 255)
    for y in 0..<im.h { for x in 0..<im.w {
        let i = y*im.w + x
        if im.px[i*4+3] == 0 || im.px[i*4+3] >= k { continue }
        var near = false
        search: for dy in -r...r { for dx in -r...r {
            let yy = y+dy, xx = x+dx
            if yy >= 0, yy < im.h, xx >= 0, xx < im.w, im.px[(yy*im.w+xx)*4+3] >= k { near = true; break search } } }
        if !near { for c in 0..<4 { out.px[i*4+c] = 0 } }
    } }
    return out
}
/// Pixels the paper cannot reach from the crop's edge become opaque in
/// their own colour: the white of the plus, enclosed by green.
func fillEnclosed(_ im: Img, original: Img, below: Double) -> Img {
    var out = im
    let lim = UInt8(below * 255)
    var seen = [Bool](repeating: false, count: im.w*im.h)
    var stack = [Int]()
    for y in 0..<im.h { for x in 0..<im.w where x == 0 || y == 0 || x == im.w-1 || y == im.h-1 {
        let i = y*im.w+x; if im.px[i*4+3] < lim { seen[i] = true; stack.append(i) } } }
    while let p = stack.popLast() {
        let x = p % im.w, y = p / im.w
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let xx = x+dx, yy = y+dy
            guard xx >= 0, yy >= 0, xx < im.w, yy < im.h else { continue }
            let q = yy*im.w+xx
            if !seen[q] && im.px[q*4+3] < lim { seen[q] = true; stack.append(q) }
        }
    }
    for i in 0..<(im.w*im.h) where !seen[i] && im.px[i*4+3] < 255 {
        for c in 0..<3 { out.px[i*4+c] = original.px[i*4+c] }; out.px[i*4+3] = 255
    }
    return out
}
/// Fills holes from their surroundings, coarse to fine (push-pull), in
/// premultiplied colour so transparent paper and pale wash mix correctly.
func pushPull(_ rgba: [Double], _ wt: [Double], _ w: Int, _ h: Int) -> [Double] {
    if w <= 1 && h <= 1 { return rgba }
    let w2 = (w + 1) / 2, h2 = (h + 1) / 2
    var c = [Double](repeating: 0, count: w2*h2*4), cw = [Double](repeating: 0, count: w2*h2)
    for y in 0..<h { for x in 0..<w {
        let i = y*w+x, j = (y/2)*w2 + x/2
        cw[j] += wt[i]; for k in 0..<4 { c[j*4+k] += rgba[i*4+k] * wt[i] } } }
    for j in 0..<(w2*h2) where cw[j] > 0 { for k in 0..<4 { c[j*4+k] /= cw[j] }; cw[j] = min(1, cw[j]) }
    let coarse = pushPull(c, cw, w2, h2)
    var out = rgba
    for y in 0..<h { for x in 0..<w {
        let i = y*w+x
        // Bilinear from the coarse level, centred.
        let fx = max(0, min(Double(w2-1), (Double(x) - 0.5) / 2)), fy = max(0, min(Double(h2-1), (Double(y) - 0.5) / 2))
        let x0 = Int(fx), y0 = Int(fy), x1 = min(w2-1, x0+1), y1 = min(h2-1, y0+1)
        let ax = fx - Double(x0), ay = fy - Double(y0)
        for k in 0..<4 {
            let v = (coarse[(y0*w2+x0)*4+k] * (1-ax) + coarse[(y0*w2+x1)*4+k] * ax) * (1-ay)
                  + (coarse[(y1*w2+x0)*4+k] * (1-ax) + coarse[(y1*w2+x1)*4+k] * ax) * ay
            out[i*4+k] = rgba[i*4+k] * wt[i] + v * (1 - wt[i])
        }
    } }
    return out
}
/// Tight box around pixels with alpha above `minA`.
func bbox(_ im: Img, minA: UInt8 = 8) -> (Int, Int, Int, Int)? {
    var x0 = im.w, y0 = im.h, x1 = -1, y1 = -1
    for y in 0..<im.h { for x in 0..<im.w where im.px[(y*im.w+x)*4+3] > minA {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 < 0 ? nil : (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
}
/// Composite on a flat colour, for looking at a cut.
func flatten(_ im: Img, on c: (UInt8, UInt8, UInt8)) -> Img {
    var out = im
    let bg = [c.0, c.1, c.2]
    for i in 0..<(im.w*im.h) {
        let a = Double(im.px[i*4+3]) / 255
        for k in 0..<3 { out.px[i*4+k] = UInt8((Double(im.px[i*4+k]) * a + Double(bg[k]) * (1 - a)).rounded()) }
        out.px[i*4+3] = 255
    }
    return out
}

let args = CommandLine.arguments
let cmd = args[1]
let sheet = load(args[2])
switch cmd {
case "crop":      // crop sheet x y w h out
    save(crop(sheet, Int(args[3])!, Int(args[4])!, Int(args[5])!, Int(args[6])!), args[7])
case "paper":     // paper sheet x y w h
    let c = crop(sheet, Int(args[3])!, Int(args[4])!, Int(args[5])!, Int(args[6])!)
    print(paper(c))
case "cut":       // cut sheet x y w h floor out [pad]
    let c = crop(sheet, Int(args[3])!, Int(args[4])!, Int(args[5])!, Int(args[6])!)
    let bg = paper(c)
    var a = despeck(unpaper(c, bg: bg, floor: Double(args[7])!), radius: 4, keep: 0.10)
    if ProcessInfo.processInfo.environment["ENCLOSED"] == "1" { a = fillEnclosed(a, original: c, below: 0.5) }
    let pad = args.count > 9 ? Int(args[9])! : 2
    if let (x, y, w, h) = bbox(a) {
        let t = crop(a, x - pad, y - pad, w + 2*pad, h + 2*pad)
        save(t, args[8])
        print("paper \(bg)  cut \(t.w)x\(t.h) at \(Int(args[3])! + x - pad),\(Int(args[4])! + y - pad)")
    }
case "check":     // check cut.png r g b out  (flatten on a colour)
    save(flatten(sheet, on: (UInt8(args[3])!, UInt8(args[4])!, UInt8(args[5])!)), args[6])
case "amask":     // amask cut.png gain out  (alpha as grey, amplified)
    var out = sheet
    let g = Double(args[3])!
    for i in 0..<(sheet.w*sheet.h) { let v = UInt8(min(255, Double(sheet.px[i*4+3]) * g)); out.px[i*4] = v; out.px[i*4+1] = v; out.px[i*4+2] = v; out.px[i*4+3] = 255 }
    save(out, args[4])
case "wash":      // wash sheet x y w h out : the blue wash with the drawing on it removed
    let c = crop(sheet, Int(args[3])!, Int(args[4])!, Int(args[5])!, Int(args[6])!)
    let bg = paper(c)
    let a = despeck(unpaper(c, bg: bg, floor: 0.02), radius: 4, keep: 0.06)
    let n = c.w * c.h
    var hole = [Bool](repeating: false, count: n)
    for i in 0..<n {
        let r = Double(c.px[i*4]), g = Double(c.px[i*4+1]), b = Double(c.px[i*4+2])
        let l = 0.299*r + 0.587*g + 0.114*b
        hole[i] = l < 196 || (b - r < 14 && Double(a.px[i*4+3]) / 255 > 0.16)
    }
    // Widen the hole past the drawing's soft edge.
    var wide = hole
    let rr = 3
    for y in 0..<c.h { for x in 0..<c.w where hole[y*c.w+x] {
        for dy in -rr...rr { for dx in -rr...rr { let yy = y+dy, xx = x+dx
            if yy >= 0, yy < c.h, xx >= 0, xx < c.w { wide[yy*c.w+xx] = true } } } } }
    var pm = [Double](repeating: 0, count: n*4), wt = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let al = Double(a.px[i*4+3]) / 255
        for k in 0..<3 { pm[i*4+k] = Double(a.px[i*4+k]) * al }
        pm[i*4+3] = al
        wt[i] = wide[i] ? 0 : 1
    }
    let filled = pushPull(pm, wt, c.w, c.h)
    var out = a
    for i in 0..<n {
        let al = max(0, min(1, filled[i*4+3]))
        out.px[i*4+3] = UInt8((al * 255).rounded())
        for k in 0..<3 { out.px[i*4+k] = al > 0.002 ? UInt8(max(0, min(255, (filled[i*4+k] / al).rounded()))) : 0 }
    }
    if let (x, y, w, h) = bbox(out, minA: 3) {
        let t = crop(out, x - 2, y - 2, w + 4, h + 4)
        save(t, args[7]); print("paper \(bg)  wash \(t.w)x\(t.h)")
    }
default: print("?")
}
