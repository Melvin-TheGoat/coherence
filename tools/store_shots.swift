import Foundation
import AppKit
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
// Style notes, deliberate (rebuilt 2026-09-29 for 1.1, when the app left its
// dark theme for Otto's valley):
//  - The ground is the valley's own daytime sky: the top of `DayLight`'s
//    first stop (0x8CBBD4) easing down to the horizon cream (0xEFE0C9), with
//    the far ridges low behind the phone. The frame is the place the app is
//    set in, so the screenshot reads as a window into it rather than a
//    screen pasted on a poster.
//  - Type is SF Pro Rounded, the face the app sets on its root: a heavy
//    headline in the sky's ink (0x26404E) and a medium subhead in its softer
//    ink (0x47697A). No em dashes, ever.
//  - Exactly one accent: the warm sun haze behind the headline (the valley's
//    sun colour, 0xFFE9B8, paled toward cream so it reads as light on the
//    blue rather than tinting it green). Everything else is sky, ink, cream.
//  - The phone is a drawn, generic dark bezel, never a photographed device.
//    Apple's marketing guidelines forbid depicting its hardware inaccurately,
//    and a generic bezel claims no specific model.
//  - The phone bleeds a little off the bottom edge. The store crops the bottom
//    of a screenshot in some placements, and a bleeding device survives that
//    where a fully contained one looks amputated. Its top is fixed, so the
//    phone sits in the same place on every slide and the strip reads as a set.
//
//   swiftc -O -o store_shots tools/store_shots.swift
//   ./store_shots <raw.png> <out.png> "Headline|second line" "Subhead"
//
// A "|" forces a line break in either caption; without one the subhead wraps
// to fit.

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let skyTop   = rgb(0x8CBBD4)
let skyMid   = rgb(0xBBD8E4)
let haze     = rgb(0xE3E8DA)
let cream    = rgb(0xF3EADB)
let ink      = rgb(0x26404E)
let inkSoft  = rgb(0x47697A)
let sun      = 0xFFF0D2 as UInt32

let OUT_W = 1320.0, OUT_H = 2868.0

// MARK: - Type

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let desc = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return (NSFont(descriptor: desc, size: size) ?? base) as CTFont
}

func line(_ text: String, font: CTFont, color: CGColor, tracking: CGFloat) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

func width(_ l: CTLine) -> Double { CTLineGetTypographicBounds(l, nil, nil, nil) }

/// Greedy word wrap to `maxWidth`, honouring "|" as a forced break.
func wrap(_ text: String, font: CTFont, tracking: CGFloat, maxWidth: Double) -> [String] {
    var out: [String] = []
    for part in text.split(separator: "|", omittingEmptySubsequences: false).map(String.init) {
        var current = ""
        for word in part.split(separator: " ").map(String.init) {
            let trial = current.isEmpty ? word : current + " " + word
            if width(line(trial, font: font, color: ink, tracking: tracking)) <= maxWidth || current.isEmpty {
                current = trial
            } else {
                out.append(current); current = word
            }
        }
        out.append(current)
    }
    return out
}

/// The same line count as a greedy wrap, with the lines as even as they can
/// be, so a subhead never leaves one word alone on its second line.
func balanced(_ text: String, font: CTFont, tracking: CGFloat, maxWidth: Double) -> [String] {
    var best = wrap(text, font: font, tracking: tracking, maxWidth: maxWidth)
    guard best.count > 1, !text.contains("|") else { return best }
    var w = maxWidth
    while w > 200 {
        w -= 10
        let trial = wrap(text, font: font, tracking: tracking, maxWidth: w)
        if trial.count != best.count { break }
        best = trial
    }
    return best
}

func roundedPath(_ r: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Inputs

guard CommandLine.arguments.count >= 5 else {
    print("usage: store_shots <raw.png> <out.png> \"Headline|line two\" \"Subhead\"")
    exit(1)
}
let rawPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let headlineText = CommandLine.arguments[3]
let subheadText = CommandLine.arguments[4]

for text in [headlineText, subheadText] where text.contains("\u{2014}") || text.contains("\u{2013}") {
    print("refusing: a caption carries an em or en dash (\(text))"); exit(1)
}

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: rawPath) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot read \(rawPath)"); exit(1)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(OUT_W), height: Int(OUT_H),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    print("no context"); exit(1)
}
// CoreGraphics origin is bottom-left; `y(top)` converts a distance from the
// top of the image into it.
func y(_ fromTop: Double) -> Double { OUT_H - fromTop }

// MARK: - Ground: the valley's daytime sky, easing into cream

let sky = CGGradient(colorsSpace: cs,
                     colors: [skyTop, skyMid, haze, cream, cream] as CFArray,
                     locations: [0, 0.26, 0.46, 0.62, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: OUT_H), end: CGPoint(x: 0, y: 0), options: [])

// The one accent: a soft sun haze high behind the headline.
let glow = CGGradient(colorsSpace: cs,
                      colors: [rgb(sun, 0.70), rgb(sun, 0.30), rgb(sun, 0)] as CFArray,
                      locations: [0, 0.45, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: OUT_W * 0.5, y: y(300)), startRadius: 0,
                       endCenter: CGPoint(x: OUT_W * 0.5, y: y(300)), endRadius: 760,
                       options: [])

// The far ridges, low behind the phone, the same two blue-greys the app draws.
func ridge(_ points: [(Double, Double)], color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    for (px, pyTop) in points { p.addLine(to: CGPoint(x: px, y: y(pyTop))) }
    p.addLine(to: CGPoint(x: OUT_W, y: 0))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}
ridge([(0, 1180), (170, 1050), (330, 1130), (560, 990), (820, 1120), (1030, 1010), (1200, 1090), (1320, 1040)],
      color: rgb(0xAFC6CE, 0.55))
ridge([(0, 1290), (220, 1170), (430, 1250), (700, 1150), (930, 1240), (1150, 1160), (1320, 1210)],
      color: rgb(0x8FAFB4, 0.45))
// Mist over the ridges' feet, so they fade into the cream instead of ending on a line.
let mist = CGGradient(colorsSpace: cs,
                      colors: [rgb(0xF3EADB, 0), rgb(0xF3EADB, 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(mist, start: CGPoint(x: 0, y: y(1080)), end: CGPoint(x: 0, y: y(1560)),
                       options: [.drawsAfterEndLocation])

// MARK: - Device geometry (fixed on every slide)

let phoneW = 1036.0
let phoneScale = phoneW / Double(shot.width)
let phoneH = Double(shot.height) * phoneScale
let phoneX = (OUT_W - phoneW) / 2
let phoneTop = 662.0
let phoneY = OUT_H - phoneTop - phoneH
let bezel = 15.0
let radius = 128.0
let outer = CGRect(x: phoneX - bezel, y: phoneY - bezel,
                   width: phoneW + bezel * 2, height: phoneH + bezel * 2)

// MARK: - Caption, centred in the band above the phone

let headFont = rounded(98, .heavy)
let headTracking: CGFloat = -1.4
let subFont = rounded(45, .medium)
let subTracking: CGFloat = 0
let maxLine = 1160.0

var headLines = wrap(headlineText, font: headFont, tracking: headTracking, maxWidth: maxLine)
var headSize: CGFloat = 98
// Never let a headline line touch the edges: step the size down if one would.
while headLines.map({ width(line($0, font: rounded(headSize, .heavy), color: ink, tracking: headTracking)) }).max()! > maxLine {
    headSize -= 2
}
let head = rounded(headSize, .heavy)
headLines = wrap(headlineText, font: head, tracking: headTracking, maxWidth: maxLine)
let subLines = balanced(subheadText, font: subFont, tracking: subTracking, maxWidth: 1080)

let headLead = Double(headSize) * 1.10
let subLead = 45.0 * 1.30
let gap = 34.0
let blockH = headLead * Double(headLines.count) + gap + subLead * Double(subLines.count)
let bandTop = 150.0, bandBottom = phoneTop - 70
var cursor = bandTop + max(0, (bandBottom - bandTop - blockH) / 2)

for text in headLines {
    let l = line(text, font: head, color: ink, tracking: headTracking)
    ctx.textPosition = CGPoint(x: (OUT_W - width(l)) / 2, y: y(cursor + Double(headSize) * 0.92))
    CTLineDraw(l, ctx)
    cursor += headLead
}
cursor += gap
for text in subLines {
    let l = line(text, font: subFont, color: inkSoft, tracking: subTracking)
    ctx.textPosition = CGPoint(x: (OUT_W - width(l)) / 2, y: y(cursor + 45 * 0.95))
    CTLineDraw(l, ctx)
    cursor += subLead
}

// MARK: - Device

// Shadow first, cast by the bezel shape: soft and cool, since the ground is light.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 80,
              color: rgb(0x1C3E4E, 0.30))
ctx.setFillColor(rgb(0x1E1F22))
ctx.addPath(roundedPath(outer, radius + bezel))
ctx.fillPath()
ctx.restoreGState()

// Screenshot, clipped to the rounded screen.
ctx.saveGState()
ctx.addPath(roundedPath(CGRect(x: phoneX, y: phoneY, width: phoneW, height: phoneH), radius))
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(shot, in: CGRect(x: phoneX, y: phoneY, width: phoneW, height: phoneH))
ctx.restoreGState()

// A hairline highlight on the bezel so the edge reads as metal, not a border.
ctx.saveGState()
ctx.addPath(roundedPath(outer.insetBy(dx: 1.5, dy: 1.5), radius + bezel))
ctx.setStrokeColor(rgb(0x5E6166, 0.9))
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
print("wrote \(outPath)  (headline \(Int(headSize))pt, \(headLines.count)+\(subLines.count) lines)")
