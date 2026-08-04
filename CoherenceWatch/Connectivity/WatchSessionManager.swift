import Foundation
import WatchConnectivity
import os

/// Watch-side session orchestration. Activates `WCSession`, receives `SessionParams`
/// from the phone, drives the workout + motion capture, and on end ships the
/// analyzed `SessionPayload` back to the phone. Watch-only.
///
/// The phone launches this app via `startWatchApp`; the actual parameters arrive
/// over WatchConnectivity (message if reachable, else queued user-info).
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case running
        case sending
        case sent
    }

    @Published var phase: Phase = .idle
    @Published var authorized = false
    @Published var elapsed = 0
    @Published var params: SessionParams?
    @Published var statusMessage: String?

    let workout = WorkoutManager()
    private var timer: Task<Void, Never>?
    /// Aborts the session if no heart rate ever arrives; see armHeartRateWatchdog.
    private var hrWatchdog: Task<Void, Never>?
    /// Sessions already started, so the three delivery channels (message,
    /// user-info, application-context) don't double-trigger and a stale context
    /// doesn't re-launch an old session.
    private var handledSessionIDs: Set<UUID> = []
    private let log = Logger(subsystem: "com.lockout.coherence.watchkitapp", category: "WatchSession")

    override init() {
        super.init()
        authorized = workout.isWorkoutAuthorized
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// One-time HealthKit workout authorization (first run).
    func authorize() async {
        _ = await HealthKitAuth.authorize()
        authorized = workout.isWorkoutAuthorized
    }

    /// Starts a session from received params (no-op if already running or if this
    /// session was already handled via another delivery channel).
    private func begin(_ p: SessionParams) async {
        // .sent is a 3-second cosmetic state; a user starting the next session
        // that fast shouldn't have it silently swallowed.
        if phase == .sent { phase = .idle }
        guard phase == .idle, !handledSessionIDs.contains(p.sessionID) else { return }
        handledSessionIDs.insert(p.sessionID)
        params = p
        elapsed = 0
        statusMessage = "Params received — starting…"   // TEMP: prove params arrived

        // Make sure authorization has actually been requested before anything
        // reads HealthKit — on a cold launch from `startWatchApp` this used to
        // race, and the read came back empty simply because we hadn't asked yet.
        await authorize()

        // NOTE: we deliberately do NOT block on a permission probe here.
        // HealthKit hides read authorization, so an empty probe means "denied"
        // OR "watch not worn" OR "asked too early" — indistinguishable. Blocking
        // on it refused sessions for users whose permissions were fully granted.
        // The gate is the watchdog below: real HR arriving once the workout runs.
        let started = await workout.start()
        guard started else {
            // workout.start() sets its own failure message; surface it on Ready.
            statusMessage = workout.statusMessage ?? "Couldn't start (unknown)."
            report(.workoutNotAuthorized, sessionID: p.sessionID)
            params = nil
            return
        }
        statusMessage = nil
        phase = .running
        startTimer(planned: p.plannedDurationSec)
        armHeartRateWatchdog(sessionID: p.sessionID)

        // Tell the phone when the workout REALLY began so its mid-session
        // clock and audio timer track this moment, not startWatchApp's
        // (seconds-earlier) callback.
        let ack = [WCKeys.started: "\(p.sessionID.uuidString)|\(Date().timeIntervalSince1970)"]
        let wc = WCSession.default
        if wc.isReachable {
            wc.sendMessage(ack, replyHandler: nil, errorHandler: nil)
        }
        wc.transferUserInfo(ack)
    }

    /// Tells the phone the session never started, so it can drop its
    /// mid-session screen and explain the fix. Sent over both channels — a
    /// message if reachable now, queued user-info regardless. Carries the
    /// sessionID so the phone can ignore a STALE refusal that flushes from
    /// this queue seconds into a later, healthy session.
    private func report(_ failure: StartFailure, sessionID: UUID) {
        let wc = WCSession.default
        let msg = [WCKeys.startFailure: "\(sessionID.uuidString)|\(failure.rawValue)"]
        if wc.isReachable {
            wc.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        }
        wc.transferUserInfo(msg)
    }

    /// Seconds of a running workout with zero heart-rate samples before we call
    /// it unreadable. The workout streams averaged HR roughly every 5 s, so
    /// this is many times the expected gap — long enough that a slow first
    /// reading can't trip it, short enough that nobody meditates for 25 minutes
    /// to find out it wasn't recording.
    private static let hrWatchdogSec = 30

    /// The honest heart-rate gate: not "does HealthKit say we're allowed"
    /// (it won't say), but "did any heart rate actually arrive". Catches denied
    /// permission, a watch that isn't on a wrist, and sensor failure alike.
    private func armHeartRateWatchdog(sessionID: UUID) {
        hrWatchdog?.cancel()
        hrWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.hrWatchdogSec))
            // A cancelled sleep THROWS and `try?` swallows it — without this the
            // action runs immediately on cancel (see CLAUDE.md, the guided-audio bug).
            guard !Task.isCancelled else { return }
            guard let self, self.phase == .running,
                  self.params?.sessionID == sessionID,
                  self.workout.hrSampleCount == 0 else { return }

            self.log.error("no heart rate after \(Self.hrWatchdogSec)s — aborting session")
            self.statusMessage = "No heart rate — check 808 in the iPhone Health app."
            _ = await self.workout.finish()      // stop the workout, discard the result
            self.timer?.cancel(); self.timer = nil
            self.phase = .idle
            self.report(.heartRateUnavailable, sessionID: sessionID)
            self.params = nil
        }
    }

    /// Ends the current session (Watch End button, or the timed countdown).
    func endByUser() {
        Task { await endSession() }
    }

    private func endSession() async {
        guard phase == .running, let p = params else { return }
        timer?.cancel()
        timer = nil
        hrWatchdog?.cancel()
        hrWatchdog = nil
        phase = .sending

        guard let finished = await workout.finish() else {
            phase = .idle
            params = nil
            return
        }

        let discard = finished.durationSec < SessionStore.minDurationSec
        let payload = SessionPayload(
            sessionID: p.sessionID,
            startedAt: finished.startedAt,
            mode: p.mode,
            trackID: p.trackID,
            bellyBreathing: false,
            durationSec: finished.durationSec,
            discard: discard,
            result: discard ? nil : finished.result
        )
        send(payload)
        phase = .sent
        params = nil

        // Return to idle so another session can start.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.phase == .sent { self.phase = .idle }
        }
    }

    private func startTimer(planned: Int?) {
        timer = Task { @MainActor [weak self] in
            var e = 0
            while let self, self.phase == .running {
                self.elapsed = e
                if let planned, e >= planned {
                    await self.endSession()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                e += 1
            }
        }
    }

    private func send(_ payload: SessionPayload) {
        // Don't swallow encode failures — a non-finite Double makes JSONEncoder
        // throw, which previously dropped the whole transfer silently (belly-nil bug).
        do {
            let data = try JSONEncoder().encode(payload)
            WCSession.default.transferUserInfo([WCKeys.payload: data])
            log.debug("Sent payload for session \(payload.sessionID)")
        } catch {
            log.error("Payload encode FAILED — session NOT sent: \(String(describing: error))")
            statusMessage = "Send failed (encode)."
        }
    }

    private nonisolated func handleParams(_ dict: [String: Any]) {
        guard let data = dict[WCKeys.params] as? Data,
              let p = try? JSONDecoder().decode(SessionParams.self, from: data) else { return }
        Task { @MainActor in await self.begin(p) }
    }

    /// Phone → Watch "end now" (the phone's mid-session End button). Ignored
    /// unless the id matches the running session, so a stale end from a previous
    /// session can't cut a later one short.
    private nonisolated func handleEnd(_ dict: [String: Any]) {
        guard let raw = dict[WCKeys.end] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            guard self.params?.sessionID == id else { return }
            await self.endSession()
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // A params context queued before the app launched is delivered here.
        if activationState == .activated {
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty { handleParams(ctx) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleParams(message)
        handleEnd(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleParams(userInfo)
        handleEnd(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleParams(applicationContext)
    }
}
