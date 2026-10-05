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
    @StateObject private var dimRig = OttoRigHolder()
    @StateObject private var brightRig = OttoRigHolder()

    /// Seconds each of looks 1 to 12 holds before the next, in whole 30 fps
    /// frames because Instagram and TikTok play reels at 30 fps and drop
    /// anything shorter. Shaped like the "only 1% can pause at the right
    /// time" reel Aziz sent (it creeps, then rushes), but no look is shorter
    /// than 6 frames. 3 frames (0.1 s) is about the tightest window a viewer
    /// timing a tap to something predictable can still hit; Aziz asked for
    /// every look to be pausable and "a bit above the bare minimum".
    static let holds: [Double] = [12, 11, 10, 9, 8, 7, 7, 6, 6, 6, 6, 6].map { $0 / 30 }
    /// Nirvana is the shortest of all, 5 frames (about 4.5 on screen, since
    /// the rig takes a beat to switch looks), so it is the hardest pause
    /// while still being a fair one.
    static let flash = 5.0 / 30
    static var loop: Double { holds.reduce(0, +) + flash }
    /// The parked Otto stays a hair above zero: a Rive view at opacity 0
    /// stops drawing, so it would show its old look for a frame or two when
    /// it swapped back in. At 0.2% it keeps up and nobody can see it.
    static let parked = 0.002

    var body: some View {
        TimelineView(.animation) { context in
            let look = lookAt(context.date)
            ZStack {
                if onGreen {
                    Color(red: 0, green: 1, blue: 0)
                } else {
                    // The valley and his cushion, with its own Otto hidden.
                    ValleyScene(progress: 0, aura: .steady, figureHidden: true, life: false)
                }
                // Exactly where and how big the valley draws him, so one
                // outline traced on green fits both clips.
                GeometryReader { geo in
                    let seated = SitLayout.ottoHeight(in: geo.size)
                    let spot = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.76 - seated / 2)
                    // Two Ottos, never one that changes shape: the figure's
                    // frame turns from wide to tall at look 9, and the Rive
                    // view draws one stretched frame whenever it does. Each
                    // of these keeps its shape and they swap by opacity.
                    // The parked one waits on the look it will show next
                    // (1 after Nirvana, 9 after look 8), because a look
                    // change takes the rig a frame or two to draw.
                    figure(look < OttoAuraFigure.tallFromLook ? look : 1, seated, dimRig)
                        .position(spot)
                        .opacity(look < OttoAuraFigure.tallFromLook ? 1 : Self.parked)
                    figure(max(look, OttoAuraFigure.tallFromLook), seated, brightRig)
                        .position(spot)
                        .opacity(look >= OttoAuraFigure.tallFromLook ? 1 : Self.parked)
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
        .task {
            // Room for the recording to start before he moves.
            try? await Task.sleep(for: .seconds(2.5))
            start = Date()
        }
    }

    private func figure(_ look: Int, _ size: CGFloat, _ rig: OttoRigHolder) -> some View {
        OttoAuraFigure(stage: OttoAura.Stage(rawValue: (look + 1) / 2) ?? .steady,
                       look: look, size: size, rig: rig, snap: true)
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
