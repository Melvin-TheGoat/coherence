import XCTest
@testable import Coherence

/// Locks the Watch's lightweight sound menu against the phone's real catalogs.
/// The Watch picker is names and ids only (audio lives on the phone), so the
/// one way it can break is silent drift: a preset added phone-side that the
/// wrist can't offer, or a menu id the phone can't resolve into sound.
final class SoundMenuTests: XCTestCase {

    private var phoneIDs: Set<String> {
        Set(FrequencyCatalog.all.map(\.id)
            + NatureCatalog.all.map(\.id)
            + GuidedCatalog.all.map(\.id))
    }

    func test_everyMenuIDResolvesOnThePhone() {
        for entry in SoundMenu.allEntries {
            XCTAssertTrue(phoneIDs.contains(entry.id),
                          "\(entry.id) is offered on the Watch but no phone catalog resolves it")
        }
    }

    func test_everyPhonePresetIsOfferedOnTheWatch() {
        let menuIDs = Set(SoundMenu.allEntries.map(\.id))
        for id in phoneIDs {
            XCTAssertTrue(menuIDs.contains(id),
                          "\(id) exists phone-side but the Watch picker doesn't offer it")
        }
    }

    /// A Watch-initiated session stamps its own Session.mode, so the menu's
    /// mode mapping must agree with the phone's — a mismatch would file wrist
    /// sessions under the wrong mode in stored history, the exact bug
    /// SoundCatalog.mode(for:) was created to fix.
    func test_modeAgreesWithThePhone() {
        XCTAssertEqual(SoundMenu.mode(for: nil), SoundCatalog.mode(for: nil))
        XCTAssertEqual(SoundMenu.mode(for: ""), SoundCatalog.mode(for: ""))
        for entry in SoundMenu.allEntries {
            XCTAssertEqual(SoundMenu.mode(for: entry.id), SoundCatalog.mode(for: entry.id),
                           "mode mismatch for \(entry.id)")
        }
    }
}
