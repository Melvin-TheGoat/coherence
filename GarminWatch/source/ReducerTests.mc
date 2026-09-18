// Tests for the only file with arithmetic in it. Run with:
//
//   monkeyc -f monkey.jungle -d vivoactive5 -o bin/808_test.prg \
//           -y ~/.garmin/808_developer_key.der --unit-test
//   monkeydo bin/808_test.prg vivoactive5 -t
//
// `(:test)` functions are stripped from a normal build, so none of this ships.
//
// What these pin is the thing that cannot be checked by looking at a watch
// face: that a breath survives the filter. The first version of `Reducer` used
// one exponential average at a 0.16 Hz cutoff for both jobs, which attenuated
// a 15 breaths/min wave to about half its size before the phone ever saw it.
// `test_aBreathSurvivesTheFilter` is what caught that and is the reason the
// tilt and gravity filters are now separate.

using Toybox.Test;
using Toybox.Math;
using Toybox.Lang;

const FS = 25.0;           // the sample rate we ask Garmin for
const G = 1000.0;          // milli-g in one g

// A wrist held at a fixed tilt, `n` samples of it.
function steady(n as Lang.Number, x as Lang.Float, y as Lang.Float, z as Lang.Float) as Lang.Array {
    var xs = []; var ys = []; var zs = [];
    for (var i = 0; i < n; i += 1) {
        xs.add(x.toNumber()); ys.add(y.toNumber()); zs.add(z.toNumber());
    }
    return [xs, ys, zs];
}

// A wrist rocking through `amp` radians at `bpm` breaths per minute, in the
// pitch plane: tilting by theta moves gravity to (-sin, 0, cos).
function breathing(n as Lang.Number, bpm as Lang.Float, amp as Lang.Float) as Lang.Array {
    var xs = []; var ys = []; var zs = [];
    for (var i = 0; i < n; i += 1) {
        var t = i / FS;
        var theta = amp * Math.sin(2 * Math.PI * (bpm / 60.0) * t);
        xs.add((-G * Math.sin(theta)).toNumber());
        ys.add(0);
        zs.add((G * Math.cos(theta)).toNumber());
    }
    return [xs, ys, zs];
}

// The reducer emits MICRO units (microradians, micro-g). These helpers return
// MILLI units, because that is the scale the engine's own constants are quoted
// in and the scale a person can read.
const MICRO_PER_MILLI = 1000.0;

// Peak-to-peak of one column of the flat [pitch, roll, residual] output,
// ignoring the first `skipBins` bins so the filters can settle.
function spread(out as Lang.Array, column as Lang.Number, skipBins as Lang.Number) as Lang.Float {
    var lo = null; var hi = null;
    var b = skipBins;
    while (b * 3 + column < out.size()) {
        var v = out[b * 3 + column].toFloat();
        if (lo == null || v < lo) { lo = v; }
        if (hi == null || v > hi) { hi = v; }
        b += 1;
    }
    return (lo == null) ? 0.0 : (hi - lo) / MICRO_PER_MILLI;
}

function meanOf(out as Lang.Array, column as Lang.Number, skipBins as Lang.Number) as Lang.Float {
    var sum = 0.0; var count = 0;
    var b = skipBins;
    while (b * 3 + column < out.size()) {
        sum += out[b * 3 + column].toFloat();
        count += 1;
        b += 1;
    }
    return count == 0 ? 0.0 : (sum / count) / MICRO_PER_MILLI;
}

(:test)
function test_binningShape(logger as Test.Logger) as Lang.Boolean {
    var s = steady(100, 0.0, 0.0, G);
    var out = new Reducer().reduce(s[0], s[1], s[2]);
    // 100 samples, five to a bin, three numbers each.
    logger.debug("got " + out.size() + " numbers");
    return out.size() == 60;
}

(:test)
function test_flatWristReadsZeroTilt(logger as Test.Logger) as Lang.Boolean {
    var s = steady(250, 0.0, 0.0, G);
    var out = new Reducer().reduce(s[0], s[1], s[2]);
    var pitch = meanOf(out, 0, 10);
    var roll = meanOf(out, 1, 10);
    var residual = meanOf(out, 2, 10);
    logger.debug("pitch " + pitch + " roll " + roll + " residual " + residual);
    return pitch > -5 && pitch < 5 && roll > -5 && roll < 5 && residual < 5;
}

(:test)
function test_tiltOnItsSideReadsAQuarterTurn(logger as Test.Logger) as Lang.Boolean {
    // Gravity along +x: pitch is -pi/2, which is -1571 milliradians.
    var s = steady(400, G, 0.0, 0.0);
    var out = new Reducer().reduce(s[0], s[1], s[2]);
    var pitch = meanOf(out, 0, 40);
    logger.debug("pitch " + pitch + " mrad, want about -1571");
    return pitch < -1520 && pitch > -1620;
}

(:test)
function test_rollReadsTheOtherAxis(logger as Test.Logger) as Lang.Boolean {
    var s = steady(400, 0.0, G, 0.0);
    var out = new Reducer().reduce(s[0], s[1], s[2]);
    var roll = meanOf(out, 1, 40);
    logger.debug("roll " + roll + " mrad, want about 1571");
    return roll > 1520 && roll < 1620;
}

// THE load-bearing test. A 6/min breath of 20 milliradians must arrive as
// roughly 40 milliradians peak to peak, not as half of that.
(:test)
function test_aBreathSurvivesTheFilter(logger as Test.Logger) as Lang.Boolean {
    var b = breathing(1500, 6.0, 0.020);     // 60 s at 25 Hz
    var out = new Reducer().reduce(b[0], b[1], b[2]);
    var pp = spread(out, 0, 30);
    logger.debug("6/min: " + pp + " mrad peak to peak, want about 40");
    return pp > 36 && pp < 44;
}

// The fast end of the band is where a one-pole filter set too low does its
// damage, so it gets its own test.
(:test)
function test_aFastBreathAlsoSurvives(logger as Test.Logger) as Lang.Boolean {
    var b = breathing(1500, 15.0, 0.020);
    var out = new Reducer().reduce(b[0], b[1], b[2]);
    var pp = spread(out, 0, 30);
    logger.debug("15/min: " + pp + " mrad peak to peak, want about 40");
    return pp > 34 && pp < 44;
}

// The same wrist rock, but handed over as Floats: what the sensor would give
// us if it were not quantised. Used only to locate where resolution is lost.
function breathingPrecise(n as Lang.Number, bpm as Lang.Float, amp as Lang.Float) as Lang.Array {
    var xs = []; var ys = []; var zs = [];
    for (var i = 0; i < n; i += 1) {
        var t = i / FS;
        var theta = amp * Math.sin(2 * Math.PI * (bpm / 60.0) * t);
        xs.add(-G * Math.sin(theta));
        ys.add(0.0);
        zs.add(G * Math.cos(theta));
    }
    return [xs, ys, zs];
}

// RESOLUTION. A settled user's real breath measured 1.1 to 1.5 milliradians on
// the Apple Watch captures, and the stiller the body the SMALLER the wave.
//
// **Garmin hands us whole milli-g.** At 1 g, a tilt of theta radians moves an
// axis by about 1000*theta milli-g, so one unit of the sensor's own quantiser
// IS about one milliradian of tilt: the same size as the entire breath we are
// trying to read. A 1.2 mrad breath arrives at the watch as a three-level
// staircase before our code sees it, and no choice of units on our side can
// put back what the sensor never resolved. This pair of tests measures how
// much is lost and proves where it is lost.
//
// It is NOT fatal, and the reason is that the engine estimates a rate by DFT
// over a 30 s window rather than by measuring an amplitude: quantisation noise
// is broadband and averages down, while the breath adds coherently. Proving
// THAT is a phone-side test against the real `SignalEngine`, not a watch test.
(:test)
function test_aTinyRealBreathSurvivesTheSensorsQuantiser(logger as Test.Logger) as Lang.Boolean {
    var b = breathing(1500, 6.0, 0.0012);
    var out = new Reducer().reduce(b[0], b[1], b[2]);
    var pp = spread(out, 0, 30);
    // About 2.4 mrad if nothing were lost; about 2.0 is what whole milli-g
    // leaves. It must not collapse toward zero or flatten to one level.
    logger.debug("1.2 mrad breath through whole milli-g: " + pp + " mrad peak to peak");
    return pp > 1.8 && pp < 2.7;
}

(:test)
function test_theLossIsTheSensorsQuantiserAndNotOurUnits(logger as Test.Logger) as Lang.Boolean {
    var b = breathingPrecise(1500, 6.0, 0.0012);
    var out = new Reducer().reduce(b[0], b[1], b[2]);
    var pp = spread(out, 0, 30);
    // Unquantised input through the identical code returns the full 2.4,
    // which puts the loss above us and rules out our own arithmetic.
    logger.debug("same breath, unquantised input: " + pp + " mrad peak to peak");
    return pp > 2.2 && pp < 2.6;
}

// Breathing is a tilt, not a shove. It must not read as movement, or every
// breath would cost the user stillness.
(:test)
function test_breathingIsNotMistakenForMovement(logger as Test.Logger) as Lang.Boolean {
    var b = breathing(1500, 6.0, 0.020);
    var out = new Reducer().reduce(b[0], b[1], b[2]);
    var residual = meanOf(out, 2, 30);
    logger.debug("residual during a breath: " + residual + " milli-g");
    return residual < 10;
}

// And the opposite: a shake has to show up.
(:test)
function test_aShakeReadsAsMovement(logger as Test.Logger) as Lang.Boolean {
    var xs = []; var ys = []; var zs = [];
    for (var i = 0; i < 500; i += 1) {
        var t = i / FS;
        // 3 Hz, 200 milli-g: an arm moving, well above the breathing band.
        xs.add((200 * Math.sin(2 * Math.PI * 3.0 * t)).toNumber());
        ys.add(0);
        zs.add(G.toNumber());
    }
    var out = new Reducer().reduce(xs, ys, zs);
    var residual = meanOf(out, 2, 20);
    logger.debug("residual during a shake: " + residual + " milli-g");
    return residual > 80;
}

// A change of posture must be absorbed within a few seconds rather than
// reading as movement for the rest of the sit.
(:test)
function test_aNewPostureIsAbsorbed(logger as Test.Logger) as Lang.Boolean {
    var r = new Reducer();
    var before = steady(250, 0.0, 0.0, G);
    r.reduce(before[0], before[1], before[2]);
    var after = steady(500, 300.0, 0.0, 954.0);   // leaned over, still 1 g
    var out = r.reduce(after[0], after[1], after[2]);
    var settled = meanOf(out, 2, 60);             // the last ~8 s of it
    logger.debug("residual once settled into the new posture: " + settled);
    return settled < 10;
}
