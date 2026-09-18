// Sensors in, batches out. The arithmetic lives in `Reducer`, where it can be
// tested; this file is the plumbing around it.
//
// A watch app gets 28.5 KB on an older fenix, so `SignalEngine` cannot live
// here; the phone runs it exactly as it does for the Apple Watch. What crosses
// the BLE link is 5 Hz triples (pitch, roll, the RMS of the residual) batched
// every 4 seconds. Breathing lives at 0.05 to 0.5 Hz, so 5 Hz is four times
// Nyquist with room to spare, and stillness survives the decimation because
// each bin carries the RMS of its five raw samples rather than one sample of
// them.
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

    var bridge;
    var reducer;
    var session;
    var startMs;
    var running;
    var heartRate;
    var batches;

    function initialize(theBridge) {
        bridge = theBridge;
        reducer = new Reducer();
        running = false;
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
        reducer = new Reducer();
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
    // The callbacks carry explicit types because Monkey C's checker matches
    // the signature it will call them with, not just the arity.
    function onSensor(info as Sensor.Info) as Void {
        if (info has :heartRate && info.heartRate != null) {
            heartRate = info.heartRate;
        }
    }

    function onData(sensorData as Sensor.SensorData) as Void {
        var accel = sensorData.accelerometerData;
        if (accel == null) { return; }

        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) { return; }

        var out = reducer.reduce(xs, ys, zs);

        var rr = [];
        var hrData = sensorData.heartRateData;
        if (hrData != null && hrData.heartBeatIntervals != null) {
            rr = hrData.heartBeatIntervals;
        }

        batches += 1;
        bridge.send({
            "v" => 1,
            "t" => elapsedMs(),
            "hz" => SAMPLE_RATE / reducer.BIN,
            "s" => out,
            "hr" => heartRate,
            "rr" => rr
        });
    }
}
