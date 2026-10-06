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
caption("my meditation app won't\nlet me open instagram 😭", 0, 2.4)
caption("then it texts me 💀", 2.4, 5.32)
caption("he forces me to meditate 🧘\nevery day to open my apps", 5.32, 8.12)
caption("if I meditate every day,\nhe gets happier ✨", 8.12, 11.44)
caption("and my streak keeps growing 🔥", 11.44, 14.09)
caption("every session earns coins 💰", 14.09, 16.84)
caption("so I can buy Otto\nnew hats 🎩", 16.84, 20.42)
caption("make meditation a habit\nwith 808 Meditate 🧘", 20.42, dur, top: 200, size: 68, sub: "on the App Store today")
vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
ex.videoComposition = vc; ex.outputURL = URL(fileURLWithPath: a[2]); ex.outputFileType = .mp4
let sem = DispatchSemaphore(value: 0); ex.exportAsynchronously { sem.signal() }; sem.wait()
print(ex.status == .completed ? "ok \(dur) src \(ns)" : "fail \(String(describing: ex.error))")
