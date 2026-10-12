import AVFoundation
import SwiftUI
import os

/// 808's own sound outside a session: the music under Home and the rest of
/// the app, the birds, the taps, the coins (Melvin, 2026-10-09: "peaceful
/// zen music for the homepage and just app in general, maybe the birds chirp
/// when they fly by").
///
/// **Main thread only**, like the tone engine that calls it. It is not
/// marked `@MainActor` so that `ToneEngine` and `SessionBell` can claim the
/// audio synchronously, the moment they take it.
///
/// **Three rules, each the reason something here exists:**
///
/// - **It is ambient, the iOS meaning of the word.** The `.ambient` category
///   mixes with whatever else is playing and obeys the ring switch, so a
///   phone on silent hears nothing from 808 outside a session, exactly as it
///   hears no keyboard clicks. The session's sound and the end bell are the
///   opposite on purpose (`.playback`, which the switch does not silence).
/// - **It steps aside for every other sound.** The music stops for a session,
///   the Ready screen's countdown, a preview in the sound list, the end
///   bell, a person's own video, and, most of all, their own audio: 808
///   promises "bring your own audio", and somebody who opens it over a
///   podcast must never get music on top of their podcast. Taps and coins
///   still play over their audio, as a phone's own clicks do; the birds do
///   not.
/// - **It never moves the audio session out from under its owner.** While a
///   session's sound, a preview or the bell holds the session in
///   `.playback`, 808's taps play under that category and leave it alone:
///   switching it to `.ambient` mid-sit would let the ring switch silence a
///   meditation, and stop it the moment the screen locked.
final class AppAudio {
    static let shared = AppAudio()
    private let log = Logger(subsystem: "com.lockout.meditate808", category: "AppAudio")

    // MARK: - Settings

    /// Settings > Music and Settings > Sound effects. Device settings in
    /// UserDefaults rather than synced `Preferences`: what a phone plays is a
    /// question about that phone, and a new synced field would need a
    /// CloudKit schema promotion for no gain. Both default to on.
    static let musicKey = "settings.music.v1"
    static let effectsKey = "settings.soundEffects.v1"
    static var musicOn: Bool { UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true }
    static var effectsOn: Bool { UserDefaults.standard.object(forKey: effectsKey) as? Bool ?? true }

    // MARK: - Holds

    /// Everything that stops the music while it lasts.
    enum Hold: Hashable {
        /// A sit is running (`SessionCoordinator.active`).
        case session
        /// The Ready screen is counting in: the music fades as the sit
        /// arrives, so silence is the first thing the sit gives.
        case countdown
        /// A `ToneEngine` is sounding: a preview in the sound list, or a
        /// session's own sound.
        case tone(ObjectIdentifier)
        /// The end-of-session bell (`SessionBell`).
        case bell
        /// A person's own clip is on screen.
        case video
        /// 808 is not the app on screen.
        case background
    }

    private(set) var holds: Set<Hold> = []

    func set(_ hold: Hold, _ on: Bool) {
        let changed = on ? holds.insert(hold).inserted : holds.remove(hold) != nil
        guard changed else { return }
        // Whoever held the session may have changed its category or switched
        // it off (the bell does), so ask again before 808 plays next.
        if !on, hold.ownsAudio { activated = false }
        reconcile()
    }

    /// Whether a holder has the audio session in `.playback`.
    private var foreignOwner: Bool { holds.contains { $0.ownsAudio } }

    /// Another app is playing, a podcast or music: the music and the birds
    /// wait for it to end.
    private var otherAudioPlaying: Bool {
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    // MARK: - Music

    /// Melvin's own track (2026-10-12), made in ElevenLabs Music after the
    /// ambient beds proved "too ethereal": music with notes, zen but
    /// gently playful. A 61-second take cut to 70 beats (68.75 BPM) from its first
    /// note, ending in the quiet phrase before a guitar came in, so the pulse
    /// carries across the loop; set to the beds' loudness. In
    /// `Coherence/Audio/Music/`.
    static let musicResource = "music-garden"
    /// The music's key note, C4 at A440, measured off the file (its chroma
    /// reads C major, tuned within a cent of A440). The effects are tuned
    /// to it (`SoundSynth.root`), and `SoundSynthTests` fails if a new track
    /// changes this without moving them.
    static let musicTonic: Double = 261.63
    static let musicVolume: Float = 0.3

    private var music: AVAudioPlayer?
    /// What 808 means the music to be doing, as opposed to what a fade in
    /// progress happens to be doing.
    private var musicPlaying = false
    private var musicTask: Task<Void, Never>?

    /// Decides the music again: Settings, a hold, another app, an
    /// interruption, the app coming back. Cheap, and safe to call any time.
    func reconcile() {
        let want = Self.musicOn && holds.isEmpty && !otherAudioPlaying
        if want { startMusic() } else { stopMusic() }
    }

    private func startMusic() {
        guard !musicPlaying, activateAmbient() else { return }
        if music == nil {
            guard let url = Bundle.main.url(forResource: Self.musicResource, withExtension: "m4a") else {
                log.error("music: \(Self.musicResource, privacy: .public).m4a is not in the bundle")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 0
                p.prepareToPlay()
                music = p
            } catch {
                log.error("music: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        guard let music else { return }
        musicTask?.cancel()
        musicPlaying = true
        music.play()
        music.setVolume(Self.musicVolume, fadeDuration: 2.5)
        log.info("music: in")
    }

    private func stopMusic() {
        guard musicPlaying, let music else { return }
        musicPlaying = false
        log.info("music: out (\(self.holds.map { "\($0)" }.sorted().joined(separator: ", "), privacy: .public))")
        let fade: TimeInterval = holds.contains(.countdown) ? 3.5 : 1.0
        music.setVolume(0, fadeDuration: fade)
        musicTask?.cancel()
        musicTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fade + 0.1))
            // A cancelled sleep throws and falls through; the newer decision
            // owns the player then.
            guard !Task.isCancelled, let self, !self.musicPlaying else { return }
            self.music?.pause()
        }
    }

    // MARK: - Effects

    /// Plays one sound effect, if Settings and the moment allow it.
    ///
    /// `pan` runs from -1 (left) to 1 (right): a bird is heard where it is.
    func play(_ effect: SoundEffect, pan: Float = 0) {
        guard Self.effectsOn, !holds.contains(.session), !holds.contains(.background) else { return }
        if case .chirp = effect {
            // The birds are ambience: they wait, as the music does.
            guard holds.isEmpty, !otherAudioPlaying else { return }
        }
        guard activateAmbient() else { return }
        let p = player(for: effect)
        p.volume = Self.volume(for: effect)
        p.pan = max(-1, min(1, pan))
        p.currentTime = 0
        if !p.play() {
            log.error("effect \(effect.name, privacy: .public) did not play")
        }
        #if DEBUG
        log.info("effect \(effect.name, privacy: .public)")
        #endif
    }

    /// Each sound's loudness, relative to the music. The synthesized sounds
    /// all peak at the same level (`SoundSynth.peak`), so this is the mix.
    static func volume(for effect: SoundEffect) -> Float {
        switch effect {
        // Set so a press is as loud as the first, wooden one was.
        case .tap: return 0.23
        case .pop: return 0.4
        case .coin: return 0.45
        case .shimmer: return 0.35
        case .chime: return 0.5
        case .land: return 0.4
        case .chirp: return 0.22
        }
    }

    /// Players kept per sound, used in turn, so a run of coins (one every
    /// 105 ms, each ringing for 600) never cuts its own last note off.
    private var players: [SoundEffect: [AVAudioPlayer]] = [:]
    private var nextPlayer: [SoundEffect: Int] = [:]
    private var rendered: [SoundEffect: Data] = [:]

    private static func poolSize(_ effect: SoundEffect) -> Int {
        switch effect {
        case .coin: return 2
        case .tap: return 2
        default: return 1
        }
    }

    private func player(for effect: SoundEffect) -> AVAudioPlayer {
        if var pool = players[effect], !pool.isEmpty {
            let i = (nextPlayer[effect] ?? 0) % pool.count
            nextPlayer[effect] = i + 1
            if pool[i].isPlaying, pool.count < Self.poolSize(effect) * 3 {
                // Every player is still ringing: add one rather than cutting.
                if let extra = makePlayer(effect) {
                    pool.append(extra)
                    players[effect] = pool
                    return extra
                }
            }
            return pool[i]
        }
        let pool = (0..<Self.poolSize(effect)).compactMap { _ in makePlayer(effect) }
        players[effect] = pool
        nextPlayer[effect] = 1
        return pool.first ?? AVAudioPlayer()
    }

    private func makePlayer(_ effect: SoundEffect) -> AVAudioPlayer? {
        let data = rendered[effect] ?? SoundSynth.wav(SoundSynth.samples(effect))
        rendered[effect] = data
        do {
            let p = try AVAudioPlayer(data: data)
            p.prepareToPlay()
            return p
        } catch {
            log.error("effect \(effect.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Birds

    /// Every valley drawing birds, oldest first. Only the newest is heard
    /// (`BirdSong`): a cover over Home has a sky of its own, and Home's,
    /// still beneath it, must not sing along.
    private var birdVoices: [UUID] = []

    func birdsAppeared(_ voice: UUID, keepingPlace: Bool = false) {
        if keepingPlace, birdVoices.contains(voice) { return }
        birdVoices.removeAll { $0 == voice }
        birdVoices.append(voice)
    }

    func birdsDisappeared(_ voice: UUID) {
        birdVoices.removeAll { $0 == voice }
    }

    func birdsAreHeard(_ voice: UUID) -> Bool { birdVoices.last == voice }

    // MARK: - The session

    /// Whether 808 has activated the session since anyone else last held it.
    private var activated = false

    /// Puts the shared session on `.ambient`, unless a holder owns it in
    /// `.playback`; then 808's sounds play under theirs and the category is
    /// left exactly as they set it.
    private func activateAmbient() -> Bool {
        if foreignOwner { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default)
                activated = false
            }
            if !activated {
                try session.setActive(true)
                activated = true
            }
            return true
        } catch {
            log.error("session refused .ambient: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Setup

    /// Called once at launch: renders every sound ahead of the first press,
    /// off the main thread, and listens for the system's audio events.
    func install() {
        DispatchQueue.global(qos: .utility).async {
            let all = SoundEffect.all.map { ($0, SoundSynth.wav(SoundSynth.samples($0))) }
            DispatchQueue.main.async {
                for (e, d) in all where self.rendered[e] == nil { self.rendered[e] = d }
            }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                // A call or an alarm: the player stops by itself, and the
                // session must be activated again after.
                self.musicPlaying = false
                self.activated = false
            } else {
                self.reconcile()
            }
        }
        // Another app starts or stops playing its own audio.
        center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.reconcile()
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.music = nil
            self.musicPlaying = false
            self.players = [:]
            self.activated = false
            self.reconcile()
        }
    }

    #if DEBUG
    /// What the music is doing, for the sound check in Settings (debug).
    var debugState: String {
        let h = holds.map { "\($0)" }.sorted().joined(separator: ", ")
        return "music \(musicPlaying ? "on" : "off")"
            + (holds.isEmpty ? "" : " · held by \(h)")
            + (otherAudioPlaying ? " · other audio playing" : "")
            + " · \(AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"
    }
    #endif
}

private extension AppAudio.Hold {
    /// Holders that put the session in `.playback` themselves.
    var ownsAudio: Bool {
        switch self {
        case .tone, .bell, .session: return true
        case .countdown, .video, .background: return false
        }
    }
}

/// Tells `AppAudio` and `Tactile` what the root knows: Settings > Haptics,
/// whether a sit is running, and whether 808 is on screen. A modifier of
/// its own because the root's chain is already near what the type checker
/// will take (the `RootHooks` precedent).
struct AppAudioHooks: ViewModifier {
    let hapticsOn: Bool
    let sessionActive: Bool
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: hapticsOn, initial: true) { _, on in Tactile.hapticsOn = on }
            .onChange(of: sessionActive, initial: true) { _, on in AppAudio.shared.set(.session, on) }
            // Only a real trip to the background stops the music: pulling
            // down Control Center makes the scene inactive for a moment, and
            // music that stopped for that would be a fault.
            .onChange(of: scenePhase, initial: true) { _, phase in
                AppAudio.shared.set(.background, phase == .background)
                if phase == .active { AppAudio.shared.reconcile() }
            }
    }
}
