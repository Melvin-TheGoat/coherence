import UIKit
import AVFoundation
import CoreImage
import os

/// Turns the kept stills into the clip, and the clip into the copy that
/// leaves the phone. `AVAssetWriter`, H.264, 30 fps, about 4 Mbps, portrait
/// 1080 by 1920. Silent: there is no audio track at all.
enum TimelapseWriter {
    private static let log = TimelapseCamera.log

    private static func settings() -> [String: Any] {
        [AVVideoCodecKey: AVVideoCodecType.h264,
         AVVideoWidthKey: TimelapseRule.outputWidth,
         AVVideoHeightKey: TimelapseRule.outputHeight,
         AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: TimelapseRule.bitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: TimelapseRule.fps,
         ]]
    }

    private static func adaptor(for input: AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
        AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: TimelapseRule.outputWidth,
            kCVPixelBufferHeightKey as String: TimelapseRule.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput) async {
        while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(4)) }
    }

    /// Writes `frames` (in order) into a clip as long as the rule says for a
    /// session of `sessionSeconds`. `progress` runs 0 to 1, frames written
    /// over frames needed.
    static func write(frames: [URL], sessionSeconds: Double, to out: URL,
                      progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            await writeDetached(frames: frames, sessionSeconds: sessionSeconds, to: out, progress: progress)
        }.value
    }

    private static func writeDetached(frames: [URL], sessionSeconds: Double, to out: URL,
                                      progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        try? FileManager.default.removeItem(at: out)
        guard let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings())
        input.expectsMediaDataInRealTime = false
        let adaptor = adaptor(for: input)
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else {
            log.error("startWriting: \(String(describing: writer.error), privacy: .public)")
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let needed = TimelapseRule.framesNeeded(forSessionSeconds: sessionSeconds)
        let map = TimelapseRule.frameMap(kept: frames.count, needed: needed)
        var lastIndex = -1
        var buffer: CVPixelBuffer?
        for (j, index) in map.enumerated() {
            if index != lastIndex {
                lastIndex = index
                guard let pool = adaptor.pixelBufferPool, let image = UIImage(contentsOfFile: frames[index].path)?.cgImage,
                      let fresh = pixelBuffer(from: pool) else { continue }
                draw(image, into: fresh)
                buffer = fresh
            }
            guard let buffer else { continue }
            await waitUntilReady(input)
            let time = CMTime(value: CMTimeValue(j), timescale: CMTimeScale(TimelapseRule.fps))
            if !adaptor.append(buffer, withPresentationTime: time) {
                log.error("append failed at \(j): \(String(describing: writer.error), privacy: .public)")
                writer.cancelWriting()
                return false
            }
            if j % 15 == 0 { progress(Double(j) / Double(needed)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        progress(1)
        return writer.status == .completed
    }

    private static func pixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        return out
    }

    /// Aspect fill into the buffer.
    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = max(CGFloat(w) / iw, CGFloat(h) / ih)
        let dw = iw * scale, dh = ih * scale
        ctx.draw(image, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
    }

    /// The clean clip with `overlay` (same size, mostly transparent) laid on
    /// every frame. A `CATextLayer` renders blank in an AVFoundation export
    /// (the ad pipeline, 2026-10-06), so the marks arrive as a bitmap.
    static func mark(_ clean: URL, overlay: UIImage, to out: URL) async -> Bool {
        guard let overlayCG = overlay.cgImage else { return false }
        return await Task.detached(priority: .userInitiated) {
            await markDetached(clean, overlay: CIImage(cgImage: overlayCG), to: out)
        }.value
    }

    private static func markDetached(_ clean: URL, overlay: CIImage, to out: URL) async -> Bool {
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: clean)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { return false }
        let readOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(readOut) else { return false }
        reader.add(readOut)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings())
        input.expectsMediaDataInRealTime = false
        let adaptor = adaptor(for: input)
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let ci = CIContext(options: [.cacheIntermediates: false])
        while let sample = readOut.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool,
                  let fresh = pixelBuffer(from: pool) else { continue }
            let frame = CIImage(cvPixelBuffer: pixels)
            let sx = CGFloat(TimelapseRule.outputWidth) / max(frame.extent.width, 1)
            let sy = CGFloat(TimelapseRule.outputHeight) / max(frame.extent.height, 1)
            let composed = overlay.composited(over: frame.transformed(by: CGAffineTransform(scaleX: sx, y: sy)))
            ci.render(composed, to: fresh)
            await waitUntilReady(input)
            adaptor.append(fresh, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return reader.status == .completed && writer.status == .completed
    }
}

/// The two small marks burned into the copy that leaves 808: the speed line
/// top left, "808 Meditate" bottom right, both kept inside Instagram's safe
/// area so its caption and buttons never cover them. Small on purpose: the
/// clip is the subject.
enum TimelapseMarks {
    @MainActor
    static func overlay(speedLine: String) -> UIImage {
        let size = CGSize(width: TimelapseRule.outputWidth, height: TimelapseRule.outputHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            let font = { (pt: CGFloat, w: UIFont.Weight) -> UIFont in
                let base = UIFont.systemFont(ofSize: pt, weight: w)
                return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pt) } ?? base
            }
            let speed = NSAttributedString(string: speedLine, attributes: [
                .font: font(34, .heavy), .foregroundColor: UIColor.white.withAlphaComponent(0.92), .shadow: shadow])
            // Below Instagram's top bar (about 250 of 1920).
            speed.draw(at: CGPoint(x: 64, y: 270))
            let mark = NSAttributedString(string: "808 Meditate", attributes: [
                .font: font(28, .bold), .foregroundColor: UIColor.white.withAlphaComponent(0.85), .shadow: shadow])
            let m = mark.size()
            // Above Instagram's caption and buttons (about 320 of 1920).
            mark.draw(at: CGPoint(x: size.width - 64 - m.width, y: size.height - 330 - m.height))
        }
    }
}
