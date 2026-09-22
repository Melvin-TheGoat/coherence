import SwiftUI

/// The sit. Otto in a valley, a sun that crosses it, and a clock you have to
/// ask for.
///
/// Built from `mockups/session-v3.html`. Three decisions carry the screen and
/// all three are deliberate:
///
/// **The clock is on the whole time** (Aziz, 2026-09-21), inside a ring that
/// closes over the sit. It used to hide itself after the opening and come
/// back for three seconds on a tap, on the argument that a countdown you
/// cannot look away from is the opposite of the thing being sold. It is not:
/// a timer you have to go looking for is a timer you keep touching the screen
/// for, which is worse. **No biometrics, ever**, on this screen: evidence
/// comes after, not during.
///
/// **The ring is a medallion in the sky, not a hoop around him.** At 79% of
/// the width it ran 88pt into Otto's face on a tall phone and 137pt on a
/// short one. `SitLayout` hangs it off the top of his head instead.
///
/// The sun does what a progress bar would, and cannot be read precisely,
/// which is exactly right for somebody mid-sit.
struct SessionActiveView: View {
    /// When the session actually started, so the clock survives the view
    /// being rebuilt and matches whatever is measuring rather than drifting
    /// from its own count.
    var startedAt: Date = Date()
    /// nil for open-ended sessions, which count up instead of down.
    var plannedDurationSec: Int?
    /// "10 min · Deep Meditation" — so you always know what is running.
    var planChip: String? = nil
    var onEnd: () -> Void

    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// An open-ended sit has no end to travel toward, so the valley takes a
    /// nominal twenty minutes to reach dusk and then holds there. It is
    /// atmosphere, not a gauge, and nothing on screen claims otherwise.
    private static let openArcSec = 1_200.0
    /// How long the opening frame stays up before the screen goes quiet. Long
    /// enough to read two lines and the plan chip without hurrying, short
    /// enough that nobody is still reading a minute in.
    private static let arrivalSec = 9.0

    private var elapsed: Int { max(0, Int(now.timeIntervalSince(startedAt))) }

    /// 0 at the first breath, 1 at the last. The whole scene reads this.
    private var progress: Double {
        let total = Double(plannedDurationSec ?? 0) > 0
            ? Double(plannedDurationSec!) : Self.openArcSec
        return min(1, Double(elapsed) / total)
    }

    /// Counts down for timed sessions, up for open-ended ones.
    private var displaySeconds: Int {
        guard let planned = plannedDurationSec else { return elapsed }
        return max(0, planned - elapsed)
    }

    private var arriving: Bool { Double(elapsed) < Self.arrivalSec }
    /// The clock has run out. Whatever is measuring is wrapping up.
    private var finishing: Bool { plannedDurationSec != nil && displaySeconds == 0 }

    private var day: DayLight { DayLight.at(progress) }

    var body: some View {
        GeometryReader { geo in
            let ring = SitLayout.ringDiameter(in: geo.size)
            let ringCentreY = SitLayout.ringCentreY(in: geo.size)

            ZStack {
                ValleyScene(progress: progress)

                // An open-ended sit gets the track and no arc. The arc is a
                // proportion of something, and there is nothing here for it
                // to be a proportion of.
                SitRing(progress: plannedDurationSec == nil ? 0 : progress,
                        track: day.ringTrack)
                    .frame(width: ring, height: ring)
                    .position(x: geo.size.width / 2, y: ringCentreY)

                // The figure scales with its ring so it never crowds the
                // stroke on a small screen.
                Text(timeString(displaySeconds))
                    .font(DisplayFont.display(ring * 0.26, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(day.ink)
                    .position(x: geo.size.width / 2, y: ringCentreY)

                VStack(spacing: 5) {
                    Text(headline)
                        .font(DisplayFont.display(17))
                        .foregroundStyle(day.ink)
                    Text(subhead)
                        .font(AppFont.caption)
                        .foregroundStyle(day.inkSoft)
                    if let planChip, arriving {
                        Text(planChip)
                            .font(AppFont.caption.weight(.bold))
                            .foregroundStyle(AppColor.textOnAccent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(AppColor.accentGold, in: Capsule())
                            .padding(.top, 10)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppMetrics.screenPadding)
                .position(x: geo.size.width / 2, y: SitLayout.headlineY(in: geo.size))
                .opacity(arriving || finishing ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: arriving)
                .animation(.easeInOut(duration: 0.7), value: finishing)

                VStack {
                    Spacer()
                    Button(finishing ? "Done" : "End", action: onEnd)
                        .font(DisplayFont.display(13.5, finishing ? .heavy : .bold))
                        .foregroundStyle(finishing ? day.ink : day.ink.opacity(0.45))
                        .padding(.bottom, 42)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onReceive(clock) { now = $0 }
    }

    private var headline: String {
        finishing ? closingLine : "Let's start meditating"
    }

    private var subhead: String {
        finishing ? "Same time tomorrow?" : "Keep 808 open to ensure you are meditating"
    }

    /// "That's ten minutes." Spelled out because a numeral here would read as
    /// one more measurement, and the sit is over.
    private var closingLine: String {
        guard let planned = plannedDurationSec else { return "That's your sit" }
        let minutes = Int((Double(planned) / 60).rounded())
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
                     "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        guard minutes > 0 else { return "That's your sit" }
        if minutes == 1 { return "That's one minute" }
        let spelled = minutes < words.count ? words[minutes] : String(minutes)
        return "That's \(spelled) minutes"
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The ring the clock lives inside: an empty track that is always there, and
/// a sage arc that closes over the sit.
private struct SitRing: View {
    let progress: Double
    let track: Color

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 1.9)
                .stroke(track, lineWidth: 3.8)
            Circle()
                .inset(by: 1.9)
                .trim(from: 0, to: max(0.0001, progress))
                .stroke(AppColor.calmAccentFill.opacity(0.3 + 0.55 * progress),
                        style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview("Arrive") {
    SessionActiveView(startedAt: Date(), plannedDurationSec: 600,
                      planChip: "10 min · Silence", onEnd: {})
}

#Preview("Mid") {
    SessionActiveView(startedAt: Date().addingTimeInterval(-390),
                      plannedDurationSec: 600, onEnd: {})
}

#Preview("Done") {
    SessionActiveView(startedAt: Date().addingTimeInterval(-600),
                      plannedDurationSec: 600, onEnd: {})
}
