import XCTest
@testable import Coherence

/// The waitlist request is the first personal data the app sends anywhere.
/// These pin exactly what leaves the phone, because the privacy manifest, the
/// App Privacy labels and the policy all promise "the email, and nothing else".
final class WaitlistClientTests: XCTestCase {

    func test_bodyCarriesExactlyTheFourKeys() throws {
        let data = WaitlistClient.body(email: "  someone@example.com ", appVersion: "1.0.2")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["token", "email", "source", "app_version"])
        XCTAssertEqual(json["email"], "someone@example.com", "whitespace must be trimmed")
        XCTAssertEqual(json["source"], "app")
        XCTAssertEqual(json["app_version"], "1.0.2")
        XCTAssertEqual(json["token"], WaitlistClient.token)
    }

    func test_plausibleAddressesPass() {
        for ok in ["a@b.co", "first.last@example.com", "x+tag@mail.example.org", " padded@example.com "] {
            XCTAssertTrue(WaitlistClient.isPlausible(ok), ok)
        }
    }

    /// The screen enables its button on "contains @ and .", which accepts all
    /// of these. None should be sent.
    func test_halfTypedAddressesAreNotSent() {
        for bad in ["@.", "a@.", "a@b.", ".@b", "a.b@", "a@@b.co", "a b@c.co", "no-at.example.com"] {
            XCTAssertFalse(WaitlistClient.isPlausible(bad), bad)
        }
    }

    /// Analytics must never see an email. The client is its own path; this
    /// guards the tempting shortcut of adding the address to an event.
    func test_analyticsSourceNeverMentionsAnEmailProperty() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Coherence/Analytics/Analytics.swift"),
                                encoding: .utf8)
        XCTAssertFalse(source.lowercased().contains("\"email\""),
                       "an email property in Analytics would send personal data to PostHog")
    }
}
