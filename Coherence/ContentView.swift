import SwiftUI

/// Phase-4 debug UI: trigger a Regular or Belly session on the Watch and dump the
/// persisted result. The real setup hierarchy replaces this in Phase 5.
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var showResults = false

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Coherence")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColor.accentGold)

                VStack(spacing: 12) {
                    // TEMP debug triggers: open-ended (plannedDurationSec nil) so the
                    // session runs until you tap End on the Watch — no auto-shutoff
                    // during testing. Timed sessions remain a real product feature.
                    Button("Begin — Regular") {
                        coordinator.begin(mode: "silence", trackID: nil, plannedDurationSec: nil,
                                          bellyBreathing: false, hapticsEnabled: true)
                    }
                    Button("Begin — Belly") {
                        coordinator.begin(mode: "silence", trackID: nil, plannedDurationSec: nil,
                                          bellyBreathing: true, hapticsEnabled: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentGold)

                Text(coordinator.status)
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                if let summary = coordinator.lastSummary {
                    Text(summary)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                }

                if coordinator.lastSessionID != nil {
                    Button("View graphs") { showResults = true }
                        .buttonStyle(.bordered)
                        .tint(AppColor.accentGold)
                }

                // TEMP: belly readability numbers, for calibrating the gate.
                if let diag = coordinator.lastBellyDiag {
                    Text(diag)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .sheet(isPresented: $showResults) {
            if let id = coordinator.lastSessionID {
                SessionResultsView(sessionID: id)
            }
        }
    }
}
