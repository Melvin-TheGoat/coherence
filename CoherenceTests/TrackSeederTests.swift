import XCTest
import SwiftData

/// Headless verification of Phase-5 track seeding: one track per type, idempotent,
/// and the type-filtered ordered query the setup lists use.
final class TrackSeederTests: XCTestCase {

    private func freshContext() -> ModelContext {
        ModelContext(Persistence.inMemory())
    }

    private func count(in ctx: ModelContext) -> Int {
        (try? ctx.fetch(FetchDescriptor<MeditationTrack>()))?.count ?? 0
    }

    /// Seeds exactly one guided, one frequency, one nature track — and no silence.
    func test_seedsOneTrackPerType() {
        let ctx = freshContext()
        TrackSeeder.seedIfNeeded(in: ctx)

        XCTAssertEqual(count(in: ctx), 3)
        XCTAssertEqual(TrackSeeder.tracks(ofType: .guided, in: ctx).count, 1)
        XCTAssertEqual(TrackSeeder.tracks(ofType: .frequency, in: ctx).count, 1)
        XCTAssertEqual(TrackSeeder.tracks(ofType: .nature, in: ctx).count, 1)

        // Guided carries its own duration; frequency/nature defer to the setup picker.
        XCTAssertEqual(TrackSeeder.tracks(ofType: .guided, in: ctx).first?.durationSec, 600)
        XCTAssertNil(TrackSeeder.tracks(ofType: .frequency, in: ctx).first?.durationSec)
    }

    /// Seeding twice does not duplicate.
    func test_seedIsIdempotent() {
        let ctx = freshContext()
        TrackSeeder.seedIfNeeded(in: ctx)
        TrackSeeder.seedIfNeeded(in: ctx)
        XCTAssertEqual(count(in: ctx), 3)
    }

    /// The type query returns only active tracks of that type, ordered by sortOrder.
    func test_tracksOfTypeFiltersActiveAndOrders() {
        let ctx = freshContext()
        ctx.insert(MeditationTrack(type: TrackType.nature.rawValue, title: "B", audioURL: "b", sortOrder: 2))
        ctx.insert(MeditationTrack(type: TrackType.nature.rawValue, title: "A", audioURL: "a", sortOrder: 1))
        ctx.insert(MeditationTrack(type: TrackType.nature.rawValue, title: "Hidden", audioURL: "h", isActive: false))
        ctx.insert(MeditationTrack(type: TrackType.frequency.rawValue, title: "Freq", audioURL: "f"))
        try? ctx.save()

        let nature = TrackSeeder.tracks(ofType: .nature, in: ctx)
        XCTAssertEqual(nature.map(\.title), ["A", "B"])   // active only, sortOrder asc
    }
}
