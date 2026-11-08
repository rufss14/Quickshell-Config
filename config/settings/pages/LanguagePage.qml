import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../theming" as T

// Language & Region — system locale via localectl. Shows the current LANG,
// lists available locales, and applies a new one with `localectl set-locale`
// (this goes through polkit, so a password prompt may appear).
Item {
    id: root

    property string current: ""
    property var locales: []
    property string status: ""

    Component.onCompleted: { curProc.running = true; listProc.running = true }

    Process {
        id: curProc
        command: ["bash", "-c", "localectl status 2>/dev/null | sed -n 's/.*LANG=\\([^ ]*\\).*/\\1/p'"]
        stdout: StdioCollector { onStreamFinished: root.current = text.trim() }
    }
    Process {
        id: listProc
        command: ["localectl", "list-locales"]
        stdout: StdioCollector { onStreamFinished: root.locales = text.trim().length ? text.trim().split("\n") : [] }
    }
    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: function(code) {
            root.status = code === 0 ? "Applied. Some apps need a restart to switch." : (setErr.text.trim() || "Failed to set locale.")
            curProc.running = false; curProc.running = true
        }
    }
    function setLocale(l) {
        root.status = "Applying " + l + "…"
        setProc.command = ["localectl", "set-locale", "LANG=" + l]
        setProc.running = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Text {
            text: "Language & Region"
            color: T.Theme.ink
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
        }

        RowLayout {
            spacing: 10
            Text {
                text: String.fromCodePoint(0xF05CA)   // translate
                color: T.Theme.accent
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 6 }
            }
            ColumnLayout {
                spacing: 0
                Text { text: "Current locale"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 } }
                Text { text: root.current || "—"; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 1; bold: true } }
            }
        }

        Text {
            visible: root.status.length > 0
            text: root.status
            color: T.Theme.accent
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
        }

        Text { text: "Available locales"; color: T.Theme.accent; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true } }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.locales
            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: 42
                radius: T.Theme.moduleRadius
                readonly property bool sel: modelData === root.current
                color: sel ? T.Theme.surfaceActive : (lma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                    Text {
                        Layout.fillWidth: true
                        text: modelData
                        color: T.Theme.ink
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: sel }
                    }
                    Text {
                        visible: sel
                        text: String.fromCodePoint(0xF012C)   // check
                        color: T.Theme.accent
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 2 }
                    }
                }
                MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !sel; onClicked: root.setLocale(modelData) }
            }
        }
    }
}
