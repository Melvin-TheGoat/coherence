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
#endif
