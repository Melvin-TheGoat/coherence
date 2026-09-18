// One batch out over BLE, every four seconds.
//
// No retry queue and no backlog, on purpose: a watch app has tens of KB, and
// a buffer big enough to matter is a buffer big enough to crash the app. A
// batch that cannot be delivered is DROPPED and counted, because
// `SignalEngine` already skips windows that are short of samples; the camera
// path learned the same thing about dropped frames. v1 therefore assumes the
// phone is nearby, which it is: the audio is playing on it.

using Toybox.Communications;
using Toybox.Lang;

class Bridge extends Communications.ConnectionListener {

    var sent;
    var dropped;

    function initialize() {
        ConnectionListener.initialize();
        sent = 0;
        dropped = 0;
    }

    function send(payload) {
        Communications.transmit(payload, null, self);
    }

    function onComplete() {
        sent += 1;
    }

    function onError() {
        dropped += 1;
    }

    // True once anything has landed, so the view can say whether the phone is
    // listening rather than guessing.
    function delivering() {
        return sent > 0 && dropped < 3;
    }
}
