import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── WifiButton ────────────────────────────────────────────────────────────────
// Left-click  → toggle WifiPanel popup
// Right-click → collapse to icon-only / expand to show SSID label
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool barShape:  false
    property bool wifiOpen:  false
    property bool collapsed: false

    property string ssid:    ""
    property int    signal:  -1
    property bool   enabled: true

    signal toggleWifi()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  pill.implicitWidth

    // ── Poller ────────────────────────────────────────────────────────────────
    Process {
        id: wifiPoller
        command: ["sh", "-c",
            "radio=$(nmcli radio wifi); " +
            "if [ \"$radio\" = 'enabled' ]; then " +
            "  nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list 2>/dev/null | grep '^yes' | head -1; " +
            "else echo 'disabled'; fi"
        ]
        running: true
        property string _buf: ""

        stdout: SplitParser {
            onRead: data => { wifiPoller._buf = data.trim() }
        }

        onRunningChanged: {
            if (!running) {
                var line = wifiPoller._buf
                if (line === "disabled") {
                    root.enabled = false; root.ssid = ""; root.signal = -1
                } else if (line === "") {
                    root.enabled = true;  root.ssid = ""; root.signal = -1
                } else {
                    var parts = line.split(":")
                    root.enabled = true
                    root.ssid    = parts.length >= 2 ? parts.slice(1, parts.length - 1).join(":") : ""
                    root.signal  = parts.length >= 3 ? parseInt(parts[parts.length - 1]) || -1 : -1
                }
                wifiPoller._buf = ""
            }
        }
    }

    Timer {
        interval: 8000; repeat: true; running: true
        onTriggered: { wifiPoller.running = false; wifiPoller.running = true }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function wifiIcon() {
        if (!root.enabled) return "󰤭"
        if (root.ssid === "") return "󰤫"
        var s = root.signal
        if (s < 0)  return "󰤫"
        if (s < 25) return "󰤟"
        if (s < 50) return "󰤢"
        if (s < 75) return "󰤥"
        return "󰤨"
    }

    function iconColor() {
        if (!root.enabled || root.ssid === "") return T.Theme.fg
        var s = root.signal
        if (s < 25) return T.Theme.pw(T.Theme.pal?.colors?.color1, 0.90)
        if (s < 50) return T.Theme.pw(T.Theme.pal?.colors?.color3, 0.90)
        return T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90)
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: T.Theme.pillHeight
        radius: T.Theme.radius(root.barShape)
        clip:   true

        readonly property int pad:    T.Theme.pillPadding
        readonly property int gap:    6
        readonly property int iconW:  iconMeasure.implicitWidth
        readonly property int labelW: labelMeasure.implicitWidth

        readonly property int collapsedW: pad + iconW + pad
        readonly property int expandedW:  pad + iconW + gap + labelW + pad

        implicitWidth: root.collapsed ? collapsedW : expandedW
        width: implicitWidth
        Behavior on implicitWidth { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        color: root.wifiOpen ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.20)
                             : T.Theme.pillBg
        Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
        Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        // Hidden measure texts — stable width references, never shown
        Text {
            id: iconMeasure
            visible: false
            text: "󰤨"
            font { pixelSize: 15; family: T.Theme.fontFamily }
        }
        Text {
            id: labelMeasure
            visible: false
            text: root.ssid !== "" ? root.ssid : "Wi-Fi"
            font { pixelSize: 11; weight: Font.Medium; family: T.Theme.fontFamily }
        }

        // Hover overlay
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: hov.containsMouse
                ? (root.wifiOpen ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.32) : T.Theme.hoverAccent)
                : "transparent"
            Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        }

        // ── Collapsed content (icon-only) ─────────────────────────────────────
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.collapsed ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }

            Text {
                text:  root.wifiIcon()
                color: root.iconColor()
                font { pixelSize: 15; family: T.Theme.fontFamily }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }
        }

        // ── Expanded content (icon + SSID label) ──────────────────────────────
        // Pill width animates immediately.
        // Label only fades in AFTER the pill has visibly started expanding.
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.collapsed ? 0.0 : 1.0

            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation {
                        // 85 ms delay ONLY when expanding (pill grows first)
                        // 0 ms when collapsing (text disappears instantly)
                        duration: root.collapsed ? 0 : 85
                    }
                    NumberAnimation {
                        duration: T.Theme.animFast
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                text:  root.wifiIcon()
                color: root.iconColor()
                font { pixelSize: 15; family: T.Theme.fontFamily }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }

            Text {
                text:  root.ssid !== "" ? root.ssid : "Wi-Fi"
                color: T.Theme.fg
                font { pixelSize: 11; weight: Font.Medium; family: T.Theme.fontFamily }
                verticalAlignment: Text.AlignVCenter
                height: T.Theme.pillHeight
            }
        }

        // ── Left-click: toggle panel ──────────────────────────────────────────
        MouseArea {
            id: hov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: root.toggleWifi()
        }

        // ── Right-click: collapse / expand ────────────────────────────────────
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: root.collapsed = !root.collapsed
        }
    }
}
