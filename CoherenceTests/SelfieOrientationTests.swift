import XCTest
@testable import Coherence

/// The selfie comes out upright, portrait, and mirrored, whatever the camera
/// tags it as.
///
/// Aziz, three builds running (2026-09-16/17): "the camera is still having
/// that rotating issue". The simulator has no camera, so this was guessed at
/// twice and wrong twice. The transform is pure, though, so it can be driven
/// through every orientation here instead, which is how the real fault was
/// finally found: AVFoundation can rotate the pixels to portrait via the
/// connection AND still tag the file as quarter-turned, and applying the tag
/// on top of upright pixels turns the shot on its side.
final class SelfieOrientationTests: XCTestCase {

    /// A portrait image with an unmistakable top-left mark, so a quarter turn
    /// or a mirror is visible in the pixels rather than only in the size.
    private func portrait(_ orientation: UIImage.Orientation = .up,
                          w: Int = 60, h: Int = 100) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let base = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w / 4, height: h / 4))   // top-left
        }
        guard orientation != .up, let cg = base.cgImage else { return base }
        return UIImage(cgImage: cg, scale: 1, orientation: orientation)
    }

    private func isWhite(_ image: UIImage, atX x: Int, y: Int) -> Bool {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let bpr = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        let offset = y * bpr + x * bpp
        guard offset + 2 < CFDataGetLength(data) else { return false }
        // Any channel near full is enough to tell the white corner from black.
        return ptr[offset] > 128 && ptr[offset + 1] > 128
    }

    /// Whatever it arrives as, a selfie leaves portrait. This screen is
    /// portrait only and front camera only, so a landscape result is wrong by
    /// definition.
    func test_everyOrientationComesOutPortrait() {
        let all: [UIImage.Orientation] = [.up, .down, .left, .right,
                                          .upMirrored, .downMirrored, .leftMirrored, .rightMirrored]
        for o in all {
            let out = portrait(o).uprightMirroredSelfie()
            XCTAssertGreaterThanOrEqual(out.size.height, out.size.width,
                                        "orientation \(o.rawValue) came out landscape")
            XCTAssertEqual(out.imageOrientation, .up,
                           "orientation \(o.rawValue) left a tag for someone else to misread")
        }
    }

    /// THE REGRESSION. Pixels already rotated upright by the capture
    /// connection, and tagged quarter-turned as well. The previous two builds
    /// swapped the target to landscape here and drew the shot on its side.
    func test_uprightPixelsTaggedAsQuarterTurnedAreNotRotatedAgain() {
        for tag in [UIImage.Orientation.right, .left, .rightMirrored, .leftMirrored] {
            let out = portrait(tag, w: 60, h: 100).uprightMirroredSelfie()
            XCTAssertEqual(out.size, CGSize(width: 60, height: 100),
                           "tag \(tag.rawValue) resized an already-upright selfie")
        }
    }

    /// A genuinely landscape bitmap (the sensor's own frame, no connection
    /// rotation) is turned upright rather than left on its side.
    func test_aLandscapeBitmapIsTurnedUpright() {
        let landscape = portrait(.right, w: 100, h: 60)
        let out = landscape.uprightMirroredSelfie()
        XCTAssertGreaterThan(out.size.height, out.size.width)
    }

    /// Mirrored, so the shot matches the preview the person was looking at.
    /// The mark starts top-left and must finish top-right.
    func test_theShotIsMirroredLikeThePreview() {
        let out = portrait(.up).uprightMirroredSelfie()
        let w = Int(out.size.width), h = Int(out.size.height)
        XCTAssertTrue(isWhite(out, atX: w - 4, y: 4), "the mark should have moved to the top right")
        XCTAssertFalse(isWhite(out, atX: 4, y: 4), "the mark should have left the top left")
        XCTAssertFalse(isWhite(out, atX: w - 4, y: h - 4), "it should not have flipped vertically too")
    }

    /// Mirroring twice is the identity, which is the cheap guard against a
    /// double flip creeping back in through `bakingOrientation`.
    func test_mirroringTwiceReturnsTheOriginal() {
        let once = portrait(.up).mirroredHorizontally()
        let twice = once.mirroredHorizontally()
        XCTAssertTrue(isWhite(twice, atX: 4, y: 4), "the mark should be back at the top left")
    }

    /// WHAT AZIZ'S iPHONE 17 PRO MAX ACTUALLY PRODUCES, pulled off the device
    /// on 2026-09-18 after four blind fixes had failed:
    ///
    ///     pixels 4032x3024 (landscape), orientation tag = down,
    ///     connection videoRotationAngle = 90, isVideoMirrored = false
    ///
    /// So `videoRotationAngle` did NOT rotate the pixels, and the tag is
    /// `.down` (a half turn), which leaves the frame landscape however it is
    /// applied. Every earlier version either applied the tag and kept a
    /// landscape image, or swapped the target and drew the shot on its side.
    /// None of the other tests here covered this combination, which is why it
    /// survived so long. The finished selfie must be portrait.
    func test_theRealDeviceCase_landscapePixelsTaggedDown() {
        let sensorFrame = portrait(.down, w: 4032, h: 3024)
        let out = sensorFrame.uprightMirroredSelfie()
        XCTAssertEqual(Int(out.size.width), 3024)
        XCTAssertEqual(Int(out.size.height), 4032)
        XCTAssertEqual(out.imageOrientation, .up)
    }

    /// The raw front sensor frame: landscape pixels, no tag worth the name.
    /// Melvin's phone, 2026-09-17. It must leave portrait, turned clockwise
    /// and then mirrored, which puts the frame's top-left mark back at the
    /// top-left of the selfie.
    func test_untaggedLandscapeSensorFrameIsTurnedUprightAndMirrored() {
        let raw = portrait(.up, w: 100, h: 60)      // landscape, white top-left
        let out = raw.uprightMirroredSelfie()
        XCTAssertEqual(Int(out.size.width), 60)
        XCTAssertEqual(Int(out.size.height), 100)
        XCTAssertEqual(out.imageOrientation, .up)
        XCTAssertTrue(isWhite(out, atX: 3, y: 3), "top-left should carry the mark")
        XCTAssertFalse(isWhite(out, atX: 56, y: 3), "top-right should not")
        XCTAssertFalse(isWhite(out, atX: 3, y: 96), "bottom-left should not")
    }
}
