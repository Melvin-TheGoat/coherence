#!/usr/bin/env swift
//
//  logo_lab.swift — 808 logo playground
//
//  Renders the LogoMark geometry to a PNG so you can eyeball parameter changes
//  without building the app. Sweep any parameter by passing a comma-separated
//  list; every combination gets its own labelled tile.
//
//  Usage:
//      swift tools/logo_lab.swift                          # current values
//      swift tools/logo_lab.swift offset=0.19,0.20,0.21    # sweep one param
//      swift tools/logo_lab.swift h=0.20 r0=0.09,0.10,0.11 # sweep + override
//      swift tools/logo_lab.swift --icon                   # 1024 app-icon PNG
//
//  Parameters (all are fractions of the mark's size, so they scale):
//      w      petal half-width   — small w = skinny petals = reads more like an "8"
//      h      petal half-height  — the long axis of each petal
//      offset petal center distance from the middle
//             offset <  h  → the two lobes OVERLAP (tight woven 8)
//             offset == h  → the lobes are TANGENT (a clean numeral-8 waist)
//             offset >  h  → the lobes SEPARATE (reads as a flower, not an 8)
//      r0     center O radius
//      lw     stroke width
//
//  Rule of thumb: total extent is (offset + h); keep it near 0.42 so the mark
//  fills its box without clipping.
//
//  When you like a tile, copy its numbers into `LogoMark.path(in:)` in
//  Shared/Theme/LogoMark.swift, then run `swift tools/logo_lab.swift --icon`
//  to regenerate Shared/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png.
//

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Current values (keep in sync with LogoMark.path(in:))

var params: [String: [Double]] = [
    "w": [0.135],
    "h": [0.205],
    "offset": [0.215],
    "r0": [0.150],
    "lw": [0.020],
]

// MARK: - Args

var iconMode = false
for arg in CommandLine.arguments.dropFirst() {
    if arg == "--icon" { iconMode = true; continue }
    let parts = arg.split(separator: "=", maxSplits: 1)
    guard parts.count == 2, params[String(parts[0])] != nil else {
        FileHandle.standardError.write("unknown argument: \(arg)\n".data(using: .utf8)!)
        exit(1)
    }
    let values = parts[1].split(separator: ",").compactMap { Double($0) }
    guard !values.isEmpty else {
        FileHandle.standardError.write("no numbers in: \(arg)\n".data(using: .utf8)!)
        exit(1)
    }
    params[String(parts[0])] = values
}

// MARK: - Palette (matches Assets.xcassets)

let bgColor = CGColor(red: 0.075, green: 0.064, blue: 0.052, alpha: 1)   // BackgroundPrimary (dark)
let goldColor = CGColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 1) // AccentGold
let labelColor = CGColor(red: 0.62, green: 0.60, blue: 0.56, alpha: 1)

struct Variant { let w, h, offset, r0, lw: Double }

/// Every combination of the swept parameters, in a stable order.
func variants() -> [Variant] {
    var out: [Variant] = []
    for w in params["w"]! {
        for h in params["h"]! {
            for offset in params["offset"]! {
                for r0 in params["r0"]! {
                    for lw in params["lw"]! {
                        out.append(Variant(w: w, h: h, offset: offset, r0: r0, lw: lw))
                    }
                }
            }
        }
    }
    return out
}

// MARK: - Drawing

/// THE geometry. Mirrors `LogoMark.path(in:)` — four round-ended petals (a
/// vertical pair + a horizontal pair) plus the center O.
func drawMark(_ ctx: CGContext, cx: Double, cy: Double, size s: Double, _ v: Variant) {
    func ellipse(_ ecx: Double, _ ecy: Double, _ rx: Double, _ ry: Double) {
        ctx.addEllipse(in: CGRect(x: ecx - rx, y: ecy - ry, width: 2 * rx, height: 2 * ry))
        ctx.strokePath()
    }
    ctx.setStrokeColor(goldColor)
    ctx.setLineWidth(s * v.lw)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    for dy in [-v.offset, v.offset] { ellipse(cx, cy + dy * s, v.w * s, v.h * s) }
    for dx in [-v.offset, v.offset] { ellipse(cx + dx * s, cy, v.h * s, v.w * s) }
    if v.r0 > 0 { ellipse(cx, cy, v.r0 * s, v.r0 * s) }
}

func drawLabel(_ ctx: CGContext, _ text: String, cx: Double, y: Double) {
    let font = CTFontCreateWithName("Menlo" as CFString, 17, nil)
    // Raw CoreText keys — the NSAttributedString.Key shorthands live in AppKit,
    // which a plain Foundation script doesn't link.
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): labelColor,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: cx - bounds.width / 2, y: y)
    CTLineDraw(line, ctx)
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(bgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx
}

func write(_ ctx: CGContext, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

// MARK: - Icon mode

if iconMode {
    let all = variants()
    guard all.count == 1 else {
        FileHandle.standardError.write("--icon needs exactly one value per parameter\n".data(using: .utf8)!)
        exit(1)
    }
    let size = 1024.0
    let ctx = makeContext(Int(size), Int(size))
    drawMark(ctx, cx: size / 2, cy: size / 2, size: size, all[0])
    let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().deletingLastPathComponent().path
    write(ctx, to: "\(repoRoot)/Shared/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png")
    exit(0)
}

// MARK: - Grid mode

let all = variants()
let tile = 460.0
let labelBand = 46.0
let columns = min(all.count, 3)
let rows = Int(ceil(Double(all.count) / Double(columns)))
let ctx = makeContext(Int(Double(columns) * tile), Int(Double(rows) * (tile + labelBand)))

for (i, v) in all.enumerated() {
    let col = i % columns
    let row = i / columns
    let cx = (Double(col) + 0.5) * tile
    // CoreGraphics origin is bottom-left; lay tiles out top-down.
    let top = Double(rows - row) * (tile + labelBand)
    let cy = top - labelBand - tile / 2
    drawMark(ctx, cx: cx, cy: cy, size: tile, v)
    let fmt = { (d: Double) in String(format: "%.3f", d) }
    drawLabel(ctx, "w\(fmt(v.w)) h\(fmt(v.h)) o\(fmt(v.offset)) r\(fmt(v.r0))",
              cx: cx, y: top - labelBand + 14)
}

let out = "/tmp/logo_lab.png"
write(ctx, to: out)
// Open it so you see the result immediately.
let open = Process()
open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
open.arguments = [out]
try? open.run()
