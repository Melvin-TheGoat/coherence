import Foundation

/// The how-to guide: the methods 808 teaches, as data.
///
/// **This is a running list.** Adding a method is an entry here and nothing
/// else — the guide UI and the post-session picker both build themselves from
/// `MeditationMethod.all`, so no screen changes when the list grows.
///
/// **Why this exists.** Every beginner asks "ok, but what do I actually *do*?"
/// and until now 808 had no answer. It's also the only content we can ship
/// without recording audio.
///
/// **Not the thing we cut.** The old "Method" gave timed cues *during* a
/// session, which fought the promise that you can meditate however you like.
/// This is reference you read beforehand. See `METHODS.md`.
///
/// Honesty rule, same as everywhere else: describe the practice faithfully,
/// and keep *why it works* separate from *where it comes from*. Nothing here
/// may claim 808 measures a brain state.
public struct MeditationMethod: Identifiable, Hashable, Codable {

    public enum Level: String, Codable, CaseIterable {
        case beginner, intermediate, advanced

        public var label: String {
            switch self {
            case .beginner:     return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced:     return "Advanced"
            }
        }
    }

    public let id: String
    public let title: String
    /// One line for the roadmap row and the logging picker.
    public let oneLine: String
    /// Optional framing shown ABOVE the steps. Only the first-timer page needs
    /// it: everyone else already knows why they sat down.
    public var intro: String = ""
    public let level: Level
    /// The practice itself, in order. Rendered as numbered steps.
    public let steps: [String]
    /// What it's for — the honest version, no mechanism we can't support.
    public let purpose: String
    /// Where it comes from. Empty when it's general practice rather than a
    /// named teacher's technique.
    public let origin: String
    /// Sub-variants (manifestation has two). Empty for most.
    public let variants: [Variant]

    public struct Variant: Identifiable, Hashable, Codable {
        public let id: String
        public let title: String
        public let origin: String
        public let body: String
    }

    /// Every method a session can be tagged with, including variants, flattened
    /// for the picker.
    public static var loggable: [(id: String, label: String)] {
        all.flatMap { method -> [(String, String)] in
            guard !method.variants.isEmpty else { return [(method.id, method.title)] }
            return method.variants.map { (($0.id), "\(method.title) · \($0.title)") }
        }
    }

    public static func method(id: String) -> MeditationMethod? {
        all.first { $0.id == id || $0.variants.contains { v in v.id == id } }
    }

    /// Human label for a logged technique id, including the free-text case.
    public static func label(for id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if id == ownID { return "My own" }
        return loggable.first { $0.id == id }?.label
    }

    /// The id used when someone describes their own practice.
    public static let ownID = "own"

    // MARK: - The list

    public static let all: [MeditationMethod] = [

        MeditationMethod(
            id: "firstTime",
            title: "First time meditating?",
            oneLine: "Start here. What it is, and what to actually do.",
            intro: """
            The goal of meditation is to train the mind to be more focused, \
            present, and self aware.

            We do this by creating the conditions for the mind to reach \
            stillness. Just as we cannot pull a flower out of a seed, we cannot \
            force the mind to be still. What we can do is create the conditions: \
            Give a seed a pot, soil, water, and sunlight, and it will naturally \
            grow on its own. Meditation works the same way. If you create the \
            right conditions, the mind will naturally reach a peaceful stillness \
            on its own. Here are the conditions.
            """,
            level: .beginner,
            steps: [
                "Set aside some time. There is no rule, but 10 to 20 minutes is a good guide. Consider turning on Do Not Disturb.",
                "Sit comfortably on a well supported surface with a straight back.",
                "Focus on an anchor. It can be anything, and the most common one is the breath. Slowly breathe in through the nose, then steadily out through the mouth. Put all of your attention on the air rising through the nostrils on the way in, and releasing on the way out. Hold that focus.",
                "Optional: try a pattern. Box breathing is 4 seconds in, 4 hold, 4 out, 4 hold, repeat. Or 4-7-8, which is 4 in, 7 hold, 8 out. Both are ways into a calmer, parasympathetic state. There is no pressure to use one. Breathing deeply and naturally works too if that is what relaxes you.",
                "Optional: some people find it helps to picture a bright, rising energy filling the body on the inhale, and a soft, grounding energy leaving on the exhale. In Chinese tradition this is yin, the passive release, and yang, the active expansion.",
                "When your mind wanders off, and it will, notice it and gently bring your attention back to the breath. Expect the wandering. All that matters is that when you notice, you return, gently and without judgement.",
            ],
            purpose: """
            That is it. The rest is practice.

            Meditation is the practice of training your mind. Done regularly it \
            helps you observe your thoughts without judgement, leading to a \
            calmer mind, lower stress, better emotional control and a stronger \
            sense of being present.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "countdown",
            title: "Counting Down From Ten",
            oneLine: "Ten slow numbers, sinking deeper on each.",
            level: .beginner,
            steps: [
                "Close your eyes and count down from ten.",
                "With each number, imagine yourself sinking deeper.",
                "Let each one take a full breath. There is no rush.",
                "At one, stay there.",
            ],
            purpose: """
            A simple way into a relaxed state, and a good on-ramp before any of \
            the others. This is a standard induction. It works for a lot of \
            people, and it costs nothing to try.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "bodyScan",
            title: "Body Scan",
            oneLine: "Release the body one part at a time.",
            level: .beginner,
            steps: [
                "Start at the top of your head.",
                "Walk your attention down: skull, eyebrows, eyes, nose, tongue, cheeks, jaw.",
                "Neck, shoulders, biceps, triceps, elbows, forearms, hands.",
                "Chest, abdomen, lower abdomen.",
                "Hips, thighs, knees, calves, ankles, feet. Every toe, even the little one.",
                "Just noticing a part is often enough to release it.",
            ],
            purpose: """
            Good for stress and good before sleep. It is also the on-ramp to \
            the manifestation practice: a relaxed body settles first, and that \
            is the state the rest is done from.

            The body scan is a core part of the eight-week mindfulness course \
            that produced measurable increases in gray matter density.
            """,
            origin: "Clinical mindfulness practice (MBSR)",
            variants: []),

        MeditationMethod(
            id: "blueSky",
            title: "Blue Sky",
            oneLine: "Watch your thoughts pass like clouds.",
            level: .intermediate,
            steps: [
                "Picture yourself lying on a field of grass, looking up at an open sky.",
                "Thoughts and emotions will come. That is not a failure, it is the point.",
                "Picture every thought as a cloud. Some are light and pretty, some are dark and stormy. Either way they are far away, and you are down here on the field.",
                "Sometimes you will notice you have been pulled up into the clouds. When you notice, simply come back to the field.",
                "Come back calmly and without judgement. As long as you are returning, you are doing it correctly.",
            ],
            purpose: """
            Understand that the returning IS the practice. You are not training \
            to have no thoughts, you are training to separate yourself from them.

            What this teaches is that you are not your thoughts, you are the \
            observer of your thoughts. Whatever your alarm bells may be, you can \
            step back from them whenever you'd like.

            Come up with your own version if you like. The same idea works as \
            cars passing on a highway, ships crossing the ocean, fish moving \
            through a pond. Anything that means something to you. Or just do \
            blue sky.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "dualAwareness",
            title: "Dual Awareness",
            oneLine: "Hold the breath and the whole room at once.",
            level: .intermediate,
            steps: [
                "Settle on the breath the way you would in any practice. Attention on the sensations where the air moves.",
                "Now, without taking your attention off the breath, notice what else is there. Sounds in the room. The weight of your body on the seat. Light through your eyelids. Air on your skin.",
                "Keep the breath in the foreground and everything else in the background, both at the same time. You are not switching between them, and you are not trying to name what you notice.",
                "You will keep collapsing into one or the other. Sometimes you narrow down until only the breath exists. Sometimes you drift out and lose the breath entirely. Both are normal. Widen or return, gently.",
                "In time a third thing shows up: you start being able to tell what your mind is doing while it is doing it. That is the part worth having.",
            ],
            purpose: """
            Attention and awareness are not the same thing. Attention picks one \
            small part of experience and studies it. Awareness is open and \
            holds the whole context around it. Most practice trains only the \
            first, and attention on its own goes narrow and dull.

            Holding both is what makes the difference. With awareness open you \
            catch a distraction while it is arriving rather than ten minutes \
            after it took you, and this is the skill that carries out of the \
            session and into an ordinary day.
            """,
            origin: "Culadasa (John Yates), The Mind Illuminated. Practice tradition, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "energyCenters",
            title: "Blessing the Energy Centers",
            oneLine: "Move through each center and bless it.",
            level: .intermediate,
            steps: [
                "Place your attention in the first energy center.",
                "Open your awareness to the space around it.",
                "Once you can sense that space, bless the center.",
                "Connect to an elevated emotion there: love, gratitude, joy.",
                "Move through all seven centers in the body the same way.",
                "The eighth sits about sixteen inches above your head. Bless that one with gratitude, because gratitude is the state of already having received.",
            ],
            purpose: """
            A structured way to move attention and feeling through the body \
            rather than sitting in one place.
            """,
            origin: "Joe Dispenza, Becoming Supernatural. Practice tradition, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "reconditioning",
            title: "Reconditioning the Body to a New Mind",
            oneLine: "Start with the feeling, let the vision follow.",
            level: .advanced,
            steps: [
                "Close your eyes and bring your attention off the outside world and onto the space of your chest.",
                "Breathe slower and deeper.",
                "Bring something to mind, real or imagined, to jumpstart the feeling.",
                "If a big future vision feels too far away, start small. Being thankful for a simple comfort, or a glass of water. Let it expand from there.",
                "Radiate that appreciation and let the body accept it is already living in that reality.",
                "Carry it into your day rather than letting it drop the moment you open your eyes.",
            ],
            purpose: """
            The emotion comes first here and the vision follows it, which is the \
            reverse of the manifestation practice. Worth having both, because \
            most people find one of the two much easier than the other.

            Slow, deep breathing shifts you toward the parasympathetic side, \
            which is well studied on its own.
            """,
            origin: "Joe Dispenza. Practice tradition, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "manifestation",
            title: "Manifestation",
            oneLine: "Plant an intention while the body is settled.",
            level: .advanced,
            steps: [
                "Relax the body completely. You can use breathing techniques, the body scan, counting down from ten, or whatever combination you choose.",
                "Bring intentions you prepared ahead of time. This one does not work improvised.",
                "Deeply feel the elevated emotions around your intentions, such as love, gratitude, and joy. To help you do this, you can perform one or both of the two techniques below.",
                "Fully feel these emotions until you are satisfied.",
                "Let it go and return to the present.",
            ],
            purpose: """
            Emotional intensity at the time of an experience affects how \
            strongly it consolidates. This helps embed the intention into your \
            subconscious.
            """,
            origin: """
            "Manifestation: embedding intentions into your subconscious." \
            Doty JR (2024), Mind Magic. A trade book, not a study.
            """,
            variants: [
                Variant(id: "innerConversation",
                        title: "Inner conversation",
                        origin: "Neville Goddard",
                        body: """
                        Imagine telling someone who genuinely wants you to win. \
                        A close friend, a family member, anyone who would be \
                        truly happy for you.

                        Tell them, in the present tense, that you have done it. \
                        Hear them react. Hear them freak out, hear them say they \
                        are proud of you.

                        Feel what you would feel. Not what you will feel one \
                        day. What you feel now, because it is done.
                        """),
                Variant(id: "mentalMovie",
                        title: "Mental movie",
                        origin: "",
                        body: """
                        Imagine an ordinary day in the life where it is already \
                        accomplished.

                        You wake up. Everything you set out to do is done. You \
                        look around and feel relaxed, grateful, in love with \
                        your life.

                        Play it like a film and let it run.
                        """),
            ]),
    ]
}
