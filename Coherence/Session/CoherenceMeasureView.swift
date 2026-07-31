import SwiftUI
import AVFoundation

/// Small live view of what the camera sees — with a finger properly on the
/// lens it glows solid red, which is itself placement feedback. Wraps the
/// capture object's single shared preview view, so screens can swap without
/// re-attaching the layer (re-attachment glitches a running session).
private struct CameraPreviewCircle: UIViewRepresentable {
    let view: PPGPreviewView
    func makeUIView(context: Context) -> PPGPreviewView { view }
    func updateUIView(_ uiView: PPGPreviewView, context: Context) {}
}

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
                    ProgressView("Starting the camera…")
                        .tint(AppColor.accentGold)
                        .frame(maxHeight: .infinity)
                case .waiting:
                    waiting
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
            .onAppear { capture.start() }        // camera + torch up immediately
            .onDisappear { capture.cancel() }
        }
        .interactiveDismissDisabled(capture.phase == .measuring)
    }

    // MARK: - Waiting / placement

    /// Camera + torch are live from the moment the sheet opens. The user
    /// places their finger (the circle goes solid red), then taps Start — the
    /// button stays dim until the finger is detected. A mid-read finger-off
    /// also lands back here.
    private var waiting: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CameraPreviewCircle(view: capture.previewView)
                .frame(width: 130, height: 130)
                .clipShape(Circle())
                .overlay(Circle().stroke(
                    capture.fingerDetected ? AppColor.accentGold : AppColor.backgroundSecondary,
                    lineWidth: 3))
                .padding(.bottom, 22)

            Text("Cover the camera and flash\nwith your fingertip")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                coachRow("hand.point.up.left", "Cup your hand over the top of the phone, fingertip flat across camera and flash together.")
                coachRow("hand.raised", "Light touch — pressing hard squeezes the blood out.")
                coachRow("timer", "45 seconds. Sit still, breathe naturally.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 12)

            Text(capture.fingerDetected
                 ? "Got it — the circle is red. Hit Start."
                 : "The circle turns solid red when your finger is placed right.")
                .font(AppFont.caption)
                .foregroundStyle(capture.fingerDetected ? AppColor.accentGold : AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            #if DEBUG
            Text(capture.debugLive)
                .font(.caption2.monospaced())
                .foregroundStyle(AppColor.textSecondary.opacity(0.6))
                .frame(height: 14)
            #endif

            Spacer(minLength: 0)
            Button("Start") { capture.beginMeasurement() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!capture.fingerDetected)
                .opacity(capture.fingerDetected ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity)
    }

    private func coachRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(AppColor.accentGold)
            Text(text)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary.opacity(0.88))
        }
    }

    // MARK: - Measuring

    private var measuring: some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 28)

            // What the camera sees: solid red glow = finger placed right.
            CameraPreviewCircle(view: capture.previewView)
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .overlay(Circle().stroke(
                    capture.fingerDetected ? AppColor.accentGold : AppColor.backgroundSecondary,
                    lineWidth: 2))
                .padding(.bottom, 18)

            // Fixed-height slot so the layout never jumps when the text swaps.
            Text(capture.fingerDetected
                 ? "Reading. Stay still."
                 : "Cover the camera and flash with your fingertip.")
                .font(AppFont.callout)
                .foregroundStyle(capture.fingerDetected
                                 ? AppColor.textSecondary : AppColor.accentGold)
                .multilineTextAlignment(.center)
                .frame(height: 48)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
            #if DEBUG
            if !capture.debugResult.isEmpty {
                Text(capture.debugResult)
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppColor.textSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 10))
            }
            #endif
            Spacer(minLength: 0)
            Button("Try again") { capture.start() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}
