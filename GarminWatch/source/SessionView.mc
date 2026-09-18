// Elapsed time, and whether the phone is hearing us. Nothing else.
//
// The no-live-biometrics stance holds here exactly as it does on the Apple
// Watch: evidence comes after the session, never during it. And no haptics,
// which is a product rule about what a buzzing wrist does to someone trying
// to settle, not an Apple platform rule, so it carries over unchanged.

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;
using Toybox.Lang;

class SessionView extends WatchUi.View {

    var capture;
    var ticker;

    function initialize(theCapture) {
        View.initialize();
        capture = theCapture;
    }

    function onShow() {
        ticker = new Timer.Timer();
        ticker.start(method(:tick), 1000, true);
    }

    function onHide() {
        if (ticker != null) {
            ticker.stop();
            ticker = null;
        }
    }

    function tick() {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        if (!capture.running) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 20, Graphics.FONT_MEDIUM, "808",
                        Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 12, Graphics.FONT_XTINY, "Start on your phone,",
                        Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy + 30, Graphics.FONT_XTINY, "or press start",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var seconds = capture.elapsedSec();
        var text = (seconds / 60).format("%d") + ":" + (seconds % 60).format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 24, Graphics.FONT_NUMBER_MEDIUM, text,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var status = capture.bridge.delivering() ? "Sending to iPhone"
                                                 : "iPhone out of reach";
        dc.drawText(cx, cy + 26, Graphics.FONT_XTINY, status,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }
}
