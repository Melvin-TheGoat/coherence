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
    var size: CGFloat = 42
    var lineWidth: CGFloat = 5

    var body: some View {
        // Inset by half the stroke: a stroke sits centred on the path, so
        // without this the outer half fell outside the frame and any clipping
        // parent cut the ring flat on one side (2026-09-14, sample session).
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                // The unfilled part of the ring is warm paper, not grey. A
                // neutral track under an amber arc is what made the ring read
                // as a gauge rather than as a thing you earned.
                .stroke(AppColor.hairline, lineWidth: lineWidth)
            if let score {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: max(0.02, min(score, 1)))
                    .stroke(AppColor.accentGold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
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
    /// The photo taken after the sit, when there is one (mockup
    /// `save-session-v7.html`). Portrait, small, before the chevron; a row
    /// without one is exactly the row it always was.
    var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            ScoreRing(score: score)
            VStack(alignment: .leading, spacing: 3) {
                Text(SessionListSupport.rowTitle(session))
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            if let rating { RatingChip(rating: rating) }
            if let thumbnail {
                Color.clear
                    .frame(width: 32, height: 42)
                    .overlay(Image(uiImage: thumbnail).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppColor.accentGoldText)
        }
        .padding(.vertical, 13)
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
    /// Start-of-day → the photo taken after that day's sit (the latest one).
    /// A day with a photo shows it where the dot was; a day without keeps
    /// its dot. The month becomes a strip of your own face, which says
    /// "look how much you sat" better than twelve gold dots
    /// (mockup `save-session-v7.html`, Aziz 2026-09-15). Declared before
    /// `onDayTap` so the trailing-closure call sites keep working.
    var photos: [Date: UIImage] = [:]
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
        let photo = photos[day]
        // Rows grow only in a month that has a photo in it, so a calendar
        // with none is pixel-identical to the one that shipped.
        let tall = !photos.isEmpty
        return VStack(spacing: tall ? 3 : 2) {
            // A practised day is a filled amber chip with the date inside it,
            // not a number with a 4.5pt dot underneath (2026-09-19). The dot
            // was correct and unreadable: it carried the single most-looked-at
            // fact on Home in four and a half points of gold. A filled day is
            // legible at a glance, is the same object as the score ring's
            // fill, and turns the month into something that visibly fills up.
            Text("\(n)")
                .font(.system(size: 13,
                              weight: done || isToday || isSelected ? .bold : .regular,
                              design: .rounded))
                .foregroundStyle(dayInk(done: done, inMonth: inMonth, photo: photo != nil))
                .frame(width: 27, height: 27)
                .background {
                    if done && photo == nil {
                        Circle().fill(AppColor.accentGold)
                    }
                }
            if let photo {
                Color.clear
                    .frame(width: 24, height: 26)
                    .overlay(Image(uiImage: photo).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if tall {
                // Holds the row's height so a month with photos in it keeps
                // every number on the same line.
                Color.clear.frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, minHeight: tall ? 46 : 32)
        // The ring marks the DATE, so it hangs off the top of the cell rather
        // than its centre. Centred, a photo day's taller cell dragged the ring
        // down over the picture (seen on the simulator, 2026-09-16).
        .background(alignment: tall ? .top : .center) {
            let y: CGFloat = tall ? -3 : -2
            if isSelected {
                Circle().stroke(AppColor.textPrimary, lineWidth: 2)
                    .frame(width: 31, height: 31).offset(y: y)
            } else if isToday && !done {
                Circle().stroke(AppColor.calmAccent, lineWidth: 1.6)
                    .frame(width: 29, height: 29).offset(y: y)
            }
        }
    }

    /// The date's own colour. On a filled day it has to be the label colour or
    /// it disappears into the amber.
    private func dayInk(done: Bool, inMonth: Bool, photo: Bool) -> Color {
        if done && !photo { return AppColor.textOnAccent }
        if !inMonth { return AppColor.textSecondary.opacity(0.35) }
        return AppColor.textPrimary
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

    /// "Yesterday · Manifest", "Fri, Aug 1 · Rain".
    static func rowTitle(_ session: Session) -> String {
        // bellyBreathing is still stored (dropping stored properties is a
        // migration hazard) but the MODE is cut, so the label would name a
        // feature that no longer exists. Old belly-era rows read like any
        // other session now.
        var what: String? = nil
        if let sound = SoundCatalog.title(for: session.frequencyID) {
            what = sound
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
