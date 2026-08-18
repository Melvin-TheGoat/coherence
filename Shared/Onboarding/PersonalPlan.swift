import Foundation

/// What 808 answers, for THIS person, in their own words.
///
/// **Why this exists.** The onboarding was written when the mission was one
/// promise: we measure what happened. It is now three, and the other two had no
/// representation in the flow at all:
///
/// - **Measurable** — the score, the curves, the verdict
/// - **Habitual** — streaks, awards, history, the reminder
/// - **Universal** — bring your own audio, share the proof, practise alongside
///   other people
///
/// The interview asks thirteen questions and then almost nothing downstream
/// reads the answers, which is the documented "decorative questions" failure.
/// This is the mapping that fixes it: every pain point a person names gets
/// answered by the part of the product that actually answers it.
///
/// Pure Foundation on purpose. Every branch is checkable without a simulator,
/// and the claims are in ONE place rather than scattered across four screens
/// that can drift apart.
public enum PersonalPlan {

    /// Which third of the mission a claim comes from. Carried so a screen can
    /// show its source, and so a test can prove the flow does not talk about
    /// measurement and nothing else.
    public enum Pillar: String, CaseIterable {
        case measurable, habitual, universal
    }

    public struct Answer: Identifiable, Hashable {
        /// What they told us, in their words where possible.
        public let concern: String
        /// What 808 does about it. A shipped feature every time.
        public let response: String
        public let pillar: Pillar
        public let icon: String

        public var id: String { concern }
    }

    // MARK: - Motivations

    /// The outcome each motivation names, phrased so it can be appended to a
    /// sentence: "Still body. Lowered stress, sharper focus."
    public static func outcomes(for motivations: Set<Motivation>) -> [String] {
        // Fixed order, not set order, so two people who picked the same things
        // read the same sentence.
        let ordered: [Motivation] = [.lessStressed, .lessAnxious, .sharperFocus,
                                     .moreDiscipline, .betterSleep, .changeIdentity,
                                     .manifestGoals, .deeperPractice, .other]
        return ordered.filter(motivations.contains).compactMap(outcome)
    }

    /// Nil where we cannot honestly name an outcome. "Something else" is the
    /// obvious one: we do not know what they meant, so we do not put words in
    /// their mouth.
    static func outcome(_ m: Motivation) -> String? {
        switch m {
        case .lessStressed:   return "lowered stress"
        case .lessAnxious:    return "a calmer head"
        case .sharperFocus:   return "sharper focus"
        case .moreDiscipline: return "a streak you can see"
        case .betterSleep:    return "an easier wind-down"
        case .changeIdentity: return "the person you are becoming"
        case .manifestGoals:  return "your intentions, practised daily"
        case .deeperPractice: return "a deeper practice"
        case .other:          return nil
        }
    }

    /// The sentence appended to "Still body." on the build screen. Empty when
    /// nothing can be claimed, and the caller prints nothing rather than an
    /// empty flourish.
    public static func outcomeSentence(for motivations: Set<Motivation>) -> String {
        let parts = outcomes(for: motivations)
        guard !parts.isEmpty else { return "" }
        return parts.map(\.capitalizedFirst).joined(separator: ", ") + "."
    }

    // MARK: - The full answer list

    /// Everything this person named, each paired with what answers it.
    ///
    /// Ordered by how sharply the concern was expressed: the reason they
    /// stopped comes before a general aspiration, because it is the thing most
    /// likely to stop them again.
    public static func answers(for a: OnboardingAnswers) -> [Answer] {
        var out: [Answer] = []
        var seen = Set<Pillar>()

        for cause in orderedCauses(a.causes) {
            out.append(answer(for: cause))
        }
        for motivation in orderedMotivations(a.motivations) {
            if let item = answer(for: motivation) { out.append(item) }
        }
        if let blindSpot = a.blindSpot {
            out.append(Answer(concern: blindSpot.label,
                              response: blindSpot.answer,
                              pillar: .measurable, icon: "eye"))
        }
        seen = Set(out.map(\.pillar))

        // Every third of the mission gets said, whatever was answered. The flow
        // used to be able to talk about measurement and nothing else; a test
        // then caught the mirror image, where someone who skipped the optional
        // questions never heard the core promise at all.
        if !seen.contains(.measurable) {
            out.append(Answer(concern: "Knowing it worked",
                              response: "A score and three curves off your wrist, after every session",
                              pillar: .measurable, icon: "chart.line.uptrend.xyaxis"))
        }
        if !seen.contains(.habitual) {
            out.append(Answer(concern: "Keeping it going",
                              response: "A streak, a nudge at the time you chose, and awards for coming back",
                              pillar: .habitual, icon: "flame"))
        }
        if !seen.contains(.universal) {
            out.append(Answer(concern: "Doing it your way",
                              response: "Play whatever you meditate to. We measure it either way",
                              pillar: .universal, icon: "headphones"))
        }
        return out
    }

    static func orderedCauses(_ causes: Set<DropoutCause>) -> [DropoutCause] {
        let order: [DropoutCause] = [.couldntTell, .noAccountability, .forgot,
                                     .tooManyChoices, .feltWrong, .gotBoring, .noTime]
        return order.filter(causes.contains)
    }

    static func orderedMotivations(_ motivations: Set<Motivation>) -> [Motivation] {
        let order: [Motivation] = [.moreDiscipline, .lessStressed, .lessAnxious,
                                   .sharperFocus, .betterSleep, .changeIdentity,
                                   .manifestGoals, .deeperPractice, .other]
        return order.filter(motivations.contains)
    }

    static func answer(for cause: DropoutCause) -> Answer {
        switch cause {
        case .couldntTell:
            return Answer(concern: cause.label,
                          response: "A score and three curves after every session",
                          pillar: .measurable, icon: "chart.line.uptrend.xyaxis")
        case .noAccountability:
            return Answer(concern: cause.label,
                          response: "A streak that notices, plus challenges and group sits with other people practising",
                          pillar: .universal, icon: "person.2")
        case .forgot:
            return Answer(concern: cause.label,
                          response: "One reminder, at the moment you told us",
                          pillar: .habitual, icon: "bell")
        case .tooManyChoices:
            return Answer(concern: cause.label,
                          response: "One button. No length to pick, nothing to choose",
                          pillar: .habitual, icon: "hand.tap")
        case .feltWrong:
            return Answer(concern: cause.label,
                          response: "Nothing to get wrong. We read your body, not your technique",
                          pillar: .measurable, icon: "checkmark.seal")
        case .gotBoring:
            return Answer(concern: cause.label,
                          response: "Your own audio, a guide with eight methods, and awards to chase",
                          pillar: .universal, icon: "headphones")
        case .noTime:
            return Answer(concern: cause.label,
                          response: "Sessions end when you end them, so two minutes still counts",
                          pillar: .habitual, icon: "clock")
        }
    }

    /// Nil where a motivation is already covered by a cause's answer, or where
    /// naming a response would overclaim.
    static func answer(for motivation: Motivation) -> Answer? {
        switch motivation {
        case .moreDiscipline:
            return Answer(concern: "More discipline",
                          response: "Streaks, awards, and every session you have practised in one place",
                          pillar: .habitual, icon: "flame")
        case .lessStressed, .lessAnxious:
            return Answer(concern: motivation.label,
                          response: "Your heart coming down, measured, session after session",
                          pillar: .measurable, icon: "heart")
        case .sharperFocus:
            return Answer(concern: "Sharper focus",
                          response: "Stillness scored every time, so you can see it climb",
                          pillar: .measurable, icon: "scope")
        case .betterSleep:
            return Answer(concern: "Better sleep",
                          response: "An evening anchor, and a reminder set to it",
                          pillar: .habitual, icon: "moon.stars")
        case .changeIdentity:
            return Answer(concern: "Change who I am",
                          response: "A guided identity meditation, and months of history to show the arc",
                          pillar: .measurable, icon: "person.crop.circle.badge.checkmark")
        case .manifestGoals:
            return Answer(concern: "Manifest my goals",
                          response: "The manifestation method in the guide, practised from a settled body",
                          pillar: .measurable, icon: "sparkles")
        // Real practices, but 808 answers them no differently from anyone else,
        // and inventing a response would be the decorative-question failure in
        // a new coat.
        case .deeperPractice, .other:
            return nil
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst()
    }
}
