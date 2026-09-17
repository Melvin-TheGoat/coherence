import Foundation
import WatchConnectivity
import WatchKit
import os

/// Watch-side session orchestration. Activates `WCSession`, receives `SessionParams`
/// from the phone, drives the workout + motion capture, and on end ships the
/// analyzed `SessionPayload` back to the phone. Watch-only.
///
/// The phone launches this app via `startWatchApp`; the actual parameters arrive
/// over WatchConnectivity (message if reachable, else queued user-info).
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    /// Whether the PHONE has finished onboarding, last we heard. Gates the
    /// start screen: a wrist Begin before the phone is set up would run a
    /// session into an app that cannot receive it, so the Watch says "finish
    /// setup on your iPhone" instead. Persisted, because the Watch launches
    /// cold with no phone in reach and must remember the last known answer;
    /// a fresh install defaults to NOT onboarded, which is the honest state
    /// for a Watch whose phone app has never run.
    @Published var phoneOnboarded =
        UserDefaults.standard.bool(forKey: "phoneOnboarded.v1")

    /// Reads the onboarded flag wherever it appears; it rides every
    /// application-context update from the phone, including the post-session
    /// clear.
    private nonisolated func handleOnboarded(_ dict: [String: Any]) {
        if let done = dict[WCKeys.onboarded] as? Bool {
            Task { @MainActor in self.applyOnboarded(done) }
        }
    }

    @MainActor private func applyOnboarded(_ done: Bool) {
        guard done != phoneOnboarded else { return }
        phoneOnboarded = done
        UserDefaults.standard.set(done, forKey: "phoneOnboarded.v1")
    }

    enum Phase: Equatable {
        case idle
        case running
        case sending
        case sent
    }

    @Published var phase: Phase = .idle
    /// Seconds left before a wrist-started session begins; nil when no
    /// countdown is running. The phone counts five seconds down before it
    /// sends params ("Get comfortable"), so a session started from the wrist
    /// gets the same five (Melvin, 2026-09-15). Numbers on screen only: the
    /// Watch plays no haptics, and a countdown is no exception.
    @Published var countdown: Int?
    private var countdownTask: Task<Void, Never>?
    @Published var authorized = false
    @Published var elapsed = 0
    @Published var params: SessionParams?
    @Published var statusMessage: String?

    /// The sound chosen on the Watch for watch-initiated sessions. Persisted
    /// between sessions; nil/empty = Silence. Audio always plays on the PHONE
    /// (the Watch bundles none), so this is a request, not a player.
    @Published var soundID: String? = UserDefaults.standard.string(forKey: soundKey) {
        didSet { UserDefaults.standard.set(soundID, forKey: Self.soundKey) }
    }
    private static let soundKey = "watchSoundID"

    /// Whether the phone acknowledged this watch-initiated session (reachable
    /// at Begin). False + a chosen sound = the live screen's honest note that
    /// today is silent.
    @Published var phoneLinked = true
    /// Whether the finished payload went over the immediate channel, so the
    /// Sent screen can say "Delivered" vs "Saved, syncing when in range"
    /// without guessing.
    @Published var deliveredImmediately = false
    /// True when this session began on the Watch (drives the silence note —
    /// phone-initiated sessions manage their own audio).
    @Published var startedOnWatch = false

    let workout = WorkoutManager()
    private var timer: Task<Void, Never>?
    /// Wall-clock anchor for `elapsed`. A sleep-loop counter drifts a few
    /// seconds behind over a long session; deriving from the clock keeps the
    /// Watch and the phone (which also derives from the clock) in agreement.
    private var sessionStartedAt: Date?
    /// Aborts the session if no heart rate ever arrives; see armHeartRateWatchdog.
    private var hrWatchdog: Task<Void, Never>?
    /// Sessions already started, so the three delivery channels (message,
    /// user-info, application-context) don't double-trigger and a stale context
    /// doesn't re-launch an old session.
    private var handledSessionIDs: Set<UUID> = []
    private let log = Logger(subsystem: "com.lockout.meditate808.watchkitapp", category: "WatchSession")

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

    /// Begin from the wrist: the Watch composes its own params instead of
    /// waiting for the phone's. Same pipeline from here on — workout, motion,
    /// engine, payload — and the phone persists idempotently as always. The
    /// one extra step is telling a reachable phone to join (live screen +
    /// audio); an unreachable phone costs only the sound.
    func beginFromWatch() {
        guard countdown == nil, phase == .idle || phase == .sent else { return }
        let chosen = (soundID?.isEmpty == false) ? soundID : nil
        let p = SessionParams(
            sessionID: UUID(),
            mode: SoundMenu.mode(for: chosen),
            trackID: nil,
            plannedDurationSec: nil,      // wrist sessions are open-ended
            bellyBreathing: false,
            hapticsEnabled: true,
            sentAt: Date()
        )
        countdown = 5
        countdownTask = Task { @MainActor [weak self] in
            while let self, let n = self.countdown, n > 0 {
                // A cancelled sleep THROWS and `try?` swallows it; without the
                // guard, Cancel would start the session (CLAUDE.md, the
                // guided-audio bug).
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.countdown = n - 1
            }
            guard !Task.isCancelled, let self else { return }
            self.countdown = nil
            await self.begin(p, watchInitiated: true)
        }
    }

    /// Cancel on the countdown screen: back to the start screen, nothing sent.
    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    /// Starts a session from received params (no-op if already running or if this
    /// session was already handled via another delivery channel).
    private func begin(_ p: SessionParams, watchInitiated: Bool = false) async {
        // The phone's start wins over a countdown still ticking on the wrist.
        if !watchInitiated { cancelCountdown() }
        // .sent is a 3-second cosmetic state; a user starting the next session
        // that fast shouldn't have it silently swallowed.
        if phase == .sent { phase = .idle }
        // Begin arrived while a session is already running on the wrist. It
        // used to be dropped in silence, so the phone armed a screen for a
        // session the Watch would never start and failed 45 seconds later,
        // twice over (Aziz, 2026-09-16: locked Watch, a false failure, then
        // Begin again did nothing). Tell the phone what IS running; its
        // adoption path takes over from there.
        if phase == .running, !watchInitiated, let running = params,
           running.sessionID != p.sessionID {
            handledSessionIDs.insert(p.sessionID)   // never start it later
            announceRunningSession()
            return
        }
        guard phase == .idle, !handledSessionIDs.contains(p.sessionID) else { return }
        // A cold launch flushes the queued backlog of start commands from
        // every earlier attempt, oldest first, and running one resurrects a
        // session the phone gave up on long ago (Aziz's demo, 2026-08-31:
        // Watch off at Begin, the Watch ran a stale id, the fresh command was
        // dropped by the phase guard above, and the phone waited forever for
        // a payload it could only file as stale). A start command is honoured
        // only inside its freshness window. Params with no `sentAt` come from
        // an old build's queue and are stale by definition. Watch-initiated
        // sessions stamp their own `sentAt` and pass untouched.
        if !watchInitiated {
            guard let sentAt = p.sentAt, Date().timeIntervalSince(sentAt) < 180 else {
                handledSessionIDs.insert(p.sessionID)   // never revisit it
                statusMessage = nil
                return
            }
        }
        handledSessionIDs.insert(p.sessionID)
        params = p
        elapsed = 0
        statusMessage = "Starting…"

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
        startedOnWatch = watchInitiated
        sessionStartedAt = Date()
        startTimer(planned: p.plannedDurationSec)
        armHeartRateWatchdog(sessionID: p.sessionID)

        let wc = WCSession.default
        if watchInitiated {
            invitePhone(sessionID: p.sessionID, startedAt: Date())
        } else {
            // Tell the phone when the workout REALLY began so its mid-session
            // clock and audio timer track this moment, not startWatchApp's
            // (seconds-earlier) callback.
            let ack = [WCKeys.started: "\(p.sessionID.uuidString)|\(Date().timeIntervalSince1970)"]
            if wc.isReachable {
                wc.sendMessage(ack, replyHandler: nil, errorHandler: nil)
            }
            wc.transferUserInfo(ack)
        }
    }

    /// Re-announces the session already running here, as a start ack for its
    /// own id. Both channels, because the reason the phone is out of step is
    /// usually that the first ack could not be delivered promptly (a locked
    /// Watch is not reachable, so only the queued copy went out).
    private func announceRunningSession() {
        guard phase == .running, let p = params, let startedAt = sessionStartedAt else { return }
        let ack = [WCKeys.started: "\(p.sessionID.uuidString)|\(startedAt.timeIntervalSince1970)"]
        let wc = WCSession.default
        if wc.isReachable { wc.sendMessage(ack, replyHandler: nil, errorHandler: nil) }
        wc.transferUserInfo(ack)
        log.info("Told the phone a session is already running here")
    }

    /// Invites the phone to join a wrist-started session: live screen + the
    /// chosen sound.
    ///
    /// **Retries, because reachability is not ready when Begin is tapped.**
    /// `WCSession` activation and the reachability handshake settle
    /// asynchronously, so on the FIRST Begin after the watch app launches
    /// `isReachable` is routinely still false — the invite was dropped and the
    /// phone showed nothing, while the second attempt of the same session
    /// worked. Now it polls for roughly fourteen seconds, sending the instant
    /// the link comes up, and gives up quietly if the session ends first.
    ///
    /// Still `sendMessage` only. A queued invite replaying hours later would
    /// resurrect a dead session's live screen — the stale-WC-queue family of
    /// bugs this codebase has been bitten by twice.
    private func invitePhone(sessionID: UUID, startedAt: Date) {
        let value = "\(sessionID.uuidString)|\(startedAt.timeIntervalSince1970)|\(soundID ?? "")"
        phoneLinked = false
        Task { @MainActor [weak self] in
            for attempt in 0..<12 {
                guard let self, self.phase == .running,
                      self.params?.sessionID == sessionID else { return }
                if WCSession.default.isReachable {
                    WCSession.default.sendMessage([WCKeys.watchBegin: value],
                                                  replyHandler: nil) { [weak self] error in
                        self?.log.error("join failed: \(error.localizedDescription)")
                        Task { @MainActor in self?.phoneLinked = false }
                    }
                    self.phoneLinked = true
                    return
                }
                // Tight at first (the handshake usually lands in under a
                // second), then patient.
                try? await Task.sleep(for: .milliseconds(attempt < 4 ? 400 : 1500))
                guard !Task.isCancelled else { return }
            }
        }
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
            self.statusMessage = "No heart rate. Check 808 in the iPhone Health app."
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

        // Tell the phone NOW, before the seconds of workout teardown + HRV
        // settle: it drops the live screen immediately and shows "receiving"
        // instead of looking frozen until the payload lands.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([WCKeys.ending: p.sessionID.uuidString],
                                          replyHandler: nil, errorHandler: nil)
        }

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
            result: discard ? nil : finished.result,
            hrv: discard ? nil : finished.hrv
        )
        send(payload)

        #if DEBUG
        // Ship the raw 100 Hz motion capture to the phone for the offline
        // posture-free-breathing / tremor analysis. transferFile queues and
        // survives the app backgrounding; the phone saves it into Documents.
        if let url = workout.rawMotionCaptureURL(sessionID: p.sessionID) {
            WCSession.default.transferFile(url, metadata: ["sessionID": p.sessionID.uuidString])
        }
        #endif

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
            while let self, self.phase == .running {
                let e = self.sessionStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
                self.elapsed = e
                if let planned, e >= planned {
                    await self.endSession()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func send(_ payload: SessionPayload) {
        // Don't swallow encode failures — a non-finite Double makes JSONEncoder
        // throw, which previously dropped the whole transfer silently (belly-nil bug).
        do {
            let data = try JSONEncoder().encode(payload)
            let dict: [String: Any] = [WCKeys.payload: data]

            // Both channels, deliberately — the same treatment params get in
            // the other direction, and for the same reason. transferUserInfo
            // is guaranteed but QUEUED: even with both apps live it can sit
            // for tens of seconds, which read on the phone as "End on the
            // Watch does nothing" while the finished session idled in the
            // queue. sendMessage is immediate whenever the phone is reachable.
            // The phone dedupes by sessionID (idempotent persist), so hearing
            // it twice is harmless; hearing it late was the bug.
            if WCSession.default.isReachable {
                deliveredImmediately = true
                WCSession.default.sendMessage(dict, replyHandler: nil) { error in
                    self.log.error("sendMessage failed (userInfo backstop stands): \(error.localizedDescription)")
                    Task { @MainActor in self.deliveredImmediately = false }
                }
            } else {
                deliveredImmediately = false
            }
            WCSession.default.transferUserInfo(dict)
            log.debug("Sent payload for session \(payload.sessionID) (reachable=\(WCSession.default.isReachable))")
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
            if !ctx.isEmpty { handleParams(ctx); handleOnboarded(ctx) }
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
        handleOnboarded(applicationContext)
    }

    /// The link came back. If a session is running here, say so again: the
    /// usual reason the phone is out of step is that the FIRST ack could not
    /// be sent because the Watch was locked and therefore unreachable, so the
    /// moment it is reachable is the moment to repeat it. This is what makes
    /// the phone recover on its own when the wrist is unlocked, with nothing
    /// for the user to do.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in
            guard let self, self.phase == .running else { return }
            self.announceRunningSession()
        }
    }
}
