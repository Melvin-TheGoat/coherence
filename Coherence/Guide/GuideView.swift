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
    /// Leave the guide and open the Begin sheet. Owned by the presenter, because
    /// swapping one sheet for another has to happen after this one is down.
    var onBegin: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Query private var reflections: [SessionReflection]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to meditate")
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Ways to practice, easiest first.")
                            .font(AppFont.note)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.bottom, 2)

                    ForEach(Array(MeditationMethod.all.enumerated()), id: \.element.id) { index, method in
                        NavigationLink {
                            MethodDetailView(method: method, onBegin: begin)
                        } label: {
                            PathStop(method: method,
                                     isLast: index == MeditationMethod.all.count - 1,
                                     loggedCount: count(for: method))
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
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

// MARK: - One stop on the path

/// A row on the roadmap. The teal rail says these are a progression (each level
/// builds, and the body scan is a stated prerequisite for manifestation) without
/// numbering them, because nobody has to go in order.
private struct PathStop: View {
    let method: MeditationMethod
    let isLast: Bool
    let loggedCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(AppColor.calmAccent, lineWidth: 1.5)
                    .background(Circle().fill(AppColor.calmAccent.opacity(0.12)))
                    .frame(width: 13, height: 13)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(AppColor.calmAccent.opacity(0.28))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 13)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(method.title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Text(method.oneLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    LevelChip(level: method.level)
                    Spacer(minLength: 4)
                    // The one gold thing in the row: what you've actually done.
                    // Hidden at zero rather than reading "0 sessions" at someone.
                    if loggedCount > 0 {
                        Text(loggedCount == 1 ? "1 session" : "\(loggedCount) sessions")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 1)
            }
            .card(padding: 14)
            .padding(.bottom, isLast ? 0 : 12)
        }
    }
}

/// Teal, because the guide is guidance. Gold stays reserved for what you did.
private struct LevelChip: View {
    let level: MeditationMethod.Level
    var body: some View {
        Text(level.label.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(AppColor.calmAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColor.calmAccent.opacity(0.45), lineWidth: 1)
            )
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
                    LevelChip(level: method.level)
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
