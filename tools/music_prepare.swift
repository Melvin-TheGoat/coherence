// Prepares a music take for the app's background loop
// (`Coherence/Audio/Music/`, played by `AppAudio`).
//
//     swiftc -O tools/music_prepare.swift -o /tmp/music_prepare
//     /tmp/music_prepare analyze in.mp3
//     /tmp/music_prepare render in.mp3 out.wav --start S --end E --fade F [--rms 0.1256]
//     /tmp/music_prepare render in.mp3 out.wav --start S --end E --crossfade X
//     afconvert -f m4af -d aac -b 160000 out.wav Coherence/Audio/Music/<name>.m4a
//
// analyze prints the length, where the first note starts, the loudness, the
// envelope of the last 30 seconds (to choose where the loop ends), the key
// (chroma against the Krumhansl major and minor profiles) and the tuning in
// cents from A440. The sound effects are tuned to the music's key
// (`SoundSynth.root`, `AppAudio.musicTonic`, `test_theEffectsAreInTheMusicsKey`),
// so a take in another key moves them too.
//
// render cuts [start, end] in seconds, fades the last F seconds to silence (the
// loop then restarts on the first note, as the 61-second take did), and scales
// to a mono RMS of 0.1256, the beds' loudness (2026-10-12), peak-limited so
// nothing clips. Written 2026-10-13 for Melvin's three-minute take.

import Foundation
import AVFoundation
import Accelerate

func load(_ path: String) -> (left: [Float], right: [Float], rate: Double) {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                               channels: 2, interleaved: false)!
    let frames = AVAudioFrameCount(file.length)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    try! file.read(into: buffer)
    let n = Int(buffer.frameLength)
    let l = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
    let r = file.fileFormat.channelCount > 1
        ? Array(UnsafeBufferPointer(start: buffer.floatChannelData![1], count: n)) : l
    return (l, r, file.fileFormat.sampleRate)
}

func rms(_ x: ArraySlice<Float>) -> Float {
    guard !x.isEmpty else { return 0 }
    var s: Float = 0
    x.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &s, vDSP_Length($0.count)) }
    return s
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: analyze|render in [...]"); exit(1) }
let (left, right, rate) = load(args[2])
let mono = zip(left, right).map { ($0 + $1) / 2 }
let n = mono.count

if args[1] == "analyze" {
    print(String(format: "length %.2f s at %.0f Hz", Double(n) / rate, rate))
    let first = mono.firstIndex { abs($0) > 0.01 } ?? 0
    let last = mono.lastIndex { abs($0) > 0.01 } ?? n - 1
    print(String(format: "first sound %.3f s, last sound %.3f s", Double(first) / rate, Double(last) / rate))
    print(String(format: "mono RMS %.4f, peak %.3f", rms(mono[...]), mono.map { abs($0) }.max() ?? 0))
    var head = "envelope, first 12 s (RMS per half second): "
    for h in 0..<24 {
        let a = Int(Double(h) * 0.5 * rate), b = min(n, Int(Double(h + 1) * 0.5 * rate))
        guard a < b else { break }
        head += String(format: "%.1f:%.3f ", Double(h) * 0.5, rms(mono[a..<b]))
    }
    print(head)
    print("envelope, last 30 s (RMS per second):")
    let tail = max(0, Int(Double(n) / rate) - 30)
    var line = ""
    for s in tail..<Int(Double(n) / rate + 1) {
        let a = Int(Double(s) * rate), b = min(n, Int(Double(s + 1) * rate))
        guard a < b else { break }
        line += String(format: "%d:%.3f ", s, rms(mono[a..<b]))
    }
    print(line)

    // Chroma and tuning from 8192-point FFT frames.
    let size = 8192, hop = 4096, log2n = vDSP_Length(13)
    let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    var window = [Float](repeating: 0, count: size)
    vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    var chroma = [Double](repeating: 0, count: 12)
    var tuneSin = 0.0, tuneCos = 0.0
    var re = [Float](repeating: 0, count: size / 2), im = [Float](repeating: 0, count: size / 2)
    var start = first
    while start + size < last {
        var frame = Array(mono[start..<start + size])
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(size))
        var mags = [Float](repeating: 0, count: size / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(size / 2))
            }
        }
        let binHz = rate / Double(size)
        let lo = Int(60 / binHz), hi = Int(2000 / binHz)
        let floor = (mags[lo..<hi].max() ?? 0) * 0.1
        for k in max(lo, 1)..<hi where mags[k] > floor && mags[k] > mags[k - 1] && mags[k] >= mags[k + 1] {
            // Parabolic peak for a fractional bin.
            let a = Double(mags[k - 1]), b = Double(mags[k]), c = Double(mags[k + 1])
            let p = 0.5 * (a - c) / (a - 2 * b + c)
            let f = (Double(k) + (p.isFinite ? p : 0)) * binHz
            let semis = 12 * log2(f / 440)
            let nearest = semis.rounded()
            let w = b * b
            chroma[((Int(nearest) % 12) + 12 + 9) % 12] += w   // index 0 = C
            let phase = 2 * Double.pi * (semis - nearest)
            tuneSin += w * sin(phase); tuneCos += w * cos(phase)
        }
        start += hop
    }
    vDSP_destroy_fftsetup(setup)
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let total = chroma.reduce(0, +)
    print("chroma:", (0..<12).map { String(format: "%@ %.3f", names[$0], chroma[$0] / total) }.joined(separator: "  "))
    let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    func corr(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / 12, my = y.reduce(0, +) / 12
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in 0..<12 { sxy += (x[i] - mx) * (y[i] - my); sxx += pow(x[i] - mx, 2); syy += pow(y[i] - my, 2) }
        return sxy / sqrt(sxx * syy)
    }
    var keys: [(String, Double)] = []
    for t in 0..<12 {
        let rot = (0..<12).map { chroma[($0 + t) % 12] }
        keys.append(("\(names[t]) major", corr(rot, major)))
        keys.append(("\(names[t]) minor", corr(rot, minor)))
    }
    keys.sort { $0.1 > $1.1 }
    print("key:", keys.prefix(4).map { String(format: "%@ %.3f", $0.0, $0.1) }.joined(separator: ", "))
    let cents = atan2(tuneSin, tuneCos) / (2 * Double.pi) * 100
    print(String(format: "tuning %+.1f cents from A440", cents))
} else if args[1] == "render" {
    func opt(_ name: String) -> Double? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }
    let startS = opt("--start") ?? 0, endS = opt("--end") ?? Double(n) / rate
    let fade = opt("--fade") ?? 0.6, target = Float(opt("--rms") ?? 0.1256)
    let a = Int(startS * rate), b = min(n, Int(endS * rate))
    var l = Array(left[a..<b]), r = Array(right[a..<b])
    // --crossfade X: the last X seconds of the cut are mixed with its first
    // X seconds and the file starts X seconds in, so the loop wraps with no
    // silent dip (a take that swells in and fades out would otherwise leave
    // one every time it restarts). Equal power; no end fade is needed then.
    if let x = opt("--crossfade"), x > 0 {
        let xn = Int(x * rate), len = l.count
        var ol = Array(l[xn..<len]), or = Array(r[xn..<len])
        for j in 0..<xn {
            let k = ol.count - xn + j
            let gIn = Float(sin(Double(j) / Double(xn) * .pi / 2))
            let gOut = Float(cos(Double(j) / Double(xn) * .pi / 2))
            ol[k] = ol[k] * gOut + l[j] * gIn
            or[k] = or[k] * gOut + r[j] * gIn
        }
        l = ol; r = or
    }
    let fadeN = opt("--crossfade") != nil ? 0 : Int(fade * rate)
    for i in 0..<fadeN where l.count - 1 - i >= 0 {
        // Equal-power fade to silence over the last `fade` seconds.
        let g = Float(sin(Double(i) / Double(fadeN) * .pi / 2))
        l[l.count - 1 - i] *= g; r[r.count - 1 - i] *= g
    }
    let m = zip(l, r).map { ($0 + $1) / 2 }
    var gain = target / rms(m[...])
    let peak = max(l.map { abs($0) }.max() ?? 0, r.map { abs($0) }.max() ?? 0)
    if peak * gain > 0.98 { gain = 0.98 / peak; print("limited by peak") }
    vDSP_vsmul(l, 1, &gain, &l, 1, vDSP_Length(l.count))
    vDSP_vsmul(r, 1, &gain, &r, 1, vDSP_Length(r.count))
    let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(l.count))!
    buffer.frameLength = AVAudioFrameCount(l.count)
    l.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: l.count) }
    r.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: r.count) }
    let file = try! AVAudioFile(forWriting: URL(fileURLWithPath: args[3]), settings: out.settings)
    try! file.write(from: buffer)
    let m2 = zip(l, r).map { ($0 + $1) / 2 }
    print(String(format: "wrote %.2f s, gain %.3f, mono RMS %.4f", Double(l.count) / rate, gain, rms(m2[...])))
}
