import SwiftUI
import Charts

/// Screens 10–25: the calculation, what they told us reflected back, the proof
/// of mechanism, the wall, their profile and projection, the commitment, and
/// the offer.
///
/// **Integrity rules held throughout, from ONBOARDING.md:**
/// - No invented goal date. The projection is arithmetic from their own
///   committed days-per-week, and says so in a footnote.
/// - No fabricated scarcity, no countdown, no "94% off".
/// - No social proof we don't have. We have zero users and no press, so those
///   slots stay empty rather than filled with invention.
/// - Tier-1 names are quoted verbatim; Tier-2 are described as practising,
///   never quoted, and rendered visibly quieter.

// MARK: - 10 · Calculating

/// The loading screen treated as a feature, which is the one piece of theatre
/// from the reference flow worth taking wholesale.
///
/// **No ring and no percentage here, deliberately.** A gold ring with a number
/// in it is our SCORE — it's what the results screen shows after a session and
/// what every history row carries. Using the same object for a progress bar
/// teaches people to read one as the other, and then the real number arrives
/// looking like something they've already learned means nothing. The checklist
/// is the progress instead.
///
/// **Every line names something the code actually does.** An earlier draft said
/// "matched them to what makes people quit", which implied we'd run the answers
/// against dropout research; we hadn't. We map their stated reasons to the
/// features that answer them, so the line says that. This screen's honesty is
/// what buys the NEXT screen its credibility.
struct CalculatingScreen: View {
    let firstName: String
    let answerCount: Int
    let onDone: () -> Void

    @State private var completed = 0
    @State private var showHandoff = false
    @State private var typed = ""

    private var steps: [(running: String, done: String)] {
        [("Reading your \(answerCount) answers", "Read your \(answerCount) answers"),
         ("Matching your reasons to what 808 does about them",
          "Matched your reasons to what 808 does about them"),
         ("Setting your anchor", "Set your anchor"),
         ("Building your profile", "Built your profile")]
    }

    private var handoffText: String {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Here's what you told us."
                            : "Alright, \(name).\nHere's what you told us."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One moment.")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.bottom, 26)

            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                stepRow(index: i, step: step)
            }

            Spacer(minLength: 0)

            if showHandoff {
                // Typed out rather than faded in: the handoff should read as a
                // person speaking, not a form submitting.
                (Text(typed) + Text(typed.count < handoffText.count ? "▌" : "")
                    .foregroundStyle(AppColor.accentGold))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 56)
        .padding(.bottom, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onboardingGround(.cost)
        .task { await run() }
    }

    private func stepRow(index: Int, step: (running: String, done: String)) -> some View {
        let isDone = index < completed
        let isNow = index == completed
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: isDone ? "checkmark" : (isNow ? "circle.fill" : "circle"))
                .font(.system(size: isNow && !isDone ? 9 : 13, weight: .bold))
                .foregroundStyle(isDone ? AppColor.accentGold
                                 : (isNow ? AppColor.accentGold.opacity(0.55)
                                          : AppColor.textSecondary.opacity(0.22)))
                .frame(width: 17)
                .padding(.top, 3)
            // The tense flips on completion: a list of promises becomes a list
            // of finished work.
            Text(isDone ? step.done : step.running)
                .font(.system(size: 16))
                .foregroundStyle(index <= completed ? AppColor.textPrimary
                                                    : AppColor.textSecondary.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 17)
        .animation(.easeOut(duration: 0.3), value: completed)
    }

    private func run() async {
        for i in 0..<steps.count {
            try? await Task.sleep(for: .seconds(i == 0 ? 0.7 : 0.9))
            guard !Task.isCancelled else { return }
            withAnimation { completed = i + 1 }
        }
        try? await Task.sleep(for: .seconds(0.4))
        guard !Task.isCancelled else { return }
        withAnimation { showHandoff = true }

        for ch in handoffText {
            try? await Task.sleep(for: .milliseconds(38))
            guard !Task.isCancelled else { return }
            typed.append(ch)
        }
        try? await Task.sleep(for: .seconds(1.1))
        guard !Task.isCancelled else { return }
        onDone()
    }
}

// MARK: - 11 · The result

/// Their own answers, connected. The footnote is not decoration: it's the line
/// that keeps this a reflection rather than a diagnosis.
struct ResultScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    private var restartLine: String {
        switch answers.restarts {
        case .never: return "You're starting fresh."
        case .once:  return "You've stopped once before."
        case .few:   return "You've started and stopped a few times."
        case .many, .some(.lostCount): return "You've started and stopped more times than you'd like."
        case .none:  return "You're building the habit."
        }
    }

    @State private var revealed = false

    var body: some View {
        OnboardingScreen(section: .cost,
                         title: "Here's what you\njust told us.",
                         ctaTitle: "That's about right",
                         onContinue: onContinue) {
            VStack(alignment: .leading, spacing: 14) {
                reflection(restartLine,
                           "That's the single most common thing in meditation. Dropout runs 21 to 54% in clinical trials, and it peaks in the first two weeks.")

                if let cause = answers.primaryCause {
                    reflection("You stop because: \(cause.label.lowercased()).",
                               "That's not a character flaw. It's a missing feedback loop.")
                }

                if answers.isHighStress, let m = answers.primaryMotivation {
                    reflection("You're carrying a lot, and you want \(m.label.lowercased()).",
                               "Those two pull against each other. The stress is exactly what makes practice hardest to keep.")
                }

                Text("Your own answers, alongside published research on meditation-app dropout. Not a diagnosis.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                    .padding(.top, 6)
            }
            .sensoryFeedback(.success, trigger: revealed)
            .onAppear { revealed = true }
        }
    }

    private func reflection(_ headline: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 12 · The cost

/// Self-report only. We ask what it's costing; we never assign a condition.
///
/// Interactive rather than a page you read past: ticking nine boxes about your
/// own life is an admission you performed, where reading three cards is not.
/// The reference flow pairs its symptom list with an invented "64% suited"
/// score; we kept the list and refused the score, because the score was fiction
/// and this is the user telling us about themselves.
///
/// **Nothing is required.** Forcing an admission to proceed is the coercion the
/// rest of this flow refuses, so the CTA stays live at zero selections.
struct CostScreen: View {
    @Binding var costs: Set<CostSymptom>
    let onContinue: () -> Void

    private var countLine: String {
        switch costs.count {
        case 0: return "Tick whatever's true."
        case 1: return "One thing."
        case 2: return "Two things."
        case 3: return "Three things."
        default: return "\(costs.count) things."
        }
    }

    var body: some View {
        OnboardingScreen(section: .cost,
                         title: "What's it costing you?",
                         subtitle: "Tick whatever's true. Only you can answer this.",
                         ctaTitle: costs.isEmpty ? "Continue" : "That's the cost",
                         onContinue: onContinue) {
            VStack(alignment: .leading, spacing: 17) {
                ForEach(CostSymptom.Lens.allCases) { lens in
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(title: lens.label)
                        ForEach(CostSymptom.inLens(lens)) { symptom in
                            symptomRow(symptom)
                        }
                    }
                }

                Text(countLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .sensoryFeedback(.selection, trigger: costs)
        }
    }

    private func symptomRow(_ symptom: CostSymptom) -> some View {
        let selected = costs.contains(symptom)
        return Button {
            if selected { costs.remove(symptom) } else { costs.insert(symptom) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AppColor.accentGold
                                              : AppColor.textSecondary.opacity(0.35))
                Text(symptom.label)
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? AppColor.accentGold.opacity(0.10)
                                 : AppColor.backgroundSecondary.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? AppColor.accentGold : .clear, lineWidth: 1.5))
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - 13–15 · Proof

/// The mechanism, in three beats: your body already keeps score → so you get a
/// number → and you can meditate however you like. Order matters: the number
/// only reads as honest *after* the mechanism that makes it honest.
struct ProofScreen: View {
    enum Beat { case body, number, yourWay }

    let beat: Beat
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .win, title: title, subtitle: subtitle,
                         ctaTitle: beat == .yourWay ? "That's what I want" : "Go on",
                         onContinue: onContinue) {
            illustration.frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }

    private var title: String {
        switch beat {
        case .body:    return "Deep meditation runs\non theta."
        case .number:  return "So you get a number."
        case .yourWay: return "Meditate however\nyou like."
        }
    }

    private var subtitle: String {
        switch beat {
        case .body:
            return "It's the slow brainwave state that shows up when someone really drops in. Measured in labs for decades."
        case .number:
            return "One score, after the session. Never during: watching a number climb would raise your heart rate and wreck the very thing it measures."
        case .yourWay:
            return "YouTube, Spotify, a podcast, prayer, or silence. Start the session, leave the app, put on whatever you actually meditate to. The Watch keeps measuring."
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch beat {
        case .body:
            VStack(spacing: 16) {
                ThetaWaveCard()
                Text("But the body that goes with it **is** visible. When someone drops into that state, two things happen, and your Watch reads both.")
                    .font(OnboardingType.sub)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    signalTile("heart.fill", "Heart rate", "drifts down", AppColor.calmAccent)
                    signalTile("figure.mind.and.body", "Your body", "goes still", AppColor.calmAccent)
                }
            }
        case .number:
            ZStack {
                Circle()
                    .stroke(AppColor.textSecondary.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: 0.81)
                    .stroke(AppColor.accentGold,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("81")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("AFTER, NOT DURING")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 150, height: 150)
        case .yourWay:
            VStack(spacing: 10) {
                ForEach(["Your favourite teacher on YouTube",
                         "That one Spotify playlist",
                         "Prayer, in your own tradition",
                         "Nothing at all"], id: \.self) { line in
                    HStack(spacing: 11) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.accentGold)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func signalTile(_ icon: String, _ name: String, _ verb: String, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(tint)
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(verb)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The theta illustration, and the sentence that keeps it honest.
///
/// **These two must never be separated.** A moving wave beside the word "theta"
/// in a health app is close to looking like a measurement, and we measure heart
/// rate and movement, not brain activity. The disclaimer is load-bearing: it is
/// what makes the animation an illustration rather than a claim.
///
/// The wave therefore has no leading edge, no cursor and no scrolling data. It
/// drifts by exactly one period on a loop, which reads as decoration rather than
/// a live trace, and it holds still under Reduce Motion.
///
/// Never write "your theta", "reach theta" or "theta score". Theta exists in the
/// research; it is not something we hand the user. Teal, never gold: it is
/// physiology, not an achievement.
private struct ThetaWaveCard: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One period of the wave, in points. The path repeats every `period`, so
    /// translating by exactly this much loops seamlessly.
    private let period: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Theta")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.calmAccent)
                Spacer()
                Text("4 to 8 Hz")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.textSecondary)
            }

            ThetaWave(period: period)
                .stroke(AppColor.calmAccent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(height: 46)
                .offset(x: drift ? -period : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) {
                        drift = true
                    }
                }

            Divider().overlay(AppColor.textSecondary.opacity(0.12))

            Text("We can't see that from a wrist.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A plain sine, drawn wide enough that drifting one period never exposes an end.
private struct ThetaWave: Shape {
    let period: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let amp = rect.height * 0.38
        // Twice the visible width plus one period of overrun.
        let end = rect.width * 2 + period
        p.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x <= end {
            let y = mid - sin(x / period * 2 * .pi) * amp
            p.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        return p
    }
}

// MARK: - 16 · The wall

/// Tier 1 is quoted verbatim. Tier 2 is described, never quoted, and rendered
/// quieter so the difference is visible rather than just documented. The teams
/// lead, because a pattern among people whose job is measurable performance
/// reads as evidence rather than endorsement.
struct WallScreen: View {
    let onContinue: () -> Void

    private struct Quote: Identifiable {
        let id = UUID()
        let who: String
        let text: String
        let verbatim: Bool
    }

    private let quotes: [Quote] = [
        .init(who: "Phil Jackson's Bulls and Lakers",
              text: "Ran mindfulness training through Michael Jordan's and Kobe Bryant's championship years.", verbatim: false),
        .init(who: "The Seattle Seahawks",
              text: "Have practised mindfulness as a team since 2011.", verbatim: false),
        .init(who: "Ray Dalio",
              text: "Transcendental Meditation has probably been the single most important reason for whatever success I've had.", verbatim: true),
        .init(who: "Kobe Bryant",
              text: "It's like having an anchor. If I don't do it, it feels like I'm constantly chasing the day.", verbatim: true),
        .init(who: "Oprah Winfrey",
              text: "Meditation reorders the natural flow of life… Decisions come easily, things fall into place, and there's no conflict.", verbatim: true),
        .init(who: "Ray Dalio",
              text: "It helps slow things down so that I can act calmly, even in the face of chaos, like a ninja in a street fight.", verbatim: true),
        .init(who: "LeBron James, Novak Djokovic, Derek Jeter",
              text: "All credit a meditation practice.", verbatim: false),
        .init(who: "Jerry Seinfeld",
              text: "Has practised Transcendental Meditation for roughly forty years.", verbatim: false),
        .init(who: "Bill Gates, Jeff Bezos, Marc Benioff",
              text: "Each have described a regular practice.", verbatim: false),
    ]

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "You'd be in\nreasonable company.",
                         subtitle: "People whose job is measurable performance keep arriving at the same habit.",
                         ctaTitle: "Continue",
                         onContinue: onContinue) {
            VStack(spacing: 11) {
                ForEach(quotes) { q in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.verbatim ? "“\(q.text)”" : q.text)
                            .font(.system(size: 14, weight: q.verbatim ? .medium : .regular))
                            .foregroundStyle(q.verbatim ? AppColor.textPrimary
                                                        : AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(q.who)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColor.accentGold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(AppColor.backgroundSecondary.opacity(q.verbatim ? 0.8 : 0.45),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                Text("Quoted lines are verbatim and on the record. The rest describe a documented practice without putting words in anyone's mouth.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.75))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - 16b · Practice profile

struct ProfileScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    var body: some View {
        let p = PracticeProfile(from: answers)
        return OnboardingScreen(section: .win,
                                title: firstNameTitle,
                                subtitle: "Four things you told us. We'll hold you to them.",
                                onContinue: onContinue) {
            VStack(spacing: 12) {
                card("target", "What you're chasing", p.chasing)
                card("arrow.trianglehead.2.clockwise", "Your pattern", p.pattern)
                card("alarm", "Your anchor", p.anchorLine)
                card("eye.trianglebadge.exclamationmark", "Your blind spot", p.blindSpot)
            }
        }
    }

    private var firstNameTitle: String {
        let name = answers.firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Your practice profile" : "\(name)'s\npractice profile"
    }

    private func card(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.accentGold)
                .frame(width: 30, height: 30)
                .background(AppColor.accentGold.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.9)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 16c · Projection

/// The one number in onboarding that isn't simply repeated back — so it is
/// real arithmetic from their committed days-per-week, and the footnote says
/// exactly that. See `OnboardingProjection` and its tests.
struct ProjectionScreen: View {
    let daysPerWeek: Int
    let onContinue: () -> Void

    private var landing: Date? {
        OnboardingProjection.streakDate(daysPerWeek: daysPerWeek, from: Date())
    }

    var body: some View {
        let series = OnboardingProjection.weeklyCumulativeDays(daysPerWeek: daysPerWeek)
        return OnboardingScreen(section: .win,
                                title: headline,
                                subtitle: "At \(daysPerWeek) sessions a week, this is what the next month looks like.",
                                onContinue: onContinue) {
            VStack(alignment: .leading, spacing: 14) {
                Chart(Array(series.enumerated()), id: \.offset) { i, days in
                    AreaMark(x: .value("Week", i + 1), y: .value("Sessions", days))
                        .foregroundStyle(LinearGradient(colors: [AppColor.accentGold.opacity(0.28),
                                                                 AppColor.accentGold.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Week", i + 1), y: .value("Sessions", days))
                        .foregroundStyle(AppColor.accentGold)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: Array(1...max(series.count, 1))) { v in
                        AxisValueLabel { Text("Wk \(v.index + 1)").font(.caption2) }
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(AppColor.textSecondary.opacity(0.12))
                        AxisValueLabel().font(.caption2).foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(height: 170)

                Text("Simple arithmetic from the schedule you just chose. Not a prediction about how you'll feel.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
            }
        }
    }

    private var headline: String {
        guard let landing else { return "Your first month" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Your 30-day streak\nlands \(f.string(from: landing))."
    }
}

// MARK: - 16d · How you'll get there

/// Features mapped to the user's own words. Every row's left side is a phrase
/// they selected — never a problem we invented for them.
struct HowScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    private var rows: [(said: String, answer: String)] {
        let chosen = DropoutCause.allCases.filter { answers.causes.contains($0) }
        let source = chosen.isEmpty ? [DropoutCause.couldntTell] : chosen
        // De-duplicate: two causes can share one answering feature.
        var seen = Set<String>()
        return source.compactMap { c in
            guard !seen.contains(c.answer) else { return nil }
            seen.insert(c.answer)
            return (said: c.label, answer: c.answer)
        }
    }

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "How you'll\nget there.",
                         subtitle: "Each one answers something you just told us.",
                         onContinue: onContinue) {
            VStack(spacing: 12) {
                ForEach(rows, id: \.said) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("“\(row.said)”")
                            .font(.footnote.italic())
                            .foregroundStyle(AppColor.textSecondary)
                        HStack(spacing: 9) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(AppColor.accentGold)
                            Text(row.answer)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(AppColor.backgroundSecondary.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

// MARK: - 20 · Commitment

struct CommitmentScreen: View {
    @State private var committed = false
    @Binding var daysPerWeek: Int
    let anchor: Anchor?
    /// The strongest thing they said it was costing them. Echoed here so the
    /// promise answers the cost they named, and so the cost screen's nine
    /// selections aren't collected and then never mentioned again.
    let cost: CostSymptom?
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Make it a promise.",
                         ctaTitle: "I commit",
                         onContinue: { committed = true; onContinue() }) {
            VStack(spacing: 22) {
                // Their own sentence, assembled from their own answers.
                (Text("I'll practise ")
                 + Text("\(daysPerWeek) days a week").foregroundStyle(AppColor.accentGold).bold()
                 + Text(anchor.map { ", \($0.phrase)" } ?? "")
                     .foregroundStyle(AppColor.accentGold).bold()
                 + Text("."))
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)

                if let cost {
                    Text("So that \(cost.echo).")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.accentGold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { d in
                        Button { daysPerWeek = d } label: {
                            Text("\(d)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(d == daysPerWeek ? AppColor.textOnAccent
                                                                  : AppColor.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(d == daysPerWeek ? AppColor.accentGold
                                                             : AppColor.backgroundSecondary.opacity(0.7),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .sensoryFeedback(.selection, trigger: daysPerWeek)
                .sensoryFeedback(.success, trigger: committed)

                Text("Days per week")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}

// MARK: - 21 · Permission pre-prompt

/// Asked after the commitment and phrased in their anchor, so a "no" doesn't
/// burn the one system dialog iOS gives us.
struct PermissionScreen: View {
    let anchor: Anchor?
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "One nudge,\nat your time.",
                         subtitle: anchor.map { "We'll remind you \($0.phrase), the moment you just chose. Nothing else, ever." }
                            ?? "One reminder a day at the time you choose. Nothing else, ever.",
                         ctaTitle: "Turn on my reminder",
                         onSkip: onSkip,
                         onContinue: onAllow) {
            HStack(spacing: 13) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.accentGold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("808")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Two minutes. Your Watch is ready.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
            .background(AppColor.backgroundSecondary.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - 22 · Your week

struct WeekPreviewScreen: View {
    let onContinue: () -> Void

    private let days = [("Day 1", "Your first measured session. You'll see a number that means something."),
                        ("Day 2", "A second point. Two points make a line."),
                        ("Day 3", "The streak starts to feel like something you don't want to break."),
                        ("Day 7", "A week of evidence, and the first honest answer to \"is this working?\"")]

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Your first week.",
                         onContinue: onContinue) {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    HStack(alignment: .top, spacing: 15) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(AppColor.accentGold)
                                .frame(width: 9, height: 9)
                            if i < days.count - 1 {
                                Rectangle()
                                    .fill(AppColor.accentGold.opacity(0.3))
                                    .frame(width: 1.5)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.0)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.accentGold)
                            Text(day.1)
                                .font(.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 20)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
