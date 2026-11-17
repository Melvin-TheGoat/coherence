#if DEBUG
import UIKit

/// Stand-in frames for the simulator, which has no camera: a room whose light
/// moves from morning to dusk while a figure sits still, so the whole
/// timelapse pipeline (reel, clip, page, share) can be checked without a
/// phone. Capture itself can only be checked on a phone.
@MainActor
enum SyntheticReel {
    private static var filming: (id: UUID, started: Date)?

    static func start(for id: UUID, plannedSeconds: Double?) {
        filming = (id, Date())
    }

    /// About one frame per second filmed, at least 30, at most 240.
    static func end() async -> [URL] {
        guard let filming else { return [] }
        self.filming = nil
        let seconds = Date().timeIntervalSince(filming.started)
        return await frames(for: filming.id, count: min(240, max(30, Int(seconds))))
    }

    static func frames(for id: UUID, count: Int) async -> [URL] {
        let dir = TimelapseRecorder.reelDir(for: id)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return await Task.detached(priority: .userInitiated) {
            (0..<count).compactMap { i -> URL? in
                let url = dir.appendingPathComponent(String(format: "f-%06d.jpg", i))
                guard let data = frame(Double(i) / Double(max(count - 1, 1))).jpegData(compressionQuality: 0.7),
                      (try? data.write(to: url)) != nil else { return nil }
                return url
            }
        }.value
    }

    /// One still, `t` from 0 (morning) to 1 (dusk).
    nonisolated static func frame(_ t: Double) -> UIImage {
        let size = CGSize(width: TimelapseCamera.frameWidth, height: TimelapseCamera.frameHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            let top = UIColor(hue: 0.58 - 0.5 * t, saturation: 0.35 + 0.2 * t, brightness: 0.95 - 0.45 * t, alpha: 1)
            let bottom = UIColor(hue: 0.1, saturation: 0.25 + 0.3 * t, brightness: 0.9 - 0.4 * t, alpha: 1)
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // A window's patch of light, sliding across the wall.
            UIColor.white.withAlphaComponent(0.22 * (1 - t)).setFill()
            c.fill(CGRect(x: 80 + 420 * t, y: 220, width: 200, height: 320))
            // The floor.
            UIColor(red: 0.62, green: 0.5, blue: 0.4, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 920, width: size.width, height: size.height - 920))
            // Someone sitting still: a cushion, a body, a head.
            UIColor(red: 0.35, green: 0.45, blue: 0.38, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 200, y: 930, width: 320, height: 90))
            UIColor(red: 0.25, green: 0.22, blue: 0.24, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 250, y: 640, width: 220, height: 320), cornerRadius: 90).fill()
            UIColor(red: 0.85, green: 0.7, blue: 0.6, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 300, y: 520, width: 120, height: 140))
        }
    }
}
#endif
