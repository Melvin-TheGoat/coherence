#if DEBUG
import UIKit
import AVFoundation

/// Writes every stage of a selfie capture to disk so the rotation bug can be
/// looked at instead of guessed at.
///
/// Four fixes have failed (Aziz and Melvin, 2026-09-16/17), every one of them
/// reasoned from the outside, because the simulator has no camera and reading
/// the device's unified log needs root. This removes the guessing: one photo
/// leaves the raw file exactly as the camera produced it, each intermediate,
/// and the facts that decide which branch of the transform runs.
///
/// Pull it with:
/// ```
/// xcrun devicectl device copy from --device <udid> \
///   --domain-type appDataContainer --domain-identifier com.azizmahmud.808 \
///   --source Documents/SelfieDebug --destination <local dir>
/// ```
/// DEBUG only: the whole file is compiled out of a Release build, so nothing
/// here can ever write a person's face to disk on the App Store app.
enum SelfieDiagnostics {

    /// OFF unless asked for. The dump writes the person's face to disk, so it
    /// stays behind a switch now the bug it was built for is found: relaunch
    /// with `SELFIE_DEBUG=1` in the environment (or
    /// `SIMCTL_CHILD_SELFIE_DEBUG=1` on the simulator) to turn it back on.
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["SELFIE_DEBUG"] == "1"
    }

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SelfieDebug", isDirectory: true)
    }

    /// Everything about one capture. Called from the photo delegate.
    static func dump(raw: Data,
                     decoded: UIImage,
                     baked: UIImage,
                     final: UIImage,
                     connection: AVCaptureConnection?) {
        guard enabled else { return }
        let fm = FileManager.default
        // A fresh folder each time: the newest capture is the only one that
        // matters and a stale file would be read as evidence.
        try? fm.removeItem(at: folder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try? raw.write(to: folder.appendingPathComponent("1-raw-from-camera.jpg"))
        if let d = baked.jpegData(compressionQuality: 0.9) {
            try? d.write(to: folder.appendingPathComponent("2-orientation-baked.jpg"))
        }
        if let d = final.jpegData(compressionQuality: 0.9) {
            try? d.write(to: folder.appendingPathComponent("3-final-as-saved.jpg"))
        }

        var lines = ["SELFIE CAPTURE, \(Date())"]
        lines.append("")
        lines.append("RAW FILE FROM THE CAMERA: \(raw.count) bytes")
        lines.append("DECODED (UIImage(data:)):  \(decoded.facts)")
        lines.append("AFTER BAKING THE TAG:      \(baked.facts)")
        lines.append("FINAL (what gets saved):   \(final.facts)")
        lines.append("")
        if let c = connection {
            lines.append("CAPTURE CONNECTION at the moment of the shot:")
            lines.append("  videoRotationAngle = \(c.videoRotationAngle)")
            lines.append("  isVideoMirrored = \(c.isVideoMirrored)")
            lines.append("  automaticallyAdjustsVideoMirroring = \(c.automaticallyAdjustsVideoMirroring)")
        } else {
            lines.append("CAPTURE CONNECTION: none found")
        }
        lines.append("")
        lines.append("WHICH BRANCH RAN: \(branch(decoded: decoded, baked: baked))")
        try? lines.joined(separator: "\n")
            .write(to: folder.appendingPathComponent("facts.txt"), atomically: true, encoding: .utf8)
    }

    /// Which arm of `uprightMirroredSelfie` this capture took, named the same
    /// way the code reads, so the dump points straight at a line.
    private static func branch(decoded: UIImage, baked: UIImage) -> String {
        guard let cg = decoded.cgImage else { return "no CGImage (returned unchanged)" }
        if baked.size.height >= baked.size.width {
            return "A: the tag produces portrait, so the tag was applied"
        }
        if cg.height >= cg.width {
            return "B: the tag would make it landscape but the pixels are already portrait, so the tag was ignored"
        }
        return "C: landscape pixels and a landscape-leaving tag, so a quarter turn clockwise was applied"
    }
}

extension UIImage {
    var facts: String {
        let o: String
        switch imageOrientation {
        case .up: o = "up"
        case .down: o = "down"
        case .left: o = "left"
        case .right: o = "right"
        case .upMirrored: o = "upMirrored"
        case .downMirrored: o = "downMirrored"
        case .leftMirrored: o = "leftMirrored"
        case .rightMirrored: o = "rightMirrored"
        @unknown default: o = "unknown(\(imageOrientation.rawValue))"
        }
        let px = cgImage.map { "\($0.width)x\($0.height)" } ?? "no cgImage"
        let shape = cgImage.map { $0.height >= $0.width ? "portrait" : "LANDSCAPE" } ?? "?"
        return "orientation=\(o) scale=\(scale) size=\(Int(size.width))x\(Int(size.height)) pixels=\(px) (\(shape))"
    }
}
#endif
