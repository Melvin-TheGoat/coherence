import SwiftUI
import SwiftData
import UIKit

/// What a finished session earned, worked out from the history before and
/// after it landed. Every number on the reward screen comes from here, and
/// nothing here is invented: minutes sat, the streak either side of it, the
/// points (one per whole minute, none for a hand-logged session), the bank
/// before them, and Otto's glow either side.
struct SessionReward: Identifiable, Equatable {
    let id: UUID
    let seconds: Int
    let streakBefore: Int
    let streakAfter: Int
    let points: Int
    let bankBefore: Int
    let glowBefore: Int
    let glowAfter: Int

    /// Rounded for the headline; a 40 second session still says 1.
    var minutes: Int { max(1, Int((Double(seconds) / 60).rounded())) }
}

/// The moment a session ends (Melvin, 2026-09-27: "super satisfying,
/// rewarding, and longer", and of `mockups/reward-v1.html`, "honestly
/// perfect"). Duolingo's lesson-complete structure (one card at a time, each
/// number counting up, then the streak) and Clash Royale's rewards (coins
/// flying one by one into the bank, a level-up burst), in the valley.
///
/// About nine seconds. Every beat has a haptic (the Settings switch still
/// governs them), and a tap anywhere finishes it at once, so it is never in
/// the way. With Reduce Motion it opens already finished.
struct SessionRewardView: View {
    let reward: SessionReward
    let onContinue: () -> Void

    @Query(sort: \Preferences.createdAt) private var prefsRows: [Preferences]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var rig = OttoRigHolder()

    @State private var lit = false
    @State private var spin = false
    @State private var hop = 0
    @State private var leaves = 0
    @State private var titleIn = false
    @State private var subIn = false
    @State private var tilesIn = [false, false, false]
    @State private var minutesShown = 0
    @State private var streakShown = 0
    @State private var flare = 0
    @State private var pointsShown = 0
    @State private var bank = 0
    @State private var bankBump = 0
    @State private var flights: [Int] = []
    @State private var glowIn = false
    @State private var glowShown = 0
    @State private var gainFloat = false
    @State private var look = 1
    @State private var ribbon = false
    @State private var flash = false
    @State private var ctaIn = false
    @State private var done = false
    @State private var started = false

    @State private var tileFrame: CGRect = .zero
    @State private var bankFrame: CGRect = .zero
    @State private var stackTop: CGFloat = 600

    private static let space = "reward"
    private var haptics: Bool { prefsRows.first?.hapticsEnabled ?? true }
    private var stageUp: OttoAura.Stage? {
        let before = OttoAura.Stage(level: reward.glowBefore), after = OttoAura.Stage(level: reward.glowAfter)
        return after.rawValue > before.rawValue ? after : nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let s = SitLayout.scale(in: size)
            let seated = 186 * s * 1.17
            // Otto and his cushion rise just clear of the cards, so the cards
            // sit on the meadow in front of him.
            let lift = max(0, SitLayout.cushionBottom(in: size) - (stackTop - 16))
            let ottoY = size.height * (1 - 0.24) - seated / 2 - lift
            ZStack {
                ValleyScene(progress: 0, showsFigure: false, clock: true)

                // The light behind him: slow rays and a warm burst.
                RewardRays()
                    .frame(width: size.width * 1.9, height: size.width * 1.9)
                    .rotationEffect(.degrees(spin ? 40 : 0))
                    .opacity(lit ? 1 : 0)
                    .position(x: size.width / 2, y: ottoY)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.67).opacity(0.95),
                                                  Color(red: 1, green: 0.84, blue: 0.47).opacity(0.5),
                                                  .clear],
                                         center: .center, startRadius: 0, endRadius: 190))
                    .frame(width: 380, height: 380)
                    .scaleEffect(lit ? 1 : 0.05)
                    .opacity(lit ? 1 : 0)
                    .position(x: size.width / 2, y: ottoY)

                Cushion()
                    .frame(width: 168 * s, height: 44 * s)
                    .position(x: size.width / 2, y: SitLayout.cushionBottom(in: size) - 22 * s - lift)
                    .standsInMeadow(feetY: SitLayout.cushionFront(in: size, scale: s) - lift,
                                    scale: s, sceneSize: size)

                OttoAuraFigure(stage: OttoAura.Stage(rawValue: (look + 1) / 2) ?? .steady,
                               look: look, size: seated, rig: rig, snap: true)
                    .keyframeAnimator(initialValue: Hop(), trigger: hop) { content, v in
                        content
                            .scaleEffect(x: v.sx, y: v.sy, anchor: .bottom)
                            .offset(y: v.y)
                    } keyframes: { _ in
                        KeyframeTrack(\.sy) {
                            SpringKeyframe(0.86, duration: 0.14)
                            SpringKeyframe(1.08, duration: 0.22)
                            SpringKeyframe(0.92, duration: 0.2)
                            SpringKeyframe(1, duration: 0.34)
                        }
                        KeyframeTrack(\.sx) {
                            SpringKeyframe(1.12, duration: 0.14)
                            SpringKeyframe(0.94, duration: 0.22)
                            SpringKeyframe(1.08, duration: 0.2)
                            SpringKeyframe(1, duration: 0.34)
                        }
                        KeyframeTrack(\.y) {
                            LinearKeyframe(0, duration: 0.14)
                            CubicKeyframe(-46 * s, duration: 0.22)
                            CubicKeyframe(0, duration: 0.2)
                            LinearKeyframe(0, duration: 0.34)
                        }
                    }
                    .position(x: size.width / 2, y: ottoY)

                RewardLeaves(trigger: leaves)
                    .position(x: size.width / 2, y: ottoY)
                    .allowsHitTesting(false)

                if let stage = stageUp {
                    Text("Otto reached \(Self.name(stage)) ✦")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.06))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.65),
                                                            Color(red: 0.95, green: 0.73, blue: 0.29)],
                                                   startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .background(Color(red: 0.78, green: 0.56, blue: 0.17),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous).offset(y: 4))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
                        .scaleEffect(ribbon ? 1 : 0.3)
                        .opacity(ribbon ? 1 : 0)
                        .position(x: size.width / 2, y: ottoY - seated * 0.66)
                }

                Color.white.opacity(flash ? 0.85 : 0).allowsHitTesting(false)

                // Coins in flight, from the points card to the bank.
                ForEach(flights, id: \.self) { i in
                    CoinFlight(from: CGPoint(x: tileFrame.midX, y: tileFrame.midY),
                               to: CGPoint(x: bankFrame.minX + 16, y: bankFrame.midY),
                               bend: CGFloat((i * 37) % 80))
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay { foreground(size: size) }
            .coordinateSpace(name: Self.space)
            .contentShape(Rectangle())
            .onTapGesture { finish() }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !started else { return }
            started = true
            streakShown = reward.streakBefore
            bank = reward.bankBefore
            glowShown = reward.glowBefore
            look = OttoAura.look(level: reward.glowBefore)
            RewardHaptics.prepare()
        }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - The words and cards

    private func foreground(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    PointCoin(size: 22)
                    Text("\(bank)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(AppColor.textPrimary)
                .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
                .background(AppColor.backgroundPrimary.opacity(0.96), in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
                .keyframeAnimator(initialValue: 1.0, trigger: bankBump) { c, v in c.scaleEffect(v) } keyframes: { _ in
                    SpringKeyframe(1.16, duration: 0.08)
                    SpringKeyframe(1, duration: 0.14)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { bankFrame = $0 }
            }
            .padding(.horizontal, 18)
            .padding(.top, SitLayout.skyTop(in: size) - 6)

            Text("Session complete!")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                // Dark enough to hold over a passing cloud.
                .shadow(color: .black.opacity(0.28), radius: 0, y: 3)
                .shadow(color: .black.opacity(0.22), radius: 6)
                .scaleEffect(titleIn ? 1 : 0.4)
                .opacity(titleIn ? 1 : 0)
                .padding(.top, 18)
            Text(reward.minutes == 1 ? "1 minute, well spent" : "\(reward.minutes) minutes, well spent")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .opacity(subIn ? 1 : 0)
                .offset(y: subIn ? 0 : 8)
                .padding(.top, 4)

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    tile(0, art: "home-time", value: "\(minutesShown)", label: reward.minutes == 1 ? "Minute" : "Minutes")
                    tile(1, art: "home-streak", value: "\(streakShown)", label: "Day streak",
                         tint: Color(red: 0.84, green: 0.42, blue: 0.2))
                    tile(2, coin: true, value: "+\(pointsShown)", label: "Points")
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tileFrame = $0 }
                }
                glowBar
                Button(action: close) { Text("Continue") }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .opacity(ctaIn ? 1 : 0)
                    .offset(y: ctaIn ? 0 : 20)
                    .allowsHitTesting(ctaIn)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { stackTop = $0 }
        }
    }

    private func tile(_ i: Int, art: String? = nil, coin: Bool = false, value: String, label: String,
                      tint: Color = AppColor.textPrimary) -> some View {
        VStack(spacing: 3) {
            Group {
                if coin { PointCoin(size: 28) } else if let art { SitArt(name: art, size: 32) }
            }
            .frame(height: 34)
            .keyframeAnimator(initialValue: 1.0, trigger: i == 1 ? flare : 0) { c, v in
                c.scaleEffect(v).rotationEffect(.degrees((v - 1) * -14))
            } keyframes: { _ in
                SpringKeyframe(1.6, duration: 0.2)
                SpringKeyframe(1, duration: 0.4)
            }
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(AppColor.hairline, in: RoundedRectangle(cornerRadius: 18, style: .continuous).offset(y: 5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
        .scaleEffect(tilesIn[i] ? 1 : 0.8)
        .offset(y: tilesIn[i] ? 0 : 30)
        .opacity(tilesIn[i] ? 1 : 0)
    }

    private var glowBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Otto's glow")
                Spacer()
                Text("\(glowShown)%").monospacedDigit().contentTransition(.numericText())
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            GeometryReader { g in
                let fill = max(14, g.size.width * CGFloat(glowShown) / 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.6))
                    Capsule()
                        .fill(LinearGradient(colors: [AppColor.auraGlow, AppColor.auraRing],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: fill)
                    // The gain rises off the end of the fill, clear of the
                    // percentage over the bar's right end.
                    Text("+\(max(0, reward.glowAfter - reward.glowBefore))%")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .fixedSize()
                        .offset(x: fill - 22, y: gainFloat ? -44 : -16)
                        .opacity(gainFloat ? 0 : (glowIn && reward.glowAfter > reward.glowBefore ? 1 : 0))
                }
            }
            .frame(height: 16)
        }
        .opacity(glowIn ? 1 : 0)
        .offset(y: glowIn ? 0 : 10)
    }

    // MARK: - The sequence

    /// Nine seconds, beat by beat, as `mockups/reward-v1.html` plays it.
    @MainActor private func run() async {
        if reduceMotion { finish(); return }
        try? await Task.sleep(for: .milliseconds(150))
        guard !done else { return }
        buzz(.heavy)
        withAnimation(.easeOut(duration: 0.9)) { lit = true }
        withAnimation(.linear(duration: 9)) { spin = true }
        hop += 1
        leaves += 1
        guard await pause(250) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { titleIn = true }
        guard await pause(270) else { return }
        withAnimation(.easeOut(duration: 0.4)) { subIn = true }
        guard await pause(680) else { return }

        // The cards, one at a time.
        showTile(0)
        guard await countMinutes() else { return }
        guard await pause(100) else { return }
        showTile(1)
        guard await pause(420) else { return }
        flare += 1
        buzz(.medium)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) { streakShown = reward.streakAfter }
        guard await pause(380) else { return }
        showTile(2)
        guard await pause(400) else { return }

        // The coins.
        guard await coins() else { return }
        guard await pause(500) else { return }

        // The glow.
        withAnimation(.easeOut(duration: 0.4)) { glowIn = true }
        guard await pause(300) else { return }
        guard await countGlow() else { return }
        if look != OttoAura.look(level: reward.glowAfter) {
            guard await pause(250) else { return }
            levelUp()
            guard await pause(900) else { return }
        }
        guard await pause(400) else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.72)) { ctaIn = true }
        done = true
    }

    /// Waits, or returns false the moment a tap has finished everything.
    private func pause(_ ms: Int) async -> Bool {
        var left = ms
        while left > 0 {
            guard !done, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(min(25, left)))
            left -= 25
        }
        return !done
    }

    private func showTile(_ i: Int) {
        buzz(.light)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { tilesIn[i] = true }
    }

    private func countMinutes() async -> Bool {
        let steps = min(reward.minutes, 20)
        for k in 1...max(steps, 1) {
            guard await pause(700 / max(steps, 1)) else { return false }
            minutesShown = reward.minutes * k / max(steps, 1)
            if k % 2 == 0 || steps < 8 { buzz(.soft) }
        }
        minutesShown = reward.minutes
        return true
    }

    /// One coin per point, at most eighteen flights however long the session,
    /// each adding its share to the bank as it lands.
    private func coins() async -> Bool {
        let points = reward.points
        guard points > 0 else { return true }
        let n = min(points, 18)
        for i in 0..<n {
            guard !done else { return false }
            flights.append(i)
            let share = points * (i + 1) / n - points * i / n
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(620))
                flights.removeAll { $0 == i }
                guard !done else { return }
                withAnimation(.snappy(duration: 0.18)) { bank += share }
                bankBump += 1
                buzz(.light)
            }
            withAnimation(.snappy(duration: 0.1)) { pointsShown = points * (i + 1) / n }
            guard await pause(105) else { return false }
        }
        guard await pause(640) else { return false }
        return true
    }

    private func countGlow() async -> Bool {
        let from = reward.glowBefore, to = reward.glowAfter
        withAnimation(.easeOut(duration: 1.1)) { gainFloat = false }
        let steps = 22
        for k in 1...steps {
            guard await pause(50) else { return false }
            withAnimation(.linear(duration: 0.05)) {
                glowShown = from + Int((Double(to - from) * Double(k) / Double(steps)).rounded())
            }
        }
        withAnimation(.easeOut(duration: 1.2)) { gainFloat = true }
        return true
    }

    /// A flash, Otto changes into his new look, and a ribbon names it when he
    /// has reached a new stage.
    private func levelUp() {
        buzzSuccess()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        look = OttoAura.look(level: reward.glowAfter)
        hop += 1
        withAnimation(.easeOut(duration: 0.6).delay(0.08)) { flash = false }
        if stageUp != nil {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { ribbon = true }
        }
    }

    /// A tap anywhere: everything lands at once.
    private func finish() {
        guard !ctaIn || !done else { return }
        done = true
        flights = []
        withAnimation(.easeOut(duration: 0.25)) {
            lit = true
            titleIn = true
            subIn = true
            tilesIn = [true, true, true]
            minutesShown = reward.minutes
            streakShown = reward.streakAfter
            pointsShown = reward.points
            bank = reward.bankBefore + reward.points
            glowIn = true
            glowShown = reward.glowAfter
            look = OttoAura.look(level: reward.glowAfter)
            ribbon = stageUp != nil
            flash = false
            ctaIn = true
        }
    }

    private func close() {
        buzz(.medium)
        onContinue()
    }

    // MARK: - Haptics

    private func buzz(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard haptics else { return }
        RewardHaptics.impact(style)
    }

    private func buzzSuccess() {
        guard haptics else { return }
        RewardHaptics.success()
    }

    private var accessibilitySummary: String {
        var parts = ["Session complete. \(reward.minutes) minutes.",
                     "Day streak \(reward.streakAfter).",
                     "\(reward.points) points."]
        parts.append("Otto's glow \(reward.glowAfter) percent.")
        if let stage = stageUp { parts.append("Otto reached \(Self.name(stage)).") }
        return parts.joined(separator: " ")
    }

    static func name(_ stage: OttoAura.Stage) -> String {
        switch stage {
        case .withered: return "Withered"
        case .faded: return "Faded"
        case .stirring: return "Stirring"
        case .steady: return "Steady"
        case .bright: return "Bright"
        case .radiant: return "Radiant"
        case .nirvana: return "Nirvana"
        }
    }

    private struct Hop { var sx: CGFloat = 1; var sy: CGFloat = 1; var y: CGFloat = 0 }
}

/// A point, as a coin: gold, with a leaf struck on it. The bank on the reward
/// screen and the Store both count in these.
struct PointCoin: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.91, blue: 0.66),
                                              Color(red: 0.95, green: 0.71, blue: 0.27),
                                              Color(red: 0.79, green: 0.54, blue: 0.12)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle().strokeBorder(Color(red: 0.72, green: 0.48, blue: 0.1).opacity(0.45), lineWidth: size * 0.06)
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(Color(red: 0.61, green: 0.42, blue: 0.1))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// One coin's arc from the points card up into the bank.
private struct CoinFlight: View {
    let from: CGPoint
    let to: CGPoint
    let bend: CGFloat
    @State private var t: CGFloat = 0

    var body: some View {
        PointCoin(size: 24)
            .modifier(Arc(t: t, from: from, to: to, bend: bend))
            .onAppear { withAnimation(.easeInOut(duration: 0.62)) { t = 1 } }
            .allowsHitTesting(false)
    }

    private struct Arc: ViewModifier, Animatable {
        var t: CGFloat
        let from: CGPoint, to: CGPoint, bend: CGFloat
        var animatableData: CGFloat { get { t } set { t = newValue } }
        func body(content: Content) -> some View {
            // A quadratic curve bowing out to the right, round Otto rather
            // than across his face, so each coin swoops up the screen's edge.
            let c = CGPoint(x: max(from.x, to.x) + 30 + bend * 0.3, y: (from.y + to.y) / 2 + bend)
            let u = 1 - t
            let x = u * u * from.x + 2 * u * t * c.x + t * t * to.x
            let y = u * u * from.y + 2 * u * t * c.y + t * t * to.y
            let scale = 0.7 + 0.55 * sin(.pi * t) - 0.1 * t
            return content.scaleEffect(scale).position(x: x, y: y)
        }
    }
}

/// Slow warm rays turning behind him.
private struct RewardRays: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = max(size.width, size.height) / 2
            for i in 0..<18 {
                let a0 = Double(i) * .pi * 2 / 18, a1 = a0 + .pi * 2 / 18 * 0.42
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(red: 1, green: 0.94, blue: 0.75).opacity(0.3)))
            }
        }
        .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear],
                             center: .center, startRadius: 0, endRadius: 330))
        .allowsHitTesting(false)
    }
}

/// Leaves thrown up from where he sits, falling away.
private struct RewardLeaves: View {
    let trigger: Int
    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                Leaf(index: i, trigger: trigger)
            }
        }
    }

    private struct Leaf: View {
        let index: Int
        let trigger: Int
        var body: some View {
            let seed = Double(index)
            let dx = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1) * 260 - 30
            let up = 160 + abs((sin(seed * 78.233) * 12345.678).truncatingRemainder(dividingBy: 1)) * 120
            let turn = Double(index % 2 == 0 ? 1 : -1) * (300 + seed * 40)
            Capsule()
                .fill(Color(red: 0.5, green: 0.69, blue: 0.41))
                .frame(width: 10, height: 17)
                .keyframeAnimator(initialValue: LeafFrame(), trigger: trigger) { c, v in
                    c.rotationEffect(.degrees(v.rot)).offset(x: v.x, y: v.y).opacity(v.alpha)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        CubicKeyframe(dx * 0.6, duration: 0.8)
                        CubicKeyframe(dx, duration: 1.2)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(-up, duration: 0.8)
                        CubicKeyframe(140, duration: 1.2)
                    }
                    KeyframeTrack(\.rot) { LinearKeyframe(turn, duration: 2) }
                    KeyframeTrack(\.alpha) {
                        LinearKeyframe(1, duration: 0.05)
                        LinearKeyframe(1, duration: 1.3)
                        LinearKeyframe(0, duration: 0.65)
                    }
                }
        }
        struct LeafFrame { var x: Double = 0; var y: Double = 0; var rot: Double = 0; var alpha: Double = 0 }
    }
}

/// Prepared generators, so no pulse is dropped while the Taptic Engine spins
/// up (the onboarding lesson, 2026-09-14).
enum RewardHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let note = UINotificationFeedbackGenerator()

    static func prepare() { [light, soft, medium, heavy].forEach { $0.prepare() }; note.prepare() }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g: UIImpactFeedbackGenerator
        switch style {
        case .soft: g = soft
        case .medium: g = medium
        case .heavy: g = heavy
        default: g = light
        }
        g.impactOccurred()
        g.prepare()
    }

    static func success() { note.notificationOccurred(.success); note.prepare() }
}
