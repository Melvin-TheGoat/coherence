import XCTest
import UIKit
@testable import Coherence

/// A posted photo is capped at 1080 on its longest side and written as JPEG,
/// so a 12-megapixel camera shot does not become a 5 MB CloudKit asset per
/// post.
final class PostPhotoTests: XCTestCase {

    private func solid(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func test_largePhotoIsScaledToTheCap() {
        let out = PostPhoto.resized(solid(CGSize(width: 4032, height: 3024)))
        XCTAssertEqual(out.size.width, 1080, accuracy: 1)
        XCTAssertEqual(out.size.height, 810, accuracy: 1)
    }

    func test_smallPhotoIsLeftAlone() {
        let out = PostPhoto.resized(solid(CGSize(width: 600, height: 900)))
        XCTAssertEqual(out.size, CGSize(width: 600, height: 900))
    }

    func test_prepareWritesAReadableJPEG() throws {
        let url = try XCTUnwrap(PostPhoto.prepare(solid(CGSize(width: 2000, height: 2000))))
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG magic")
        XCTAssertLessThan(data.count, 600_000)
        XCTAssertEqual(UIImage(data: data)?.size.width, 1080)
    }
}
