using Toybox.WatchUi;
using Toybox.Lang;

class SessionDelegate extends WatchUi.BehaviorDelegate {

    var capture;

    function initialize(theCapture) {
        BehaviorDelegate.initialize();
        capture = theCapture;
    }

    // Start on the watch is a convenience, not the main door: the iPhone app
    // cannot be launched by the watch, so a sit begun here only reaches 808
    // if 808 is already running or backgrounded. The phone starts sessions.
    function onSelect() {
        if (capture.running) {
            capture.stop();
        } else {
            capture.start();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (capture.running) {
            capture.stop();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
}
