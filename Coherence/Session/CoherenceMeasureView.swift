import SwiftUI

/// The finger-on-camera coherence snapshot: instructions → 90 s live capture
/// with coaching → score. Presented before and after a session (Phase 9c wires
/// the flow; a DEBUG home button opens it standalone for device testing).
struct CoherenceMeasureView: View {
    /// "Before" / "After" — shown in the title so the user knows which
    /// snapshot this is.
    var label: String = "Before"
    var onComplete: ((CoherenceAnalyzer.Snapshot) -> Void)? = nil

    @StateObject private var capture = CoherenceCapture()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch capture.phase {
                case .idle:
                    instructions
                case .measuring:
                    measuring
                case .analyzing:
                    ProgressView("Reading your rhythm…")
                        .tint(AppColor.accentGold)
                        .frame(maxHeight: .infinity)
                case .done:
                    if let snap = capture.snapshot { result(snap) }
                case .failed(let message):
                    failed(message)
                }
            }
            .padding(AppMetrics.screenPadding)
            .screenBackground()
            .navigationTitle("\(label) · Coherence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { capture.cancel(); dismiss() }
                        .tint(AppColor.textSecondary)
                }
            }
            .onDisappear { capture.cancel() }
        }
        .interactiveDismissDisabled(capture.phase == .measuring)
    }

    // MARK: - Idle / instructions

    private var instructions: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "camera.macro")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.accentGold)
            Text("Read your heart's rhythm")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            VStack(alignment: .leading, spacing: 12) {
                coachRow("hand.point.up.left", "Rest your fingertip flat over the back camera and the flash together.")
                coachRow("hand.raised", "Light touch. Pressing hard squeezes the blood out of the fingertip.")
                coachRow("figure.seated.side", "Sit still for a minute and a half. Breathe however you naturally do.")
                coachRow("flashlight.on.fill", "The flash stays on and may feel warm. That's normal.")
            }
            .padding(18)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 0)
            Button("Start") { capture.start() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func coachRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(AppColor.accentGold)
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary.opacity(0.88))
        }
    }

    // MARK: - Measuring

    private var measuring: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(AppColor.backgroundSecondary, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.003, capture.progress))
                    .stroke(AppColor.accentGold,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: capture.progress)
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppColor.accentGold)
                        .scaleEffect(1 + 0.35 * capture.pulseLevel)
                        .animation(.easeOut(duration: 0.12), value: capture.pulseLevel)
                    Text("\(Int((capture.progress * capture.targetDuration).rounded()))s / \(Int(capture.targetDuration))s")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 180, height: 180)

            Text(capture.fingerDetected
                 ? "Reading. Stay still."
                 : "Cover the camera and flash with your fingertip.")
                .font(AppFont.callout)
                .foregroundStyle(capture.fingerDetected
                                 ? AppColor.textSecondary : AppColor.accentGold)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: capture.fingerDetected)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Done

    private func result(_ snap: CoherenceAnalyzer.Snapshot) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(AppColor.backgroundSecondary, lineWidth: 13)
                Circle()
                    .trim(from: 0, to: max(0.01, snap.coherenceScore))
                    .stroke(AppColor.accentGold,
                            style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int((snap.coherenceScore * 100).rounded()))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary).monospacedDigit()
                    Text("COHERENCE")
                        .font(.caption2.weight(.semibold)).tracking(1.1)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 180, height: 180)

            HStack(spacing: 10) {
                StatTile(value: String(format: "%.0f", snap.meanHR), label: "Heart rate")
                StatTile(value: String(format: "%.0f ms", snap.rmssdMs), label: "HRV (RMSSD)")
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
            Button("Done") {
                onComplete?(snap)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Failed

    private func failed(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "hand.point.up.left.and.text")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.textSecondary)
            Text(message)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Try again") { capture.start() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}
