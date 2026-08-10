// Runs the REAL SignalEngine over a captured CSV, off the device.
//
// The Python bench is a replica and replicas drift. This compiles the shipped
// engine itself, so what it prints is what the Watch would compute. Use it to
// confirm a change before installing anything, and to catch the case where the
// bench and the engine have quietly stopped agreeing.
//
//   swiftc -parse-as-library -O -o /tmp/breath \
//     Shared/Engine/SignalEngine.swift tools/breath_harness.swift
//   /tmp/breath ~/Desktop/captures/motion-*.csv
//
// Columns: t,pitch,roll,yaw,ax,ay,az at 100 Hz. The Watch's own buffer is
// decimated to 20 Hz, so this decimates too: feeding the engine 5x the samples
// it will ever see would measure something the product does not run.

import Foundation

@main
struct BreathHarness {
    static func main() {
        let paths = Array(CommandLine.arguments.dropFirst())
        guard !paths.isEmpty else {
            FileHandle.standardError.write(Data("usage: breath <capture.csv>...\n".utf8))
            exit(2)
        }
        print(String(format: "%-10s %6s %8s %8s %6s %6s  %@",
                     ("capture" as NSString).utf8String!, ("dur" as NSString).utf8String!,
                     ("breaths" as NSString).utf8String!, ("still" as NSString).utf8String!,
                     ("IQR" as NSString).utf8String!, ("read" as NSString).utf8String!,
                     "curve"))
        for path in paths { run(path) }
    }

    static func run(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("\(path): unreadable"); return
        }
        var motion: [MotionSample] = []
        var line = 0
        for row in text.split(separator: "\n") {
            line += 1
            if line == 1 { continue }              // header
            if line % 5 != 2 { continue }          // 100 Hz -> 20 Hz
            let f = row.split(separator: ",").map { Double($0) ?? 0 }
            guard f.count >= 7 else { continue }
            let accel = (f[4] * f[4] + f[5] * f[5] + f[6] * f[6]).squareRoot()
            motion.append(MotionSample(t: f[0], pitch: f[1], roll: f[2], userAccel: accel))
        }
        guard let last = motion.last else { print("\(path): empty"); return }

        let r = SignalEngine.analyze(motion: motion, hr: [], bellyBreathing: false)
        let live = r.breathingRateTimeseries.filter { $0 > 0 }
        let frac = r.breathingRateTimeseries.isEmpty ? 0
            : Double(live.count) / Double(r.breathingRateTimeseries.count)
        let sorted = live.sorted()
        let spread = sorted.isEmpty ? 0
            : sorted[(sorted.count * 3) / 4] - sorted[sorted.count / 4]

        let tag = (path as NSString).lastPathComponent
            .replacingOccurrences(of: "motion-", with: "").prefix(8)
        let curve = stride(from: 0, to: r.breathingRateTimeseries.count, by: 3)
            .map { String(format: "%.0f", r.breathingRateTimeseries[$0]) }
            .joined(separator: " ")
        print(String(format: "%-10@ %6.0f %8@ %8.2f %6.2f %5.0f%%  %@",
                     String(tag) as NSString, last.t,
                     r.meanBreathingRate.map { String(format: "%.1f", $0) } as NSString? ?? "-",
                     r.stillnessScore ?? 0, spread, frac * 100, curve))
    }
}
