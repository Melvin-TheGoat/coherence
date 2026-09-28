// Where Otto's head is in each of the seven aura drawings, so a hat fitted on
// one (Steady, the reference every hat was generated on) can be carried onto
// the others (2026-09-27).
//
//   swiftc -O -o /tmp/head tools/otto_head_measure.swift
//   /tmp/head Shared/Assets.xcassets/OttoAura{1..7}.imageset/OttoAura{1..7}.png
//
// For each drawing, on its 664 x 744 canvas, counting only solid fur (alpha
// over 0.9 and darker than the paper, so baked light and motes are ignored):
//   tuft  the topmost fur pixel near his centre line (the tuft's tip)
//   skull the first row whose fur spans more than 55% of his head's width:
//         the top of his head proper, under the tuft, where a hat sits
//   cx    the head's centre, halfway across the fur 60 units under the skull
//   w     the head's width 100 units under the skull
import AppKit
import Foundation

for path in CommandLine.arguments.dropFirst() {
    let img = NSImage(contentsOfFile: path)!
    var rect = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let W = cg.width, H = cg.height
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    func solid(_ x: Int, _ y: Int) -> Bool {
        let i = (y * W + x) * 4
        let a = Int(px[i + 3])
        guard a > 230 else { return false }
        // un-premultiplied colour: fur is darker than 200 on every channel
        return Int(px[i]) < 200 && Int(px[i + 1]) < 200 && Int(px[i + 2]) < 200
    }
    let mid = W / 2
    func extent(_ y: Int) -> (Int, Int)? {
        var lo: Int?, hi: Int?
        for x in max(0, mid - 230)..<min(W, mid + 230) where solid(x, y) {
            if lo == nil { lo = x }; hi = x
        }
        guard let l = lo, let h = hi else { return nil }
        return (l, h)
    }
    var tuft = 0
    for y in 0..<H { if (mid - 90..<mid + 90).contains(where: { solid($0, y) }) { tuft = y; break } }
    var headW = 0
    for y in tuft..<min(H, tuft + 220) { if let e = extent(y) { headW = max(headW, e.1 - e.0) } }
    var skull = tuft
    for y in tuft..<min(H, tuft + 200) { if let e = extent(y), Double(e.1 - e.0) > 0.55 * Double(headW) { skull = y; break } }
    let e60 = extent(skull + 60) ?? (0, W)
    let e100 = extent(skull + 100) ?? (0, W)
    var bottom = tuft
    for y in stride(from: H - 1, through: 0, by: -1) { if (0..<W).contains(where: { solid($0, y) }) { bottom = y; break } }
    let name = (path as NSString).lastPathComponent
    print(String(format: "%@ size=%dx%d tuft=%d skull=%d cx=%.1f w=%d bottom=%d", name, W, H, tuft, skull,
                 Double(e60.0 + e60.1) / 2, e100.1 - e100.0, bottom))
}
