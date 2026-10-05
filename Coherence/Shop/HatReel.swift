#if DEBUG
import SwiftUI

/// One hat on every pose Otto wears it in, one at a time and full size, for a
/// screen recording per hat (Melvin, 2026-09-28: "clips of all hats with every
/// single pose so I can verify each one"). The gallery shows all thirteen
/// looks at once but at 72pt, too small to judge a brim against a cheek.
///
/// Launch with `PREVIEW_HAT=<id> PREVIEW_HAT_REEL=1`: the thirteen aura looks
/// in the valley as Home draws them, then the Ready screen's wave and the
/// sit's cross-legged pose. The hat comes from `PREVIEW_HAT`, which both the
/// aura figure and the session rig already read.
struct HatReel: View {
    @State private var step = 0
    private let hat = OttoAuraFigure.previewHat ?? "none"

    /// Thirteen looks, then the two session poses.
    private static let steps = 15
    private static let lookSeconds = 1.6
    private static let poseSeconds = 3.2

    var body: some View {
        ZStack(alignment: .top) {
            scene
                .id(step < 13 ? 0 : step)
                .ignoresSafeArea()
            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ValleyGround.ink)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.white.opacity(0.85), in: Capsule())
                .padding(.top, 70)
        }
        .task {
            while step < Self.steps - 1 {
                try? await Task.sleep(for: .seconds(step < 13 ? Self.lookSeconds : Self.poseSeconds))
                guard !Task.isCancelled else { return }
                step += 1
            }
        }
    }

    @ViewBuilder private var scene: some View {
        if step < 13 {
            let look = step + 1
            ValleyScene(progress: 0,
                        aura: OttoAura.Stage(rawValue: (look + 1) / 2) ?? .steady,
                        auraLook: look, auraSnap: true, life: false)
        } else if step == 13 {
            ValleyScene(progress: 0, pose: .greeting, life: false)
        } else {
            ValleyScene(progress: 0, pose: .meditating, life: false)
        }
    }

    private var label: String {
        let names = [1: "Withered", 3: "Faded", 5: "Stirring", 7: "Steady",
                     9: "Bright", 11: "Radiant", 13: "Nirvana"]
        if step < 13 {
            let look = step + 1
            return "\(hat) · look \(look)\(names[look].map { " · \($0)" } ?? "")"
        }
        return step == 13 ? "\(hat) · Ready (waving)" : "\(hat) · The sit"
    }
}
/// Otto climbing from Withered to Nirvana for a marketing clip (Aziz,
/// 2026-10-05: "Otto cycles through his different stages and it speeds up at
/// the end when he's enlightened"). Each look holds a little shorter than the
/// one before, then Nirvana holds. Launch with `PREVIEW_STAGE_REEL=green`
/// (Otto alone on chroma green, to key out in an editor) or `=valley` (in the
/// valley as Home draws him), and screen-record the simulator.
struct StageReel: View {
    let onGreen: Bool
    @State private var start: Date? = nil
    @StateObject private var rig = OttoRigHolder()

    /// Seconds each of looks 1 to 12 holds before the next, matched to the
    /// "only 1% can pause at the right time" reel Aziz sent: a 2 s loop that
    /// creeps for most of its length and then rushes, the target on screen
    /// for about one frame. 0.44 s, then each 79% of the last, down to
    /// 0.033 s, so the climb is 1.97 s and Nirvana lands with one frame to go.
    static let holds: [Double] = (0..<12).map { 0.44 * pow(0.79, Double($0)) }
    /// How long Nirvana shows before the loop starts again.
    static let flash = 0.05
    static var loop: Double { holds.reduce(0, +) + flash }

    var body: some View {
        TimelineView(.animation) { context in
            let look = lookAt(context.date)
            let stage = OttoAura.Stage(rawValue: (look + 1) / 2) ?? .steady
            ZStack {
                if onGreen {
                    Color(red: 0, green: 1, blue: 0).ignoresSafeArea()
                    OttoAuraFigure(stage: stage, look: look, size: 330, rig: rig, snap: true)
                        .frame(width: 330, height: 330)
                        .offset(y: 60)
                } else {
                    ValleyScene(progress: 0, aura: stage, auraLook: look,
                                auraSnap: true, life: false)
                        .ignoresSafeArea()
                }
            }
        }
        .statusBarHidden()
        .task {
            // Room for the recording to start before he moves.
            try? await Task.sleep(for: .seconds(2.5))
            start = Date()
        }
    }

    /// Driven by the clock, not by sleeps, so tiny holds land on time. It
    /// loops, like the reel it copies.
    private func lookAt(_ now: Date) -> Int {
        guard let start else { return 1 }
        var t = now.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.loop)
        for (i, hold) in Self.holds.enumerated() {
            if t < hold { return i + 1 }
            t -= hold
        }
        return 13
    }
}
#endif
