import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// App Store screenshot compositor.
//
// Takes a raw simulator screenshot (1320x2868, the 6.9" size Apple requires)
// and frames it under a caption, producing the marketing image that actually
// goes in the store listing.
//
// Style notes, deliberate:
//  - Dark ground, not the white card most apps use. 808 IS a dark app; a white
//    frame would promise a screen the user never sees. It also separates us in
//    a search-results row where nearly everything is white.
//  - One gold element per image (the subhead), matching the app's rule that a
//    screen shows exactly one gold thing.
//  - The phone bleeds off the bottom edge. The store crops the bottom of a
//    screenshot in some placements, and a bleeding device survives that where a
//    fully-contained one looks amputated.
//
//   swift tools/store_shots.swift <raw.png> <out.png> "Headline|second line" "Subhead"

let gold = CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 1)
let ink  = CGColor(red: 0.976, green: 0.973, blue: 0.965, alpha: 1)
let bg   = CGColor(red: 0.075, green: 0.063, blue: 0.051, alpha: 1)

let OUT_W = 1320.0, OUT_H = 2868.0

func face(_ kind: String, _ size: Double) -> CTFont {
    switch kind {
    case "bold":  return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
    default:      return CTFontCreateUIFontForLanguage(.system, size, nil)!
    }
}

@discardableResult
func draw(_ ctx: CGContext, _ text: String, kind: String, size: Double,
          color: CGColor, cx: Double, baseline: Double, tracking: Double = 0) -> Double {
    let f = face(kind, size)
    var attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    if tracking != 0 { attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking }
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attrs))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: cx - w / 2, y: baseline)
    CTLineDraw(line, ctx)
    return w
}

func roundedPath(_ r: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Compose

guard CommandLine.arguments.count >= 5 else {
    print("usage: store_shots <raw.png> <out.png> \"Headline|line two\" \"Subhead\"")
    exit(1)
}
let rawPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let headline = CommandLine.arguments[3].split(separator: "|").map(String.init)
let subhead = CommandLine.arguments[4]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: rawPath) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot read \(rawPath)"); exit(1)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(OUT_W), height: Int(OUT_H),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("no context"); exit(1)
}

// Ground
ctx.setFillColor(bg)
ctx.fill(CGRect(x: 0, y: 0, width: OUT_W, height: OUT_H))

// A soft gold bloom behind the headline. Warms the top third so the type sits
// on something rather than floating on flat black.
if let grad = CGGradient(colorsSpace: cs,
                         colors: [CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 0.16),
                                  CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 0)] as CFArray,
                         locations: [0, 1]) {
    ctx.saveGState()
    ctx.drawRadialGradient(grad,
                           startCenter: CGPoint(x: OUT_W / 2, y: OUT_H - 430), startRadius: 0,
                           endCenter: CGPoint(x: OUT_W / 2, y: OUT_H - 430), endRadius: 900,
                           options: [])
    ctx.restoreGState()
}

// Caption. CoreGraphics origin is bottom-left, so baselines count down from top.
let headSize = headline.count > 1 ? 92.0 : 100.0
var baseline = OUT_H - 300
for line in headline {
    draw(ctx, line, kind: "bold", size: headSize, color: ink,
         cx: OUT_W / 2, baseline: baseline, tracking: -1.6)
    baseline -= headSize * 1.16
}
draw(ctx, subhead, kind: "regular", size: 42, color: gold,
     cx: OUT_W / 2, baseline: baseline - 26, tracking: 0.2)

// Device. Width chosen so the phone bleeds a little off the bottom edge.
let phoneW = 1006.0
let scale = phoneW / Double(shot.width)
let phoneH = Double(shot.height) * scale
let phoneX = (OUT_W - phoneW) / 2
let phoneTop = headline.count > 1 ? 690.0 : 660.0     // distance from image top
let phoneY = OUT_H - phoneTop - phoneH                 // CG bottom-left origin
let bezel = 13.0
let outer = CGRect(x: phoneX - bezel, y: phoneY - bezel,
                   width: phoneW + bezel * 2, height: phoneH + bezel * 2)
let radius = 108.0

// Shadow first, cast by the bezel shape.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
ctx.setFillColor(CGColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
ctx.addPath(roundedPath(outer, radius + bezel))
ctx.fillPath()
ctx.restoreGState()

// Screenshot, clipped to the rounded screen.
ctx.saveGState()
ctx.addPath(roundedPath(CGRect(x: phoneX, y: phoneY, width: phoneW, height: phoneH), radius))
ctx.clip()
ctx.draw(shot, in: CGRect(x: phoneX, y: phoneY, width: phoneW, height: phoneH))
ctx.restoreGState()

// A hairline highlight on the bezel so the edge reads as metal, not a border.
ctx.saveGState()
ctx.addPath(roundedPath(outer.insetBy(dx: 1.5, dy: 1.5), radius + bezel))
ctx.setStrokeColor(CGColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 0.9))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("cannot write"); exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
