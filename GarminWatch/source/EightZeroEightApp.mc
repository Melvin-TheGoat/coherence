using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

class EightZeroEightApp extends Application.AppBase {

    var capture;
    var bridge;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        bridge = new Bridge();
        capture = new Capture(bridge);
    }

    // Leaving the app must end the activity session and unregister the
    // sensors, or the watch keeps recording a meditation nobody is sitting.
    function onStop(state) {
        if (capture != null) {
            capture.stop();
        }
    }

    function getInitialView() {
        return [new SessionView(capture), new SessionDelegate(capture)];
    }
}
