import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import "../../theming" as T

// Battery — UPower: charge %, charging state, health, time remaining, capacity,
// plus power-profile selection (power-profiles-daemon). This page is only listed
// in the nav when a battery is actually present (see SettingsWindow), so on a
// desktop it disappears entirely.
Item {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isLaptopBattery
    // UPower reports percentage as a 0–1 fraction; convert to whole percent.
    readonly property real pct: dev ? dev.percentage * 100 : 0
    readonly property int  state: dev ? dev.state : 0
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
    readonly property bool full: state === UPowerDeviceState.FullyCharged

    function stateText() {
        if (full) return "Fully charged"
        if (charging) return "Charging"
        if (state === UPowerDeviceState.Discharging) return "On battery"
        return "Not charging"
    }
    function fmtTime(secs) {
        if (!secs || secs <= 0) return "—"
        var h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m"
    }

    // ── Power profiles ────────────────────────────────────────────────────────────
    property string profile: ""
    property var profiles: []
    Process {
        id: profQuery
        command: ["bash", "-c",
            "echo CUR=$(powerprofilesctl get 2>/dev/null); "
          + "echo LIST=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[* ] \\([a-z-]*\\):/\\1/p' | tr '\\n' ',')"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                text.split("\n").forEach(function(l) {
                    if (l.indexOf("CUR=") === 0) root.profile = l.substring(4).trim()
                    else if (l.indexOf("LIST=") === 0)
                        root.profiles = l.substring(5).split(",").filter(function(x){ return x.length })
                })
            }
        }
    }
    Process { id: profSet; onExited: { profQuery.running = false; profQuery.running = true } }
    function setProfile(p) { profSet.command = ["powerprofilesctl", "set", p]; profSet.running = true }

    function profLabel(p) {
        return p === "power-saver" ? "Power saver" : p === "performance" ? "Performance" : "Balanced"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 20

        Text {
            text: "Battery"
            color: T.Theme.ink
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
        }

        // Big charge readout.
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Text {
                text: {
                    if (root.charging) return String.fromCodePoint(0xF0084)  // charging
                    if (root.pct <= 5) return String.fromCodePoint(0xF0083)  // alert
                    var r = Math.round(root.pct / 10)
                    return String.fromCodePoint(r >= 10 ? 0xF0079 : 0xF0079 + r)
                }
                color: root.charging ? T.Theme.accent : (root.pct <= 15 ? T.Theme.accentAlt : T.Theme.ink)
                font { family: T.Theme.fontFamily; pixelSize: 52 }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: Math.round(root.pct) + "%"
                    color: T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 16; bold: true }
                }
                Text {
                    text: root.stateText()
                    color: T.Theme.accent
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize }
                }
            }
        }

        // Details.
        Rectangle {
            Layout.fillWidth: true
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            implicitHeight: detail.implicitHeight + 24
            ColumnLayout {
                id: detail
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16; anchors.rightMargin: 16
                spacing: 8
                Row2 { k: "Time remaining"; v: root.charging ? (root.fmtTime(root.dev ? root.dev.timeToFull : 0) + " to full")
                                                             : (root.fmtTime(root.dev ? root.dev.timeToEmpty : 0) + " left") }
                Row2 { k: "Health"; v: (root.dev && root.dev.healthSupported) ? Math.round(root.dev.healthPercentage) + "%" : "—" }
                Row2 { k: "Capacity"; v: root.dev ? (root.dev.energyCapacity.toFixed(1) + " Wh") : "—" }
                Row2 { k: "Rate"; v: root.dev ? (Math.abs(root.dev.changeRate).toFixed(1) + " W") : "—" }
            }
        }

        // Power profile selector.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.profiles.length > 0
            spacing: 8
            Text {
                text: "Power mode"
                color: T.Theme.accent
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: root.profiles
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: root.profile === modelData
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: T.Theme.moduleRadius
                        color: sel ? T.Theme.surfaceActive : (pma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                        border.width: sel ? 1 : 0
                        border.color: T.Theme.accent
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: root.profLabel(modelData)
                            color: sel ? T.Theme.accent : T.Theme.ink
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: sel }
                        }
                        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setProfile(modelData) }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    component Row2: RowLayout {
        property string k: ""
        property string v: ""
        Layout.fillWidth: true
        spacing: 12
        Text { Layout.preferredWidth: 130; text: k; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 } }
        Text { Layout.fillWidth: true; text: v; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 } }
    }
}
