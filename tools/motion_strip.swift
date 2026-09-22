// motion_strip: proves a short animation actually plays, from a simulator
// screen recording, on a Mac with no ffmpeg (2026-09-22, Otto's jiggle).
//
//   xcrun simctl io <sim> recordVideo --codec=h264 --force clip.mp4 &
//   (tap the thing), then: kill -INT %1
//   swiftc -O -o /tmp/motion_strip tools/motion_strip.swift
//   /tmp/motion_strip clip.mp4 strip.png <x> <y> <w> <h>
//
// The crop is in the recording's pixels (1206 x 2622 on an iPhone 17 Pro).
// It prints which frames moved against the first one inside the crop, then
// writes every second frame from just before the motion as one strip.
//
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Arguments: <video> <out.png> x y w h
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]); let out = URL(fileURLWithPath: args[2])
let crop = CGRect(x: Double(args[3])!, y: Double(args[4])!, width: Double(args[5])!, height: Double(args[6])!)
let asset = AVURLAsset(url: url)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
let duration = CMTimeGetSeconds(asset.duration)

func gray(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return buf
}
var frames: [(t: Double, img: CGImage, diff: Double)] = []
var base: [UInt8]? = nil
var t = 0.0
while t < duration {
    if let full = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
       let c = full.cropping(to: crop) {
        let g = gray(c, 60, 70)
        if base == nil { base = g }
        let d = zip(g, base!).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(g.count)
        frames.append((t, c, d))
    }
    t += 1.0 / 30.0
}
print(String(format: "video %.2fs, %d frames, full %dx%d", duration, frames.count,
             (try? gen.copyCGImage(at: .zero, actualTime: nil))?.width ?? 0, (try? gen.copyCGImage(at: .zero, actualTime: nil))?.height ?? 0))
let moving = frames.filter { $0.diff > 0.8 }
print("moving frames:", moving.map { String(format: "%.2f(%.1f)", $0.t, $0.diff) }.joined(separator: " "))
guard let first = moving.first else { print("NO MOTION"); exit(1) }
// A strip: the frame before the motion, then every 2nd frame through it.
let startIdx = max(0, (frames.firstIndex { $0.t == first.t } ?? 0) - 1)
let picks = Array(frames[startIdx...].enumerated().filter { $0.offset % 2 == 0 }.map(\.element).prefix(9))
let scale = 0.4
let cw = Int(crop.width * scale), ch = Int(crop.height * scale)
let ctx = CGContext(data: nil, width: cw * picks.count, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (i, f) in picks.enumerated() { ctx.draw(f.img, in: CGRect(x: i * cw, y: 0, width: cw, height: ch)) }
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
print("strip:", picks.map { String(format: "%.2f", $0.t) }.joined(separator: " "))
