import SwiftUI

/// The mid-session screen — the calm-stakes moment, shown on the phone for
/// **every** session type (guided, frequency, nature, silence; belly or not)
/// while the Watch measures. Deliberately minimal and biometric-free: evidence
/// comes after, not during. A slow breathing pacer orb (~6 breaths/min) in the
/// muted calm accent, the session clock, and a quiet end control.
///
/// The pacer is a suggestion, not a requirement — the resonance pace is the
/// fastest way into the state we're looking for regardless of what's playing.
struct SessionActiveView: View {
    let bellyBreathing: Bool
    /// When the session actually started, so the clock survives the view being
    /// rebuilt and matches the Watch rather than drifting from its own count.
    var startedAt: Date = Date()
    /// nil for open-ended sessions — those count up instead of down.
    var plannedDurationSec: Int?
    /// "Belly · 10 min · Deep Meditation" — so you always know what's running.
    var planChip: String? = nil
    var onEnd: () -> Void

    @State private var inhaling = false
    @State private var now = Date()

    // ~6 breaths/min: 5 s inhale, 5 s exhale.
    private let breathPhase = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsed: Int { max(0, Int(now.timeIntervalSince(startedAt))) }

    /// Counts down for timed sessions, up for open-ended ones.
    private var displaySeconds: Int {
        guard let planned = plannedDurationSec else { return elapsed }
        return max(0, planned - elapsed)
    }

    /// Timed session's countdown has run out; the Watch is wrapping up.
    private var finishing: Bool { plannedDurationSec != nil && displaySeconds == 0 }

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()

            VStack {
                if let planChip {
                    MetaChip(text: planChip)
                        .padding(.top, 6)
                }

                Spacer()

                ZStack {
                    orb
                    Text(inhaling ? "Breathe in" : "Breathe out")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .animation(.easeInOut(duration: 0.6), value: inhaling)
                }

                Spacer()

                Text(timeString(displaySeconds))
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)

                // A timed session ends on the WATCH's clock, which started a
                // beat after the phone's — so at 0:00 say what's happening
                // instead of sitting on a frozen countdown.
                Text(finishing
                     ? "Finishing on your Watch…"
                     : (bellyBreathing
                        ? "Lie back with your wrist flat on your belly"
                        : "Your Watch is measuring — let it settle"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

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
        .onReceive(clock) { now = $0 }
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
    SessionActiveView(bellyBreathing: true, plannedDurationSec: 600,
                      planChip: "Belly · 10 min · Deep Meditation", onEnd: {})
}
