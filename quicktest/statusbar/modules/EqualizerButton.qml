import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── EqualizerButton ───────────────────────────────────────────────────────────
// Left-click  → toggle EqualizerPanel popup
// Scroll      → adjust volume
// Right-click → expand inline volume slider (0–100%)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool barShape:      false
    property bool equalizerOpen: false
    property bool showSlider:    false

    signal toggleEqualizer()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  pill.implicitWidth

    // ── Volume state ──────────────────────────────────────────────────────────
    property real _vol:   0.0
    property bool _muted: false

    readonly property color _accent: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90)
    readonly property color _dim:    T.Theme.pw(T.Theme.pal?.colors?.color4, 0.22)

    readonly property string _icon: {
        if (_muted || _vol <= 0.0) return "󰝟"
        if (_vol < 0.35)           return "󰕿"
        if (_vol < 0.70)           return "󰖀"
        return "󰕾"
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: volReader.running = true
    }

    Process {
        id: volReader
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        running: false
        property string _buf: ""
        stdout: SplitParser {
            onRead: function(data) { volReader._buf = data.trim() }
        }
        onRunningChanged: {
            if (!running && _buf !== "") {
                var parts = _buf.split(/\s+/)
                root._vol   = Math.min(1.0, parseFloat(parts[1]) || 0.0)
                root._muted = _buf.indexOf("[MUTED]") !== -1
                _buf = ""
            }
        }
    }

    Process {
        id: volChanger
        running: false
        onRunningChanged: { if (!running) volReader.running = true }
    }

    function setVolume(v) {
        var clamped = Math.max(0.0, Math.min(1.0, v))
        volChanger.command = ["sh", "-c",
            "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + clamped.toFixed(2)
        ]
        volChanger.running = false
        volChanger.running = true
        root._vol = clamped
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: T.Theme.pillHeight
        radius: T.Theme.radius(root.barShape)
        clip:   true

        // Tight: padding + icon + gap + label + padding
        // Expanded: padding + icon + gap + slider(80) + gap + pct + padding
        readonly property int pad:        T.Theme.pillPadding
        readonly property int iconW:      iconTextMeasure.implicitWidth
        readonly property int labelW:     volTextMeasure.implicitWidth
        readonly property int sliderW:    80
        readonly property int pctW:       pctTextMeasure.implicitWidth
        readonly property int gap:        6

        readonly property int collapsedW: pad + iconW + gap + labelW + pad
        readonly property int expandedW:  pad + iconW + gap + sliderW + gap + pctW + pad

        implicitWidth: root.showSlider ? expandedW : collapsedW
        width: implicitWidth

        Behavior on implicitWidth { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        color: root.equalizerOpen ? T.Theme.btnActiveBg
                                  : (hov.containsMouse ? T.Theme.btnHoverBg : T.Theme.pillBg)
        Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
        Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        // Hidden measure texts (always rendered, never visible)
        Text {
            id: iconTextMeasure
            visible: false
            text: "󰕾"  // widest icon
            font { pixelSize: 15; family: T.Theme.fontFamily }
        }
        Text {
            id: volTextMeasure
            visible: false
            text: root._muted ? "muted" : Math.round(root._vol * 100) + "%"
            font { pixelSize: 11; family: T.Theme.fontFamily; weight: Font.Bold }
        }
        Text {
            id: pctTextMeasure
            visible: false
            text: "100%"
            font { pixelSize: 11; family: T.Theme.fontFamily; weight: Font.Bold }
        }

        // ── Collapsed view ────────────────────────────────────────────────────
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.showSlider ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }

            Text {
                id: iconText
                text: root._icon
                color: root._muted ? T.Theme.color1
                                   : (root.equalizerOpen ? T.Theme.btnActiveFg : T.Theme.btnFg)
                font { pixelSize: 15; family: T.Theme.fontFamily }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }

            Text {
                text: root._muted ? "muted" : Math.round(root._vol * 100) + "%"
                color: root._muted ? T.Theme.color1
                                   : (root.equalizerOpen ? T.Theme.btnActiveFg : T.Theme.btnFg)
                font { pixelSize: 11; family: T.Theme.fontFamily; weight: Font.Bold }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }
        }

        // ── Expanded view ─────────────────────────────────────────────────────
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.showSlider ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal } }

            Text {
                text: root._icon
                color: root._muted ? T.Theme.color1 : root._accent
                font { pixelSize: 15; family: T.Theme.fontFamily }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }

            Item {
                id: track
                width:  pill.sliderW
                height: T.Theme.pillHeight

                Rectangle {
                    id: rail
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 3; radius: 2
                    color: root._dim
                }
                Rectangle {
                    anchors.top:    rail.top
                    anchors.bottom: rail.bottom
                    anchors.left:   rail.left
                    radius: rail.radius
                    color:  root._accent
                    width:  Math.max(rail.radius * 2, rail.width * root._vol)
                    Behavior on width { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                }
                Rectangle {
                    anchors.verticalCenter: rail.verticalCenter
                    width: 9; height: 9; radius: 5
                    color: root._accent
                    x: Math.max(0, Math.min(track.width - width, track.width * root._vol - width / 2))
                    Behavior on x { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                }
                MouseArea {
                    anchors.fill:         parent
                    anchors.topMargin:    -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor
                    onPressed:         function(m) { root.setVolume(m.x / track.width) }
                    onPositionChanged: function(m) { if (pressed) root.setVolume(m.x / track.width) }
                }
            }

            Text {
                text: root._muted ? "mut" : Math.round(root._vol * 100) + "%"
                color: root._muted ? T.Theme.color1 : T.Theme.btnFg
                font { pixelSize: 11; family: T.Theme.fontFamily; weight: Font.Bold }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                opacity: 0.75
                width: pill.pctW
            }
        }

        // ── Hover area (collapsed) ─────────────────────────────────────────────
        MouseArea {
            id: hov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            enabled: !root.showSlider
            onClicked: root.toggleEqualizer()
            onWheel: function(w) { root.setVolume(root._vol + (w.angleDelta.y > 0 ? 0.05 : -0.05)) }
        }

        // ── Hover area (expanded, icon side only) ─────────────────────────────
        MouseArea {
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            width:          pill.pad + pill.iconW
            hoverEnabled:   true
            visible:        root.showSlider
            cursorShape:    Qt.PointingHandCursor
            onClicked:      root.toggleEqualizer()
            onWheel: function(w) { root.setVolume(root._vol + (w.angleDelta.y > 0 ? 0.05 : -0.05)) }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: root.showSlider = !root.showSlider
        }
    }
}
