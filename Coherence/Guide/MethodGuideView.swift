import SwiftUI

/// The The Method: the practice explained, reachable before a session and from
/// Settings. Overview lists the five steps; each opens its own page.
///
/// Colour grammar holds — teal is guidance, gold is what you achieved. Nothing
/// on these screens is gold, because none of it is an achievement.
struct MethodGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MethodGuideContent()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(AppColor.accentGold)
                    }
                }
        }
    }
}

/// The guide without navigation chrome, so it can be **pushed** onto an
/// existing stack (Settings) as well as **presented** as a sheet (setup).
/// Wrapping it in its own NavigationStack in both places would nest stacks and
/// leave a stray Done button on the pushed copy.
struct MethodGuideContent: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                stepList
                referenceList
            }
            .padding(AppMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("The Method")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MethodGuide.introTitle)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            MarkdownProse(MethodGuide.intro)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "The five steps")
            ForEach(MethodGuide.steps) { step in
                // Destination-based rather than value-based: this view gets
                // PUSHED into Settings' stack as well as presented as a sheet,
                // and a destination link works in both without the parent
                // needing a matching navigationDestination registration.
                NavigationLink { MethodStepView(step: step) } label: {
                    HStack(alignment: .top, spacing: 13) {
                        Text("\(step.id)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.calmAccent)
                            .frame(width: 26, height: 26)
                            .background(AppColor.calmAccent.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(AppFont.callout.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(step.oneLine)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.top, 4)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    private var referenceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "References")
            ForEach(MethodGuide.allCitations) { CitationRow(citation: $0) }
        }
    }
}

/// One step in full: how to do it, what's been measured, where it comes from.
struct MethodStepView: View {
    let step: MethodGuide.Step

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STEP \(step.id)")
                        .font(.caption2.weight(.bold)).tracking(1.4)
                        .foregroundStyle(AppColor.calmAccent)
                    Text(step.title)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.oneLine)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                block(title: "How to do it") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(step.doThis.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle()
                                    .fill(AppColor.calmAccent)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(AppFont.note)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // The split that keeps this honest: measured findings first,
                // clearly separated from the tradition the technique came from.
                block(title: "What's been measured") {
                    VStack(alignment: .leading, spacing: 12) {
                        MarkdownProse(step.measured)
                        ForEach(step.citations) { CitationRow(citation: $0) }
                    }
                }

                if !step.technique.isEmpty {
                    block(title: "Where the technique comes from") {
                        VStack(alignment: .leading, spacing: 12) {
                            MarkdownProse(step.technique)
                            ForEach(step.sources) { source in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(source.who) · \(source.work)")
                                        .font(AppFont.caption.weight(.semibold))
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(source.note)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("Practice tradition, not peer-reviewed evidence.")
                                .font(.caption2)
                                .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                                .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(AppMetrics.screenPadding)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationTitle("Step \(step.id)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            content()
        }
    }
}

/// A citation, rendered so the DOI is obviously a real, checkable thing.
struct CitationRow: View {
    let citation: MethodGuide.Citation

    var body: some View {
        Link(destination: URL(string: "https://doi.org/\(citation.doi)")!) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(citation.authors) (\(String(citation.year)))")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(citation.title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(citation.venue)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.85))
                Text("doi.org/\(citation.doi)")
                    .font(.caption2)
                    .foregroundStyle(AppColor.calmAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// Minimal prose renderer: paragraphs, with **bold** honoured. The guide's copy
/// is authored text, not user input, so this stays deliberately small rather
/// than pulling in a full markdown engine.
struct MarkdownProse: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, para in
                Text(attributed(para))
                    .font(AppFont.note)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

#Preview { MethodGuideView() }
