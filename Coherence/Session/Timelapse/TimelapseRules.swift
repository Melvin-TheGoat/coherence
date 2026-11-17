import Foundation

/// The arithmetic behind a session timelapse (Melvin, 2026-11-16, the
/// "Session Timelapse" mockup, `record-session.html`). Pure, so every rule
/// the feature promises is pinned by `TimelapseRulesTests`.
///
/// **Always a timelapse, never real speed**, whatever the length: one second
/// of clip for every half minute meditated, never shorter than 6 seconds and
/// never longer than 30. So 5 minutes plays in 10 seconds, 10 in 20, and 15
/// and longer in 30.
enum TimelapseRule {
    /// One second of clip per this many seconds meditated.
    static let secondsPerClipSecond: Double = 30
    static let shortestClip = 6
    static let longestClip = 30
    /// The clip's frame rate.
    static let fps = 30
    /// Portrait, the shape Reels and Stories want, so nothing is cropped or
    /// letterboxed when it leaves 808.
    static let outputWidth = 1080
    static let outputHeight = 1920
    /// About 4 Mbps: 30 seconds lands near 15 MB, well under the 40 MB every
    /// kept video is held to (`SessionVideo`).
    static let bitRate = 4_000_000

    /// Whole seconds of clip for a session of this length, clamped.
    static func clipSeconds(forSessionSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return shortestClip }
        let raw = Int((seconds / secondsPerClipSecond).rounded())
        return min(max(raw, shortestClip), longestClip)
    }

    /// Frames the finished clip is made of.
    static func framesNeeded(forSessionSeconds seconds: Double) -> Int {
        clipSeconds(forSessionSeconds: seconds) * fps
    }

    /// "20 min in 30 s". A measured fact, so it wears the measured blue
    /// where it is drawn in the app.
    static func speedLine(sessionSeconds: Double) -> String {
        "\(minutesLabel(sessionSeconds)) in \(clipSeconds(forSessionSeconds: sessionSeconds)) s"
    }

    /// "20 minutes becomes 30 seconds", under "Making your timelapse".
    static func makingLine(sessionSeconds: Double) -> String {
        let m = max(1, Int((sessionSeconds / 60).rounded()))
        let s = clipSeconds(forSessionSeconds: sessionSeconds)
        return "\(m) \(m == 1 ? "minute" : "minutes") becomes \(s) seconds"
    }

    /// "20 min", "1 h 5 min": what the speed line leads with.
    static func minutesLabel(_ seconds: Double) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        if m < 60 { return "\(m) min" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
    }

    /// For each frame of the clip, which kept frame it shows. Fewer kept
    /// frames than the clip needs repeats each one evenly (a one-minute open
    /// session); more skips evenly (a long one between thinnings).
    static func frameMap(kept: Int, needed: Int) -> [Int] {
        guard kept > 0, needed > 0 else { return [] }
        return (0..<needed).map { j in min(kept - 1, j * kept / needed) }
    }
}

/// The reel of stills kept while somebody sits: one frame every `interval`
/// seconds, never more than `capacity`. **When full, every other frame goes
/// and the gap doubles**, so the speed stays even, scratch space never grows
/// past one reel, and a three-hour session costs what a forty-minute one does.
/// A timed session knows its length at Begin and picks the exact gap, so it
/// never thins.
struct TimelapseReelPlan: Equatable {
    /// Frames kept before the reel thins. At about 90 KB a frame, roughly
    /// 110 MB of scratch at most.
    static let capacity = 1_200
    /// The shortest gap between kept frames.
    static let shortestInterval: Double = 0.5

    private(set) var interval: Double
    /// When each kept frame was taken, seconds from the start, in order.
    private(set) var times: [Double] = []
    private var nextDue: Double = 0

    /// Exact for a timed session; `shortestInterval` for an open one, which
    /// thins as it runs.
    init(plannedSeconds: Double?) {
        if let planned = plannedSeconds, planned > 0 {
            let needed = Double(TimelapseRule.framesNeeded(forSessionSeconds: planned))
            interval = max(Self.shortestInterval, planned / needed)
        } else {
            interval = Self.shortestInterval
        }
    }

    var count: Int { times.count }

    /// Whether a frame arriving at `t` should be kept.
    func wants(at t: Double) -> Bool { t >= nextDue }

    /// Records a kept frame. Returns the indexes of frames to delete when the
    /// reel just reached capacity and thinned itself (the odd ones), else [].
    mutating func keep(at t: Double) -> [Int] {
        times.append(t)
        // On a fixed beat, not "a gap after the last frame": frames arrive a
        // few times a second, and measuring from each late arrival would
        // stretch every gap by part of a frame (a ten-minute sit kept 532
        // frames where it needed 600). A long gap (the app was away) starts
        // the beat again from now.
        nextDue += interval
        if nextDue <= t { nextDue = t + interval }
        guard times.count >= Self.capacity else { return [] }
        let dropped = stride(from: 1, to: times.count, by: 2).map { $0 }
        times = stride(from: 0, to: times.count, by: 2).map { times[$0] }
        interval *= 2
        nextDue = (times.last ?? t) + interval
        return dropped
    }

    /// The camera is running hot (`systemPressureState` serious): sample
    /// half as often from here on.
    mutating func slowDown() {
        interval *= 2
        nextDue = (times.last ?? 0) + interval
    }
}

/// Whether new timelapses are saved to Photos by themselves (Melvin,
/// 2026-11-16): **off until the person's first manual Save; that first Save
/// offers it, once.** Turning it on at first launch would ask for Photos
/// before anyone has filmed anything, the permission-on-launch pattern App
/// Review dislikes. Stored on this phone only.
struct TimelapseAutoSave: Equatable {
    /// nil until they have answered the one offer.
    var enabled: Bool?
    var offered = false

    var savesAutomatically: Bool { enabled == true }

    /// After a manual Save succeeds: whether to ask "Save them all
    /// automatically?" now. Only ever once.
    mutating func afterManualSave() -> Bool {
        guard !offered, enabled == nil else { return false }
        offered = true
        return true
    }

    mutating func answer(_ yes: Bool) { enabled = yes; offered = true }

    private static let enabledKey = "timelapse.autoSave.v1"
    private static let offeredKey = "timelapse.autoSaveOffered.v1"

    static func load(_ d: UserDefaults = .standard) -> TimelapseAutoSave {
        TimelapseAutoSave(enabled: d.object(forKey: enabledKey) as? Bool,
                          offered: d.bool(forKey: offeredKey))
    }

    func store(_ d: UserDefaults = .standard) {
        if let enabled { d.set(enabled, forKey: Self.enabledKey) } else { d.removeObject(forKey: Self.enabledKey) }
        d.set(offered, forKey: Self.offeredKey)
    }
}

/// Front or back, the person's choice, remembered.
enum TimelapseLens: String {
    case front, back

    static let key = "timelapse.lens.v1"
    static func load(_ d: UserDefaults = .standard) -> TimelapseLens {
        TimelapseLens(rawValue: d.string(forKey: key) ?? "") ?? .front
    }
    func store(_ d: UserDefaults = .standard) { d.set(rawValue, forKey: Self.key) }

    var flipped: TimelapseLens { self == .front ? .back : .front }
    /// The front camera is mirrored, to match the viewfinder and the selfie
    /// camera; the back camera films the room as it is.
    var mirrored: Bool { self == .front }
}
