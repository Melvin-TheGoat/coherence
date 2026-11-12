import SwiftUI
import UIKit

// MARK: - The rebirth

/// The moment Otto is reborn into a new form (Melvin, 2026-11-10,
/// `mockups/level-up.html`): Pokémon's evolution, Duolingo's confetti and
/// Finch's card, played as one sequence of about ten seconds.
///
/// Night falls and he turns into a white silhouette; the silhouette flickers
/// between his old shape and his new one, faster and faster; a warm flash;
/// day returns and the new form pops in with light turning behind him and
/// confetti in 808's colours; the card slides up. A tap anywhere skips to the
/// card, which waits for a tap of its own.
///
/// Opened from a quiet Home (`QuietHomeHooks`), so it never stacks with the
/// session reward or an award. `onRevealed` fires once, the moment the new
/// form shows: that is when the rebirth is stored (`CompanionStore.announce`)
/// and his glow starts again at 50.
struct EvolutionView: View {
    let from: Companion
    let fromStage: OttoAura.Stage
    let to: Companion
    let lifetime: Int
    /// "2 of 2" when a member catches up on more than one form.
    let index: Int
    let total: Int
    let wearsHat: Bool
    let onRevealed: () -> Void
    let onMeditate: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var rig = OttoRigHolder()

    @State private var night = false
    @State private var titleIn = false
    @State private var white = 0.0
    @State private var showNew = false
    @State private var flash = false
    @State private var revealed = false
    @State private var popped = false
    @State private var spin = false
    @State private var confettiAt: Date?
    @State private var cardIn = false
    @State private var sequence: Task<Void, Never>?
    @State private var reported = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let s = SitLayout.scale(in: size)
            let seated = 186 * s * 1.17
            let rise: CGFloat = cardIn ? size.height * 0.2 : 0
            let ottoY = size.height * (1 - 0.24) - seated / 2 - rise
            ZStack {
                ValleyScene(progress: 0, showsFigure: false, clock: true)

                // Night: the valley darkens and the stars come out.
                Color(red: 0.04, green: 0.06, blue: 0.16).opacity(night ? 0.78 : 0)
                Stars().opacity(night ? 1 : 0)

                RewardRays()
                    .frame(width: size.width * 1.9, height: size.width * 1.9)
                    .rotationEffect(.degrees(spin ? 50 : 0))
                    .opacity(popped ? 1 : 0)
                    .position(x: size.width / 2, y: ottoY)

                figure(seated: seated)
                    .position(x: size.width / 2, y: ottoY)

                if let start = confettiAt {
                    Confetti(start: start, origin: CGPoint(x: size.width / 2, y: ottoY - seated * 0.2),
                             size: size)
                        .allowsHitTesting(false)
                }

                Color(red: 1, green: 0.98, blue: 0.9).opacity(flash ? 1 : 0).allowsHitTesting(false)

                VStack(spacing: 8) {
                    Text("Otto is changing...")
                        .font(DisplayFont.display(28, .heavy))
                    Text("Every minute you meditated is coming together")
                        .font(AppFont.body)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                .padding(.horizontal, 32)
                .opacity(titleIn && !revealed ? 1 : 0)
                .position(x: size.width / 2, y: geo.safeAreaInsets.top + 90)

                VStack {
                    Spacer()
                    card
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 8)
                        .offset(y: cardIn ? 0 : size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { if !cardIn { Tactile.tap(); skip() } }
        }
        .ignoresSafeArea()
        .onAppear { if sequence == nil { sequence = Task { await play() } } }
        .onDisappear { sequence?.cancel() }
    }

    /// Before the flash: his still, washing to white, then flickering
    /// between the two shapes. After it: the new form, his rig and hat.
    @ViewBuilder private func figure(seated: CGFloat) -> some View {
        if revealed {
            OttoAuraFigure(stage: .steady, size: seated, rig: rig, form: to)
                .scaleEffect(popped ? 1 : 0.55, anchor: .bottom)
        } else {
            let canvas = seated * 0.95 / OttoAuraFigure.bodyShare
            let name = showNew ? to.stillName(stage: OttoAura.Stage.steady.rawValue)
                               : from.stillName(stage: fromStage.rawValue)
            ZStack {
                Image(name).resizable().scaledToFit().opacity(1 - white)
                Image(name).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(.white).opacity(white)
                    .shadow(color: .white.opacity(0.8 * white), radius: 18)
            }
            .frame(width: canvas * OttoAuraFigure.canvasAspect, height: canvas)
            .offset(y: canvas * (1 - OttoAuraFigure.baseline))
            .frame(width: seated, height: seated, alignment: .bottom)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text(kicker)
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
            Text("Otto was reborn as \(to.withArticle)")
                .font(DisplayFont.display(26, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(line)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Starts at Steady")
                        .font(DisplayFont.display(18, .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(OttoAura.startLevel)%")
                        .font(DisplayFont.display(18, .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                }
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.trace)
                        Capsule()
                            .fill(LinearGradient(colors: [AppColor.auraGlow, AppColor.auraRing],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: bar.size.width * CGFloat(OttoAura.startLevel) / 100)
                    }
                }
                .frame(height: 10)
                Text("Keep meditating and he'll glow.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(14)
            .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button("Meditate together") { onMeditate() }
                .buttonStyle(TogetherStyle.green)
            Button("Later") { onDone() }
                .font(AppFont.body.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .buttonStyle(.tactile)
        }
        .padding(20)
        .background(TileFill(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var kicker: String {
        let points = "\(lifetime.formatted()) lifetime points"
        return total > 1 ? "\(index) of \(total) · \(points)" : points
    }

    private var line: String {
        if total > 1 && index < total { return "Same Otto, new form. Another change is coming." }
        if total > 1 {
            let times = total == 2 ? "twice" : "\(total) times"
            return "You meditated enough for \(total) forms, so he changed \(times)."
        }
        return "Same Otto, new form." + (wearsHat ? " His hat came with him." : "")
    }

    // MARK: Timing

    private func play() async {
        if reduceMotion { skip(); return }
        func wait(_ seconds: Double) async -> Bool {
            try? await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        }
        withAnimation(.easeInOut(duration: 1.1)) { night = true; titleIn = true }
        guard await wait(1.0) else { return }
        withAnimation(.easeIn(duration: 0.6)) { white = 1 }
        guard await wait(0.7) else { return }
        // The flicker, faster and faster.
        let gaps = [0.46, 0.4, 0.34, 0.28, 0.23, 0.19, 0.15, 0.12, 0.1, 0.085, 0.07, 0.06, 0.055, 0.05, 0.05, 0.05]
        for gap in gaps {
            showNew.toggle()
            EvolutionHaptics.tick()
            guard await wait(gap) else { return }
        }
        showNew = true
        withAnimation(.easeIn(duration: 0.14)) { flash = true }
        guard await wait(0.16) else { return }
        reveal()
        withAnimation(.easeOut(duration: 0.9)) { flash = false; night = false }
        guard await wait(1.4) else { return }
        withAnimation(.spring(duration: 0.55, bounce: 0.2)) { cardIn = true }
    }

    private func reveal() {
        guard !revealed else { return }
        revealed = true
        report()
        AppAudio.shared.play(.chime)
        EvolutionHaptics.success()
        withAnimation(.spring(duration: 0.5, bounce: 0.45)) { popped = true }
        withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
        confettiAt = Date()
    }

    private func report() {
        guard !reported else { return }
        reported = true
        onRevealed()
    }

    private func skip() {
        sequence?.cancel()
        night = false
        flash = false
        titleIn = false
        white = 0
        reveal()
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { cardIn = true }
    }
}

/// A sky of still stars, for the night that falls before a rebirth.
private struct Stars: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x5EED
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<70 {
                let x = next() * size.width, y = next() * size.height * 0.55
                let r = 0.6 + next() * 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.4 + Double(next()) * 0.6)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A burst of confetti from where he sits, in 808's colours, falling with
/// gravity (Duolingo's, at 808's volume).
struct Confetti: View {
    let start: Date
    let origin: CGPoint
    let size: CGSize

    private struct Piece {
        let vx: CGFloat, vy: CGFloat, spin: Double, width: CGFloat, height: CGFloat, color: Color, wobble: Double
    }

    private static let colors: [Color] = [AppColor.accentGold, AppColor.skyDeep, OnboardingGreen.fill,
                                          AppColor.streakBlush, AppColor.auraRing, AppColor.measure]

    private let pieces: [Piece] = {
        var seed: UInt64 = 0xC0FFEE
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        return (0..<90).map { i in
            let angle = -Double.pi / 2 + (Double(next()) - 0.5) * 2.4
            let speed = 520 + next() * 680
            return Piece(vx: CGFloat(cos(angle)) * speed, vy: CGFloat(sin(angle)) * speed,
                         spin: Double(next()) * 720 - 360, width: 6 + next() * 6, height: 9 + next() * 8,
                         color: colors[i % colors.count], wobble: Double(next()) * 6)
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, _ in
                guard t < 4.5 else { return }
                let g: CGFloat = 1400
                for p in pieces {
                    let tt = CGFloat(t)
                    // Air drag on the way out, then a gentle fall.
                    let drag = (1 - exp(-2.2 * tt)) / 2.2
                    let x = origin.x + p.vx * drag + CGFloat(sin(t * p.wobble)) * 8
                    let y = origin.y + p.vy * drag + 0.5 * g * tt * tt * 0.35
                    guard y < size.height + 40 else { continue }
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(p.spin * t))
                    piece.opacity = t > 3.5 ? max(0, 4.5 - t) : 1
                    piece.fill(Path(CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)),
                               with: .color(p.color))
                }
            }
        }
    }
}

// MARK: - Otto's forms

/// Every form Otto can take, from his glow card on Home (`mockups/level-up.html`,
/// "Otto's forms"): the ones he has been reborn into as big cards, any of
/// them a tap away; the rest as silhouettes with the lifetime points they
/// arrive at, and only the next one with a bar.
struct OttoFormsView: View {
    let lifetime: Int
    /// Today's glow, which every form shares.
    let stage: OttoAura.Stage
    let onClose: () -> Void

    @ObservedObject private var companions = CompanionStore.shared
    @State private var asking: Companion?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text(lifetime.formatted())
                            .font(DisplayFont.display(34, .heavy))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                        Text("lifetime points")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.vertical, 6)
                    ForEach(Companion.allCases) { form in row(form) }
                    Text("Buying hats never slows him: his next form follows every point you have earned.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(AppMetrics.screenPadding)
            }
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Otto's forms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                }
            }
        }
        .sheet(item: $asking) { form in
            choose(form)
                .presentationDetents([.height(460)])
        }
    }

    @ViewBuilder private func row(_ form: Companion) -> some View {
        let available = companions.available.contains(form)
        let chosen = companions.chosen == form
        if available {
            Button { if !chosen { asking = form } } label: {
                HStack(spacing: 14) {
                    Image(form.stillName(stage: stage.rawValue))
                        .resizable().scaledToFit()
                        .frame(width: 96, height: 108)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(form.title)
                            .font(DisplayFont.display(22, .heavy))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(chosen ? "Meditating with you" : form == .otto ? "Where he started" : "Unlocked")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    if chosen {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(OnboardingGreen.fill)
                    }
                }
                .padding(14)
                .background(TileFill(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(chosen ? OnboardingGreen.fill : .clear, lineWidth: 2.5))
            }
            .buttonStyle(.tactile)
            .accessibilityLabel("Otto as \(form.withArticle)\(chosen ? ", chosen" : "")")
        } else {
            let next = Companion.next(lifetime: lifetime) == form
            let ready = form.threshold <= lifetime
            HStack(spacing: 14) {
                Image(form.stillName(stage: OttoAura.Stage.steady.rawValue))
                    .resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(AppColor.textPrimary.opacity(0.22))
                    .frame(width: 72, height: 80)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ready ? "A new form is ready" : "At \(form.threshold.formatted()) points")
                        .font(DisplayFont.display(18, .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                    if ready {
                        Text("He changes next time you open Home.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    } else if next {
                        ProgressView(value: Double(lifetime), total: Double(form.threshold))
                            .tint(AppColor.auraRing)
                        Text("\(lifetime.formatted()) / \(form.threshold.formatted())")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(TileFill(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), opacity: 0.6))
            .accessibilityElement(children: .combine)
        }
    }

    private func choose(_ form: Companion) -> some View {
        VStack(spacing: 14) {
            OttoAuraFigure(stage: stage, size: 170, rig: OttoRigHolder(), form: form)
                .frame(height: 180)
            Text("Otto as \(form.withArticle)")
                .font(DisplayFont.display(24, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(form == .otto ? "Where he started" : "Unlocked at \(form.threshold.formatted()) lifetime points")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text("His glow, \(SessionRewardView.name(stage)) today. His hat comes too.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Meditate as \(form.withArticle)") {
                companions.choose(form)
                asking = nil
            }
            .buttonStyle(TogetherStyle.green)
            Button("Keep the \(companions.chosen.creature)") { asking = nil }
                .font(AppFont.body.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .buttonStyle(.tactile)
        }
        .padding(AppMetrics.screenPadding)
    }
}

/// The flicker's ticks and the reveal's thump, under Settings > Haptics.
private enum EvolutionHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let note = UINotificationFeedbackGenerator()

    static func tick() {
        guard Tactile.hapticsOn else { return }
        light.impactOccurred(intensity: 0.6)
        light.prepare()
    }

    static func success() {
        guard Tactile.hapticsOn else { return }
        note.notificationOccurred(.success)
    }
}
