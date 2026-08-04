import Foundation

/// The **Field Guide** — the practice explained, one step at a time, with the
/// evidence and the lineage kept visibly apart.
///
/// **The rule this file exists to enforce:** every step separates
/// *what has been measured* (peer-reviewed, cited, DOI) from *where the
/// technique comes from* (Goddard, Maltz, Proctor, Dispenza, Doty — tradition
/// and teachers, not evidence). Blurring the two is the fastest way to lose a
/// skeptical reader and the surest way to attract an App Review problem. It's
/// the same discipline `SCIENCE.md` already applies to the solfeggio tones,
/// which are labelled tradition-only rather than dressed up as proven.
///
/// Nothing here may claim 808 *measures* a brain state. The findings describe
/// what meditation does; they are not readings we take. See the citation
/// integrity note at the bottom of `SCIENCE.md`.
///
/// Pure Foundation so it's testable and shared with the Watch if ever needed.
public enum FieldGuide {

    /// A peer-reviewed finding. Every one of these carries a real DOI.
    public struct Citation: Identifiable, Hashable {
        public var id: String { doi }
        public let authors: String
        public let year: Int
        public let title: String
        public let venue: String
        public let doi: String
    }

    /// A technique's origin. Deliberately a different type from `Citation` so
    /// the two can never be rendered as the same thing by accident.
    public struct Source: Identifiable, Hashable {
        public var id: String { "\(who)-\(work)" }
        public let who: String
        public let work: String
        /// What the technique actually is, in one line.
        public let note: String
    }

    public struct Step: Identifiable, Hashable {
        public let id: Int
        /// The matching movement in the in-session cue timeline.
        public let scriptStep: StructuredScript.Step
        public let title: String
        /// One line for the overview list.
        public let oneLine: String
        /// How to actually do it.
        public let doThis: [String]
        /// What's been measured — prose, backed by `citations`.
        public let measured: String
        public let citations: [Citation]
        /// Where the technique comes from — prose, backed by `sources`.
        public let technique: String
        public let sources: [Source]
    }

    // MARK: - Citations (verified against primary sources 2026-08-04)

    static let holzel = Citation(
        authors: "Hölzel BK, Carmody J, Vangel M, et al.", year: 2011,
        title: "Mindfulness practice leads to increases in regional brain gray matter density",
        venue: "Psychiatry Research: Neuroimaging, 191(1):36–43",
        doi: "10.1016/j.pscychresns.2010.08.006")

    static let brewer = Citation(
        authors: "Brewer JA, Worhunsky PD, Gray JR, et al.", year: 2011,
        title: "Meditation experience is associated with differences in default mode network activity and connectivity",
        venue: "PNAS, 108(50):20254–20259",
        doi: "10.1073/pnas.1112029108")

    static let tang = Citation(
        authors: "Tang YY, Hölzel BK, Posner MI", year: 2015,
        title: "The neuroscience of mindfulness meditation",
        venue: "Nature Reviews Neuroscience, 16(4):213–225",
        doi: "10.1038/nrn3916")

    static let mcgaugh = Citation(
        authors: "McGaugh JL", year: 2004,
        title: "The amygdala modulates the consolidation of memories of emotionally arousing experiences",
        venue: "Annual Review of Neuroscience, 27:1–28",
        doi: "10.1146/annurev.neuro.27.070203.144157")

    static let zaccaro = Citation(
        authors: "Zaccaro A, Piarulli A, Laurino M, et al.", year: 2018,
        title: "How breath-control can change your life: a systematic review on psycho-physiological correlates of slow breathing",
        venue: "Frontiers in Human Neuroscience, 12:353",
        doi: "10.3389/fnhum.2018.00353")

    static let lomas = Citation(
        authors: "Lomas T, Ivtzan I, Fu CHY", year: 2015,
        title: "A systematic review of the neurophysiology of mindfulness on EEG oscillations",
        venue: "Neuroscience & Biobehavioral Reviews, 57:401–410",
        doi: "10.1016/j.neubiorev.2015.09.018")

    // MARK: - The opening

    public static let introTitle = "What the practice is doing"

    public static let intro = """
    Three things have actually been measured in people who meditate, and they're \
    the reason this app exists.

    **Gray matter.** Eight weeks of mindfulness practice produced measurable \
    increases in gray matter density — in a controlled study, in ordinary people, \
    in two months.

    **Neuroplasticity.** The brain keeps rewiring in response to what you \
    repeatedly do with your attention. That's the mechanism behind every claim \
    below: repetition changes structure.

    **The Default Mode Network.** The DMN is the self-referential chatter \
    network — the running commentary about you. In experienced meditators its \
    main nodes, the medial prefrontal and posterior cingulate cortices, go \
    relatively quiet. That quiet is the opening the rest of this practice works in.

    None of this is something 808 measures in your brain. We measure your body — \
    stillness, heart rate, breath — which is what a wrist and a camera can \
    honestly read.
    """

    public static let introCitations: [Citation] = [holzel, tang, brewer]

    // MARK: - The five steps

    public static let steps: [Step] = [

        Step(id: 1, scriptStep: .intention,
             title: "Write it down first",
             oneLine: "Decide what you're planting before you close your eyes.",
             doThis: [
                "Keep a short written list — two or three intentions, not ten.",
                "Write them in the present tense, as already true.",
                "Be specific. \"I am calm\" is weaker than a scene you could film.",
                "Re-read it once, right before you start. Then put it down.",
             ],
             measured: """
             Honestly: this step is craft, not a finding. We're not aware of a \
             study showing that writing an intention down before meditating \
             changes an outcome, and we're not going to imply one exists.

             What it does is force specificity. "I am calm" is not a scene; a \
             scene is what steps three and four need to work with. Write it down \
             and the vagueness has nowhere to hide.
             """,
             citations: [],
             technique: """
             Maxwell Maltz argued the self-image is the governing mechanism: you \
             don't outperform the person you believe you are, so the target is \
             the self-image, not the behaviour. James Doty frames intention as \
             the thing that has to be clear before the nervous system can be \
             recruited toward it.
             """,
             sources: [
                Source(who: "Maxwell Maltz", work: "Psycho-Cybernetics (1960)",
                       note: "The self-image is the governing mechanism — change it and behaviour follows."),
                Source(who: "James Doty", work: "Into the Magic Shop · Mind Magic",
                       note: "Stanford neurosurgeon; intention-setting as the opening move."),
             ]),

        Step(id: 2, scriptStep: .bodyScan,
             title: "Release the body",
             oneLine: "Relax part by part until the body stops asking for attention.",
             doThis: [
                "Start at the crown, finish at the feet. Don't skip ahead.",
                "Let each exhale be where the letting-go happens.",
                "You're not relaxing to feel nice — you're clearing the line.",
                "This is the step that takes the longest. Let it.",
             ],
             measured: """
             The body scan is a core component of the eight-week mindfulness \
             programme in which the gray-matter changes were recorded. Slow, \
             settled breathing is independently well studied: reviews find \
             increased parasympathetic activity and measurable reductions in \
             stress and anxiety. This is also the part 808 can see — your \
             stillness curve is this step, drawn.
             """,
             citations: [holzel, zaccaro],
             technique: """
             The progressive body scan comes out of the clinical mindfulness \
             tradition rather than the manifestation one. It's here because a \
             body still demanding attention will keep interrupting the steps \
             that follow.
             """,
             sources: []),

        Step(id: 3, scriptStep: .envision,
             title: "See it already done",
             oneLine: "Not wishing for it — remembering it.",
             doThis: [
                "Enter the scene from the inside. Your own eyes, not a camera on you.",
                "Pick the moment just after it's true, not the achieving of it.",
                "Run a short mental movie and let it loop.",
                "Have the conversation you'd be having. Hear the other person answer.",
             ],
             measured: """
             Mental rehearsal is not idle daydreaming — imagining an action \
             recruits much of the same circuitry as performing it, which is why \
             imagery-based practice produces measurable change. This is the \
             neuroplasticity claim in its most practical form: attention, \
             repeated, reshapes structure.

             It also matters that this comes *after* the body work. The quieting \
             of the Default Mode Network — the self-commentary — is what makes \
             a scene feel inhabited rather than narrated.
             """,
             citations: [tang, brewer],
             technique: """
             Neville Goddard called it living in the end, and his inner \
             conversation technique is the specific move in step four of the \
             list above: rehearse the dialogue you'd be having if it were \
             already so. Bob Proctor taught the same thing as a mental movie. \
             Joe Dispenza's mental rehearsal is the popular modern version.
             """,
             sources: [
                Source(who: "Neville Goddard", work: "The Law and the Promise (1961)",
                       note: "Living in the end; inner conversation from the wish fulfilled."),
                Source(who: "Bob Proctor", work: "You Were Born Rich",
                       note: "The mental movie — a looped, sensory scene of the result."),
                Source(who: "Joe Dispenza", work: "Breaking the Habit of Being Yourself",
                       note: "Mental rehearsal of the future self. Popular framing, not peer-reviewed."),
             ]),

        Step(id: 4, scriptStep: .emotion,
             title: "Feel it as already true",
             oneLine: "The feeling is the part that sticks. The pictures are scaffolding.",
             doThis: [
                "Find the emotion you'd actually have — relief, gratitude, love.",
                "Thank someone for it, as if it were already given.",
                "When the images fade, stay with the feeling. That's not a failure.",
                "One genuine minute beats ten forced ones.",
             ],
             measured: """
             This is the best-supported step in the whole sequence. Emotional \
             arousal at the time of an experience modulates how strongly it \
             consolidates — the amygdala acts on memory formation, which is why \
             emotionally charged events are the ones you retain. Whatever you \
             want to take root, feeling is the mechanism that plants it deeper \
             than repetition alone.
             """,
             citations: [mcgaugh],
             technique: """
             Goddard's phrase was the feeling of the wish fulfilled — the claim \
             that the emotion, not the visualisation, is what does the work. \
             Dispenza's elevated emotion is the same instruction in modern \
             language.
             """,
             sources: [
                Source(who: "Neville Goddard", work: "Feeling Is the Secret (1944)",
                       note: "The emotion, not the image, is what impresses the subconscious."),
                Source(who: "Joe Dispenza", work: "Becoming Supernatural",
                       note: "Elevated emotion paired with clear intention. Popular framing, not peer-reviewed."),
             ]),

        Step(id: 5, scriptStep: .release,
             title: "Let it go",
             oneLine: "Holding on is the tell that you don't believe it yet.",
             doThis: [
                "Drop the images deliberately. Keep whatever feeling remains.",
                "Don't check whether it worked. Checking is doubt wearing a lab coat.",
                "Come back to the breath, then the room, then open your eyes.",
                "Get up and act like someone for whom it's already handled.",
             ],
             measured: """
             The Default Mode Network is the self-referential network — the \
             running commentary about you and your situation — and its main \
             nodes go relatively quiet in experienced meditators. That's the \
             measured part.

             The rest is reasoning from it, and we'll say so: anxiously checking \
             whether it worked is self-referential monitoring, which is the \
             activity that quiet was the absence of. Letting go isn't mystical \
             here. It's declining to switch the commentary back on.
             """,
             citations: [brewer],
             technique: """
             Every tradition in this list ends the same way, which is unusual \
             enough to be worth noticing. Goddard: having assumed the feeling, \
             drop it and go about your day. Doty: intention, then release. The \
             instruction is consistent because grasping and having are \
             incompatible postures.
             """,
             sources: [
                Source(who: "Neville Goddard", work: "The Power of Awareness (1952)",
                       note: "Assume the feeling, then release it and act from it."),
                Source(who: "James Doty", work: "Into the Magic Shop",
                       note: "Set the intention, then let go of the outcome."),
             ]),
    ]

    /// Everything cited anywhere in the guide, de-duplicated, for the reference
    /// list at the foot of the overview.
    public static var allCitations: [Citation] {
        var seen = Set<String>()
        return (introCitations + steps.flatMap(\.citations)).filter { seen.insert($0.id).inserted }
    }
}
