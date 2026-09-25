import SwiftUI
import UIKit

/// The bar as a strip of Otto's meadow. A TEST (Melvin, 2026-09-25: "Can we
/// test it with this?"), built from the ChatGPT sheet he made from concept 1
/// of `mockups/tabbar-icons/PROMPTS.md`, "the bar is the meadow". DEBUG only,
/// one of the `TestTabBar` styles; Release draws the classic bar.
///
/// Each tab is a small object standing in the grass: a cottage (Home), a
/// wooden gate (Block), a green mound with a white plus (Begin, in the green
/// of the onboarding buttons rather than gold, Melvin, same day), two sloths
/// (Friends) and a signpost (Profile). The selected one stands in a beam of
/// sunlight with its label in a white pill, as the sheet draws it.
///
/// The icons are cut from that sheet (`Coherence/TabBar/tab-*.png`, about
/// 120 px each), so they are a little soft at this size. A version that
/// ships needs the set exported larger.
struct MeadowTabBar: View {
    @Binding var selection: MainTab
    let onPlus: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home, art: "tab-home", label: "Home", tour: nil)
            item(.block, art: "tab-block", label: "Block", tour: .block)
            begin
            item(.friends, art: "tab-friends", label: "Friends", tour: .friends)
            item(.profile, art: "tab-profile", label: "Profile", tour: .profile)
        }
        .padding(.horizontal, 4)
        // Room for the hills above the objects.
        .padding(.top, 24)
        .padding(.bottom, 4)
        .background(MeadowBarGround().ignoresSafeArea(edges: .bottom))
        // Down into the home indicator's inset, as the classic bar does.
        .padding(.bottom, -Self.intoInset)
    }

    static let intoInset: CGFloat = 16

    private func item(_ tab: MainTab, art name: String, label: String,
                      tour: TourTarget?) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                art(name)
                    .frame(height: 44)
                    .scaleEffect(selected ? 1.1 : 1, anchor: .bottom)
                    .background(alignment: .bottom) {
                        if selected {
                            SunBeam()
                                .frame(width: 74, height: 96)
                                .offset(y: -4)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? AppColor.skyDeep : ValleyGround.ink.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .opacity(selected ? 1 : 0)
                    )
            }
            .anchorPreference(key: TourTargetKey.self, value: .bounds) { anchor in
                tour.map { [$0: anchor] } ?? [:]
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The green mound: bigger than the other objects and standing on the
    /// same ground line, so it rises above them without floating.
    private var begin: some View {
        Button(action: onPlus) {
            art("tab-begin")
                .frame(height: 60)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.begin: $0] }
        // Level with the other objects' feet, above where their labels sit.
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Begin session")
    }

    @ViewBuilder
    private func art(_ name: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

/// A soft shaft of sunlight falling on the selected object.
private struct SunBeam: View {
    var body: some View {
        BeamShape()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.72).opacity(0),
                                          Color(red: 1, green: 0.94, blue: 0.62).opacity(0.75)],
                                 startPoint: .top, endPoint: .bottom))
            .blur(radius: 5)
    }
}

/// Narrow at the top, wide at the bottom.
private struct BeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Two rows of rolling hills and the meadow in front of them, in the
/// valley's own daytime colours (`DayLight.at(0)`), so the bar is the same
/// place as every screen above it.
private struct MeadowBarGround: View {
    var body: some View {
        let day = DayLight.at(0)
        ZStack(alignment: .top) {
            RollingHills(peaks: [0.35, 0.8, 0.45, 1.0, 0.55, 0.9, 0.4, 0.75, 0.3], crest: 30)
                .fill(day.ridge[0])
            RollingHills(peaks: [0.6, 0.3, 0.75, 0.4, 0.85, 0.35, 0.7, 0.45], crest: 22)
                .fill(day.ridge[1])
                .padding(.top, 12)
            RollingHills(peaks: [0.4, 0.7, 0.35, 0.6, 0.3, 0.65, 0.45], crest: 12)
                .fill(LinearGradient(colors: day.field, startPoint: .top, endPoint: .bottom))
                .padding(.top, 26)
            // The sheet's grass is scattered with flowers and tufts between
            // the objects (Melvin: "You didnt use the like flowers and decor
            // surrounding the icons?").
            Canvas { ctx, size in
                let band = min(size.height, 96)
                for f in Self.flowers {
                    let c = CGPoint(x: f.x * size.width, y: 40 + f.y * (band - 48))
                    if f.tuft { Self.tuft(at: c, in: &ctx) }
                    Self.flower(at: c, scale: f.s, yellow: f.yellow, in: &ctx)
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }

    /// Spread across the grass, most of them between the objects rather than
    /// under them: x and y are fractions of the band.
    private static let flowers: [(x: CGFloat, y: CGFloat, s: CGFloat, yellow: Bool, tuft: Bool)] = [
        (0.02, 0.35, 1.0, false, true), (0.09, 0.90, 0.8, false, false), (0.19, 0.20, 0.7, true, false),
        (0.21, 0.80, 0.9, false, true), (0.31, 0.15, 0.6, false, false), (0.39, 0.95, 0.8, true, true),
        (0.44, 0.30, 0.7, false, false), (0.57, 0.25, 0.7, false, true), (0.60, 0.92, 0.9, true, false),
        (0.70, 0.18, 0.6, false, false), (0.79, 0.85, 0.8, false, true), (0.81, 0.22, 0.7, true, false),
        (0.90, 0.30, 0.8, false, false), (0.97, 0.75, 1.0, false, true),
    ]

    private static func flower(at c: CGPoint, scale s: CGFloat, yellow: Bool, in ctx: inout GraphicsContext) {
        let petal = 2.3 * s, reach = 2.5 * s
        for k in 0..<5 {
            let a = CGFloat(k) / 5 * 2 * .pi - .pi / 2
            let p = CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - petal, y: p.y - petal, width: petal * 2, height: petal * 2)),
                     with: .color(yellow ? Color(red: 1, green: 0.86, blue: 0.42) : .white))
        }
        let r = 1.7 * s
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(yellow ? Color(red: 0.93, green: 0.55, blue: 0.2) : Color(red: 0.97, green: 0.78, blue: 0.3)))
    }

    private static func tuft(at c: CGPoint, in ctx: inout GraphicsContext) {
        var p = Path()
        for dx in [-5.0, -1.0, 3.5] as [CGFloat] {
            p.move(to: CGPoint(x: c.x + dx, y: c.y + 7))
            p.addQuadCurve(to: CGPoint(x: c.x + dx * 1.6, y: c.y - 2),
                           control: CGPoint(x: c.x + dx * 0.4, y: c.y + 2))
        }
        ctx.stroke(p, with: .color(Color(red: 0.36, green: 0.58, blue: 0.3)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}

/// A band of soft hills across the top of its frame, solid below: each value
/// in `peaks` is how high that crest rises within the top `crest` points,
/// and the curve runs through the midpoints so every crest is rounded.
private struct RollingHills: Shape {
    var peaks: [CGFloat]
    var crest: CGFloat

    func path(in rect: CGRect) -> Path {
        let n = peaks.count
        let points = peaks.enumerated().map { i, v in
            CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1),
                    y: rect.minY + (1 - v) * crest)
        }
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: points[0])
        for i in 1..<n {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            p.addQuadCurve(to: mid, control: points[i - 1])
        }
        p.addLine(to: points[n - 1])
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
