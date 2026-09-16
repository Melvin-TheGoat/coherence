// Puts questions to the same on-device model Otto uses, on the Mac, so
// answers can be read and the brief tuned without a phone.
//
//   swiftc -O -framework FoundationModels -o /tmp/otto_lab tools/otto_lab.swift
//   /tmp/otto_lab /tmp/otto_brief.txt "Why did I score 15?" "How do I settle faster?"
//
// The brief comes from `test_dumpBriefForTheLab` in OttoBriefTests:
//   TEST_RUNNER_OTTO_BRIEF_OUT=/tmp/otto_brief.txt xcodebuild test ... -only-testing:CoherenceTests/OttoBriefTests/test_dumpBriefForTheLab
// Needs macOS 26 with Apple Intelligence on. Nothing leaves the Mac.
import Foundation
import FoundationModels

let args = CommandLine.arguments
guard args.count >= 3, let brief = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    print("usage: otto_lab <brief.txt> <question> [question ...]"); exit(1)
}
let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "1") ?? 1
let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 400)
for q in args.dropFirst(2) {
    for run in 1...runs {
        let session = LanguageModelSession(instructions: brief)
        print("\n=== Q\(runs > 1 ? " (run \(run))" : ""): \(q)")
        do {
            let r = try await session.respond(to: q, options: options)
            print(r.content)
        } catch {
            print("ERROR: \(error)")
        }
    }
}
