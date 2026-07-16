import SwiftUI
import Charts

/// Phase-2 proving-ground UI: authorize, pick Regular vs Belly breathing, run a
/// workout that captures motion + HR, and on end eyeball the raw capture (sample
/// counts, and for belly the pitch waveform + estimated breaths/min). The real
/// session UI (haptics, timing, no live biometrics) arrives in later phases.
struct WatchContentView: View {
    @StateObject private var workout = WorkoutManager()
    @State private var isAuthorized = false
    @State private var belly = false
    @State private var isEnding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(bpmText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accentGold)
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)

                if isAuthorized && !workout.isRunning && workout.capture == nil {
                    Toggle("Belly breathing", isOn: $belly)
                        .font(.caption)
                        .tint(AppColor.accentGold)
                }

                if workout.isRunning && belly {
                    Text(liveBreathsText)
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                control
                    .tint(AppColor.accentGold)

                if let message = workout.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let capture = workout.capture {
                    captureView(capture)
                }
            }
            .padding()
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
    }

    @ViewBuilder
    private var control: some View {
        if !isAuthorized {
            Button("Authorize") {
                Task { isAuthorized = await HealthKitAuth.authorize() }
            }
        } else if workout.isRunning {
            Button(isEnding ? "Ending…" : "End") {
                isEnding = true
                Task {
                    await workout.end()
                    isEnding = false
                }
            }
            .disabled(isEnding)
        } else {
            Button("Start") { workout.start(bellyBreathing: belly) }
        }
    }

    @ViewBuilder
    private func captureView(_ capture: CaptureSummary) -> some View {
        VStack(spacing: 6) {
            Text("motion: \(capture.motionCount)  hr: \(capture.hrCount)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)

            if capture.bellyBreathing {
                if let breaths = capture.finalBreaths {
                    Text(String(format: "≈ %.1f breaths/min", breaths))
                        .font(.caption)
                        .foregroundStyle(AppColor.accentGold)
                    Chart(capture.pitchSeries) { point in
                        LineMark(x: .value("t", point.t), y: .value("pitch", point.pitch))
                            .foregroundStyle(AppColor.accentGold)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 90)
                } else {
                    Text("no clear breathing signal")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var bpmText: String {
        guard let hr = workout.currentHR else { return "—" }
        return String(Int(hr.rounded()))
    }

    private var liveBreathsText: String {
        guard let b = workout.liveBreaths else { return "reading breath…" }
        return String(format: "≈ %.1f breaths/min", b)
    }
}

#Preview {
    WatchContentView()
}
