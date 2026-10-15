// Renders 808's App Store creative asset (the product page header and the
// search results image, iOS 27 and later) from the app's own valley painting,
// at Apple's universal size, 5244 x 2950, with no alpha channel.
//
//   swiftc -parse-as-library -O -o /tmp/store_art \
//       Coherence/Session/DayLight.swift Coherence/Session/ValleyPainting.swift \
//       tools/store_art.swift
//   /tmp/store_art <out-dir>
//
// It writes one PNG per variant, plus a 1600 px preview of each with Apple's
// safe area and both crops drawn on it (`-guides.png`), for review.
//
// THE SAFE AREA IS APPLE'S, READ OFF THEIR OWN TEMPLATE
// (`creative_assets-templates.sketch`, "16x9Universal - 5244x2950", layer
// "Art Safe Area"): x 1921 to 3323, y 660 to 1622. Apple crops the universal
// image to 21:9 for the header and 3:2 for search results, and lays the app's
// icon, name and Get button over it, so Otto and any words stay inside that
// box and everything outside it is scenery. The header's own safe area sits
// at the vertical middle of a 21:9 frame, which maps onto the universal one
// only if the header is cut from the TOP of the 16:9 image, so the guides
// draw it that way; the search results cut keeps the full height.
//
// Everything is the app's painting (`ValleyPainting.swift`, `DayLight`) and
// Otto's own aura still, recomposed for a wide frame: the phone scene is a
// portrait, so the ridges, field and meadow are laid out here around Otto
// rather than by the phone's fractions.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Frame {
    static let size = CGSize(width: 5244, height: 2950)
    static let safe = CGRect(x: 1921, y: 660, width: 1402, height: 962)
}

struct Variant {
    var name: String
    /// DayLight's 0 (full day) to 1 (night).
    var hour: Double
    /// Otto's aura still, 1 to 7.
    var stage: Int
    /// The box he sits in, as `SitLayout.ottoHeight` is on the phone.
    var ottoBox: CGFloat
    /// The bottom of his cushion.
    var cushionBottom: CGFloat
    var line: String?
}

@main
struct StoreArt {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "store-art", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let variants: [Variant] = [
            Variant(name: "otto", hour: 0.0, stage: 7, ottoBox: 780, cushionBottom: 1560, line: nil),
            Variant(name: "every-day", hour: 0.0, stage: 7, ottoBox: 660, cushionBottom: 1600,
                    line: "Meditate every day with Otto"),
            Variant(name: "habit", hour: 0.0, stage: 7, ottoBox: 660, cushionBottom: 1600,
                    line: "Make meditation a habit"),
        ]
        let only = ProcessInfo.processInfo.environment["ONLY"]
        for v in variants where only == nil || v.name == only {
            let still = root.appendingPathComponent("Shared/Assets.xcassets/OttoAura\(v.stage).imageset/OttoAura\(v.stage).png")
            guard let otto = NSImage(contentsOf: still) else { throw Failure("no still at \(still.path)") }
            var birds: [NSImage] = []
            for name in ["BirdA2", "BirdC4", "BirdB3"] {
                let url = root.appendingPathComponent("Shared/Assets.xcassets/Life/\(name).imageset/\(name).png")
                guard let bird = NSImage(contentsOf: url) else { throw Failure("no bird at \(url.path)") }
                birds.append(bird)
            }
            let renderer = ImageRenderer(content: Creative(variant: v, otto: otto, birds: birds))
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(Frame.size)
            guard let image = renderer.cgImage else { throw Failure("render failed for \(v.name)") }
            let flat = try opaque(image)
            try write(flat, to: out.appendingPathComponent("808-\(v.name).png"))
            try write(guides(on: flat), to: out.appendingPathComponent("808-\(v.name)-guides.png"))
            print("wrote 808-\(v.name).png  \(flat.width) x \(flat.height)  alpha \(flat.alphaInfo.rawValue)")
        }
    }

    /// Apple refuses alpha channels, so the render is redrawn into an RGB
    /// context with no alpha at all.
    static func opaque(_ image: CGImage) throws -> CGImage {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure("no context")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = ctx.makeImage() else { throw Failure("no image") }
        return out
    }

    /// A 1600 px copy with the safe area (green), the header's 21:9 cut
    /// (amber, from the top) and the search results' 3:2 cut (blue).
    static func guides(on image: CGImage) throws -> CGImage {
        let k = 1600 / Frame.size.width
        let w = 1600, h = Int((Frame.size.height * k).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure("no context") }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics counts y from the bottom.
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * k, y: CGFloat(h) - r.maxY * k, width: r.width * k, height: r.height * k)
        }
        ctx.setLineWidth(4)
        ctx.setStrokeColor(CGColor(red: 0.1, green: 0.85, blue: 0.2, alpha: 1))
        ctx.stroke(rect(Frame.safe))
        ctx.setLineWidth(3)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.65, blue: 0.1, alpha: 1))
        ctx.stroke(rect(CGRect(x: 0, y: 0, width: Frame.size.width, height: Frame.size.width * 9 / 21)))
        ctx.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1))
        let searchW = Frame.size.height * 3 / 2
        ctx.stroke(rect(CGRect(x: (Frame.size.width - searchW) / 2, y: 0, width: searchW, height: Frame.size.height)))
        guard let out = ctx.makeImage() else { throw Failure("no image") }
        return out
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure("cannot finish \(url.path)") }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// The picture: the valley at one hour, Otto on his cushion in the middle of
/// Apple's safe area, and the line above him when there is one.
struct Creative: View {
    let variant: Variant
    let otto: NSImage
    let birds: [NSImage]

    var body: some View {
        let W = Frame.size.width, H = Frame.size.height
        let day = DayLight.at(variant.hour)
        // The phone scene's scale for this Otto: `SitLayout.ottoHeight` is
        // 186 x 1.17 of it.
        let s = variant.ottoBox / (186 * 1.17)
        let cushion = variant.cushionBottom
        // The phone's proportions, measured off the cushion: the field starts
        // 77.5 units above it and the ridge band runs from 238.7 to 52.7.
        let fieldTop = cushion - 77.5 * s
        let ridgeTop = cushion - 238.7 * s
        let ridgeBottom = cushion - 52.7 * s

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: day.sky, startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: H)

            // The sun left of him, half behind the far ridge, as on the phone.
            Circle()
                .fill(day.sun)
                .frame(width: (44 + 4 * variant.hour) * s, height: (44 + 4 * variant.hour) * s)
                .shadow(color: day.glow, radius: 20 * s)
                .shadow(color: day.glow.opacity(0.75), radius: 44 * s)
                .position(x: W * 0.30, y: ridgeTop + (60 + 40 * variant.hour) * s)

            clouds(day: day, s: s)

            ridges(day: day, top: ridgeTop, bottom: ridgeBottom)

            flock(s: s)

            field(day: day, top: fieldTop)

            ground(s: s, fieldTop: fieldTop, cushion: cushion)
                .colorMultiply(Color(white: day.light))

            ottoFigure(s: s, cushion: cushion)

            if let line = variant.line {
                Text(line)
                    .font(.system(size: 104, weight: .heavy, design: .rounded))
                    .foregroundStyle(day.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .shadow(color: .white.opacity(0.45), radius: 22)
                    .frame(width: Frame.safe.width - 60)
                    .position(x: W / 2, y: Frame.safe.minY + 92)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }

    /// The phone's ridge is one 300-unit polyline; stretched across a wide
    /// frame it flattens into a single low hill. Each row is laid as tiles of
    /// its own width, alternate ones mirrored so the ends always meet, and
    /// offset from the other rows so no two peaks line up.
    private func ridges(day: DayLight, top: CGFloat, bottom: CGFloat) -> some View {
        let W = Frame.size.width, h = bottom - top
        let widths: [CGFloat] = [2300, 1850, 1500]
        let shifts: [CGFloat] = [-640, 310, -120]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { row in
                let tw = widths[row]
                let count = Int((W / tw).rounded(.up)) + 2
                ForEach(0..<count, id: \.self) { i in
                    ValleyRidge(row: row)
                        .fill(day.ridge[row])
                        .frame(width: tw + 2, height: h)
                        .scaleEffect(x: i.isMultiple(of: 2) ? 1 : -1, y: 1)
                        .position(x: shifts[row] + (CGFloat(i) - 0.5) * tw, y: top + h / 2)
                }
            }
        }
        .frame(width: W, height: Frame.size.height)
    }

    /// Three of the app's birds crossing the sky on the right, toward him,
    /// clear of the safe area.
    private func flock(s: CGFloat) -> some View {
        let specs: [(x: CGFloat, y: CGFloat, w: CGFloat, tilt: Double)] = [
            (3780, 470, 36, -6), (4120, 340, 30, -10), (4330, 590, 26, -4),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<specs.count, id: \.self) { i in
                let b = specs[i]
                Image(nsImage: birds[i % birds.count])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: b.w * s, height: b.w * s * 1.1)
                    .rotationEffect(.degrees(b.tilt))
                    // The sprites face right; these fly left, toward him.
                    .scaleEffect(x: -1, y: 1)
                    .position(x: b.x, y: b.y)
            }
        }
        .frame(width: Frame.size.width, height: Frame.size.height)
    }

    /// Three clouds placed by hand, clear of his head and the line: two in
    /// the sky over the left and right shoulders of the frame, one small one
    /// low on the far right.
    private func clouds(day: DayLight, s: CGFloat) -> some View {
        let specs: [(w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat)] = [
            (158, 82, 0.12, 0.13), (132, 68, 0.80, 0.09), (96, 50, 0.90, 0.30),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<specs.count, id: \.self) { i in
                let c = specs[i]
                ValleyCloud()
                    .fill(day.cloud)
                    .frame(width: c.w * s, height: c.h * s)
                    .position(x: c.x * Frame.size.width, y: c.y * Frame.size.height)
            }
        }
        .frame(width: Frame.size.width, height: Frame.size.height)
        .opacity(day.cloudOpacity)
    }

    /// The field: the app's two greens from the ridge to the bottom edge,
    /// with the same haze where it meets the ridge and the same darkening
    /// toward the viewer.
    private func field(day: DayLight, top: CGFloat) -> some View {
        let W = Frame.size.width, depth = Frame.size.height - top
        return ZStack {
            LinearGradient(colors: day.field, startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0), location: 0.18),
                .init(color: .clear, location: 0.40),
                .init(color: Color(red: 0.16, green: 0.30, blue: 0.14).opacity(0.26), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: W, height: depth)
        .position(x: W / 2, y: top + depth / 2)
    }

    /// The meadow and his cushion. The phone's meadow is a 300-unit-wide
    /// portrait, so the wide frame lays it out as tiles, alternate ones
    /// mirrored, with his cushion standing in the middle one; then a second,
    /// larger row of the nearest flowers for the foreground the phone never
    /// has to draw.
    private func ground(s: CGFloat, fieldTop: CGFloat, cushion: CGFloat) -> some View {
        let W = Frame.size.width, H = Frame.size.height
        // The mid meadow: its field band (the bottom 34% of its frame) from
        // the field's top to where the foreground takes over.
        let midBottom = fieldTop + 211 * s
        let midHeight = (midBottom - fieldTop) / 0.34
        let midTile = 300 * s
        let midTop = midBottom - midHeight
        let tiles = Int((W / midTile).rounded(.up)) | 1   // odd, so one is centred
        let firstX = W / 2 - CGFloat(tiles / 2) * midTile

        // The foreground: bigger flowers, only the nearer half of a meadow.
        let nearScale = s * 1.9
        let nearHeight = (H + 40 * s - midBottom + 60 * s) / 0.34
        let nearTop = H + 40 * s - nearHeight
        let nearTile = 300 * nearScale
        let nearTiles = Int((W / nearTile).rounded(.up)) + 1

        return ZStack(alignment: .topLeading) {
            ForEach(0..<tiles, id: \.self) { i in
                let size = CGSize(width: midTile, height: midHeight)
                ZStack(alignment: .topLeading) {
                    Meadow(scale: s)
                        .frame(width: size.width, height: size.height)
                    if i == tiles / 2 {
                        Cushion()
                            .frame(width: 168 * s, height: 44 * s)
                            .position(x: size.width / 2, y: cushion - midTop - 22 * s)
                            .standsInMeadow(feetY: cushion - midTop - 6 * s, scale: s, sceneSize: size)
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(x: i.isMultiple(of: 2) == (tiles / 2).isMultiple(of: 2) ? 1 : -1, y: 1)
                // Every tile but his own nudged a little, so the same clump
                // does not stand in the same row five times.
                .position(x: firstX + CGFloat(i) * midTile + (i == tiles / 2 ? 0 : jitter(i, 1) * midTile * 0.22),
                          // Only ever down: a tile nudged up stood its far
                          // flowers on the ridge.
                          y: midTop + midHeight / 2 + (i == tiles / 2 ? 0 : abs(jitter(i, 2)) * 70 * s))
            }
            ForEach(0..<nearTiles, id: \.self) { i in
                Meadow(scale: nearScale, nearerThan: nearHeight * (1 - 0.27))
                    .frame(width: nearTile, height: nearHeight)
                    .scaleEffect(x: i.isMultiple(of: 2) ? -1 : 1, y: 1)
                    .position(x: W / 2 + (CGFloat(i) - CGFloat(nearTiles - 1) / 2) * nearTile + nearTile * 0.31
                                 + jitter(i, 3) * nearTile * 0.18,
                              y: nearTop + nearHeight / 2 + abs(jitter(i, 4)) * 50 * s)
            }
        }
        .frame(width: W, height: H)
    }

    /// A fixed number in -1...1 for tile `i`, so every render is the same.
    private func jitter(_ i: Int, _ salt: UInt64) -> CGFloat {
        var z = UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 31)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 29
        return CGFloat(Double(z >> 11) / Double(1 << 53)) * 2 - 1
    }

    /// His still, framed exactly as `OttoAuraFigure` and the widget frame
    /// it, floating at the two brightest stages.
    private func ottoFigure(s: CGFloat, cushion: CGFloat) -> some View {
        let box = variant.ottoBox
        let canvas = box * 0.95 / OttoStillCanvas.bodyShare
        let centreY = cushion - 15.5 * s - box / 2
        return Image(nsImage: otto)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: canvas * OttoStillCanvas.aspect, height: canvas)
            .offset(y: canvas * (1 - OttoStillCanvas.baseline))
            .offset(y: variant.stage >= 6 ? -box * 0.05 : 0)
            .frame(width: box, height: box, alignment: .bottom)
            .position(x: Frame.size.width / 2, y: centreY)
    }
}
