import SwiftUI

/// Shown when the Watch refuses to start a session because it can't get what it
/// needs to measure. This is deliberately a hard stop rather than a warning: a
/// session that records stillness but no heart rate is a broken result, and the
/// worst time to discover that is 25 minutes later.
struct PermissionBlockedView: View {
    let failure: StartFailure
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColor.accentGold)
                .padding(.bottom, 22)

            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(explanation)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)")
                            .font(AppFont.caption.weight(.bold))
                            .foregroundStyle(AppColor.textOnAccent)
                            .frame(width: 20, height: 20)
                            .background(AppColor.accentGold, in: Circle())
                        Text(step)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.top, 26)

            Spacer()

            Button("Done", action: onDismiss)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
    }

    private var icon: String {
        switch failure {
        case .heartRateUnavailable: "heart.slash"
        case .workoutNotAuthorized: "figure.mind.and.body"
        case .watchUnreachable: "applewatch.slash"
        }
    }

    private var title: String {
        switch failure {
        case .heartRateUnavailable: "We can't read your heart rate"
        case .workoutNotAuthorized: "We can't record your session"
        case .watchUnreachable: "Your Watch didn't answer"
        }
    }

    private var explanation: String {
        switch failure {
        case .heartRateUnavailable:
            "Your settling heart rate is one of the signals 808 measures — without it there's no evidence your practice landed, so we won't start a session that can't be read.\n\nMake sure your Watch is on your wrist, then check the permission:"
        case .workoutNotAuthorized:
            "808 records a mindful workout on your Watch — that's what keeps it measuring for the whole session. Without it we can't capture anything."
        case .watchUnreachable:
            "808 measures your session on your Apple Watch, and the Watch couldn't be launched just now."
        }
    }

    private var steps: [String] {
        switch failure {
        case .heartRateUnavailable:
            // Per-app Health permissions are managed from the iPhone only —
            // there is no 808 entry under the Watch's own Health settings.
            ["Make sure your Watch is on your wrist and snug",
             "On iPhone, open Settings → Health → Data Access & Devices",
             "Tap 808 and turn on Heart Rate"]
        case .workoutNotAuthorized:
            ["On iPhone, open the Health app",
             "Go to Sharing → Apps → 808",
             "Turn on Workouts"]
        case .watchUnreachable:
            ["Make sure your Watch is on your wrist and unlocked",
             "Check that 808 is installed on the Watch (iPhone Watch app → 808)",
             "Bring the Watch near your phone and try again"]
        }
    }
}

#Preview {
    PermissionBlockedView(failure: .heartRateUnavailable, onDismiss: {})
}
