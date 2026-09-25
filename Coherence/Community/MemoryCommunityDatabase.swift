#if DEBUG
import Foundation
import CloudKit
import UIKit
import AVFoundation

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
    /// A soft two-tone image standing in for a selfie or a video's poster
    /// frame, so seeded posts have something to draw. `aspect` (width /
    /// height) varies across the demo media, so the strip's "keep the
    /// original aspect ratio" rule is actually exercised on review rather
    /// than every tile happening to be the same shape.
    static func fakeSelfie(_ top: UIColor, _ bottom: UIColor, aspect: Double = 0.75) -> URL? {
        let size = CGSize(width: 900, height: (900 / aspect).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return PostPhoto.prepare(image)
    }

    /// A real photo for a seeded post, so reviewing the feed shows what posts
    /// will look like rather than blank gradients (Melvin, 2026-09-25: "can
    /// we use actual pictures instead of these weird like blank photos").
    /// From `Coherence/Community/DemoPhotos`, each cropped to its post's
    /// shape: Unsplash License photos by Caleb George (roof), Chris Liu-Beers
    /// (window), Kenneth Thewissen (field), Dominik Martin (tea), Ilham
    /// Rahmansyah (feet), Philipp Reiner (sunrise) and Schicka (lily), via
    /// Lorem Picsum. The files ship in every build (about 350 KB); only this
    /// DEBUG seed reads them.
    static func demoPhoto(_ name: String) -> UIImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    }

    /// A real three-second clip: the photo slowly zooming in, or when there
    /// is no photo, the gradient with a light drifting across it. It used
    /// to be four bytes, which the viewer showed as a broken video, so a
    /// review of the demo read as a playback bug.
    private static func fakeVideo(_ top: UIColor, _ bottom: UIColor, aspect: Double,
                                  photo: CGImage? = nil) async -> URL? {
        let width = 480, height = Int((480 / aspect / 2).rounded()) * 2
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-video-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let space = CGColorSpaceCreateDeviceRGB()
        let ground = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        let light = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 0.3).cgColor,
                                                            UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        let frames = 45, fps: Int32 = 15
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 5_000_000) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let t = CGFloat(i) / CGFloat(frames - 1)
                if let photo {
                    let zoom = 1 + 0.08 * t
                    let w = CGFloat(width) * zoom, h = CGFloat(height) * zoom
                    ctx.draw(photo, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2,
                                               width: w, height: h))
                } else {
                    // Quartz's y runs up, so the top colour starts at y = height.
                    ctx.drawLinearGradient(ground, start: CGPoint(x: 0, y: height), end: .zero, options: [])
                    let centre = CGPoint(x: CGFloat(width) * (0.15 + 0.7 * t), y: CGFloat(height) * 0.5)
                    ctx.drawRadialGradient(light, startCenter: centre, startRadius: 0, endCenter: centre,
                                           endRadius: CGFloat(min(width, height)) * 0.45, options: [])
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    /// One or several items for a seeded post, mixing photos and videos so
    /// the feed's strip can be reviewed with 1, 3, and a mixed set (Melvin,
    /// 2026-09-23). `spec` is (demo photo, top colour, bottom colour, aspect, isVideo); the
    /// gradient only stands in when the photo cannot load.
    static func media(_ spec: [(String?, UIColor, UIColor, Double, Bool)]) async -> [CommunityStore.DraftMedia] {
        var items: [CommunityStore.DraftMedia] = []
        for (name, top, bottom, aspect, isVideo) in spec {
            let photo = name.flatMap(demoPhoto)
            guard let poster = photo.flatMap(PostPhoto.prepare) ?? fakeSelfie(top, bottom, aspect: aspect) else { continue }
            if isVideo {
                guard let video = await fakeVideo(top, bottom, aspect: aspect, photo: photo?.cgImage) else { continue }
                items.append(.init(kind: .video, aspect: aspect, fileURL: video, posterURL: poster))
            } else {
                items.append(.init(kind: .photo, aspect: aspect, fileURL: poster, posterURL: poster))
            }
        }
        return items
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
        // One photo (the ordinary case).
        let melvinPost = try? await melvin.post(.init(minutes: 14, streak: 9, technique: "Slow breathing",
                                                       caption: "Cold enough to see my breath.",
                                                       media: media([("demo-feed-roof", UIColor(red: 0.24, green: 0.35, blue: 0.42, alpha: 1), UIColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 1), 0.75, false)]),
                                                       practicedAt: Date().addingTimeInterval(-3_600),
                                                       title: "Roof before work", sound: "Rain"))
        // Three photos, different aspect ratios, so the strip's "shrink to
        // one height, never crop" rule is exercised across shapes.
        _ = try? await melvin.post(.init(minutes: 25, streak: 8, technique: "Guided",
                                          caption: "", media: media([
                                            ("demo-feed-window", UIColor(red: 0.17, green: 0.14, blue: 0.10, alpha: 1), UIColor(red: 0.42, green: 0.31, blue: 0.13, alpha: 1), 0.75, false),
                                            ("demo-feed-field", UIColor(red: 0.20, green: 0.24, blue: 0.28, alpha: 1), UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1), 1.33, false),
                                            ("demo-feed-tea", UIColor(red: 0.30, green: 0.28, blue: 0.20, alpha: 1), UIColor(red: 0.55, green: 0.48, blue: 0.32, alpha: 1), 1.0, false),
                                          ]),
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
        // A phone sit: no media, so the feed reviews "a post with no media
        // shows no strip".
        _ = try? await sam.post(.init(minutes: 8, streak: 1, technique: "Silence",
                                      caption: "", practicedAt: Date().addingTimeInterval(-7_200),
                                      title: "Quick sit", sound: "Silence"))

        db.user = "_demo_me"
        try? await me.accept(CommunityNames.profile(user: "_demo_melvin"))
        try? await me.sendRequest(to: CommunityNames.profile(user: "_demo_lena"))
        if let melvinPost { try? await me.react(to: melvinPost.id) }
        // A mix of photos and a video, so the strip's play glyph and the
        // viewer's mixed paging both get a real post to open.
        _ = try? await me.post(.init(minutes: 18, streak: 4, technique: "Counting",
                                      caption: "", media: media([
                                        ("demo-feed-feet", UIColor(red: 0.30, green: 0.22, blue: 0.24, alpha: 1), UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1), 0.75, false),
                                        ("demo-feed-sunrise", UIColor(red: 0.18, green: 0.26, blue: 0.22, alpha: 1), UIColor(red: 0.08, green: 0.14, blue: 0.11, alpha: 1), 1.78, true),
                                        ("demo-feed-lily", UIColor(red: 0.34, green: 0.28, blue: 0.40, alpha: 1), UIColor(red: 0.14, green: 0.11, blue: 0.20, alpha: 1), 0.75, false),
                                      ]),
                                      practicedAt: Date().addingTimeInterval(-86_400 * 2),
                                      title: "Morning session", sound: "Silence"))
        return me
    }
}
#endif
