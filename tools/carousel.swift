import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// 808 carousel slide renderer.
//
// Reads a deck described in JSON and writes one PNG per slide, in every
// requested size. The copy is written elsewhere (by hand, or by the carousel
// generator's ads flow); this tool only ever LAYS OUT copy it is given. That
// split is deliberate: a model is good at hooks and bad at consistency, and
// the whole 808 position is that the brand looks deliberate.
//
//   swift tools/carousel.swift <deck.json> <outdir> [ig|vertical|square|all]
//
// Sizes:
//   ig        1080x1350   Instagram carousel, the default
//   vertical  1080x1920   TikTok photo posts, Stories, and later the frames a
//                         reel is cut from. Same deck, no second write-up.
//   square    1080x1080   feed, when a square set is asked for
//
// Every rule in marketing/CAROUSEL_BRIEF.md that a machine can check is checked
// here and fails the render rather than warning. See `lint`.

// MARK: - Tokens
//
// Straight from the brief's palette table. Written as hex so they can be
// diffed against that table by eye; the app's own no-hardcoded-hex rule is
// about routing through AppColor, and this tool has no asset catalog to route
// through.

func hex(_ s: String, _ alpha: Double = 1) -> CGColor {
    var v: UInt64 = 0
    Scanner(string: s.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return CGColor(red: Double((v >> 16) & 0xFF) / 255,
                   green: Double((v >> 8) & 0xFF) / 255,
                   blue: Double(v & 0xFF) / 255, alpha: alpha)
}

enum Ink {
    static let bg     = hex("#13100D")
    static let card   = hex("#221E19")
    static let border = hex("#2E2A23")
    static let fg     = hex("#F5F3EC")
    static let muted  = hex("#9A9A93")
    static let dim    = hex("#55534E")
    static let gold   = hex("#D4AF37")
    static func gold(_ a: Double) -> CGColor { hex("#D4AF37", a) }
}

// MARK: - Faces
//
// Loaded from marketing/fonts rather than the system, because the three brand
// faces are not installed on either cofounder's Mac and a silent fallback to
// SF Pro would ship a carousel that does not match the website.

/// The repo root, derived from this file's own location rather than from the
/// working directory. Fonts and screenshot paths are repo-relative, and
/// resolving them against the cwd meant the tool only ran from one directory
/// and blamed the screenshot when it did not.
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()      // tools/
    .deletingLastPathComponent()      // repo root

/// Repo-relative unless the deck gave an absolute path.
func resolve(_ path: String) -> String {
    path.hasPrefix("/") ? path : repoRoot.appendingPathComponent(path).path
}

let fontDir: URL = repoRoot.appendingPathComponent("marketing/fonts")

var faceCache: [String: CGFont] = [:]

func face(_ file: String, _ size: Double) -> CTFont {
    if let cached = faceCache[file] {
        return CTFontCreateWithGraphicsFont(cached, size, nil, nil)
    }
    let url = fontDir.appendingPathComponent(file + ".ttf")
    guard let p = CGDataProvider(url: url as CFURL), let cg = CGFont(p) else {
        fputs("missing font \(file).ttf in \(fontDir.path)\n", stderr)
        exit(1)
    }
    faceCache[file] = cg
    return CTFontCreateWithGraphicsFont(cg, size, nil, nil)
}

enum Face {
    static func display(_ s: Double) -> CTFont { face("Manrope-ExtraBold", s) }
    static func displayBold(_ s: Double) -> CTFont { face("Manrope-Bold", s) }
    static func body(_ s: Double) -> CTFont { face("HankenGrotesk-Regular", s) }
    static func bodyEm(_ s: Double) -> CTFont { face("HankenGrotesk-SemiBold", s) }
    static func mono(_ s: Double) -> CTFont { face("DMMono-Medium", s) }
}

// MARK: - Type setting

let kFont = NSAttributedString.Key(kCTFontAttributeName as String)
let kColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
let kKern = NSAttributedString.Key(kCTKernAttributeName as String)

/// Build one line, optionally painting a single word or phrase in a second
/// colour. The highlight is how a slide spends its one gold element on a word
/// inside a headline rather than on the kicker above it.
func attributed(_ text: String, font: CTFont, color: CGColor, tracking: Double,
                highlight: String?, highlightColor: CGColor) -> NSAttributedString {
    let s = NSMutableAttributedString(string: text, attributes: [
        kFont: font, kColor: color, kKern: tracking,
    ])
    if let h = highlight, !h.isEmpty {
        // Case-insensitive so the deck can say "blind" and the copy "Blind".
        var searchStart = text.startIndex
        while let r = text.range(of: h, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            s.addAttribute(kColor, value: highlightColor, range: NSRange(r, in: text))
            searchStart = r.upperBound
        }
    }
    return s
}

func width(_ text: String, _ font: CTFont, _ tracking: Double) -> Double {
    let line = CTLineCreateWithAttributedString(
        attributed(text, font: font, color: Ink.fg, tracking: tracking,
                   highlight: nil, highlightColor: Ink.fg))
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

/// Greedy word wrap. Long single words are left to overflow rather than
/// hyphenated; the fit loop below shrinks the size until they stop.
func wrap(_ text: String, font: CTFont, tracking: Double, maxWidth: Double) -> [String] {
    var lines: [String] = []
    for paragraph in text.components(separatedBy: "\n") {
        var current = ""
        for word in paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if width(candidate, font, tracking) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        lines.append(current)
    }
    return lines
}

/// Shrink until the copy fits both the width and the line budget. Returns the
/// size actually used, so callers can lay out what comes after it.
func fit(_ text: String, maker: (Double) -> CTFont, tracking: Double,
         maxWidth: Double, maxLines: Int, from: Double, to: Double) -> (size: Double, lines: [String]) {
    var size = from
    while size > to {
        let f = maker(size)
        let lines = wrap(text, font: f, tracking: tracking * size, maxWidth: maxWidth)
        if lines.count <= maxLines && lines.allSatisfy({ width($0, f, tracking * size) <= maxWidth }) {
            return (size, lines)
        }
        size -= 2
    }
    let f = maker(to)
    return (to, wrap(text, font: f, tracking: tracking * to, maxWidth: maxWidth))
}

enum Align { case left, center }

/// Draws one line and returns nothing useful; callers advance their own cursor,
/// because every slide kind wants different leading.
func put(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor,
         tracking: Double, x: Double, boxWidth: Double, baseline: Double,
         align: Align, highlight: String? = nil, highlightColor: CGColor = Ink.gold) {
    let attr = attributed(text, font: font, color: color, tracking: tracking,
                          highlight: highlight, highlightColor: highlightColor)
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: align == .center ? x + (boxWidth - w) / 2 : x, y: baseline)
    CTLineDraw(line, ctx)
}

// MARK: - Deck

struct Slide: Decodable {
    var kind: String                // hook | statement | stat | shot | quote | cta
    var kicker: String?             // DM Mono, uppercased on render
    var headline: String?
    var highlight: String?          // a word inside the headline, painted gold
    var body: String?
    var value: String?              // stat: the number itself
    var label: String?              // stat: what the number is of
    var source: String?             // stat: citation, or the research caveat
    var quote: String?
    var attribution: String?
    var image: String?              // repo-relative path to a REAL screenshot
    var cta: String?
}

struct Deck: Decodable {
    var topic: String?
    var handle: String?
    var slides: [Slide]
}

extension Slide {
    /// Every string a reader will actually see. The lint reads this, so a new
    /// field is linted the moment it is added here.
    var copy: [String] {
        [kicker, headline, body, value, label, source, quote, attribution, cta].compactMap { $0 }
    }
}

// MARK: - Lint
//
// Only rules a machine can settle. "Is there an invented number about the
// user" and "does this make sense to a stranger" stay human checks, and the
// brief's section 13 is still the list to read before publishing.

/// Always wrong, in any context. These fail the render.
let hardBans: [(needle: String, why: String)] = [
    ("—", "em dash. Restructure the sentence: usually two sentences, sometimes a colon, often just delete it."),
    ("–", "en dash reads the same way an em dash does. Restructure."),
    ("scientifically proven", "808 does not get to say this about anything."),
    ("23 minutes", "the refocus statistic has no paper behind it."),
    ("download now", "pre-launch. The only CTA is the waitlist."),
    ("app store", "pre-launch. The only CTA is the waitlist."),
    ("48%", "the cardiac-events figure needs three paragraphs of context a slide cannot carry."),
]

/// Usually wrong, occasionally the honest word. These print and keep going.
let softBans = [
    "brainwave", "theta", "hrv", "nervous system", "biohack", "rewire",
    "transform", "optimize", "unlock your potential",
]

func lint(_ deck: Deck) {
    var failures: [String] = []
    for (i, slide) in deck.slides.enumerated() {
        let n = i + 1
        for text in slide.copy {
            let lower = text.lowercased()
            for ban in hardBans where lower.contains(ban.needle) {
                failures.append("slide \(n): \(ban.why)\n           \"\(text)\"")
            }
            for word in softBans where lower.contains(word) {
                fputs("  warn  slide \(n): \"\(word)\" is on the avoid list. Keep it only if the "
                      + "sentence is denying the claim rather than making it.\n", stderr)
            }
        }
        // Rule 7 of the self-check: every screenshot is a real one.
        if let img = slide.image, !FileManager.default.fileExists(atPath: resolve(img)) {
            failures.append("slide \(n): no screenshot at \(img). Real screenshots live in "
                            + "marketing/appstore/ and website/img/.")
        }
    }
    guard failures.isEmpty else {
        fputs("\nDeck rejected:\n\n", stderr)
        for f in failures { fputs("  \(f)\n\n", stderr) }
        exit(1)
    }
}

// MARK: - Canvas

struct Format {
    let name: String
    let w: Double
    let h: Double
    /// Fraction of the height that platform UI sits over. Nothing is drawn
    /// into it. Reels, TikTok and Stories all lay a caption bar and an action
    /// rail over the bottom of a vertical frame.
    let bottomReserve: Double
}

let formats: [Format] = [
    Format(name: "ig", w: 1080, h: 1350, bottomReserve: 0.06),
    Format(name: "vertical", w: 1080, h: 1920, bottomReserve: 0.18),
    Format(name: "square", w: 1080, h: 1080, bottomReserve: 0.06),
]

/// A slide being drawn. Owns the cursor so the slide kinds below read as a
/// sequence of blocks rather than arithmetic, and owns the gold budget so the
/// brief's one-gold-element rule is enforced rather than remembered.
final class Slate {
    let ctx: CGContext
    let f: Format
    let margin: Double = 90            // brief section 6: 90px from every edge
    var y: Double                      // distance from the TOP to the next baseline
    private var goldUsed = 0

    var contentWidth: Double { f.w - margin * 2 }
    var floor: Double { f.h * (1 - f.bottomReserve) }   // lowest drawable y-from-top

    init(_ ctx: CGContext, _ f: Format) {
        self.ctx = ctx
        self.f = f
        self.y = f.h * (f.h > 1400 ? 0.16 : 0.13)
    }

    /// Claim the slide's single gold element. Calling it twice is the bug the
    /// brief warns about, so it is fatal rather than a warning.
    func claimGold(_ what: String) -> CGColor {
        goldUsed += 1
        if goldUsed > 1 {
            fputs("two gold elements on one slide (\(what) was the second). "
                  + "Exactly one, or neither is the point.\n", stderr)
            exit(1)
        }
        return Ink.gold
    }

    func sealGold(_ slideNumber: Int) {
        if goldUsed != 1 {
            fputs("slide \(slideNumber) spends its gold \(goldUsed) times. It must be exactly once.\n", stderr)
            exit(1)
        }
    }

    /// CG counts from the bottom left; every layout number here counts from the top.
    func baseline(_ fromTop: Double) -> Double { f.h - fromTop }

    // MARK: blocks

    func kicker(_ text: String, gold: Bool) {
        let size = f.w * 0.0235
        let color = gold ? claimGold("kicker") : Ink.muted
        put(ctx, text.uppercased(), font: Face.mono(size), color: color,
            tracking: size * 0.10, x: margin, boxWidth: contentWidth,
            baseline: baseline(y), align: .left)
        y += size * 2.4
    }

    func headline(_ text: String, highlight: String?, scale: Double = 1.0, maxLines: Int = 3) {
        let top = f.w * 0.086 * scale
        let (size, lines) = fit(text, maker: Face.display, tracking: -0.02,
                                maxWidth: contentWidth, maxLines: maxLines,
                                from: top, to: top * 0.55)
        let highlightColor = highlight == nil ? Ink.fg : claimGold("headline word")
        for line in lines {
            put(ctx, line, font: Face.display(size), color: Ink.fg,
                tracking: -0.02 * size, x: margin, boxWidth: contentWidth,
                baseline: baseline(y + size), align: .left,
                highlight: highlight, highlightColor: highlightColor)
            y += size * 1.16
        }
        y += size * 0.30
    }

    func body(_ text: String, color: CGColor = Ink.muted, emphasis: Bool = false) {
        let size = f.w * 0.0345
        let maker = emphasis ? Face.bodyEm : Face.body
        for line in wrap(text, font: maker(size), tracking: 0, maxWidth: contentWidth) {
            put(ctx, line, font: maker(size), color: color, tracking: 0,
                x: margin, boxWidth: contentWidth, baseline: baseline(y + size), align: .left)
            y += size * 1.55            // brief section 4: body line height ~1.55
        }
        y += size * 0.5
    }

    func caption(_ text: String, color: CGColor = Ink.dim) {
        let size = f.w * 0.021
        for line in wrap(text, font: Face.mono(size), tracking: size * 0.04, maxWidth: contentWidth) {
            put(ctx, line, font: Face.mono(size), color: color, tracking: size * 0.04,
                x: margin, boxWidth: contentWidth, baseline: baseline(y + size), align: .left)
            y += size * 1.6
        }
    }

    /// Citations and caveats. Deliberately NOT the mono face: mono is for
    /// labels, and a four-line source note set in it reads as a wall rather
    /// than as the honest small print it is meant to be.
    func fineprint(_ text: String) {
        let size = f.w * 0.0225
        for line in wrap(text, font: Face.body(size), tracking: 0, maxWidth: contentWidth) {
            put(ctx, line, font: Face.body(size), color: Ink.dim, tracking: 0,
                x: margin, boxWidth: contentWidth, baseline: baseline(y + size), align: .left)
            y += size * 1.5
        }
    }
}

// MARK: - Decoration

extension Slate {
    /// The warm radial glow the brief permits, and the only gradient allowed.
    func bloom(atFractionOfHeight fy: Double) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let g = CGGradient(colorsSpace: cs,
                                 colors: [Ink.gold(0.14), Ink.gold(0)] as CFArray,
                                 locations: [0, 1]) else { return }
        let c = CGPoint(x: f.w / 2, y: f.h * (1 - fy))
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: min(f.w, f.h) * 0.62, options: [])
    }

    /// The 808 quatrefoil. Geometry is Melvin's, lifted from tools/endcard.swift
    /// so the two tools cannot drift into drawing different marks.
    func mark(cx: Double, cyFromTop: Double, size s: Double, color: CGColor) {
        let cy = baseline(cyFromTop)
        let W = 0.135, H = 0.205, OFF = 0.215, R0 = 0.150, LW = 0.026
        func ellipse(_ ecx: Double, _ ecy: Double, _ rx: Double, _ ry: Double) {
            ctx.addEllipse(in: CGRect(x: ecx - rx, y: ecy - ry, width: 2 * rx, height: 2 * ry))
            ctx.strokePath()
        }
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(s * LW)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for dy in [-OFF, OFF] { ellipse(cx, cy + dy * s, W * s, H * s) }
        for dx in [-OFF, OFF] { ellipse(cx + dx * s, cy, H * s, W * s) }
        ellipse(cx, cy, R0 * s, R0 * s)
        ctx.restoreGState()
    }

    /// A real screenshot in the drawn bezel from tools/store_shots.swift: thin
    /// dark ring, one silver hairline, deep shadow. Never a chunky white case.
    /// The phone bleeds off the bottom, which survives the crop every platform
    /// applies somewhere.
    func phone(_ shot: CGImage, topFromTop: Double, widthFraction: Double = 0.62) {
        let phoneW = f.w * widthFraction
        let scale = phoneW / Double(shot.width)
        let phoneH = Double(shot.height) * scale
        let x = (f.w - phoneW) / 2
        let yBottom = baseline(topFromTop + phoneH)
        let bezel = phoneW * 0.013
        let radius = phoneW * 0.107
        let outer = CGRect(x: x - bezel, y: yBottom - bezel,
                           width: phoneW + bezel * 2, height: phoneH + bezel * 2)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        ctx.setFillColor(CGColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius + bezel,
                           cornerHeight: radius + bezel, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: yBottom, width: phoneW, height: phoneH),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(shot, in: CGRect(x: x, y: yBottom, width: phoneW, height: phoneH))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: outer.insetBy(dx: 1.5, dy: 1.5),
                           cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
        ctx.setStrokeColor(CGColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The card panel from the palette table. Used for testimonials, which are
    /// quoted verbatim and therefore need a container that says "this is
    /// someone else talking".
    func panel(height: Double) -> Double {
        let r = CGRect(x: margin, y: baseline(y + height), width: contentWidth, height: height)
        let path = CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.saveGState()
        ctx.setFillColor(Ink.card)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(Ink.border)
        ctx.setLineWidth(2)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
        return r.height
    }

    /// Slide number, bottom left, dim. The brief assigns Dim to exactly this.
    func number(_ n: Int, of total: Int) {
        let size = f.w * 0.019
        put(ctx, String(format: "%02d / %02d", n, total), font: Face.mono(size),
            color: Ink.dim, tracking: size * 0.10, x: margin, boxWidth: contentWidth,
            baseline: baseline(floor - size * 0.4), align: .left)
    }
}

// MARK: - Slide kinds

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: resolve(path)) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Lays out one slide's copy from the cursor down. Called twice per slide:
/// once against a throwaway context to learn how tall the block came out, then
/// again for real with the cursor moved so the block sits centred. Measuring by
/// drawing is the only honest way to do it here, because the type shrinks to
/// fit and the final height is not knowable until it has.
func layout(_ s: Slide, _ p: Slate, n: Int) {
    switch s.kind {

    // Slide 1. It is the only slide most people see, so it gets the largest
    // type on the ground with nothing else competing.
    case "hook":
        if let k = s.kicker { p.kicker(k, gold: s.highlight == nil) }
        p.headline(s.headline ?? "", highlight: s.highlight, scale: 1.25, maxLines: 4)
        if let b = s.body { p.body(b) }

    case "statement":
        if let k = s.kicker { p.kicker(k, gold: s.highlight == nil) }
        p.headline(s.headline ?? "", highlight: s.highlight, scale: 1.0, maxLines: 3)
        if let b = s.body { p.body(b) }

    // The kicker names the felt effect, the number is the gold. "A sharper
    // mind" above "+16 points", never the reverse.
    case "stat":
        if let k = s.kicker { p.kicker(k, gold: false) }
        let size = p.f.w * 0.20
        put(p.ctx, s.value ?? "", font: Face.display(size), color: p.claimGold("stat value"),
            tracking: -0.02 * size, x: p.margin, boxWidth: p.contentWidth,
            baseline: p.baseline(p.y + size), align: .left)
        p.y += size * 1.24
        if let l = s.label { p.body(l, color: Ink.fg) }
        if let src = s.source { p.y += 18; p.fineprint(src) }

    // A screenshot always beats a claim, so the copy here is short and the
    // phone gets the rest of the frame.
    case "shot":
        if let k = s.kicker { p.kicker(k, gold: s.highlight == nil) }
        p.headline(s.headline ?? "", highlight: s.highlight, scale: 0.78, maxLines: 2)
        if let b = s.body { p.body(b) }

    case "quote":
        if let k = s.kicker { p.kicker(k, gold: true) }
        let qSize = p.f.w * 0.040
        let inset = 52.0
        let lines = wrap(s.quote ?? "", font: Face.body(qSize), tracking: 0,
                         maxWidth: p.contentWidth - inset * 2)
        let panelH = Double(lines.count) * qSize * 1.55 + inset * 2
        _ = p.panel(height: panelH)
        var ty = p.y + inset
        for line in lines {
            put(p.ctx, line, font: Face.body(qSize), color: Ink.fg, tracking: 0,
                x: p.margin + inset, boxWidth: p.contentWidth - inset * 2,
                baseline: p.baseline(ty + qSize), align: .left)
            ty += qSize * 1.55
        }
        p.y += panelH + 34
        if let a = s.attribution { p.caption(a) }

    default:
        fputs("unknown slide kind \"\(s.kind)\" on slide \(n). "
              + "Known: hook, statement, stat, shot, quote, cta.\n", stderr)
        exit(1)
    }
}

/// The closing slide. Centred rather than left-aligned, and laid out by hand
/// rather than through the cursor, because it is a lockup and not a column of
/// copy.
func layoutCTA(_ s: Slide, _ p: Slate, handle: String?) {
    let f = p.f
    p.bloom(atFractionOfHeight: 0.52)
    let markSize = f.w * 0.135
    let markCY = f.h * 0.33
    // The mark and the wordmark are both gold, but they are one lockup, so
    // they cost the slide's gold once between them.
    p.mark(cx: f.w / 2, cyFromTop: markCY, size: markSize, color: p.claimGold("brand lockup"))
    let wSize = f.w * 0.058
    put(p.ctx, "808", font: Face.display(wSize), color: Ink.gold, tracking: -0.02 * wSize,
        x: 0, boxWidth: f.w, baseline: p.baseline(markCY + markSize * 0.42 + wSize), align: .center)

    var cy = markCY + markSize * 0.42 + wSize * 2.6
    let hSize = f.w * 0.062
    for line in wrap(s.headline ?? "", font: Face.display(hSize), tracking: -0.02 * hSize,
                     maxWidth: p.contentWidth) {
        put(p.ctx, line, font: Face.display(hSize), color: Ink.fg, tracking: -0.02 * hSize,
            x: 0, boxWidth: f.w, baseline: p.baseline(cy + hSize), align: .center)
        cy += hSize * 1.16
    }
    cy += hSize * 0.6
    if let b = s.body {
        let bSize = f.w * 0.0345
        for line in wrap(b, font: Face.body(bSize), tracking: 0, maxWidth: p.contentWidth) {
            put(p.ctx, line, font: Face.body(bSize), color: Ink.muted, tracking: 0,
                x: 0, boxWidth: f.w, baseline: p.baseline(cy + bSize), align: .center)
            cy += bSize * 1.55
        }
    }
    p.y = cy

    let dSize = f.w * 0.026
    put(p.ctx, s.cta ?? "meditate808.com", font: Face.mono(dSize), color: Ink.muted,
        tracking: dSize * 0.10, x: 0, boxWidth: f.w,
        baseline: p.baseline(p.floor - dSize * 2.4), align: .center)
    if let h = handle {
        put(p.ctx, h, font: Face.mono(dSize * 0.85), color: Ink.dim, tracking: dSize * 0.08,
            x: 0, boxWidth: f.w, baseline: p.baseline(p.floor - dSize * 0.6), align: .center)
    }
}

func newContext(_ f: Format) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(f.w), height: Int(f.h),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fputs("no context\n", stderr); exit(1)
    }
    return ctx
}

func render(_ s: Slide, n: Int, of total: Int, f: Format, handle: String?) -> CGImage {
    let ctx = newContext(f)
    ctx.setFillColor(Ink.bg)
    ctx.fill(CGRect(x: 0, y: 0, width: f.w, height: f.h))
    let p = Slate(ctx, f)

    if s.kind == "cta" {
        layoutCTA(s, p, handle: handle)
    } else {
        // Measure, then place. A shot slide stays top-anchored: its phone is
        // supposed to bleed off the bottom edge, which survives the crop every
        // platform applies somewhere.
        let scratch = Slate(newContext(f), f)
        let start = scratch.y
        layout(s, scratch, n: n)
        let blockHeight = scratch.y - start

        if s.kind != "shot" {
            p.y = max(f.h * 0.10, (p.floor - blockHeight) / 2)
        }
        switch s.kind {
        case "hook":  p.bloom(atFractionOfHeight: 1 - (p.y + blockHeight / 2) / f.h)
        case "stat":  p.bloom(atFractionOfHeight: 1 - (p.y + blockHeight / 2) / f.h)
        default: break
        }
        layout(s, p, n: n)

        if s.kind == "shot", let path = s.image, let img = loadImage(path) {
            p.phone(img, topFromTop: p.y + f.h * 0.02)
        }
    }

    if s.kind != "cta" { p.number(n, of: total) }
    p.sealGold(n)

    // Copy that runs past the reserved bottom is a layout failure, not a taste
    // call: on a vertical frame the platform's own UI is sitting there.
    if p.y > p.floor && s.kind != "shot" {
        fputs("slide \(n) (\(f.name)): copy overruns the safe area by "
              + "\(Int(p.y - p.floor))px. Shorten it.\n", stderr)
        exit(1)
    }

    guard let image = ctx.makeImage() else { fputs("render failed\n", stderr); exit(1) }
    return image
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("""
    usage: swift tools/carousel.swift <deck.json> <outdir> [ig|vertical|square|all]

      ig        1080x1350  Instagram carousel (default)
      vertical  1080x1920  TikTok, Stories, and the frames a reel is cut from
      square    1080x1080  feed
    """)
    exit(1)
}
let deckPath = args[1]
let outDir = URL(fileURLWithPath: args[2])
let want = args.count > 3 ? args[3] : "ig"

guard let data = FileManager.default.contents(atPath: deckPath) else {
    fputs("cannot read \(deckPath)\n", stderr); exit(1)
}
let deck: Deck
do { deck = try JSONDecoder().decode(Deck.self, from: data) }
catch { fputs("bad deck: \(error)\n", stderr); exit(1) }

lint(deck)

let chosen = want == "all" ? formats : formats.filter { $0.name == want }
guard !chosen.isEmpty else { fputs("unknown size \"\(want)\"\n", stderr); exit(1) }

for f in chosen {
    let dir = outDir.appendingPathComponent(f.name)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    print("\(deck.topic ?? "deck") · \(f.name) \(Int(f.w))x\(Int(f.h)):")
    for (i, slide) in deck.slides.enumerated() {
        let img = render(slide, n: i + 1, of: deck.slides.count, f: f, handle: deck.handle)
        let url = dir.appendingPathComponent(String(format: "slide-%02d.png", i + 1))
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("  \(url.lastPathComponent)  \(slide.kind)")
    }
}
