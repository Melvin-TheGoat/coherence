import Foundation

/// The on-device text filter guideline 1.2 requires ("a method for filtering
/// objectionable material from being posted"). Runs on every title, caption,
/// nickname and username before it leaves the phone.
///
/// Whole-word matching after normalisation, so it catches "F.U.C.K", "fvck"
/// and "f u c k" without the Scunthorpe problem (a town, a class, "assess" and
/// "grapefruit" all pass). Deliberately short and blunt: it stops the obvious
/// slur or explicit word, and reports plus removal (the human half of 1.2)
/// catch the rest. Pure Foundation, in Shared/ so it is testable.
public enum ContentFilter {

    /// Whole words, after `normalize`. Slurs, explicit sexual terms and the
    /// strongest profanity. Mild words (damn, hell, crap) are allowed: a
    /// caption saying the session was hard as hell is not abuse.
    static let blocked: Set<String> = [
        // profanity aimed at people
        "fuck", "fucker", "fucking", "motherfucker", "cunt", "twat", "bitch", "whore", "slut",
        // explicit sexual
        "porn", "porno", "nude", "nudes", "dick", "cock", "pussy", "cum", "blowjob", "anal",
        "rape", "rapist",
        // slurs
        "nigger", "nigga", "faggot", "fag", "retard", "retarded", "tranny", "spic", "chink",
        "kike", "wetback", "dyke", "coon", "gook",
        // self-harm and violence directed at someone
        "kys", "killyourself",
    ]

    /// Phrases checked against the text with spaces and punctuation removed.
    static let blockedCompact: [String] = ["killyourself", "kysnow"]

    public enum Verdict: Equatable {
        case ok
        case blocked
    }

    public static func check(_ text: String) -> Verdict {
        let normalized = normalize(text)
        let words = normalized.split(separator: " ").map(String.init)
        if words.contains(where: matchesBlocked) { return .blocked }
        // Letter-by-letter spacing ("f u c k") collapses single letters into
        // a word before checking.
        let collapsedSingles = collapseSingleLetters(words)
        if collapsedSingles.contains(where: matchesBlocked) { return .blocked }
        let compact = words.joined()
        if blockedCompact.contains(where: { compact.contains($0) }) { return .blocked }
        return .ok
    }

    /// All fields of one post, profile or report, checked together.
    public static func check(_ fields: [String]) -> Verdict {
        fields.contains { check($0) == .blocked } ? .blocked : .ok
    }

    /// Lowercase, common look-alike digits and symbols mapped to letters,
    /// repeated letters squeezed to two, everything else a space.
    static func normalize(_ text: String) -> String {
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
                                           "7": "t", "@": "a", "$": "s", "!": "i", "v": "u"]
        var out = ""
        var last: Character?
        var run = 0
        for raw in text.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            var c = raw
            if let m = map[c] { c = m }
            if c.isLetter {
                if c == last { run += 1 } else { run = 1; last = c }
                if run <= 2 { out.append(c) }
            } else if c == "*" {
                // A masked letter ("f*ck") is kept as a one-letter wildcard.
                out.append("?")
                last = nil
                run = 0
            } else if c == "." || c == "_" || c == "-" {
                // Separators inside a word ("f.u.c.k", "f*ck") are dropped,
                // not turned into spaces, so the word stays whole.
                continue
            } else {
                out.append(" ")
                last = nil
                run = 0
            }
        }
        return out.split(separator: " ").joined(separator: " ")
            // Map "v" back where it is simply a v inside an ordinary word is
            // handled by whole-word matching: "love" becomes "loue", which
            // blocks nothing.
    }

    /// A word matches when it, its singular, or its letters-squeezed-to-one
    /// form is blocked ("fuuuuck" squeezes to "fuck"), with "?" standing for
    /// any single letter ("f?ck").
    static func matchesBlocked(_ word: String) -> Bool {
        let candidates = [word, depluralized(word), squeezed(word)]
        for c in candidates {
            if c.contains("?") {
                if blocked.contains(where: { wildcardMatch(c, $0) }) { return true }
            } else if blocked.contains(c) {
                return true
            }
        }
        return false
    }

    private static func squeezed(_ word: String) -> String {
        var out = ""
        for ch in word where ch != out.last { out.append(ch) }
        return out
    }

    private static func wildcardMatch(_ pattern: String, _ word: String) -> Bool {
        guard pattern.count == word.count, pattern.contains(where: { $0 != "?" }) else { return false }
        return zip(pattern, word).allSatisfy { $0 == "?" || $0 == $1 }
    }

    private static func depluralized(_ word: String) -> String {
        word.hasSuffix("s") && word.count > 3 ? String(word.dropLast()) : word
    }

    private static func collapseSingleLetters(_ words: [String]) -> [String] {
        var out: [String] = []
        var run = ""
        for w in words {
            if w.count == 1 { run += w } else {
                if run.count > 1 { out.append(run) }
                run = ""
            }
        }
        if run.count > 1 { out.append(run) }
        return out
    }
}
