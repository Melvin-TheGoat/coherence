import SwiftUI

// The wandering question (Aziz, 2026-09-25). Its answer feeds `MindWander`,
// the arithmetic behind the "N years" moment after the mind profile: THEIR
// numbers multiplied, never invented. That moment is to be a GENERATED
// animation (Aziz), not built screens; a first attempt at building it as four
// SwiftUI screens was dropped the same day.

// MARK: - The question

/// "How much of your day is your mind somewhere else?" A slider from 10% to
/// 90% that opens on the research average, which a note under it names. Age
/// is not mentioned here (Aziz): it first appears in the "N years" moment.
struct WanderingScreen: View {
    @Binding var share: Double?
    let count: InterviewCount
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back
    private var value: Double { share ?? MindWander.average }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                OnboardingProgress(from: Double(count.index - 1) / Double(max(count.total, 1)),
                                   to: Double(count.index) / Double(max(count.total, 1)))
                Color.clear.frame(width: SeatedClipLayer.cornerWidth)
            }
            .frame(height: 40)

            Text("How much of your day is your mind somewhere else?")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
            Text("Your best guess. There's no wrong answer.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
                .padding(.top, 8)

            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 22)

            PercentSlider(value: Binding(get: { value }, set: { share = $0 }))
                .padding(.top, 12)
            HStack {
                Text("Hardly ever")
                Spacer()
                Text("Almost always")
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppColor.textPrimary.opacity(0.75))
            .padding(.top, 4)

            Text("Most people land around 47%.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue") {
                if share == nil { share = MindWander.average }
                onContinue()
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: Int((value * 20).rounded()))
    }
}

/// A 10% to 90% slider in steps of 5, green, Otto's face as the handle.
private struct PercentSlider: View {
    @Binding var value: Double
    private static let knob: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - Self.knob
            let x = travel * CGFloat((value - 0.1) / 0.8)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                    .frame(height: 14)
                Capsule().fill(OnboardingGreen.fill)
                    .frame(width: x + Self.knob / 2, height: 14)
                Image("OttoHead")
                    .resizable().scaledToFit().padding(5)
                    .frame(width: Self.knob, height: Self.knob)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .offset(x: x)
            }
            .frame(height: Self.knob)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let t = min(max((g.location.x - Self.knob / 2) / max(1, travel), 0), 1)
                value = ((0.1 + 0.8 * Double(t)) * 20).rounded() / 20
            })
        }
        .frame(height: Self.knob)
        .accessibilityElement()
        .accessibilityLabel("How much of your day your mind is somewhere else")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { d in
            value = min(0.9, max(0.1, value + (d == .increment ? 0.05 : -0.05)))
        }
    }
}
