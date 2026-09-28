import AppKit

// How much higher each of Otto's thirteen looks must wear a hat so its brim
// clears the dark patches round his eyes by as much as it does at Steady,
// where every hat was fitted (Melvin, 2026-09-28: at the bright looks "the
// hats start to cover it, and it looks like the hats are drooping down onto
// his face").
//
//   swiftc -O -o /tmp/hat_lift tools/hat_lift.swift
//   /tmp/hat_lift <hat picture> <x,y,w,h box> <bodies dir> [--debug out.png --look N]
//
// The hat picture is what is drawn OVER his face (hat-<id>-front.png for a
// layered hat, hat-<id>.png otherwise) and the box is its HatArt.placement.
// The bodies are the thirteen images the aura rig draws
// (tools/riv_dump.py Coherence/Otto/OttoAura.riv --bodies DIR).
//
// Everything is compared in Steady's canvas units, the frame the hats are
// fitted in: each look's head is laid onto Steady's by its skull, centre and
// width (the same anchors the app places hats by). For every column across
// his face, the gap is the top of the patch minus the bottom of the hat; a
// look's lift is how much its closest gap falls short of Steady's. Never
// negative: the early looks already clear the patches, the drooping ones by
// far. Prints the thirteen lifts, comma separated, ready for HatArt.faceLift
// and hat_extract's --lifts.

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
    // Row 0 is the TOP. Colour un-premultiplied.
    func at(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
        let i = (y * w + x) * 4
        let a = Double(px[i + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Double(px[i]) * 255 / a, Double(px[i + 1]) * 255 / a, Double(px[i + 2]) * 255 / a, a)
    }
}

let a = CommandLine.arguments
let hat = Bitmap(a[1])
let box = a[2].split(separator: ",").map { Double($0)! }
let dir = a[3]
let debugOut = a.firstIndex(of: "--debug").map { a[$0 + 1] }
let debugLook = a.firstIndex(of: "--look").map { Int(a[$0 + 1])! } ?? 13

let files = ["otto-clean2-body-1", "otto-mid2-body-1", "otto-clean2-body-2", "otto-mid2-body-2",
             "otto-clean2-body-3", "otto-mid2-body-3", "otto-clean2-body-4", "otto-mid2-body-4",
             "otto-clean2-body-5", "otto-mid2-body-5", "otto-clean2-body-6", "otto-mid2-body-6",
             "otto-clean2-body-7"]
// (skull, cx, width) in each image's own pixels: OttoAuraFigure.bodies.
let heads: [(Double, Double, Double)] = [
    (52, 255.5, 331), (47, 258.5, 340), (54, 252.0, 344), (51, 250.5, 337), (56, 248.5, 340),
    (51, 243.5, 343), (51, 246.5, 340), (61, 247.5, 335), (62, 251.0, 326), (67, 248.5, 325),
    (66, 253.0, 320), (84, 248.0, 309), (68, 249.5, 320)]
let steady = (skull: 86.0, cx: 330.5, width: 341.0)

// The hat's lowest opaque point in each canvas column (x in whole units).
var hatBottom = [Int: Double]()
for u in 0..<hat.w {
    guard let v = (0..<hat.h).reversed().first(where: { hat.at(u, $0).3 > 128 }) else { continue }
    let X = Int((box[0] + (Double(u) + 0.5) / Double(hat.w) * box[2]).rounded(.down))
    let Y = box[1] + (Double(v) + 1) / Double(hat.h) * box[3]
    hatBottom[X] = max(hatBottom[X] ?? -.infinity, Y)
}

// The patches' top in each canvas column, for one look, before any lift.
// Walk down each column from the skull: fur, then the cream of his face,
// then the first run of the patch's own mid brown. Requiring the cream first
// is what keeps the shaded fur at the sides of his head out (a colour test
// alone counted it, and Steady looked as though its hats already overlapped).
// The patch brown is darker than the fur at every look (Steady's fur is
// ~160,115,88, the bright looks' ~190,130,85) and lighter than a pupil, the
// nose or a lid line.
func patchTop(_ n: Int) -> ([Int: Double], [(Int, Int)]) {
    let b = Bitmap(dir + "/" + files[n] + ".png")
    let (skull, cx, hw) = heads[n]
    let k = steady.width / hw
    var top = [Int: Double](), pts = [(Int, Int)]()
    for x in max(0, Int(cx - 0.46 * hw))...min(b.w - 1, Int(cx + 0.46 * hw)) {
        var state = 0, run = 0
        for y in Int(skull)..<min(b.h - 1, Int(skull + 0.55 * hw)) {
            let (r, g, bl, al) = b.at(x, y)
            guard al > 200 else { state = 0; run = 0; continue }
            if state == 0 {
                // A real stretch of face, not the rim light the bright looks
                // carry along the edge of their fur (a few pale pixels).
                if r > 205 && g > 165 { run += 1; if run >= 8 { state = 1; run = 0 } } else { run = 0 }
            } else {
                let patch = r >= 80 && r <= 150 && g >= 50 && g <= 108 && r - bl >= 25 && r - bl <= 95
                if patch { run += 1 } else { run = 0 }
                if run >= 3 {
                    let yTop = y - 2
                    let X = Int((steady.cx + (Double(x) - cx) * k).rounded(.down))
                    top[X] = min(top[X] ?? .infinity, steady.skull + (Double(yTop) - skull) * k)
                    pts.append((x, yTop))
                    break
                }
            }
        }
    }
    // Isolated points are specks, not a patch: a column counts only when
    // its neighbours within 3 units agree to within 4.
    var kept = [Int: Double]()
    for (X, t) in top {
        let near = (X - 3...X + 3).compactMap { $0 == X ? nil : top[$0] }.filter { abs($0 - t) <= 4 }
        if near.count >= 3 { kept[X] = t }
    }
    return (kept, pts)
}

func closestGap(_ top: [Int: Double]) -> Double? {
    var best: Double?
    for (X, t) in top { if let hb = hatBottom[X] { best = min(best ?? .infinity, t - hb) } }
    return best
}

// The gap a look must keep: Steady's, capped at --cap (default 12, the brim
// hats' own gap at Steady), because a hat that sits far above his eyes (the
// halo, a crown on the crown of his head) only has to stay off the patches,
// and lifting it to keep ALL of that height would float it off his head.
// From look --margin-from (default 8) the bright looks add --margin (default
// 3): their patches are taller and wider, and the same closest gap runs
// along more of the brim, which reads tighter than Steady's.
func flag(_ name: String, _ fallback: Double) -> Double {
    a.firstIndex(of: name).map { Double(a[$0 + 1])! } ?? fallback
}
let cap = flag("--cap", 12), margin = flag("--margin", 3), marginFrom = Int(flag("--margin-from", 8))

let tops = (0..<13).map { patchTop($0) }
guard let steadyGap = closestGap(tops[6].0) else {
    print((0..<13).map { _ in "0" }.joined(separator: ","))
    exit(0)
}
var lifts = [Double]()
var report = [String]()
for n in 0..<13 {
    let g = closestGap(tops[n].0)
    let target = min(steadyGap, cap) + (n + 1 >= marginFrom ? margin : 0)
    let lift = g.map { n == 6 ? 0 : max(0, target - $0) } ?? 0
    lifts.append((lift * 2).rounded() / 2)
    report.append(String(format: "look %2d gap %@ lift %.1f", n + 1, g.map { String(format: "%6.1f", $0) } ?? "  none", lift))
}
FileHandle.standardError.write((report.joined(separator: "\n") + "\n").data(using: .utf8)!)
print(lifts.map { String(format: "%g", $0) }.joined(separator: ","))

// --debug: the chosen look's patches (red) and the hat's lower edge (blue),
// in canvas units, before the lift, over Steady's patches (green).
if let out = debugOut {
    let n = debugLook - 1
    let scale = 2.0
    let Wc = Int(664 * scale), Hc = Int(420 * scale)
    let ctx = CGContext(data: nil, width: Wc, height: Hc, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: Wc, height: Hc))
    func dot(_ X: Double, _ Y: Double, _ c: CGColor) {
        ctx.setFillColor(c); ctx.fill(CGRect(x: X * scale, y: Double(Hc) - Y * scale, width: scale, height: scale))
    }
    for (look, colour) in [(6, CGColor(red: 0, green: 0.6, blue: 0, alpha: 0.5)), (n, CGColor(red: 0.9, green: 0, blue: 0, alpha: 0.6))] {
        let (skull, cx, hw) = heads[look]
        let k = steady.width / hw
        for (x, y) in tops[look].1 {
            dot(steady.cx + (Double(x) - cx) * k, steady.skull + (Double(y) - skull) * k + (look == n ? 0 : 0), colour)
        }
    }
    for (X, Y) in hatBottom { dot(Double(X), Y, CGColor(red: 0, green: 0, blue: 1, alpha: 1)) }
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: out))
}
