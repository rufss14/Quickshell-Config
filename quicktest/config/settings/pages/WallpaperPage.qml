import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T

// Wallpaper — browse ~/wallpapers/walls as thumbnails; clicking one sets it
// (awww) and regenerates the pywal palette (scripts/apply-wallpaper.sh), which
// recolors the whole shell live via theming/PywalColors.qml's file watch.
Item {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/wallpapers/walls"
    property var wallpapers: []
    property string currentName: ""
    property string applying: ""

    Component.onCompleted: { listProc.running = true; curProc.running = true }

    Process {
        id: listProc
        command: ["bash", "-c",
            "find '" + root.dir + "' -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
          + "-o -iname '*.gif' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: root.wallpapers = text.trim().length ? text.trim().split("\n") : []
        }
    }
    Process {
        id: curProc
        command: ["cat", Quickshell.env("HOME") + "/.cache/current_wallpaper_name"]
        stdout: StdioCollector { onStreamFinished: root.currentName = text.trim() }
    }
    Process {
        id: applyProc
        onExited: { root.applying = ""; curProc.running = false; curProc.running = true }
    }
    function apply(path) {
        if (root.applying.length) return
        root.applying = path
        applyProc.command = ["bash", Quickshell.env("HOME") + "/.config/quicktest/scripts/apply-wallpaper.sh", path]
        applyProc.running = true
    }
    function baseName(p) { return p.split("/").pop() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Wallpaper"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.applying.length > 0
                text: "Applying & recoloring…"
                color: T.Theme.accent
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
            }
        }

        Text {
            visible: root.wallpapers.length === 0
            text: "No images found in " + root.dir
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; italic: true }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.wallpapers.length > 0
            clip: true
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 170)))
            cellHeight: 130
            model: root.wallpapers

            delegate: Item {
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                readonly property bool isCurrent: root.baseName(modelData) === root.currentName
                readonly property bool isApplying: root.applying === modelData

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: T.Theme.moduleRadius
                    color: T.Theme.surfaceAlt
                    clip: true
                    border.width: isCurrent ? 2 : 0
                    border.color: T.Theme.accent

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: "file://" + modelData
                        sourceSize.width: 320
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    // Filename + current badge overlay.
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 22
                        color: T.Theme.background
                        Text {
                            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            text: (isCurrent ? "● " : "") + root.baseName(modelData)
                            color: isCurrent ? T.Theme.accent : T.Theme.ink
                            elide: Text.ElideRight
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                        }
                    }

                    // Applying overlay.
                    Rectangle {
                        anchors.fill: parent
                        visible: isApplying
                        color: T.Theme.background
                        opacity: 0.75
                        Text {
                            anchors.centerIn: parent
                            text: "…"
                            color: T.Theme.accent
                            font { family: T.Theme.fontFamily; pixelSize: 28; bold: true }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.apply(modelData)
                    }
                }
            }
        }
    }
}
