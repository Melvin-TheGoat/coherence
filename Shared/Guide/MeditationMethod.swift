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
        techniques + sounds
    }

    /// The practices: what you did with your attention.
    public static var techniques: [(id: String, label: String)] {
        [(silenceID, "Silence"),
         (breathworkID, "Breath work"),
         (guidedID, "Guided meditation")] + all.flatMap { method -> [(String, String)] in
            guard !method.variants.isEmpty else { return [(method.id, method.title)] }
            return method.variants.map { (($0.id), "\(method.title) · \($0.title)") }
        }
    }

    /// Every sound 808 offers, as something you can say you did (Melvin,
    /// 2026-09-22). `SoundMenu` is the one list of them, so a sound added
    /// there appears here, on the results card and on Save session at once.
    public static var sounds: [(id: String, label: String)] {
        SoundMenu.groups.flatMap { group in
            group.entries.map { (id: $0.id, label: "\(group.name) · \($0.title)") }
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
    /// Sitting in silence with no named technique (Aziz, 2026-09-15: the
    /// picker had nothing for the most common session there is). Distinct
    /// from `ownID`, which means "a technique you have, that we don't list"
    /// and carries free text; this one means there was no technique to name.
    /// Not in the guide's method list: there are no steps to teach.
    public static let silenceID = "silence"
    /// The 808 guided journey. Not in the guide's method list (it is audio, not
    /// a technique to learn), but the most common thing a new person did.
    public static let guidedID = "guided"
    /// Deliberate breathing as the practice itself, rather than as the way
    /// into another one (Melvin, 2026-09-18: "add Silence and Breath work to
    /// the usual list"). Like `silenceID` and `guidedID` it is loggable but
    /// not a guide entry: the guide teaches specific patterns inside its own
    /// methods, and this is the plain category people reach for when naming
    /// what they just did. It is also the practice 808 reads best, since a
    /// slow-breath doorway is what the breath term scores.
    public static let breathworkID = "breathwork"

    // MARK: - The list

    public static let all: [MeditationMethod] = [

        MeditationMethod(
            id: "firstTime",
            title: "First time meditating",
            oneLine: "Start here. What meditation is, and what to actually do.",
            intro: """
            Meditation trains your mind to be more focused, more present, and \
            more aware of what it is doing.

            You can't force a mind to be quiet, the same way you can't pull a \
            flower out of a seed. But give a seed soil, water and sunlight, and \
            it grows on its own. Meditation works the same way. Set up the right \
            conditions and your mind settles by itself. Here they are.
            """,
            level: .beginner,
            steps: [
                "Set aside 10 to 20 minutes somewhere you won't be interrupted.",
                "Sit comfortably with your back straight, on something that supports you well. A chair is fine.",
                "Pick an anchor to rest your attention on. Most people use the breath. Breathe in slowly through your nose and out steadily through your mouth. Feel the air come in and feel it leave, and keep your attention right there.",
                "Optional: try a breathing pattern. Box breathing is in for 4 seconds, hold for 4, out for 4, hold for 4, and repeat. Or try 4-7-8: in for 4, hold for 7, out for 8. Both slow your breathing down, which helps your body relax. You don't need either one. If a hold ever makes you light-headed, skip it and just make each breath out a little longer than the breath in. Easy, natural breathing works too.",
                "Optional: some people like to picture a bright, rising energy filling them as they breathe in, and a soft, settling energy leaving as they breathe out. In Chinese tradition these are yang, the active side, and yin, the restful side.",
                "Your mind will wander. Everyone's does. When you notice, gently bring your attention back to the breath. Noticing and coming back is the practice, so there's no need to be hard on yourself for drifting.",
            ],
            purpose: """
            That's it. The rest is practice.

            Every time you notice a thought and come back, you get a little \
            better at watching your thoughts instead of getting carried off by \
            them. Done regularly, many people find that shows up as less \
            stress, steadier moods, and more time spent in the moment they're \
            actually in.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "countdown",
            title: "Counting Down From Ten",
            oneLine: "Ten slow numbers, a little deeper with each.",
            level: .beginner,
            steps: [
                "Close your eyes and count down slowly from ten.",
                "With each number, let yourself sink a little deeper, like walking down a staircase one step at a time.",
                "Give each number a full breath. There's no rush.",
                "When you reach one, stay there and rest.",
            ],
            purpose: """
            An easy way to relax, and a good way to start before any of the \
            other practices. Counting down is a common way to begin in hypnosis \
            and guided relaxation. It works for a lot of people, and it only \
            takes a minute to try.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "bodyScan",
            title: "Body Scan",
            oneLine: "Relax your body one part at a time.",
            level: .beginner,
            steps: [
                "Start at the top of your head.",
                "Slowly move your attention down your face: forehead, eyebrows, eyes, nose, cheeks, jaw, tongue.",
                "Then your neck and shoulders, and down your arms to your elbows, forearms and hands.",
                "Your chest, your belly, your lower belly.",
                "Your hips, thighs, knees, calves, ankles and feet. Every toe, even the little one.",
                "You don't have to make anything relax. Noticing a spot is often enough for it to soften on its own.",
            ],
            purpose: """
            Good for stress, and good before sleep. It's also a good way to \
            start the Manifestation practice, which works best from a relaxed \
            body.

            The body scan is a core part of Mindfulness-Based Stress Reduction, \
            the eight-week course in which one widely cited study found \
            increases in gray matter density (Hölzel 2011).
            """,
            origin: "Mindfulness-Based Stress Reduction (MBSR), the course Jon Kabat-Zinn started at the University of Massachusetts Medical School in 1979.",
            variants: []),

        MeditationMethod(
            id: "blueSky",
            title: "Blue Sky",
            oneLine: "Watch your thoughts drift by like clouds.",
            level: .intermediate,
            steps: [
                "Picture yourself lying in a grassy field, looking up at an open sky.",
                "Thoughts and feelings will come. That's fine. They're what you're practicing with.",
                "Let each thought be a cloud. Some are light and pretty, some are dark and stormy. Either way they're up there, far away, and you're down here on the grass.",
                "Every so often you'll realize you've been pulled up into a cloud. When you notice, come back down to the field.",
                "Come back calmly, without scolding yourself. As long as you keep coming back, you're doing it right.",
            ],
            purpose: """
            Coming back is the practice. You aren't trying to stop thinking. \
            You're learning to step back from your thoughts.

            Over time this shows you that you are not your thoughts. You're the \
            one noticing them. Whatever tends to set off your alarm bells, you \
            can step back and watch it pass.

            Make your own version if you like: cars going by on a highway, \
            ships crossing the ocean, fish swimming through a pond. Pick \
            whatever means something to you, or stay with the sky.
            """,
            origin: "",
            variants: []),

        MeditationMethod(
            id: "dualAwareness",
            title: "Dual Awareness",
            oneLine: "Rest on your breath while taking in the whole room.",
            level: .intermediate,
            steps: [
                "Settle on your breath as you would in any practice, with your attention on the feeling of the air moving.",
                "Without leaving the breath, start to notice what else is there. Sounds in the room. The weight of your body on the seat. Light through your eyelids. Air on your skin.",
                "Keep the breath in front and everything else in the background, both at once. You're not switching back and forth, and you don't need to name anything.",
                "You'll keep losing the balance. Sometimes you'll narrow in until only the breath is left. Sometimes you'll drift out and lose the breath completely. Both are normal. Gently widen out, or come back.",
                "With time you'll start to notice what your mind is doing while it's doing it. That's the skill this practice builds.",
            ],
            purpose: """
            Attention and awareness are two different things. Attention zooms \
            in on one thing. Awareness is wide and takes in everything around \
            it. Practicing with attention alone can leave you narrow and a \
            little dull.

            Holding both changes that. With awareness open, you catch a \
            distraction as it arrives instead of ten minutes after it carried \
            you off. It's also a skill that comes with you out of the session \
            and into an ordinary day.
            """,
            origin: "Culadasa (John Yates), The Mind Illuminated. A meditation teacher's book, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "energyCenters",
            title: "Blessing the Energy Centers",
            oneLine: "Move up through each center and bless it.",
            level: .intermediate,
            steps: [
                "In this practice there are seven energy centers running up the body: the base of the spine, the lower belly, the upper belly, the heart, the throat, the middle of the head, and the top of the head.",
                "Start with the first. Rest your attention there, then let your awareness open to the space around it.",
                "Once you can feel that space, bless it: fill it with a good feeling, like love, gratitude or joy.",
                "Move up to the next center and do the same, all the way to the top of your head.",
                "The eighth center is said to sit about sixteen inches above your head. Bless that one with gratitude. Dispenza describes gratitude as the feeling of having already received.",
            ],
            purpose: """
            A structured way to move your attention, and a good feeling, up \
            through your body instead of resting in one spot.
            """,
            origin: "Joe Dispenza, Becoming Supernatural. A practice tradition, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "reconditioning",
            title: "Reconditioning the Body to a New Mind",
            oneLine: "Start with the feeling, and let the picture follow.",
            level: .advanced,
            steps: [
                "Close your eyes. Let go of the room around you and bring your attention to the space in your chest.",
                "Slow your breathing down and let each breath go a little deeper.",
                "Bring something to mind, real or imagined, that sparks a good feeling.",
                "If a big dream for the future feels too far away, start small. Feel thankful for something simple, like a warm bed or a glass of water, and let the feeling grow from there.",
                "Stay in that feeling, as if the life you want is already yours.",
                "When you open your eyes, try to carry the feeling into your day instead of dropping it.",
            ],
            purpose: """
            Here the feeling comes first and the picture follows, the opposite \
            of the Manifestation practice. It's worth having both, since most \
            people find one much easier than the other.

            The slow breathing part is well studied on its own: breathing \
            slowly helps the body relax (Zaccaro 2018).
            """,
            origin: "Joe Dispenza. A practice tradition, not peer-reviewed evidence.",
            variants: []),

        MeditationMethod(
            id: "manifestation",
            title: "Manifestation",
            oneLine: "Plant an intention while your body is relaxed.",
            level: .advanced,
            steps: [
                "Relax your body completely. Use slow breathing, the body scan, counting down from ten, or any mix of them.",
                "Bring an intention you chose before you started. It's hard to come up with one while you're settling in.",
                "Feel the good feelings that go with it, like love, gratitude and joy. One or both of the two ways in below can help.",
                "Stay with those feelings until they feel complete.",
                "Then let it go and come back to the present.",
            ],
            purpose: """
            Memory research finds that moments with strong feeling attached are \
            remembered more strongly (McGaugh 2004). This practice puts that to \
            use by pairing what you want with a strong, good feeling. The idea \
            that this plants it in your subconscious comes from the practice's \
            teachers, not from research.
            """,
            origin: """
            "Manifestation: embedding intentions into your subconscious." \
            James Doty, Mind Magic (2024). A popular book, not a study.
            """,
            variants: [
                Variant(id: "innerConversation",
                        title: "Inner conversation",
                        origin: "Neville Goddard",
                        body: """
                        Imagine telling someone who really wants you to win. A \
                        close friend, someone in your family, anyone who would \
                        be truly happy for you.

                        Tell them, in the present tense, that it has happened. \
                        Hear how they react. Hear them get excited, and hear \
                        them say they're proud of you.

                        Feel what you would feel. Not someday. Right now, \
                        because it's already done.
                        """),
                Variant(id: "mentalMovie",
                        title: "Mental movie",
                        origin: "",
                        body: """
                        Imagine an ordinary day in a life where it has already \
                        happened.

                        You wake up. What you set out to do is done. You look \
                        around and feel relaxed, grateful, and in love with \
                        your life.

                        Play it like a film and let it run.
                        """),
            ]),
    ]
}

// MARK: - Symbols

extension MeditationMethod {
    /// The SF Symbol drawn in the method's sky circle, on the guide's list and
    /// on its own page (Aziz, 2026-09-22, the guide moved into the valley).
    /// Kept here beside the copy, so adding a method still needs no view
    /// change: an id with no entry draws the leaf.
    public var symbol: String {
        switch id {
        case "firstTime": return "leaf.fill"
        case "countdown": return "10.circle.fill"
        case "bodyScan": return "figure.stand"
        case "blueSky": return "cloud.sun.fill"
        case "dualAwareness": return "circle.circle.fill"
        case "energyCenters": return "sparkles"
        case "reconditioning": return "arrow.triangle.2.circlepath"
        case "manifestation": return "wand.and.stars"
        default: return "leaf.fill"
        }
    }
}
