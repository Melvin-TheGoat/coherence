import XCTest
import CloudKit
@testable import Coherence

/// A friend's practice summary must be current after a refresh, not frozen at
/// whatever the app loaded first. Found on two phones (2026-10-01, CloudKit
/// Step 5): the friend meditated, and pulling to refresh on the other phone
/// showed the old numbers until 808 was closed and reopened, because the
/// profile cache only ever fetched people it did not already hold.
@MainActor
final class CommunityRefreshTests: XCTestCase {

    private let keys = [CommunityModel.pendingDeletionKey, CommunityModel.publishingPausedKey]
    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    private func model(_ db: MemoryCommunityDatabase, as user: String, handle: String,
                       sessions: @escaping () -> [(startedAt: Date, durationSec: Int)]) async -> CommunityModel {
        let m = CommunityModel(store: CommunityStore(database: db.acting(as: user)))
        m.allSessions = sessions
        await m.load()
        _ = await m.claim(handle, displayName: handle)
        return m
    }

    func test_aFriendsNewSessionShowsAfterARefreshAndOnTheirPage() async throws {
        let db = MemoryCommunityDatabase(user: "_aziz")
        var melvinSessions: [(startedAt: Date, durationSec: Int)] = []
        let aziz = await model(db, as: "_aziz", handle: "aziz", sessions: { [] })
        let melvin = await model(db, as: "_melvin", handle: "melvin", sessions: { melvinSessions })
        let melvinID = CommunityNames.profile(user: "_melvin")

        await aziz.request(melvinID)
        await melvin.refresh()
        await melvin.accept(CommunityNames.profile(user: "_aziz"))
        await aziz.refresh()
        await aziz.loadPerson(melvinID)
        XCTAssertEqual(aziz.person(melvinID)?.practice.totalSessions, 0)

        melvinSessions = [(startedAt: Date(), durationSec: 600)]
        await melvin.syncPracticeStats(force: true)

        await aziz.refresh()
        XCTAssertEqual(aziz.person(melvinID)?.practice.totalSessions, 1, "pull to refresh on Friends")

        melvinSessions.append((startedAt: Date(), durationSec: 300))
        await melvin.syncPracticeStats(force: true)

        await aziz.loadPerson(melvinID)
        XCTAssertEqual(aziz.person(melvinID)?.practice.totalSessions, 2, "opening or refreshing their page")
    }
}
