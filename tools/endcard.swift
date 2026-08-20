import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// End card for video edits: the 808 mark, "Meditate with 808", and the domain.
//
// Built to sit under a fade at the end of a clip, so: black ground (matches the
// app's dark theme and any footage fading to black), gold mark, generous dead
// space so it reads at a glance rather than being studied.
//
//   swift tools/endcard.swift            # writes every size
//   swift tools/endcard.swift 1080x1920  # just one

// Exact app tokens. AccentGold dark, BackgroundPrimary dark.
let gold  = CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 1)
let ink   = CGColor(red: 0.961, green: 0.953, blue: 0.925, alpha: 1)
let muted = CGColor(red: 0.604, green: 0.604, blue: 0.576, alpha: 1)
let bg    = CGColor(red: 0.045, green: 0.038, blue: 0.030, alpha: 1)

// Melvin's chosen mark geometry: w.135 h.205 o.215 r.150, lw .026.
let W = 0.135, H = 0.205, OFF = 0.215, R0 = 0.150, LW = 0.026

func drawMark(_ ctx: CGContext, cx: Double, cy: Double, size s: Double) {
    func ellipse(_ ecx: Double, _ ecy: Double, _ rx: Double, _ ry: Double) {
        ctx.addEllipse(in: CGRect(x: ecx - rx, y: ecy - ry, width: 2 * rx, height: 2 * ry))
        ctx.strokePath()
    }
    ctx.setStrokeColor(gold)
    ctx.setLineWidth(s * LW)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    for dy in [-OFF, OFF] { ellipse(cx, cy + dy * s, W * s, H * s) }
    for dx in [-OFF, OFF] { ellipse(cx + dx * s, cy, H * s, W * s) }
    ellipse(cx, cy, R0 * s, R0 * s)
}

/// Centred text. Returns the line height so callers can stack without guessing.
/// `system` and `systemBold` resolve to SF Pro, which no font NAME reaches.
/// Everything else is looked up normally.
func face(_ name: String, _ size: Double) -> CTFont {
    switch name {
    case "system":     return CTFontCreateUIFontForLanguage(.system, size, nil)!
    case "systemBold": return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
    default:           return CTFontCreateWithName(name as CFString, size, nil)
    }
}

@discardableResult
func draw(_ ctx: CGContext, _ text: String, font: String, size: Double,
          color: CGColor, cx: Double, baseline: Double, tracking: Double = 0) -> Double {
    let f = face(font, size)
    var attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    if tracking != 0 {
        attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
    }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: cx - b.width / 2, y: baseline)
    CTLineDraw(line, ctx)
    return b.height
}

func card(width: Int, height: Int, _ t: Treatment, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = Double(width), h = Double(height)

    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // A very soft warm bloom behind the mark, the same gesture the app's own
    // screens use. Subtle enough to survive compression rather than banding.
    if let grad = CGGradient(colorsSpace: cs,
                             colors: [CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 0.10),
                                      CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 0)] as CFArray,
                             locations: [0, 1]) {
        let short = min(w, h)
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: w / 2, y: h * 0.60), startRadius: 0,
                               endCenter: CGPoint(x: w / 2, y: h * 0.60), endRadius: short * 0.55,
                               options: [])
    }

    // Scaled off the SHORT side so the composition holds at any aspect ratio.
    let short = min(w, h)
    let markSize = short * 0.30
    let markCY = h * 0.60

    drawMark(ctx, cx: w / 2, cy: markCY, size: markSize)

    let headline = short * t.size
    draw(ctx, "Meditate with 808", font: t.face, size: headline,
         color: ink, cx: w / 2, baseline: markCY - markSize * 0.62 - headline,
         tracking: headline * t.tracking)

    let sub = short * 0.028
    draw(ctx, "MEASURED ON APPLE WATCH", font: t.subFace, size: sub,
         color: muted, cx: w / 2,
         baseline: markCY - markSize * 0.62 - headline - sub * 2.6, tracking: sub * 0.22)

    let domain = short * 0.034
    // 18% up from the bottom, not 11%: Reels, TikTok and Shorts all lay a
    // caption bar and action rail over the bottom ~15% of a vertical frame,
    // and a domain nobody can read is a domain nobody types.
    draw(ctx, "meditate808.com", font: "AvenirNext-Medium", size: domain,
         color: gold, cx: w / 2, baseline: h * 0.18)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { print("failed \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("  \(url.lastPathComponent)  \(width)x\(height)")
}

/// The headline treatment. Lighter weights need MORE letter spacing, not less:
/// a thin face set tight reads as cramped, and the space is what makes it look
/// deliberate rather than small. Nothing below UltraLight, because video
/// compression eats hairlines and this has to survive an Instagram re-encode.
struct Treatment {
    let name: String
    let face: String
    let subFace: String
    /// Fraction of the short side.
    let size: Double
    /// Fraction of the type size.
    let tracking: Double
}

let treatments: [Treatment] = [
    Treatment(name: "regular", face: "AvenirNext-Regular", subFace: "AvenirNext-Medium",
              size: 0.078, tracking: 0.04),
    Treatment(name: "light", face: "AvenirNext-UltraLight", subFace: "AvenirNext-Regular",
              size: 0.084, tracking: 0.07),
    Treatment(name: "thin-wide", face: "AvenirNext-UltraLight", subFace: "AvenirNext-Regular",
              size: 0.072, tracking: 0.16),
    // The website's treatment, as closely as a stock Mac can get it. Bricolage
    // Grotesque and IBM Plex are not installed, so this is SF Pro, which is at
    // least the same species: a grotesque rather than Avenir's humanist forms.
    // The negative tracking is the site's own -0.03em on display type.
    Treatment(name: "grotesque", face: "systemBold", subFace: "system",
              size: 0.080, tracking: -0.03),
    Treatment(name: "grotesque-medium", face: "system", subFace: "system",
              size: 0.080, tracking: -0.02),
]

let sizes: [(String, Int, Int)] = [
    ("endcard-vertical-1080x1920", 1080, 1920),   // Reels, TikTok, Shorts, Stories
    ("endcard-square-1080x1080", 1080, 1080),     // feed
    ("endcard-wide-1920x1080", 1920, 1080),       // YouTube landscape
]
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1]
              : FileManager.default.currentDirectoryPath + "/scratchpad")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// One treatment renders every shape; no treatment renders all three verticals
// so they can be compared side by side.
let picked = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
if let picked, let t = treatments.first(where: { $0.name == picked }) {
    print("End cards · \(t.name):")
    for (name, w, h) in sizes {
        card(width: w, height: h, t, to: out.appendingPathComponent(name + ".png"))
    }
} else {
    print("Headline treatments (vertical only, pick one):")
    for t in treatments {
        card(width: 1080, height: 1920, t,
             to: out.appendingPathComponent("headline-\(t.name).png"))
    }
    print("\nThen: swift tools/endcard.swift <outdir> <regular|light|thin-wide>")
}
