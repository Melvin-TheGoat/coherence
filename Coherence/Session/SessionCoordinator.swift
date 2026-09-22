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
    /// The current attempt's payload arrived but was too short or unreadable
    /// to persist. The onboarding walkthrough listens so its "scoring it"
    /// state can resolve honestly instead of waiting forever.
    @Published var lastDiscardedID: UUID?
    /// The same event with what the "too short" screen needs. Separate from
    /// `lastDiscardedID` so the walkthrough's listener is untouched.
    @Published var lastDiscard: Discard?

    struct Discard: Identifiable, Equatable {
        let id: UUID
        let durationSec: Int
        /// Under the minimum (an accident) rather than long but unreadable.
        var tooShort: Bool { durationSec < SessionStore.minDurationSec }
    }
    /// True once the Watch has ACKED the current attempt's actual workout
    /// start. `active` alone is a phone-side guess: `startWatchApp`'s callback
    /// fires seconds (a cold Watch: tens of seconds) before the wrist really
    /// begins, which is why the mid-session clock re-anchors on the ack. The
    /// onboarding demo waits for THIS, so its orb and countdown start with
    /// the Watch instead of ahead of it (Aziz, 2026-08-31).
    @Published private(set) var startAcked = false
    /// Whether onboarding is complete, mirrored to the Watch inside every
    /// application-context update. The Watch's start screen gates on it: a
    /// wrist Begin before the phone is set up would run a session into an app
    /// that cannot yet receive it.
    private(set) var onboarded = false
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
        /// Who is running the sit. Defaulted to `.watch` so every existing
        /// construction below reads the same.
        var engine: Engine = .watch
    }

    /// **The Watch is optional.** 808 runs the sit on the phone unless a Watch
    /// is actually there to measure it, and a Watch that fails to answer hands
    /// the sit back rather than ending it.
    ///
    /// The reasoning is the product's, not the plumbing's: a meditation app
    /// that refuses to time a meditation because of missing hardware has
    /// stopped being a meditation app. The measurements were always the bonus
    /// on top of sitting down, and they stay exactly that.
    enum Engine: String { case watch, phone }

    /// Finishes a timed phone sit on its own clock, since there is no wrist to
    /// fire the authoritative end.
    private var phoneFinishTask: Task<Void, Never>?

    /// Sound preset chosen at Begin, keyed by sessionID — the Watch never
    /// carries it, so the phone holds it until the payload lands.
    private var pendingSoundIDs: [UUID: String] = [:]

    /// The session the user most recently began (set at Begin, before the Watch
    /// answers — `active` is still nil in that window). Launching the watch app
    /// flushes its queued transferUserInfo backlog, so STALE payloads/failures
    /// from old sessions can land seconds into a new one; everything that stops
    /// audio or tears down the live screen must match against this first.
    private var currentAttemptID: UUID?

    /// True between the Watch's "ending" announcement and the payload landing:
    /// the live screen is already down, and the home screen shows a small
    /// receiving banner so the handoff never looks frozen.
    @Published var receivingFromWatch = false

    private let container: ModelContainer
    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.lockout.meditate808", category: "SessionCoordinator")

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
            // Is there a wrist to measure this, or are we on our own? Asked
            // before anything is launched, because the answer decides which
            // pipeline runs, and because `startWatchApp` fails the same way
            // whether no Watch is paired, the app was never installed on it,
            // or it is simply out of range.
            let watchReady = await watchIsReady()

            let params = SessionParams(
                sessionID: UUID(),
                mode: mode,
                trackID: trackID,
                plannedDurationSec: plannedDurationSec,
                bellyBreathing: false,
                hapticsEnabled: hapticsEnabled,
                sentAt: Date()
            )
            currentAttemptID = params.sessionID
            await MainActor.run { self.startAcked = false }
            if let soundID { pendingSoundIDs[params.sessionID] = soundID }
            Analytics.track(.sessionStarted(source: "phone", sound: soundID ?? "silence"))

            guard watchReady else {
                await MainActor.run {
                    self.beginOnPhone(params: params, soundID: soundID,
                                      headphones: headphones, reason: "no Watch")
                }
                return
            }

            await requestWorkoutAuthorization()

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
                    try? wc.updateApplicationContext([WCKeys.params: data,
                                                      WCKeys.onboarded: true])
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
                        self.status = "Watch launched. Meditate, then End on the Watch."
                        // The session is live: show the phone's mid-session screen.
                        self.active = ActiveSession(id: params.sessionID,
                                                    startedAt: Date(),
                                                    plannedDurationSec: plannedDurationSec,
                                                    soundTitle: SoundCatalog.title(for: soundID))
                        // Play the chosen sound on the phone while the Watch measures.
                        self.startAudio(soundID: soundID, headphones: headphones,
                                        plannedDurationSec: plannedDurationSec)
                        self.armStartWatchdog(for: params.sessionID)
                    } else {
                        // The Watch would not launch. That used to end the
                        // attempt with a screen about permissions; it now
                        // costs the measurements and nothing else, because the
                        // sit can run here.
                        self.log.error("startWatchApp failed, running on the phone: \(String(describing: error))")
                        self.beginOnPhone(params: params, soundID: soundID,
                                          headphones: headphones,
                                          reason: "the Watch would not start")
                    }
                }
            }
            status = "Starting on your Watch…"
        }
    }

    /// Whether there is a Watch that can actually measure this sit.
    ///
    /// Waits for WatchConnectivity to activate before reading `isPaired`,
    /// rather than skipping the check when it has not settled: activation is
    /// async and routinely unsettled on the first Begin after launch. Two
    /// seconds is far longer than activation takes and invisible next to the
    /// Watch app launching.
    private func watchIsReady() async -> Bool {
        guard WCSession.isSupported() else { return false }
        let wc = WCSession.default
        if wc.activationState != .activated {
            wc.activate()
            for _ in 0..<20 where wc.activationState != .activated {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard wc.activationState == .activated else { return false }
        return wc.isPaired && wc.isWatchAppInstalled
    }

    /// Runs the whole sit here: the phone keeps the clock, plays the sound,
    /// and writes the session when it ends.
    ///
    /// Nothing is measured, so nothing is scored, and the session is stored
    /// with no `MeditationStats` rather than an empty one. The difference
    /// matters: an empty row claims we looked and found nothing, and nothing
    /// was looking.
    private func beginOnPhone(params: SessionParams, soundID: String?,
                              headphones: Bool, reason: String) {
        log.info("Running session \(params.sessionID) on the phone (\(reason))")
        startAcked = true
        startFailure = nil
        active = ActiveSession(id: params.sessionID,
                               startedAt: Date(),
                               plannedDurationSec: params.plannedDurationSec,
                               soundTitle: SoundCatalog.title(for: soundID),
                               engine: .phone)
        startAudio(soundID: soundID, headphones: headphones,
                   plannedDurationSec: params.plannedDurationSec)
        status = "Meditating."

        phoneFinishTask?.cancel()
        guard let planned = params.plannedDurationSec else { return }
        phoneFinishTask = Task { @MainActor [weak self] in
            // A cancelled sleep THROWS and `try?` swallows it, which would run
            // the finish immediately on the cancel. Bitten three times here.
            try? await Task.sleep(for: .seconds(planned))
            guard !Task.isCancelled else { return }
            self?.finishPhoneSession()
        }
    }

    /// The Watch was supposed to be measuring and never answered. Take the sit
    /// over here rather than end it: somebody has been sitting for the length
    /// of the watchdog, and losing that is a worse outcome than losing the
    /// measurements.
    private func convertToPhoneSession(sessionID: UUID) {
        guard let current = active, current.id == sessionID,
              current.engine == .watch else { return }
        log.info("The Watch never answered for \(sessionID); finishing on the phone")
        active = ActiveSession(id: current.id,
                               startedAt: current.startedAt,
                               plannedDurationSec: current.plannedDurationSec,
                               soundTitle: current.soundTitle,
                               engine: .phone)
        startAcked = true
        status = "Meditating."
        guard let planned = current.plannedDurationSec else { return }
        let remaining = Double(planned) - Date().timeIntervalSince(current.startedAt)
        phoneFinishTask?.cancel()
        phoneFinishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, remaining)))
            guard !Task.isCancelled else { return }
            self?.finishPhoneSession()
        }
    }

    /// Ends and writes a phone-run sit. Mirrors what `persist` does for a
    /// Watch payload, minus everything there is no instrument for.
    private func finishPhoneSession() {
        guard let current = active, current.engine == .phone else { return }
        phoneFinishTask?.cancel()
        phoneFinishTask = nil
        stopAudio(reason: "phone session ended")
        active = nil
        currentAttemptID = nil

        let duration = Int(Date().timeIntervalSince(current.startedAt).rounded())
        let soundID = pendingSoundIDs.removeValue(forKey: current.id)
        let context = container.mainContext
        guard let session = SessionStore.persistPhoneSession(
            id: current.id,
            startedAt: current.startedAt,
            mode: SoundCatalog.mode(for: soundID),
            frequencyID: soundID,
            durationSec: duration,
            in: context) else {
            // Under the floor. A Begin-then-End by accident is not a broken
            // session and must not read as one.
            status = "Session discarded (too short)"
            lastDiscardedID = current.id
            lastDiscard = Discard(id: current.id, durationSec: duration)
            Analytics.track(.sessionDiscarded(reason: "too_short",
                                              durationBand: Analytics.durationBand(seconds: duration)))
            return
        }
        lastSessionID = session.id
        PendingSave.set(session.id)
        status = "Saved ✓"
        let dates = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).map(\.startedAt)
        Analytics.track(.sessionCompleted(
            durationBand: Analytics.durationBand(seconds: session.durationSec),
            streakBand: Analytics.streakBand(days: StreakCalculator.streak(from: dates).current)))
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

    /// How long to wait for the Watch to confirm it really started.
    ///
    /// Generous on purpose. It has to cold-launch the app, clear HealthKit, and
    /// spin up a workout, and on a fresh install the user may be tapping an
    /// Allow prompt on their wrist while this runs. Firing early costs a wrong
    /// error message; firing late costs someone a whole meditation. Neither
    /// costs data: the Watch keeps recording either way and `persist` is
    /// idempotent, so a session that started slowly still lands.
    private static let startAckTimeoutSec = 45.0

    /// Cancelled the instant the Watch confirms it began. See armStartWatchdog.
    private var startWatchdog: Task<Void, Never>?

    /// `startWatchApp` reporting success means iOS accepted the launch request,
    /// not that anything is measuring.
    ///
    /// The phone treated it as proof: it raised the mid-session screen and
    /// started the track, so a launch that never actually reached the Watch
    /// looked exactly like a running session, for as long as the user sat
    /// there. The Watch announces a genuine start with `WCKeys.started` over
    /// both channels, so the absence of that ack is the thing to watch for.
    private func armStartWatchdog(for sessionID: UUID) {
        startWatchdog?.cancel()
        startWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.startAckTimeoutSec))
            // A cancelled sleep throws and `try?` swallows it, which would run
            // the failure path immediately on the ack we were waiting for.
            guard !Task.isCancelled, let self else { return }
            guard self.currentAttemptID == sessionID else { return }
            self.log.error("no start ack from the Watch after \(Self.startAckTimeoutSec)s")
            self.convertToPhoneSession(sessionID: sessionID)
        }
    }

    /// The Watch reported its ACTUAL workout start. Re-anchor the mid-session
    /// clock and the audio-stop timer to it — `startWatchApp`'s callback fires
    /// seconds before the Watch really begins (params delivery + HealthKit
    /// check + workout spin-up), which made the phone's countdown reach 0:00
    /// while the Watch still had time left.
    private func watchStarted(sessionID: UUID, at startedAt: Date) {
        // Cancel before the guard: this ack is the proof the watchdog waits
        // for, and it counts even if `active` has already moved on.
        if sessionID == currentAttemptID { startWatchdog?.cancel() }
        // The ack arrived for a session the phone is not showing. Either it
        // gave up (the watchdog fired while the Watch was locked and could not
        // reach us) or the Watch is telling us it is already running something
        // else. Both mean a real session IS being measured, so adopt it rather
        // than leave the truth on the wrist. Aziz, 2026-09-16: locked Watch at
        // Begin, phone said it could not start, the Watch was at 33 seconds.
        if active?.id != sessionID {
            guard adoptRunningSession(sessionID: sessionID, at: startedAt) else { return }
        }
        guard let current = active, current.id == sessionID else { return }
        startAcked = true
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

    /// Takes over a session the Watch says it is running but the phone is not
    /// showing. Returns false when the ack should be ignored.
    ///
    /// The danger here is the stale-WC-queue family (bitten four times): a
    /// queued ack from a finished session replaying hours later would
    /// resurrect a dead session's screen. Two guards, and both must hold: the
    /// session cannot already be persisted (a finished one always is), and it
    /// must have begun recently enough to still be running.
    @discardableResult
    private func adoptRunningSession(sessionID: UUID, at startedAt: Date) -> Bool {
        let context = container.mainContext
        let existing = try? context.fetch(
            FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID }))
        guard Self.shouldAdopt(startedAt: startedAt,
                               alreadyPersisted: !((existing ?? []).isEmpty)) else {
            log.info("Ignoring a start ack for \(sessionID): not a session that can still be running")
            return false
        }

        log.info("Adopting the Watch's running session \(sessionID)")
        // A different attempt may be in flight (they pressed Begin again while
        // the Watch was still busy). Its watchdog would otherwise fire and tear
        // down the session we just adopted.
        startWatchdog?.cancel()
        startFailure = nil
        currentAttemptID = sessionID
        startAcked = true
        active = ActiveSession(id: sessionID,
                               startedAt: startedAt,
                               plannedDurationSec: nil,
                               soundTitle: SoundCatalog.title(for: pendingSoundIDs[sessionID]))
        status = "Running on your Watch"
        return true
    }

    /// Past this, a start ack describes a session that cannot still be running,
    /// so it is a queued message replaying rather than news. Generous, because
    /// an open-ended sit has no upper bound and only the Watch ends it.
    static let maxAdoptAgeSec: TimeInterval = 4 * 60 * 60

    /// Whether a start ack for a session the phone is not showing should be
    /// taken over. Pure, so the stale-queue guards can be tested without a
    /// Watch: a queued ack replaying from a finished session must never
    /// resurrect its screen, and a persisted session is by definition finished.
    nonisolated static func shouldAdopt(startedAt: Date, now: Date = Date(),
                                        alreadyPersisted: Bool) -> Bool {
        guard !alreadyPersisted else { return false }
        let age = now.timeIntervalSince(startedAt)
        // A start stamped in the future is a clock skew, not news.
        return age >= 0 && age < maxAdoptAgeSec
    }

    /// Ends the running session from the phone. The Watch still performs the
    /// authoritative finish (analysis + haptic) and ships the payload back —
    /// this only asks it to stop now. The mid-session screen stays up until that
    /// payload lands, so we never claim a result we don't have yet.
    func endActiveSession() {
        guard let active else { return }
        // No wrist involved: this screen owns the whole session, so ending it
        // here is the end of it.
        if active.engine == .phone {
            finishPhoneSession()
            return
        }
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
        // The Watch is reporting a refusal for a sit that is already running
        // here, because the watchdog gave up on it and handed it over. The
        // session is real and somebody is in the middle of it; a blocking
        // screen about Watch permissions would end it.
        if active?.engine == .phone {
            log.info("Ignoring \(failure.rawValue): this sit is running on the phone")
            return
        }
        stopAudio(reason: "start failure: \(failure.rawValue)")
        active = nil
        currentAttemptID = nil
        startFailure = failure
        status = "Couldn't start: \(failure.rawValue)"
        Analytics.track(.sessionStartFailed(reason: failure.rawValue))
        log.error("session refused to start: \(failure.rawValue)")
    }

    /// Stops live-session audio (called when the session ends).
    private func stopAudio(reason: String = "session end") {
        audioStopTask?.cancel()
        audioStopTask = nil
        tone.stop(reason: reason)
    }

    /// RootView reports onboarding state here (at launch and on change); the
    /// Watch hears about it through the application context. Sign-out resets
    /// `onboardingComplete`, so a signed-out phone re-gates the wrist too.
    func setOnboarded(_ done: Bool) {
        onboarded = done
        try? WCSession.default.updateApplicationContext([WCKeys.onboarded: done])
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
            receivingFromWatch = false
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
            // Clearing the start command must not also clear the Watch's
            // onboarded flag, which rides the same context.
            try? WCSession.default.updateApplicationContext([WCKeys.onboarded: onboarded])
        } else {
            log.info("Stale payload \(payload.sessionID) persisted without touching the live session")
        }

        let soundID = pendingSoundIDs.removeValue(forKey: payload.sessionID)

        let context = container.mainContext
        guard let session = SessionStore.persist(payload, frequencyID: soundID,
                                                 in: context) else {
            if isCurrent {
                status = "Session discarded (too short / unreadable)"
                lastDiscardedID = payload.sessionID
                let discard = Discard(id: payload.sessionID, durationSec: payload.durationSec)
                lastDiscard = discard
                // Its own event, NOT a failure: a Begin-then-End by accident is
                // not a broken session and must not read as one on the
                // dashboard. Long-but-unreadable is tracked apart from it.
                Analytics.track(.sessionDiscarded(reason: discard.tooShort ? "too_short" : "unreadable",
                                                  durationBand: Analytics.durationBand(seconds: payload.durationSec)))
            }
            return
        }
        guard isCurrent else { return }
        lastSessionID = session.id
        // Survives the app being suspended or killed between the Watch
        // shipping the payload and the person picking the phone up, which is
        // how a session ends nearly every time. See PendingSave.
        PendingSave.set(session.id)
        status = "Saved ✓"
        let dates = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).map(\.startedAt)
        Analytics.track(.sessionCompleted(
            durationBand: Analytics.durationBand(seconds: session.durationSec),
            streakBand: Analytics.streakBand(days: StreakCalculator.streak(from: dates).current)))
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

    /// Raw motion captures from DEBUG Watch builds (the posture-free-breathing
    /// and tremor experiments). Saved into Documents/MotionCaptures so they're
    /// visible in the Files app (AirDrop to the Mac) and reachable by devicectl.
    ///
    /// The file at `file.fileURL` is deleted by the system when this returns,
    /// so the copy must happen synchronously, not in a Task.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("MotionCaptures", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(file.fileURL.lastPathComponent)
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: file.fileURL, to: dest)
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
            return
        }
        if let raw = dict[WCKeys.ending] as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in self.watchEnding(sessionID: id) }
            return
        }
        if let raw = dict[WCKeys.watchBegin] as? String {
            // "<sessionID>|<epoch>|<soundID or empty>". Arrives over
            // sendMessage only (never queued), so it can't replay stale.
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count == 3, let id = UUID(uuidString: String(parts[0])),
               let epoch = Double(parts[1]) {
                let soundID = parts[2].isEmpty ? nil : String(parts[2])
                Task { @MainActor in
                    self.joinWatchSession(sessionID: id,
                                          at: Date(timeIntervalSince1970: epoch),
                                          soundID: soundID)
                }
            }
        }
    }

    /// End was tapped on the Watch: drop the live screen and stop audio NOW,
    /// then show the small "receiving" note until the payload lands. Without
    /// this the phone sat frozen mid-session for the seconds the Watch spends
    /// finishing the workout, waiting out the HRV settle, and shipping.
    @MainActor
    private func watchEnding(sessionID: UUID) {
        guard sessionID == currentAttemptID else { return }   // stale-safe
        // A session that is ending obviously started. Unlike the other terminal
        // paths this one keeps `currentAttemptID` (the payload is still coming),
        // so the watchdog's own guard would not stop it firing mid-handover.
        startWatchdog?.cancel()
        stopAudio(reason: "watch ending")
        active = nil
        receivingFromWatch = true
        status = "Receiving from your Watch…"
        // Safety valve: if the payload somehow never arrives on the immediate
        // channel (it queues instead), don't pin a banner forever — history
        // updates live via @Query whenever it lands.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self.receivingFromWatch = false
        }
    }

    /// A session the Watch initiated: the phone joins it — mid-session screen
    /// up, chosen sound playing — instead of orchestrating it. Everything
    /// downstream (started re-anchor, payload, persist) is the existing path.
    @MainActor
    private func joinWatchSession(sessionID: UUID, at startedAt: Date, soundID: String?) {
        guard currentAttemptID != sessionID else { return }   // double delivery
        currentAttemptID = sessionID
        if let soundID { pendingSoundIDs[sessionID] = soundID }
        Analytics.track(.sessionStarted(source: "watch", sound: soundID ?? "silence"))
        startAcked = true
        active = ActiveSession(id: sessionID,
                               startedAt: startedAt,
                               plannedDurationSec: nil,
                               soundTitle: SoundCatalog.title(for: soundID))
        startAudio(soundID: soundID, headphones: false, plannedDurationSec: nil)
        status = "Started from your Watch. Meditate, then End on the Watch."
    }
}
