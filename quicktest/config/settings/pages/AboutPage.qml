import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T

// Services / About — real machine specs, queried live (never hardcoded) via
// scripts/specs.sh: CPU, GPU, RAM, kernel, distro, host, uptime, and every
// connected monitor (including refresh rate, so the 144Hz panel shows).
Item {
    id: root

    property var spec: ({})       // key → value
    property var monitors: []     // [{ name, mode, desc }]

    function refresh() { proc.running = false; proc.running = true }
    Component.onCompleted: refresh()

    Process {
        id: proc
        command: ["bash", Quickshell.env("HOME") + "/.config/quicktest/scripts/specs.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = {}, mons = []
                text.split("\n").forEach(function(line) {
                    if (!line) return
                    var eq = line.indexOf("=")
                    if (eq < 0) return
                    var k = line.substring(0, eq), v = line.substring(eq + 1)
                    if (k === "MON") {
                        var p = v.split("|")
                        mons.push({ name: p[0], mode: p[1] || "", desc: p[2] || "" })
                    } else s[k] = v
                })
                root.spec = s
                root.monitors = mons
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        ColumnLayout {
            id: col
            width: parent.width
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "About this PC"
                    color: T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.spec.HOST || ""
                    color: T.Theme.accent
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                }
            }

            Group {
                title: "System"
                Row2 { k: "Distro";  v: root.spec.DISTRO || "—" }
                Row2 { k: "Kernel";  v: root.spec.KERNEL || "—" }
                Row2 { k: "Uptime";  v: root.spec.UPTIME || "—" }
            }
            Group {
                title: "Processor"
                Row2 { k: "CPU";   v: root.spec.CPU || "—" }
                Row2 { k: "Cores"; v: root.spec.CORES || "—" }
            }
            Group {
                title: "Graphics"
                Row2 { k: "GPU";    v: root.spec.GPU || "—" }
                Row2 { k: "Driver"; v: root.spec.DRIVER || "—" }
                Row2 { k: "VRAM";   v: root.spec.VRAM || "—" }
            }
            Group {
                title: "Memory"
                Row2 { k: "RAM"; v: root.spec.RAM || "—" }
            }
            Group {
                title: "Displays"
                Repeater {
                    model: root.monitors
                    delegate: Row2 {
                        required property var modelData
                        k: modelData.name
                        v: modelData.mode + (modelData.desc ? "   ·   " + modelData.desc : "")
                    }
                }
            }
        }
    }

    // ── Reusable spec group + row ─────────────────────────────────────────────────
    component Group: ColumnLayout {
        default property alias content: inner.data
        property string title: ""
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: title
            color: T.Theme.accent
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
        }
        Rectangle {
            Layout.fillWidth: true
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            implicitHeight: inner.implicitHeight + 20
            ColumnLayout {
                id: inner
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 6
            }
        }
    }
    component Row2: RowLayout {
        property string k: ""
        property string v: ""
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.preferredWidth: 90
            text: k
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 }
        }
        Text {
            Layout.fillWidth: true
            text: v
            color: T.Theme.ink
            wrapMode: Text.WordWrap
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 }
        }
    }
}
