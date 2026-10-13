import Foundation

/// What this phone remembers about its reminders, so the planner can learn
/// which topics actually get this person to meditate (`ReminderPlanner`).
///
/// It never asks iOS what was delivered. Every reminder the planner schedules
/// goes into `pending`; at the next replan, anything in `pending` whose time
/// has passed was delivered, and anything still ahead is about to be replaced.
/// A delivered reminder is scored once its window closes: a WIN if it was
/// tapped or a session started within `ReminderPlanner.winWindow` of it.
/// Stored as JSON in UserDefaults on this phone only, never synced or sent.
struct ReminderLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: String
        var fireDate: Date
        var topic: ReminderTopic
        var variant: Int
    }

    var pending: [Entry] = []
    /// Delivered and still inside their window, waiting to be scored.
    var unscored: [Entry] = []
    /// Ids of reminders the person tapped.
    var tapped: Set<String> = []
    var stats: [ReminderTopic: ReminderTopicStats] = [:]
    var lastUsed: [ReminderTopic: Date] = [:]
    var lastVariant: [ReminderTopic: Int] = [:]

    /// Brings the ledger up to date before a new plan replaces `pending`.
    /// `delivering` is false when iOS isn't allowed to show notifications:
    /// nothing passed was seen, so nothing may count against a topic.
    mutating func settle(now: Date, sessionStarts: [Date], delivering: Bool) {
        if delivering {
            for entry in pending where entry.fireDate <= now {
                unscored.append(entry)
                if (lastUsed[entry.topic] ?? .distantPast) < entry.fireDate {
                    lastUsed[entry.topic] = entry.fireDate
                    lastVariant[entry.topic] = entry.variant
                }
            }
        }
        pending = []

        var still: [Entry] = []
        for entry in unscored {
            let end = entry.fireDate.addingTimeInterval(ReminderPlanner.winWindow)
            let won = tapped.contains(entry.id)
                || sessionStarts.contains { $0 >= entry.fireDate && $0 <= end }
            if won || now >= end {
                stats[entry.topic, default: ReminderTopicStats()].sends += 1
                if won { stats[entry.topic, default: ReminderTopicStats()].wins += 1 }
                tapped.remove(entry.id)
            } else {
                still.append(entry)
            }
        }
        unscored = still
        // A tap on something no longer tracked (a reminder from before this
        // ledger existed) has nothing to score.
        tapped = tapped.filter { id in unscored.contains { $0.id == id } }
    }

    /// The new plan becomes what is pending.
    mutating func record(_ plan: [PlannedReminder]) {
        pending = plan.map { Entry(id: $0.id, fireDate: $0.fireDate, topic: $0.topic, variant: $0.variant) }
    }

    /// Reminders taken back before they fired (a session began) were never
    /// delivered, so they leave `pending` without counting.
    mutating func withdraw(ids: Set<String>) {
        pending.removeAll { ids.contains($0.id) }
    }
}
