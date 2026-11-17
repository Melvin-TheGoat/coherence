import SwiftUI
import SwiftData
import AVFoundation
import Photos
import Combine
import os

/// Film yourself while you meditate, and 808 turns it into a short timelapse
/// kept on the session's page (Melvin, 2026-11-16, `record-session.html` and
/// his answers to its open decisions).
///
/// The life of one: the Timelapse pill on the Ready screen turns it on and
/// asks for the camera (`turnOn`); the viewfinder frames the shot every time
/// before Begin (`openViewfinder`); Begin starts the reel (`startFilming`);
/// the session ends however it ends, and once it is written the reel becomes
/// a clip, attached to the session as an ordinary `SessionPhoto` with a video
/// (`timelapse = true`), while Otto's reward plays. A session that was not
/// written (too short, or ended for leaving) deletes its frames quietly.
/// **Nothing is posted until the person taps Post.**
@MainActor
final class TimelapseRecorder: ObservableObject {
    static let shared = TimelapseRecorder()
    private let log = TimelapseCamera.log

    /// The switch, remembered between sessions. The viewfinder still shows
    /// every time it is on, so framing is checked before every Begin.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    @Published var lens: TimelapseLens = TimelapseLens.load()
    /// The camera is configured and running, so a preview can draw.
    @Published private(set) var cameraLive = false
    /// Camera access was refused; the pill explains where to allow it.
    @Published private(set) var cameraDenied = false
    /// The session being filmed right now.
    @Published private(set) var filmingID: UUID?
    /// Clips being made, by session, with how far along (frames written over
    /// frames needed: honest progress, never a spinner).
    @Published private(set) var making: [UUID: Double] = [:]
    /// Sessions whose clip could not be made.
    @Published private(set) var failed: Set<UUID> = []
    /// Bumped whenever a clip lands, so a page showing it reloads.
    @Published private(set) var landed: UUID?
    /// The small self-view during the sit: hidden with a tap, back with a
    /// tap on the dot. Remembered.
    @Published var selfViewHidden: Bool {
        didSet { UserDefaults.standard.set(selfViewHidden, forKey: Self.selfViewKey) }
    }

    private static let enabledKey = "timelapse.on.v1"
    private static let selfViewKey = "timelapse.selfViewHidden.v1"

    private var viewfinderOpen = false
    private var filmingSeconds: Double?
    private var container: ModelContainer?
    private var activeWatch: AnyCancellable?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        selfViewHidden = UserDefaults.standard.bool(forKey: Self.selfViewKey)
    }

    /// Every way a session ends passes through `active` going nil, so the
    /// recorder listens there rather than in any one screen. Set once at
    /// launch. Also clears reels a killed app left behind.
    func attach(coordinator: SessionCoordinator, container: ModelContainer) {
        self.container = container
        activeWatch = coordinator.$active
            .map { $0?.id }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in
                guard id == nil else { return }
                // `@Published` fires before the property changes, and the
                // session is written after `active` goes nil in the same
                // turn: look once the turn is over.
                Task { @MainActor [weak self] in self?.sessionEnded() }
            }
        Self.clearStaleReels()
    }

    // MARK: - The switch and the camera

    /// The pill: on asks for the camera (a choice first, then the prompt,
    /// never at launch), off closes it.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        guard on else {
            enabled = false
            closeViewfinder()
            Analytics.track(.timelapseToggled(on: false))
            return false
        }
        guard await Self.cameraAllowed() else {
            cameraDenied = true
            enabled = false
            return false
        }
        cameraDenied = false
        enabled = true
        Analytics.track(.timelapseToggled(on: true))
        await openViewfinder()
        return true
    }

    static func cameraAllowed() async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        // The simulator has no camera; the synthetic frames stand in.
        return true
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
        #endif
    }

    /// Starts the camera for framing. Called when the Ready screen shows with
    /// the switch on, and when it is turned on.
    func openViewfinder() async {
        guard enabled, !viewfinderOpen else { return }
        viewfinderOpen = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let camera = TimelapseCamera.shared
        let hasChosen = await camera.hasCamera(lens)
        if !hasChosen {
            guard await camera.hasCamera(lens.flipped) else { return }
            lens = lens.flipped
        }
        guard viewfinderOpen, await camera.configure(lens), viewfinderOpen else { return }
        let running = await camera.startRunning()
        cameraLive = running && viewfinderOpen
    }

    /// The Ready screen closed (or the switch went off). Filming keeps the
    /// camera until the session ends.
    func closeViewfinder() {
        viewfinderOpen = false
        guard filmingID == nil else { return }
        cameraLive = false
        TimelapseCamera.shared.stopRunning()
    }

    func flip() {
        lens = lens.flipped
        lens.store()
        Analytics.track(.timelapseLensFlipped(lens: lens.rawValue))
        Task {
            cameraLive = false
            guard await TimelapseCamera.shared.configure(lens) else { return }
            cameraLive = await TimelapseCamera.shared.startRunning()
        }
    }

    // MARK: - Filming

    static func reelDir(for id: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("timelapse-reels", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Begin. Hand-logged sessions never come here: they never pass Begin.
    func startFilming(sessionID: UUID, plannedSeconds: Int?) {
        guard enabled else { return }
        #if !(DEBUG && targetEnvironment(simulator))
        // No picture, no film: the camera was refused or would not start.
        guard cameraLive else { return }
        #endif
        filmingID = sessionID
        filmingSeconds = plannedSeconds.map(Double.init)
        #if DEBUG && targetEnvironment(simulator)
        log.info("filming \(sessionID) (simulator: synthetic frames)")
        SyntheticReel.start(for: sessionID, plannedSeconds: filmingSeconds)
        return
        #else
        let camera = TimelapseCamera.shared
        camera.beginReel(in: Self.reelDir(for: sessionID), plannedSeconds: filmingSeconds)
        camera.setFilmingRate(true)
        log.info("filming \(sessionID)")
        #endif
    }

    /// `active` went nil. Stops the camera at once, then waits for the
    /// session row (a Watch payload can take a moment) and makes the clip,
    /// or quietly deletes the frames when nothing was written.
    private func sessionEnded() {
        guard let id = filmingID else { return }
        filmingID = nil
        // The page that opens after the reward shows "Making" from here.
        making[id] = 0
        #if DEBUG && targetEnvironment(simulator)
        let framesTask = Task { await SyntheticReel.end() }
        #else
        let camera = TimelapseCamera.shared
        let framesTask = Task { await camera.endReel() }
        camera.setFilmingRate(false)
        if !viewfinderOpen { cameraLive = false; camera.stopRunning() }
        #endif
        Task { @MainActor in
            let frames = await framesTask.value
            guard let seconds = await waitForSession(id) else {
                log.info("session \(id) was not written; deleting its frames")
                making[id] = nil
                try? FileManager.default.removeItem(at: Self.reelDir(for: id))
                return
            }
            await make(sessionID: id, frames: frames, sessionSeconds: seconds)
        }
    }

    /// The written session's length, or nil once it is clear none was
    /// written. A phone session is written in the same turn; a Watch one
    /// when its payload lands, so this waits up to a minute and a half.
    private func waitForSession(_ id: UUID) async -> Double? {
        guard let container else { return nil }
        for attempt in 0..<90 {
            let context = container.mainContext
            if let s = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first {
                return Double(s.durationSec)
            }
            // A phone session not written in its own turn never will be.
            if attempt >= 3, SessionCoordinatorLookup.endedWithoutWatch(id) { return nil }
            try? await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    // MARK: - Making the clip

    /// Writes the clip, attaches it, deletes the stills, and saves a copy to
    /// Photos when the person asked for that.
    func make(sessionID id: UUID, frames: [URL], sessionSeconds: Double) async {
        guard !frames.isEmpty, let container else {
            making[id] = nil
            failed.insert(id)
            return
        }
        making[id] = 0
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("timelapse-\(id.uuidString).mp4")
        let ok = await TimelapseWriter.write(frames: frames, sessionSeconds: sessionSeconds, to: out) { p in
            Task { @MainActor in if self.making[id] != nil { self.making[id] = p } }
        }
        defer {
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: Self.reelDir(for: id))
        }
        guard ok, let video = try? Data(contentsOf: out),
              let poster = SessionVideo.posterFrame(out),
              let jpeg = PostPhoto.jpeg(poster), let thumb = PostPhoto.thumbnail(poster) else {
            making[id] = nil
            failed.insert(id)
            log.error("could not make the timelapse for \(id)")
            return
        }
        let context = container.mainContext
        let row = SessionStore.addTimelapse(sessionID: id, jpeg: jpeg, thumbnail: thumb, video: video, in: context)
        making[id] = nil
        guard let row else { failed.insert(id); return }
        log.info("timelapse for \(id): \(video.count / 1024) KB")
        landed = id
        if TimelapseAutoSave.load().savesAutomatically {
            _ = await saveToPhotos(row, sessionSeconds: sessionSeconds, automatic: true)
        }
    }

    /// Waits until a clip in the making has landed (or failed), up to a
    /// limit, so Post can carry it.
    func waitForClip(_ id: UUID, timeout: Double = 90) async {
        let start = Date()
        while making[id] != nil, Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - Leaving the phone

    /// The copy that leaves 808 carries two small marks (the speed line top
    /// left, "808 Meditate" bottom right); the clip in the app plays clean.
    /// Cached by the item's id.
    func exportedCopy(of item: SessionPhoto, sessionSeconds: Double) async -> URL? {
        guard let video = item.video else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timelapse-exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("808-timelapse-\(item.id.uuidString).mp4")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard let clean = SessionVideo.tempFile(video) else { return nil }
        defer { try? FileManager.default.removeItem(at: clean) }
        let overlay = TimelapseMarks.overlay(speedLine: TimelapseRule.speedLine(sessionSeconds: sessionSeconds))
        return await TimelapseWriter.mark(clean, overlay: overlay, to: out) ? out : nil
    }

    /// Add-only Photos access, asked when Save is first tapped. True when it
    /// landed in the camera roll.
    func saveToPhotos(_ item: SessionPhoto, sessionSeconds: Double, automatic: Bool = false) async -> Bool {
        guard let url = await exportedCopy(of: item, sessionSeconds: sessionSeconds) else { return false }
        let saved = await Self.saveVideoToPhotos(url)
        if saved, !automatic { Analytics.track(.timelapseSaved) }
        return saved
    }

    static func saveVideoToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { c in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, _ in c.resume(returning: ok) }
        }
    }

    /// Reels a killed app left in temp. Recovering them is not attempted.
    private static func clearStaleReels() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("timelapse-reels", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    /// The clip's frames for the debug hook, which makes one with no camera.
    #if DEBUG
    func makeDemo(sessionID: UUID, sessionSeconds: Double) {
        Task { @MainActor in
            let frames = await SyntheticReel.frames(for: sessionID, count: 240)
            await make(sessionID: sessionID, frames: frames, sessionSeconds: sessionSeconds)
        }
    }
    #endif
}

/// Whether a session the recorder was filming ended without anything being
/// written. A phone session is written in the turn it ends; only a Watch
/// payload arrives later. Read from the store and the coordinator's own
/// record, so the recorder never waits ninety seconds for a discard.
@MainActor
enum SessionCoordinatorLookup {
    /// Set by the coordinator as a session ends: whether it was a phone
    /// session (so nothing more is coming).
    static var phoneEnded: Set<UUID> = []
    static func endedWithoutWatch(_ id: UUID) -> Bool { phoneEnded.contains(id) }
}
