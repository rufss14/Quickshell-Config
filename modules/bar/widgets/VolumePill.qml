import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── VolumePill ────────────────────────────────────────────────────────────────
// Speaker icon, a travelling-wave slider, level — always shown, no more
// collapsed/expanded toggle. (Showing the slider only on hover was tried 2026-10-31
// and undone the same day: the user preferred it always there.) The wave's SIZE follows the sink's actual peak
// level (a PwNodePeakMonitor, through Audio.meterLevel()), not the volume
// percentage — see WaveSlider.qml for why those are different questions, and
// why the level is smoothed there rather than fed raw.
//
//   left-click   → open the full mixer panel
//   middle-click → toggle mute
//   scroll       → step volume
//
// Was EqualizerButton. It polled `sh -c wpctl get-volume` every 2 seconds and
// spawned another `wpctl set-volume` on every single scroll tick and every drag
// frame — and, because the bar built both its layouts, all of that ran twice.
// The level shown could be up to 2s stale, which is why it used to visibly lag
// behind the volume keys.
//
// Now it reads Audio (native PipeWire, pushed) and writes by assigning a
// property. No process, no poll, no debounce, and the number is always current.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.of(QsWindow.window).primary

    property bool active: false
    signal toggled()

    readonly property real volume: Audio.volume
    readonly property bool muted:  Audio.muted

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    readonly property int gap:     Tokens.spacingMd
    readonly property int sliderW: 80

    // Gated on visible, same discipline SoundPage's own meters use — enabling
    // one asks PipeWire to keep streaming peak data for that node.
    PwNodePeakMonitor {
        id: sinkPeak
        node:    Audio.sink
        enabled: root.visible && Audio.ready && Audio.hasKnownChannels(Audio.sink)
    }

    readonly property int iconExt: Math.round(Tokens.fontTitle * Config.barIconScale)

    readonly property string iconName: Audio.iconName(root.volume, root.muted)
    // A real name to start on (corrected in onCompleted, no animation): an empty one
    // would draw nothing for a frame.
    property string shownIcon: "headphones"
    Component.onCompleted: root.shownIcon = root.iconName

    // The level reads at full strength while it is being changed, and settles back to
    // dim a moment after the last step. StyledText already animates its own colour, so
    // `emphasis` is all this needs. The timer is a dwell, not motion; motion off makes
    // it 0, so the highlight is simply never seen.
    property bool adjusting: false
    onVolumeChanged: { root.adjusting = true; adjustDwell.restart() }
    Timer { id: adjustDwell; interval: Motion.spatialSlow; onTriggered: root.adjusting = false }

    IconButton {
        id: pill
        tipProvider: Config.barTooltips ? function () { return ModuleGlance.tip("volume") } : null
        container: false
        height: Config.barPillHeight
        // The row's width, which the level's slot animates (it closes while muted).
        width:  Tokens.pillPadding + row.implicitWidth + Tokens.pillPadding

        squareMode: Config.barShape
        active:     root.active
        clip:       true
        interactive: false     // the icon and slider own their own hit areas below

        // Hidden measure — keeps the pill's width stable rather than letting it
        // twitch as the percentage changes width between e.g. "9%" and "100%". The
        // icon needs no such measure: it's a fixed size regardless of level.
        BarLabel {
            id: levelMeasure
            visible: false
            text: "100%"
        }

        // No spacing: each slot carries the gap before it, so a closed one leaves none.
        Row {
            id: row
            anchors.left:           parent.left
            anchors.leftMargin:     Tokens.pillPadding
            anchors.verticalCenter: parent.verticalCenter

            Item {
                width:  root.iconExt
                height: Config.barPillHeight

                // Mute pops the icon (it shrinks out and the other one grows in) instead
                // of cutting; `shownIcon` is the held copy SwapFade needs. Not on every
                // volume step — the icon only changes with the muted state.
                // Colour transition is the Behavior on the icon's color.
                SwapFade {
                    target:   speaker
                    key:      root.iconName
                    shownKey: root.shownIcon
                    travel:   0
                    dip:      0.7
                    onSwapped: root.shownIcon = root.iconName
                }
                MaterialIcon {
                    id: speaker
                    anchors.centerIn: parent
                    name:  root.shownIcon
                    // Filled while its panel is open, as every IconButton's symbol is.
                    fill:  root.active ? 1 : 0
                    font.pixelSize: root.iconExt
                    color:  root.muted ? Colors.of(QsWindow.window).danger
                          : root.active ? Colors.of(QsWindow.window).stateActiveFg
                          : root.accent
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(m) {
                        if (m.button === Qt.MiddleButton) Audio.toggleMute()
                        else                               root.toggled()
                    }
                    onWheel: function(w) { Audio.stepVolume(w.angleDelta.y > 0 ? 0.05 : -0.05) }
                }
            }

            // The slider, and the gap before it.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width:  root.gap + root.sliderW
                height: Config.barPillHeight

                WaveSlider {
                    x:      root.gap
                    anchors.verticalCenter: parent.verticalCenter
                    width:  root.sliderW
                    value:  root.volume
                    accent: root.accent
                    level:  root.muted ? 0 : Audio.meterLevel(sinkPeak.peak)
                    onMoved:    function(v) { Audio.setVolume(v) }
                    onScrolled: function(d) { Audio.stepVolume(d * 0.05) }
                }
            }

            // The level, and the gap before it. Muted, it goes: the icon says so (it read "mut").
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width:  root.muted ? 0 : root.gap + levelMeasure.implicitWidth
                height: levelText.implicitHeight
                clip:   true
                Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                BarLabel {
                    id: levelText
                    x:        root.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text:     Math.round(root.volume * 100) + "%"
                    emphasis: root.adjusting ? "normal" : "dim"
                    opacity:  root.muted ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.enter } }
                }
            }
        }
    }
}
