import SwiftUI

/// Phase-4 debug UI: trigger a Regular or Belly session on the Watch and dump the
/// persisted result. The real setup hierarchy replaces this in Phase 5.
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var showSetup = false
    @State private var showResults = false
    @State private var showCalendar = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("808")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColor.accentGold)

                Button("Begin session") { showSetup = true }
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

                HStack(spacing: 12) {
                    if coordinator.lastSessionID != nil {
                        Button("View graphs") { showResults = true }
                    }
                    Button("Calendar") { showCalendar = true }
                    Button("History") { showHistory = true }
                    Button("Settings") { showSettings = true }
                }
                .buttonStyle(.bordered)
                .tint(AppColor.accentGold)

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
        .sheet(isPresented: $showSetup) {
            SessionSetupView()
        }
        .sheet(isPresented: $showResults) {
            if let id = coordinator.lastSessionID {
                SessionResultsView(sessionID: id)
            }
        }
        .sheet(isPresented: $showCalendar) {
            SessionHistoryView()
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { AllSessionsView() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
