// Cuts Otto out of a video generated on a plain white background (Runway)
// and writes HEVC with alpha, which AVPlayerLayer plays transparently.
//
//   swiftc -O -o /tmp/otto_key tools/otto_video_key.swift
//   /tmp/otto_key in.mp4 out.mov [previewDir] [--from N --to N] [--center-feet]
//
// --from / --to keep frames N..M only (a loop: pick two frames where the
// pose matches). --center-feet centres the crop on his feet rather than on
// the box around him, so a raised arm does not push his body off centre.
//
// Per frame: flood the white in from the border; remove enclosed white
// pockets with no near-black within 6 px (the gap between a raised paw and
// his head is one; an eye white sits by its pupil and stays); then un-mix the
// two pixels at the edge from the white, so no pale rim is left. The output
// is cropped to the union of his outline across the clip, plus a margin.
import AVFoundation
import VideoToolbox
import AppKit

var args = CommandLine.arguments
func flag(_ name: String) -> Int? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return Int(args[i + 1])
}
let fromFrame = flag("--from") ?? 0, toFrame = flag("--to") ?? Int.max
let centerFeet = args.contains("--center-feet")
args.removeAll { $0 == "--center-feet" }
let inURL = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2])
let previewDir = args.count > 3 ? args[3] : nil

func reader(_ asset: AVAsset) throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
    let track = asset.tracks(withMediaType: .video)[0]
    let r = try AVAssetReader(asset: asset)
    let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    r.add(o); r.startReading()
    return (r, o)
}

@inline(__always) func isWhite(_ b: UInt8, _ g: UInt8, _ r: UInt8) -> Bool {
    let mn = min(r, g, b), mx = max(r, g, b)
    return mn >= 228 && mx - mn <= 22
}

/// Returns straight-alpha RGBA (4 bytes/px) for one BGRA frame.
func key(_ px: UnsafePointer<UInt8>, w: Int, h: Int, stride: Int) -> [UInt8] {
    let n = w * h
    var white = [Bool](repeating: false, count: n)
    for y in 0..<h { for x in 0..<w {
        let p = px + y * stride + x * 4
        white[y * w + x] = isWhite(p[0], p[1], p[2])
    } }
    // Flood from the border.
    var bg = [Bool](repeating: false, count: n)
    var stack = [Int]()
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    while let i = stack.popLast() {
        if bg[i] || !white[i] { continue }
        bg[i] = true
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
    }
    // Near-black, grown by 6 px: an eye white is ringed by an antialiased
    // grey between it and the pupil, so it never quite touches black itself.
    var dark = [Bool](repeating: false, count: n)
    for y in 0..<h { for x in 0..<w {
        let p = px + y * stride + x * 4
        if max(p[0], p[1], p[2]) < 80 { dark[y * w + x] = true }
    } }
    for _ in 0..<6 {
        var grown = dark
        for i in 0..<n where !dark[i] {
            let x = i % w, y = i / w
            if (x > 0 && dark[i - 1]) || (x < w - 1 && dark[i + 1]) || (y > 0 && dark[i - w]) || (y < h - 1 && dark[i + w]) { grown[i] = true }
        }
        dark = grown
    }
    // Enclosed white pockets: gone unless they sit by near-black (an eye).
    var seen = bg
    for s in 0..<n where white[s] && !seen[s] {
        var comp = [Int](), q = [s]; seen[s] = true
        var touchesDark = false
        while let i = q.popLast() {
            comp.append(i)
            if dark[i] { touchesDark = true }
            let x = i % w, y = i / w
            for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1] where j >= 0 {
                if white[j] { if !seen[j] { seen[j] = true; q.append(j) } }

            }
        }
        if !touchesDark && comp.count > 12 { for i in comp { bg[i] = true } }
    }
    // Distance to background, up to 2, for the edge band.
    var near = [UInt8](repeating: 9, count: n)
    for i in 0..<n where bg[i] { near[i] = 0 }
    for pass in 1...2 {
        for i in 0..<n where near[i] == 9 {
            let x = i % w, y = i / w
            if (x > 0 && near[i - 1] == pass - 1) || (x < w - 1 && near[i + 1] == pass - 1) ||
               (y > 0 && near[i - w] == pass - 1) || (y < h - 1 && near[i + w] == pass - 1) { near[i] = UInt8(pass) }
        }
    }
    var out = [UInt8](repeating: 0, count: n * 4)
    for i in 0..<n where !bg[i] {
        let p = px + (i / w) * stride + (i % w) * 4
        var r = Double(p[2]), g = Double(p[1]), b = Double(p[0]), a = 1.0
        if near[i] <= 2 {
            // Un-mix from white: his darkest edge fur is about 150 at its
            // lightest channel, so a pixel that pale is half white.
            let mn = min(r, g, b)
            a = min(1, max(0, (255 - mn) / (255 - 150)))
            if near[i] == 2 { a = max(a, 0.6) }
            if a > 0.01 {
                r = (r - (1 - a) * 255) / a; g = (g - (1 - a) * 255) / a; b = (b - (1 - a) * 255) / a
            }
        }
        out[i*4] = UInt8(max(0, min(255, r))); out[i*4+1] = UInt8(max(0, min(255, g)))
        out[i*4+2] = UInt8(max(0, min(255, b))); out[i*4+3] = UInt8(a * 255)
    }
    return out
}

let asset = AVURLAsset(url: inURL)
let track = asset.tracks(withMediaType: .video)[0]
let fps = track.nominalFrameRate

// Pass 1: key every frame and find the union box.
var frames = [[UInt8]](); var times = [CMTime]()
var W = 0, H = 0
var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0
do {
    let (r, o) = try reader(asset)
    var index = -1
    while let sb = o.copyNextSampleBuffer(), let buf = CMSampleBufferGetImageBuffer(sb) {
        index += 1
        if index < fromFrame || index > toFrame { continue }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        W = CVPixelBufferGetWidth(buf); H = CVPixelBufferGetHeight(buf)
        let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let k = key(base, w: W, h: H, stride: CVPixelBufferGetBytesPerRow(buf))
        CVPixelBufferUnlockBaseAddress(buf, .readOnly)
        for y in 0..<H { for x in 0..<W where k[(y * W + x) * 4 + 3] > 20 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        frames.append(k); times.append(CMSampleBufferGetPresentationTimeStamp(sb))
    }
    _ = r
}
let m = 12
if centerFeet {
    // His feet are symmetric whatever his arms do: the bottom 6% of his
    // outline, averaged over the clip, is where his body's centre line is.
    var centres = [Double]()
    let footTop = maxY - Int(Double(maxY - minY) * 0.06)
    for k in frames {
        var lo = Int.max, hi = 0
        for y in footTop...maxY { for x in 0..<W where k[(y * W + x) * 4 + 3] > 128 { lo = min(lo, x); hi = max(hi, x) } }
        if hi > lo { centres.append(Double(lo + hi) / 2) }
    }
    let c = Int(centres.reduce(0, +) / Double(max(centres.count, 1)))
    let half = max(c - minX, maxX - c)
    print("feet centre \(c), box centre \((minX + maxX) / 2)")
    minX = c - half; maxX = c + half
}
minX = max(0, minX - m); minY = max(0, minY - m); maxX = min(W - 1, maxX + m); maxY = min(H - 1, maxY + m)
var cw = maxX - minX + 1, ch = maxY - minY + 1
cw -= cw % 2; ch -= ch % 2
print("frames \(frames.count) at \(fps) fps, crop \(cw)x\(ch) at (\(minX),\(minY))")

// Pass 2: write HEVC with alpha.
try? FileManager.default.removeItem(at: outURL)
let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: cw, AVVideoHeightKey: ch,
    AVVideoCompressionPropertiesKey: [
        AVVideoQualityKey: 0.8,
        kVTCompressionPropertyKey_TargetQualityForAlpha as String: 0.9,
        kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: cw, kCVPixelBufferHeightKey as String: ch])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: times[0])
for (fi, k) in frames.enumerated() {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let dst = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
    let ds = CVPixelBufferGetBytesPerRow(buf)
    for y in 0..<ch { for x in 0..<cw {
        let s = ((y + minY) * W + (x + minX)) * 4
        let a = Double(k[s + 3]) / 255
        let d = dst + y * ds + x * 4
        d[0] = UInt8(Double(k[s + 2]) * a); d[1] = UInt8(Double(k[s + 1]) * a)
        d[2] = UInt8(Double(k[s]) * a); d[3] = k[s + 3]
    } }
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: times[fi])
    // Previews: every 24th frame over a magenta ground, where a pale rim shows.
    if let dir = previewDir, fi % 24 == 0 || fi == frames.count - 1 {
        var rgba = [UInt8](repeating: 0, count: cw * ch * 4)
        for y in 0..<ch { for x in 0..<cw {
            let s = ((y + minY) * W + (x + minX)) * 4, o = (y * cw + x) * 4
            let a = Double(k[s + 3]) / 255
            rgba[o] = UInt8(Double(k[s]) * a + 230 * (1 - a))
            rgba[o+1] = UInt8(Double(k[s+1]) * a + 40 * (1 - a))
            rgba[o+2] = UInt8(Double(k[s+2]) * a + 200 * (1 - a)); rgba[o+3] = 255
        } }
        let ctx = CGContext(data: &rgba, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/k\(String(format: "%03d", fi)).png"))
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("wrote \(outURL.path): \(writer.status == .completed ? "ok" : String(describing: writer.error))")
