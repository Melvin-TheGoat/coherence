import Foundation
import StoreKit
import UserNotifications

/// Otto's one notification about money: "Your free trial ends tomorrow."
///
/// Onboarding promises it before the paywall ("I'll remind you the day before
/// it ends", Aziz, 2026-11-11), so it is scheduled from what StoreKit says,
/// not from what the paywall showed: a free trial in progress is a current
/// entitlement whose transaction carries the introductory offer, and its
/// expiration date is the end of the trial. `Store.refreshEntitlement` hands
/// that date here on every launch, purchase, restore and renewal, so the
/// reminder follows a purchase made on another device, disappears once the
/// trial has converted, and is never scheduled for someone who paid outright.
///
/// When the trial is cancelled it still fires: the trial does still end, and
/// saying so is true. Without notification permission nothing is delivered,
/// which is why the screen that promises the reminder asks for it.
enum TrialEndNotice {
    static let id = "trial-ends"

    /// Schedules the reminder for a trial ending at `trialEnd`, or takes it
    /// back when there is no trial running (nil).
    static func sync(trialEnd: Date?, now: Date = Date()) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard let trialEnd, let fire = TrialReminder.fireDate(trialEnd: trialEnd, now: now) else {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                return
            }
            // Already waiting for the same moment: nothing to do.
            let pending = await center.pendingNotificationRequests().first { $0.identifier == id }
            if let trigger = pending?.trigger as? UNCalendarNotificationTrigger,
               trigger.nextTriggerDate() == fire {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Otto"
            content.body = TrialReminder.body(fire: fire, end: trialEnd)
            content.sound = .default
            content.interruptionLevel = .active
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }

    /// The end of the free trial this transaction is in, or nil when it is
    /// not a free trial (paid outright, a renewal, a paid introductory offer)
    /// or has already ended.
    static func trialEnd(of transaction: Transaction, now: Date = Date()) -> Date? {
        guard let end = transaction.expirationDate, end > now else { return nil }
        if #available(iOS 17.2, *) {
            guard let offer = transaction.offer, offer.type == .introductory,
                  offer.paymentMode == .freeTrial else { return nil }
        } else {
            guard transaction.offerType == .introductory else { return nil }
        }
        return end
    }
}
