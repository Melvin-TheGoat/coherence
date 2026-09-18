import XCTest

/// The Garmin path, from the bytes on the BLE link to a scored session.
///
/// The question these have to answer is not "does the code run" but **can a
/// Garmin watch read a breath at all**, given that it hands us whole milli-g
/// and a settled user's real breath is 1.1 to 1.5 milliradians of tilt, which
/// is about one unit of that quantiser. The watch-side tests measured the loss
/// (2.0 mrad of a true 2.4). These put the lossy signal through the REAL
/// `SignalEngine` and ask whether the rate still comes out, because the engine
/// estimates a rate by DFT over a 30 s window rather than by measuring an
/// amplitude, and quantisation noise is broadband where a breath is coherent.
final class GarminStreamTests: XCTestCase {

    // MARK: - A simulated Garmin watch

    /// Mirrors `GarminWatch/source/Reducer.mc`: two one-pole filters with
    /// opposite jobs, five raw samples to a bin, integers out. This is a
    /// REPLICA and replicas drift (the breathing work learned that the hard
    /// way), so it exists to generate believable input for the engine, never
    /// to certify the watch. The watch's own tests certify the watch.
    private func watchBatches(
        durationSec: Double,
        breathsPerMin: Double,
        tiltRadians: Double,
        accelNoiseMilliG: Double = 0,
        quantise: Bool = true,
        sampleRate: Double = 25,
        bin: Int = 5,
        period: Double = 4
    ) -> [GarminBatch] {
        let tiltAlpha = 0.40, gravityAlpha = 0.05, micro = 1_000_000.0
        var tx = 0.0, ty = 0.0, tz = 0.0, gx = 0.0, gy = 0.0, gz = 0.0
        var primed = false
        var triples: [(Int, Int, Int)] = []

        let n = Int(durationSec * sampleRate)
        var pending: [(Double, Double, Double)] = []
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let theta = tiltRadians * sin(2 * .pi * (breathsPerMin / 60) * t)
            // A little movement on top, as a real body has.
            let jitter = accelNoiseMilliG * sin(2 * .pi * 2.7 * t)
            var x = -1000 * sin(theta) + jitter
            var y = 0.0
            var z = 1000 * cos(theta)
            if quantise {       // Garmin delivers whole milli-g
                x = (x).rounded(.towardZero); y = 0; z = (z).rounded(.towardZero)
            }

            if !primed {
                tx = x; ty = y; tz = z; gx = x; gy = y; gz = z; primed = true
            } else {
                tx += tiltAlpha * (x - tx); ty += tiltAlpha * (y - ty); tz += tiltAlpha * (z - tz)
                gx += gravityAlpha * (x - gx); gy += gravityAlpha * (y - gy); gz += gravityAlpha * (z - gz)
            }
            let rx = x - gx, ry = y - gy, rz = z - gz
            pending.append((
                atan2(-tx, (ty * ty + tz * tz).squareRoot()),
                atan2(ty, tz),
                rx * rx + ry * ry + rz * rz
            ))

            if pending.count == bin {
                let p = pending.reduce(0.0) { $0 + $1.0 } / Double(bin)
                let r = pending.reduce(0.0) { $0 + $1.1 } / Double(bin)
                let a = (pending.reduce(0.0) { $0 + $1.2 } / Double(bin)).squareRoot()
                triples.append((Int(micro * p), Int(micro * r), Int(1000 * a)))
                pending.removeAll()
            }
        }

        // Cut into four-second batches, as the sensor callback does.
        let outHz = sampleRate / Double(bin)
        let perBatch = Int(period * outHz)
        var batches: [GarminBatch] = []
        var index = 0
        while index + perBatch <= triples.count {
            let slice = triples[index..<(index + perBatch)]
            let flat = slice.flatMap { [$0.0, $0.1, $0.2] }
            let endMs = Int((Double(index + perBatch) / outHz) * 1000)
            let message: [AnyHashable: Any] = [
                "v": 1, "t": endMs, "hz": Int(outHz), "s": flat, "hr": 62, "rr": [980, 1010]
            ]
            if let b = GarminBatch(message: message) { batches.append(b) }
            index += perBatch
        }
        return batches
    }

    private func stream(_ batches: [GarminBatch], startedAt: Date = Date()) -> GarminStream {
        let s = GarminStream(sessionID: UUID(), startedAt: startedAt, mode: "silence")
        batches.forEach { s.accept($0) }
        return s
    }

    // MARK: - Decoding

    func test_decodeUnpacksMicroUnitsAndTimesSamplesBackwardsFromTheStamp() throws {
        // Two samples at 5 Hz, batch stamped at 4000 ms: the last sample sits
        // at 4.0 s and the one before it 0.2 s earlier.
        let message: [AnyHashable: Any] = [
            "v": 1, "t": 4000, "hz": 5,
            "s": [1200, -2400, 3000, 1300, -2500, 3100],
            "hr": 61, "rr": [990, 1005]
        ]
        let batch = try XCTUnwrap(GarminBatch(message: message))
        XCTAssertEqual(batch.samples.count, 2)
        XCTAssertEqual(batch.samples[0].pitch, 0.0012, accuracy: 1e-9, "microradians to radians")
        XCTAssertEqual(batch.samples[0].roll, -0.0024, accuracy: 1e-9)
        XCTAssertEqual(batch.samples[0].userAccel, 0.003, accuracy: 1e-9, "micro-g to g")
        XCTAssertEqual(batch.time(of: 1), 4.0, accuracy: 1e-9)
        XCTAssertEqual(batch.time(of: 0), 3.8, accuracy: 1e-9)
        XCTAssertEqual(batch.bpm, 61)
        XCTAssertEqual(batch.beatIntervalsMs, [990, 1005])
    }

    func test_malformedMessagesDecodeToNilRatherThanCrashing() {
        let bad: [[AnyHashable: Any]] = [
            ["v": 2, "t": 0, "s": [1, 2, 3]],            // a version we do not speak
            ["v": 1, "s": [1, 2, 3]],                     // no stamp
            ["v": 1, "t": 0, "s": [1, 2, 3, 4]],          // not whole triples
            ["v": 1, "t": 0, "s": [Int]()],               // empty
            ["v": 1, "t": 0, "s": "not an array"],        // wrong type
            ["v": 1, "t": 0, "s": [1, 2, 3], "hz": 0]     // impossible rate
        ]
        for message in bad {
            XCTAssertNil(GarminBatch(message: message), "should refuse \(message)")
        }
    }

    func test_aHeartRateOfZeroIsNoReadingNotAZeroInTheCurve() throws {
        let message: [AnyHashable: Any] = ["v": 1, "t": 4000, "hz": 5, "s": [0, 0, 0], "hr": 0]
        let batch = try XCTUnwrap(GarminBatch(message: message))
        XCTAssertNil(batch.bpm, "a watch that has not read the heart yet must not plot a zero")
    }

    func test_theEndMarkerIsNotABatch() {
        let end: [AnyHashable: Any] = ["v": 1, "end": 600_000]
        XCTAssertTrue(GarminBatch.isEnd(end))
        XCTAssertNil(GarminBatch(message: end))
    }

    // MARK: - The stream

    func test_aRepeatedOrOutOfOrderBatchIsIgnored() throws {
        let batches = watchBatches(durationSec: 12, breathsPerMin: 6, tiltRadians: 0.02)
        let s = stream(batches)
        let before = s.motion.count
        batches.forEach { s.accept($0) }        // the whole lot again
        XCTAssertEqual(s.motion.count, before, "a replayed batch must not be interleaved")
    }

    func test_aMissingBatchIsCountedAsAGap() throws {
        var batches = watchBatches(durationSec: 40, breathsPerMin: 6, tiltRadians: 0.02)
        batches.remove(at: 3)                   // the phone was out of range
        XCTAssertEqual(stream(batches).gaps, 1)
    }

    func test_aSitTooShortToReadIsDiscarded() {
        let start = Date()
        let s = stream(watchBatches(durationSec: 20, breathsPerMin: 6, tiltRadians: 0.02),
                       startedAt: start)
        let payload = s.payload(endedAt: start.addingTimeInterval(20))
        XCTAssertTrue(payload.discard)
        XCTAssertNil(payload.result)
    }

    func test_aSitWhereAlmostNothingArrivedIsDiscarded() {
        // The watch ran for six minutes but the phone only ever heard twenty
        // seconds of it. A Garmin-only failure: the Watch cannot lose a sit
        // this way, because it computes the result itself.
        let start = Date()
        let s = stream(watchBatches(durationSec: 20, breathsPerMin: 6, tiltRadians: 0.02),
                       startedAt: start)
        let payload = s.payload(endedAt: start.addingTimeInterval(360))
        XCTAssertTrue(payload.discard, "a long sit we barely heard must not be scored")
    }

    // MARK: - The question that decides the platform

    /// A deliberate slow breath of 20 milliradians, which is what a paced sit
    /// on a wrist looks like when the arm is resting on a leg.
    func test_aPacedBreathIsReadThroughTheWholeGarminPath() throws {
        let start = Date()
        let s = stream(watchBatches(durationSec: 180, breathsPerMin: 6, tiltRadians: 0.02),
                       startedAt: start)
        let payload = s.payload(endedAt: start.addingTimeInterval(180))
        XCTAssertFalse(payload.discard)
        let result = try XCTUnwrap(payload.result)
        let rate = try XCTUnwrap(result.meanBreathingRate)
        XCTAssertEqual(rate, 6, accuracy: 0.5, "Garmin read \(rate)/min for a paced 6")
    }

    /// **THE test.** 1.2 milliradians is a settled user's real breath, and one
    /// unit of Garmin's milli-g quantiser is about one milliradian of tilt. If
    /// the rate survives this, the platform can carry the feature.
    func test_aTinyRealBreathSurvivesGarminsQuantiser() throws {
        let start = Date()
        let s = stream(watchBatches(durationSec: 180, breathsPerMin: 6, tiltRadians: 0.0012),
                       startedAt: start)
        let payload = s.payload(endedAt: start.addingTimeInterval(180))
        let result = try XCTUnwrap(payload.result)
        let rate = try XCTUnwrap(result.meanBreathingRate,
                                 "a 1.2 mrad breath must still be READ through whole milli-g")
        XCTAssertEqual(rate, 6, accuracy: 1.0, "Garmin read \(rate)/min for a tiny real 6")
    }

    /// A Garmin sit must be scored by the same engine, at the same version, as
    /// an Apple Watch sit. The camera path deliberately marks itself with an
    /// `algorithmVersion` prefix so `ScoreMigration` skips it; Garmin must NOT,
    /// because it runs the identical engine over the identical kind of input
    /// and its sessions belong in the same history.
    func test_aGarminSitIsScoredAsAnyOtherSit() throws {
        let start = Date()
        let s = stream(watchBatches(durationSec: 180, breathsPerMin: 6, tiltRadians: 0.02,
                                    accelNoiseMilliG: 4),
                       startedAt: start)
        let result = try XCTUnwrap(s.payload(endedAt: start.addingTimeInterval(180)).result)
        XCTAssertFalse(result.algorithmVersion.hasPrefix("camera-"))
        XCTAssertFalse(result.algorithmVersion.hasPrefix("garmin-"))
        XCTAssertNotNil(result.overallScore)
    }

    func test_beatIntervalsAreKeptButNeverReachTheScore() throws {
        let start = Date()
        let s = stream(watchBatches(durationSec: 180, breathsPerMin: 6, tiltRadians: 0.02),
                       startedAt: start)
        XCTAssertFalse(s.beatIntervalsMs.isEmpty, "Garmin gives RR and we keep it")
        let result = try XCTUnwrap(s.payload(endedAt: start.addingTimeInterval(180)).result)
        // Nothing on the result can carry them yet, by design: scoring them
        // would make a Garmin sit incomparable with every Watch sit.
        XCTAssertNotNil(result.overallScore)
    }
}
