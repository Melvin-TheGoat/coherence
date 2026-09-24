import Foundation
import SwiftUI
import SwiftData
import HealthKit
import WatchConnectivity
import UIKit
import os

/// iOS-side session pipeline.
///
/// **`begin` runs the sit on the phone and never asks about a Watch** (Aziz,
/// 2026-09-21). The wrist is no longer launched, waited for, or reported on
/// when somebody taps Begin here.
///
/// The Watch half of this class is not dead, it is just no longer something
/// the phone initiates: a session started ON the Watch still composes its own
/// params, runs the full measuring pipeline, and ships a `SessionPayload`
/// back, which `persist` writes exactly as it always did. So the two paths
/// are now phone-starts-a-timer and wrist-starts-a-measured-session, and
/// nothing in between.
///
/// iOS still holds the HealthKit entitlement and reads no biometric data.
///
/// **A phone sit keeps the screen awake the whole time** (`beginOnPhone`
/// sets `isIdleTimerDisabled`), restored on every way out
/// (`finishPhoneSession`, `discardLeftAppSession`). Without that, Auto-Lock
/// backgrounds 808 on its own somewhere between thirty seconds and a few
/// minutes in, which the leave rule below would then read as the person
/// walking away and void the sit for nobody's fault. See `LeftAppRule` and
/// `phoneScenePhaseChanged`.
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

    /// A phone sit was left for too long and is waiting on a decision:
    /// `SessionActiveView` shows `SessionLeftAppView` instead of the sit
    /// itself while this is set. Cleared by either `overrideLeftApp` or
    /// `discardLeftAppSession` — see `phoneScenePhaseChanged`.
    @Published var leftAppPrompt: LeftAppPrompt?

    struct LeftAppPrompt: Identifiable, Equatable {
        let id: UUID
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

    /// When the phone left the foreground during the active PHONE sit — nil
    /// the rest of the time. Only phone sits are tracked at all
    /// (`LeftAppRule.applies`): a Watch sit keeps measuring on the wrist no
    /// matter what the phone's screen is doing.
    private var awayEnteredAt: Date?

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

    /// Begins a session. **It runs here. The Watch is not asked about**
    /// (Aziz, 2026-09-21: "dont even ask if a watch is there").
    ///
    /// Everything that used to happen first is gone: no WatchConnectivity
    /// pairing check, no `startWatchApp`, no workout authorization, no
    /// forty-five second watchdog waiting for a wrist to confirm it began.
    /// Tapping Begin starts the sit in the same runloop turn, every time, on
    /// every phone.
    ///
    /// What that costs, stated plainly because nobody should rediscover it:
    /// **a phone-started sit is no longer measured, even for somebody wearing
    /// a Watch.** Heart rate, stillness and breath all come off the wrist, and
    /// the wrist is not being launched. A Watch owner who wants the readings
    /// starts from the Watch itself, which still runs the full pipeline and
    /// still ships its payload here (`persist`). The asymmetry is deliberate:
    /// the phone's Begin belongs to the person sitting down, and it was
    /// spending up to forty-five seconds, a permissions screen and a whole
    /// failure vocabulary on hardware most people do not own.
    /// Every session written, phone or Watch, current or stale: Block opens
    /// the rest of the windows it counts for (2026-09-22). Set once at launch
    /// by the app. A hook rather than a view's `onChange`, so a Watch
    /// session landing while 808 is in the background still opens the apps.
    static var onSessionSaved: ((_ startedAt: Date, _ durationSec: Int) -> Void)?

    func begin(mode: String, trackID: UUID?, plannedDurationSec: Int?,
               hapticsEnabled: Bool, soundID: String? = nil, headphones: Bool = false) {
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
        startAcked = false
        if let soundID { pendingSoundIDs[params.sessionID] = soundID }
        Analytics.track(.sessionStarted(source: "phone", sound: soundID ?? "silence"))
        beginOnPhone(params: params, soundID: soundID,
                     headphones: headphones, reason: "phone Begin")
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
        awayEnteredAt = nil
        leftAppPrompt = nil
        active = ActiveSession(id: params.sessionID,
                               startedAt: Date(),
                               plannedDurationSec: params.plannedDurationSec,
                               soundTitle: SoundCatalog.title(for: soundID),
                               engine: .phone)
        // Auto-lock would otherwise send 808 to the background thirty
        // seconds to a few minutes in, and the leave rule would then void
        // nearly every sit even though nobody touched the phone.
        UIApplication.shared.isIdleTimerDisabled = true
        startAudio(soundID: soundID, headphones: headphones,
                   plannedDurationSec: params.plannedDurationSec)
        status = "Meditating."

        phoneFinishTask?.cancel()
        guard let planned = params.plannedDurationSec else { return }
        // Rings at the end even with the phone locked and 808 asleep.
        SessionEndNotice.schedule(for: params.sessionID, afterSeconds: planned)
        phoneFinishTask = Task { @MainActor [weak self] in
            // A cancelled sleep THROWS and `try?` swallows it, which would run
            // the finish immediately on the cancel. Bitten three times here.
            try? await Task.sleep(for: .seconds(planned))
            guard !Task.isCancelled else { return }
            self?.finishPhoneSession(early: false)
        }
    }

    /// Ends and writes a phone-run sit. Mirrors what `persist` does for a
    /// Watch payload, minus everything there is no instrument for.
    ///
    /// `early` is End tapped before the timer ran out. Only then is the end
    /// notification taken back: on time, it is firing at this same moment and
    /// is the chime that says so.
    private func finishPhoneSession(early: Bool) {
        guard let current = active, current.engine == .phone else { return }
        // Covers every way this can be reached: on time, an early End, and
        // the too-short discard below all funnel through here.
        UIApplication.shared.isIdleTimerDisabled = false
        if early { SessionEndNotice.cancel(for: current.id) }
        phoneFinishTask?.cancel()
        phoneFinishTask = nil
        stopAudio(reason: "phone session ended")
        // The silence was for the meditation and the meditation is over.
        // `restoreIfOurs` is the guard that matters: a Focus the user had on
        // before they sat down is theirs, and 808 must not switch it off.
        Task { await FocusShortcut.shared.restoreIfOurs() }
        active = nil
        currentAttemptID = nil

        var duration = Int(Date().timeIntervalSince(current.startedAt).rounded())
        // A silent timed sit lets iOS suspend 808, so the finish can run
        // late, when the phone is next picked up. The session was the length
        // that was set, not the length of the wait.
        if let planned = current.plannedDurationSec { duration = min(duration, planned) }
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
        Self.onSessionSaved?(session.startedAt, session.durationSec)
        PendingSave.set(session.id)
        status = "Saved ✓"
        let dates = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).map(\.startedAt)
        Analytics.track(.sessionCompleted(
            durationBand: Analytics.durationBand(seconds: session.durationSec),
            streakBand: Analytics.streakBand(days: StreakCalculator.streak(from: dates).current)))
    }

    /// The scene left the foreground or came back, forwarded from
    /// `SessionActiveView` on every change. Only a phone sit is judged by
    /// this — `LeftAppRule.applies` is what makes a Watch sit exempt, since
    /// it keeps measuring on the wrist no matter what the phone's screen is
    /// doing.
    ///
    /// Melvin, 2026-09-23: "if they leave for more than 10 seconds then the
    /// meditation doesn't count," with a quiet way back in for an honest
    /// accident — see `overrideLeftApp`.
    func phoneScenePhaseChanged(_ phase: ScenePhase) {
        guard let current = active, LeftAppRule.applies(engine: current.engine) else { return }
        if LeftAppRule.isLeaving(phase) {
            guard awayEnteredAt == nil else { return }   // already tracking a departure
            awayEnteredAt = Date()
            // The clock the person set is paused with them: a background
            // finish must never race ahead of the verdict below and quietly
            // complete a session that is about to be voided for exactly the
            // reason it's finishing.
            phoneFinishTask?.cancel()
            phoneFinishTask = nil
            Task { await LeftAppNotice.post(for: current.id) }
        } else if phase == .active {
            guard let left = awayEnteredAt else { return }
            awayEnteredAt = nil
            LeftAppNotice.cancel(for: current.id)
            // Already waiting on an earlier departure this sit — a second
            // blip before it's been answered doesn't need its own verdict.
            guard leftAppPrompt == nil else { return }
            switch LeftAppRule.verdict(awaySec: Date().timeIntervalSince(left)) {
            case .continues: rearmPhoneFinish(for: current)
            case .voided: leftAppPrompt = LeftAppPrompt(id: current.id)
            }
        }
        // .inactive: Control Center, Notification Center, a system alert —
        // none of that is leaving.
    }

    /// Restarts the timed sit's own finish against the real time remaining —
    /// the sibling of the Watch-ack re-anchor above, for the same reason:
    /// wall-clock time moved while something else had the clock paused. If
    /// the planned length already passed while the person was away, there
    /// is nothing left to wait for: finish now, capped at the length that
    /// was set, exactly like any other late finish.
    private func rearmPhoneFinish(for session: ActiveSession) {
        guard let planned = session.plannedDurationSec else { return }
        let remaining = Double(planned) - Date().timeIntervalSince(session.startedAt)
        guard remaining > 0 else {
            finishPhoneSession(early: false)
            return
        }
        phoneFinishTask?.cancel()
        phoneFinishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.finishPhoneSession(early: false)
        }
    }

    /// "I was still meditating" — deliberately easy to miss rather than hard
    /// to find (Melvin: don't make the override obvious). Forgives the
    /// departure and lets the sit carry on exactly as it was; nothing here
    /// touches `startedAt`, so the time away still counts toward the
    /// session's length.
    func overrideLeftApp() {
        guard let current = active, leftAppPrompt?.id == current.id else { return }
        leftAppPrompt = nil
        rearmPhoneFinish(for: current)
    }

    /// "End session": the departure stands, and the sit ends with nothing
    /// written. Mirrors `finishPhoneSession`'s teardown, minus the write —
    /// no Session row, so no streak day and no Block release either, since
    /// both are derived from Sessions that exist.
    func discardLeftAppSession() {
        guard let current = active, leftAppPrompt?.id == current.id else { return }
        leftAppPrompt = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phoneFinishTask?.cancel()
        phoneFinishTask = nil
        SessionEndNotice.cancel(for: current.id)
        stopAudio(reason: "left the app")
        Task { await FocusShortcut.shared.restoreIfOurs() }
        active = nil
        currentAttemptID = nil
        let duration = Int(Date().timeIntervalSince(current.startedAt).rounded())
        pendingSoundIDs.removeValue(forKey: current.id)
        status = "Session discarded (left the app)"
        Analytics.track(.sessionDiscarded(reason: "left_app",
                                          durationBand: Analytics.durationBand(seconds: duration)))
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
            finishPhoneSession(early: true)
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
            Task { await FocusShortcut.shared.restoreIfOurs() }
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
        Self.onSessionSaved?(session.startedAt, session.durationSec)
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
