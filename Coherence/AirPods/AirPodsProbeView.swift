#if DEBUG
import SwiftUI

/// DEBUG-ONLY screen for `AirPodsProbe`: live counts while a capture runs,
/// the files it wrote, and how to pull them. Reached from Settings under
/// "AirPods (debug)". Leaving the screen stops the capture, because the probe
/// lives in this view's state; that is deliberate for a first spike.
@available(iOS 26.0, *)
struct AirPodsProbeView: View {
    @StateObject private var probe = AirPodsProbe()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                statusCard
                heartCard
                motionCard
                filesCard
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationTitle("AirPods probe")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            controls
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.vertical, 12)
                .background(AppColor.backgroundPrimary)
        }
        .onDisappear { probe.stop() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Developer test")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Wear AirPods Pro 3 or Powerbeats Pro 2, keep them connected to this iPhone, and tap Start. The phone runs a mind-and-body workout so the buds measure heart rate, and records head motion at the same time. Nothing is scored or saved to your history; the workout is discarded at Stop.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Status")
            line("Phase", probe.phase.rawValue, highlight: probe.phase == .running)
            line("Elapsed", format(seconds: probe.elapsedSec))
            if let message = probe.message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentGoldText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var heartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Heart rate (HealthKit)")
            line("Samples", "\(probe.summary.hrCount)")
            line("Last", probe.summary.lastBPM.map { String(format: "%.0f bpm", $0) } ?? "none yet")
            line("Source", probe.summary.lastHRSource ?? "none yet")
            line("Gap", probe.summary.lastHRGapSec.map { String(format: "%.1f s between samples", $0) } ?? "n/a")
            line("Age", probe.summary.lastHRAgeSec.map { String(format: "%.0f s since last", $0) } ?? "n/a")
            line("Builder", probe.summary.builderBPM.map { String(format: "%.0f bpm (live builder)", $0) } ?? "nothing collected")
        }
        .card()
    }

    private var motionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Head motion (CMHeadphoneMotionManager)")
            line("Available", probe.motionAvailable ? "yes" : "no")
            line("Authorization", probe.motionAuthorization)
            line("Connected", probe.summary.motionConnected ? "yes" : "no")
            line("Samples", "\(probe.summary.motionCount)")
            line("Rate", String(format: "%.1f Hz", probe.summary.motionRateHz), highlight: probe.summary.motionRateHz > 0)
            if let p = probe.summary.lastPitch, let r = probe.summary.lastRoll, let y = probe.summary.lastYaw {
                line("Attitude", String(format: "pitch %.3f  roll %.3f  yaw %.3f rad", p, r, y))
            }
            if let a = probe.summary.lastAccel {
                line("User accel", String(format: "%.4f g", a))
            }
        }
        .card()
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Captures")
            if probe.files.isEmpty {
                Text("No captures yet.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(probe.files) { file in
                    HStack {
                        Text(file.name)
                            .font(AppFont.caption.monospaced())
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(format(bytes: file.bytes))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            Text("Files land in Documents/AirPodsCaptures (visible in the Files app). From a Mac: xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier <bundle id> --source Documents/AirPodsCaptures --destination ~/Desktop/captures --device <udid>")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !probe.files.isEmpty {
                Button("Delete all captures", role: .destructive) { probe.deleteAllCaptures() }
                    .font(AppFont.caption.weight(.medium))
            }
        }
        .card()
    }

    private var controls: some View {
        Group {
            switch probe.phase {
            case .idle, .stopped:
                Button("Start capture") { Task { await probe.start() } }
                    .buttonStyle(PrimaryButtonStyle())
            case .running:
                Button("Stop capture") { probe.stop() }
                    .buttonStyle(SecondaryButtonStyle())
            case .authorizing, .starting, .stopping:
                Button(probe.phase.rawValue) {}
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(true)
            }
        }
    }

    private func line(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(AppFont.callout.monospacedDigit())
                .foregroundStyle(highlight ? AppColor.calmAccent : AppColor.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func format(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func format(bytes: Int) -> String {
        bytes >= 1_000_000 ? String(format: "%.1f MB", Double(bytes) / 1_000_000)
            : bytes >= 1_000 ? String(format: "%.0f KB", Double(bytes) / 1_000)
            : "\(bytes) B"
    }
}
#endif
