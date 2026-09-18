// Raw accelerometer to the two signals the phone's engine expects.
//
// Apple hands us `attitude` (where the wrist points) and `userAcceleration`
// (what the body did), both from a gyro-backed fusion. Garmin gives neither:
// only raw acceleration in milli-g. This rebuilds both, and it needs TWO
// filters, not one, which the first draft of this file got wrong.
//
// TILT, for breathing. The direction of the accelerometer vector IS the
// wrist's tilt whenever the wrist is not being flung about, so it needs only
// enough smoothing to drop fast linear acceleration. The cutoff must sit ABOVE
// the breathing band or it eats the thing we are trying to measure: a
// one-pole filter attenuates by 1/sqrt(1 + (f/fc)^2), so a 0.16 Hz cutoff
// would take a 15 breaths/min wave down to 0.54 of its size and push it under
// the engine's amplitude floor. At 2 Hz the whole band 0.05 to 0.5 Hz passes
// essentially untouched (0.5 Hz keeps 0.97).
//
// GRAVITY, for stillness. This one is the opposite: it must be SLOWER than
// breathing so that subtracting it leaves the body's movement rather than the
// breath. 0.2 Hz is below the band, which is what makes the residual the same
// quantity `userAcceleration` gives us on Apple.
//
// alpha = 1 - e^(-2*pi*fc/fs), at fs = 25 Hz.

using Toybox.Math;
using Toybox.Lang;

class Reducer {

    const BIN = 5;               // 25 Hz in, 5 Hz out
    const TILT_ALPHA = 0.40;     // fc ~2 Hz: the breathing band passes
    const GRAVITY_ALPHA = 0.05;  // fc ~0.2 Hz: below the band, so it is posture

    var tx, ty, tz;
    var gx, gy, gz;
    var primed;

    function initialize() {
        primed = false;
        tx = 0.0; ty = 0.0; tz = 0.0;
        gx = 0.0; gy = 0.0; gz = 0.0;
    }

    // xs, ys, zs: equal-length arrays of milli-g, as Garmin delivers them.
    // Returns a flat array, three numbers per bin:
    //   pitch in milliradians, roll in milliradians, residual RMS in milli-g.
    function reduce(xs as Lang.Array, ys as Lang.Array, zs as Lang.Array) as Lang.Array {
        var n = xs.size();
        if (ys.size() < n) { n = ys.size(); }
        if (zs.size() < n) { n = zs.size(); }

        var out = [];
        var i = 0;

        while (i + BIN <= n) {
            var sumPitch = 0.0;
            var sumRoll = 0.0;
            var sumSquares = 0.0;

            for (var k = 0; k < BIN; k += 1) {
                var x = xs[i + k].toFloat();
                var y = ys[i + k].toFloat();
                var z = zs[i + k].toFloat();

                if (!primed) {
                    tx = x; ty = y; tz = z;
                    gx = x; gy = y; gz = z;
                    primed = true;
                } else {
                    tx += TILT_ALPHA * (x - tx);
                    ty += TILT_ALPHA * (y - ty);
                    tz += TILT_ALPHA * (z - tz);
                    gx += GRAVITY_ALPHA * (x - gx);
                    gy += GRAVITY_ALPHA * (y - gy);
                    gz += GRAVITY_ALPHA * (z - gz);
                }

                // Where the wrist points, from the tilt-filtered vector.
                sumPitch += Math.atan2(-tx, Math.sqrt(ty * ty + tz * tz));
                sumRoll += Math.atan2(ty, tz);

                // What the body did, with the held posture taken out.
                var rx = x - gx;
                var ry = y - gy;
                var rz = z - gz;
                sumSquares += rx * rx + ry * ry + rz * rz;
            }

            out.add((1000.0 * sumPitch / BIN).toNumber());
            out.add((1000.0 * sumRoll / BIN).toNumber());
            out.add(Math.sqrt(sumSquares / BIN).toNumber());
            i += BIN;
        }

        return out;
    }
}
