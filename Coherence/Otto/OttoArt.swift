import SwiftUI

/// Otto the sloth, drawn.
///
/// Melvin picked board 1 (sitting cross-legged, eyes closed) and the head
/// badge off `mockups/otto-sloth.html` (2026-09-16), so those two are drawn
/// here and the hanging pose is not.
///
/// **The path data is the mockup's, character for character.** The concepts
/// were hand-written SVG in the 808 mark's language (one stroke weight, round
/// caps and joins, ellipses doing the work, no fills but the eye mask), and
/// copying the `d` strings across rather than redrawing them means the art in
/// the app is the art that was approved. `SVGPath` parses the handful of
/// commands they use, so a revised drawing is a changed string rather than a
/// rewritten view.
///
/// Colour comes from outside, like the mockup's `currentColor`: the caller
/// tints it. Otto is teal wherever it appears, because teal is guidance and
/// gold is a measured score.
enum OttoArt {

    // MARK: - The face, in a 64 unit head

    /// Eyes closed, the three-toed mask tilted out and down, a small flat
    /// nose, the wide low smile.
    static let faceStrokes = [
        "M17 29.2Q22 33.8 27 29.2",
        "M37 29.2Q42 33.8 47 29.2",
        "M30.6 39H33.4",
        "M22 45.5Q32 53.5 42 45.5",
    ]

    /// The eye mask: the one fill in the whole drawing, a wash rather than an
    /// outline because outlining doubles the lines around the eyes and turns
    /// to mud at 24 pt.
    static let faceMask: [(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, degrees: Double)] = [
        (18.5, 31, 12, 4.8, -20),
        (45.5, 31, 12, 4.8, 20),
    ]
    static let maskOpacity: Double = 0.26

    /// The badge's head. A 64 box, so the face sits in it untransformed.
    static let badgeHead = (x: CGFloat(32), y: CGFloat(32), r: CGFloat(29))

    // MARK: - Sitting cross-legged, in a 240 box

    /// Arms, crossed legs, three claws on each hand and foot. The head and
    /// face are drawn separately so the face can be the same 64 unit drawing
    /// scaled, rather than a second copy that could drift from it.
    static let sitBody = [
        // Left arm, shoulder to the curled hand.
        "M92 101C76 106 62 118 58 136C54 150 54 162 58 172",
        "M100 118C88 130 82 148 82 166",
        "M58 172C62 184 78 184 82 166",
        "M63 180C61 186 62 192 66 196",
        "M70 182C69 188 70 194 74 198",
        "M77 180C77 186 78 192 82 195",
        // Right arm: the same six paths mirrored about x = 120.
        "M148 101C164 106 178 118 182 136C186 150 186 162 182 172",
        "M140 118C152 130 158 148 158 166",
        "M182 172C178 184 162 184 158 166",
        "M177 180C179 186 178 192 174 196",
        "M170 182C171 188 170 194 166 198",
        "M163 180C163 186 162 192 158 195",
        // The seat and the crossed legs.
        "M58 172C44 178 42 196 60 204C92 214 148 214 180 204C198 196 196 178 182 172",
        "M156 170C134 178 100 190 72 203",
        "M82 168C96 176 110 182 122 186",
        "M72 203C66 204 60 208 60 213",
        "M77 205C72 207 68 211 68 215",
        "M82 206C78 209 76 213 77 217",
    ]

    /// The head: an ellipse, 84 wide.
    static let sitHead = (x: CGFloat(120), y: CGFloat(74), rx: CGFloat(42), ry: CGFloat(38))
    /// Where the 64 unit face lands inside the 240 box, and by how much it
    /// grows. 84 / 64 = 1.3125.
    static let sitFaceScale: CGFloat = 1.3125
    static let sitFaceOrigin = CGPoint(x: 120 - 32 * 1.3125, y: 74 - 32 * 1.3125)

    // MARK: - Stroke ratios

    /// A figure's stroke is 1.5 percent of its artboard; the badge's is 5
    /// percent of its diameter. The badge is heavier on purpose: it is an
    /// optical size for 24 to 56 pt, where the figure's ratio is a hairline.
    static let figureStrokeRatio: CGFloat = 0.015
    static let badgeStrokeRatio: CGFloat = 0.05
}

// MARK: - The SVG path data

/// The subset of SVG path data the drawings use: absolute M, L, H, V, C and
/// Q. Enough for every string in `OttoArt`, and it fails to nothing (an empty
/// path) rather than guessing at a command it does not know.
struct SVGPath {
    let commands: [Command]

    enum Command: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case cubic(to: CGPoint, c1: CGPoint, c2: CGPoint)
        case quad(to: CGPoint, c: CGPoint)
    }

    init(_ d: String) {
        var commands: [Command] = []
        var numbers: [CGFloat] = []
        var letter: Character = " "
        var current = CGPoint.zero
        var token = ""

        func flushNumber() {
            if let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        func flushCommand() {
            flushNumber()
            switch letter {
            case "M", "L":
                // A repeated pair after M is an implicit lineto, per SVG.
                var i = 0
                while i + 1 < numbers.count {
                    let p = CGPoint(x: numbers[i], y: numbers[i + 1])
                    commands.append(letter == "M" && i == 0 ? .move(p) : .line(p))
                    current = p
                    i += 2
                }
            case "H":
                for x in numbers {
                    current = CGPoint(x: x, y: current.y)
                    commands.append(.line(current))
                }
            case "V":
                for y in numbers {
                    current = CGPoint(x: current.x, y: y)
                    commands.append(.line(current))
                }
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    let c1 = CGPoint(x: numbers[i], y: numbers[i + 1])
                    let c2 = CGPoint(x: numbers[i + 2], y: numbers[i + 3])
                    let to = CGPoint(x: numbers[i + 4], y: numbers[i + 5])
                    commands.append(.cubic(to: to, c1: c1, c2: c2))
                    current = to
                    i += 6
                }
            case "Q":
                var i = 0
                while i + 3 < numbers.count {
                    let c = CGPoint(x: numbers[i], y: numbers[i + 1])
                    let to = CGPoint(x: numbers[i + 2], y: numbers[i + 3])
                    commands.append(.quad(to: to, c: c))
                    current = to
                    i += 4
                }
            default:
                break
            }
            numbers = []
        }

        for ch in d {
            if ch.isLetter {
                flushCommand()
                letter = ch
            } else if ch == "-" && !token.isEmpty && token.last != "e" {
                // A minus with digits behind it starts the next number.
                flushNumber()
                token = "-"
            } else if ch == "," || ch == " " {
                flushNumber()
            } else {
                token.append(ch)
            }
        }
        flushCommand()
        self.commands = commands
    }

    /// Appends the commands into `path`, mapped through `transform`.
    func append(to path: inout Path, _ transform: CGAffineTransform) {
        func at(_ p: CGPoint) -> CGPoint { p.applying(transform) }
        for command in commands {
            switch command {
            case .move(let p):               path.move(to: at(p))
            case .line(let p):               path.addLine(to: at(p))
            case .cubic(let to, let a, let b): path.addCurve(to: at(to), control1: at(a), control2: at(b))
            case .quad(let to, let c):       path.addQuadCurve(to: at(to), control: at(c))
            }
        }
    }
}

// MARK: - The drawings

/// Otto's head as a round badge: the chat icon, the row mark, the header.
/// Melvin, 2026-09-16: "i definitely like having his face as an icon".
struct OttoSlothBadge: View {
    var size: CGFloat = 32
    var dimmed = false

    var body: some View {
        // The badge is a 64 unit drawing, so one scale maps the whole thing.
        let t = CGAffineTransform(scaleX: size / 64, y: size / 64)
        ZStack {
            OttoFaceMask(transform: t)
            Path { path in
                let head = OttoArt.badgeHead
                path.addEllipse(in: CGRect(x: head.x - head.r, y: head.y - head.r,
                                           width: head.r * 2, height: head.r * 2)
                    .applying(t))
                for d in OttoArt.faceStrokes { SVGPath(d).append(to: &path, t) }
            }
            .stroke(style: StrokeStyle(lineWidth: max(1, size * OttoArt.badgeStrokeRatio),
                                       lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}

/// Otto sitting cross-legged, eyes closed: the big placements (the locked
/// state, an empty chat, the store screenshot).
struct OttoSlothSitting: View {
    var size: CGFloat = 160

    var body: some View {
        let scale = size / 240
        let t = CGAffineTransform(scaleX: scale, y: scale)
        // The face is the same 64 unit drawing, grown into the 240 box and
        // moved onto the head: scale it, place it, then map the box to the
        // view. One drawing of the face, so the badge and the figure cannot
        // drift apart.
        let face = CGAffineTransform(scaleX: OttoArt.sitFaceScale, y: OttoArt.sitFaceScale)
            .concatenating(CGAffineTransform(translationX: OttoArt.sitFaceOrigin.x,
                                             y: OttoArt.sitFaceOrigin.y))
            .concatenating(t)
        ZStack {
            OttoFaceMask(transform: face)
            Path { path in
                let head = OttoArt.sitHead
                path.addEllipse(in: CGRect(x: head.x - head.rx, y: head.y - head.ry,
                                           width: head.rx * 2, height: head.ry * 2)
                    .applying(t))
                for d in OttoArt.faceStrokes { SVGPath(d).append(to: &path, face) }
                for d in OttoArt.sitBody { SVGPath(d).append(to: &path, t) }
            }
            .stroke(style: StrokeStyle(lineWidth: max(1, size * OttoArt.figureStrokeRatio),
                                       lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The eye mask, the one filled shape in either drawing: two rotated
/// ellipses at 26 percent of the tint. Takes the same transform as the
/// strokes it sits under, so it lands with them at any size.
private struct OttoFaceMask: View {
    let transform: CGAffineTransform

    var body: some View {
        Path { path in
            for e in OttoArt.faceMask {
                let rect = CGRect(x: -e.rx, y: -e.ry, width: e.rx * 2, height: e.ry * 2)
                let place = CGAffineTransform(rotationAngle: e.degrees * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: e.x, y: e.y))
                    .concatenating(transform)
                path.addEllipse(in: rect, transform: place)
            }
        }
        .fill(.tint.opacity(OttoArt.maskOpacity))
    }
}
