// concat <out.mp4> file:start:end:speed ...   (30 fps, HighestQuality)
import AVFoundation
let a = CommandLine.arguments
let comp = AVMutableComposition()
let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
var size = CGSize.zero
for seg in a.dropFirst(2) {
    let p = seg.split(separator: ":").map(String.init)
    let asset = AVURLAsset(url: URL(fileURLWithPath: p[0]))
    let vt = asset.tracks(withMediaType: .video)[0]; size = vt.naturalSize
    let r = CMTimeRange(start: CMTime(seconds: Double(p[1])!, preferredTimescale: 6000), end: CMTime(seconds: Double(p[2])!, preferredTimescale: 6000))
    let at = comp.duration
    try! ct.insertTimeRange(r, of: vt, at: at)
    let sp = Double(p[3])!
    if sp != 1 { ct.scaleTimeRange(CMTimeRange(start: at, duration: r.duration), toDuration: CMTime(seconds: r.duration.seconds / sp, preferredTimescale: 6000)) }
    print(p[0].split(separator: "/").last!, "at", String(format: "%.2f", at.seconds), "len", String(format: "%.2f", r.duration.seconds / sp))
}
let vc = AVMutableVideoComposition(propertiesOf: comp)
vc.frameDuration = CMTime(value: 1, timescale: 30); vc.renderSize = size
let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
ex.videoComposition = vc; ex.outputURL = URL(fileURLWithPath: a[1]); ex.outputFileType = .mp4
let s = DispatchSemaphore(value: 0); ex.exportAsynchronously { s.signal() }; s.wait()
print(ex.status == .completed ? "ok \(comp.duration.seconds)" : "fail")
