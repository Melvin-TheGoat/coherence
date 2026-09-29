// Turns a generated full-screen clip (Higgsfield, Runway) into what the app
// plays behind a screen: cropped to the phone's shape, retimed to 20 fps,
// H.264. For the clips `OttoClip(fills: true)` plays edge to edge
// (otto-seasons, otto-life-moments). A clip of Otto ALONE on white goes
// through otto_video_key.swift instead, which keys him out.
//
//   swiftc -O -o /tmp/clip_fill tools/clip_fill.swift
//   /tmp/clip_fill in.mp4 out.mov [--from 0 --to 4.85] [--width 650 --height 1416]
//
// Why these choices, each learned on an earlier clip:
//   * 20 fps, because 24 does not divide a 60 Hz refresh and the frames are
//     then held unevenly (the "glitching"). Output frame k takes the source
//     frame nearest k/20 s, so a 24 fps source drops one frame in six and
//     plays at its own speed.
//   * 650 x 1416 is the phone's shape (an iPhone 17 Pro is 402 x 874 pt), the
//     centre of the source cut to it, so the clip's framing on screen is the
//     framing the screens' words were placed against.
//   * `--patch-from T --patch-circle cx,cy,r --patch-last N` lays a circle
//     of the source frame at T seconds (source pixels, y from the top) over
//     the last N output frames. For otto-seasons: the clock's hands spin to
//     the clip's last frame, so every late frame is motion-blurred, and the
//     screen holds that last frame (Melvin, 2026-09-27: "it ends with the
//     clock blurry"). The clock is still for the first second, and the
//     camera is locked, so its sharp face drops straight onto the ending
//     and the hands stop. Feathered 3 px so the rim leaves no seam.
//   * `--end-still PATH --end-frames N` dissolves the last N output frames
//     into a still the same size as the source, and ends on it, so the
//     screen holds the still. For otto-seasons (Melvin, 2026-09-29: "the
//     ending screen is still blurry like the background"): the seasons race
//     to the last frame, so the mountains, meadow and clock are all smeared
//     there, and the patch above only fixed the clock. The still is that
//     frame redrawn sharp (Higgsfield, GPT Image 2.5 from the 4.85 s frame)
//     and colour-matched to it, `mockups/otto-clock/end-sharp.png`. The
//     dissolve reads as the picture coming into focus.
//   * It prints which source frames are identical to the one before. A
//     REGULAR pattern (one in every four, say) is a generator padding its
//     frame rate, a stutter to fix before shipping (CLAUDE.md, "CHECK EVERY
//     RUNWAY CLIP FOR A BUILT-IN STUTTER"). Runs clustered together are only
//     stillness: both Higgsfield clips of 2026-09-27 showed runs where Otto
//     sits calm, and dropping them would have hurried exactly those moments.
import AVFoundation
import CoreImage
import Foundation

var args = CommandLine.arguments
func option(_ name: String) -> Double? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return Double(args[i + 1])
}
let from = option("--from") ?? 0
let to = option("--to") ?? .greatestFiniteMagnitude
let outW = Int(option("--width") ?? 650), outH = Int(option("--height") ?? 1416)
let fps = 20.0
let patchFrom = option("--patch-from")
let patchLast = Int(option("--patch-last") ?? 0)
var patchCircle: (x: Double, y: Double, r: Double)?
if let i = args.firstIndex(of: "--patch-circle"), i + 1 < args.count {
    let v = args[i + 1].split(separator: ",").compactMap { Double($0) }
    if v.count == 3 { patchCircle = (v[0], v[1], v[2]) }
    args.removeSubrange(i...(i + 1))
}
var endStill: CIImage?
if let i = args.firstIndex(of: "--end-still"), i + 1 < args.count {
    endStill = CIImage(contentsOf: URL(fileURLWithPath: args[i + 1]))
    args.removeSubrange(i...(i + 1))
}
let endFrames = Int(option("--end-frames") ?? 8)
guard args.count >= 3 else { print("clip_fill in out [--from s --to s]"); exit(1) }
let inURL = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2])

let asset = AVURLAsset(url: inURL)
let sem = DispatchSemaphore(value: 0)
Task {
    let track = try await asset.loadTracks(withMediaType: .video).first!
    let natural = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let duration = CMTimeGetSeconds(try await asset.load(.duration))
    let end = min(to, duration)

    // The patch's source frame, when asked for, decoded on its own.
    var patchImage: CIImage?
    if let t = patchFrom {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        gen.appliesPreferredTrackTransform = true
        patchImage = CIImage(cgImage: try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image)
    }

    // Every source frame in the range, decoded once.
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    var frames: [(t: Double, image: CIImage)] = []
    while let sample = output.copyNextSampleBuffer() {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        guard t >= from - 0.05, t <= end + 0.05, let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
        // Copy out of the reader's pool before it recycles the buffer.
        let image = CIImage(cvPixelBuffer: pb).transformed(by: transform)
        let ctx = CIContext()
        let cg = ctx.createCGImage(image, from: image.extent)!
        frames.append((t, CIImage(cgImage: cg)))
    }
    guard !frames.isEmpty else { print("no frames in range"); exit(1) }
    let size = transform.isIdentity ? natural : frames[0].image.extent.size

    // The centre of the source, cut to the output's shape, then scaled.
    let aspect = Double(outW) / Double(outH)
    var crop = CGRect(origin: .zero, size: size)
    if size.width / size.height > aspect {
        let w = size.height * aspect
        crop = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
    } else {
        let h = size.width / aspect
        crop = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
    let scale = Double(outW) / crop.width

    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: outW, AVVideoHeightKey: outH,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000,
                                          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let ctx = CIContext()

    // Which source frames are identical to the one before (mean change under
    // half a level). Reported, never dropped: see the header.
    var repeatAt: [Int] = []
    for j in 1..<frames.count {
        let a = frames[j - 1].image, b = frames[j].image
        let diff = a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b])
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: a.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(diff, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: nil)
        if Int(px[0]) + Int(px[1]) + Int(px[2]) == 0 { repeatAt.append(j) }
    }

    let count = Int(((end - from) * fps).rounded(.down)) + 1
    for k in 0..<count {
        let want = from + Double(k) / fps
        let i = frames.indices.min { abs(frames[$0].t - want) < abs(frames[$1].t - want) }!
        var source = frames[i].image
        if let patchImage, let c = patchCircle, k >= count - patchLast {
            // CIImage counts y from the bottom.
            let centre = CIVector(x: c.x, y: source.extent.height - c.y)
            let mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": centre, "inputRadius0": c.r - 3, "inputRadius1": c.r,
                "inputColor0": CIColor.white, "inputColor1": CIColor.clear])!.outputImage!
                .cropped(to: source.extent)
            source = patchImage.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: source, kCIInputMaskImageKey: mask])
        }
        if var still = endStill, k >= count - endFrames {
            // Eased in over the last frames, fully the still on the last one.
            let x = Double(k - (count - endFrames) + 1) / Double(endFrames)
            let w = x * x * (3 - 2 * x)
            still = still.transformed(by: CGAffineTransform(
                scaleX: source.extent.width / still.extent.width,
                y: source.extent.height / still.extent.height))
            source = still.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: w)])
                .composited(over: source)
        }
        let image = source
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        ctx.render(image, to: pb!, bounds: CGRect(x: 0, y: 0, width: outW, height: outH),
                   colorSpace: CGColorSpaceCreateDeviceRGB())
        adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(k), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { print("write failed: \(String(describing: writer.error))"); exit(1) }

    print(String(format: "%@: %d frames at 20 fps (%.2f s), from %.2f to %.2f s, %d source frames",
                 outURL.lastPathComponent, count, Double(count) / fps, from, end, frames.count))
    print("identical to the frame before:", repeatAt.map(String.init).joined(separator: " "))
    sem.signal()
}
sem.wait()
