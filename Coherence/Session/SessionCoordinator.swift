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
    /// The session currently running on the Watch — drives the phone's
    /// mid-session screen. Non-nil from a successful `startWatchApp` until the
    /// payload lands.
    @Published private(set) var active: ActiveSession?

    /// Set when the Watch refuses to start a session — drives the blocking
    /// explanation screen. Cleared when the user dismisses it.
    @Published var startFailure: StartFailure?

    /// What the phone needs to render the mid-session screen.
    struct ActiveSession: Identifiable, Equatable {
        let id: UUID
        let startedAt: Date
        /// nil for open-ended sessions (ended from the Watch or the phone).
        let plannedDurationSec: Int?
        /// Human title of the sound playing, for the plan chip ("Deep Meditation").
        var soundTitle: String? = nil
    }

    /// Sound preset chosen at Begin, keyed by sessionID — the Watch never
    /// carries it, so the phone holds it until the payload lands.
    private var pendingSoundIDs: [UUID: String] = [:]

    /// The session the user most recently began (set at Begin, before the Watch
    /// answers — `active` is still nil in that window). Launching the watch app
    /// flushes its queued transferUserInfo backlog, so STALE payloads/failures
    /// from old sessions can land seconds into a new one; everything that stops
    /// audio or tears down the live screen must match against this first.
    private var currentAttemptID: UUID?

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
    func begin(mode: String, trackID: UUID?, plannedDurationSec: Int?,
               hapticsEnabled: Bool, soundID: String? = nil, headphones: Bool = false) {
        Task {
            await requestWorkoutAuthorization()

            let params = SessionParams(
                sessionID: UUID(),
                mode: mode,
                trackID: trackID,
                plannedDurationSec: plannedDurationSec,
                bellyBreathing: false,
                hapticsEnabled: hapticsEnabled
            )
            currentAttemptID = params.sessionID
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
                        // The session is live: show the phone's mid-session screen.
                        self.active = ActiveSession(id: params.sessionID,
                                                    startedAt: Date(),
                                                    plannedDurationSec: plannedDurationSec,
                                                    soundTitle: SoundCatalog.title(for: soundID))
                        // Play the chosen sound on the phone while the Watch measures.
                        self.startAudio(soundID: soundID, headphones: headphones,
                                        plannedDurationSec: plannedDurationSec)
                    } else {
                        // Previously silent — the user tapped Begin and nothing
                        // visibly happened. Now it's a first-class refusal.
                        self.log.error("startWatchApp failed: \(String(describing: error))")
                        self.sessionFailedToStart(.watchUnreachable)
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
        tone.stop(reason: "new session start")
        guard let id = soundID else { return }
        if let fp = FrequencyCatalog.preset(id: id) {
            tone.play(fp, method: headphones ? .binaural : .isochronic)
        } else if let np = NatureCatalog.preset(id: id) {
            tone.playNature(np)
        } else if let gp = GuidedCatalog.preset(id: id) {
            tone.playGuided(gp)
        } else {
            log.error("startAudio: unknown sound id \(id)")
            return
        }
        if let planned = plannedDurationSec {
            audioStopTask = Task { @MainActor [weak self] in
                // A cancelled sleep THROWS, and `try?` swallows it — without this
                // guard, cancelling the task (the watch-ack re-anchor does) would
                // fire the stop immediately instead of never. That was the
                // "guided track cuts out after one word" bug.
                try? await Task.sleep(for: .seconds(planned))
                guard !Task.isCancelled else { return }
                self?.tone.stop(reason: "planned timer")
            }
        }
    }

    /// The Watch reported its ACTUAL workout start. Re-anchor the mid-session
    /// clock and the audio-stop timer to it — `startWatchApp`'s callback fires
    /// seconds before the Watch really begins (params delivery + HealthKit
    /// check + workout spin-up), which made the phone's countdown reach 0:00
    /// while the Watch still had time left.
    private func watchStarted(sessionID: UUID, at startedAt: Date) {
        guard let current = active, current.id == sessionID else { return }
        active = ActiveSession(id: current.id,
                               startedAt: startedAt,
                               plannedDurationSec: current.plannedDurationSec,
                               soundTitle: current.soundTitle)
        if let planned = current.plannedDurationSec {
            let remaining = Double(planned) - Date().timeIntervalSince(startedAt)
            audioStopTask?.cancel()
            audioStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, remaining)))
                guard !Task.isCancelled else { return }
                self?.tone.stop(reason: "planned timer (re-anchored, \(Int(remaining))s left)")
            }
        }
    }

    /// Ends the running session from the phone. The Watch still performs the
    /// authoritative finish (analysis + haptic) and ships the payload back —
    /// this only asks it to stop now. The mid-session screen stays up until that
    /// payload lands, so we never claim a result we don't have yet.
    func endActiveSession() {
        guard let active else { return }
        stopAudio(reason: "user ended on phone")
        let wc = WCSession.default
        let msg = [WCKeys.end: active.id.uuidString]
        if wc.isReachable {
            wc.sendMessage(msg, replyHandler: nil, errorHandler: { [weak self] error in
                self?.log.error("end sendMessage failed: \(error.localizedDescription)")
            })
        }
        // Queued delivery too, in case the Watch isn't reachable this instant.
        wc.transferUserInfo(msg)
        status = "Ending on your Watch…"
    }

    /// The Watch refused to start. Tear down the mid-session screen and audio —
    /// there is no session — and surface what to fix. `sessionID` is nil for
    /// phone-local failures (startWatchApp itself failed); Watch-sent reports
    /// carry the id so a STALE refusal flushed from the Watch's queue can't
    /// kill a newer, healthy session.
    private func sessionFailedToStart(_ failure: StartFailure, sessionID: UUID? = nil) {
        if let sessionID, sessionID != currentAttemptID {
            log.info("Stale start-failure for \(sessionID) ignored")
            return
        }
        stopAudio(reason: "start failure: \(failure.rawValue)")
        active = nil
        currentAttemptID = nil
        startFailure = failure
        status = "Couldn't start: \(failure.rawValue)"
        log.error("session refused to start: \(failure.rawValue)")
    }

    /// Stops live-session audio (called when the session ends).
    private func stopAudio(reason: String = "session end") {
        audioStopTask?.cancel()
        audioStopTask = nil
        tone.stop(reason: reason)
    }

    private func persist(_ payload: SessionPayload) {
        // A payload is "ours" if it matches the session the user just began, or
        // if no attempt is in flight (e.g. the app relaunched mid-session and the
        // payload finally landed). A STALE payload — flushed from the Watch's
        // transferUserInfo queue when the watch app launches for a NEW session —
        // still gets persisted below (it's a real finished session), but it must
        // not stop the new session's audio or tear down its screen.
        let isCurrent = currentAttemptID == nil || payload.sessionID == currentAttemptID

        if isCurrent {
            // Session ended (Watch End for open-ended, or the Watch's own timer) —
            // stop the phone audio now. For timed sessions the parallel timer may
            // have already stopped it; stopAudio() is idempotent.
            stopAudio(reason: "payload landed")
            // The session is over — take down the mid-session screen.
            active = nil
            currentAttemptID = nil

            // The session is complete — clear the "start" command from the persistent
            // application context so a cold-launching Watch can't replay a finished
            // session (application context lingers until overwritten).
            try? WCSession.default.updateApplicationContext([:])
        } else {
            log.info("Stale payload \(payload.sessionID) persisted without touching the live session")
        }

        let soundID = pendingSoundIDs.removeValue(forKey: payload.sessionID)

        let context = container.mainContext
        guard let session = SessionStore.persist(payload, frequencyID: soundID,
                                                 in: context) else {
            if isCurrent { status = "Session discarded (too short / unreadable)" }
            return
        }
        guard isCurrent else { return }
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
        handle(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    /// Both delivery channels carry the same payloads — a finished session, or
    /// a refusal to start.
    private nonisolated func handle(_ dict: [String: Any]) {
        if let data = dict[WCKeys.payload] as? Data,
           let payload = try? JSONDecoder().decode(SessionPayload.self, from: data) {
            Task { @MainActor in self.persist(payload) }
            return
        }
        if let raw = dict[WCKeys.startFailure] as? String {
            // New format "<sessionID>|<failure>" (so stale refusals are matchable);
            // bare "<failure>" accepted from older Watch builds.
            let parts = raw.split(separator: "|")
            let id = parts.count == 2 ? UUID(uuidString: String(parts[0])) : nil
            if let failure = StartFailure(rawValue: String(parts.last ?? "")) {
                Task { @MainActor in self.sessionFailedToStart(failure, sessionID: id) }
            }
            return
        }
        if let raw = dict[WCKeys.started] as? String {
            let parts = raw.split(separator: "|")
            if parts.count == 2, let id = UUID(uuidString: String(parts[0])),
               let epoch = Double(parts[1]) {
                Task { @MainActor in
                    self.watchStarted(sessionID: id, at: Date(timeIntervalSince1970: epoch))
                }
            }
        }
    }
}
