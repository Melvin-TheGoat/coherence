#if DEBUG
import SwiftUI

/// Every screen "Ask Otto" can lead to, in one list, so Melvin can demo them
/// on his own phone over a cable with no environment variables (Settings >
/// the DEBUG section > "Otto's unblock screens"). The twenty intervention
/// kinds (`InterventionKind`, `Shared/Block/Interventions.swift`) plus the
/// "Not now" how-long screen: everything `InterventionView.swift`'s flow can
/// show. That covers the odd ones by construction, not by a special case:
/// the countdown that hides "Not now" until it hits zero is `.countdown`,
/// and the call that opens the front camera is `.faceTime`.
///
/// Tapping a row presents the EXACT SAME `InterventionView` the real "Ask
/// Otto" notification opens, full screen, the same way `ContentView` does.
/// But nothing here is real: `rehearsal: true` tells `HowLongScreen` to skip
/// `BlockController.takePass`, so "Open my apps" can never touch a real
/// blocker or Screen Time, and `onMeditate` here only dismisses, so
/// "let's meditate" never starts a session. Both doors, and the X, just
/// close back to this list.
struct InterventionGalleryView: View {
    @ObservedObject private var block = BlockController.shared
    @State private var showing: Row?

    private enum Row: Identifiable {
        case kind(InterventionKind)
        /// `HowLongScreen`: reached the moment any of the twenty screens has
        /// its "Not now" tapped. Its own row opens it directly.
        case howLong

        var id: String {
            switch self {
            case .kind(let kind): return kind.rawValue
            case .howLong: return "howLong"
            }
        }

        var title: String {
            switch self {
            case .kind(let kind): return kind.galleryName
            case .howLong: return "How long? (\"Not now\")"
            }
        }

        var subtitle: String {
            switch self {
            case .kind(let kind): return kind.gallerySubtitle
            case .howLong: return "What any screen's Not now opens"
            }
        }
    }

    var body: some View {
        List {
            Section("Intervention screens (20)") {
                ForEach(InterventionKind.allCases, id: \.rawValue) { kind in
                    row(.kind(kind))
                }
            }
            Section("Other screens") {
                row(.howLong)
            }
        }
        .navigationTitle("Otto's unblock screens")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $showing) { which in
            switch which {
            case .kind(let kind):
                InterventionView(kind: kind, context: Self.demoContext, block: block,
                                 onMeditate: { _ in showing = nil },
                                 onClose: { showing = nil },
                                 rehearsal: true)
            case .howLong:
                // .standing is never seen: startOnHowLong skips straight
                // past the "ask" step to HowLongScreen.
                InterventionView(kind: .standing, context: Self.demoContext, block: block,
                                 onMeditate: { _ in showing = nil },
                                 onClose: { showing = nil },
                                 rehearsal: true, startOnHowLong: true)
            }
        }
    }

    private func row(_ which: Row) -> some View {
        Button { showing = which } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(which.title)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(which.subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 2)
        }
    }

    /// What Otto would know, so every screen reads true instead of blank: a
    /// real streak, a mid-glow aura, and a friend so `.friend` has a name.
    /// The gallery shows every kind regardless of hour or streak, unlike the
    /// real `InterventionPicker.eligible`, since the whole point is seeing
    /// all twenty on demand.
    private static var demoContext: InterventionContext {
        InterventionContext(hour: Calendar.current.component(.hour, from: Date()),
                            streak: 6, aura: .progressing, friendWhoSat: "Sam")
    }
}

private extension InterventionKind {
    /// A readable name for the gallery list; the raw case name is for code.
    var galleryName: String {
        switch self {
        case .standing: return "Standing ask"
        case .textThread: return "Text thread"
        case .faceTime: return "FaceTime call"
        case .breatheWithMe: return "Breathe with me"
        case .voiceNote: return "Voice note"
        case .fridgeNote: return "Fridge note"
        case .stillThere: return "It'll still be there"
        case .wakingOtto: return "Waking Otto"
        case .sign: return "Otto's sign"
        case .streak: return "Streak reminder"
        case .glow: return "Help me glow"
        case .twoDoors: return "Two doors"
        case .countdown: return "Countdown"
        case .affirmation: return "Today's affirmation"
        case .bedtime: return "Wind down for bed"
        case .sticker: return "Sticker"
        case .valley: return "Quiet valley"
        case .friend: return "A friend already sat"
        case .oneMinute: return "One minute"
        case .askWhy: return "Otto asks why"
        }
    }

    /// One line naming what's notable, for anyone rehearsing a screen who
    /// has not read `InterventionView.swift`.
    var gallerySubtitle: String {
        switch self {
        case .standing: return "Otto standing, a plain ask"
        case .textThread: return "A chat thread from Otto"
        case .faceTime: return "A call screen. Asks for the front camera"
        case .breatheWithMe: return "One paced breath, then a choice"
        case .voiceNote: return "A voice note bubble"
        case .fridgeNote: return "A handwritten note"
        case .stillThere: return "Whatever it is can wait"
        case .wakingOtto: return "Morning only, in the real flow"
        case .sign: return "A little sign he's holding up"
        case .streak: return "Names the current streak"
        case .glow: return "Asks for help with his glow"
        case .twoDoors: return "Calm or the scroll, side by side"
        case .countdown: return "Not now is hidden until it hits zero"
        case .affirmation: return "Today's line, and a short sit"
        case .bedtime: return "Night only, in the real flow"
        case .sticker: return "A sticker message"
        case .valley: return "Otto alone in the valley"
        case .friend: return "Names a friend who already sat"
        case .oneMinute: return "As short as the shortest session that counts"
        case .askWhy: return "Asks why, then answers what you pick"
        }
    }
}
#endif
