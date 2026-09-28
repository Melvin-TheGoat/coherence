import SwiftUI

/// "Your body" (Aziz, 2026-09-28, `mockups/apple-watch/`): what the Watch
/// measured in a session, on the session's own page (`SessionView`) and on
/// the page for adding details (`SaveSessionView`). The score ring, then
/// heart rate, stillness and breathing in words, and the graphs one tap in.
/// Only ever built when the Watch measured the session: a phone-only session
/// shows no card at all, never an empty one.
struct BodyCard: View {
    let readings: BodyReadings
    var score: Double?
    let seeGraphs: () -> Void
    var inset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ScoreRing(score: score, size: 52, lineWidth: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your body")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Label("Measured on your Apple Watch", systemImage: "applewatch")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.calmAccent)
                }
                Spacer(minLength: 0)
            }

            ForEach(readings.readings, id: \.label) { reading in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.label.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(reading.note)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(reading.value)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.calmAccent)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }

            Button(action: seeGraphs) {
                HStack(spacing: 6) {
                    Text("See the graphs")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(AppColor.skyDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(inset)
    }
}

extension BodyReadings {
    /// The readings off a stored Watch measurement.
    init(_ stats: MeditationStats) {
        self.init(score: stats.overallScore, startHR: stats.startHR, endHR: stats.endHR,
                  stillness: stats.stillnessScore,
                  doorwayRate: stats.breathDoorwayRate,
                  doorwayHeldSec: stats.breathDoorwayHeldSec,
                  meanBreathingRate: stats.meanBreathingRate)
    }
}
