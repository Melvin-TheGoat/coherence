import SwiftUI

/// Phase-4 Watch session UI: authorize once, then wait for the phone to start a
/// session. During a session it shows only elapsed time + an End control — no
/// live biometrics (evidence comes after, not during).
struct WatchContentView: View {
    @EnvironmentObject private var manager: WatchSessionManager

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()
            content
                .padding()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !manager.authorized {
            VStack(spacing: 10) {
                Text("Coherence")
                    .font(.headline)
                    .foregroundStyle(AppColor.accentGold)
                Button("Authorize") { Task { await manager.authorize() } }
                    .tint(AppColor.accentGold)
                if let msg = manager.statusMessage {
                    Text(msg).font(.caption2).foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            switch manager.phase {
            case .idle:
                VStack(spacing: 8) {
                    Text("Ready")
                        .font(.headline)
                        .foregroundStyle(AppColor.accentGold)
                    Text("Start a session from your phone")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            case .running:
                VStack(spacing: 12) {
                    Text(timeString(manager.elapsed))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.accentGold)
                    if manager.params?.bellyBreathing == true {
                        Text("belly breathing")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Button("End") { manager.endByUser() }
                        .tint(AppColor.accentGold)
                }
            case .sending:
                Text("Saving…")
                    .font(.headline)
                    .foregroundStyle(AppColor.textSecondary)
            case .sent:
                VStack(spacing: 6) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(AppColor.accentGold)
                    Text("Sent to your phone")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
