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
            .navigationTitle("Coherence check · \(label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // The session must never feel hostage to the read.
                    Button(onComplete != nil ? "Skip" : "Cancel") { capture.cancel(); dismiss() }
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
        let remaining = max(0, Int((capture.targetDuration * (1 - capture.progress)).rounded()))
        return VStack(spacing: 0) {
            Text("Reading your pulse…")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 6)
            Spacer(minLength: 0)

            // The camera circle IS the interface: red glow = placed, the gold
            // arc around it is the 45-s progress. No second progress bar.
            ZStack {
                Circle().stroke(AppColor.backgroundSecondary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.003, capture.progress))
                    .stroke(AppColor.accentGold,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: capture.progress)
                CameraPreviewCircle(view: capture.previewView)
                    .frame(width: 138, height: 138)
                    .clipShape(Circle())
                    .opacity(capture.fingerDetected ? 1 : 0.45)
            }
            .frame(width: 184, height: 184)
            .padding(.bottom, 22)

            // Fixed-height slot so the layout never jumps when the text swaps.
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.accentGold)
                    .scaleEffect(1 + 0.35 * capture.pulseLevel)
                    .animation(.easeOut(duration: 0.12), value: capture.pulseLevel)
                Text(capture.fingerDetected
                     ? "pulse found · \(remaining)s left"
                     : "place your fingertip back over the camera")
                    .font(AppFont.callout)
                    .foregroundStyle(capture.fingerDetected
                                     ? AppColor.textSecondary : AppColor.accentGold)
                    .monospacedDigit()
            }
            .frame(height: 40)

            Spacer(minLength: 0)

            Text("Cup your hand over the top of the phone.\nStay still — jitter blurs the read.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
