// finish <in.mov> <out.mp4>: crop the 16:9 render to 9:16, cream background, captions.
import AVFoundation
import QuartzCore
import AppKit
let a = CommandLine.arguments
let src = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let vt = src.tracks(withMediaType: .video)[0]
let ns = vt.naturalSize
let W: CGFloat = 1080, H: CGFloat = 1920
let comp = AVMutableComposition()
let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try! ct.insertTimeRange(CMTimeRange(start: .zero, duration: src.duration), of: vt, at: .zero)
let dur = comp.duration.seconds
let s = H / ns.height
let tx = (W - ns.width * s) / 2
let li = AVMutableVideoCompositionLayerInstruction(assetTrack: ct)
li.setTransform(CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: tx, y: 0)), at: .zero)
let ins = AVMutableVideoCompositionInstruction()
ins.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
ins.layerInstructions = [li]
ins.backgroundColor = CGColor(red: 0.953, green: 0.929, blue: 0.886, alpha: 1)  // warm cream
let vc = AVMutableVideoComposition()
vc.instructions = [ins]; vc.renderSize = CGSize(width: W, height: H)
vc.frameDuration = CMTime(value: 1, timescale: 30)
let parent = CALayer(); parent.frame = CGRect(x: 0, y: 0, width: W, height: H)
let video = CALayer(); video.frame = parent.frame
parent.addSublayer(video)
func rounded(_ size: CGFloat, _ w: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: w)
    return NSFont(descriptor: f.fontDescriptor.withDesign(.rounded)!, size: size)!
}
let ink = NSColor(red: 0.17, green: 0.13, blue: 0.09, alpha: 1)
// caption(text, start, end, yTop, size)
func caption(_ text: String, _ t0: Double, _ t1: Double, top: CGFloat = 250, size: CGFloat = 62, pill: Bool = true, sub: String? = nil) {
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4
    let attr = NSMutableAttributedString(string: text, attributes: [.font: rounded(size, .heavy), .foregroundColor: ink, .paragraphStyle: para])
    if let sub { attr.append(NSAttributedString(string: "\n" + sub, attributes: [.font: rounded(size * 0.5, .bold), .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: para])) }
    let maxW: CGFloat = 900
    let r = attr.boundingRect(with: CGSize(width: maxW - 60, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let tw = ceil(r.width), th = ceil(r.height)
    let box = CALayer()
    let bw = tw + 64, bh = th + 40
    box.frame = CGRect(x: (W - bw) / 2, y: H - top - bh, width: bw, height: bh)
    if pill {
        box.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.96)
        box.cornerRadius = 30
        box.shadowColor = CGColor(gray: 0, alpha: 1); box.shadowOpacity = 0.12; box.shadowRadius = 18; box.shadowOffset = CGSize(width: 0, height: -6)
    }
    // Draw the words into a bitmap: CATextLayer renders blank during export.
    let sc: CGFloat = 2
    let cg = CGContext(data: nil, width: Int((tw + 40) * sc), height: Int((th + 16) * sc), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cg.scaleBy(x: sc, y: sc)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    attr.draw(with: CGRect(x: 0, y: 4, width: tw + 40, height: th + 10), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
    let tl = CALayer(); tl.contents = cg.makeImage()
    tl.frame = CGRect(x: 32 - 19, y: 20 - 10, width: tw + 40, height: th + 16)
    box.addSublayer(tl)
    box.opacity = 0
    let fade = CAKeyframeAnimation(keyPath: "opacity")
    let fi = 0.18
    fade.values = [0, 1, 1, 0]
    fade.keyTimes = [0, NSNumber(value: fi / (t1 - t0)), NSNumber(value: 1 - fi / (t1 - t0)), 1]
    fade.beginTime = t0 == 0 ? AVCoreAnimationBeginTimeAtZero : t0
    fade.duration = t1 - t0; fade.isRemovedOnCompletion = false; fade.fillMode = .both
    box.add(fade, forKey: "fade")
    let pop = CAKeyframeAnimation(keyPath: "transform.scale")
    pop.values = [0.9, 1.04, 1.0]; pop.keyTimes = [0, 0.6, 1]
    pop.beginTime = t0 == 0 ? AVCoreAnimationBeginTimeAtZero : t0
    pop.duration = 0.28; pop.isRemovedOnCompletion = false; pop.fillMode = .both
    box.add(pop, forKey: "pop")
    parent.addSublayer(box)
}
caption("my meditation app won't\nlet me open instagram 😭", 0, 3.6)
caption("then it texts me 💀", 3.6, 6.52)
caption("he forces me to meditate 🧘\nevery day to open my apps", 6.52, 10.62)
caption("if I meditate every day,\nhe gets happier ✨", 10.62, 13.94)
caption("and my streak keeps growing 🔥", 13.94, 16.59)
caption("every session earns coins 💰", 16.59, 19.34)
caption("so I can buy Otto\nnew hats 🎩", 19.34, 22.92)
caption("make meditation a habit\nwith 808 Meditate 🧘", 22.92, dur, top: 200, size: 68, sub: "on the App Store today")
vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)

// Voice lines (01...08.mp3 in a[3]) on their beats, and a quiet bed (a[4]).
let voiceAt: [Double] = [0.15, 3.75, 6.67, 10.77, 14.09, 16.74, 19.49, 23.07]
let mix = AVMutableAudioMix()
var params: [AVMutableAudioMixInputParameters] = []
for (k, t) in voiceAt.enumerated() {
    let url = URL(fileURLWithPath: a[3] + String(format: "/%02d.mp3", k + 1))
    let asset = AVURLAsset(url: url)
    guard let at = asset.tracks(withMediaType: .audio).first else { continue }
    let tr = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let len = min(asset.duration, CMTimeSubtract(comp.duration, CMTime(seconds: t, preferredTimescale: 600)))
    try! tr.insertTimeRange(CMTimeRange(start: .zero, duration: len), of: at, at: CMTime(seconds: t, preferredTimescale: 600))
}
if a.count > 4 {
    let bed = AVURLAsset(url: URL(fileURLWithPath: a[4]))
    if let bt = bed.tracks(withMediaType: .audio).first {
        let tr = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try! tr.insertTimeRange(CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: comp.duration), of: bt, at: .zero)
        let p = AVMutableAudioMixInputParameters(track: tr)
        let total = comp.duration.seconds
        p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 0.16, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 0.6, preferredTimescale: 600)))
        p.setVolume(0.16, at: CMTime(seconds: 0.6, preferredTimescale: 600))
        p.setVolumeRamp(fromStartVolume: 0.16, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: total - 1.2, preferredTimescale: 600), duration: CMTime(seconds: 1.2, preferredTimescale: 600)))
        params.append(p)
    }
}
mix.inputParameters = params
let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
ex.videoComposition = vc; ex.audioMix = mix; ex.outputURL = URL(fileURLWithPath: a[2]); ex.outputFileType = .mp4
let sem = DispatchSemaphore(value: 0); ex.exportAsynchronously { sem.signal() }; sem.wait()
print(ex.status == .completed ? "ok \(dur) src \(ns)" : "fail \(String(describing: ex.error))")
