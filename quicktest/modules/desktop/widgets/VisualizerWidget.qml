pragma ComponentBehavior: Bound
import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── VisualizerWidget ──────────────────────────────────────────────────────────
// The audio spectrum, on the desktop. Pure decoration, and the only widget here whose
// whole point is motion.
//
// Cava is refcounted and shared: the bar's pill, the desktop background and the sound
// page all read the SAME analyser, so adding this tile does not start a second cava.
// It releases when the tile is hidden, so a covered desktop isn't analysing audio.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Cava.acquire(); root._held = true }
        else if (!root.active && root._held) { Cava.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) Cava.release()

    Spectrum {
        anchors.fill: parent
        // Mirrored so the spectrum reads as symmetrical about its centre — the shape a
        // visualiser is expected to have, and it fills a wide tile better than a ramp
        // that trails off to the right.
        levels: Cava.mirrored(Cava.bars)
        barCount: root.size === "small" ? 16 : 32
        accent: root.accent
    }

    StyledText {
        anchors.centerIn: parent
        visible: !Cava.hasData
        text: "Play something"
        variant: "caption"
        emphasis: "dim"
    }
}
