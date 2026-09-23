// Cuts Otto's seven aura states out of one sheet drawn on white.
//
//     swiftc -O tools/otto_aura_cut.swift -o /tmp/otto_aura_cut
//     /tmp/otto_aura_cut sheet.png out-dir [--names a,b,c] [--grid 4,3]
//
// WHY A NEW CUTTER: `otto_unmatte.py` lifts a flat background by flooding it
// away, which is right for figures that end in a clean edge. The aura sheet
// does not: from stage 5 up he sits in a haze of light, and the haze is the
// point. Flooding it away leaves a hard pale blob; keeping it opaque paints a
// white-yellow halo onto the sky. So light that sits OUTSIDE the figure is
// un-composited off the white ("colour to alpha": the one alpha and colour
// that, laid over white, give back exactly the pixel drawn), which turns the
// haze into real translucent light that glows over any background.
//
// What counts as the figure is found by darkness, not by colour: the fur,
// his mask, a leaf and a bug are all well darker than any light effect, and
// his cream face and belly are enclosed by fur, so filling holes brings them
// in. A small closing first joins the cream claws to the fur they hang from.
// Anything the figure encloses stays fully opaque; everything else is light.
//
// The number printed under each figure is erased first: it is the one thing
// on the sheet that is dark, neutral and not part of anybody.
//
// Swift rather than Python because this Mac has no numpy or PIL, and a
// morphological closing over 1.5M pixels in pure Python takes minutes.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Image {
    var w: Int
    var h: Int
    var px: [UInt8]   // RGBA, straight (not premultiplied)
}

func load(_ path: String) -> Image {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("cannot read \(path)")
    }
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Image(w: w, h: h, px: px)
}

func save(_ img: Image, _ path: String) {
    // CoreGraphics wants premultiplied data.
    var pre = img.px
    for i in stride(from: 0, to: pre.count, by: 4) {
        let a = Int(pre[i + 3])
        for c in 0..<3 { pre[i + c] = UInt8((Int(pre[i + c]) * a + 127) / 255) }
    }
    let ctx = CGContext(data: &pre, width: img.w, height: img.h, bitsPerComponent: 8,
                        bytesPerRow: img.w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cg = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Masks

/// Square dilation, separable, so a closing costs 4 passes rather than r².
func dilate(_ m: [Bool], _ w: Int, _ h: Int, _ r: Int) -> [Bool] {
    var tmp = [Bool](repeating: false, count: m.count)
    for y in 0..<h {
        var run = -1
        for x in 0..<w where m[y * w + x] {
            let lo = max(0, x - r, run + 1), hi = min(w - 1, x + r)
            if lo <= hi { for xx in lo...hi { tmp[y * w + xx] = true } }
            run = hi
        }
    }
    var out = [Bool](repeating: false, count: m.count)
    for x in 0..<w {
        var run = -1
        for y in 0..<h where tmp[y * w + x] {
            let lo = max(0, y - r, run + 1), hi = min(h - 1, y + r)
            if lo <= hi { for yy in lo...hi { out[yy * w + x] = true } }
            run = hi
        }
    }
    return out
}

func erode(_ m: [Bool], _ w: Int, _ h: Int, _ r: Int) -> [Bool] {
    dilate(m.map { !$0 }, w, h, r).map { !$0 }
}

/// Everything the border cannot reach through `open` pixels.
func enclosed(_ open: [Bool], _ w: Int, _ h: Int) -> [Bool] {
    var reached = [Bool](repeating: false, count: open.count)
    var stack: [Int] = []
    func seed(_ i: Int) { if open[i] && !reached[i] { reached[i] = true; stack.append(i) } }
    for x in 0..<w { seed(x); seed((h - 1) * w + x) }
    for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
    while let i = stack.popLast() {
        let x = i % w, y = i / w
        if x > 0 { seed(i - 1) }
        if x < w - 1 { seed(i + 1) }
        if y > 0 { seed(i - w) }
        if y < h - 1 { seed(i + w) }
    }
    return reached.map { !$0 }
}

/// Connected components (4-way) of a mask: labels and each label's pixel list size.
func components(_ m: [Bool], _ w: Int, _ h: Int) -> (labels: [Int32], sizes: [Int]) {
    var labels = [Int32](repeating: -1, count: m.count)
    var sizes: [Int] = []
    var stack: [Int] = []
    for start in 0..<m.count where m[start] && labels[start] < 0 {
        let id = Int32(sizes.count)
        var n = 0
        labels[start] = id; stack.append(start)
        while let i = stack.popLast() {
            n += 1
            let x = i % w, y = i / w
            for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1,
                      y > 0 ? i - w : -1, y < h - 1 ? i + w : -1] where j >= 0 {
                if m[j] && labels[j] < 0 { labels[j] = id; stack.append(j) }
            }
        }
        sizes.append(n)
    }
    return (labels, sizes)
}

// MARK: - Main

var args = CommandLine.arguments.dropFirst().map { $0 }
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let names = (option("--names") ?? "aura-1,aura-2,aura-3,aura-4,aura-5,aura-6,aura-7")
    .split(separator: ",").map(String.init)
let grid = (option("--grid") ?? "4,3").split(separator: ",").compactMap { Int($0) }
/// Darker than this in every channel's minimum is figure for certain.
let seedMin = Int(option("--seed") ?? "178")!
let closeRadius = Int(option("--close") ?? "3")!
let normalizeTarget = option("--normalize").flatMap(Double.init)
/// `--canvas W,H,baseline`: force the canvas instead of fitting it to this
/// sheet, so a later sheet (the clean bodies for the Rive rig) lands on
/// exactly the grid the first one set: 664,744,649.
let fixedCanvas = option("--canvas").map { $0.split(separator: ",").compactMap { Double($0) } }
guard args.count >= 2 else {
    print("usage: otto_aura_cut sheet.png out-dir [--names …] [--grid 4,3]"); exit(1)
}
var img = load(args[0])
let outDir = args[1]
let w = img.w, h = img.h
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
print("sheet \(w)x\(h)")

func rgb(_ i: Int) -> (Int, Int, Int) {
    (Int(img.px[i * 4]), Int(img.px[i * 4 + 1]), Int(img.px[i * 4 + 2]))
}

// 1. The seeds: pixels dark enough to be figure, leaf or bug for certain.
var seed = [Bool](repeating: false, count: w * h)
for i in 0..<(w * h) {
    let (r, g, b) = rgb(i)
    seed[i] = min(r, g, b) < seedMin
}

// 2. The printed numbers. Small components of dark NEUTRAL grey that sit on
// their own. Erased back to white before anything else reads them.
do {
    let (labels, sizes) = components(seed, w, h)
    var neutral = [Int](repeating: 0, count: sizes.count)
    var minX = [Int](repeating: Int.max, count: sizes.count), maxX = [Int](repeating: -1, count: sizes.count)
    var minY = [Int](repeating: Int.max, count: sizes.count), maxY = [Int](repeating: -1, count: sizes.count)
    for i in 0..<(w * h) where labels[i] >= 0 {
        let l = Int(labels[i]); let (r, g, b) = rgb(i)
        if max(r, g, b) - min(r, g, b) < 18 { neutral[l] += 1 }
        let x = i % w, y = i / w
        minX[l] = min(minX[l], x); maxX[l] = max(maxX[l], x)
        minY[l] = min(minY[l], y); maxY[l] = max(maxY[l], y)
    }
    var erased = 0
    for l in 0..<sizes.count {
        let bw = maxX[l] - minX[l] + 1, bh = maxY[l] - minY[l] + 1
        // A digit: mostly neutral, glyph sized, taller than it is wide.
        guard sizes[l] >= 20, Double(neutral[l]) / Double(sizes[l]) > 0.85,
              bw <= 30, bh >= 12, bh <= 40 else { continue }
        for y in max(0, minY[l] - 3)...min(h - 1, maxY[l] + 3) {
            for x in max(0, minX[l] - 3)...min(w - 1, maxX[l] + 3) {
                let i = y * w + x; let (r, g, b) = rgb(i)
                if max(r, g, b) - min(r, g, b) < 24 {
                    img.px[i * 4] = 255; img.px[i * 4 + 1] = 255; img.px[i * 4 + 2] = 255
                    seed[i] = false
                }
            }
        }
        erased += 1
        print("erased a label at \(minX[l]),\(minY[l]) \(bw)x\(bh)")
    }
    print("labels erased: \(erased)")
}

// 3. The solid figure: seeds, closed so the claws join the fur, holes filled
// so the cream face and belly come in.
let closed = erode(dilate(seed, w, h, closeRadius), w, h, closeRadius)
var solid = enclosed(closed.map { !$0 }, w, h)

// The closing also traps the palest fur tips between strands, and opaque
// near-white tips draw a white rim around him on the sky. Anything light
// within a few pixels of the outside goes back to being light instead.
do {
    var dist = [Int](repeating: Int.max, count: w * h)
    var queue: [Int] = []
    for i in 0..<(w * h) where !solid[i] { dist[i] = 0; queue.append(i) }
    var head = 0
    let reach = 3
    while head < queue.count {
        let i = queue[head]; head += 1
        guard dist[i] < reach else { continue }
        let x = i % w, y = i / w
        for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1,
                  y > 0 ? i - w : -1, y < h - 1 ? i + w : -1] where j >= 0 {
            if dist[j] == Int.max { dist[j] = dist[i] + 1; queue.append(j) }
        }
    }
    var softened = 0
    for i in 0..<(w * h) where solid[i] && dist[i] <= reach {
        let (r, g, b) = rgb(i)
        if min(r, g, b) > 212 { solid[i] = false; softened += 1 }
    }
    print("edge tips softened: \(softened)")
}

// 4. Alpha. Solid stays opaque; everything else is un-composited off white.
var out = img
for i in 0..<(w * h) {
    let (r, g, b) = rgb(i)
    if solid[i] {
        out.px[i * 4 + 3] = 255
        continue
    }
    let a = Double(255 - min(r, g, b)) / 255
    if a < 2.0 / 255 {
        out.px[i * 4] = 0; out.px[i * 4 + 1] = 0; out.px[i * 4 + 2] = 0; out.px[i * 4 + 3] = 0
        continue
    }
    func un(_ c: Int) -> UInt8 {
        let v = (Double(c) - 255 * (1 - a)) / a
        return UInt8(max(0, min(255, v.rounded())))
    }
    out.px[i * 4] = un(r); out.px[i * 4 + 1] = un(g); out.px[i * 4 + 2] = un(b)
    out.px[i * 4 + 3] = UInt8((a * 255).rounded())
}

// 5. Who owns what. The big solid components are the figures, read in grid
// order (rows by y, then x). Every visible pixel goes to the nearest figure
// centre, which is what carries a mote or a leaf with the sloth it circles.
let (labels, sizes) = components(solid, w, h)
let biggest = sizes.enumerated().sorted { $0.element > $1.element }.prefix(names.count).map { $0.offset }
var centres: [(Int, Double, Double)] = []   // label, cx, cy
for l in biggest {
    var sx = 0.0, sy = 0.0, n = 0.0
    for i in 0..<(w * h) where labels[i] == Int32(l) { sx += Double(i % w); sy += Double(i / w); n += 1 }
    centres.append((l, sx / n, sy / n))
}
// Grid order: split rows by the gap in y, then left to right.
let byY = centres.sorted { $0.2 < $1.2 }
var ordered: [(Int, Double, Double)] = []
var start = 0
for count in grid {
    let row = byY[start..<min(byY.count, start + count)].sorted { $0.1 < $1.1 }
    ordered.append(contentsOf: row); start += count
}
print("figures: " + ordered.map { "(\(Int($0.1)),\(Int($0.2)))" }.joined(separator: " "))

// Rows are split at the middle of the gap between one row's lowest body
// and the next row's highest, so a mote over a head in the bottom row can
// never be handed to a figure in the row above. Inside a row, the nearest
// centre wins.
var bodyTop = [Int](repeating: h, count: ordered.count)
var bodyBottom = [Int](repeating: -1, count: ordered.count)
for (k, c) in ordered.enumerated() {
    for i in 0..<(w * h) where labels[i] == Int32(c.0) {
        bodyTop[k] = min(bodyTop[k], i / w); bodyBottom[k] = max(bodyBottom[k], i / w)
    }
}
var rowOf = [Int](repeating: 0, count: ordered.count)
var splits: [Int] = []
do {
    var k = 0
    for (r, count) in grid.enumerated() {
        for _ in 0..<count where k < ordered.count { rowOf[k] = r; k += 1 }
    }
    for r in 0..<(grid.count - 1) {
        let above = (0..<ordered.count).filter { rowOf[$0] == r }.map { bodyBottom[$0] }.max() ?? 0
        let below = (0..<ordered.count).filter { rowOf[$0] == r + 1 }.map { bodyTop[$0] }.min() ?? h
        splits.append((above + below) / 2)
    }
}
print("row splits: \(splits)")

var owner = [Int](repeating: -1, count: w * h)
for i in 0..<(w * h) where out.px[i * 4 + 3] > 0 {
    let x = Double(i % w), y = i / w
    let row = splits.filter { y >= $0 }.count
    var best = -1, bestD = Double.infinity
    for (k, c) in ordered.enumerated() where rowOf[k] == row {
        let d = abs(x - c.1)
        if d < bestD { bestD = d; best = k }
    }
    owner[i] = best
}

for (k, name) in names.enumerated() where k < ordered.count {
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for i in 0..<(w * h) where owner[i] == k && out.px[i * 4 + 3] > 6 {
        let x = i % w, y = i / w
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    }
    let cw = x1 - x0 + 1, chh = y1 - y0 + 1
    var cut = Image(w: cw, h: chh, px: [UInt8](repeating: 0, count: cw * chh * 4))
    for y in y0...y1 {
        for x in x0...x1 {
            let i = y * w + x
            guard owner[i] == k else { continue }
            let o = ((y - y0) * cw + (x - x0)) * 4
            for c in 0..<4 { cut.px[o + c] = out.px[i * 4 + c] }
        }
    }
    // The body's own box, so the importer can seat every state on one line.
    var bx0 = w, by0 = h, bx1 = -1, by1 = -1
    let body = Int32(ordered[k].0)
    for i in 0..<(w * h) where labels[i] == body {
        let x = i % w, y = i / w
        bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y)
    }
    let path = (outDir as NSString).appendingPathComponent(name + ".png")
    save(cut, path)
    let meta: [String: Int] = ["x": x0, "y": y0, "w": cw, "h": chh,
                               "bodyX": bx0 - x0, "bodyY": by0 - y0,
                               "bodyW": bx1 - bx0 + 1, "bodyH": by1 - by0 + 1]
    let json = try! JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
    try! json.write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(name + ".json")))
    print("\(name): \(cw)x\(chh) at \(x0),\(y0); body \(bx1 - bx0 + 1)x\(by1 - by0 + 1)")
}

// 6. One canvas for all of them (`--normalize <body width in px>`).
//
// The image model draws the second row bigger than the first (stage 5 came
// out 12% wider than stage 4), and Otto must not change size between states.
// So every state is scaled until its BODY is the same width, and every body
// sits on the same baseline, centred, in one shared canvas big enough for the
// widest light and the tallest halo. Width rather than height because the
// halo and the hover make height mean different things per state, while the
// crossed legs span the same in all seven.
if let target = normalizeTarget {
    struct Placed { let img: CGImage; let scale: Double; let bodyCX: Double; let bodyBottom: Double; let w: Double; let h: Double }
    var placed: [Placed] = []
    for name in names {
        let base = (outDir as NSString).appendingPathComponent(name)
        let data = try! Data(contentsOf: URL(fileURLWithPath: base + ".json"))
        let m = try! JSONSerialization.jsonObject(with: data) as! [String: Int]
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: base + ".png") as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let s = target / Double(m["bodyW"]!)
        placed.append(Placed(img: cg, scale: s,
                             bodyCX: (Double(m["bodyX"]!) + Double(m["bodyW"]!) / 2) * s,
                             bodyBottom: Double(m["bodyY"]! + m["bodyH"]!) * s,
                             w: Double(m["w"]!) * s, h: Double(m["h"]!) * s))
    }
    let left = placed.map { $0.bodyCX }.max()!
    let right = placed.map { $0.w - $0.bodyCX }.max()!
    var half = max(left, right).rounded(.up) + 4
    var up = (placed.map { $0.bodyBottom }.max()! + 4).rounded(.up)
    var down = (placed.map { $0.h - $0.bodyBottom }.max()! + 4).rounded(.up)
    if let c = fixedCanvas, c.count == 3 {
        half = c[0] / 2; up = c[2]; down = c[1] - c[2]
    }
    let cw = Int(half * 2), chh = Int(up + down)
    for (k, name) in names.enumerated() {
        let p = placed[k]
        let ctx = CGContext(data: nil, width: cw, height: chh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        // CoreGraphics puts y = 0 at the bottom.
        let x = half - p.bodyCX
        let yTop = up - p.bodyBottom
        ctx.draw(p.img, in: CGRect(x: x, y: Double(chh) - yTop - p.h, width: p.w, height: p.h))
        let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(name + "-norm.png")) as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
    // Where the body sits in the canvas, for the app: its width and its
    // baseline, as fractions of the canvas.
    let info: [String: Double] = ["canvasW": Double(cw), "canvasH": Double(chh),
                                  "bodyWidth": target / Double(cw), "baseline": up / Double(chh)]
    let json = try! JSONSerialization.data(withJSONObject: info, options: [.sortedKeys, .prettyPrinted])
    try! json.write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent("canvas.json")))
    print("canvas \(cw)x\(chh): body \(Int(target)) px wide, baseline at \(Int(up))")
}
