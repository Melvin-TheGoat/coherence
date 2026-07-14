import SwiftUI

/// Phase 2 Watch UI: authorize, run a workout showing live BPM, then on End read
/// back the recorded heartbeat series and dump the raw RR data to eyeball it.
/// Temporary proving-ground UI — the real session UI (haptics, timing, no live
/// biometrics) arrives in later phases.
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

                if let captured = workout.captured {
                    readback(captured)
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
            Button(isEnding ? "Reading…" : "End") {
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

    /// Raw beat-to-beat dump for Phase 2 verification.
    @ViewBuilder
    private func readback(_ captured: CapturedSeries) -> some View {
        VStack(spacing: 4) {
            Text("beats: \(captured.beatCount)")
            Text("uuid: \(captured.healthkitUUID.prefix(8))…")
            Text("first RR (ms):")
            Text(firstIntervalsMS(captured.rrIntervals))
                .multilineTextAlignment(.center)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(AppColor.textSecondary)
    }

    private var bpmText: String {
        guard let hr = workout.currentHR else { return "—" }
        return String(Int(hr.rounded()))
    }

    private func firstIntervalsMS(_ rr: [Double]) -> String {
        rr.prefix(10)
            .map { String(Int(($0 * 1000).rounded())) }
            .joined(separator: ", ")
    }
}

#Preview {
    WatchContentView()
}
