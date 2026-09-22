import Foundation
import ManagedSettings

/// The shield's two buttons.
///
/// **A shield cannot open an app**, so "Ask Otto" sends a notification
/// ("Otto wants a word"), and tapping it opens 808 on one of Otto's twenty
/// screens. `.defer` keeps the shield up and has it draw itself again, now
/// saying the notification is on its way. "Close" sends the person home.
final class BlockShieldAction: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    private func respond(to action: ShieldAction,
                         _ done: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            BlockAsk.post { done(.defer) }
        case .secondaryButtonPressed:
            done(.close)
        @unknown default:
            done(.close)
        }
    }
}
