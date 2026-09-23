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

    /// In the valley, and Otto says it (Aziz, 2026-09-22,
    /// `mockups/after-valley.html`). Curious, not let down: a Begin-then-End
    /// by accident is not a failure and must not read as one (Steady, the open-eyed
    /// calm Otto, since the seven stages replaced Curious). It was a
    /// cream page with a timer glyph.
    var body: some View {
        let day = DayLight.at(0)
        GeometryReader { geo in
            ZStack {
                ValleyScene(progress: 0, aura: .steady)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    OttoSpeech(text: line, tail: .bottom, size: 16,
                               ink: day.ink, stroke: day.ink.opacity(0.38),
                               fill: AppColor.backgroundPrimary.opacity(0.84),
                               speaking: .constant(false))
                }
                .frame(width: min(geo.size.width - 56, 320),
                       height: max(120, SitLayout.ottoTop(in: geo.size) - 8))
                .position(x: geo.size.width / 2,
                          y: max(120, SitLayout.ottoTop(in: geo.size) - 8) / 2)
                VStack(spacing: 10) {
                    Spacer()
                    Button(action: onStartAgain) { Text("Start a session") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button(action: onDone) {
                        Text("Done")
                            .font(DisplayFont.display(15, .bold))
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    /// His line: the fact in bold, then what it means.
    private var line: String {
        let length = discard.durationSec < 60
            ? "\(discard.durationSec) second\(discard.durationSec == 1 ? "" : "s")"
            : "\(discard.durationSec / 60) min"
        if discard.tooShort {
            return "**That was \(length).** Sessions count from \(SessionStore.minDurationSec) seconds. Want to go again?"
        }
        return "**Your Watch couldn't read that one.** No readings came back, so it wasn't saved. Keep it snug and try again."
    }

}
