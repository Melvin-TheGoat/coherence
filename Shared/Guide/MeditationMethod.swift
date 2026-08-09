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
            id: "blueSky",
            title: "Blue Sky",
            oneLine: "Watch your thoughts pass like clouds.",
            level: .beginner,
            steps: [
                "Picture yourself lying on a field of grass, looking up at an open sky.",
                "Thoughts will come. That is not a failure, it is the point.",
                "Make every thought a cloud. Some are light and pretty, some are dark and stormy. Either way they are far away, and you are down here on the field.",
                "Sometimes you will notice you have been pulled up into the clouds. When you notice, come back to the field.",
                "Come back calmly. No judgement, no deciding you are doing it wrong.",
            ],
            purpose: """
            The returning is the practice. You are not training to have no \
            thoughts, you are training the return, and that is the rep.

            What it teaches is that you are not your thoughts, you are the one \
            watching them. That is what lets you step back from the alarm bells, \
            whatever yours happen to be.
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
            level: .intermediate,
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
                "Do the body scan first. This is done from a settled body, not a busy one.",
                "Bring intentions you prepared ahead of time. This one does not work improvised.",
                "Wrap them in love, gratitude and joy, as much as you can genuinely find.",
                "Use one of the two techniques below.",
                "Keep going until you have actually felt it, not just pictured it.",
                "Then let it go and come back to the present.",
            ],
            purpose: """
            Emotional intensity at the time of an experience affects how \
            strongly it consolidates, which is why the feeling matters more \
            here than the picture.
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
