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
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownParser.Block) -> some View {
        switch block {
        case .title(let s):
            Text(s)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppColor.accentGold)
                .padding(.bottom, 2)
        case .heading(let s):
            Text(s)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 6)
        case .subheading(let s):
            Text(s)
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 4)
        case .paragraph(let s):
            Text(inline(s))
                .font(.callout)
                .foregroundStyle(AppColor.textSecondary)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(AppColor.accentGold)
                Text(inline(s)).font(.callout).foregroundStyle(AppColor.textSecondary)
            }
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").font(.caption2.monospacedDigit()).foregroundStyle(AppColor.textSecondary)
                Text(inline(s)).font(.caption2).foregroundStyle(AppColor.textSecondary)
            }
        case .divider:
            Rectangle()
                .fill(AppColor.textSecondary.opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

enum MarkdownParser {
    enum Block {
        case title(String)
        case heading(String)
        case subheading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
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
