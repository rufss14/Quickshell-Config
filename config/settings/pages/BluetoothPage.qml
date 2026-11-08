import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T
import ".."

// Bluetooth page — BlueZ (bluetoothctl). Master power toggle, background scan
// while the page is open, device list with pair / connect / disconnect. Scanning
// stops automatically when the settings window closes (Loader gated on shown).
Item {
    id: root

    property bool powered: true
    property var devices: []          // [{ mac, paired, connected, name }]
    property string status: ""
    property bool working: false

    function refresh() { powerProc.running = false; powerProc.running = true
                         devProc.running = false; devProc.running = true }

    Component.onCompleted: refresh()

    Process {
        id: powerProc
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.powered = text.trim() === "on" }
    }

    Process {
        id: devProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quicktest/scripts/bt-devices.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = []
                text.split("\n").forEach(function(line) {
                    if (!line) return
                    var p = line.split("|")
                    if (p.length < 4) return
                    arr.push({ mac: p[0], paired: p[1] === "1", connected: p[2] === "1", name: p.slice(3).join("|") })
                })
                arr.sort(function(a, b) { return (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name) })
                root.devices = arr
            }
        }
    }

    // Continuous discovery while powered + page open. Killed when the page unloads.
    Process {
        id: scanProc
        command: ["bluetoothctl", "scan", "on"]
        running: root.powered
        // If bluetoothctl exits, the restart timer brings scanning back.
    }
    Timer {
        interval: 8000; running: true; repeat: true
        onTriggered: {
            if (root.powered && !scanProc.running) scanProc.running = true
            root.refresh()
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────────
    Process { id: powerToggle; onExited: root.refresh() }
    function setPowered(on) {
        powerToggle.command = ["bluetoothctl", "power", on ? "on" : "off"]
        powerToggle.running = true
    }

    Process { id: actProc; onExited: { root.working = false; root.refresh() } }
    function pair(mac, name) {
        root.working = true; root.status = "Pairing " + name + "…"
        actProc.command = ["bash", "-c", "bluetoothctl pair " + mac + " && bluetoothctl trust " + mac + " && bluetoothctl connect " + mac]
        actProc.running = true
    }
    function connect(mac, name)    { root.working = true; root.status = "Connecting " + name + "…"; actProc.command = ["bluetoothctl", "connect", mac]; actProc.running = true }
    function disconnect(mac, name) { root.working = true; root.status = "Disconnecting " + name + "…"; actProc.command = ["bluetoothctl", "disconnect", mac]; actProc.running = true }

    // ── UI ────────────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Bluetooth"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }
            Item { Layout.fillWidth: true }
            RowLayout {
                visible: root.powered
                spacing: 6
                Text {
                    text: String.fromCodePoint(0xF0210)   // magnify (scanning)
                    color: T.Theme.accent
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize }
                    RotationAnimation on rotation { running: root.powered; loops: Animation.Infinite; from: 0; to: 360; duration: 2500 }
                }
                Text {
                    text: "Scanning…"
                    color: T.Theme.inkDim
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
                }
            }
            Toggle {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 10
                on: root.powered
                onToggled: function(v) { root.setPowered(v) }
            }
        }

        Text {
            visible: !root.powered
            text: "Bluetooth is off."
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; italic: true }
        }
        Text {
            visible: root.status.length > 0 && root.powered
            Layout.fillWidth: true
            text: root.status
            color: T.Theme.accent
            elide: Text.ElideRight
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.powered
            clip: true
            spacing: 4
            model: root.devices

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: 52
                radius: T.Theme.moduleRadius
                color: modelData.connected ? T.Theme.surfaceActive : (dma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 10
                    Text {
                        text: String.fromCodePoint(modelData.connected ? 0xF00B1 : 0xF00AF)  // bluetooth-connect / bluetooth
                        color: modelData.connected ? T.Theme.accent : T.Theme.ink
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 4 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData.name
                            color: T.Theme.ink
                            elide: Text.ElideRight
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: modelData.connected }
                        }
                        Text {
                            text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Available"
                            color: T.Theme.inkDim
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                        }
                    }
                    TextBtn {
                        label: modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"
                        danger: modelData.connected
                        accent: !modelData.paired
                        enabled: !root.working
                        onClicked: {
                            if (modelData.connected)   root.disconnect(modelData.mac, modelData.name)
                            else if (modelData.paired) root.connect(modelData.mac, modelData.name)
                            else                        root.pair(modelData.mac, modelData.name)
                        }
                    }
                }
                MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }
        Text {
            visible: root.powered && root.devices.length === 0
            text: "Searching for devices…"
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; italic: true }
        }
    }

    component TextBtn: Rectangle {
        property string label: ""
        property bool danger: false
        property bool accent: false
        signal clicked()
        implicitWidth: lbl.implicitWidth + 24; implicitHeight: 30
        radius: T.Theme.moduleRadius
        opacity: enabled ? 1 : 0.5
        color: tbma.containsMouse ? T.Theme.surfaceHover : (accent ? T.Theme.surfaceActive : T.Theme.surfaceAlt)
        Text {
            id: lbl; anchors.centerIn: parent; text: parent.label
            color: parent.danger ? T.Theme.accentAlt : parent.accent ? T.Theme.accent : T.Theme.ink
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; bold: true }
        }
        MouseArea { id: tbma; anchors.fill: parent; hoverEnabled: true; enabled: parent.enabled; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }
}
