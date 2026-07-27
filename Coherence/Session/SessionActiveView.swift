import SwiftUI

/// The mid-session screen — the calm-stakes moment. Deliberately minimal and
/// biometric-free (evidence comes after, not during): a slow breathing pacer orb
/// (~6 breaths/min) in the muted calm accent, elapsed time, and a quiet end
/// control. The Watch measures + owns the authoritative end; this guides + soothes.
struct SessionActiveView: View {
    let bellyBreathing: Bool
    var onEnd: () -> Void

    @State private var inhaling = false
    @State private var elapsed = 0

    // ~6 breaths/min: 5 s inhale, 5 s exhale.
    private let breathPhase = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()

            VStack {
                Spacer()

                ZStack {
                    orb
                    Text(inhaling ? "Breathe in" : "Breathe out")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .animation(.easeInOut(duration: 0.6), value: inhaling)
                }

                Spacer()

                Text(timeString(elapsed))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)

                if bellyBreathing {
                    Text("Rest your wrist flat on your belly")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.top, 4)
                }

                Button("End session", action: onEnd)
                    .font(AppFont.callout.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 28)
                    .padding(.bottom, 8)
            }
            .padding(AppMetrics.screenPadding)
        }
        .onAppear { inhaling = true }
        .onReceive(breathPhase) { _ in inhaling.toggle() }
        .onReceive(clock) { _ in elapsed += 1 }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(AppColor.calmAccent.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 28)
            Circle()
                .fill(RadialGradient(
                    colors: [AppColor.calmAccent.opacity(0.55), AppColor.calmAccent.opacity(0.06)],
                    center: .center, startRadius: 8, endRadius: 150))
                .frame(width: 250, height: 250)
            Circle()
                .stroke(AppColor.calmAccent.opacity(0.45), lineWidth: 1.5)
                .frame(width: 250, height: 250)
        }
        .scaleEffect(inhaling ? 1.0 : 0.62)
        .animation(.easeInOut(duration: 5), value: inhaling)
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    SessionActiveView(bellyBreathing: true, onEnd: {})
}
