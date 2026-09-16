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
    private var session: LanguageModelSession

    /// Keeps a reply to a few sentences, which is Otto's voice anyway, and
    /// leaves room in the window for the conversation to continue.
    private static let options = GenerationOptions(maximumResponseTokens: 400)

    init(instructions: String, opening: String) {
        self.instructions = instructions
        self.session = LanguageModelSession(instructions: instructions)
        self.messages = [OttoMessage(role: .otto, text: opening)]
        session.prewarm()
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
            return
        }
        await respond(to: q, retried: false)
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
