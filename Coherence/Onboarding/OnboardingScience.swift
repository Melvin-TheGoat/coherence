import SwiftUI

// The science section (Aziz, 2026-10-17, built from the canvas
// "Onboarding neuroscience screens"). Three white pages between the life
// moments clip and "How 808 makes meditation stick", shaped by the sales
// research behind them:
//
// 1. Teach ONE insight that leads to what only 808 does (Challenger): the
//    brain adapts to what you do daily, so showing up often is what changes
//    you. That is the habit 808 exists to build.
// 2. Let the reader name the value (SPIN): they pick the benefit they want,
//    and it comes back on the next screen and on the paywall.
// 3. Size the plan to one day and hand their answers back: 13 minutes, at
//    the time they picked, toward the benefit they picked.
//
// Gain framing throughout (Gallagher & Updegraff 2012): the years screens
// already carry the loss. Every claim names a study in the small print, and
// none is a health promise. "Adds brain cells" was asked for and refused: a
// scan shows gray matter, not new neurons.

// MARK: - The brain drawing

/// A brain seen from the side, in the 300 by 220 space the mockups drew it
/// in, scaled to whatever frame it is given.
private struct BrainPath: Shape {
    enum Part { case outline, cerebellum, hippocampus, folds }
    let part: Part

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 300, sy = rect.height / 220
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        switch part {
        case .outline:
            path.move(to: p(78, 158))
            path.addCurve(to: p(40, 88), control1: p(46, 150), control2: p(30, 118))
            path.addCurve(to: p(142, 24), control1: p(50, 54), control2: p(92, 26))
            path.addCurve(to: p(266, 80), control1: p(196, 21), control2: p(246, 42))
            path.addCurve(to: p(252, 154), control1: p(283, 112), control2: p(274, 142))
            path.addCurve(to: p(200, 168), control1: p(240, 170), control2: p(216, 175))
            path.addCurve(to: p(155, 180), control1: p(190, 183), control2: p(170, 187))
            path.addLine(to: p(151, 202))
            path.addCurve(to: p(138, 202), control1: p(149, 209), control2: p(140, 209))
            path.addLine(to: p(134, 180))
            path.addCurve(to: p(78, 158), control1: p(112, 182), control2: p(92, 173))
            path.closeSubpath()
        case .cerebellum:
            path.move(to: p(200, 168))
            path.addCurve(to: p(250, 160), control1: p(214, 176), control2: p(238, 174))
            path.addCurve(to: p(236, 150), control1: p(256, 152), control2: p(246, 146))
            path.addCurve(to: p(200, 168), control1: p(226, 154), control2: p(212, 156))
            path.closeSubpath()
        case .hippocampus:
            path.move(to: p(134, 132))
            path.addCurve(to: p(194, 118), control1: p(146, 112), control2: p(176, 108))
            path.addCurve(to: p(190, 134), control1: p(204, 124), control2: p(200, 136))
            path.addCurve(to: p(150, 140), control1: p(176, 128), control2: p(160, 130))
            path.addCurve(to: p(134, 132), control1: p(142, 146), control2: p(130, 142))
            path.closeSubpath()
        case .folds:
            let folds: [[CGFloat]] = [
                [72, 74, 90, 66, 104, 78, 98, 94],
                [118, 44, 128, 60, 146, 58, 150, 44],
                [228, 66, 220, 80, 232, 96, 248, 94],
                [62, 120, 82, 112, 96, 126, 112, 118],
            ]
            for f in folds {
                path.move(to: p(f[0], f[1]))
                path.addCurve(to: p(f[6], f[7]), control1: p(f[2], f[3]), control2: p(f[4], f[5]))
            }
        }
        return path
    }
}

/// The brain with the four areas the Massachusetts General Hospital scans
/// found growing (Hölzel et al. 2011: the hippocampus, the posterior
/// cingulate, the temporo-parietal junction and the cerebellum), lit green.
/// `grown` runs 0 to 1, so the areas can light up as the screen arrives.
private struct GrowingBrain: View {
    var grown: CGFloat

    private static let line = Color(red: 0.60, green: 0.71, blue: 0.59)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 300
            ZStack {
                BrainPath(part: .outline).fill(Color(red: 0.97, green: 0.98, blue: 0.965))
                BrainPath(part: .outline).stroke(Self.line, style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round))
                BrainPath(part: .folds).stroke(Self.line.opacity(0.45), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                Group {
                    BrainPath(part: .cerebellum).fill(OnboardingGreen.fill.opacity(0.35))
                    BrainPath(part: .cerebellum).stroke(OnboardingGreen.shade, lineWidth: 2.4 * s)
                    Circle().fill(OnboardingGreen.fill.opacity(0.14))
                        .frame(width: 60 * s, height: 60 * s).position(x: 168 * s, y: 126 * s)
                    BrainPath(part: .hippocampus).fill(OnboardingGreen.fill)
                    BrainPath(part: .hippocampus).stroke(OnboardingGreen.shade, lineWidth: 2 * s)
                    glow(x: 196, y: 74, r: 11, s: s)
                    glow(x: 230, y: 110, r: 9, s: s)
                }
                .opacity(grown)
                .scaleEffect(0.85 + 0.15 * grown)
            }
        }
        .aspectRatio(300 / 220, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func glow(x: CGFloat, y: CGFloat, r: CGFloat, s: CGFloat) -> some View {
        ZStack {
            Circle().fill(OnboardingGreen.fill.opacity(0.16)).frame(width: r * 4.4 * s, height: r * 4.4 * s)
            Circle().fill(OnboardingGreen.fill).frame(width: r * 2 * s, height: r * 2 * s)
            Circle().stroke(OnboardingGreen.shade, lineWidth: 2 * s).frame(width: r * 2 * s, height: r * 2 * s)
        }
        .position(x: x * s, y: y * s)
    }
}

// MARK: - Shared pieces

/// The page every science screen stands on: a title and a line under it at
/// the top, the screen's own middle, and Continue rising once it has all
/// arrived. White, like "How 808 makes meditation stick" after it.
private struct SciencePage<Middle: View>: View {
    let title: String
    let subtitle: String
    let source: String
    var cta: String = "Continue"
    let onContinue: () -> Void
    /// Handed whether the screen has arrived, so the middle can animate in.
    @ViewBuilder let middle: (_ shown: Bool) -> Middle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var ctaShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            middle(shown)
                .frame(maxHeight: .infinity)
            Text(source)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 4)
        // Clear of the progress bar and Back above it.
        .padding(.top, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: cta, action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 30)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
        .task {
            if reduceMotion { shown = true; ctaShown = true; return }
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.35)) { shown = true }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
            WelcomeHaptics.land()
        }
    }
}

/// A small proof card: a label in capitals and the finding under it.
private struct FindingCard: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(OnboardingGreen.shade)
            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ScienceColors.greenWash))
        .accessibilityElement(children: .combine)
    }
}

enum ScienceColors {
    static let greenWash = Color(red: 0.93, green: 0.97, blue: 0.925)
    static let blueWash = Color(red: 0.93, green: 0.953, blue: 0.973)
    static let blueInk = Color(red: 0.247, green: 0.502, blue: 0.678)
}

// MARK: - 1. Your brain becomes what you do every day

/// The insight: neuroplasticity, the scan that shows it, and the session
/// data that says showing up often is what changes you most.
///
/// - "More gray matter in areas for learning, memory and emotion" after
///   eight weeks: Hölzel et al. 2011, Psychiatry Research: Neuroimaging
///   (Massachusetts General Hospital).
/// - "4 to 7 days a week improved the most", 280,000 sessions: Cearns &
///   Clark 2023, JMIR (University of Adelaide).
struct NeuroBrainScreen: View {
    let onContinue: () -> Void

    @State private var grown: CGFloat = 0

    var body: some View {
        SciencePage(title: "Your brain becomes what you do every day.",
                    subtitle: "Neuroscientists call it neuroplasticity: whatever you practice, your brain builds up. Meditation builds up the parts that keep you steady.",
                    source: "Based on studies at Massachusetts General Hospital and the University of Adelaide.",
                    onContinue: onContinue) { shown in
            VStack(spacing: 10) {
                Spacer(minLength: 8)
                GrowingBrain(grown: grown)
                    .frame(maxWidth: 230)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 8)
                FindingCard(label: "ON A BRAIN SCAN",
                            text: "After eight weeks of meditation, people had more gray matter in areas for learning, memory and emotion.")
                FindingCard(label: "IN 280,000 SESSIONS",
                            text: "The people who meditated 4 to 7 days a week improved the most.")
            }
            .onChange(of: shown) { _, now in
                guard now else { return }
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.35)) { grown = 1 }
            }
            .onAppear { if shown { grown = 1 } }
        }
    }
}

// MARK: - 2. Which would change your days the most?

/// The benefit, picked by the reader (`Benefit`). It opens on the one their
/// goal answer points to; a tap moves it, with a tick, and Continue keeps it.
struct NeuroPickScreen: View {
    @Binding var benefit: Benefit?
    let suggested: Benefit
    let onContinue: () -> Void

    private var picked: Benefit { benefit ?? suggested }

    var body: some View {
        SciencePage(title: "Which would change your days the most?",
                    subtitle: "What a few weeks of daily practice did for people in studies:",
                    source: "Based on studies at NYU, UC Santa Barbara, UCLA and the University of Adelaide.",
                    onContinue: {
                        if benefit == nil { benefit = suggested }
                        onContinue()
                    }) { _ in
            VStack(spacing: 10) {
                Spacer(minLength: 10)
                ForEach(Benefit.allCases) { option in
                    Button {
                        benefit = option
                        WelcomeHaptics.tick()
                    } label: {
                        row(option, on: option == picked)
                    }
                    .buttonStyle(.tactile)
                    .accessibilityAddTraits(option == picked ? .isSelected : [])
                }
                Spacer(minLength: 10)
            }
        }
    }

    private func row(_ option: Benefit, on: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(on ? OnboardingGreen.fill : Color.white)
                Circle().strokeBorder(on ? OnboardingGreen.fill : Color(red: 0.85, green: 0.82, blue: 0.80), lineWidth: 2.5)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(option.line)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? ScienceColors.greenWash : Color(red: 0.968, green: 0.957, blue: 0.945))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? OnboardingGreen.fill : .clear, lineWidth: 2.5)
        )
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - 3. Just a few minutes a day

/// The plan, made small (Aziz, 2026-10-18: "13 minutes" could overwhelm, and
/// the readback of their time and goal read awkwardly). No number at all, and
/// never the five minutes that open Block's apps, which copy does not name.
/// The science is habit formation (Lally et al. 2010, UCL): repeating a
/// behaviour in the same context makes it automatic, and missing one day did
/// not materially set it back. Drawn as a week of six checks and one gap.
struct NeuroPlanScreen: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many of the week's days have lit, in order.
    @State private var lit = 0

    private static let days = ["M", "T", "W", "T", "F", "S", "S"]
    /// The day left empty: the missed one that does not undo the week.
    private static let missed = 3

    var body: some View {
        SciencePage(title: "Just a few minutes a day.",
                    subtitle: "A habit forms by repeating something in the same part of your day. You don't need long sessions to start.",
                    source: "Based on a habit study at University College London.",
                    onContinue: onContinue) { shown in
            VStack(spacing: 18) {
                Spacer(minLength: 6)
                week
                Text("Missed a day? You haven't lost your progress.")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .opacity(lit >= Self.days.count ? 1 : 0)
                Spacer(minLength: 6)
                Text("808 makes it easy to show up, one day at a time.")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: shown) {
                guard shown, lit == 0 else { return }
                if reduceMotion { lit = Self.days.count; return }
                try? await Task.sleep(for: .milliseconds(400))
                for i in 0..<Self.days.count {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lit = i + 1 }
                    if i != Self.missed { WelcomeHaptics.tick() }
                    try? await Task.sleep(for: .milliseconds(220))
                }
            }
        }
    }

    private var week: some View {
        HStack(spacing: 9) {
            ForEach(Array(Self.days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 7) {
                    ZStack {
                        if i == Self.missed {
                            Circle()
                                .strokeBorder(Color(red: 0.84, green: 0.80, blue: 0.765),
                                              style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        } else {
                            Circle().fill(Color(red: 0.937, green: 0.918, blue: 0.898))
                            Circle()
                                .fill(OnboardingGreen.fill)
                                .scaleEffect(i < lit ? 1 : 0.2)
                                .opacity(i < lit ? 1 : 0)
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                                .opacity(i < lit ? 1 : 0)
                        }
                    }
                    .frame(width: 38, height: 38)
                    Text(day)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(white: 0.965)))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A week with six days meditated and one day missed")
    }
}
