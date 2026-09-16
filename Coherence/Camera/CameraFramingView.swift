#if DEBUG
import SwiftUI

/// The camera, big, with a seated figure to sit into: shown on the Begin
/// sheet before a session, so the phone can be propped and the person framed
/// while moving still helps. The outline is white until Vision has found
/// someone, then teal (the body's signal, found), and the caption follows.
/// Nothing here is gold: Begin is.
///
/// 3:4, the front camera's own frame, as wide as the sheet has room for.
struct CameraFramingView: View {
    @ObservedObject var recorder: CameraSignalRecorder

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                AppColor.cameraGround
                CameraPreviewView(session: recorder.captureSession)
                SeatedFigureOutline()
                    .stroke(recorder.framed ? AppColor.calmAccent : AppColor.cameraOverlay,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 30)
                    .animation(.easeInOut(duration: 0.3), value: recorder.framed)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
            // A hairline so the card reads as a card on the dark ground before
            // the feed arrives. Grey in both states: only the outline changes.
            .overlay(RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .stroke(AppColor.textSecondary.opacity(0.2), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            Text(recorder.framed ? "You're in frame" : "Sit so your head and lap fit the outline")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// The live screen's view of the same camera: a thumbnail that says "the
/// camera is on" and nothing more. No outline, no numbers. A live readout
/// would contradict the product's stance of no biometrics during the sit,
/// and framing was settled on the Begin sheet. A teal hairline means the
/// recorder has fixed its region of interest.
struct CameraThumbnail: View {
    @ObservedObject var recorder: CameraSignalRecorder

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                AppColor.cameraGround
                CameraPreviewView(session: recorder.captureSession)
            }
            .frame(width: 84, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(recorder.roiFixed ? AppColor.calmAccent : AppColor.textSecondary.opacity(0.35),
                        lineWidth: 1))
            Text("Camera capture · \(recorder.statusLine)")
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
#endif
