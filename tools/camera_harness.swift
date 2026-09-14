// Runs the REAL camera engine (Shared/Engine/CameraSignal.swift) over a
// captured signals CSV, off the device, and scores it against the wrist's own
// breathing curve where one exists.
//
//   swiftc -parse-as-library -O -o /tmp/camera_harness \
//     Shared/Engine/SignalEngine.swift Shared/Engine/CameraSignal.swift \
//     tools/camera_harness.swift
//   /tmp/camera_harness <signals.csv> [--wrist wrist.csv|<id>_wrist.json]
//                       [--offset SEC|auto] [--session SEC] [--table]
//
// The CSV is either the probe's dump (`camera_probe --dump`) or the in-app
// collector's file (Documents/CameraCaptures/<id>.csv). Both carry the same
// nine columns. Video captures start before Begin, so `--offset` shifts the
// video clock onto the session clock. THE TWO AUG 24 VIDEOS ARE 20 s
// (IMG_7635) AND 25 s (IMG_9543); pass those. `auto` sweeps 0..180 s for the
// offset that minimises median error, as tools/camera_compare.py does, but it
// is not trustworthy: slow breathing is self-similar, and on these two
// captures it locks onto 175 s and 45 s by aligning one slow stretch onto
// another. In-app captures need no offset: their t = 0 is the Watch's
// started-ack, which is the whole point of the collector.
//
// Ground truth is the wrist: a digitized share-card CSV (t_sec,breath,
// stillness) or the collector's <id>_wrist.json (a SessionPayload). The
// comparison rule is camera_compare.py's, so the numbers here are directly
// comparable to the branch notes (median |error| 1.68 and 1.29 breaths/min
// on IMG_9543 and IMG_7635 with the probe): windows where the wrist read
// (>= 3.5), the camera read (clarity >= 0.30), and 30 s <= t <= session - 30.

import Foundation

@main
struct CameraHarness {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let path = args.first else {
            FileHandle.standardError.write(Data("usage: camera_harness <signals.csv> [--wrist W] [--offset SEC|auto] [--session SEC] [--table]\n".utf8))
            exit(2)
        }
        args.removeFirst()
        var wristPath: String?
        var offsetArg = "0"
        var sessionSec: Double?
        var table = false
        var gate = CameraSignal.motionGateRatio
        var dumpPath: String?
        var uniform = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--wrist" where i + 1 < args.count: wristPath = args[i + 1]; i += 2
            case "--offset" where i + 1 < args.count: offsetArg = args[i + 1]; i += 2
            case "--session" where i + 1 < args.count: sessionSec = Double(args[i + 1]); i += 2
            case "--table": table = true; i += 1
            // Diagnostics: sweep the motion gate ("off" disables it) and dump
            // every window (t, rate, clarity, gated, stillness) to a CSV.
            case "--gate" where i + 1 < args.count:
                gate = args[i + 1] == "off" ? .infinity : (Double(args[i + 1]) ?? gate); i += 2
            case "--dump" where i + 1 < args.count: dumpPath = args[i + 1]; i += 2
            // Replace the recorded timestamps with a uniform grid at the mean
            // rate, which is what the offline probe assumed. For checking the
            // port against the probe's own numbers only.
            case "--uniform": uniform = true; i += 1
            default: i += 1
            }
        }

        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("\(path): unreadable"); exit(1)
        }
        var capture = CameraCapture.parse(csv: text)
        print("loaded \(capture.frames.count) frames\(capture.hasROI ? " (ROI)" : "") from \((path as NSString).lastPathComponent)")
        if uniform, let first = capture.frames.first, let last = capture.frames.last, capture.frames.count > 1 {
            let dt = (last.t - first.t) / Double(capture.frames.count - 1)
            capture.frames = capture.frames.enumerated().map { i, f in
                CameraFrame(t: first.t + Double(i) * dt, motion: f.motion, dy: f.dy, dx: f.dx, luma: f.luma,
                            rmotion: f.rmotion, rdy: f.rdy, rdx: f.rdx, rluma: f.rluma)
            }
            print(String(format: "uniform grid: dt %.4f s", dt))
        }

        let wrist = wristPath.flatMap(loadWrist)
        let session = sessionSec ?? wrist?.durationSec ?? (capture.frames.last?.t ?? 0)

        // Offset: given, or solved against the wrist.
        var offset = Double(offsetArg) ?? 0
        if offsetArg == "auto" {
            guard let w = wrist else { print("--offset auto needs --wrist"); exit(1) }
            var best: (off: Double, med: Double)?
            var off = 0.0
            while off <= 180 {
                let r = CameraSignal.analyze(frames: shifted(capture.frames, by: off, session: session),
                                             roiFixedAtSec: capture.roiFixedAtSec.map { max(0, $0 - off) })
                if let m = compare(r, wrist: w, session: session), m.n >= 20,
                   best == nil || m.median < best!.med {
                    best = (off, m.median)
                }
                off += 5
            }
            offset = best?.off ?? 0
            print(String(format: "offset solved: %.0f s", offset))
        }

        let frames = shifted(capture.frames, by: offset, session: session)
        let t0 = Date()
        let r = CameraSignal.analyze(frames: frames,
                                     roiFixedAtSec: capture.roiFixedAtSec.map { max(0, $0 - offset) },
                                     gateRatio: gate)
        let elapsed = -t0.timeIntervalSinceNow
        let times = frames.map(\.t)
        let windows = CameraSignal.windows(totalSec: frames.last?.t ?? 0, windowSec: 30, hopSec: 5)
        let read = CameraSignal.breathing(frames: frames, times: times, windows: windows,
                                          windowSec: 30, hopSec: 5, gateRatio: gate)
        if let dumpPath {
            let motionWin = CameraSignal.windowMeans(frames.map(\.rmotion), times: times, windows: windows)
            let motionMedian = CameraSignal.median(motionWin)
            var csv = "t_session_sec,rate,tracked,clarity,gated,stillness,motion_x_median\n"
            for (i, rate) in read.rates.enumerated() {
                csv += String(format: "%.1f,%.2f,%.2f,%.3f,%d,%.3f,%.2f\n", Double(i) * 5 + 15, rate, read.tracked[i],
                              read.clarity[i], read.gated[i] ? 1 : 0,
                              i < r.stillnessTimeseries.count ? r.stillnessTimeseries[i] : 0,
                              motionMedian > 0 ? motionWin[i] / motionMedian : 0)
            }
            try? csv.write(toFile: dumpPath, atomically: true, encoding: .utf8)
            print("windows -> \(dumpPath)")
        }

        // Breathing summary.
        let readable = read.rates.filter { $0 > 0 }.sorted()
        print(String(format: "windows %d  read %d (%.0f%%)  gated %d  median rate %@  engine %.2fs",
                     read.rates.count, readable.count, read.fraction * 100,
                     read.gated.filter { $0 }.count,
                     readable.isEmpty ? "-" : String(format: "%.1f/min", readable[readable.count / 2]),
                     elapsed))
        let clar = zip(read.rates, read.clarity).filter { $0.0 > 0 }.map(\.1)
        if !clar.isEmpty {
            let s = clar.sorted()
            print(String(format: "clarity on read windows: median %.2f  p90 %.2f  max %.2f",
                         s[s.count / 2], s[Int(Double(s.count) * 0.9)], s.last!))
        }
        if let d = read.doorway {
            print(String(format: "doorway %.1f/min  start %.0f s  held %.0f s", d.rate, d.startSec, d.heldSec))
        } else {
            print("doorway none")
        }
        // What other clarity floors would have done, on the same tracked path.
        let sweep = [0.15, 0.20, 0.30, 0.45].map { f -> String in
            let d = SignalEngine.breathDoorway(rates: read.tracked, clarities: read.clarity,
                                               windowSec: 30, hopSec: 5, clarityFloor: f, lateClarity: .infinity)
            return String(format: "%.2f: %@", f, d.map { String(format: "%.1f@%.0fs/%.0fs", $0.rate, $0.startSec, $0.heldSec) } ?? "none")
        }
        print("doorway by floor  " + sweep.joined(separator: "   "))

        // Stillness summary.
        let still = r.stillnessTimeseries
        if !still.isEmpty {
            let s = still.sorted()
            let floor = CameraSignal.stillnessFloor(motion: frames.map(\.rmotion), times: times,
                                                    fromSec: capture.roiFixedAtSec.map { max(0, $0 - offset) } ?? 0)
            let means = CameraSignal.windowMeans(frames.map(\.rmotion), times: times, windows: windows)
            let ratios = means.map { floor > 0 ? $0 / floor : 0 }.sorted()
            print(String(format: "stillness mean %.3f  min %.3f  p10 %.3f  median %.3f  p90 %.3f  -> spread %.2f",
                         r.stillnessScore ?? 0, s.first!, s[s.count / 10], s[s.count / 2], s[Int(Double(s.count) * 0.9)],
                         SignalEngine.spreadStillness(r.stillnessScore ?? 0)))
            print(String(format: "motion/floor ratio: floor %.4f  median x%.2f  p90 x%.2f  max x%.1f  gate at x%.2f of median",
                         floor, ratios[ratios.count / 2], ratios[Int(Double(ratios.count) * 0.9)], ratios.last!,
                         CameraSignal.motionGateRatio))
        }
        print(String(format: "score %@  (duration %.0f s, factor %.2f)",
                     r.overallScore.map { String(format: "%.0f", $0 * 100) } ?? "-",
                     frames.last?.t ?? 0, SignalEngine.durationFactor(seconds: Int((frames.last?.t ?? 0).rounded()))))

        // Against the wrist.
        if let w = wrist {
            if let m = compare(r, wrist: w, session: session) {
                print(String(format: "vs wrist: n=%d  median|err| %.2f/min  within ±1.5 %.0f%%  mean|err| %.2f",
                             m.n, m.median, m.within * 100, m.mean))
            } else {
                print("vs wrist: too few overlapping windows")
            }
            if table { perMinute(r, wrist: w, session: session) }
        } else if table {
            print("\n  min   camera   clarity   still")
            var byMin: [Int: [(Double, Double, Double)]] = [:]
            for (i, rate) in read.rates.enumerated() {
                let t = Double(i) * 5 + 15
                byMin[Int(t / 60), default: []].append((rate, read.clarity[i], still[i]))
            }
            for m in byMin.keys.sorted() {
                let v = byMin[m]!
                let rates = v.map(\.0).filter { $0 > 0 }.sorted()
                let stillMed = v.map(\.2).sorted()[v.count / 2]
                let clMed = v.map(\.1).sorted()[v.count / 2]
                print(String(format: "  %3d   %@   %.2f      %.2f", m,
                             rates.isEmpty ? "   -- " : String(format: "%6.1f", rates[rates.count / 2]),
                             clMed, stillMed))
            }
        }
    }

    // MARK: - Helpers

    /// Video time onto session time: subtract the offset, drop what came
    /// before Begin, clip at the session's end.
    static func shifted(_ frames: [CameraFrame], by offset: Double, session: Double) -> [CameraFrame] {
        frames.compactMap { f in
            let t = f.t - offset
            guard t >= 0, t <= session else { return nil }
            return CameraFrame(t: t, motion: f.motion, dy: f.dy, dx: f.dx, luma: f.luma,
                               rmotion: f.rmotion, rdy: f.rdy, rdx: f.rdx, rluma: f.rluma)
        }
    }

    struct Wrist {
        /// Breath rate keyed by window start (t rounded to 5 s), zeros dropped.
        let breath: [Int: Double]
        let stillness: [Int: Double]
        let durationSec: Double?
    }

    static func loadWrist(_ path: String) -> Wrist? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var breath: [Int: Double] = [:], still: [Int: Double] = [:]
        if path.hasSuffix(".json") {
            guard let data = text.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = j["result"] as? [String: Any],
                  let win = r["windowSec"] as? Double, let hop = r["hopSec"] as? Double,
                  let rates = r["breathingRateTimeseries"] as? [Double] else { return nil }
            let stills = r["stillnessTimeseries"] as? [Double] ?? []
            for (i, v) in rates.enumerated() where v > 0 {
                breath[Int((win / 2 + Double(i) * hop).rounded())] = v
            }
            for (i, v) in stills.enumerated() {
                still[Int((win / 2 + Double(i) * hop).rounded())] = v
            }
            return Wrist(breath: breath, stillness: still, durationSec: j["durationSec"] as? Double)
        }
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",").compactMap { Double($0) }
            guard f.count >= 2 else { continue }
            let key = Int((f[0] / 5).rounded()) * 5
            if f[1] > 0 { breath[key] = f[1] }
            if f.count >= 3 { still[key] = f[2] }
        }
        return Wrist(breath: breath, stillness: still, durationSec: nil)
    }

    struct Agreement { let n: Int; let median: Double; let mean: Double; let within: Double }

    /// camera_compare.py's rule. The camera's window i is centred at 15 + 5i
    /// (session time); the digitized wrist series is keyed by the same centres.
    static func compare(_ r: SignalResult, wrist: Wrist, session: Double) -> Agreement? {
        var errs: [Double] = []
        for (i, rate) in r.breathingRateTimeseries.enumerated() where rate > 0 {
            guard i < r.breathClarityTimeseries.count, r.breathClarityTimeseries[i] >= CameraSignal.readClarity else { continue }
            let centre = Double(r.windowSec) / 2 + Double(i) * Double(r.hopSec)
            let key = Int((centre / 5).rounded()) * 5
            guard let w = wrist.breath[key], w >= 3.5, Double(key) >= 30, Double(key) <= session - 30 else { continue }
            errs.append(abs(rate - w))
        }
        guard !errs.isEmpty else { return nil }
        let s = errs.sorted()
        return Agreement(n: s.count, median: s[s.count / 2],
                         mean: s.reduce(0, +) / Double(s.count),
                         within: Double(s.filter { $0 <= 1.5 }.count) / Double(s.count))
    }

    static func perMinute(_ r: SignalResult, wrist: Wrist, session: Double) {
        var cam: [Int: [Double]] = [:], wr: [Int: [Double]] = [:]
        var camStill: [Int: [Double]] = [:], wrStill: [Int: [Double]] = [:]
        for (i, rate) in r.breathingRateTimeseries.enumerated() {
            let centre = Double(r.windowSec) / 2 + Double(i) * Double(r.hopSec)
            if rate > 0, i < r.breathClarityTimeseries.count, r.breathClarityTimeseries[i] >= CameraSignal.readClarity {
                cam[Int(centre / 60), default: []].append(rate)
            }
        }
        for (i, s) in r.stillnessTimeseries.enumerated() {
            let centre = Double(r.windowSec) / 2 + Double(i) * Double(r.hopSec)
            camStill[Int(centre / 60), default: []].append(s)
        }
        for (k, v) in wrist.breath where v >= 3.5 { wr[k / 60, default: []].append(v) }
        for (k, v) in wrist.stillness { wrStill[k / 60, default: []].append(v) }
        func med(_ a: [Double]?) -> Double? { guard let a, !a.isEmpty else { return nil }; return a.sorted()[a.count / 2] }
        func f(_ v: Double?, _ w: Int = 6) -> String { v.map { String(format: "%\(w).1f", $0) } ?? String(repeating: " ", count: w - 2) + "--" }
        func f2(_ v: Double?) -> String { v.map { String(format: "%5.2f", $0) } ?? "   --" }
        print("\n  min   wrist  camera   diff   | still wrist  camera")
        for m in 0..<Int(session / 60) {
            let a = med(wr[m]), b = med(cam[m])
            let d = (a != nil && b != nil) ? String(format: "%+5.1f", b! - a!) : "   --"
            print("  \(String(format: "%3d", m))  \(f(a, 6))  \(f(b, 6))  \(d)   |  \(f2(med(wrStill[m])))  \(f2(med(camStill[m])))")
        }
    }
}
