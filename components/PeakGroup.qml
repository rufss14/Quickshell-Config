import QtQuick
import Quickshell.Services.Pipewire
import "../services"

// ── PeakGroup ─────────────────────────────────────────────────────────────────
// The loudest of several nodes, as one level. An app can hold more than one capture
// stream (Discord: microphone plus game audio), and only one of them may be live, so
// metering only the first would read flat whenever the live one was another.
//
// Lived inline in SoundPage; the bar's mixer needs the same for its "recording" rows.
// Non-visual. Feed `peak` through Audio.meterLevel() for a bar.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: pg

    property var  nodes:  []
    property bool active: false
    property real peak:   0

    function note(v) { pg.peak = Math.max(v, pg.peak * 0.75) }

    // Nothing is arriving to decay it, so it would otherwise freeze at its last
    // value and the row would keep showing a level after the page closed.
    onActiveChanged: if (!pg.active) pg.peak = 0

    Repeater {
        model: pg.nodes

        Item {
            id: pgSlot
            required property var modelData

            // pgSlot.modelData, not `parent.modelData`: PwNodePeakMonitor is a plain
            // QObject, so it has no visual `parent` to reach through.
            PwNodePeakMonitor {
                node:    pgSlot.modelData
                enabled: pg.active && Audio.hasKnownChannels(pgSlot.modelData)
                onPeakChanged: pg.note(peak)
            }
        }
    }
}
