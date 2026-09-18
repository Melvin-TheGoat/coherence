// The whole Garmin idea lives in this file.
//
// Garmin gives raw acceleration in milli-g at up to 25 Hz and no fused
// attitude, where Apple gives us `CMDeviceMotion.attitude` (pitch and roll
// off a sensor-fusion estimate of gravity) and `userAcceleration`. We rebuild
// both here, which is honest precisely because the user is sitting still: at
// rest the accelerometer vector IS gravity, so a slow exponential average of
// the raw samples estimates it, and what is left over is the body's own
// movement.
//
// Then we reduce. A watch app gets 28.5 KB on an older fenix, so the engine
// cannot live here; the phone runs `SignalEngine` exactly as it does for the
// Apple Watch. What crosses the BLE link is 5 Hz triples (pitch, roll, the
// RMS of the residual), batched every 4 seconds. Breathing lives at 0.05 to
// 0.5 Hz, so 5 Hz is four times Nyquist with room to spare, and stillness
// survives the decimation because each bin carries the RMS of its five raw
// samples rather than one sample of them.
//
// Units on the wire are integers: milliradians, milli-g, milliseconds. The
// phone scales once.

using Toybox.Sensor;
using Toybox.System;
using Toybox.Math;
using Toybox.ActivityRecording;
using Toybox.Activity;
using Toybox.Lang;

class Capture {

    // 25 Hz is the documented ceiling; 4 s is the documented maximum period,
    // so one callback carries 100 samples per axis and becomes 20 bins.
    const SAMPLE_RATE = 25;
    const PERIOD_SEC = 4;
    const BIN = 5;              // 25 Hz / 5 = the 5 Hz we send

    // Gravity follows the accelerometer with a time constant near one second:
    // at 25 Hz, alpha = 1 - e^(-1/25) is about 0.04. Slow enough that a breath
    // at 0.1 Hz passes through into the residual rather than being absorbed,
    // fast enough that settling into a new posture does not poison the whole
    // sit. This constant is a measurement waiting to happen; the wrist engine's
    // gate stack was tuned the same way, and nothing here is validated yet.
    const GRAVITY_ALPHA = 0.04;

    var bridge;
    var session;
    var startMs;
    var running;
    var gx, gy, gz;
    var primed;
    var heartRate;
    var batches;

    function initialize(theBridge) {
        bridge = theBridge;
        running = false;
        primed = false;
        heartRate = 0;
        batches = 0;
        startMs = 0;
    }

    // Sensors return null on real hardware until an activity is recording.
    // It works in the simulator without one, which is how an afternoon gets
    // lost. The session also puts the sit in Garmin Connect, which is the
    // same thing our HKWorkout does on Apple.
    function start() {
        if (running) { return; }
        startMs = System.getTimer();
        primed = false;
        batches = 0;

        session = ActivityRecording.createSession({
            :name => "Meditation",
            :sport => Activity.SPORT_MEDITATION,
            :subSport => Activity.SUB_SPORT_BREATHING
        });
        session.start();

        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
        Sensor.registerSensorDataListener(method(:onData), {
            :period => PERIOD_SEC,
            :accelerometer => { :enabled => true, :sampleRate => SAMPLE_RATE },
            :heartBeatIntervals => { :enabled => true }
        });
        running = true;
    }

    function stop() {
        if (!running) { return; }
        Sensor.unregisterSensorDataListener();
        Sensor.enableSensorEvents(null);
        if (session != null) {
            session.stop();
            session.save();
            session = null;
        }
        running = false;
        bridge.send({ "v" => 1, "end" => elapsedMs() });
    }

    function elapsedMs() {
        return startMs == 0 ? 0 : System.getTimer() - startMs;
    }

    function elapsedSec() {
        return elapsedMs() / 1000;
    }

    // 1 Hz, and the only use of it is to stamp the batch. Beat-to-beat
    // intervals ride along untouched: Garmin gives real RR where the Apple
    // Watch never has, and v1 records it without scoring it so that a Garmin
    // sit and a Watch sit stay comparable in one history.
    function onSensor(info) {
        if (info has :heartRate && info.heartRate != null) {
            heartRate = info.heartRate;
        }
    }

    function onData(sensorData) {
        var accel = sensorData.accelerometerData;
        if (accel == null) { return; }

        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) { return; }

        var n = xs.size();
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
                    gx = x; gy = y; gz = z;
                    primed = true;
                } else {
                    gx += GRAVITY_ALPHA * (x - gx);
                    gy += GRAVITY_ALPHA * (y - gy);
                    gz += GRAVITY_ALPHA * (z - gz);
                }

                // What the body did, with gravity taken out: the same
                // quantity `userAcceleration` gives us, and stillness reads it.
                var rx = x - gx;
                var ry = y - gy;
                var rz = z - gz;
                sumSquares += rx * rx + ry * ry + rz * rz;

                // Where the wrist is pointing, from gravity alone.
                sumPitch += Math.atan2(-gx, Math.sqrt(gy * gy + gz * gz));
                sumRoll += Math.atan2(gy, gz);
            }

            out.add((1000.0 * sumPitch / BIN).toNumber());   // milliradians
            out.add((1000.0 * sumRoll / BIN).toNumber());    // milliradians
            out.add(Math.sqrt(sumSquares / BIN).toNumber()); // milli-g, RMS
            i += BIN;
        }

        var rr = [];
        var hrData = sensorData.heartRateData;
        if (hrData != null && hrData.heartBeatIntervals != null) {
            rr = hrData.heartBeatIntervals;
        }

        batches += 1;
        bridge.send({
            "v" => 1,
            "t" => elapsedMs(),
            "hz" => SAMPLE_RATE / BIN,
            "s" => out,
            "hr" => heartRate,
            "rr" => rr
        });
    }
}
