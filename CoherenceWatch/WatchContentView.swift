import SwiftUI

/// Phase 1 Watch UI: authorize HealthKit, start a workout, watch the live BPM
/// update on the wrist, and end. This is a proving-ground screen — the real
/// session UI (haptics, timing, no live biometrics) arrives in later phases.
struct WatchContentView: View {
    @StateObject private var workout = WorkoutManager()
    @State private var isAuthorized = false

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary
                .ignoresSafeArea()

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
            }
            .padding()
        }
    }

    @ViewBuilder
    private var control: some View {
        if !isAuthorized {
            Button("Authorize") {
                Task { isAuthorized = await HealthKitAuth.authorize() }
            }
        } else if workout.isRunning {
            Button("End") { workout.end() }
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
