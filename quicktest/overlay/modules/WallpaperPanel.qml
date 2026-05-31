import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

Item {
    id: root

    implicitWidth:  535
    implicitHeight: 340

    property bool listView: false

    // Reactive filtered list
    readonly property var filteredWallpapers: {
        var walls = wallpaperList.wallpapers
        var s = searchInput.text.toLowerCase()
        return s.length > 0
            ? walls.filter(w => w.toLowerCase().includes(s))
            : walls
    }

    // ── Wallpaper list ────────────────────────────────────────────────────────
    Process {
        id: wallpaperList
        command: ["sh", "-c",
            "find " + Quickshell.env("HOME") + "/wallpapers/walls " +
            "-type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \\) | sort"
        ]
        running: true

        property var wallpapers: []
        property var _buf: []

        stdout: SplitParser {
            onRead: function(data) {
                var trimmed = data.trim()
                if (trimmed) {
                    wallpaperList._buf.push(trimmed)
                }
            }
        }

        onRunningChanged: function() {
            if (!running && _buf.length > 0) {
                wallpapers = _buf.slice()
                _buf = []
            }
        }
    }

    // ── Notification process ──────────────────────────────────────────────────
    Process {
        id: notifyProcess
        running: false
    }

    // ── Wallpaper applier ─────────────────────────────────────────────────────
    Process {
        id: wallpaperApplier
        running: false

        property string selectedPath: ""

        command: ["sh", "-c",
            "LOG=/tmp/wallpaper.log && " +
            "echo '' >> $LOG && " +
            "echo '=== ' $(date) ' ===' >> $LOG && " +
            "echo '[RUN] awww' >> $LOG && " +
            "awww img '" + selectedPath + "' --transition-type right --transition-fps 144 --transition-duration 0.5 >> $LOG 2>&1 && " +
            "echo '[RUN] wal' >> $LOG && " +
            "wal -i '" + selectedPath + "' -n >> $LOG 2>&1 || true && " +
            "echo '[RUN] hyprland-wal' >> $LOG && " +
            "bash \"$HOME/.config/hypr/scripts/wal-reload.sh\" >> $LOG 2>&1 && " +
            "echo '[RUN] swaync' >> $LOG && " +
            "swaync-client --reload-css >> $LOG 2>&1 || true && " +
            "wal -i '" + selectedPath + "' -n >> $LOG 2>&1 || true && " +
            "echo '[RUN] hyprland-wal' >> $LOG && " +
            "echo '[RUN] pwspice' >> $LOG && " +
            "python3 \"$HOME/.config/spicetify/pwspice.py\" >> $LOG 2>&1 && " +
            "echo '[RUN] kitty' >> $LOG && " +
            "cat \"$HOME/.cache/wal/colors-kitty.conf\" > \"$HOME/.config/kitty/current-theme.conf\" && " +
            "killall -USR1 kitty 2>/dev/null || true && " +
            "echo '[RUN] pywalfox' >> $LOG && " +
            "pywalfox update >> $LOG 2>&1 && sleep 0.3 && pywalfox update >> $LOG 2>&1 || true && " +
            "echo '[RUN] discord-vencord' >> $LOG && " +
            "python3 \"$HOME/.config/Vencord/pywal-midnight.py\" >> $LOG 2>&1 || true && " +
            "echo '[RUN] discord-vesktop' >> $LOG && " +
            "python3 \"$HOME/.config/vesktop/pywal-midnight.py\" >> $LOG 2>&1 || true && " +
            "color1=$(awk 'match($0, /color2=\\47(.*)\\47/,a) { print a[1] }' \"$HOME/.cache/wal/colors.sh\") && " +
            "color2=$(awk 'match($0, /color3=\\47(.*)\\47/,a) { print a[1] }' \"$HOME/.cache/wal/colors.sh\") && " +
            "echo \"[INFO] cava colors: $color1 $color2\" >> $LOG && " +
            "sed -i \"s/^gradient_color_1 = .*/gradient_color_1 = '$color1'/\" \"$HOME/.config/cava/config\" && " +
            "sed -i \"s/^gradient_color_2 = .*/gradient_color_2 = '$color2'/\" \"$HOME/.config/cava/config\" && " +
            "pkill -USR2 cava 2>/dev/null || true && " +
            "cp '" + selectedPath + "' \"$HOME/wallpapers/pywallpaper.jpg\" && " +
            "echo \"[RUN] fastfetch-profile\" >> $LOG && " +
            "basename \"" + selectedPath + "\" > \"$HOME/.cache/current_wallpaper_name\" && " +
            "pkill -USR1 kitty >/dev/null 2>&1; pkill -USR1 alacritty >/dev/null 2>&1; clear >/dev/null 2>&1 && " +
            "echo '[RUN] dunst-wal' >> $LOG && " +
            "~/.config/quicktest/scripts/dunst-wal.sh >> $LOG 2>&1 && " +
            "echo '[DONE]' >> $LOG"
        ]

        onExited: function(code) {
            var fileName = selectedPath.split("/").pop()
            notifyProcess.command = code === 0
                ? ["notify-send", "--app-name=Wallpaper", "--urgency=low", "--icon=" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/Palette.svg", "Wallpaper applied!", "Wallpaper \"" + fileName + "\" and colors updated"]
                : ["notify-send", "--app-name=Wallpaper", "--urgency=critical", "--icon=dialog-error", "Wallpaper failed", "Could not apply: " + fileName]
            notifyProcess.running = false
            notifyProcess.running = true
        }
    }

    function applyWallpaper(path) {
        wallpaperApplier.selectedPath = path
        wallpaperApplier.running = false
        wallpaperApplier.running = true
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (searchInput.activeFocus) searchInput.focus = false
            mouse.accepted = false
        }
    }

    // ── Content ───────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 34
                    height: 34
                    radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.25) }
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color2, 0.20) }
                    }
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                    border.width: 1

                    Image {
                        anchors.centerIn: parent
                        source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/wallpaper.svg"
                        width: 18
                        height: 18
                        fillMode: Image.PreserveAspectFit
                    }
                }

                ColumnLayout {
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "Wallpaper"
                            color: T.Theme.fg
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                        Text {
                            text: "Gallery"
                            color: T.Theme.color9
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                    }
                    Text {
                        text: wallpaperList.wallpapers.length + " wallpapers found!"
                        color: T.Theme.fg
                        opacity: 0.5
                        font.pixelSize: 10
                        font.family: T.Theme.fontFamily
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Refresh button
            Rectangle {
                width: 30
                height: 30
                radius: 8
                color: refreshHov.containsMouse
                    ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.20)
                    : T.Theme.pillBg

                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: T.Theme.fg
                    font.pixelSize: 14
                    font.family: T.Theme.fontFamily
                }
                MouseArea {
                    id: refreshHov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        wallpaperList._buf = []
                        wallpaperList.wallpapers = []
                        wallpaperList.running = false
                        wallpaperList.running = true
                    }
                }
            }

            // Grid / List toggle
            Rectangle {
                width: 64
                height: 30
                radius: 8
                color: T.Theme.pillBg

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        radius: 6
                        color: !root.listView ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                        Image {
                            anchors.centerIn: parent
                            source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/cozy.svg"
                            width: 18
                            height: 18
                            fillMode: Image.PreserveAspectFit
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.listView = false
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        radius: 6
                        color: root.listView ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                        Image {
                            anchors.centerIn: parent
                            source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/list.svg"
                            width: 18
                            height: 18
                            fillMode: Image.PreserveAspectFit
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.listView = true
                        }
                    }
                }
            }
        }

        // Search bar
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 10
            color: T.Theme.pillBg
            border.color: searchInput.activeFocus
                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.45)
                : "transparent"
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Text {
                    text: "󰍉"
                    color: T.Theme.fg
                    opacity: 0.45
                    font.pixelSize: 14
                    font.family: T.Theme.fontFamily
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: T.Theme.fg
                    font.pixelSize: 12
                    font.family: T.Theme.fontFamily
                    cursorVisible: activeFocus

                    Keys.onEscapePressed: {
                        text = ""
                        focus = false
                    }

                    Text {
                        anchors.fill: parent
                        text: "Search wallpapers…"
                        color: T.Theme.fg
                        opacity: 0.28
                        font.pixelSize: 12
                        font.family: T.Theme.fontFamily
                        verticalAlignment: Text.AlignVCenter
                        visible: !searchInput.activeFocus && searchInput.text.length === 0
                    }
                }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: clearHov.containsMouse
                        ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25)
                        : "transparent"
                    visible: searchInput.text.length > 0
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: T.Theme.fg
                        opacity: 0.50
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        font.family: T.Theme.fontFamily
                    }
                    MouseArea {
                        id: clearHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }

        // Grid view
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.listView

            GridView {
                id: wallpaperGrid
                anchors.fill: parent
                anchors.rightMargin: 8
                clip: true
                cellWidth: 164
                cellHeight: 115
                model: root.filteredWallpapers
                cacheBuffer: 500
                maximumFlickVelocity: 2500
                flickDeceleration: 1500

                delegate: Item {
                    width: wallpaperGrid.cellWidth
                    height: wallpaperGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        color: T.Theme.pillBg
                        radius: 12
                        clip: true
                        border.color: hoverArea.containsMouse ? T.Theme.color9 : "transparent"
                        border.width: hoverArea.containsMouse ? 2 : 0
                        scale: hoverArea.pressed ? 0.95 : (hoverArea.containsMouse ? 1.04 : 1.0)

                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                        Behavior on border.width { NumberAnimation { duration: T.Theme.animFast } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Qt.rgba(T.Theme.bg.r, T.Theme.bg.g, T.Theme.bg.b, 0.5)
                                radius: 8
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 300
                                    sourceSize.height: 200

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: T.Theme.pillBg
                                        visible: parent.status === Image.Loading
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰔟"
                                            color: T.Theme.fg
                                            opacity: 0.5
                                            font.pixelSize: 18
                                            font.family: T.Theme.fontFamily
                                            RotationAnimation on rotation {
                                                loops: Animation.Infinite
                                                from: 0
                                                to: 360
                                                duration: 1000
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    opacity: hoverArea.containsMouse ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0.28) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.58) }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 56
                                        height: 24
                                        radius: 12
                                        color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.90)
                                        scale: hoverArea.containsMouse ? 1.0 : 0.82
                                        opacity: hoverArea.containsMouse ? 1.0 : 0.0
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Apply"
                                            color: T.Theme.bg
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            font.family: T.Theme.fontFamily
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                text: modelData.split("/").pop()
                                color: T.Theme.fg
                                opacity: 0.65
                                font.pixelSize: 10
                                font.family: T.Theme.fontFamily
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: hoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyWallpaper(modelData)
                        }
                    }
                }
            }
        }

        // List view
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.listView

            ListView {
                id: wallpaperListView
                anchors.fill: parent
                anchors.rightMargin: 8
                spacing: 8
                clip: true
                cacheBuffer: 300
                model: root.filteredWallpapers

                delegate: Rectangle {
                    width: wallpaperListView.width
                    height: 80
                    radius: 10
                    color: listHover.containsMouse
                        ? Qt.rgba(T.Theme.pillBg.r, T.Theme.pillBg.g, T.Theme.pillBg.b, T.Theme.pillBg.a * 2)
                        : T.Theme.pillBg
                    border.color: listHover.containsMouse
                        ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.40)
                        : "transparent"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 100
                            Layout.fillHeight: true
                            color: Qt.rgba(T.Theme.bg.r, T.Theme.bg.g, T.Theme.bg.b, 0.5)
                            radius: 8
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                sourceSize.width: 150
                                sourceSize.height: 100
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: modelData.split("/").pop()
                                color: T.Theme.fg
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                font.family: T.Theme.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                color: T.Theme.fg
                                opacity: 0.45
                                font.pixelSize: 10
                                font.family: T.Theme.fontFamily
                                elide: Text.ElideMiddle
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 70
                            Layout.preferredHeight: 32
                            radius: 8
                            color: listHover.containsMouse
                                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                                : T.Theme.pw(T.Theme.pal?.colors?.color9, 0.15)
                            Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                            Text {
                                anchors.centerIn: parent
                                text: "Apply"
                                color: T.Theme.fg
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                font.family: T.Theme.fontFamily
                            }
                        }
                    }

                    MouseArea {
                        id: listHover
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.applyWallpaper(modelData)
                    }
                }
            }
        }
    }
}