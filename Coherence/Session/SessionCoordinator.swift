import Foundation
import SwiftData
import HealthKit
import WatchConnectivity
import os

/// iOS-side session pipeline. Sends `SessionParams` to the Watch, launches the
/// watch workout via `startWatchApp`, receives the finished `SessionPayload`, and
/// persists it via `SessionStore`.
///
/// iOS uses HealthKit ONLY to authorize + issue `startWatchApp` — it reads no
/// biometric data. All analysis happens on the Watch; all persistence here.
@MainActor
final class SessionCoordinator: NSObject, ObservableObject {

    /// One-line status of the current attempt (Phase-4 debug UI).
    @Published var status: String = "Idle"
    /// Summary of the most recently persisted session (Phase-4 debug UI).
    @Published var lastSummary: String?

    private let container: ModelContainer
    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.lockout.coherence", category: "SessionCoordinator")

    init(container: ModelContainer) {
        self.container = container
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Requests the iOS workout authorization `startWatchApp` needs (share + read
    /// of the workout type only — no biometric reads).
    func requestWorkoutAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workout = HKObjectType.workoutType()
        try? await healthStore.requestAuthorization(toShare: [workout], read: [workout])
    }

    /// Begins a session: sends params to the Watch and launches its workout.
    func begin(mode: String, trackID: UUID?, plannedDurationSec: Int?, bellyBreathing: Bool, hapticsEnabled: Bool) {
        Task {
            await requestWorkoutAuthorization()

            let params = SessionParams(
                sessionID: UUID(),
                mode: mode,
                trackID: trackID,
                plannedDurationSec: plannedDurationSec,
                bellyBreathing: bellyBreathing,
                hapticsEnabled: hapticsEnabled
            )

            // Deliver params over every available channel: queued user-info
            // always; a message if reachable now; and application-context so a
            // cold-launching watch app picks it up on activation (dedup'd by
            // sessionID on the watch).
            if let data = try? JSONEncoder().encode(params) {
                let wc = WCSession.default
                wc.transferUserInfo([WCKeys.params: data])
                if wc.isReachable {
                    wc.sendMessage([WCKeys.params: data], replyHandler: nil, errorHandler: nil)
                }
                if wc.activationState == .activated {
                    try? wc.updateApplicationContext([WCKeys.params: data])
                }
            }

            // Launch / foreground the watch workout.
            let config = HKWorkoutConfiguration()
            config.activityType = .mindAndBody
            config.locationType = .unknown
            healthStore.startWatchApp(with: config) { [weak self] success, error in
                Task { @MainActor in
                    guard let self else { return }
                    if success {
                        self.status = "Watch launched — meditate, then End on the Watch"
                    } else {
                        self.status = "startWatchApp failed: \(error?.localizedDescription ?? "unknown")"
                        self.log.error("startWatchApp failed: \(String(describing: error))")
                    }
                }
            }
            status = "Starting on your Watch…"
        }
    }

    private func persist(_ payload: SessionPayload) {
        // The session is complete — clear the "start" command from the persistent
        // application context so a cold-launching Watch can't replay a finished
        // session (application context lingers until overwritten).
        try? WCSession.default.updateApplicationContext([:])

        let context = container.mainContext
        guard let session = SessionStore.persist(payload, in: context) else {
            status = "Session discarded (too short / unreadable)"
            return
        }
        let stats = statsFor(session.id, in: context)
        let streak = StreakCalculator.streak(from: SessionStore.sessionStartDates(in: context))
        lastSummary = summaryLine(session: session, stats: stats, currentStreak: streak.current)
        status = "Saved ✓"
    }

    private func statsFor(_ sessionID: UUID, in context: ModelContext) -> MeditationStats? {
        let d = FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == sessionID })
        return try? context.fetch(d).first
    }

    private func summaryLine(session: Session, stats: MeditationStats?, currentStreak: Int) -> String {
        func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
        let breaths = stats?.meanBreathingRate.map { String(format: "%.1f", $0) } ?? "nil"
        return """
        dur \(session.durationSec)s · belly \(session.bellyBreathing)
        stillness \(f(stats?.stillnessScore)) (\(stats?.stillnessMethod ?? "?"))
        hrDecline \(f(stats?.hrDecline)) · breaths \(breaths)
        overall \(f(stats?.overallScore)) · streak \(currentStreak)
        HR pts \(stats?.heartRateTimeseries.count ?? 0)
        """
    }
}

extension SessionCoordinator: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WCKeys.payload] as? Data,
              let payload = try? JSONDecoder().decode(SessionPayload.self, from: data) else { return }
        Task { @MainActor in self.persist(payload) }
    }
}
