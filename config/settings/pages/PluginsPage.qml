import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T
import "../../config"
import ".."

// Plugins — discovers drop-in bar modules in ~/.config/quicktest/plugins/*.qml
// and lets you enable/disable each one. Enabling adds "plugin:<Name>" to the bar
// module list (Config.barModules); the bar loads the file dynamically. See
// plugins/README.md for the plugin contract.
Item {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/quicktest/plugins"
    property var plugins: []      // list of plugin base names (no .qml)

    Component.onCompleted: scanProc.running = true
    function rescan() { scanProc.running = false; scanProc.running = true }

    Process {
        id: scanProc
        command: ["bash", "-c", "find '" + root.dir + "' -maxdepth 1 -type f -name '*.qml' -printf '%f\\n' 2>/dev/null | sed 's/\\.qml$//' | sort"]
        stdout: StdioCollector {
            onStreamFinished: root.plugins = text.trim().length ? text.trim().split("\n") : []
        }
    }

    // Reading the three groups directly keeps `enabledIds` reactive (a
    // Config.barEnabled() call would hide the dependency and go stale).
    readonly property var enabledIds: Config.barLeading.concat(Config.barCenter).concat(Config.barTrailing)
    function idFor(name) { return "plugin:" + name }
    function setEnabled(name, on) {
        if (on) Config.barEnable(idFor(name), "leading")
        else    Config.barDisable(idFor(name))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Plugins"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: 32; implicitHeight: 32; radius: T.Theme.moduleRadius
                color: rma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt
                Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0450); color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 2 } }
                MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rescan() }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Drop a .qml bar module into " + root.dir + " and enable it here. "
                + "See plugins/README.md for the contract. Reload the shell (ALT+Q) after adding a new file."
            color: T.Theme.inkDim
            wrapMode: Text.WordWrap
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
        }

        Text {
            visible: root.plugins.length === 0
            text: "No plugins found."
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; italic: true }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.plugins
            delegate: Rectangle {
                id: pluginRow
                required property var modelData
                readonly property bool on: root.enabledIds.indexOf(root.idFor(modelData)) !== -1
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: 56
                radius: T.Theme.moduleRadius
                color: on ? T.Theme.surfaceActive : T.Theme.surfaceAlt
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 12
                    Text {
                        text: String.fromCodePoint(0xF0431)   // puzzle
                        color: on ? T.Theme.accent : T.Theme.inkDim
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 5 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData
                            color: T.Theme.ink
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                        }
                        Text {
                            text: "plugin:" + modelData + (on ? "   ·   on the bar" : "")
                            color: T.Theme.inkDim
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                        }
                    }
                    Toggle { on: pluginRow.on; onToggled: function(v){ root.setEnabled(pluginRow.modelData, v) } }
                }
            }
        }
    }
}
