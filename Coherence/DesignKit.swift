import SwiftUI
import SwiftData

/// Shared UI vocabulary for the redesigned screens. One way to show a score,
/// one way to show a session, one calendar — used identically on Home, Journey,
/// and the evidence screen so the whole app reads as a single language.
/// Color grammar (design review, 2026-08): gold = chosen/achieved, teal = the
/// body's signals + guidance. Never both loud in the same element.

// MARK: - Button style

/// What `.buttonStyle(.plain)` should have been: the WHOLE frame is tappable,
/// not just the drawn glyphs and text. Without `contentShape`, the gaps in a
/// card row (between the ring and the title, the empty space before the
/// chevron) fall through and the row feels broken. Also adds the press
/// feedback plain buttons don't give.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Makes a tappable row/card hit-test across its whole frame. Use on the
    /// label of a NavigationLink (which can't take a custom ButtonStyle's
    /// content shape reliably) or anywhere a bare tap gesture is attached.
    func fullyTappable() -> some View { contentShape(Rectangle()) }
}

// MARK: - Score ring

/// Small conic progress ring with the score in the middle (0–1 → 0–100).
struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 38
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(AppColor.textSecondary.opacity(0.15), lineWidth: lineWidth)
            if let score {
                Circle()
                    .trim(from: 0, to: max(0.02, min(score, 1)))
                    .stroke(AppColor.accentGold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(score != nil ? AppColor.textPrimary : AppColor.textSecondary)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Evidence row

/// THE session row — the same everywhere a session is listed (home proof list,
/// Journey log). Ring + when/what + a one-line metric reading.
struct EvidenceRow: View {
    let session: Session
    let score: Double?
    var subtitle: String
    var rating: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            ScoreRing(score: score)
            VStack(alignment: .leading, spacing: 2) {
                Text(SessionListSupport.rowTitle(session))
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            if let rating { RatingChip(rating: rating) }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppColor.accentGoldText)
        }
        .padding(.vertical, 10)
    }
}

/// The user's subjective rating, shown at a glance in list rows.
struct RatingChip: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9))
            Text("\(rating)").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AppColor.backgroundPrimary, in: Capsule())
    }
}

// MARK: - Mode / meta chips

/// Tiny capsule label (session meta on the evidence screen, plan chip mid-session).
struct MetaChip: View {
    let text: String
    var teal = false
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(teal ? AppColor.calmAccent : AppColor.accentGold)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((teal ? AppColor.calmAccent : AppColor.accentGold).opacity(0.14),
                        in: Capsule())
    }
}

// MARK: - Month calendar

/// One month, dotted on practiced days, today ringed in teal. Used on Home
/// (current month, compact) and Journey (browsable, tappable days).
struct MonthCalendar: View {
    let monthAnchor: Date
    let practiced: Set<Date>
    var selectedDay: Date? = nil
    var onDayTap: ((Date) -> Void)? = nil

    private let calendar = Calendar.current

    var body: some View {
        let grid = SessionCalendar.monthGrid(containing: monthAnchor, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                // Keyed by position, not by the letter: S and T each appear
                // twice in a week, and duplicate ForEach IDs are undefined
                // behaviour (SwiftUI logs it and may reuse the wrong view).
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        cell(day, today: today)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if practiced.contains(day) { onDayTap?(day) }
                            }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, today: Date) -> some View {
        let n = calendar.component(.day, from: day)
        let inMonth = SessionCalendar.isSameMonth(day, as: monthAnchor, calendar: calendar)
        let done = practiced.contains(day)
        let isToday = day == today
        let isSelected = selectedDay == day
        return VStack(spacing: 2) {
            Text("\(n)")
                .font(.system(size: 12, weight: isToday || isSelected ? .bold : .regular, design: .rounded))
                .foregroundStyle(inMonth ? AppColor.textPrimary : AppColor.textSecondary.opacity(0.35))
            Circle()
                // Informational, not decorative: at fill-gold it reads 1.78
                // against the card and stops being a signal.
                .fill(done ? AppColor.accentGoldText : .clear)
                .frame(width: 4.5, height: 4.5)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background {
            if isSelected {
                Circle().fill(AppColor.accentGold.opacity(0.18)).frame(width: 30, height: 30).offset(y: -2)
            } else if isToday {
                Circle().stroke(AppColor.calmAccent, lineWidth: 1.4).frame(width: 30, height: 30).offset(y: -2)
            }
        }
    }

    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

// MARK: - Shared row + formatting

/// Small formatting/lookup helpers shared by every list of sessions.
enum SessionListSupport {
    /// overallScore keyed by sessionID (for at-a-glance rings).
    static func scoreMap(_ stats: [MeditationStats]) -> [UUID: Double] {
        var out: [UUID: Double] = [:]
        for s in stats {
            if let sid = s.sessionID, let score = s.overallScore { out[sid] = score }
        }
        return out
    }

    /// Full stats row keyed by sessionID (for metric subtitles).
    static func statsMap(_ stats: [MeditationStats]) -> [UUID: MeditationStats] {
        var out: [UUID: MeditationStats] = [:]
        for s in stats { if let sid = s.sessionID { out[sid] = s } }
        return out
    }

    /// User rating (0–10) keyed by sessionID.
    static func ratingMap(_ reflections: [SessionReflection]) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        for r in reflections {
            if let sid = r.sessionID, let rating = r.rating { out[sid] = rating }
        }
        return out
    }

    /// "Tonight · Belly", "Yesterday · Guided", "Fri, Aug 1 · Rain".
    static func rowTitle(_ session: Session) -> String {
        var what = session.bellyBreathing ? "Belly" : nil
        if let sound = SoundCatalog.title(for: session.frequencyID) {
            what = what.map { "\($0) · \(sound)" } ?? sound
        }
        let when = relativeDay(session.startedAt)
        return what.map { "\(when) · \($0)" } ?? when
    }

    /// One-line metric reading for a row: "10 min · HR −11 · breath 5.8".
    static func metricLine(_ session: Session, stats: MeditationStats?) -> String {
        var parts = [duration(session.durationSec)]
        if let d = stats?.hrDecline, abs(d) >= 1 {
            parts.append(String(format: "HR %+.0f", -d))
        }
        if let r = stats?.meanBreathingRate {
            parts.append(String(format: "breath %.1f", r))
        } else if let s = stats?.stillnessScore {
            parts.append(String(format: "stillness %.2f", s))
        }
        return parts.joined(separator: " · ")
    }

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let hour = cal.component(.hour, from: date)
            return hour >= 17 ? "Tonight" : "Today"
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        f.dateFormat = days < 7 ? "EEE" : "EEE, MMM d"
        return f.string(from: date)
    }

    static func rowTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    static func duration(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60) min" : "\(sec)s"
    }
}
