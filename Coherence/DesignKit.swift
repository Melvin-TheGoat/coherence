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
                    // Light blue, the colour of a measured number (Melvin,
                    // 2026-09-29). It was gold, then the buttons' green.
                    .stroke(AppColor.measure, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(DisplayFont.display(size * 0.34, .heavy))
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
///
/// **`ReachChip` and the "Friends" / "Only you" chip are gone** (Melvin,
/// 2026-09-27: no more posting, no more feed). A session was never shared or
/// kept back any more finely than the whole account is; marking individual
/// rows with who could see them was a claim about a feature that no longer
/// exists.
///
/// A measured session's score, on the row or on its picture.
private struct ScoreCapsule: View {
    let score: Double?

    var body: some View {
        Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            // Deep blue on the light blue: white on it read at under 3:1.
            .foregroundStyle(score == nil ? AppColor.textSecondary : AppColor.measureInk)
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // Light blue, like the score ring (Melvin, 2026-09-29).
            .background(Capsule().fill(score == nil ? AppColor.trace : AppColor.measure))
    }
}

struct EvidenceRow: View {
    let session: Session
    let score: Double?
    var rating: Int? = nil

    /// The row's own corner, deliberately tighter than the card's
    /// `AppMetrics.cardRadius` it sits inside: a nested plate only reads as
    /// an object ON the card when its corner is smaller than the container's
    /// (the same relationship `.whiteCard()` uses for a card standing on the
    /// grass). Matches `AppMetrics.buttonRadius`.
    private static let plateRadius: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // The puck, not the selfie (Melvin, 2026-09-23: "the photo
            // should not be there, it looks super ugly ... you only see
            // the photo if you tap on it"). A list row is not where a photo
            // is looked at; the session's own page, one tap in, still shows
            // it whole. Shared with Profile's week list so the two read as
            // one visual language.
            MinutesPuck(durationSec: session.durationSec)
            // No measurement columns (Melvin, 2026-09-23: "it should not
            // show 'heart settled' and 'still' in the recent tab on home,
            // clutters everything too much"). A row is its length, its
            // title and its day; the measurements, when a Watch took any,
            // are one tap in, on the session's own page. And no "10 min"
            // under the title either: the puck already says it, and a row
            // that states its length twice is the same clutter.
            VStack(alignment: .leading, spacing: 4) {
                Text(SessionListSupport.rowTitle(session))
                    .font(DisplayFont.display(16))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !session.isPhoneOnly, score != nil {
                ScoreCapsule(score: score)
            }
            if let rating { RatingChip(rating: rating) }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        // A surface of its own, not the card's sand (Melvin, 2026-09-27: "in
        // the home tab, in the 'recent' part, its buttons are like not
        // distinguishable from the background, its like the same gray
        // color"). Home's "Recent" card (`ContentView.proofSection`) is
        // `.card()`, which fills with `backgroundSecondary` sand through this
        // same `TileFill` — so a row filled the identical way was invisible
        // against the card holding it. `backgroundPrimary`, the app's
        // lighter cream paper, is the plate instead, still routed through
        // `TileFill` so it dims exactly like every other tile at night
        // (`tileDim`; "never fill a tile with `.white`, draw it through
        // `TileFill`"). This is scoped to `EvidenceRow` itself rather than a
        // parameter every call site would carry: the view has exactly one
        // call site left (Home's Recent card — grep confirms it; Profile's
        // week log draws its own bare `MinutesRow` on a hairline instead), so
        // there is no other screen a param would need to reach, and a plain
        // Button already dims this whole row on press (`CardButtonStyle`).
        .background(TileFill(shape: RoundedRectangle(cornerRadius: Self.plateRadius, style: .continuous),
                              color: AppColor.backgroundPrimary))
        .clipShape(RoundedRectangle(cornerRadius: Self.plateRadius, style: .continuous))
        // The same soft lift `.whiteCard()` gives a card standing on the
        // grass: this row needs an equivalent lift standing on the card.
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
    }
}

/// A session's length, in a small amber puck — the one fact any session,
/// phone or Watch, can report. Shared between Home's evidence rows and
/// Profile's week list so the two lists read as one visual language
/// (Melvin, 2026-09-23: replaces the photo that used to sit here — "you
/// only see the photo if you tap on it").
///
/// **Soft amber, never the accent gold**: a puck on every row down a page
/// would spend the one-gold-per-section rule on every row and leave nothing
/// on the screen emphasised. A tint is a material; the accent is a decision.
struct MinutesPuck: View {
    let durationSec: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("\(max(1, durationSec / 60))")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text("MIN")
                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .opacity(0.75)
        }
        // Light blue, the colour of a measured number (Melvin, 2026-09-29).
        .foregroundStyle(AppColor.measureInk)
        .frame(width: 44, height: 44)
        .background(AppColor.measure.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(DisplayFont.display(size * 0.38, .heavy))
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
            SitArt(name: "home-rating", size: 13)
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

/// Seven days ending today, as a garden: a plant per day, in full flower from
/// the FIRST session and one more bloom per session after that
/// (`mockups/session-view.html`, section 2, option C). Cairns (option A)
/// shipped first on 2026-09-27; Melvin swapped them for the plants the next
/// day ("with the little plants, I like that more actually"). Either way it
/// replaced a single gold tick or photo per day, which could only ever say
/// WHETHER you sat, never how many times. **Most people only meditate once a
/// day** (Melvin, 2026-09-28), so a single session earning only a bare sprout
/// undersold it; a session now earns the whole plant, and it is EXTRA
/// sessions that show up, as extra blooms fanned off the same stem.
///
/// Home used to carry a whole month (2026-09-19, Aziz: "I think the calendar
/// should be a weekly calendar"). A month is a grid of thirty-five small
/// numbers, and a grid is a spreadsheet however round its corners are: it was
/// the largest object on Home and the least like the rest of the app.
///
/// **Seven days ending TODAY, not the calendar week.** A Sunday-to-Saturday
/// week shows the days that have not happened yet, and on a habit app a row of
/// empty circles for Thursday, Friday and Saturday reads as three days you
/// have already failed. Rolling means today is always the last cairn, the
/// streak is the run of filled ones leading up to it, and nothing on the strip
/// is a promise you have not had the chance to keep.
///
/// The month has not gone anywhere. It lives on Profile, which is where you go
/// when you actually want to look back.
struct WeekStrip: View {
    let days: [WeekCairns.Day]
    /// Start-of-day → that day's photo. **Unused** since the cairns replaced
    /// a photo-per-day (Melvin, 2026-09-27: a stack of stones says how many
    /// times, a single photo could only ever say whether). Kept, defaulted,
    /// so a caller built against the old signature still compiles.
    var photos: [Date: UIImage] = [:]
    var onDayTap: ((Date) -> Void)? = nil

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.date) { day in
                plant(day)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if day.sessionCount > 0 { onDayTap?(day.date) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(day))
                    .accessibilityAddTraits(day.sessionCount > 0 ? .isButton : [])
            }
        }
    }

    /// A day is a plant (option C of `mockups/session-view.html`, Melvin,
    /// 2026-09-28: "change it to plan C, with the little plants"): bare soil
    /// on a day not sat, a full flowering plant from the FIRST session, and
    /// one more bloom fanned off the same stem for every session after that,
    /// capped so the count always reads as "one plant", never a crowd. The
    /// rest day the streak forgave is a leaf fallen on the soil, never a
    /// plant, because it was bridged, not practised.
    private func plant(_ day: WeekCairns.Day) -> some View {
        VStack(spacing: 8) {
            Text(letter(day.date))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(day.isToday ? AppColor.textPrimary : AppColor.textSecondary)
            ZStack(alignment: .bottom) {
                // An empty today is still waiting on you, and it has to be
                // visible (Aziz, 2026-09-19: "we are gonna need more
                // contrast"): a dashed sage ring round its patch of soil.
                if day.isToday && day.sessionCount == 0 {
                    Circle()
                        .strokeBorder(AppColor.calmAccent,
                                     style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 32, height: 32)
                        .offset(y: 2)
                }
                Canvas { ctx, size in
                    Self.draw(day, in: &ctx, size: size)
                }
                .frame(width: 40, height: 64)
            }
            .frame(height: 64, alignment: .bottom)
        }
    }

    /// Capped so a very active day still reads as "a full plant", never a
    /// crowd of overlapping petals in a 40pt column (Melvin, 2026-09-28:
    /// "add multiple flowers under one day for however many times they
    /// meditated" — this is the ceiling on "however many").
    private static let maxBlooms = 3

    /// Soil, then a mature plant, drawn a fifth larger (`k`) so it still reads
    /// at arm's length: a stem, two leaves, a flower on top from the FIRST
    /// session — no more waiting for a third. Each session after that fans a
    /// smaller bloom off the same stem, alternating sides, up to `maxBlooms`.
    private static func draw(_ day: WeekCairns.Day, in ctx: inout GraphicsContext, size: CGSize) {
        let k: CGFloat = 1.2
        let cx = size.width / 2
        let ground = size.height - 4
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 13 * k, y: ground - 3.5 * k, width: 26 * k, height: 7 * k)),
                 with: .color(AppColor.textSecondary.opacity(0.32)))

        let leafInk = AppColor.meadowInk.opacity(0.78)
        guard day.sessionCount > 0 else {
            if day.isRestDay {
                var leaf = Path()
                leaf.move(to: CGPoint(x: cx - 5 * k, y: ground - 1))
                leaf.addQuadCurve(to: CGPoint(x: cx + 6 * k, y: ground - 5 * k),
                                  control: CGPoint(x: cx, y: ground - 13 * k))
                leaf.addQuadCurve(to: CGPoint(x: cx - 5 * k, y: ground - 1),
                                  control: CGPoint(x: cx, y: ground - 4 * k))
                ctx.fill(leaf, with: .color(leafInk))
            }
            return
        }

        // The plant itself no longer scales with the count: one session
        // already earns the mature stem, both leaves, and the main bloom.
        let height = CGFloat(4 + 12 * 3) * k
        let top = ground - 2 - height
        var stem = Path()
        stem.move(to: CGPoint(x: cx, y: ground - 2))
        stem.addCurve(to: CGPoint(x: cx, y: top),
                      control1: CGPoint(x: cx - 1.5, y: ground - 2 - height * 0.35),
                      control2: CGPoint(x: cx + 1.5, y: ground - 2 - height * 0.7))
        ctx.stroke(stem, with: .color(AppColor.meadowInk),
                   style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))

        for i in 0..<2 {
            let y = ground - (8 + CGFloat(12 * i)) * k
            let side: CGFloat = (i.isMultiple(of: 2) ? -1 : 1) * k
            var leaf = Path()
            leaf.move(to: CGPoint(x: cx, y: y))
            leaf.addQuadCurve(to: CGPoint(x: cx + side * 14, y: y - 2 * k),
                              control: CGPoint(x: cx + side * 9, y: y - 7 * k))
            leaf.addQuadCurve(to: CGPoint(x: cx, y: y),
                              control: CGPoint(x: cx + side * 7, y: y + 4 * k))
            ctx.fill(leaf, with: .color(leafInk))
        }

        Self.bloom(at: CGPoint(x: cx, y: top), in: &ctx, k: k,
                   petal: AppColor.streakBlush, dot: AppColor.accentGold, scale: 1)

        // One bloom per session after the first, fanned off the main stem
        // at a shared branch point so the count is read at a glance rather
        // than counted. Only the centre dot stays gold — that reads as the
        // one achieved thing on the plant, so it never repeats.
        let extra = min(day.sessionCount, Self.maxBlooms) - 1
        guard extra > 0 else { return }
        let branchOrigin = CGPoint(x: cx, y: ground - 2 - height * 0.6)
        let angles: [Double] = extra == 1 ? [18] : [-18, 18]
        let petals: [Color] = [AppColor.streakBlush.opacity(0.75), AppColor.calmAccent.opacity(0.6)]
        for (index, degrees) in angles.enumerated() {
            let radians = degrees * .pi / 180
            let radius: CGFloat = 17 * k
            let bloomCenter = CGPoint(x: branchOrigin.x + radius * sin(radians),
                                      y: branchOrigin.y - radius * cos(radians))
            var branch = Path()
            branch.move(to: branchOrigin)
            branch.addQuadCurve(to: bloomCenter,
                                control: CGPoint(x: (branchOrigin.x + bloomCenter.x) / 2,
                                                 y: branchOrigin.y - radius * 0.5))
            ctx.stroke(branch, with: .color(AppColor.meadowInk),
                       style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round))
            Self.bloom(at: bloomCenter, in: &ctx, k: k,
                       petal: petals[index % petals.count],
                       dot: AppColor.meadowInk.opacity(0.55), scale: 0.78)
        }
    }

    /// Five petals ringed round a centre dot, the same shape at every size:
    /// `scale` shrinks a branched bloom so it reads as a smaller flower off
    /// the same plant, never a second identical one.
    private static func bloom(at point: CGPoint, in ctx: inout GraphicsContext, k: CGFloat,
                              petal: Color, dot: Color, scale: CGFloat) {
        let offset = 3.4 * k * scale
        let petalSize = 6.6 * k * scale
        for i in 0..<5 {
            let a = Double(i) / 5 * 2 * .pi - .pi / 2
            let p = CGPoint(x: point.x + offset * cos(a), y: point.y + offset * sin(a))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - petalSize / 2, y: p.y - petalSize / 2,
                                            width: petalSize, height: petalSize)),
                     with: .color(petal))
        }
        let dotSize = 5 * k * scale
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2,
                                        width: dotSize, height: dotSize)),
                 with: .color(dot))
    }

    private func accessibilityLabel(_ day: WeekCairns.Day) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide))
        switch day.sessionCount {
        case 0: return day.isRestDay ? "\(name), rest day" : name
        case 1: return "\(name), 1 session"
        default: return "\(name), \(day.sessionCount) sessions"
        }
    }

    /// One letter, and the day's own initial rather than a fixed S M T W T F S,
    /// because the strip rolls: the leftmost cairn is a different weekday
    /// every day.
    private func letter(_ day: Date) -> String {
        let i = calendar.component(.weekday, from: day) - 1
        return calendar.veryShortWeekdaySymbols[i]
    }
}

/// The ground of the valley pages (Profile, the guide, Friends): the meadow a
/// page continues under its band of sky, the sky's own ink for type drawn on
/// it, and the divider to use inside a white card. Not the app's `hairline`,
/// which is cream and on white reads as the brown these pages moved off.
enum ValleyGround {
    // The grass follows the hour, like Home (Melvin, 2026-09-27: every
    // screen matches the time of day).
    static var meadow: Color { DayLight.now.field[1] }
    /// Daytime ink, for words on a cream surface (the tab bar, pills, cards),
    /// which stays cream at every hour.
    static let ink = DayLight.at(0).ink
    static let inkSoft = DayLight.at(0).inkSoft
    /// The sky's ink at this hour, for words drawn straight on the sky: dark
    /// by day, pale at night.
    static var skyInk: Color { DayLight.now.ink }
    static var skyInkSoft: Color { DayLight.now.inkSoft }
    static let quiet = AppColor.meadowInk.opacity(0.11)
}

extension View {
    /// Where a band of valley meets the flat grass of the page under it, the
    /// flowers and tufts fade into that grass instead of stopping on a line
    /// (Melvin, 2026-09-27: "right now theres this like hard cut off, it
    /// looks weird"). A gradient of the page's own green over the band's
    /// bottom `share` of its height, so the ground's darker near edge lands
    /// exactly on the page colour as well.
    ///
    /// Put it on the scene itself, never on a stack that also holds Otto or
    /// a control: it paints over whatever is under it.
    func fadesIntoMeadow(_ meadow: Color = ValleyGround.meadow, share: CGFloat = 0.2) -> some View {
        overlay {
            GeometryReader { geo in
                // Smoothstep, then held solid for the last few points, so the
                // fade has no visible start and no visible end.
                LinearGradient(stops: [
                    .init(color: meadow.opacity(0), location: 0),
                    .init(color: meadow.opacity(0.10), location: 0.18),
                    .init(color: meadow.opacity(0.35), location: 0.37),
                    .init(color: meadow.opacity(0.65), location: 0.55),
                    .init(color: meadow.opacity(0.90), location: 0.74),
                    .init(color: meadow, location: 0.9),
                    .init(color: meadow, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: geo.size.height * share)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Otto's bubble over the valley (Melvin, 2026-09-26: "the text should be
/// centered, and i want it more transparent"): see-through glass with its
/// words centred, where it used to be a cream card.
///
/// By day it is cream glass under the day's dark ink. **A valley that
/// follows the clock (Home) turns it to dark glass under the night's pale
/// ink once the sky is dark**, because dark words on a see-through bubble
/// over a night sky cannot be read. The switch is at 0.55 of the valley's
/// day, where both looks read at about 4.5:1 against the sky behind them.
enum ValleyBubble {
    /// The day's glass.
    static let dayGlass = AppColor.backgroundPrimary.opacity(0.42)

    /// The glass for a valley drawn at this hour, which every app screen is.
    static var now: (ink: Color, stroke: Color, fill: Color) { look(at: DayLight.clockProgress()) }

    /// Ink, outline and fill for a valley at `progress` (0 full day, 1 night).
    static func look(at progress: Double) -> (ink: Color, stroke: Color, fill: Color) {
        if progress < 0.55 {
            let ink = DayLight.at(0).ink
            return (ink, ink.opacity(0.38), dayGlass)
        }
        let ink = DayLight.at(1).ink
        return (ink, ink.opacity(0.42), Color.black.opacity(0.14))
    }
}

/// A section title standing on the grass: white, with a faint shadow so it
/// survives the flowers.
struct GrassHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DisplayFont.display(15, .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

extension View {
    /// A card standing on the grass: the valley pages' one surface. Sand, not
    /// white, since 2026-09-26; the name stayed so the call sites did too.
    func whiteCard(radius: CGFloat = 20) -> some View {
        background(TileFill(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
            .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
    }
}
