import Foundation

/// Invite codes (Aziz, 2026-10-18; mockup "808 Invite Codes"). A friend who
/// joins with your code is your friend the moment they sign up: no search,
/// no request. The code is your yes, given in advance.
///
/// A code is up to five letters of the username, then five random
/// characters: `AZIZ-K7QX4`. Easy to read aloud and type, and it never
/// changes, so it can be posted anywhere. Five, not three (2026-10-18
/// review): the username half is public, so three left only 15,625 codes to
/// try for anyone who wanted to friend you without asking; five leave
/// nearly ten million.
///
/// Stored in canonical form, upper case with no dash (`AZIZK7QX4`), as the
/// name of an `InviteCode` record pointing at its owner's profile. Shown
/// with the dash before the last three (`display`). Pure Foundation, so the
/// rules are tested without CloudKit.
enum InviteCode {
    /// Characters a code is made of: no 0/O, 1/I/L, 2/Z, 5/S or 8/B, which
    /// read as each other on a phone screen or out loud.
    static let alphabet = Array("ACDEFGHJKMNPQRTUVWXY34679")
    static let suffixLength = 5
    static let maxPrefix = 5

    /// A new code for a person with this username.
    static func make<R: RandomNumberGenerator>(username: String, using rng: inout R) -> String {
        var prefix = String(username.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(maxPrefix))
        if prefix.isEmpty { prefix = "OTTO" }
        let suffix = String((0..<suffixLength).map { _ in alphabet.randomElement(using: &rng)! })
        return prefix + suffix
    }

    /// The canonical form of something a person typed or pasted, or nil when
    /// it cannot be a code. Spaces, dashes and case are forgiven; a pasted
    /// message works too when the code is its only word in capitals with a
    /// dash ("Use my code AZIZ-K7QX4 when you join").
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A whole message pasted in: take the code out of it, preferring one
        // written in capitals, the way 808's own message writes it, over a
        // word like "x-ray" earlier in the text.
        if trimmed.contains(where: \.isWhitespace) {
            let pattern = #"\b[A-Za-z]{1,5}-[A-Za-z0-9]{5}\b"#
            let found = (try? NSRegularExpression(pattern: pattern))?
                .matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
                .compactMap { Range($0.range, in: trimmed).map { String(trimmed[$0]) } } ?? []
            if let best = found.first(where: { $0 == $0.uppercased() }) ?? found.first {
                return normalize(best)
            }
        }
        let plain = trimmed.uppercased().filter { $0 != "-" && $0 != " " && $0 != "@" }
        guard (suffixLength + 1)...(maxPrefix + suffixLength) ~= plain.count,
              plain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return plain
    }

    /// `AZIZK7QX4` → `AZIZ-K7QX4`.
    static func display(_ code: String) -> String {
        guard code.count > suffixLength else { return code }
        let cut = code.index(code.endIndex, offsetBy: -suffixLength)
        return code[..<cut] + "-" + code[cut...]
    }

    /// Where an invite points: our own page, whose preview in Messages is
    /// Otto with "Meditate with me on 808" (website/invite.html), and which
    /// sends the reader on to the App Store with the invite campaign tag, so
    /// installs still show in App Store Connect. The App Store link itself
    /// previewed as the listing's old Apple Watch screenshot (2026-10-18).
    static let link = URL(string: "https://meditate808.com/invite")!

    /// The first message the share sheet sends. The code then goes again as
    /// a text of its own (`InviteCodeSheet`), so it can be copied in one tap.
    static func message(for code: String) -> String {
        "Meditate with me on 808 🧘 Use my invite code \(display(code)) when you join and we'll be friends right away.\n"
            + link.absoluteString
    }
}

/// An invite entered before the person has a profile: during onboarding, or
/// from Friends while iCloud is off. Kept until a profile exists, then
/// redeemed (`CommunityModel.redeemPendingInvite`). On this phone only.
struct PendingInvite: Codable, Equatable {
    let code: String
    let inviter: String
    let name: String
    let username: String

    /// "Aziz", or "@aziz" when there is no display name.
    var firstName: String {
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "@" + username : first
    }

    private static let key = "community.pendingInvite.v1"

    static var saved: PendingInvite? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(PendingInvite.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
