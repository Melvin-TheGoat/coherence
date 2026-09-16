import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One line of the chat.
struct OttoMessage: Identifiable, Equatable {
    enum Role { case otto, user }
    let id = UUID()
    var role: Role
    var text: String
    /// True while the reply is still arriving.
    var isStreaming = false
}

/// Whether this phone can run Otto at all, decided before the lock is
/// considered: nobody should be sold a chat their phone cannot run.
enum OttoAvailability: Equatable {
    case available
    /// iOS older than 26, or an SDK without the framework.
    case needsUpdate
    case deviceNotEligible
    case notEnabled
    case modelNotReady

    static let headline = "Otto needs an iPhone with Apple Intelligence and iOS 26."

    var detail: String {
        switch self {
        case .available:
            return ""
        case .needsUpdate:
            return "Otto runs on the phone so your numbers never leave it, and that needs Apple's on-device model. Update to iOS 26 to use Otto."
        case .deviceNotEligible:
            return "Otto runs on the phone so your numbers never leave it, and that needs Apple's on-device model, which this iPhone cannot run."
        case .notEnabled:
            return "Otto runs on the phone so your numbers never leave it, and that needs Apple's on-device model. Turn on Apple Intelligence in Settings, then come back."
        case .modelNotReady:
            return "Apple Intelligence is still getting its model ready on this iPhone. Try again in a little while."
        }
    }

    static func current() -> OttoAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:          return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady:              return .modelNotReady
                @unknown default:                 return .modelNotReady
                }
            }
        }
        #endif
        return .needsUpdate
    }
}

#if canImport(FoundationModels)
/// The chat: one `LanguageModelSession` per conversation, primed with the
/// brief from `OttoBrief`. Replies stream in.
///
/// **No network, by construction.** `SystemLanguageModel.default` is Apple's
/// on-device model; the session never leaves the process. That is what lets
/// heart-rate numbers sit in the prompt at all (guideline 5.1.3) and keeps
/// the App Review answer "no server, no AI service" true.
@available(iOS 26, *)
@MainActor
@Observable
final class OttoModel {
    private(set) var messages: [OttoMessage]
    private(set) var isResponding = false
    /// A quiet line under the chat when the conversation had to restart.
    private(set) var note: String?

    private let instructions: String
    private let opening: String
    /// Where this conversation is kept between visits (`OttoChatStore`).
    private let storeKey: String
    private var session: LanguageModelSession

    /// Keeps a reply to a few sentences, which is Otto's voice anyway, and
    /// leaves room in the window for the conversation to continue. The low
    /// temperature is for consistency: the same question about the same sit
    /// got a right explanation one time and a wrong one the next (Melvin,
    /// 2026-09-16); with the score card doing the arithmetic and sampling
    /// kept close to greedy, the answer stays the same answer.
    private static let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 400)

    init(instructions: String, opening: String, storeKey: String) {
        self.instructions = instructions
        self.opening = opening
        self.storeKey = storeKey
        // A saved conversation comes back on screen in full, and its last
        // turns are replayed into the model's transcript under the CURRENT
        // brief, so a chat reopened after new sits knows about them.
        let saved = OttoChatStore.load(key: storeKey)?.lines ?? []
        if saved.count > 1 {
            self.messages = saved.map { OttoMessage(role: $0.fromOtto ? .otto : .user, text: $0.text) }
            self.session = LanguageModelSession(transcript: Self.transcript(instructions: instructions, replaying: saved))
        } else {
            self.messages = [OttoMessage(role: .otto, text: opening)]
            self.session = LanguageModelSession(instructions: instructions)
        }
        session.prewarm()
    }

    /// Whether there is a conversation to throw away.
    var hasHistory: Bool { messages.count > 1 }

    /// Back to the opening line, the saved conversation gone.
    func startOver() {
        guard !isResponding else { return }
        messages = [OttoMessage(role: .otto, text: opening)]
        session = LanguageModelSession(instructions: instructions)
        note = nil
        OttoChatStore.delete(key: storeKey)
        session.prewarm()
    }

    /// The model's transcript rebuilt from saved lines: the current
    /// instructions first, then the last few question/answer pairs. The
    /// opening line is UI, not a model turn, so it is not replayed.
    private static func transcript(instructions: String, replaying lines: [OttoChatStore.Saved.Line]) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(.init(content: instructions))], toolDefinitions: []))
        ]
        var pairs: [(String, String)] = []
        var i = 1
        while i + 1 < lines.count {
            if !lines[i].fromOtto, lines[i + 1].fromOtto, !lines[i + 1].text.isEmpty {
                pairs.append((lines[i].text, lines[i + 1].text))
                i += 2
            } else {
                i += 1
            }
        }
        for (q, a) in pairs.suffix(OttoChatStore.replayedTurns) {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: q))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: a))])))
        }
        return Transcript(entries: entries)
    }

    private func persist() {
        let lines = messages.filter { !$0.isStreaming }.map { OttoChatStore.Saved.Line(fromOtto: $0.role == .otto, text: $0.text) }
        OttoChatStore.save(lines, key: storeKey)
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isResponding else { return }
        messages.append(OttoMessage(role: .user, text: q))
        // Name only. Never the question, never a number.
        Analytics.track(.ottoAsked)
        // Medical questions never reach the model. The guarantee lives here,
        // in a rule, not in a small model's reading of its instructions.
        if let decline = OttoBrief.medicalDecline(for: q) {
            messages.append(OttoMessage(role: .otto, text: decline))
            persist()
            return
        }
        await respond(to: q, retried: false)
        persist()
    }

    private func respond(to q: String, retried: Bool) async {
        isResponding = true
        defer { isResponding = false }
        messages.append(OttoMessage(role: .otto, text: "", isStreaming: true))
        let index = messages.count - 1
        do {
            let stream = session.streamResponse(to: q, options: Self.options)
            for try await snapshot in stream {
                guard index < messages.count else { return }
                messages[index].text = OttoBrief.sanitize(snapshot.content)
            }
            messages[index].isStreaming = false
            if messages[index].text.isEmpty {
                messages[index].text = "Otto had nothing to add there. Ask it another way?"
            }
        } catch let error as LanguageModelSession.GenerationError {
            messages.remove(at: index)
            if case .exceededContextWindowSize = error, !retried {
                // The window filled up. Start over with the same brief and
                // ask once more; the person loses the earlier turns, not
                // the answer.
                session = LanguageModelSession(instructions: instructions)
                note = "Otto started a fresh chat to keep things short."
                await respond(to: q, retried: true)
            } else {
                messages.append(OttoMessage(role: .otto, text: Self.message(for: error)))
            }
        } catch {
            messages.remove(at: index)
            messages.append(OttoMessage(role: .otto, text: "Otto could not answer that one. Try again in a moment."))
        }
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .refusal, .guardrailViolation:
            return "Otto would rather not go there. Ask about your sessions, the score, or how to sit."
        case .rateLimited, .concurrentRequests:
            return "Otto is busy for a moment. Try again shortly."
        case .assetsUnavailable:
            return "Apple Intelligence is not ready on this iPhone right now. Try again in a little while."
        case .unsupportedLanguageOrLocale:
            return "Otto can only chat in the languages Apple Intelligence supports on this iPhone."
        case .exceededContextWindowSize:
            return "This chat got long. Close Otto and open it again for a fresh one."
        default:
            return "Otto could not answer that one. Try again in a moment."
        }
    }
}
#endif
