import SwiftUI
import SwiftData

/// The how-to guide. Answers the question every beginner actually asks, which
/// 808 had no answer to: "ok, but what do I *do*?"
///
/// **Every word on these screens comes from `Shared/Guide/MeditationMethod.swift`.**
/// Nothing here hardcodes copy, so editing the instructions never touches a view
/// and adding a method needs no UI change at all.
///
/// This is reference you read beforehand, not cues during a session. The old
/// "Method" was the second thing and it fought the promise that you can meditate
/// however you like. See `METHODS.md`.
struct GuideView: View {
    /// True when the guide is the Guide tab rather than a full-screen sheet:
    /// no Done button, nothing to dismiss.
    var embedded: Bool = false
    /// Leave the guide and open the Begin sheet. Owned by the presenter, because
    /// swapping one sheet for another has to happen after this one is down.
    var onBegin: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Query private var reflections: [SessionReflection]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to meditate")
                            .font(DisplayFont.display(24, .heavy))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("\(MeditationMethod.all.count) ways in. Any order you like.")
                            .font(AppFont.note)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.bottom, 8)

                    ForEach(MeditationMethod.Level.allCases, id: \.self) { level in
                        let methods = MeditationMethod.all.filter { $0.level == level }
                        if !methods.isEmpty {
                            SectionHeader(title: heading(for: level))
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                            ForEach(methods, id: \.id) { method in
                                NavigationLink {
                                    MethodDetailView(method: method, onBegin: begin)
                                } label: {
                                    MethodRow(method: method, loggedCount: count(for: method))
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                    }
                }
            }
        }
    }

    /// The level, said out loud instead of drawn as a rail.
    ///
    /// The list used to hang off a teal line with a hollow circle per row,
    /// which asserted "these are a progression" in the one visual language the
    /// rest of the app has dropped, and asserted it about a list nobody has to
    /// take in order. Three headings say the same thing in words, cost no ink,
    /// and are the only place the level needs to appear: the outlined
    /// `LevelChip` repeated on every row is gone with them.
    private func heading(for level: MeditationMethod.Level) -> String {
        switch level {
        case .beginner: return "Start here"
        case .intermediate: return "When you're ready"
        case .advanced: return "Going deeper"
        }
    }

    private func begin() {
        onBegin()
        dismiss()
    }

    /// How many sessions this method has been logged on. Variants count toward
    /// their parent, so "Manifestation" totals both ways in.
    private func count(for method: MeditationMethod) -> Int {
        let ids: Set<String> = method.variants.isEmpty
            ? [method.id]
            : Set(method.variants.map(\.id))
        return reflections.filter { ids.contains($0.technique ?? "") }.count
    }
}

// MARK: - One technique

/// A technique, and how many times YOU have sat it.
///
/// **The count is a capsule on the right, and it is absent at zero.** The
/// first cut of this put it in a 50pt token on the LEFT of every row, amber
/// and raised when practised and an empty hollow when not, matching an earned
/// award and a sat day. On the simulator that turned out to be wrong for the
/// one reader who matters most: somebody who has just installed the app meets
/// eight blank tiles down a screen whose whole job is to make them want to try
/// something. An empty slot works on the awards shelf because an award is a
/// thing you are meant to go and get. A technique is not a target, so an empty
/// box beside it is only an absence.
///
/// So the row is clean until you have earned something to put on it, and then
/// the capsule appears, amber, the one coloured thing in the row. Same idea,
/// no dead state.
private struct MethodRow: View {
    let method: MeditationMethod
    let loggedCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(method.title)
                    .font(DisplayFont.display(17))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(method.oneLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if loggedCount > 0 {
                Text(loggedCount == 1 ? "1 session" : "\(loggedCount) sessions")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textOnAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppColor.accentGold))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary.opacity(0.5))
                .padding(.top, 3)
        }
        .card(padding: 16)
        .padding(.bottom, 10)
    }
}

// MARK: - One method

/// Steps first, because that's what people came for. Why it works sits below,
/// and where it came from stays visibly separate from it. Same two-tier rule as
/// `SCIENCE.md`: never let a practice tradition borrow the authority of evidence.
struct MethodDetailView: View {
    let method: MeditationMethod
    var onBegin: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    // The detail screen keeps the level, because it arrives
                    // here without the heading that grouped it on the list.
                    // Filled tint rather than an outline, like every other
                    // chip in the app.
                    Text(method.level.label)
                        .font(AppFont.caption.weight(.bold))
                        .foregroundStyle(AppColor.calmAccent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(AppColor.calmAccentFill.opacity(0.18), in: Capsule())
                    Text(method.title)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(method.oneLine)
                        .font(AppFont.note)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if !method.intro.isEmpty {
                    Text(method.intro)
                        .font(AppFont.note)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "The practice")
                    ForEach(Array(method.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(AppFont.caption.weight(.bold))
                                .foregroundStyle(AppColor.calmAccent)
                                .monospacedDigit()
                                .frame(width: 14, alignment: .trailing)
                                .padding(.top, 2)
                            Text(step)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !method.variants.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: method.variants.count == 2 ? "Two ways in" : "Ways in")
                        ForEach(method.variants) { variant in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(variant.title)
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                if !variant.origin.isEmpty {
                                    Text(variant.origin)
                                        .font(.caption2)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Text(variant.body)
                                    .font(AppFont.note)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                            .card(padding: 14)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "What it is for")
                    Text(method.purpose)
                        .font(AppFont.note)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !method.origin.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(AppColor.textSecondary.opacity(0.3))
                                .frame(width: 2)
                            Text(method.origin)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    }
                }

                Button("Begin a session", action: onBegin)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
