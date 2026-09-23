import Foundation

/// The lengths the Ready screen's tape offers, and the arithmetic around them
/// (Aziz, 2026-09-22, `mockups/ready-timer.html`, the tape).
///
/// `nil` minutes is Open: the session runs until End, which is what every
/// session was before the timer came back. It sits at the left end of the
/// tape as ∞ so nobody is made to choose a length.
///
/// **Five minutes is the shortest timed session** (Aziz, 2026-09-22): the
/// tape runs ∞, 5, 6, 7..., so sliding left past 5 lands on ∞. Five is also
/// what opens Block's held apps (`Blocker.sessionMinutes`), so a timed sit
/// always counts.
///
/// Pure Foundation, so the rules are tested without a screen.
enum SessionLength {
    static let shortest = 5

    /// Open, then every minute from five to two hours. **Evenly, all the
    /// way**: it used to jump 60, 75, 90, 120 on consecutive ticks, and four
    /// labels one tick apart piled into "60759012O". Longer than two hours is
    /// typed.
    static let values: [Int?] = [nil] + Array(shortest...120)

    /// What the tap-to-type field accepts: five minutes to the ten hours the
    /// old custom length field allowed.
    static let typedRange = shortest...600

    /// A stored or typed length brought into range: under five becomes five,
    /// Open stays Open. A default saved before the floor (a 2 minute one)
    /// reads as 5.
    static func clamped(_ minutes: Int?) -> Int? {
        minutes.map { min(max($0, typedRange.lowerBound), typedRange.upperBound) }
    }

    /// The tape position for `minutes`: its own tick, or the nearest one for a
    /// typed length the tape does not carry (a typed 300 sits on 120).
    static func nearestIndex(for minutes: Int?) -> Int {
        guard let minutes else { return 0 }
        var best = 1   // the first timed tick
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            if abs(v - minutes) < abs((values[best] ?? 0) - minutes) { best = i }
        }
        return best
    }

    /// A typed entry, clamped, or nil when it is not a number worth taking.
    /// Zero reads as Open: "0 minutes" is somebody who wants no timer.
    /// Anything from 1 to 4 becomes 5.
    static func typed(_ text: String) -> (minutes: Int?, valid: Bool) {
        let digits = text.filter(\.isNumber)
        guard let n = Int(digits.prefix(4)) else { return (nil, false) }
        if n == 0 { return (nil, true) }
        return (clamped(n), true)
    }

    /// The clock the sit screen will start from: "10:00", "90:00", or ∞.
    static func clock(_ minutes: Int?) -> String {
        guard let minutes else { return "\u{221E}" }
        return "\(minutes):00"
    }

    /// The end-of-session notification's title: "That's 10 minutes".
    static func endTitle(minutes: Int) -> String {
        if minutes == 60 { return "That's an hour" }
        return minutes == 1 ? "That's 1 minute" : "That's \(minutes) minutes"
    }

    /// The line under the clock.
    static func words(_ minutes: Int?) -> String {
        guard let minutes else { return "Open, end when you like" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
