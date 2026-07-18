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

    /// Starts a session from received params (no-op if one is already running).
    private func begin(_ p: SessionParams) async {
        guard phase == .idle else { return }
        params = p
        elapsed = 0
        let started = await workout.start(bellyBreathing: p.bellyBreathing)
        guard started else {
            statusMessage = workout.statusMessage
            params = nil
            return
        }
        phase = .running
        startTimer(planned: p.plannedDurationSec)
    }

    /// Ends the current session (Watch End button, or the timed countdown).
    func endByUser() {
        Task { await endSession() }
    }

    private func endSession() async {
        guard phase == .running, let p = params else { return }
        timer?.cancel()
        timer = nil
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
            bellyBreathing: p.bellyBreathing,
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
        guard let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.transferUserInfo([WCKeys.payload: data])
        log.debug("Sent payload for session \(payload.sessionID)")
    }

    private nonisolated func handleParams(_ dict: [String: Any]) {
        guard let data = dict[WCKeys.params] as? Data,
              let p = try? JSONDecoder().decode(SessionParams.self, from: data) else { return }
        Task { @MainActor in await self.begin(p) }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleParams(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleParams(userInfo)
    }
}
