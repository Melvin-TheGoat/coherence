import SwiftUI

/// Loads a bundled markdown doc (e.g. `PURPOSE.md`, `SCIENCE.md`) so onboarding
/// shows the real, full copy — and stays in sync when it's edited.
enum DocLoader {
    static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

/// A lightweight markdown renderer for our Purpose/Science pages: titles,
/// headings, paragraphs (with inline **bold**/*italic*), bullet + numbered lists,
/// and dividers. Strips HTML comments and `<sup>` citation tags. Not a general
/// markdown engine — just enough for these docs.
/// `LogoMark`'s geometry as a `Shape`, so it can be trim-animated (the mark
/// "draws itself" during onboarding).
struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path { LogoMark.path(in: rect) }
}

struct MarkdownView: View {
    let markdown: String
    /// When true (onboarding), the hero draws itself in and the copy staggers
    /// up after it. Settings and re-reads render instantly.
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = nothing, 1 = logo drawing, 2 = title+rule, 3 = body copy.
    @State private var stage = 0

    private var revealed: Bool { !animated || stage >= 3 }
    private var logoProgress: CGFloat { !animated || stage >= 1 ? 1 : 0 }
    private var titleShown: Bool { !animated || stage >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { i, block in
                if case .title = block {
                    view(for: block)
                } else {
                    view(for: block)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: runEntrance)
    }

    private func runEntrance() {
        guard animated, stage == 0 else { return }
        if reduceMotion { stage = 3; return }
        withAnimation(.easeInOut(duration: 1.5)) { stage = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.9)) { stage = 2 }
        withAnimation(.easeOut(duration: 0.7).delay(1.3)) { stage = 3 }
    }

    @ViewBuilder
    private func view(for block: MarkdownParser.Block) -> some View {
        switch block {
        case .title(let s):
            // Hero: the 808 mark draws itself in (trim animation) over a soft
            // breathing glow, then the title and gold rule follow.
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    BreathingGlow()
                        .frame(width: 96, height: 96)
                        .opacity(logoProgress == 1 ? 1 : 0)
                    LogoShape()
                        .trim(from: 0, to: logoProgress)
                        .stroke(AppColor.accentGold,
                                style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                        .frame(width: 48, height: 48)
                }
                .frame(width: 56, height: 56, alignment: .center)
                Text(s)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .opacity(titleShown ? 1 : 0)
                    .offset(y: titleShown ? 0 : 10)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColor.accentGold)
                    .frame(width: titleShown ? 44 : 0, height: 3)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        case .heading(let s):
            VStack(alignment: .leading, spacing: 6) {
                Text(s)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppColor.accentGold.opacity(0.55))
                    .frame(width: 26, height: 2)
            }
            .padding(.top, 12)
        case .subheading(let s):
            Text(s)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 6)
        case .paragraph(let s):
            Text(inline(s))
                .font(.callout)
                .lineSpacing(5)
                .foregroundStyle(AppColor.textPrimary.opacity(0.88))
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(AppColor.accentGold)
                    .frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                Text(inline(s))
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(AppColor.textPrimary.opacity(0.88))
            }
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.accentGold)
                    .frame(width: 16, alignment: .trailing)
                Text(inline(s))
                    .font(.caption2)
                    .lineSpacing(2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .note(let s):
            // Pull-quote style: gold stripe, roomy card.
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColor.accentGold)
                    .frame(width: 3)
                Text(inline(s))
                    .font(.footnote)
                    .italic()
                    .lineSpacing(4)
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .divider:
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppColor.accentGold.opacity(0.35))
                    .frame(width: 56, height: 2)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// A slow, soft gold halo that "breathes" behind the logo — calm-app ambience,
/// deliberately near-subliminal. Respects Reduce Motion (renders static).
struct BreathingGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [AppColor.accentGold.opacity(0.28), .clear],
                               center: .center, startRadius: 2, endRadius: 48)
            )
            .scaleEffect(inhale ? 1.12 : 0.9)
            .opacity(inhale ? 0.85 : 0.55)
            .blur(radius: 6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                    inhale = true
                }
            }
            .allowsHitTesting(false)
    }
}

/// The 808 mark drawing itself in over the breathing glow — the shared entrance
/// moment. Self-contained so any screen can drop it in.
struct DrawnLogo: View {
    var markSize: CGFloat = 72
    var glowSize: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            BreathingGlow()
                .frame(width: glowSize, height: glowSize)
                .opacity(progress >= 1 ? 1 : 0)
            LogoShape()
                .trim(from: 0, to: progress)
                .stroke(AppColor.accentGold,
                        style: StrokeStyle(lineWidth: markSize * 0.042,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: markSize, height: markSize)
        }
        .onAppear {
            if reduceMotion { progress = 1; return }
            withAnimation(.easeInOut(duration: 1.4)) { progress = 1 }
        }
    }
}

/// Fade-up entrance for any view, with a per-element delay — used to stagger a
/// screen's pieces in after the logo. Respects Reduce Motion.
struct FadeInUp: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.easeOut(duration: 0.6).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func fadeInUp(delay: Double) -> some View { modifier(FadeInUp(delay: delay)) }
}

enum MarkdownParser {
    enum Block {
        case title(String)
        case heading(String)
        case subheading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case note(String)
        case divider
    }

    static func parse(_ raw: String) -> [Block] {
        let cleaned = strip(raw)
        var blocks: [Block] = []

        // Paragraphs are separated by blank lines.
        for rawBlock in cleaned.components(separatedBy: "\n\n") {
            let lines = rawBlock.split(separator: "\n", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let first = lines.first, !first.isEmpty else { continue }

            if first.hasPrefix("### ") {
                blocks.append(.subheading(String(first.dropFirst(4))))
            } else if first.hasPrefix("## ") {
                blocks.append(.heading(String(first.dropFirst(3))))
            } else if first.hasPrefix("# ") {
                blocks.append(.title(String(first.dropFirst(2))))
            } else if first == "---" {
                blocks.append(.divider)
            } else if lines.allSatisfy({ $0.hasPrefix(">") }) {
                blocks.append(.note(lines.map { $0.drop(while: { $0 == ">" || $0 == " " }) }.joined(separator: " ")))
            } else if first.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                blocks.append(contentsOf: numberedItems(lines))
            } else if lines.allSatisfy({ $0.hasPrefix("- ") }) {
                blocks.append(contentsOf: lines.map { .bullet(String($0.dropFirst(2))) })
            } else {
                blocks.append(.paragraph(lines.joined(separator: " ")))
            }
        }
        return blocks
    }

    /// Groups a run of numbered lines into items, joining wrapped continuation
    /// lines into the item they belong to (references wrap across lines).
    private static func numberedItems(_ lines: [String]) -> [Block] {
        var items: [(Int, String)] = []
        for line in lines {
            if let r = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                let num = Int(line[line.startIndex..<line.index(before: r.upperBound)]
                    .prefix { $0.isNumber }) ?? items.count + 1
                items.append((num, String(line[r.upperBound...])))
            } else if !items.isEmpty {
                items[items.count - 1].1 += " " + line
            }
        }
        return items.map { .numbered($0.0, $0.1) }
    }

    /// Removes HTML comments and `<sup>…</sup>` tags (keeping the bracketed
    /// citation text), which our docs use but the renderer shouldn't show raw.
    private static func strip(_ s: String) -> String {
        var out = s
        for pattern in [#"<!--[\s\S]*?-->"#, #"</?sup>"#] {
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return out
    }
}
