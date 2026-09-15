import SwiftUI

/// What a session that could not be scored ends on (Aziz, 2026-09-14: he tapped
/// Begin then End right away, twice, and the phone just dropped the live screen
/// with no word, while PostHog read it as a broken session).
///
/// Two cases, told apart by the Watch's payload:
/// - **too short**: under `SessionStore.minDurationSec`. An accident, not a
///   failure. Nothing was saved and nothing is wrong.
/// - **unreadable**: long enough, but the Watch returned no result. Rare, and
///   honest about it.
struct SessionTooShortView: View {
    let discard: SessionCoordinator.Discard
    let onStartAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: discard.tooShort ? "timer" : "applewatch.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColor.accentGoldText)
                .padding(.bottom, 22)

            Text(discard.tooShort ? "Too short to score" : "Your Watch couldn't read that session")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(explanation)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onStartAgain) { Text("Start a session") }
                .buttonStyle(PrimaryButtonStyle())
            Button("Done", action: onDone)
                .font(AppFont.callout.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 14)
        }
        .padding(AppMetrics.screenPadding)
        .padding(.bottom, 8)
        .screenBackground()
    }

    private var explanation: String {
        let length = discard.durationSec < 60
            ? "\(discard.durationSec) second\(discard.durationSec == 1 ? "" : "s")"
            : "\(discard.durationSec / 60) min"
        if discard.tooShort {
            return "808 scores a session once it runs at least \(SessionStore.minDurationSec) seconds. This one was \(length), so it wasn't saved."
        }
        return "It ran \(length), but no readings came back from your Watch, so it wasn't saved. Keep the Watch snug on your wrist and try again."
    }
}
