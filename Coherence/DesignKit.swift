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
/// **Every entry has a picture** (Aziz, 2026-09-19, picking option C out of
/// `mockups/recent-v1.html`): the selfie taken after the sit if there is one,
/// and Otto if there is not. That is Letterboxd's diary, where every entry
/// gets a poster, and it is what turns a log into something worth scrolling.
///
/// The aligned columns from Strava's activity card stay, inside it. A list of
/// sessions exists to be COMPARED, so Heart, Still and Breath sit in the same
/// three places on every card and a signal that was not read is a dash rather
/// than a missing column. Picture on the left, facts on the right, and the
/// columns still line up down the list because the panel is a fixed width.
///
/// The worry when this was drawn was three identical Ottos down one screen.
/// Two things answer it. His pose follows the TIME somebody sat, so an early
/// riser and a night sitter get different cards, and it varies for anyone
/// whose life is not identical every day. And Friends is on in Release as of
/// the social-1.1 merge, so most cards will carry a real face before long.
/// The pose deliberately does NOT follow the score: a mascot pulling a
/// disappointed face at a bad sit is the app judging somebody for showing up.
struct EvidenceRow: View {
    let session: Session
    let score: Double?
    /// The measurements themselves, not a pre-built sentence. The card needs
    /// them apart so it can put each one in its own place.
    var stats: MeditationStats? = nil
    var rating: Int? = nil
    /// The selfie taken after the sit. When it is there it takes the panel.
    var thumbnail: UIImage? = nil

    private var panelWidth: CGFloat { 98 }

    var body: some View {
        HStack(spacing: 0) {
            picture
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SessionListSupport.rowTitle(session))
                            .font(AppFont.callout.weight(.bold))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(SessionListSupport.duration(session.durationSec))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let rating { RatingChip(rating: rating) }
                }
                Rectangle().fill(AppColor.hairline)
                    .frame(height: 1)
                    .padding(.vertical, 11)
                HStack(spacing: 0) {
                    ForEach(SessionListSupport.columns(stats), id: \.label) { column in
                        VStack(spacing: 1) {
                            Text(column.value)
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundStyle(column.value == "—" ? AppColor.textSecondary
                                                                     : AppColor.calmAccent)
                                .monospacedDigit()
                            Text(column.label)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .background(AppColor.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
        .shadow(color: AppColor.hairline, radius: 0, y: 2)
    }

    /// The panel. A photo fills it; Otto sits in it on a wash of the sky.
    private var picture: some View {
        ZStack {
            if let thumbnail {
                Color.clear.overlay(Image(uiImage: thumbnail).resizable().scaledToFill())
            } else {
                AppColor.sky
                // He sits above the score badge rather than behind it: at the
                // first size his crossed legs ran straight through the number.
                OttoMark(size: panelWidth * 0.72, pose: pose)
                    .padding(.bottom, 22)
            }
            // The score rides on the picture so the one gold object per card
            // is also the first thing the eye lands on.
            VStack {
                Spacer()
                HStack {
                    Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(score == nil ? AppColor.textSecondary
                                                      : AppColor.textOnAccent)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(score == nil ? AppColor.trace
                                                                : AppColor.accentGold))
                    Spacer(minLength: 0)
                }
            }
            .padding(7)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .clipped()
    }

    /// Otto follows the clock, not the score. Somebody who sits at dawn and
    /// somebody who sits at midnight get different cards, which is the variety
    /// this panel needs, and neither of them is being told how they did.
    private var pose: OttoPose {
        switch Calendar.current.component(.hour, from: session.startedAt) {
        case ..<11: return .awake
        case 11..<18: return .meditating
        default: return .resting
        }
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
//
// Deleted 2026-09-19. 808 shows a week on Home and a bar per sit on Profile,
// and no month anywhere; see the note in `SessionHistoryView`. `SessionCalendar`
// stays: `practicedDays` still feeds the week strip, and `monthGrid` keeps its
// tests, so the grid can come back without being re-derived.

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
        // The LABEL carries the direction, never a minus sign. A card that
        // says "-12" under the words "Heart settled" is contradicting itself,
        // and it takes a reader who already knows which way the sign points to
        // notice. Seen on a real card, 2026-09-19.
        let heart: (String, String) = {
            guard let d = stats?.hrDecline, abs(d) >= 1 else { return ("—", "Heart settled") }
            return d > 0 ? (String(format: "%.0f", d), "Heart settled")
                         : (String(format: "%.0f", -d), "Heart rose")
        }()
        let still: String = {
            guard let s = stats?.stillnessScore else { return "—" }
            return String(format: "%.0f%%", s * 100)
        }()
        let breath: String = {
            guard let r = stats?.meanBreathingRate else { return "—" }
            return String(format: "%.1f", r)
        }()
        return [(heart.0, heart.1), (still, "Still"), (breath, "Breath")]
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
