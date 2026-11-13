// Cuts a companion's seven bodies and seven chest patches for the Rive rig.
//
//   swift tools/companion_cut.swift <masterDir> <name> <outDir> [density] [chestDown] [chestHalf]
// (red panda: 1.3 0.62 0.13, its chin sits low and the default patch caught it)
//
// Input: <masterDir>/<name>-1..7.png, 1328x1488 (2x of the 664x744 canvas),
// transparent, base on y=1298. Output, at `density` x the canvas (default 1.5):
//   body-<i>.png   the body cropped to its alpha box
//   chest-<i>.png  a feathered ellipse of the chest (body pixels x mask),
//                  centred at 50% of the figure's width and 60% down from its
//                  top, cropped to the ellipse's box
//   boxes.txt      "<name> x y w h" in CANVAS units (664x744), plus
//                  "figure-<i> x y w h" (the body's alpha box)
// The rig places each image by its box and scales it by 100/density percent.
//
// BOXES_FROM=<dir> (2026-11-13): take every box from <dir>/<name>-<i>.png (the
// masters the rig was built from) and the pixels from <masterDir>. Used to
// re-cut cleaned art (tools/paper_check.swift) into images of exactly the
// rig's sizes and places, so it can be swapped in with tools/riv_images.py
// without moving anything a hat or a rig number was measured against.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 4 else { print("usage: companion_cut.swift masterDir name outDir [density]"); exit(1) }
let master = a[1], name = a[2], out = a[3]
let density = a.count > 4 ? Double(a[4])! : 1.5
// optional: chest centre (fraction down the figure, default 0.60) and its half-height (fraction, default 0.17)
let chestDown = a.count > 5 ? Double(a[5])! : 0.60
let chestHalf = a.count > 6 ? Double(a[6])! : 0.17
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let W = Int((664 * density).rounded()), H = Int((744 * density).rounded())
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func ctx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ img: CGImage, _ p: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

var lines: [String] = []
for i in 1...7 {
    let c = ctx(W, H)
    c.interpolationQuality = .high
    c.draw(load("\(master)/\(name)-\(i).png"), in: CGRect(x: 0, y: 0, width: W, height: H))
    let px = c.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)  // row 0 = TOP
    var boxPx = px
    var boxCtx: CGContext? = nil   // keeps boxPx's memory alive for this stage
    if let from = ProcessInfo.processInfo.environment["BOXES_FROM"] {
        let b = ctx(W, H)
        b.interpolationQuality = .high
        b.draw(load("\(from)/\(name)-\(i).png"), in: CGRect(x: 0, y: 0, width: W, height: H))
        boxCtx = b
        boxPx = b.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
    }
    _ = boxCtx
    var x0 = W, y0 = H, x1 = -1, y1 = -1
    for y in 0..<H { for x in 0..<W where boxPx[(y * W + x) * 4 + 3] > 6 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    x0 = max(0, x0 - 2); y0 = max(0, y0 - 2); x1 = min(W - 1, x1 + 2); y1 = min(H - 1, y1 + 2)
    let full = c.makeImage()!
    let bw = x1 - x0 + 1, bh = y1 - y0 + 1
    save(full.cropping(to: CGRect(x: x0, y: y0, width: bw, height: bh))!, "\(out)/body-\(i).png")
    let k = 1 / density
    lines.append(String(format: "body-%d %.2f %.2f %.2f %.2f", i, Double(x0) * k, Double(y0) * k, Double(bw) * k, Double(bh) * k))
    lines.append(String(format: "figure-%d %.2f %.2f %.2f %.2f", i, Double(x0) * k, Double(y0) * k, Double(bw) * k, Double(bh) * k))

    // The chest: a feathered ellipse; alpha 1 inside 55% of the radius, 0 at the rim.
    let cx = Double(x0) + Double(bw) * 0.5, cy = Double(y0) + Double(bh) * chestDown
    let rx = min(Double(bw) * 0.22, 150 * density), ry = min(Double(bh) * chestHalf, 120 * density)
    let ex0 = Int(cx - rx), ey0 = Int(cy - ry), ew = Int(2 * rx) + 1, eh = Int(2 * ry) + 1
    let p = ctx(ew, eh)
    let q = p.data!.bindMemory(to: UInt8.self, capacity: ew * eh * 4)
    for y in 0..<eh { for x in 0..<ew {
        let sx = ex0 + x, sy = ey0 + y
        guard sx >= 0, sy >= 0, sx < W, sy < H else { continue }
        let dx = (Double(sx) + 0.5 - cx) / rx, dy = (Double(sy) + 0.5 - cy) / ry
        let r = (dx * dx + dy * dy).squareRoot()
        var m = r <= 0.55 ? 1.0 : max(0, 1 - (r - 0.55) / 0.45)
        m = m * m * (3 - 2 * m)
        // context memory row 0 is the top; the patch context's too
        for ch in 0..<4 { q[(y * ew + x) * 4 + ch] = UInt8((Double(px[(sy * W + sx) * 4 + ch]) * m).rounded()) }
    } }
    save(p.makeImage()!, "\(out)/chest-\(i).png")
    lines.append(String(format: "chest-%d %.2f %.2f %.2f %.2f", i, Double(ex0) * k, Double(ey0) * k, Double(ew) * k, Double(eh) * k))
}
try! lines.joined(separator: "\n").appending("\n").write(toFile: "\(out)/boxes.txt", atomically: true, encoding: .utf8)
print(lines.joined(separator: "\n"))
