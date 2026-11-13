import CoreGraphics

/// Where each of Otto's forms carries a hat (2026-11-12): every hat he owns
/// works on every form (Melvin, 2026-11-10: "hats carry over").
///
/// **Measured, never placed by eye.** `tools/companion_head_measure.swift`
/// reads each form and stage's head off the clean drawings the rigs animate
/// (`mockups/companions/master/`, 2x), in the 664 x 744 canvas every still and
/// rig shares: the centre between the eyes, the top of the skull, the brow
/// width, the top of the eyes, and the top of anything drawn above the head
/// (ears, horns, a crest). Otto's Steady, measured the same way, is the
/// reference: each hat's Steady box (`HatArt.placement`, where it was
/// generated on him) is carried onto a form by scaling with the brow and
/// hanging it from the skull, then raised until it clears the eyes by what it
/// cleared Otto's. No new art: the same hat pictures, in three depths where
/// they were cut that way (`OttoAuraFigure` draws them).
///
/// The rig's body at rest is exactly its still (both are cut from the same
/// master onto the same canvas), so these numbers hold on the rig too, plus
/// the rig's own `Lift` and float at the bright stages.
enum CompanionHeads {
    struct Head {
        let cx: CGFloat
        let skull: CGFloat
        let browW: CGFloat
        let eyeTop: CGFloat
        let top: CGFloat
        let topCentral: CGFloat
        /// The top of the eye, or of the dark patch round it where the form
        /// has one (red panda, phoenix), read BY HAND off the masters with a
        /// ruler (2026-11-13). `eyeTop` is the tool's dark-blob top: the pupil
        /// on an open eye but the lid line on a closed one, so it moved
        /// about the face from stage to stage and could not carry a gap.
        var eye: CGFloat = 0
    }

    /// Otto's Steady (`OttoAura4`), measured by the same tool.
    static let otto = Head(cx: 332.5, skull: 84.0, browW: 342.0, eyeTop: 186.0, top: 41.0, topCentral: 41.0, eye: 186.0)

    /// Stages 1 to 7, per form. The output of `tools/companion_head_measure.swift`.
    static let heads: [Companion: [Head]] = [
        .redPanda: [
            .init(cx: 332.0, skull: 196.0, browW: 271.5, eyeTop: 393.0, top: 157.5, topCentral: 157.5, eye: 392.0),
            .init(cx: 329.6, skull: 178.0, browW: 310.0, eyeTop: 353.5, top: 140.0, topCentral: 140.0, eye: 338.0),
            .init(cx: 330.0, skull: 160.5, browW: 336.5, eyeTop: 279.0, top: 106.5, topCentral: 106.5, eye: 270.0),
            .init(cx: 332.3, skull: 157.0, browW: 338.0, eyeTop: 278.0, top: 112.0, topCentral: 112.0, eye: 266.0),
            .init(cx: 339.3, skull: 131.5, browW: 322.0, eyeTop: 237.5, top: 89.0, topCentral: 89.0, eye: 221.0),
            .init(cx: 337.7, skull: 128.5, browW: 359.0, eyeTop: 261.0, top: 82.5, topCentral: 82.5, eye: 223.0),
            .init(cx: 333.3, skull: 107.5, browW: 360.0, eyeTop: 235.5, top: 60.0, topCentral: 60.0, eye: 206.0),
        ],
        .tiger: [
            .init(cx: 339.1, skull: 152.5, browW: 305.5, eyeTop: 325.0, top: 113.5, topCentral: 113.5, eye: 314.0),
            .init(cx: 332.2, skull: 154.5, browW: 315.0, eyeTop: 306.0, top: 125.5, topCentral: 125.5, eye: 291.0),
            .init(cx: 331.7, skull: 153.0, browW: 318.0, eyeTop: 247.0, top: 122.0, topCentral: 124.5, eye: 235.0),
            .init(cx: 332.3, skull: 141.5, browW: 302.5, eyeTop: 231.5, top: 106.0, topCentral: 111.5, eye: 223.0),
            .init(cx: 332.7, skull: 99.5, browW: 311.5, eyeTop: 192.0, top: 65.5, topCentral: 69.5, eye: 177.0),
            .init(cx: 332.6, skull: 97.0, browW: 351.5, eyeTop: 215.0, top: 64.5, topCentral: 67.5, eye: 186.0),
            .init(cx: 336.8, skull: 91.5, browW: 356.0, eyeTop: 207.5, top: 62.0, topCentral: 62.5, eye: 177.0),
        ],
        .phoenix: [
            .init(cx: 340.7, skull: 268.0, browW: 171.0, eyeTop: 411.5, top: 195.0, topCentral: 196.5, eye: 405.0),
            .init(cx: 344.5, skull: 267.5, browW: 178.5, eyeTop: 380.0, top: 188.5, topCentral: 189.0, eye: 354.0),
            .init(cx: 340.5, skull: 232.5, browW: 189.5, eyeTop: 323.0, top: 177.5, topCentral: 177.5, eye: 308.0),
            .init(cx: 337.3, skull: 233.5, browW: 191.5, eyeTop: 317.0, top: 164.0, topCentral: 164.0, eye: 305.0),
            .init(cx: 343.7, skull: 181.0, browW: 214.5, eyeTop: 271.0, top: 110.0, topCentral: 110.0, eye: 252.0),
            .init(cx: 347.5, skull: 187.5, browW: 235.0, eyeTop: 282.0, top: 97.5, topCentral: 97.5, eye: 246.0),
            .init(cx: 333.3, skull: 170.0, browW: 240.5, eyeTop: 283.0, top: 93.5, topCentral: 93.5, eye: 248.0),
        ],
        .dragon: [
            .init(cx: 349.6, skull: 190.5, browW: 200.0, eyeTop: 330.5, top: 107.0, topCentral: 146.5, eye: 327.0),
            .init(cx: 338.7, skull: 187.0, browW: 200.0, eyeTop: 329.5, top: 112.0, topCentral: 163.5, eye: 310.0),
            .init(cx: 340.1, skull: 183.5, browW: 212.0, eyeTop: 268.5, top: 97.0, topCentral: 141.5, eye: 254.0),
            .init(cx: 332.3, skull: 170.5, browW: 220.0, eyeTop: 253.0, top: 83.0, topCentral: 125.0, eye: 238.0),
            .init(cx: 334.9, skull: 155.0, browW: 219.0, eyeTop: 235.0, top: 72.5, topCentral: 110.5, eye: 224.0),
            .init(cx: 338.0, skull: 153.0, browW: 228.0, eyeTop: 238.0, top: 68.5, topCentral: 107.5, eye: 217.0),
            .init(cx: 338.0, skull: 150.0, browW: 228.0, eyeTop: 234.0, top: 64.0, topCentral: 105.0, eye: 217.0),
        ],
    ]

    static func head(_ form: Companion, stage: Int) -> Head {
        let list = heads[form] ?? []
        guard !list.isEmpty else { return otto }
        return list[min(max(stage, 1), list.count) - 1]
    }

    /// How much bigger the tiara is worn on a form: cut to sit inside Otto's
    /// tuft, it read as a speck on the forms' broader heads.
    static let tiaraGrowth: CGFloat = 1.7

    /// The width the tiara is worn at on a crested or horned head, as a
    /// share of the brow, and where its band sits: this much of the brow
    /// above the top of the eyes. Hung from the skull like the other hats it
    /// floated in the phoenix's crest and between the dragon's horns,
    /// because there the "skull" row is the crest's or the horns' spread.
    static let tiaraSeatWidth: CGFloat = 0.8
    static let tiaraSeatAbove: CGFloat = 0.17
    /// How far down the tiara picture its band's centre runs (the lowest
    /// opaque row of its middle columns).
    static let tiaraBandBottom: CGFloat = 0.686

    /// The astronaut dome's width on the red panda and the tiger, the same
    /// at every stage (2026-11-13: it grew at the bright stages and the
    /// tiger's ears pressed the glass). The narrowest dome that holds the
    /// head and ears at stages 2 to 7 with 10 units to spare, measured on the
    /// masters; Withered's straggling wisps are left to poke out.
    static let domeWidth: [Companion: CGFloat] = [.redPanda: 460, .tiger: 430]

    /// Where each hat's brim begins, as a share of its picture's height: the
    /// first row at least 80% of its widest. On the phoenix only the side
    /// feathers below this are drawn back over the brim; above it they are
    /// the crest, which belongs under a tall crown.
    static let brimTop: [String: CGFloat] = [
        "sunhat": 0.513, "bucket": 0.568, "sombrero": 0.506, "tophat": 0.593,
        "wizardhat": 0.664, "monkhat": 0.565, "wanderer": 0.564, "enso": 0.577,
        "baseballcap": 0.365, "beanie": 0.527, "goldcrown": 0.375,
        "flowercrown": 0.355, "leafcrown": 0.315,
    ]

    /// A hat's box on a form and stage, in canvas units, at rest (the rig's
    /// lift and float are added by the caller).
    static func hatBox(_ id: String, form: Companion, stage: Int) -> CGRect {
        let h = head(form, stage: stage)
        if id == "tiara", form == .phoenix || form == .dragon {
            let b = HatArt.placement[id] ?? CGRect(x: 252.8, y: 56.2, width: 148.8, height: 72.2)
            let w = tiaraSeatWidth * h.browW
            let ht = w * b.height / b.width
            // A drooping head (Withered, Faded) shows its forehead
            // foreshortened, so the band goes higher up the brow there.
            let band = h.eye - (tiaraSeatAbove + (stage <= 2 ? 0.12 : 0)) * h.browW
            return CGRect(x: h.cx - w / 2, y: band - tiaraBandBottom * ht, width: w, height: ht)
        }
        var r = carried(id, form: form, stage: stage)
        switch id {
        case "halo", "tiara":
            break
        case "astronaut":
            if let w = domeWidth[form] {
                // About the collar this stage puts under his chin.
                let collar = r.minY + r.height * (360.0 + 21.9) / 416.4
                let ht = w * r.height / r.width
                r = CGRect(x: h.cx - w / 2, y: collar - ht * (360.0 + 21.9) / 416.4, width: w, height: ht)
            }
        default:
            // Never closer to the eyes than at this form's Steady: a drooping
            // head (Withered, Faded) and the bright stages each carry their
            // eyes at a different depth below the skull the hat hangs from.
            let steady = head(form, stage: 4)
            let steadyBox = carried(id, form: form, stage: 4)
            let gap = (steady.eye - steadyBox.maxY) / steady.browW
            let need = h.eye - gap * h.browW
            if r.maxY > need { r.origin.y -= r.maxY - need }
        }
        return r
    }

    /// A hat carried from Otto's Steady onto a form: scaled by the brow, hung
    /// from the skull, then raised to clear the eyes by what it cleared his.
    private static func carried(_ id: String, form: Companion, stage: Int) -> CGRect {
        let b = HatArt.placement[id] ?? CGRect(x: 172, y: -20, width: 318, height: 206)
        let h = head(form, stage: stage)
        let s = h.browW / otto.browW
        var r = CGRect(x: h.cx + (b.minX - otto.cx) * s, y: h.skull + (b.minY - otto.skull) * s,
                       width: b.width * s, height: b.height * s)
        if id == "tiara" {
            let g = tiaraGrowth
            r = CGRect(x: r.midX - r.width * g / 2, y: r.maxY - r.height * g, width: r.width * g, height: r.height * g)
        }
        switch id {
        case "halo":
            // Just above whatever rises from the head (a crest, horns, a
            // tuft). The phoenix's crest tip curls, so the ring may touch it.
            let want = h.topCentral + (form == .phoenix ? 4 : form == .dragon ? -4 : -10)
            if r.maxY > want { r.origin.y -= r.maxY - want }
            else if form == .phoenix || form == .dragon { r.origin.y += want - r.maxY }
        case "astronaut":
            // The dome grows about its collar until it takes in the ears,
            // horns or crest (Otto's tuft fit inside it as drawn).
            let collar = r.minY + r.height * (360.0 + 21.9) / 416.4
            let circleTop = r.minY + r.height * (-20 + 21.9) / 416.4
            let f = max(1, (collar - (h.top - 12)) / (collar - circleTop))
            r = CGRect(x: h.cx - (h.cx - r.minX) * f, y: collar - (collar - r.minY) * f,
                       width: r.width * f, height: r.height * f)
        default:
            // Clear the eyes by what the hat cleared Otto's at Steady.
            let gap = (otto.eyeTop - b.maxY) * s
            let need = h.eyeTop - gap
            if r.maxY > need { r.origin.y -= r.maxY - need }
        }
        return r
    }

    /// Whether the form's own ears, horns or side feathers are drawn again
    /// over a hat's brim, so it reads as worn between them rather than
    /// pasted over them. Not over the glass dome (they are inside it) or the
    /// halo (it floats clear).
    static func earsOverBrim(_ id: String) -> Bool { id != "astronaut" && id != "halo" }

    /// The two side bands the ears are drawn back in, in canvas units: left
    /// and right of the face, from the top of the canvas to just under the
    /// skull.
    /// The radius the bands' inner bottom corner is rounded to, and how far
    /// their edge is feathered, in canvas units (`formStill`).
    static func earRound(form: Companion, stage: Int) -> CGFloat { 0.16 * head(form, stage: stage).browW }
    static let earFeather: CGFloat = 3

    /// On the phoenix they start where the hat's brim begins (`hatBox`
    /// in, `brimTop`): above that, what sits beside the crown is the crest
    /// curling sideways, and redrawn it crossed the top hat's and wizard
    /// hat's crowns.
    static func earBands(form: Companion, stage: Int, hat: String? = nil, box: CGRect? = nil) -> [CGRect] {
        let h = head(form, stage: stage)
        let band = 0.24 * h.browW
        let bottom = h.skull + 10
        var top: CGFloat = -200
        if form == .phoenix, let hat, let box {
            top = box.minY + (brimTop[hat] ?? 0.5) * box.height
        }
        guard bottom > top else { return [] }
        return [CGRect(x: 0, y: top, width: h.cx - band, height: bottom - top),
                CGRect(x: h.cx + band, y: top, width: 664 - h.cx - band, height: bottom - top)]
    }
}
