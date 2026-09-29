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

    // MARK: - Usernames

    /// What the handle check found. `reserved` is a handle that would read as
    /// 808 speaking (support, admin, otto, 808 itself): shown as taken.
    public enum HandleVerdict: Equatable {
        case ok
        case reserved
        case blocked
    }

    /// The username check, on top of `check` (Melvin, 2026-09-29, guideline
    /// 1.2).
    ///
    /// **A handle is one word, so the whole-word rule above cannot see into
    /// it.** "fuckyou", "bigdick" and "cuntface" are single words that are
    /// in no list, and they passed. Free text keeps the whole-word rule
    /// (a class, an assessment, Scunthorpe); a handle is checked for a short
    /// list of unambiguous STEMS anywhere inside it. A substring rule is only
    /// safe with an allowlist beside it, so `handleAllowed` names the real
    /// words and names that contain a stem (peacock, Dickens, therapist,
    /// Yamashita, Nazia) and they are taken out before the stems are looked
    /// for.
    public static func checkHandle(_ raw: String) -> HandleVerdict {
        var handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if handle.hasPrefix("@") { handle.removeFirst() }
        if isReservedHandle(handle) { return .reserved }
        for (variant, squeezed) in handleVariants(handle) {
            var text = variant
            for safe in squeezed ? allowedSqueezed : allowedAsWritten {
                text = text.replacingOccurrences(of: safe, with: " ")
            }
            if handleStems.contains(where: { text.contains($0) }) { return .blocked }
        }
        return check(handle) == .blocked ? .blocked : .ok
    }

    /// Stems no ordinary word or name contains once `handleAllowed` is taken
    /// out. Chosen short on purpose: each is a slur, an explicit term or the
    /// strongest profanity, and each was run against the system dictionary
    /// and names list before it went in. "twat" was tried and left out: it
    /// sits inside saltwater, sweetwater and outwatch, and the whole-word
    /// rule still catches it alone.
    static let handleStems: [String] = [
        "fuck", "cunt", "nigg", "fagg", "porn", "shit", "dick", "cock", "pussy",
        "whore", "slut", "bitch", "rapist", "nazi", "hitler", "kkk",
    ]

    /// Real words and names that contain a stem.
    static let handleAllowed: [String] = [
        // cock
        "shuttlecock", "weathercock", "hitchcock", "cockatiel", "cockroach", "woodcock",
        "cockatoo", "cocktail", "gamecock", "stopcock", "peacock", "hancock", "babcock",
        "cockpit", "cockburn", "cocker", "cockney", "cockle", "cockapoo",
        "alcock", "adcock", "laycock", "pocock", "silcock", "simcock", "willcock", "maycock",
        // dick
        "dickerson", "dickinson", "dickens", "dickson", "dickey", "dickie", "benedick",
        // shit: the mushroom, washi tape, and Japanese and Indian names
        // (Yamashita, Kinoshita, Yoshito, Ishita). A vowel before "shit" is
        // required, so "noshit" and "shitass" are not let through.
        "shiitake", "shitake", "shiite", "washi", "kshiti",
        "ashita", "eshita", "ishita", "oshita", "ushita",
        "ashito", "eshito", "ishito", "oshito", "ushito",
        // porn: Thai given names (Pornchai, Pornsak, Pornthip)
        "pornchai", "pornsak", "pornthip", "pornpimol", "pornpimon", "pornpan",
        "pornsiri", "pornrat", "pornwilai", "pornpen",
        // cunt, nigg, rapist, nazi, and the "oo" in poorness that a
        // squeeze turns into "porn"
        "scunthorpe", "niggl", "niggard", "therapist", "ashkenaz", "poorness",
        "nazia", "nazir", "nazim", "nazif", "nazih", "nazish", "naziya",
    ]

    /// Each allowed word as written, for the variants read as written, and as
    /// `handleVariants` squeezes it ("cockatoo" is read as "cockato"), for the
    /// squeezed ones. Kept apart: the squeezed Shiite is "shite", which must
    /// stay blocked when somebody types it. Longest first, so a longer word
    /// is removed whole before a shorter one inside it.
    private static let allowedAsWritten: [String] = handleAllowed.sorted { $0.count > $1.count }
    private static let allowedSqueezed: [String] = Array(Set(handleAllowed.map(squeezedRuns)))
        .sorted { $0.count > $1.count }

    /// The handle with separators gone, digits read two ways (as the letters
    /// they imitate, "sh1t", and as separators, "fuck2you"), each also with
    /// runs squeezed ("fuuuck", "niiigger"): a vowel run to one, anything
    /// else to two, so a stem's own double letter survives.
    private static func handleVariants(_ handle: String) -> [(text: String, squeezed: Bool)] {
        let lookalike: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
                                                 "7": "t", "@": "a", "$": "s", "!": "i"]
        let plain = handle.folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0 != "." && $0 != "_" && $0 != "-" }
        let mapped = String(plain.compactMap { c -> Character? in
            if let m = lookalike[c] { return m }
            return c.isLetter ? c : nil
        })
        let stripped = String(plain.filter(\.isLetter))
        return [(mapped, false), (stripped, false), (squeezedRuns(mapped), true), (squeezedRuns(stripped), true)]
    }

    private static func squeezedRuns(_ text: String) -> String {
        var out = ""
        var run = 0
        for c in text {
            if c == out.last { run += 1 } else { run = 1 }
            let limit = "aeiou".contains(c) ? 1 : 2
            if run <= limit { out.append(c) }
        }
        return out
    }

    /// Handles that would read as the app, its maker, or its staff.
    static let reservedHandles: Set<String> = [
        "808", "meditate808", "otto", "support", "admin", "administrator", "apple", "app",
        "official", "staff", "team", "moderator", "mod", "help", "security", "root",
        "system", "lockout",
    ]

    /// Reserved when every word in it is a reserved one: "admin", "808_support",
    /// "otto.official", "apple_help", "admin42" (a number beside a reserved
    /// word adds nothing), "meditate_808". A reserved word beside anything
    /// else is somebody's own name ("otto_k", "melvin808", "root_beer"), and
    /// `CreateProfileView` itself suggests "name.808" when a handle is taken.
    static func isReservedHandle(_ handle: String) -> Bool {
        let compact = handle.filter { $0 != "." && $0 != "_" && $0 != "-" }
        if reservedHandles.contains(compact) { return true }
        // Words: letter runs, plus "808" wherever it appears as a number.
        // Other numbers are dropped.
        var words: [String] = []
        var letters = ""
        var digits = ""
        func flush() {
            if !letters.isEmpty { words.append(letters); letters = "" }
            if !digits.isEmpty { if digits.contains("808") { words.append("808") }; digits = "" }
        }
        for c in handle {
            if c.isLetter {
                if !digits.isEmpty { flush() }
                letters.append(c)
            } else if c.isNumber {
                if !letters.isEmpty { flush() }
                digits.append(c)
            } else {
                flush()
            }
        }
        flush()
        let reservedWords = reservedHandles.union(["meditate"])
        return !words.isEmpty && words.allSatisfy { reservedWords.contains($0) }
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
