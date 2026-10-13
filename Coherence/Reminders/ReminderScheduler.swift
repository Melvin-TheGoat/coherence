import Foundation
import SwiftData
import UserNotifications

/// Puts `ReminderPlanner`'s plan in front of iOS, and keeps it current.
///
/// **Replan whenever anything a reminder says could have changed**: 808
/// coming to the front, a session landing or being deleted, a session
/// discarded, the reminder settings changing. Each replan takes back every
/// pending reminder and schedules the plan again from what is stored, so a
/// session today always cancels the rest of today's nudges, and the copy
/// (streak, glow, held apps) is worked out for the day it fires.
///
/// Everything here stays on the phone: the ledger is UserDefaults, the
/// notifications are local, and nothing is sent anywhere.
@MainActor
enum ReminderScheduler {
    /// Every reminder's identifier starts with this; nothing else does.
    static let idPrefix = "reminder."
    /// The one repeating reminder 808 sent before 2026-10-12, taken back
    /// on the first replan.
    static let legacyID = "daily-meditation-reminder"

    private static let ledgerKey = "reminders.ledger.v1"
    nonisolated private static let cadenceKey = "reminders.cadence.v1"
    nonisolated private static let profileKey = "reminders.profile.v1"
    private static let lastOpenedKey = "reminders.lastOpened.v1"

    private static var container: ModelContainer?
    private static var generation = 0

    /// Called once at launch, so callers without a context can replan.
    static func install(container: ModelContainer) {
        self.container = container
    }

    // MARK: Settings and profile

    nonisolated static var cadence: ReminderCadence {
        get { UserDefaults.standard.string(forKey: cadenceKey).flatMap(ReminderCadence.init) ?? .smart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cadenceKey) }
    }

    nonisolated static var profile: ReminderProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: profileKey) else { return ReminderProfile() }
            return (try? JSONDecoder().decode(ReminderProfile.self, from: data)) ?? ReminderProfile()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: profileKey) }
    }

    /// 808 came to the front: the person is around, whether or not they sit.
    static func noteOpened(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastOpenedKey)
    }

    /// A reminder was tapped: its topic counts as having worked.
    static func noteTapped(_ id: String) {
        guard id.hasPrefix(idPrefix) else { return }
        var ledger = loadLedger()
        ledger.tapped.insert(id)
        saveLedger(ledger)
    }

    // MARK: Scheduling

    /// Takes back the rest of today's reminders while a session runs, so
    /// nothing buzzes mid-meditation. The session's end replans.
    static func holdForSession(now: Date = Date()) {
        // A replan already running would put them straight back.
        generation += 1
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
        var ledger = loadLedger()
        let ids = Set(ledger.pending.filter { $0.fireDate >= now && $0.fireDate < end }.map(\.id))
        guard !ids.isEmpty else { return }
        ledger.withdraw(ids: ids)
        saveLedger(ledger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(ids))
    }

    /// Everything off: Settings switched reminders off, or the account went.
    static func cancelAll() {
        generation += 1
        var ledger = loadLedger()
        ledger.pending = []
        saveLedger(ledger)
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) || $0 == legacyID }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Rebuilds every pending reminder from what is stored.
    static func replan(now: Date = Date()) {
        guard let container else { return }
        generation += 1
        let mine = generation
        let context = container.mainContext
        let prefs = (try? context.fetch(FetchDescriptor<Preferences>(sortBy: [SortDescriptor(\.createdAt)])))?.first
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard mine == generation else { return }   // a newer replan is running
            let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
            let delivering = allowed.contains(settings.authorizationStatus)

            var ledger = loadLedger()
            ledger.settle(now: now, sessionStarts: sessions.map(\.startedAt), delivering: delivering)

            let old = await center.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) || $0 == legacyID }
            guard mine == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: old)

            #if DEBUG
            // PREVIEW_REMINDERS=1: plan from the real store and print it,
            // scheduling nothing. A simulator can't flip the reminder switch
            // or answer the permission prompt from a script.
            if ProcessInfo.processInfo.environment["PREVIEW_REMINDERS"] != nil, let prefs {
                var rng = SystemRandomNumberGenerator()
                let dry = ReminderPlanner.plan(makeInput(now: now, prefs: prefs, sessions: sessions,
                                                         ledger: ledger), using: &rng)
                let f = DateFormatter()
                f.dateFormat = "EEE d HH:mm"
                NSLog("Reminders (dry run): %d planned\n%@", dry.count,
                      dry.map { "  \(f.string(from: $0.fireDate)) [\($0.slot.rawValue)] \($0.topic.rawValue): \($0.title) / \($0.body)" }
                        .joined(separator: "\n"))
            }
            #endif
            guard delivering, let prefs, prefs.remindersEnabled, prefs.onboardingComplete else {
                ledger.pending = []
                saveLedger(ledger)
                return
            }

            let input = makeInput(now: now, prefs: prefs, sessions: sessions, ledger: ledger)
            var rng = SystemRandomNumberGenerator()
            let plan = ReminderPlanner.plan(input, using: &rng)
            ledger.record(plan)
            saveLedger(ledger)
            for reminder in plan {
                try? await center.add(request(for: reminder))
            }
            #if DEBUG
            // The plan, readable from a phone or simulator console
            // (`devicectl ... --console` / `simctl launch --console`).
            let f = DateFormatter()
            f.dateFormat = "EEE HH:mm"
            NSLog("Reminders: %d planned. %@", plan.count,
                  plan.prefix(6).map { "\(f.string(from: $0.fireDate)) \($0.topic.rawValue): \($0.title)" }
                    .joined(separator: " | "))
            #endif
        }
    }

    private static func makeInput(now: Date, prefs: Preferences, sessions: [Session],
                                  ledger: ReminderLedger) -> ReminderInput {
        let cal = Calendar.current
        let time = prefs.reminderTime
            ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        var input = ReminderInput(
            now: now,
            calendar: cal,
            sessionStarts: sessions.map(\.startedAt),
            sits: sessions.map { OttoAura.Sit(date: $0.startedAt, seconds: $0.durationSec) },
            // Priced into the glow exactly as Home shows it. Screen Time's
            // state only ever shapes a notification on this phone.
            notNow: FeatureFlags.block ? BlockController.shared.notNowWindows : [],
            glowSince: OttoAura.glowStart(),
            lastOpened: UserDefaults.standard.object(forKey: lastOpenedKey) as? Date,
            hour: cal.component(.hour, from: time),
            minute: cal.component(.minute, from: time),
            cadence: cadence,
            profile: profile,
            stats: ledger.stats,
            lastUsed: ledger.lastUsed,
            lastVariant: ledger.lastVariant)
        if FeatureFlags.block {
            let state = BlockController.shared.state
            input.appsHeld = { !BlockRules.holding(state, at: $0, calendar: cal).isEmpty }
        }
        if FeatureFlags.shop {
            let owned = prefs.ownedHatIDList
            let balance = OttoPoints.balance(sessions: sessions, ownedHatIDs: owned)
            if let next = HatCatalog.all
                .filter({ !owned.contains($0.id) && $0.price > balance })
                .min(by: { $0.price < $1.price }) {
                input.nextHat = (next.name, next.price - balance)
            }
        }
        return input
    }

    private static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        // Active, never time sensitive: a reminder to meditate can wait for
        // a Focus to end, and asking for more would be the fastest way to
        // get notifications switched off.
        content.interruptionLevel = .active
        content.threadIdentifier = "reminders"
        content.relevanceScore = reminder.slot == .lastCall ? 0.8 : 0.5
        content.userInfo = [userInfoKey: reminder.topic.rawValue]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                    from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    /// Marks a reminder in `userInfo`, carrying its topic.
    static let userInfoKey = "reminderTopic"

    // MARK: Ledger storage

    private static func loadLedger() -> ReminderLedger {
        guard let data = UserDefaults.standard.data(forKey: ledgerKey) else { return ReminderLedger() }
        return (try? JSONDecoder().decode(ReminderLedger.self, from: data)) ?? ReminderLedger()
    }

    private static func saveLedger(_ ledger: ReminderLedger) {
        UserDefaults.standard.set(try? JSONEncoder().encode(ledger), forKey: ledgerKey)
    }

    /// Sign-out and account deletion: forget what this phone learned.
    static func forget() {
        cancelAll()
        for key in [ledgerKey, cadenceKey, profileKey, lastOpenedKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
