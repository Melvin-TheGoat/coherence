#if DEBUG
import Foundation
import HealthKit
import CoreMotion
import UIKit
import os

/// DEBUG-ONLY hardware probe for the no-Watch path: heart rate from AirPods
/// Pro 3 / Powerbeats Pro 2 through an iPhone-side workout session (iOS 26),
/// plus head motion from `CMHeadphoneMotionManager`. See AIRPODS_PLAN.md.
///
/// This is the deliberate FIRST place the iOS target reads a biometric.
/// CLAUDE.md's rule ("the iOS target reads zero biometric data") is a fact
/// about Release builds: this whole folder is compiled out of Release, and
/// `HealthScopeTests.test_theiOSTargetQueriesNoHealthData` enforces that
/// `Coherence/AirPods/` is the only exception and that every file in it stays
/// wrapped in `#if DEBUG`.
///
/// What it does: asks the shared `HealthScope`, starts a `.mindAndBody`
/// `HKWorkoutSession` on the phone (Apple's support pages say the buds only
/// measure heart rate during a workout), reads every heart-rate sample the
/// system writes through an anchored query (so cadence and the source device
/// are MEASURED, not assumed; the live builder's statistics are shown beside
/// it), streams headphone device motion, shows live counts, and writes CSVs
/// into `Documents/AirPodsCaptures/` for offline analysis. The workout is
/// DISCARDED at stop: a probe run must never appear in Health as a session.
@available(iOS 26.0, *)
@MainActor
final class AirPodsProbe: NSObject, ObservableObject {

    enum Phase: String {
        case idle = "Idle"
        case authorizing = "Asking Health"
        case starting = "Starting workout"
        case running = "Running"
        case stopping = "Stopping"
        case stopped = "Stopped"
    }

    struct CaptureFile: Identifiable {
        let name: String
        let bytes: Int
        var id: String { name }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var elapsedSec = 0
    @Published private(set) var summary = AirPodsCaptureBuffer.Summary()
    @Published private(set) var motionAvailable = false
    @Published private(set) var motionAuthorization = "unknown"
    @Published private(set) var files: [CaptureFile] = []

    /// The buffers live outside the actor so CoreMotion's queue and HealthKit's
    /// queue can append without hopping to main (same shape as the Watch's
    /// `MotionRecorder`). The main-actor ticker reads a summary twice a second.
    nonisolated let buffer = AirPodsCaptureBuffer()

    private let store = HKHealthStore()
    private let headphones = CMHeadphoneMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "AirPodsProbe.motion"
        return q
    }()
    nonisolated private let log = Logger(subsystem: "com.lockout.meditate808", category: "AirPodsProbe")

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var hrQuery: HKAnchoredObjectQuery?
    private var ticker: Task<Void, Never>?
    private var stopFallback: Task<Void, Never>?
    private var finishing = false
    private var captureID = ""

    static var capturesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AirPodsCaptures", isDirectory: true)
    }

    override init() {
        super.init()
        refreshFiles()
    }

    // MARK: Start

    func start() async {
        guard phase == .idle || phase == .stopped else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health data is not available on this device."
            return
        }
        message = nil
        finishing = false
        buffer.reset()
        summary = AirPodsCaptureBuffer.Summary()
        elapsedSec = 0
        phase = .authorizing

        _ = await HealthScope.request(using: store)
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            message = "Workouts are not shared with 808. Health app > Sharing > Apps > 808, then try again."
            phase = .idle
            return
        }

        phase = .starting
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            let began: Bool = await withCheckedContinuation { cont in
                builder.beginCollection(withStart: start) { ok, error in
                    if let error { self.log.error("beginCollection failed: \(error.localizedDescription)") }
                    cont.resume(returning: ok)
                }
            }
            guard began else {
                message = "The workout builder refused to begin collection."
                teardown()
                phase = .idle
                return
            }
            startedAt = start
            captureID = String(UUID().uuidString.prefix(8))
            startHeartRateQuery(from: start)
            startMotion(reference: start)
            // Keep the screen on for the first captures so lock behaviour is a
            // separate, deliberate test rather than a confound.
            UIApplication.shared.isIdleTimerDisabled = true
            phase = .running
            startTicker()
        } catch {
            message = "Workout session error: \(error.localizedDescription)"
            teardown()
            phase = .idle
        }
    }

    /// Every heart-rate sample written to Health from the moment the workout
    /// started, whoever wrote it. The source name on each sample is the proof
    /// of where the number came from ("AirPods Pro 3", a Watch, a strap).
    private func startHeartRateQuery(from start: Date) {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let buffer = self.buffer
        let log = self.log
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            _, samples, _, _, error in
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let error {
                log.error("HR query: \(error.localizedDescription)")
                buffer.note("HR query error: \(error.localizedDescription)")
                return
            }
            for sample in (samples ?? []).compactMap({ $0 as? HKQuantitySample }) {
                buffer.appendHR(uuid: sample.uuid,
                                t: sample.startDate.timeIntervalSince(start),
                                bpm: sample.quantity.doubleValue(for: unit),
                                source: sample.device?.name ?? sample.sourceRevision.source.name)
            }
        }
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        hrQuery = query
    }

    private func startMotion(reference: Date) {
        motionAvailable = headphones.isDeviceMotionAvailable
        motionAuthorization = Self.describe(CMHeadphoneMotionManager.authorizationStatus())
        guard motionAvailable else {
            buffer.note("Headphone motion not available: connect AirPods with head tracking and wear them.")
            return
        }
        headphones.delegate = self
        let buffer = self.buffer
        headphones.startDeviceMotionUpdates(to: motionQueue) { motion, error in
            if let error { buffer.note("Motion error: \(error.localizedDescription)") }
            guard let motion else { return }
            let a = motion.userAcceleration
            buffer.appendMotion(AirPodsCaptureBuffer.MotionRow(
                t: Date().timeIntervalSince(reference),
                pitch: motion.attitude.pitch, roll: motion.attitude.roll, yaw: motion.attitude.yaw,
                ax: a.x, ay: a.y, az: a.z))
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                // A cancelled sleep throws, try? swallows it, and the body would
                // run once more. Same trap as the session audio timer.
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                ticks += 1
                if ticks % 60 == 0 { self.flush() }   // every 30 s, so a crash keeps most of it
            }
        }
    }

    private func refresh() {
        if let startedAt { elapsedSec = Int(Date().timeIntervalSince(startedAt)) }
        summary = buffer.summary(now: startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        if let note = summary.lastNote, note != message { message = note }
    }

    // MARK: Stop

    func stop() {
        guard phase == .running else { return }
        phase = .stopping
        headphones.stopDeviceMotionUpdates()
        if let hrQuery { store.stop(hrQuery) }
        hrQuery = nil
        ticker?.cancel()
        ticker = nil
        UIApplication.shared.isIdleTimerDisabled = false
        refresh()
        flush()
        // WWDC25 session 322: stopActivity first, then endCollection once the
        // session reports .stopped (handled in the delegate below).
        session?.stopActivity(with: Date())
        stopFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.log.error("no .stopped state within 5 s; finishing anyway")
            await self.finishAfterStop()
        }
    }

    private func finishAfterStop() async {
        guard !finishing else { return }
        finishing = true
        stopFallback?.cancel()
        stopFallback = nil
        if let builder {
            await withCheckedContinuation { cont in
                builder.endCollection(withEnd: Date()) { _, _ in cont.resume() }
            }
            // A probe run is not a session: nothing lands in Health from us.
            builder.discardWorkout()
        }
        session?.end()
        session = nil
        builder = nil
        phase = .stopped
    }

    private func teardown() {
        headphones.stopDeviceMotionUpdates()
        if let hrQuery { store.stop(hrQuery) }
        hrQuery = nil
        ticker?.cancel()
        ticker = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if let session, session.state != .ended, session.state != .notStarted {
            session.end()
        }
        session = nil
        builder = nil
    }

    // MARK: Files

    /// Writes the two CSVs (and a small meta file) atomically. Called every
    /// 30 s while running and once at stop; each call rewrites the whole file.
    func flush() {
        guard !captureID.isEmpty, let startedAt else { return }
        let dir = Self.capturesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let hr = buffer.snapshotHR()
        var hrCSV = "t,bpm\n"
        hrCSV.reserveCapacity(hr.count * 16)
        for r in hr { hrCSV += String(format: "%.3f,%.1f\n", r.t, r.bpm) }

        let motion = buffer.snapshotMotion()
        var motionCSV = "t,pitch,roll,yaw,ax,ay,az\n"
        motionCSV.reserveCapacity(motion.count * 70)
        for r in motion {
            motionCSV += String(format: "%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f\n",
                                r.t, r.pitch, r.roll, r.yaw, r.ax, r.ay, r.az)
        }

        let iso = ISO8601DateFormatter().string(from: startedAt)
        let meta = """
        capture=\(captureID)
        started=\(iso)
        startedEpoch=\(startedAt.timeIntervalSince1970)
        device=\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)
        hrSamples=\(hr.count)
        hrSources=\(buffer.sourcesSeen().joined(separator: "|"))
        motionSamples=\(motion.count)
        motionAvailable=\(motionAvailable)
        motionAuthorization=\(motionAuthorization)
        elapsedSec=\(elapsedSec)

        """
        do {
            try hrCSV.write(to: dir.appendingPathComponent("airpods-\(captureID)-hr.csv"), atomically: true, encoding: .utf8)
            try motionCSV.write(to: dir.appendingPathComponent("airpods-\(captureID)-motion.csv"), atomically: true, encoding: .utf8)
            try meta.write(to: dir.appendingPathComponent("airpods-\(captureID)-meta.txt"), atomically: true, encoding: .utf8)
        } catch {
            message = "Could not write capture: \(error.localizedDescription)"
        }
        refreshFiles()
    }

    func refreshFiles() {
        let dir = Self.capturesDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        files = urls
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return CaptureFile(name: url.lastPathComponent, bytes: size)
            }
            .sorted { $0.name > $1.name }
    }

    func deleteAllCaptures() {
        try? FileManager.default.removeItem(at: Self.capturesDirectory)
        refreshFiles()
    }

    private static func describe(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Delegates (all nonisolated; they only touch the Sendable buffer + log)

@available(iOS 26.0, *)
extension AirPodsProbe: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }
        let bpm = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        if let bpm { buffer.setBuilderBPM(bpm) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

@available(iOS 26.0, *)
extension AirPodsProbe: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        log.debug("workout session \(fromState.rawValue) -> \(toState.rawValue)")
        buffer.note("Workout state: \(Self.name(toState))")
        if toState == .stopped {
            Task { @MainActor in await self.finishAfterStop() }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        log.error("workout session failed: \(error.localizedDescription)")
        buffer.note("Workout failed: \(error.localizedDescription)")
        Task { @MainActor in
            self.teardown()
            self.phase = .stopped
        }
    }

    nonisolated private static func name(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted: return "not started"
        case .prepared: return "prepared"
        case .running: return "running"
        case .paused: return "paused"
        case .stopped: return "stopped"
        case .ended: return "ended"
        @unknown default: return "unknown"
        }
    }
}

@available(iOS 26.0, *)
extension AirPodsProbe: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        buffer.setMotionConnected(true)
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        buffer.setMotionConnected(false)
    }
}

// MARK: - Buffer

/// Lock-protected capture buffers, written from CoreMotion's and HealthKit's
/// queues, read from the main actor. `@unchecked Sendable` because every
/// access goes through the lock.
final class AirPodsCaptureBuffer: @unchecked Sendable {

    struct MotionRow {
        let t: Double
        let pitch: Double
        let roll: Double
        let yaw: Double
        let ax: Double
        let ay: Double
        let az: Double
    }

    struct HRRow {
        let t: Double
        let bpm: Double
    }

    struct Summary {
        var hrCount = 0
        var lastBPM: Double?
        var lastHRSource: String?
        var lastHRGapSec: Double?
        var lastHRAgeSec: Double?
        var builderBPM: Double?
        var motionConnected = false
        var motionCount = 0
        var motionRateHz: Double = 0
        var lastPitch: Double?
        var lastRoll: Double?
        var lastYaw: Double?
        var lastAccel: Double?
        var lastNote: String?
    }

    private let lock = NSLock()
    private var hr: [HRRow] = []
    private var seen = Set<UUID>()
    private var sources: [String] = []
    private var lastSource: String?
    private var builderBPM: Double?
    private var motion: [MotionRow] = []
    private var recentMotion: [Double] = []
    private var connected = false
    private var note: String?

    func reset() {
        lock.lock(); defer { lock.unlock() }
        hr.removeAll(keepingCapacity: true)
        seen.removeAll()
        sources.removeAll()
        lastSource = nil
        builderBPM = nil
        motion.removeAll(keepingCapacity: true)
        recentMotion.removeAll()
        note = nil
    }

    func appendHR(uuid: UUID, t: Double, bpm: Double, source: String) {
        lock.lock(); defer { lock.unlock() }
        guard !seen.contains(uuid) else { return }
        seen.insert(uuid)
        hr.append(HRRow(t: t, bpm: bpm))
        lastSource = source
        if !sources.contains(source) { sources.append(source) }
    }

    func appendMotion(_ row: MotionRow) {
        lock.lock(); defer { lock.unlock() }
        motion.append(row)
        recentMotion.append(row.t)
        while let first = recentMotion.first, first < row.t - 2 { recentMotion.removeFirst() }
    }

    func setBuilderBPM(_ bpm: Double) {
        lock.lock(); defer { lock.unlock() }
        builderBPM = bpm
    }

    func setMotionConnected(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        connected = value
        note = value ? "Headphones connected for motion." : "Headphones disconnected (out of ear, or switched device)."
    }

    func note(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        note = text
    }

    func summary(now: Double) -> Summary {
        lock.lock(); defer { lock.unlock() }
        var s = Summary()
        s.hrCount = hr.count
        s.lastBPM = hr.last?.bpm
        s.lastHRSource = lastSource
        if hr.count >= 2 { s.lastHRGapSec = hr[hr.count - 1].t - hr[hr.count - 2].t }
        if let last = hr.last { s.lastHRAgeSec = now - last.t }
        s.builderBPM = builderBPM
        s.motionConnected = connected
        s.motionCount = motion.count
        // Samples in the trailing two seconds; meaningful once two seconds have passed.
        s.motionRateHz = now >= 2 ? Double(recentMotion.count) / 2.0 : 0
        if let m = motion.last {
            s.lastPitch = m.pitch
            s.lastRoll = m.roll
            s.lastYaw = m.yaw
            s.lastAccel = (m.ax * m.ax + m.ay * m.ay + m.az * m.az).squareRoot()
        }
        s.lastNote = note
        return s
    }

    func sourcesSeen() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return sources
    }

    func snapshotHR() -> [HRRow] {
        lock.lock(); defer { lock.unlock() }
        return hr
    }

    func snapshotMotion() -> [MotionRow] {
        lock.lock(); defer { lock.unlock() }
        return motion
    }
}
#endif
