import Foundation

/// The lengths the Ready screen's tape offers, and the arithmetic around them
/// (Aziz, 2026-09-22, `mockups/ready-timer.html`, the tape).
///
/// `nil` minutes is Open: the session runs until End, which is what every
/// session was before the timer came back. It sits at the left end of the
/// tape as ∞ so nobody is made to choose a length.
///
/// Pure Foundation, so the rules are tested without a screen.
enum SessionLength {
    /// Open, then every minute to an hour, then the long ones.
    static let values: [Int?] = [nil] + Array(1...60) + [75, 90, 120]

    /// What the tap-to-type field accepts. The same ceiling the old custom
    /// length field had: ten hours.
    static let typedRange = 1...600

    /// The tape position for `minutes`: its own tick, or the nearest one for a
    /// typed length the tape does not carry (100 sits on 90).
    static func nearestIndex(for minutes: Int?) -> Int {
        guard let minutes else { return 0 }
        var best = 1
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            if abs(v - minutes) < abs((values[best] ?? 0) - minutes) { best = i }
        }
        return best
    }

    /// A typed entry, clamped, or nil when it is not a number worth taking.
    /// Zero reads as Open: "0 minutes" is somebody who wants no timer.
    static func typed(_ text: String) -> (minutes: Int?, valid: Bool) {
        let digits = text.filter(\.isNumber)
        guard let n = Int(digits.prefix(4)) else { return (nil, false) }
        if n == 0 { return (nil, true) }
        return (min(max(n, typedRange.lowerBound), typedRange.upperBound), true)
    }

    /// The clock the sit screen will start from: "10:00", "90:00", or ∞.
    static func clock(_ minutes: Int?) -> String {
        guard let minutes else { return "\u{221E}" }
        return "\(minutes):00"
    }

    /// The line under the clock.
    static func words(_ minutes: Int?) -> String {
        guard let minutes else { return "Open, end when you like" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
