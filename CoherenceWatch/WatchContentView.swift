import SwiftUI

/// Option-4 measurement UI: authorize, run a mind-and-body workout showing live
/// BPM, then on End report how finely the Watch sampled heart rate (sample count
/// and the gaps between samples). Temporary proving-ground UI — the real session
/// UI (haptics, timing, no live biometrics) arrives in later phases.
struct WatchContentView: View {
    @StateObject private var workout = WorkoutManager()
    @State private var isAuthorized = false
    @State private var isEnding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(bpmText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accentGold)
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)

                control
                    .tint(AppColor.accentGold)

                if let message = workout.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let report = workout.samplingReport {
                    Text(report)
                        .font(.system(.caption2, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let stored = workout.storedReport {
                    Text(stored)
                        .font(.system(.caption2, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.accentGold)
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
            Button("Start") { workout.start() }
        }
    }

    private var bpmText: String {
        guard let hr = workout.currentHR else { return "—" }
        return String(Int(hr.rounded()))
    }
}

#Preview {
    WatchContentView()
}
