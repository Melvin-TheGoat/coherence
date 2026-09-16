import Foundation

/// Everything Otto knows, written by rules before the model reads a word.
///
/// Otto is the data interpreter (BACKLOG.md): a chat about the person's own
/// sessions that speaks in "the data suggests", never a diagnosis. It runs
/// on Apple's on-device model, so the whole brief below, numbers included,
/// stays on the phone. This file is pure Foundation on purpose: the prompt
/// can be read, budgeted and tested without a model or a store.
///
/// **What the model is told about 808 comes from here, not from its
/// training.** The score rules, the voice rules, the guide's techniques and
/// the person's last sessions are all supplied as instructions. Anything the
/// model might "know" about meditation apps is irrelevant; anything it says
/// about the score must trace to a sentence in this file.
enum OttoBrief {

    // MARK: - The person's sessions

    /// One session as Otto reads it. Plain values, no SwiftData, so the brief
    /// is testable without a container. Built from `Session`,
    /// `MeditationStats` and `SessionReflection` by `OttoLoader`.
    struct SessionRow: Equatable {
        var date: Date
        var minutes: Int
        /// 0 to 1, as stored. Printed to the model as 0 to 100.
        var overallScore: Double?
        var startHR: Double?
        var endHR: Double?
        var meanHR: Double?
        var stillnessScore: Double?
        var doorwayRate: Double?
        var doorwayHeldSec: Double?
        var technique: String?
        var sound: String?
        var rating: Int?
        /// The score's working, from the engine, so the card below is
        /// arithmetic the app did and the model only reads.
        var breakdown: SignalEngine.ScoreBreakdown?

        init(date: Date, minutes: Int, overallScore: Double? = nil,
             startHR: Double? = nil, endHR: Double? = nil, meanHR: Double? = nil,
             stillnessScore: Double? = nil, doorwayRate: Double? = nil,
             doorwayHeldSec: Double? = nil, technique: String? = nil,
             sound: String? = nil, rating: Int? = nil,
             breakdown: SignalEngine.ScoreBreakdown? = nil) {
            self.date = date
            self.minutes = minutes
            self.overallScore = overallScore
            self.startHR = startHR
            self.endHR = endHR
            self.meanHR = meanHR
            self.stillnessScore = stillnessScore
            self.doorwayRate = doorwayRate
            self.doorwayHeldSec = doorwayHeldSec
            self.technique = technique
            self.sound = sound
            self.rating = rating
            self.breakdown = breakdown
        }

        /// Positive = the heart settled, matching `MeditationStats.hrDecline`.
        var hrDecline: Double? {
            guard let startHR, let endHR else { return nil }
            return startHR - endHR
        }

        var score100: Int? { overallScore.map { Int(($0 * 100).rounded()) } }

        /// The same depth scored under the 10-minute ceiling, for sits shorter
        /// than ten minutes. Nil at or past ten minutes (the ceiling is already
        /// reached) or with no score. Depth is the score over its time factor;
        /// at ten minutes the factor is exactly 1.0.
        var scoreAtTenMinutes: Int? {
            guard minutes < 10, let score = overallScore else { return nil }
            let factor = SignalEngine.durationFactor(seconds: minutes * 60)
            guard factor > 0 else { return nil }
            return Int((min(1, score / factor) * 100).rounded())
        }
    }

    // MARK: - Budget

    /// The on-device model's context is about 4,096 tokens for instructions,
    /// the conversation and the reply together. Roughly four characters to a
    /// token, so this keeps the standing brief near 2,000 tokens (the score
    /// card for the session in focus is about 450 of them) and leaves the
    /// rest for the chat; a chat that outgrows it restarts on the same brief.
    static let characterBudget = 8_000
    /// Sessions listed for the model, newest first. Ten is enough to talk
    /// about a trend and few enough to fit.
    static let maxSessions = 10

    // MARK: - Instructions

    /// The whole system prompt: who Otto is, how it speaks, how the score is
    /// built, what advice it may give, and the person's sessions.
    ///
    /// - Parameter focus: the session the chat was opened from, if any. It is
    ///   marked in the table so "this session" means what the person means.
    static func instructions(sessions: [SessionRow], focus: SessionRow?, now: Date = Date()) -> String {
        // The opening line is NOT quoted here. The first build told the model
        // "you already opened the chat by saying: ..." and the on-device model
        // answered the first question by repeating that line word for word
        // (simulator, 2026-09-15). The opening is UI; the model only needs
        // the table, where the session in focus is marked.
        var parts: [String] = [identity, voiceRules, scoreRules, practiceRules,
                               "THIS PERSON'S SESSIONS, newest first. \"This session\" means the one marked (in focus); the person is looking at its score and curves on the screen behind this chat. Points are heart + stillness + breath, already scaled to the sit's length.",
                               table(sessions, focus: focus, now: now)]
        if let focus, let card = scoreCard(focus) { parts.append(card) }
        var text = parts.joined(separator: "\n\n")
        // The fixed text is well under budget; only a pathological table
        // could push it over, and if it does the oldest rows go first.
        var rows = sessions
        while text.count > characterBudget, rows.count > 1 {
            rows.removeLast()
            parts[5] = table(rows, focus: focus, now: now)
            text = parts.joined(separator: "\n\n")
        }

        return text
    }

    static let identity = """
    You are Otto, the data interpreter inside 808, a meditation app for iPhone and Apple Watch. \
    You are talking with the person whose sessions are listed below. Everything in this \
    conversation stays on their phone.
    """

    static let voiceRules = """
    VOICE
    - Warm, plain, specific. Two to five short sentences unless asked for more. No bullet lists unless asked. Never use an em dash.
    - Answer the question that was asked, in your own words, and explain the why behind it. Never repeat a session summary word for word.
    - Say "the data suggests" or "your numbers show". Describe what was measured; never tell the person what they are or what they lack.
    - Use only the numbers in the table. If something was not read, say it was not read. Never invent a number, a trend, or a session.
    - 808 reads wrist motion and an averaged heart rate from the Watch. It cannot read brainwaves, theta, HRV, or any health outcome, and you never state those about the person.
    - No diagnosis, no medical advice, nothing about a condition, a symptom, medication, or whether something is safe. If asked, reply with exactly: "\(declineLine)"
    - Sessions compare only with this person's own history, never with other people.
    - A weak session gets honest, practical coaching, never shame. Showing up counts.
    """

    static let scoreRules = """
    HOW THE 808 SCORE WORKS (0 to 100). In the app's words: how deep you got, and how long you held it.
    - Depth mixes heart 50%, stillness 30%, breath 20%. When no breath doorway was read, depth is heart 60% and stillness 40%; an unread breath never subtracts.
    - Heart, half the score: 60% for holding at or below the opening heart rate through the sit, 40% for the size of the drop. A calm start with little room to fall can still score well.
    - Stillness: how little the wrist moved, measured the whole sit, cubed in the score so the top of the range matters most. Real sits run about 0.80 to 0.98.
    - Breath doorway: at least 60 seconds of deliberate slow breathing at 9 per minute or slower (slow, even breaths; never holding the breath), starting in the first 5 minutes. All or nothing: a doorway earns the full breath credit. Starting within the first 90 seconds counts on its own; starting between 90 seconds and 5 minutes needs a very clear read; after 5 minutes nothing counts. Quiet natural breathing is often too small to read from the wrist, which is normal.
    - Time is a ceiling, never a bonus for its own sake: under 10 minutes the cap is 50 plus 5 per minute (5 minutes caps at 75, 10 minutes at 100). Past 10 minutes a small bonus, up to 8% at 40 minutes, multiplies depth. Thirty restless minutes never beat five settled ones.
    - NEVER do arithmetic on the score. Every session line carries its points already worked out by the app ("heart 12 of 45"), and the session in focus has a SCORE CARD below with each line of the working. Quote those lines. Never add percentages, never multiply weights, never say what a score "would have been" beyond the two hypotheticals the app computes for you: "at 10 min the same sit would score N" and "with a breath doorway it would score N". If a line has no such number, say the app does not estimate that. A longer sit only raises the ceiling; it does not change how deep the sit was.
    - Stillness is a fraction of 1: how still the wrist was over the whole sit, where 1.00 is not moving at all and settled sits read 0.80 to 0.98.
    - The opening heart rate is the first reading of the sit, printed on the card.
    - Always explain the why in plain words: a heart rate that climbs means the body did not settle during the sit; movement means the body was not at rest; a doorway is the on-ramp into the settled state, which is why it is scored. Then say what to do about it, from the coaching line.
    - What a score means: under 40 is a restless or short sit; 40 to 69 is a sit that settled; 70 and up is deep and held. Each session line names its band; quote it, never invent another scale.
    - Comparing two sessions: name what changed (length, heart, stillness, doorway) in at most four sentences, using the points on each line.
    - The rating out of 10 is the person's own feeling afterwards. It is not part of the score.
    """

    static var practiceRules: String {
        let methods = MeditationMethod.all.map { "\($0.title) (\($0.level.label.lowercased())): \($0.oneLine)" }
        return """
        PRACTICE ADVICE YOU MAY GIVE
        - Open the sit with a minute or two of slow breathing, around 4 to 7 breaths a minute, then let the breath go natural. That is the doorway, and it is what the Watch reads best.
        - Sit or lie comfortably, straight back, undisturbed. Ten to twenty minutes is plenty. Consistency beats length.
        - The mind will wander. Returning is the practice, gently and without judgement.
        - Techniques in the 808 guide (the Guide tab has the steps): \(methods.joined(separator: " "))
        """
    }

    // MARK: - The table

    static func table(_ sessions: [SessionRow], focus: SessionRow?, now: Date = Date()) -> String {
        guard !sessions.isEmpty else {
            return "No sessions yet. Say so if asked about their numbers, and help them start."
        }
        return sessions.prefix(maxSessions).enumerated().map { i, row in
            "\(i + 1). " + line(row, focus: focus == row, now: now)
        }.joined(separator: "\n")
    }

    /// One session on one line. Absences are named ("heart not read") so the
    /// model has a sentence to repeat instead of a gap to fill.
    static func line(_ r: SessionRow, focus: Bool, now: Date) -> String {
        var parts: [String] = [when(r.date, now: now) + (focus ? " (in focus)" : ""),
                               "\(r.minutes) min"]
        parts.append(r.score100.map { "score \($0), \(band($0))" } ?? "no score")
        if let b = r.breakdown { parts.append(points(b)) }
        // The one hypothetical Otto may quote, computed here so the model
        // never does arithmetic: the same depth under the 10-minute ceiling.
        // Otto once told Melvin a 5-minute sit "would have scored 100 at 10
        // minutes"; the true number was the score over its time factor.
        if let at10 = r.scoreAtTenMinutes { parts.append("at 10 min the same sit would score \(at10)") }
        if let s = r.startHR, let e = r.endHR {
            var heart = "heart \(Int(s.rounded())) to \(Int(e.rounded())) bpm"
            if let m = r.meanHR, m > 0 { heart += ", avg \(Int(m.rounded()))" }
            parts.append(heart)
        } else {
            parts.append("heart not read")
        }
        parts.append(r.stillnessScore.map { String(format: "stillness %.2f", $0) } ?? "stillness not read")
        if let rate = r.doorwayRate {
            let held = r.doorwayHeldSec.map { " kept up for \(mmss($0))" } ?? ""
            parts.append(String(format: "slow-breath doorway %.1f/min", rate) + held)
        } else {
            parts.append("no doorway")
        }
        if let t = r.technique, !t.isEmpty { parts.append(t.lowercased()) }
        if let s = r.sound, !s.isEmpty { parts.append("sound \(s)") }
        if let rating = r.rating { parts.append("rated \(rating)/10") }
        return parts.joined(separator: " · ")
    }

    /// The band a score sits in, written here because the model cannot be
    /// trusted to place 13 under 40 (it called it "deep and held" once).
    static func band(_ score: Int) -> String {
        score < 40 ? "a restless or short sit" : score < 70 ? "a sit that settled" : "deep and held"
    }

    // MARK: - The score card

    /// The points each term earned, scaled to the sit's length so the three
    /// add up to the score on the ring. "heart 1 of 45 · stillness 13 of 30".
    /// Written by rules from `ScoreBreakdown`; the model copies it.
    static func points(_ b: SignalEngine.ScoreBreakdown) -> String {
        let scaled = min(1, b.durationFactor)
        var out: [String] = []
        if let h = b.heartPoints, let max = b.heartMax {
            out.append("heart \(Int((h * scaled).rounded())) of \(Int((max * scaled).rounded()))")
        }
        if let s = b.stillnessPoints, let max = b.stillnessMax {
            out.append("stillness \(Int((s * scaled).rounded())) of \(Int((max * scaled).rounded()))")
        }
        if b.hasDoorway {
            out.append("breath \(Int((b.breathPoints * scaled).rounded())) of \(Int((b.breathMax * scaled).rounded()))")
        }
        return out.joined(separator: ", ")
    }

    /// The working behind the session in focus, one line per term, with
    /// the levers ranked at the end. Every number here is computed; the
    /// model's job is to read it back in a warm voice and answer questions
    /// about it, not to redo it.
    static func scoreCard(_ r: SessionRow) -> String? {
        guard let b = r.breakdown, let score = r.score100 else { return nil }
        let scaled = min(1, b.durationFactor)
        func pts(_ v: Double?) -> String { v.map { "\(Int(($0 * scaled).rounded()))" } ?? "0" }
        var lines: [String] = ["SCORE CARD for the session in focus (score \(score), \(band(score)), \(r.minutes) min). Quote these lines; the arithmetic is done."]

        if b.heartTerm != nil, let held = b.heartHeld, let drop = b.heartDrop,
           let opening = r.startHR, let closing = r.endHR {
            let move = drop >= 1 ? "so it settled \(Int(drop.rounded())) beats"
                : drop <= -1 ? "so it climbed \(Int((-drop).rounded())) beats" : "so it ended where it began"
            lines.append("- Heart: opened at \(Int(opening.rounded())) bpm, closed at \(Int(closing.rounded())) bpm, \(move). It stayed at or below the opening rate for \(Int((held * 100).rounded()))% of the sit. Heart earned \(pts(b.heartPoints)) of \(pts(b.heartMax)) points: 60% of those are for staying at or under the opening rate, 40% for the size of the drop (12 beats earns all of it).")
        } else {
            lines.append("- Heart: not read this sit, so it earned no points and its weight went to the other signals.")
        }

        if let raw = b.stillnessRaw, let cubed = b.stillnessTerm {
            let read = raw >= 0.90 ? "a settled body" : raw >= 0.80 ? "ordinary small movement" : raw >= 0.60 ? "noticeable movement, more than a settled sit" : "a lot of movement"
            lines.append("- Stillness: \(String(format: "%.2f", raw)) on a 0 to 1 scale, which reads as \(read) (settled sits read 0.80 to 0.98). Cubed for the score it is \(String(format: "%.2f", cubed)). Stillness earned \(pts(b.stillnessPoints)) of \(pts(b.stillnessMax)) points.")
        } else {
            lines.append("- Stillness: not read this sit.")
        }

        if b.hasDoorway, let rate = r.doorwayRate {
            let held = r.doorwayHeldSec.map { ", kept up for \(mmss($0))" } ?? ""
            lines.append("- Breath: a slow-breath doorway was read at \(String(format: "%.1f", rate)) per minute\(held). Breath earned \(pts(b.breathPoints)) of \(pts(b.breathMax)) points, the full credit.")
        } else {
            lines.append("- Breath: no slow-breath doorway was read (no 60 seconds of deliberate slow breathing in the first 5 minutes), so breath earned nothing and heart and stillness share the whole score 60/40. Nothing was subtracted for it.")
            if let with = scoreWithDoorway(b) { lines.append("- With a breath doorway the same sit would score \(with).") }
        }

        if b.durationFactor < 1 {
            lines.append("- Time earns no points of its own; it sets the cap. A \(r.minutes) minute sit is scored against a cap of \(Int(b.cap.rounded())) (50 plus 5 per minute, up to 100 at 10 minutes), and the points above are already scaled to that cap." + (r.scoreAtTenMinutes.map { " At 10 min the same sit would score \($0)." } ?? ""))
        } else if b.durationFactor > 1 {
            lines.append("- Time earns no points of its own. Past 10 minutes a length bonus of \(Int(((b.durationFactor - 1) * 100).rounded()))% multiplied the depth.")
        } else {
            lines.append("- Time earns no points of its own. At 10 minutes the full 100 was available.")
        }
        let sum = "\(pts(b.heartPoints)) + \(pts(b.stillnessPoints)) + \(pts(b.hasDoorway ? b.breathPoints : 0))"
        if b.durationFactor > 1 {
            lines.append("- Total: \(sum) = \(Int((b.depth * 100).rounded())) before the length bonus; with it the score is \(score).")
        } else {
            lines.append("- Total: \(sum) = \(score), \(band(score)) (rounding may move it by one).")
        }
        lines.append(coaching(r, b))
        return lines.joined(separator: "\n")
    }

    /// The same sit had it opened with a doorway: the weights change to
    /// 50/30/20 and breath earns its full 20, so this is a real recompute,
    /// not a guess. Nil when the sit already had one.
    static func scoreWithDoorway(_ b: SignalEngine.ScoreBreakdown) -> Int? {
        guard !b.hasDoorway else { return nil }
        var terms: [(Double, Double)] = [(1.0, 0.20)]
        if let h = b.heartTerm { terms.append((h, 0.50)) }
        if let s = b.stillnessTerm { terms.append((s, 0.30)) }
        let total = terms.reduce(0) { $0 + $1.1 }
        let depth = terms.reduce(0) { $0 + $1.0 * $1.1 } / total
        return Int((min(1, depth * b.durationFactor) * 100).rounded())
    }

    /// The levers, ranked by points left on the table, so the advice is the
    /// same every time and always points at the biggest gap.
    static func coaching(_ r: SessionRow, _ b: SignalEngine.ScoreBreakdown) -> String {
        var levers: [(gap: Double, text: String)] = []
        let scaled = min(1, b.durationFactor)
        if let h = b.heartPoints, let max = b.heartMax, let held = b.heartHeld {
            let gap = (max - h) * scaled
            let text = held < 0.5
                ? "the heart rate ran above where it opened for most of the sit; settle before Begin (sit down, a few slow breaths, then start) and open with a minute of slow breathing so the opening reading is calm and the sit can settle under it"
                : "the heart held under its opening rate but did not fall far; a longer, quieter opening with slow breathing gives it room to drop"
            levers.append((gap, "heart (\(Int(gap.rounded())) points left): " + text))
        }
        if let s = b.stillnessPoints, let max = b.stillnessMax, let raw = b.stillnessRaw {
            let gap = (max - s) * scaled
            let text = raw < 0.80
                ? "the wrist moved a lot; rest the Watch arm on a leg or cushion, settle the posture before Begin, and let the body go heavy"
                : "small movement; the top of the range is where the points are, so keep the Watch arm resting and still"
            levers.append((gap, "stillness (\(Int(gap.rounded())) points left): " + text))
        }
        if !b.hasDoorway {
            let gain = scoreWithDoorway(b).map { max(0, $0 - Int((b.score * 100).rounded())) } ?? 0
            levers.append((Double(gain), "breath (\(gain) points available): open the sit with a minute or two of slow, even breathing at 4 to 7 per minute, then let it go natural"))
        }
        if b.durationFactor < 1 {
            levers.append((b.durationFactor < 0.8 ? 12 : 4, "time: the same sit at 10 minutes lifts the cap to 100"))
        }
        levers.sort { $0.gap > $1.gap }
        let ranked = levers.prefix(3).map(\.text)
        return "COACHING FOR THIS SESSION, biggest lever first: " + ranked.joined(separator: "; ") + "."
    }

    private static func when(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = cal.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d yyyy"
        var s = f.string(from: date)
        if cal.isDate(date, inSameDayAs: now) { s += " (today)" }
        else if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { s += " (yesterday)" }
        return s
    }

    private static func mmss(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - The opening line

    /// Otto's first message, written by rules from the stored numbers with
    /// the verdict engine's own phrase bank. Instant, offline, and it cannot
    /// claim anything the results screen underneath does not show.
    static func opening(focus: SessionRow?, sessionCount: Int) -> String {
        if let focus {
            let verdict = VerdictEngine.verdict(for: .init(
                overallScore: focus.overallScore,
                stillnessScore: focus.stillnessScore,
                hrDecline: focus.hrDecline,
                breathDoorwayRate: focus.doorwayRate,
                breathDoorwayHeldSec: focus.doorwayHeldSec), numbers: true)
            let claims = verdict.sentence
            let lead = focus.score100.map { "Here is your \($0) from " } ?? "Here is "
            let sentence = claims.prefix(1).lowercased() + String(claims.dropFirst())
            return "\(lead)\(sitName(focus)): \(sentence) Ask me anything about it, or what to try next time."
        }
        if sessionCount == 0 {
            return "I'm Otto. Once you've sat with your Watch on, I can read your sessions back to you and explain the score. Until then, ask me anything about how to start."
        }
        let n = min(sessionCount, maxSessions)
        return "I'm Otto. I can read your last \(n == 1 ? "session" : "\(n) sessions") back to you, explain how the score is built, and help with the basics of sitting. Everything stays on your phone."
    }

    private static func sitName(_ r: SessionRow) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: r.date)
        let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        let day = cal.isDateInToday(r.date) ? "this" : cal.isDateInYesterday(r.date) ? "yesterday" : nil
        let when = day.map { $0 == "this" ? "this \(part)'s" : "yesterday \(part)'s" }
            ?? "\(r.date.formatted(.dateTime.weekday(.wide)))'s"
        return "\(when) \(r.minutes) minute sit"
    }

    // MARK: - Suggested questions

    static func suggestedQuestions(focus: SessionRow?, sessionCount: Int) -> [String] {
        if let focus, let score = focus.score100 {
            return ["Why did I score \(score)?", "What is a breath doorway?", "How do I settle faster?"]
        }
        if sessionCount == 0 {
            return ["How do I start meditating?", "What does the score measure?", "What is a breath doorway?"]
        }
        return ["How is my practice trending?", "What is a breath doorway?", "How do I settle faster?"]
    }

    // MARK: - Medical questions

    /// The one line Otto has for anything medical.
    static let declineLine = "That one is for a doctor or another health professional, not for me."

    /// Catches medical questions BEFORE the model sees them. The model is
    /// told the same rule, but a small on-device model is not where the
    /// guarantee should live. Word-start matching, so "retreat" is not
    /// "treat" and "retreats" stay a meditation topic.
    static func medicalDecline(for question: String) -> String? {
        medicalPattern.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)) == nil
            ? nil : declineLine
    }

    private static let medicalPattern: NSRegularExpression = {
        let stems = [
            "diagnos", "doctor", "physician", "cardiolog", "therapist", "medication", "medicine", "medical",
            "prescri", "pill", "drug", "dose", "symptom", "treat", "cure", "heal my",
            "arrhythm", "afib", "fibrillation", "tachycard", "bradycard", "palpitation", "murmur",
            "blood pressure", "hypertension", "hypotension", "heart condition", "heart disease",
            "heart attack", "heart failure", "chest pain", "stroke", "cholesterol",
            "pregnan", "anxiety", "depress", "panic", "ptsd", "adhd", "bipolar", "schizo", "trauma",
            "asthma", "copd", "diabet", "epilep", "seizure", "insomnia", "sleep apnea", "apnea",
            "faint", "dizz", "nausea", "sick", "illness", "disease", "disorder", "syndrome", "injur",
            "beta blocker", "ssri", "antidepress", "surgery", "hospital", "emergency",
            "is it safe", "is this safe", "safe to", "safe for", "dangerous", "harmful",
        ]
        let alternation = stems.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "\\b(\(alternation))", options: [.caseInsensitive])
    }()

    // MARK: - Output hygiene

    /// No em dashes reach the screen (the standing rule for every user-facing
    /// string; a generated sentence is user-facing). A comma is the closest
    /// honest substitute for a dash the model chose.
    static func sanitize(_ text: String) -> String {
        var s = text
        for dash in [" — ", " —", "— ", "—", " – "] {
            s = s.replacingOccurrences(of: dash, with: ", ")
        }
        return s.replacingOccurrences(of: ", ,", with: ",")
    }
}
