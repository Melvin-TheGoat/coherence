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

/// THE session card, identical on Home and Profile.
///
/// It was a list row until 2026-09-19 (Aziz: "the recent meditations tab just
/// does not look that great, use inspiration from someone else"): a small
/// ring, a title, a run-on subtitle, a chevron. That is the generic iOS list,
/// and it was the most app-shaped thing left in the product.
///
/// **This is Strava's activity card**, and the reason that shape works is not
/// that it is prettier. A list of sessions exists to be COMPARED: you look at
/// it to find out whether this week went better than last. Strava puts
/// Distance, Pace and Time in the same three places on every single card, so
/// the comparison is made by looking down a column instead of by reading two
/// sentences. Ours are Heart settled, Still and Breath.
///
/// A signal that was not read is a dash in its column, never a missing
/// column. A gap would make two sessions stop lining up, which is the one
/// thing this layout is for.
struct EvidenceRow: View {
    let session: Session
    let score: Double?
    /// The measurements themselves, not a pre-built sentence. The card needs
    /// them apart so it can put each one in its own place.
    var stats: MeditationStats? = nil
    var rating: Int? = nil
    /// The photo taken after the sit, when there is one (mockup
    /// `save-session-v7.html`).
    var thumbnail: UIImage? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ScoreBubble(score: score)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SessionListSupport.rowTitle(session))
                        .font(AppFont.callout.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(SessionListSupport.duration(session.durationSec))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                if let rating { RatingChip(rating: rating) }
                if let thumbnail {
                    Color.clear
                        .frame(width: 38, height: 48)
                        .overlay(Image(uiImage: thumbnail).resizable().scaledToFill())
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
            Rectangle().fill(AppColor.hairline)
                .frame(height: 1)
                .padding(.top, 14)
            HStack(spacing: 0) {
                ForEach(SessionListSupport.columns(stats), id: \.label) { column in
                    VStack(spacing: 1) {
                        Text(column.value)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(column.value == "—" ? AppColor.textSecondary
                                                                 : AppColor.calmAccent)
                            .monospacedDigit()
                        Text(column.label)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .fill(AppColor.backgroundSecondary)
                .shadow(color: AppColor.hairline, radius: 0, y: 2)
        )
    }
}

/// The score, as the filled disc at the head of a card.
///
/// A ring was right when the score sat in a row of other thin things. Beside
/// an illustrated sloth a 5pt stroke is the odd one out, and the number inside
/// it was 12pt and unreadable at arm's length. A filled disc is the same
/// object as a sat day in the week strip, which is the point: one shape means
/// "this happened and it scored something".
struct ScoreBubble: View {
    let score: Double?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(score == nil ? AppColor.trace : AppColor.accentGold)
            Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(.system(size: size * 0.37, weight: .bold, design: .rounded))
                .foregroundStyle(score == nil ? AppColor.textSecondary : AppColor.textOnAccent)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
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
        // Six rows are reserved so every month fits, and most months fill
        // five. A whole row of greyed next-month dates is filler, and on Home
        // it is filler directly under the object people actually read, so any
        // trailing week with nothing of this month in it is dropped.
        let grid = SessionCalendar.monthGrid(containing: monthAnchor, calendar: calendar)
            .filter { week in
                week.contains { SessionCalendar.isSameMonth($0, as: monthAnchor, calendar: calendar) }
            }
        let today = calendar.startOfDay(for: Date())
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                // Keyed by position, not by the letter: S and T each appear
                // twice in a week, and duplicate ForEach IDs are undefined
                // behaviour (SwiftUI logs it and may reuse the wrong view).
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
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
                .frame(width: 30, height: 30)
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
        .frame(maxWidth: .infinity, minHeight: tall ? 48 : 36)
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

    /// The three columns on a session card, always three and always in this
    /// order. A signal that was not read is a dash, never an absent column:
    /// see `EvidenceRow` for why the alignment is the whole point.
    static func columns(_ stats: MeditationStats?) -> [(value: String, label: String)] {
        let heart: String = {
            guard let d = stats?.hrDecline, abs(d) >= 1 else { return "—" }
            return String(format: "%+.0f", d)
        }()
        let still: String = {
            guard let s = stats?.stillnessScore else { return "—" }
            return String(format: "%.0f%%", s * 100)
        }()
        let breath: String = {
            guard let r = stats?.meanBreathingRate else { return "—" }
            return String(format: "%.1f", r)
        }()
        return [(heart, "Heart settled"), (still, "Still"), (breath, "Breath")]
    }

    /// One line under a session row: "10 min · heart settled 11 · breath 5.8".
    ///
    /// It read "HR −11" until 2026-09-19, which is a notation, not a sentence.
    /// A signed number needs the reader to know which direction is good before
    /// it says anything, and on a home screen nobody is doing that work. The
    /// words carry the direction instead, so a settling heart and a climbing
    /// one read differently at a glance rather than by their sign.
    static func metricLine(_ session: Session, stats: MeditationStats?) -> String {
        var parts = [duration(session.durationSec)]
        if let d = stats?.hrDecline, abs(d) >= 1 {
            parts.append(d > 0 ? String(format: "heart settled %.0f", d)
                               : String(format: "heart rose %.0f", -d))
        }
        if let r = stats?.meanBreathingRate {
            parts.append(String(format: "breath %.1f a minute", r))
        } else if let s = stats?.stillnessScore {
            parts.append(String(format: "%.0f%% still", s * 100))
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

// MARK: - The week

/// Seven days ending today, as bubbles.
///
/// Home used to carry a whole month (2026-09-19, Aziz: "I think the calendar
/// should be a weekly calendar"). A month is a grid of thirty-five small
/// numbers, and a grid is a spreadsheet however round its corners are: it was
/// the largest object on Home and the least like the rest of the app.
///
/// **Seven days ending TODAY, not the calendar week.** A Sunday-to-Saturday
/// week shows the days that have not happened yet, and on a habit app a row of
/// empty circles for Thursday, Friday and Saturday reads as three days you
/// have already failed. Rolling means today is always the last bubble, the
/// streak is the run of filled ones leading up to it, and nothing on the strip
/// is a promise you have not had the chance to keep.
///
/// The month has not gone anywhere. It lives on Profile, which is where you go
/// when you actually want to look back.
struct WeekStrip: View {
    let practiced: Set<Date>
    /// Start-of-day → that day's photo, when Friends is on. A day with one
    /// shows it inside its bubble.
    var photos: [Date: UIImage] = [:]
    var onDayTap: ((Date) -> Void)? = nil

    private let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0 - 6, to: today)
        }
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                bubble(day, isToday: day == today)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if practiced.contains(day) { onDayTap?(day) } }
            }
        }
    }

    private func bubble(_ day: Date, isToday: Bool) -> some View {
        let done = practiced.contains(day)
        let photo = photos[day]
        return VStack(spacing: 8) {
            Text(letter(day))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? AppColor.textPrimary : AppColor.textSecondary)
            ZStack {
                if let photo {
                    Circle()
                        .fill(AppColor.backgroundPrimary)
                        .overlay(Image(uiImage: photo).resizable().scaledToFill())
                        .clipShape(Circle())
                } else if done {
                    Circle().fill(AppColor.accentGold)
                } else {
                    // An empty day is a shallow well, and it has to be visible
                    // (Aziz, 2026-09-19: "we are gonna need more contrast in
                    // the this week circles"). The first cut filled it with
                    // the PAPER colour, reasoning that a hollow reads as
                    // nothing happened. True on the paper and wrong here: the
                    // strip sits on a white card, so a paper-coloured circle
                    // on white is no circle at all and the row read as seven
                    // floating letters. `trace` is a warm tone deep enough to
                    // be a shape against both grounds.
                    Circle().fill(AppColor.trace)
                }
                if isToday && !done {
                    Circle().stroke(AppColor.calmAccent, lineWidth: 2)
                }
                if done && photo == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(AppColor.textOnAccent)
                }
            }
            .frame(width: 40, height: 40)
        }
    }

    /// One letter, and the day's own initial rather than a fixed S M T W T F S,
    /// because the strip rolls: the leftmost bubble is a different weekday
    /// every day.
    private func letter(_ day: Date) -> String {
        let i = calendar.component(.weekday, from: day) - 1
        return calendar.veryShortWeekdaySymbols[i]
    }
}
