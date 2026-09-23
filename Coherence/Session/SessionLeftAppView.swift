import SwiftUI

/// What 808 shows when you come back from being away too long mid-sit
/// (Melvin, 2026-09-23: "if they leave for more than 10 seconds then the
/// meditation doesn't count"). Drawn the way `SessionTooShortView` is: Otto,
/// in the valley, saying what happened in his own bubble.
///
/// The one thing this screen does that `SessionTooShortView` doesn't: it
/// asks BEFORE the sit is over, not after. "End session" is the only
/// obvious way out; the line underneath is there for an honest accident
/// (the phone locked itself, a call came in) without inviting every
/// wandering tap to take it.
struct SessionLeftAppView: View {
    let onEndSession: () -> Void
    let onOverride: () -> Void

    var body: some View {
        let day = DayLight.at(0)
        GeometryReader { geo in
            ZStack {
                ValleyScene(progress: 0, aura: .steady)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    OttoSpeech(text: "**You left 808.** This session won't count.",
                               tail: .bottom, size: 16,
                               ink: day.ink, stroke: day.ink.opacity(0.38),
                               fill: AppColor.backgroundPrimary.opacity(0.84),
                               speaking: .constant(false))
                }
                .frame(width: min(geo.size.width - 56, 320),
                       height: max(120, SitLayout.ottoTop(in: geo.size) - 8))
                .position(x: geo.size.width / 2,
                          y: max(120, SitLayout.ottoTop(in: geo.size) - 8) / 2)
                VStack(spacing: 8) {
                    Spacer()
                    Button(action: onEndSession) { Text("End session") }
                        .buttonStyle(PrimaryButtonStyle())
                    // Deliberately not styled as a button (Melvin: don't make
                    // the override obvious) — caption size, faint, but still
                    // a normal tap target, for whoever really was still
                    // sitting there.
                    Button(action: onOverride) {
                        Text("I was still meditating")
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                // Matches End's own fix on the sit screen this replaces:
                // a control this close to a hidden home indicator needs to
                // clear the same 44pt, or iOS can read the first tap as the
                // start of a swipe home instead of a tap on the button.
                .padding(.bottom, 44)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

#Preview("Left the app") {
    SessionLeftAppView(onEndSession: {}, onOverride: {})
}
