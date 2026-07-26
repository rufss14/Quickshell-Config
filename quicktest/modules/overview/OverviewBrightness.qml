import QtQuick
import "../../config"
import "../../components"
import "../../services"

// ── OverviewBrightness ────────────────────────────────────────────────────────
// Vertical, iPhone-style brightness sliders — one per CONTROLLABLE monitor. Sits
// beside the media cards at the top of the overview, and stays there whether or not
// anything is playing (brightness isn't media, so it doesn't vanish with the cards).
//
// A monitor the shell can't drive (no DDC, no backlight) shows no slider rather than a
// dead one — an invisible delegate takes no room in the Row, so the visible sliders
// still address the model by their REAL index.
//
// The whole thing renders nothing at all when there's no controllable display, so a
// desktop with a fixed external monitor doesn't get an empty stub.
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    spacing: Tokens.spacingMd

    Component.onCompleted: Brightness.ensureProbed()

    readonly property int controllableCount: {
        let n = 0
        for (let i = 0; i < Brightness.monitors.count; i++)
            if (Brightness.monitors.get(i).controllable) n++
        return n
    }

    visible: controllableCount > 0

    Repeater {
        model: Brightness.monitors

        // ── One slider ────────────────────────────────────────────────────────
        Item {
            id: cell
            required property int index
            required property var model

            visible: cell.model.controllable
            width:  48
            height: 148

            readonly property real value: cell.model.brightness      // 0..100
            readonly property real min:   cell.model.type === "bcl" ? Brightness.laptopMinBrightness : 0

            function apply(v) {
                Brightness.requestBrightness(cell.index, Math.max(cell.min, Math.min(100, v)))
            }

            // The track.
            Surface {
                id: track
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width:  46
                height: 128
                elevation: Tokens.elevationNested
                // A true stadium — fully rounded caps top and bottom, the iOS Control
                // Centre pill. The fill's radius tracks this, so a low level reads as a
                // rounded lens sitting in the bottom cap.
                cornerRadius: Math.round(track.width / 2)
                clip: true
                focused: drag.pressed

                // Fill from the bottom. INSET from the edge and rounded, so the track's
                // border stays visible around it and its corners don't poke through the
                // rounded track (QML `clip` is rectangular — it wouldn't have masked them).
                Rectangle {
                    id: fill
                    readonly property int pad: 3

                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin:   fill.pad
                    anchors.rightMargin:  fill.pad
                    anchors.bottomMargin: fill.pad

                    height: (track.height - fill.pad * 2) * (cell.value / 100)
                    radius: track.cornerRadius - fill.pad

                    color: Colors.alpha(Colors.focus, 0.9)

                    // Must NOT ease while dragging — DDC takes ~300ms to confirm, and
                    // easing toward a value the finger already moved past reads as lag.
                    Behavior on height {
                        enabled: !drag.pressed
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                    }
                }

                // ── The sun ───────────────────────────────────────────────────
                // Sits at the bottom cap, so the fill rises past it. It GROWS and
                // BRIGHTENS with the level — dim and small at the floor, full and bright
                // at the top — which is the iOS Control Centre cue: the icon is the level,
                // the number is secondary. Behaviours ease both so a drag looks alive.
                StyledText {
                    id: sun
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.spacingMd
                    text: "󰃠"
                    variant: "title"
                    color: Colors.fg

                    readonly property real frac: cell.value / 100
                    scale:   0.78 + 0.42 * sun.frac
                    opacity: 0.50 + 0.50 * sun.frac
                    Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                }

                // The value — only while you're adjusting. iOS shows no number at rest;
                // the fill and the sun ARE the readout, and a number that's always there
                // turns a clean pill into a gauge.
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.spacingMd
                    text: Math.round(cell.value) + ""
                    variant: "caption"
                    font.family: Tokens.fontMono
                    font.bold: true
                    color: Colors.fg
                    opacity: drag.pressed ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    // Drag anywhere on the track, iPhone-style — press sets the value at
                    // the finger, and moving keeps setting it.
                    function fromY(y) {
                        const frac = 1 - Math.max(0, Math.min(1, y / height))
                        cell.apply(frac * 100)
                    }
                    onPressed:         function(m) { fromY(m.y) }
                    onPositionChanged: function(m) { if (pressed) fromY(m.y) }
                    onWheel:           function(w) { cell.apply(cell.value + (w.angleDelta.y > 0 ? 5 : -5)) }
                }
            }

            // Monitor label.
            StyledText {
                anchors.top: track.bottom
                anchors.topMargin: Tokens.spacingXs
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: cell.model.type === "bcl" ? "Internal"
                    : (cell.model.port || cell.model.label || "Display")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }
    }
}
