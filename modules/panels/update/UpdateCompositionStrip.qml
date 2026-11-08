import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── CompositionStrip ─────────────────────────────────────────────────────
// Same idiom as UpdatesPage's own strip (built locally there too, for the
// same reason): official/AUR/flatpak side by side, widths proportional to
// share of the total. An empty pending list draws as a flat muted track
// rather than three invisible zero-width segments.
// (Was UpdatePanel's inline `CompositionStrip`; `host` is the UpdatePanel.)
Item {
    required property var host
    id: strip

    property int official: 0
    property int aur:      0
    property int flatpak:  0
    readonly property int total: strip.official + strip.aur + strip.flatpak

    implicitHeight: Tokens.spacingXs + 2

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
        visible: strip.total === 0
    }

    Row {
        anchors.fill: parent
        visible: strip.total > 0
        spacing: 1   // a hairline seam between segments, not a gap in the bar

        Rectangle {
            width:  Math.round((strip.width - 2) * (strip.official / Math.max(strip.total, 1)))
            height: parent.height
            radius: height / 2
            color:  host.officialTint
            Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }
        Rectangle {
            width:  Math.round((strip.width - 2) * (strip.aur / Math.max(strip.total, 1)))
            height: parent.height
            radius: height / 2
            color:  host.aurTint
            Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }
        Rectangle {
            width:  Math.round((strip.width - 2) * (strip.flatpak / Math.max(strip.total, 1)))
            height: parent.height
            radius: height / 2
            color:  host.flatpakTint
            Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }
    }
}
