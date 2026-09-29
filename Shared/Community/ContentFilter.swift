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
        // "fuk" is the spelling people reach for when "fuck" is refused
        // (Melvin, 2026-09-29, a reviewer's bypass); as a stem inside a
        // handle it would catch Fukuda and Fukushima, so it lives here.
        "fuck", "fuk", "fucker", "fucking", "motherfucker", "cunt", "twat", "bitch", "whore", "slut",
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
    /// list of unambiguous STEMS anywhere inside it.
    ///
    /// **Second pass, same day, after a reviewer ran real names through it.**
    /// The first version blocked Thai names ending in -porn, Yoshiteru,
    /// Riddick, Glasscock, Slutsky, Fagg and "crush_it", and let "fvckyou",
    /// "ni99er" and "applesupport" through. What changed, and why:
    /// - A stem is looked for inside each part of the handle between dots
    ///   and underscores, never across one: "crush_it" is two words, and
    ///   joining them manufactured "shit". Parts of one or two letters are
    ///   joined back up, so "f_u_c_k" is still one word.
    /// - An allowed name exempts a stem only where the stem sits INSIDE it,
    ///   so a name next to a slur never hides the slur.
    /// - "porn" is no longer a stem (it ends hundreds of Thai names); its
    ///   compounds are, and the word alone is still caught whole.
    /// - "shit" between vowels is a name (Yamashita, Yoshiteru, Ishitsuka).
    /// - "oo" is no longer squeezed to "o" (Poornima is not "pornima").
    /// - v reads as u, q as g, and 9 or 6 as g, but only between letters, so
    ///   a birth year ("dani1990", "jenni99") never becomes a slur.
    public static func checkHandle(_ raw: String) -> HandleVerdict {
        var handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if handle.hasPrefix("@") { handle.removeFirst() }
        handle = handle.folding(options: .diacriticInsensitive, locale: nil)
        if isReservedHandle(handle) { return .reserved }
        for part in handleParts(handle) {
            for variant in handleVariants(part) where containsStem(variant.text, squeezed: variant.squeezed) {
                return .blocked
            }
        }
        return check(withoutAllowedWords(handle)) == .blocked ? .blocked : .ok
    }

    /// Stems no ordinary word or name contains, outside the names in
    /// `handleAllowed`. Chosen short on purpose: each is a slur, an explicit
    /// term or the strongest profanity. "twat" was tried and left out: it
    /// sits inside saltwater, sweetwater and outwatch, and the whole-word
    /// rule still catches it alone. "fuk" is left to the whole-word rule for
    /// the same reason (Fukuda, Fukushima).
    static let handleStems: [String] = [
        "fuck", "phuck", "cunt", "nigg", "nlgg", "faggot", "fagot",
        "porno", "pornhub", "pornstar", "shit", "dick", "cock", "pussy",
        "whore", "slut", "bitch", "biatch", "rapist", "nazi", "hitler", "kkk",
    ]

    /// Real words and names that contain a stem. A stem found inside one of
    /// these is not counted; the same stem anywhere else in the handle still
    /// is.
    static let handleAllowed: [String] = [
        // cock
        "shuttlecock", "weathercock", "hitchcock", "cockatiel", "cockroach", "woodcock",
        "cockatoo", "cocktail", "gamecock", "stopcock", "peacock", "hancock", "babcock",
        "cockpit", "cockburn", "cocker", "cockney", "cockle", "cockapoo",
        "alcock", "adcock", "laycock", "pocock", "silcock", "simcock", "willcock", "maycock",
        "glasscock", "pidcock", "moorcock", "leacock", "wilcock", "hiscock", "haycock",
        "heathcock", "hedgecock", "allcock", "handcock", "meacock", "cockrell", "cockrum",
        "cockayne", "cocking", "cockcroft", "shinnecock",
        // dick
        "dickerson", "dickinson", "dickens", "dickson", "dickey", "dickie", "benedick",
        "riddick", "reddick", "braddick", "maddick", "dickman", "dickel", "dickert",
        "dickstein", "dicko",
        // shit: the mushroom and Shia Islam; Indian, Nepali, Nigerian,
        // Ethiopian and Chinese names that start with it or follow a
        // consonant. Between vowels needs no entry (`shitBetweenVowels`).
        "shiitake", "shitake", "shiite", "kshiti", "ikshit", "akshit", "arshit", "ishith",
        "shital", "shitara", "shittu", "shitole", "shitaye", "shitanshu", "shitij",
        "shiting", "shitong", "shitao", "shitian", "shitou",
        // slut
        "slutsk", "sluter",
        // cunt, nigg, rapist
        "scunthorpe", "niggl", "niggard", "snigger", "therapist",
        // nazi
        "ashkenazi", "anazi", "nazia", "nazir", "nazim", "nazif", "nazih", "nazish",
        "naziya", "nazik", "nazil", "nazion",
    ]

    /// Whole words of a handle the whole-word rule would otherwise refuse
    /// because squeezing their double letter makes a listed word ("Fagg", an
    /// English surname, squeezes to "fag").
    static let handleAllowedWords: Set<String> = ["fagg"]

    /// Each allowed word as written, for the variants read as written, and as
    /// `handleVariants` squeezes it ("shiitake" is read as "shitake"), for
    /// the squeezed ones. Kept apart: the squeezed Shiite is "shite", which
    /// must stay blocked when somebody types it.
    private static let allowedAsWritten: [[Character]] = handleAllowed.map { Array($0) }
    private static let allowedSqueezed: [[Character]] = Array(Set(handleAllowed.map(squeezedRuns))).map { Array($0) }

    /// Digits and symbols that stand in for a letter anywhere.
    private static let lookalike: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
                                                            "7": "t", "@": "a", "$": "s", "!": "i"]

    /// Where the stems are looked for: every part between dots, underscores
    /// and hyphens, plus each run of two or more one- and two-letter parts
    /// joined back into the word they spell ("f_u_c_k", "sh_it").
    static func handleParts(_ handle: String) -> [String] {
        let parts = handle.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" }).map(String.init)
        var out = parts
        var run: [String] = []
        func close() {
            if run.count > 1 { out.append(run.joined()) }
            run = []
        }
        for part in parts {
            if part.count <= 2 { run.append(part) } else { close() }
        }
        close()
        return out
    }

    /// One part read four ways: with look-alikes as letters ("sh1t", "fvck",
    /// "niqqa", "ni99er") and with every non-letter dropped ("fuck2you"),
    /// each also with runs squeezed ("fuuuck", "niiigger"). The squeeze takes
    /// a run of a, e, i or u to one letter and anything else to two, so a
    /// stem's own double letter survives, and so does the "oo" of Poornima.
    private static func handleVariants(_ part: String) -> [(text: [Character], squeezed: Bool)] {
        let chars = Array(part)
        var mapped: [Character] = []
        for (i, c) in chars.enumerated() {
            if c.isLetter {
                mapped.append(c == "v" ? "u" : c == "q" ? "g" : c)
            } else if let letter = lookalike[c] {
                mapped.append(letter)
            } else if c == "9" || c == "6", digitRunIsBetweenLetters(chars, at: i) {
                mapped.append("g")
            }
        }
        let stripped = chars.filter(\.isLetter)
        return [(mapped, false), (stripped, false),
                (Array(squeezedRuns(String(mapped))), true), (Array(squeezedRuns(String(stripped))), true)]
    }

    /// True when the digits around `i` have a letter on both sides: "ni99er"
    /// yes, the year in "dani1990" and the "99" ending "jenni99" no.
    private static func digitRunIsBetweenLetters(_ chars: [Character], at i: Int) -> Bool {
        var lo = i
        var hi = i
        while lo > 0, chars[lo - 1].isNumber { lo -= 1 }
        while hi < chars.count - 1, chars[hi + 1].isNumber { hi += 1 }
        return lo > 0 && hi < chars.count - 1 && chars[lo - 1].isLetter && chars[hi + 1].isLetter
    }

    private static func containsStem(_ text: [Character], squeezed: Bool) -> Bool {
        let safe = occurrences(of: squeezed ? allowedSqueezed : allowedAsWritten, in: text)
        for stem in handleStems {
            for found in occurrences(of: [Array(stem)], in: text) {
                if safe.contains(where: { $0.lowerBound <= found.lowerBound && found.upperBound <= $0.upperBound }) {
                    continue
                }
                if stem == "shit", shitBetweenVowels(text, found) { continue }
                return true
            }
        }
        return false
    }

    private static func occurrences(of words: [[Character]], in text: [Character]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for word in words where !word.isEmpty && word.count <= text.count {
            for start in 0...(text.count - word.count)
            where text[start..<(start + word.count)].elementsEqual(word) {
                out.append(start..<(start + word.count))
            }
        }
        return out
    }

    /// "shit" with a vowel before it and a vowel (or "s" and a vowel) after
    /// it is Japanese and Indian names: Yamashita, Yoshiteru, Ishitsuka,
    /// Mashiter, Ashita. At the start or end of a part, or after a
    /// consonant, it is the word: "shithead", "noshit", "bullshit".
    private static func shitBetweenVowels(_ text: [Character], _ found: Range<Int>) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        guard found.lowerBound > 0, vowels.contains(text[found.lowerBound - 1]),
              found.upperBound < text.count else { return false }
        let next = text[found.upperBound]
        if vowels.contains(next) { return true }
        return next == "s" && found.upperBound + 1 < text.count && vowels.contains(text[found.upperBound + 1])
    }

    private static func squeezedRuns(_ text: String) -> String {
        var out = ""
        var run = 0
        for c in text {
            if c == out.last { run += 1 } else { run = 1 }
            let limit = "aeiu".contains(c) ? 1 : 2
            if run <= limit { out.append(c) }
        }
        return out
    }

    /// The handle with every word in `handleAllowedWords` blanked, for the
    /// whole-word check.
    private static func withoutAllowedWords(_ handle: String) -> String {
        var out = ""
        var word = ""
        func flush() {
            out += handleAllowedWords.contains(word) ? " " : word
            word = ""
        }
        for c in handle {
            if c.isLetter { word.append(c) } else { flush(); out.append(c) }
        }
        flush()
        return out
    }

    /// Handles that would read as the app, its maker, or its staff.
    static let reservedHandles: Set<String> = [
        "808", "meditate808", "otto", "support", "admin", "administrator", "apple", "app",
        "official", "staff", "team", "moderator", "mod", "help", "helpdesk", "security", "root",
        "system", "lockout",
    ]

    private static let reservedWords = reservedHandles.union(["meditate"])

    /// Reserved when every word in it is made only of reserved words:
    /// "admin", "808_support", "otto.official", "apple_help", "admin42" (a
    /// number beside a reserved word adds nothing), "meditate_808", and the
    /// same glued together ("applesupport", "808helpdesk", "adminteam") or
    /// spelled with look-alikes ("supp0rt", "adm1n", "0tto"). A reserved
    /// word beside anything else is somebody's own name ("otto_k",
    /// "melvin808", "root_beer", "teamwork"), and `CreateProfileView` itself
    /// suggests "name.808" when a handle is taken.
    static func isReservedHandle(_ handle: String) -> Bool {
        readsAsReserved(handle) || readsAsReserved(lookalikeLetters(handle))
    }

    private static func readsAsReserved(_ handle: String) -> Bool {
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
        return !words.isEmpty && words.allSatisfy(isMadeOfReservedWords)
    }

    /// Whether a word splits entirely into reserved words ("applesupport" is
    /// apple + support; "appleseed" is not).
    private static func isMadeOfReservedWords(_ word: String) -> Bool {
        let chars = Array(word)
        guard !chars.isEmpty else { return false }
        var reachable = [Bool](repeating: false, count: chars.count + 1)
        reachable[0] = true
        for end in 1...chars.count {
            for start in 0..<end where reachable[start] && reservedWords.contains(String(chars[start..<end])) {
                reachable[end] = true
                break
            }
        }
        return reachable[chars.count]
    }

    /// Look-alike digits read as letters where they touch a letter ("0tto",
    /// "supp0rt"), so "808" itself stays a number.
    private static func lookalikeLetters(_ handle: String) -> String {
        let chars = Array(handle)
        return String(chars.enumerated().map { i, c -> Character in
            guard let letter = lookalike[c] else { return c }
            let touchesLetter = (i > 0 && chars[i - 1].isLetter) || (i + 1 < chars.count && chars[i + 1].isLetter)
            return touchesLetter ? letter : c
        })
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
