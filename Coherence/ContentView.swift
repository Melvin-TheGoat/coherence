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
                    Button("Begin — Regular (2 min)") {
                        coordinator.begin(mode: "silence", trackID: nil, plannedDurationSec: 120,
                                          bellyBreathing: false, hapticsEnabled: true)
                    }
                    Button("Begin — Belly (2 min)") {
                        coordinator.begin(mode: "silence", trackID: nil, plannedDurationSec: 120,
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
