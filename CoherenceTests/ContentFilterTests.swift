import XCTest
@testable import Coherence

final class ContentFilterTests: XCTestCase {

    func test_ordinaryMeditationTextPasses() {
        for ok in ["Roof before work. Cold enough to see my breath.",
                   "Hard as hell today, damn restless", "Scunthorpe sunrise sit",
                   "assessing my class schedule", "grapefruit and green tea first",
                   "Evening meditation", "I love this", "@jordan.k", "session 5 of 10",
                   "cocktail party later, needed this", "analysis paralysis gone"] {
            XCTAssertEqual(ContentFilter.check(ok), .ok, ok)
        }
    }

    func test_obviousAbuseIsBlocked() {
        for bad in ["fuck you", "you're a bitch", "kys", "send nudes"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_disguisedSpellingsAreBlocked() {
        for bad in ["F.U.C.K", "fvck", "f*ck", "fuuuuck", "b1tch", "f u c k", "k y s", "p0rn"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_anyBlockedFieldBlocksTheWhole() {
        XCTAssertEqual(ContentFilter.check(["Morning sit", "nice", "porn"]), .blocked)
        XCTAssertEqual(ContentFilter.check(["Morning sit", "", "nice"]), .ok)
    }

    // MARK: Usernames (2026-09-29, guideline 1.2)

    /// A handle is one word, so the whole-word rule could not see inside it:
    /// every one of these passed before the handle check existed.
    func test_handlesHidingAStemAreBlocked() {
        for bad in ["fuckyou", "bigdick", "cuntface", "pornstar", "shithead", "niggerxx",
                    "f_u_c_k", "sh1thead", "d1ck.pic", "hitler88", "kkk_member", "fuuuckyou",
                    "niiiggger", "bullshit", "noshit", "shitass", "b1tchplease", "wh0re",
                    "fuck2you", "f4gg0t", "shite", "nazi_guy"] {
            XCTAssertEqual(ContentFilter.checkHandle(bad), .blocked, bad)
        }
    }

    /// The whole-word rule still runs on a handle, so a listed word alone is
    /// caught even where no stem covers it.
    func test_handlesThatAreAListedWordAreBlocked() {
        for bad in ["twat", "b1tch", "@porn"] {
            XCTAssertEqual(ContentFilter.checkHandle(bad), .blocked, bad)
        }
    }

    /// Handles that would read as 808, Otto or their staff are never handed
    /// out, alone or combined only with each other or a number.
    func test_reservedHandles() {
        for handle in ["808", "meditate808", "otto", "support", "admin", "administrator", "apple",
                       "app", "official", "staff", "team", "moderator", "mod", "help", "security",
                       "root", "system", "lockout", "otto_808", "808.support", "admin42",
                       "apple_support", "meditate_808", "otto.official", "808team", "@Otto"] {
            XCTAssertEqual(ContentFilter.checkHandle(handle), .reserved, handle)
        }
    }

    /// Real words and names that contain a stem or a reserved word pass, and
    /// so do the "name.808" suggestions the claim screen makes itself.
    func test_innocentHandlesPass() {
        for ok in ["grape", "scunthorpe_fan", "peacock", "dickens", "cocktail", "therapist",
                   "hancock", "hitchcock", "cockatoo", "dickinson", "yamashita", "yoshito",
                   "ishita", "kshitij", "shiite", "shiitake", "nazia", "ashkenazi", "pornsak",
                   "niggle", "saltwater", "sweetwater", "poorness", "analyst", "document",
                   "cumberland", "night.owl", "melvin808", "melvin.808", "melvin_808",
                   "the808", "otto_k", "mod_squad", "root_beer", "happy", "teamwork",
                   "appleseed", "aziz", "jordan.k", "sam_p"] {
            XCTAssertEqual(ContentFilter.checkHandle(ok), .ok, ok)
        }
    }

    /// Free text keeps the whole-word rule: a caption is not a handle.
    func test_freeTextIsStillWholeWord() {
        XCTAssertEqual(ContentFilter.check("Scunthorpe sunrise, then a cocktail"), .ok)
        XCTAssertEqual(ContentFilter.check("analysis before the session"), .ok)
    }
}
