#if DEBUG
import Foundation
import CloudKit
import UIKit

/// An in-memory public database: a dictionary of records keyed by name, the
/// way CloudKit's default zone is (so a name collision between types shows up
/// here too). `user` is who the caller is; tests and the demo swap it to act
/// as someone else. Used by `CommunityStoreTests` and by `PREVIEW_FRIENDS=1`,
/// so the tab can be looked at on a simulator with no iCloud account.
final class MemoryCommunityDatabase: CommunityDatabase {
    var user: String
    var records: [String: CKRecord] = [:]
    var saves = 0

    init(user: String) { self.user = user }

    func currentUserRecordName() async throws -> String { user }

    func save(_ record: CKRecord) async throws -> CKRecord {
        saves += 1
        records[record.recordID.recordName] = record
        return record
    }

    func create(_ record: CKRecord) async throws -> CKRecord {
        guard records[record.recordID.recordName] == nil else { throw CommunityError.alreadyExists }
        return try await save(record)
    }

    func fetch(_ recordName: String) async throws -> CKRecord? { records[recordName] }

    func query(_ query: CommunityQuery) async throws -> [CKRecord] {
        var hits = records.values.filter(query.matches)
        if let field = query.sortField {
            hits.sort {
                guard let a = $0[field] as? Date, let b = $1[field] as? Date else { return false }
                return query.ascending ? a < b : a > b
            }
        }
        return Array(hits.prefix(query.limit))
    }

    func delete(_ recordName: String) async throws { records[recordName] = nil }
}

/// A seeded tab for design review: me (@aziz, claimed), Melvin as a friend
/// with two posts, one incoming request, one sent request.
enum DemoCommunity {
    /// A soft two-tone image standing in for a selfie, so seeded posts obey
    /// the selfie rule.
    static func fakeSelfie(_ top: UIColor, _ bottom: UIColor) -> URL? {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return PostPhoto.prepare(image)
    }

    static func store() async -> CommunityStore {
        let db = MemoryCommunityDatabase(user: "_demo_me")
        let me = CommunityStore(database: db)
        // PREVIEW_FRIENDS=claim leaves me unclaimed so the first-run screen shows.
        if ProcessInfo.processInfo.environment["PREVIEW_FRIENDS"] != "claim" {
            try? await me.claimUsername("aziz", displayName: "Aziz")
        }

        db.user = "_demo_melvin"
        let melvin = CommunityStore(database: db)
        try? await melvin.claimUsername("melvin", displayName: "Melvin")
        try? await melvin.markFirstSession(at: Date().addingTimeInterval(-86_400 * 40))
        try? await melvin.sendRequest(to: CommunityNames.profile(user: "_demo_me"))
        let melvinPost = try? await melvin.post(.init(score: 81, minutes: 14, streak: 9, technique: "Slow breathing",
                                                       caption: "Cold enough to see my breath.",
                                                       photoURL: fakeSelfie(UIColor(red: 0.24, green: 0.35, blue: 0.42, alpha: 1), UIColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 1)),
                                                       practicedAt: Date().addingTimeInterval(-3_600),
                                                       title: "Roof before work", sound: "Rain"))
        _ = try? await melvin.post(.init(score: 64, minutes: 25, streak: 8, technique: "Guided",
                                          caption: "", photoURL: fakeSelfie(UIColor(red: 0.17, green: 0.14, blue: 0.10, alpha: 1), UIColor(red: 0.42, green: 0.31, blue: 0.13, alpha: 1)),
                                          practicedAt: Date().addingTimeInterval(-86_400 - 1_800),
                                          title: "Evening meditation", sound: "Guided"))

        db.user = "_demo_jordan"
        let jordan = CommunityStore(database: db)
        try? await jordan.claimUsername("jordan.k", displayName: "Jordan")
        try? await jordan.sendRequest(to: CommunityNames.profile(user: "_demo_me"))

        db.user = "_demo_lena"
        let lena = CommunityStore(database: db)
        try? await lena.claimUsername("lena", displayName: "Lena")

        // Sam: I asked, Sam accepted, Sam sat. The reward case.
        db.user = "_demo_sam"
        let sam = CommunityStore(database: db)
        try? await sam.claimUsername("sam_p", displayName: "Sam")

        db.user = "_demo_me"
        try? await me.sendRequest(to: CommunityNames.profile(user: "_demo_sam"))
        db.user = "_demo_sam"
        try? await sam.accept(CommunityNames.profile(user: "_demo_me"))
        try? await sam.markFirstSession(at: Date().addingTimeInterval(1))

        db.user = "_demo_me"
        try? await me.accept(CommunityNames.profile(user: "_demo_melvin"))
        try? await me.sendRequest(to: CommunityNames.profile(user: "_demo_lena"))
        if let melvinPost { try? await me.react(to: melvinPost.id) }
        _ = try? await me.post(.init(score: 72, minutes: 18, streak: 4, technique: "Counting",
                                      caption: "", photoURL: fakeSelfie(UIColor(red: 0.30, green: 0.22, blue: 0.24, alpha: 1), UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1)),
                                      practicedAt: Date().addingTimeInterval(-86_400 * 2),
                                      title: "Morning sit", sound: "Silence"))
        return me
    }
}
#endif
