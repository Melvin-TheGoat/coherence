import XCTest
@testable import Coherence

/// 808's sound effects (2026-10-09). Like the bell, they are synthesized, so
/// the only way one can sound wrong is the arithmetic: these pin that none
/// clips, none is silent, every one ends on silence (a cut at full level is
/// a click), and the coins and chimes stay in the music's key.
final class SoundSynthTests: XCTestCase {

    func test_everySoundPeaksAtTheSameLevelAndEndsOnSilence() {
        for e in SoundEffect.all {
            let s = SoundSynth.samples(e)
            XCTAssertEqual(s.count, Int(SoundSynth.duration(e) * SoundSynth.rate), e.name)
            XCTAssertTrue(s.allSatisfy { $0.isFinite }, e.name)
            let peak = s.reduce(0) { max($0, abs($1)) }
            XCTAssertEqual(peak, SoundSynth.peak, accuracy: 0.001, "\(e.name) is normalized")
            XCTAssertLessThan(abs(s.last ?? 1), 0.01, "\(e.name) ends on silence")
            // No offset that would thump the speaker cone when it starts.
            let mean = s.reduce(0, +) / Float(s.count)
            XCTAssertLessThan(abs(mean), 0.02, "\(e.name) has no DC")
        }
    }

    func test_theSoundsAreShortWhereTheyHaveToBe() {
        // A tap must be over before the next one: people press fast.
        XCTAssertLessThan(SoundSynth.duration(.tap(main: false)), 0.12)
        // A bird's call is a call, not a song.
        for s in 0..<3 {
            for c in 0..<2 {
                XCTAssertLessThan(SoundSynth.duration(.chirp(species: s, call: c)), 0.8)
            }
        }
    }

    func test_theCoinsClimbTheScaleAndStopAtTheTop() {
        let pitches = (0..<SoundEffect.coinSteps).map { SoundSynth.coinPitch($0) }
        for (a, b) in zip(pitches, pitches.dropFirst()) {
            XCTAssertLessThan(a, b)
        }
        // The eighteenth coin sounds the same as the ninth, not a whistle.
        XCTAssertEqual(SoundSynth.coinPitch(17), pitches.last!, accuracy: 0.001)
        XCTAssertLessThan(pitches.last!, 2_000)
    }

    /// Every pitch the effects use is a note of C major pentatonic, the key
    /// of the home music, so nothing can sound out of tune against it.
    func test_thePitchesAreCPentatonic() {
        XCTAssertEqual(SoundSynth.pentatonic(0), 261.63, accuracy: 0.01)    // C4
        XCTAssertEqual(SoundSynth.pentatonic(5), 523.26, accuracy: 0.01)    // C5
        XCTAssertEqual(SoundSynth.pentatonic(-5), 130.815, accuracy: 0.01)  // C3
        let cPentatonic: Set<Int> = [0, 2, 4, 7, 9]   // C D E G A
        for degree in -5...16 {
            let semitones = 12 * log2(SoundSynth.pentatonic(degree) / 261.63)
            XCTAssertEqual(semitones, semitones.rounded(), accuracy: 0.01, "degree \(degree) is a real note")
            XCTAssertTrue(cPentatonic.contains(((Int(semitones.rounded()) % 12) + 12) % 12), "degree \(degree)")
        }
    }

    /// The effects' root is the music's key note in some octave. Swapping in
    /// a track in another key means changing `AppAudio.musicTonic`, and then
    /// this fails until `SoundSynth.root` moves too, here rather than on a
    /// phone as a coin that sounds wrong.
    func test_theEffectsAreInTheMusicsKey() {
        let octaves = log2(AppAudio.musicTonic / SoundSynth.root)
        XCTAssertEqual(octaves, octaves.rounded(), accuracy: 0.01)
    }

    /// One sound for every press, and a main button's lands a few notes
    /// higher: never a different sound, never an octave, never a clash.
    func test_aMainButtonSoundsTheSameNoteAStepHigher() {
        let tap = SoundSynth.tapPitch(main: false), main = SoundSynth.tapPitch(main: true)
        XCTAssertGreaterThan(main, tap)
        XCTAssertLessThan(main / tap, pow(2, 7.0 / 12), "a few notes higher, not an octave")
        XCTAssertEqual(SoundSynth.duration(.tap(main: true)), SoundSynth.duration(.tap(main: false)))
    }

    func test_everySoundHasItsOwnName() {
        let names = SoundEffect.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func test_theWAVIsTheShapeAVAudioPlayerOpens() {
        let s = SoundSynth.samples(.pop)
        let wav = SoundSynth.wav(s)
        XCTAssertEqual(wav.count, 44 + 2 * s.count)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
    }

    /// The music must be in the bundle under the name `AppAudio` asks for,
    /// or the app is silent with nothing but a log line to say why.
    func test_theMusicIsInTheBundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: AppAudio.musicResource, withExtension: "m4a"))
    }
}
