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

    /// One-line status of the current attempt (logged; surfaced if needed).
    @Published var status: String = "Idle"
    /// ID of the most recently persisted session — opens the results graphs.
    @Published var lastSessionID: UUID?

    /// Sound preset chosen at Begin, keyed by sessionID — the Watch never
    /// carries it, so the phone holds it until the payload lands.
    private var pendingSoundIDs: [UUID: String] = [:]

    private let container: ModelContainer
    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.lockout.coherence", category: "SessionCoordinator")

    /// Live-session audio (phone-side): plays the chosen tone + bed during the
    /// meditation and stops on the timer / when the Watch payload lands.
    private let tone = ToneEngine()
    private var audioStopTask: Task<Void, Never>?

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

    /// Begins a session: sends params to the Watch and launches its workout. If a
    /// `soundID` is given, the phone plays that frequency tone+bed OR nature sound
    /// during the session.
    func begin(mode: String, trackID: UUID?, plannedDurationSec: Int?, bellyBreathing: Bool,
               hapticsEnabled: Bool, soundID: String? = nil, headphones: Bool = false) {
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
            if let soundID { pendingSoundIDs[params.sessionID] = soundID }

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
                        // Play the chosen sound on the phone while the Watch measures.
                        self.startAudio(soundID: soundID, headphones: headphones,
                                        plannedDurationSec: plannedDurationSec)
                    } else {
                        self.status = "startWatchApp failed: \(error?.localizedDescription ?? "unknown")"
                        self.log.error("startWatchApp failed: \(String(describing: error))")
                    }
                }
            }
            status = "Starting on your Watch…"
        }
    }

    /// Starts the selected tone + bed, and (for timed sessions) schedules a phone-side
    /// stop — the Watch fires the authoritative end-haptic; this timer only stops audio.
    private func startAudio(soundID: String?, headphones: Bool, plannedDurationSec: Int?) {
        audioStopTask?.cancel()
        tone.stop()
        guard let id = soundID else { return }
        if let fp = FrequencyCatalog.preset(id: id) {
            tone.play(fp, method: headphones ? .binaural : .isochronic)
        } else if let np = NatureCatalog.preset(id: id) {
            tone.playNature(np)
        } else if let gp = GuidedCatalog.preset(id: id) {
            tone.playGuided(gp)
        } else {
            return
        }
        if let planned = plannedDurationSec {
            audioStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(planned))
                self?.tone.stop()
            }
        }
    }

    /// Stops live-session audio (called when the session ends).
    private func stopAudio() {
        audioStopTask?.cancel()
        audioStopTask = nil
        tone.stop()
    }

    private func persist(_ payload: SessionPayload) {
        // Session ended (Watch End for open-ended, or the Watch's own timer) — stop
        // the phone audio now. For timed sessions the parallel timer may have already
        // stopped it; stopAudio() is idempotent.
        stopAudio()

        // The session is complete — clear the "start" command from the persistent
        // application context so a cold-launching Watch can't replay a finished
        // session (application context lingers until overwritten).
        try? WCSession.default.updateApplicationContext([:])

        let soundID = pendingSoundIDs.removeValue(forKey: payload.sessionID)

        let context = container.mainContext
        guard let session = SessionStore.persist(payload, frequencyID: soundID, in: context) else {
            status = "Session discarded (too short / unreadable)"
            return
        }
        lastSessionID = session.id
        status = "Saved ✓"
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
