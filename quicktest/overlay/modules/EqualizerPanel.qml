import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── EqualizerPanel ── Apple-style compact audio mixer ─────────────────────────
Item {
    id: root

    implicitWidth:  320
    implicitHeight: col.implicitHeight + 20

    // ── State ─────────────────────────────────────────────────────────────────
    property real masterVol:   100
    property bool masterMuted: false
    property real micVol:      100
    property bool micMuted:    false
    property var  streams:     []
    property var  sinks:       []
    property var  sources:     []

    // ── Icon helpers ──────────────────────────────────────────────────────────
    readonly property var _iconOverrides: ({
        "spotify": "spotify", "spotify (mpris)": "spotify",
        "firefox": "firefox", "mozilla firefox": "firefox",
        "chromium": "chromium", "google-chrome": "google-chrome",
        "discord": "discord", "vesktop": "vesktop", "vencord-desktop": "discord",
        "telegram": "telegram", "telegram desktop": "telegram-desktop",
        "mpv": "mpv", "vlc": "vlc",
        "obs": "com.obsproject.Studio", "obs studio": "com.obsproject.Studio",
        "steam": "steam", "lutris": "lutris"
    })
    readonly property var _badIcons: ([
        "audio-src", "audio-x-generic", "audio-volume-high",
        "audio-volume-medium", "audio-volume-low", "audio-volume-muted",
        "multimedia-volume-control"
    ])

    function resolvedIconPaths(appName, rawIcon) {
        var iconName = _iconOverrides[appName.toLowerCase()] || null
        if (!iconName && rawIcon) {
            var bad = false
            for (var k = 0; k < _badIcons.length; k++) if (rawIcon === _badIcons[k]) { bad = true; break }
            if (!bad && rawIcon.length > 0) iconName = rawIcon
        }
        if (!iconName) return []
        var home = Quickshell.env("HOME")
        // scalable dirs only carry .svg; raster dirs only carry .png
        var paths = []
        var svgDirs = [
            "/usr/share/icons/hicolor/scalable/apps/",
            home + "/.local/share/icons/hicolor/scalable/apps/"
        ]
        var pngDirs = [
            home + "/.local/share/icons/hicolor/48x48/apps/",
            "/usr/share/icons/Papirus/48x48/apps/",
            "/usr/share/icons/Papirus-Dark/48x48/apps/",
            "/usr/share/icons/hicolor/48x48/apps/",
            "/usr/share/pixmaps/"
        ]
        for (var s = 0; s < svgDirs.length; s++)
            paths.push("file://" + svgDirs[s] + iconName + ".svg")
        for (var p = 0; p < pngDirs.length; p++)
            paths.push("file://" + pngDirs[p] + iconName + ".png")
        return paths
    }

    function appGlyph(name) {
        var n = name.toLowerCase()
        if (n.includes("firefox"))                                                   return "󰈹"
        if (n.includes("chrome") || n.includes("chromium"))                          return "󰊯"
        if (n.includes("spotify"))                                                   return "󰓇"
        if (n.includes("mpv"))                                                       return "󰎁"
        if (n.includes("vlc"))                                                       return "󰕼"
        if (n.includes("discord") || n.includes("vesktop") || n.includes("vencord")) return "󰙯"
        if (n.includes("telegram"))                                                  return "󰔁"
        if (n.includes("steam"))                                                     return "󰓓"
        if (n.includes("lutris"))                                                    return "󰊗"
        if (n.includes("obs"))                                                       return "󰐋"
        if (n.includes("zoom") || n.includes("teams"))                               return "󰤅"
        if (n.includes("zen"))                                                       return "󰈹"
        return "󰓃"
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    Component.onCompleted: refresh()
    Timer { interval: 3000; running: true; repeat: true; onTriggered: refresh() }

    function refresh() {
        masterReader.running = false; masterReader.running = true
        micReader.running    = false; micReader.running    = true
        streamReader.running = false; streamReader.running = true
        sinkReader.running   = false; sinkReader.running   = true
        sourceReader.running = false; sourceReader.running = true
    }

    Process {
        id: masterReader
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        running: false; property string _buf: ""
        stdout: SplitParser { onRead: function(d) { masterReader._buf = d.trim() } }
        onRunningChanged: {
            if (!running && _buf !== "") {
                var p = _buf.split(/\s+/)
                root.masterVol   = Math.round((parseFloat(p[1]) || 0) * 100)
                root.masterMuted = _buf.indexOf("[MUTED]") !== -1
                _buf = ""
            }
        }
    }

    Process {
        id: micReader
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@"]
        running: false; property string _buf: ""
        stdout: SplitParser { onRead: function(d) { micReader._buf = d.trim() } }
        onRunningChanged: {
            if (!running && _buf !== "") {
                var p = _buf.split(/\s+/)
                root.micVol   = Math.round((parseFloat(p[1]) || 0) * 100)
                root.micMuted = _buf.indexOf("[MUTED]") !== -1
                _buf = ""
            }
        }
    }

    Process {
        id: streamReader
        command: ["sh", "-c",
            "pactl -f json list sink-inputs 2>/dev/null | python3 -c \"\n" +
            "import sys, json\n" +
            "data = json.load(sys.stdin)\n" +
            "for s in data:\n" +
            "    props = s.get('properties', {})\n" +
            "    name  = (props.get('application.name') or props.get('media.name') or 'Unknown')\n" +
            "    icon  = (props.get('application.icon_name') or '')\n" +
            "    first = next(iter(s.get('volume', {}).values()), {})\n" +
            "    vol   = str(first.get('value_percent','100%')).replace('%','')\n" +
            "    mute  = '1' if s.get('mute', False) else '0'\n" +
            "    print(str(s.get('index','')) + '\\t' + name + '\\t' + icon + '\\t' + vol + '\\t' + mute)\n" +
            "\" 2>/dev/null || true"
        ]
        running: false; property var _rows: []
        stdout: SplitParser {
            onRead: function(d) {
                var t = d.trim(); if (!t) return
                var c = t.split("\t")
                if (c.length >= 5) {
                    var n = c[1]
                    streamReader._rows.push({
                        index: c[0],
                        appName: n.length > 18 ? n.substring(0, 16) + "…" : n,
                        rawIcon: c[2],
                        vol: Math.min(150, parseFloat(c[3]) || 0),
                        muted: c[4].trim() === "1"
                    })
                }
            }
        }
        onRunningChanged: { if (!running) { root.streams = _rows.slice(); _rows = [] } }
    }

    Process {
        id: sinkReader
        command: ["sh", "-c",
            "pactl -f json list sinks 2>/dev/null | python3 -c \"\n" +
            "import sys, json\n" +
            "for s in json.load(sys.stdin):\n" +
            "    print(str(s.get('index','')) + '\\t' + s.get('description', s.get('name','?')))\n" +
            "\" 2>/dev/null || true"
        ]
        running: false; property var _rows: []
        stdout: SplitParser {
            onRead: function(d) {
                var t = d.trim(); if (!t) return
                var c = t.split("\t")
                if (c.length >= 2) sinkReader._rows.push({ id: c[0], name: c.slice(1).join("\t") })
            }
        }
        onRunningChanged: { if (!running) { root.sinks = _rows.slice(); _rows = [] } }
    }

    Process {
        id: sourceReader
        command: ["sh", "-c",
            "pactl -f json list sources 2>/dev/null | python3 -c \"\n" +
            "import sys, json\n" +
            "for s in json.load(sys.stdin):\n" +
            "    if '.monitor' in s.get('name',''): continue\n" +
            "    print(str(s.get('index','')) + '\\t' + s.get('description', s.get('name','?')))\n" +
            "\" 2>/dev/null || true"
        ]
        running: false; property var _rows: []
        stdout: SplitParser {
            onRead: function(d) {
                var t = d.trim(); if (!t) return
                var c = t.split("\t")
                if (c.length >= 2) sourceReader._rows.push({ id: c[0], name: c.slice(1).join("\t") })
            }
        }
        onRunningChanged: { if (!running) { root.sources = _rows.slice(); _rows = [] } }
    }

    // Instant-run (mute toggles, device switch)
    Process {
        id: cmd; running: false
        onRunningChanged: { if (!running) root.refresh() }
    }
    function run(args) { cmd.command = args; cmd.running = false; cmd.running = true }

    // Debounced-run (sliders — fires 120 ms after last move)
    Process {
        id: debCmd; running: false
        onRunningChanged: { if (!running) root.refresh() }
    }
    property var _pending: null
    Timer {
        id: debTimer; interval: 120; repeat: false
        onTriggered: {
            if (root._pending) {
                debCmd.command = root._pending
                debCmd.running = false; debCmd.running = true
                root._pending = null
            }
        }
    }
    function runD(args) { root._pending = args; debTimer.restart() }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: col
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
        spacing: 0

        // ── Header (matching WallpaperPanel) ──────────────────────────────────
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
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.22) }
                    }
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰕾"
                        color: T.Theme.fg
                        font.pixelSize: 18
                        font.family: T.Theme.fontFamily
                    }
                }

                ColumnLayout {
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "Audio"
                            color: T.Theme.fg
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                        Text {
                            text: "Controller"
                            color: T.Theme.color9
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                    }
                    Text {
                        text: root.streams.length + " active streams"
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
                    onClicked: root.refresh()
                }
            }
        }

        // Divider after header
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 10
            height: 1
            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
        }

        // ── Output ────────────────────────────────────────────────────────────
        AudioRow {
            Layout.fillWidth: true
            glyph:  root.masterMuted ? "󰝟" : root.masterVol < 35 ? "󰕿" : root.masterVol < 70 ? "󰖀" : "󰕾"
            label:  "Output"
            vol:    root.masterVol
            muted:  root.masterMuted
            accent: root.masterVol > 100 ? T.Theme.color1 : T.Theme.color4
            onToggleMute: root.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
            onSetVol: function(v) {
                root.masterVol = v
                root.runD(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v + "%"])
            }
        }

        DeviceRow {
            Layout.fillWidth: true; Layout.leftMargin: 28
            visible: root.sinks.length > 1
            devices: root.sinks
            onPick: function(id) { root.run(["pactl", "set-default-sink", id]) }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 6
            height: 1
            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
        }

        // ── Input ─────────────────────────────────────────────────────────────
        AudioRow {
            Layout.fillWidth: true
            glyph:  root.micMuted ? "󰍭" : "󰍬"
            label:  "Input"
            vol:    root.micVol
            muted:  root.micMuted
            accent: root.micVol > 100 ? T.Theme.color1 : T.Theme.color9
            onToggleMute: root.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
            onSetVol: function(v) {
                root.micVol = v
                root.runD(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", v + "%"])
            }
        }

        // ── Input device chips ────────────────────────────────────────────────
        DeviceRow {
            Layout.fillWidth: true; Layout.leftMargin: 28
            visible: root.sources.length > 1
            devices: root.sources
            onPick: function(id) { root.run(["pactl", "set-default-source", id]) }
        }

        // ── App streams ───────────────────────────────────────────────────────
        Repeater {
            model: root.streams
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 6
                    height: 1
                    color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
                }

                AudioRow {
                    Layout.fillWidth: true
                    isApp:    true
                    appName:  modelData.appName
                    rawIcon:  modelData.rawIcon
                    vol:      modelData.vol
                    muted:    modelData.muted
                    // App streams go to 150%, accent shifts orange past 100%
                    maxVol:   150
                    accent:   modelData.muted ? T.Theme.dimFg
                            : (modelData.vol > 100 ? T.Theme.color3 : T.Theme.color9)
                    onToggleMute: root.run(["pactl", "set-sink-input-mute", modelData.index, "toggle"])
                    onSetVol: function(v) {
                        root.runD(["pactl", "set-sink-input-volume",
                                   modelData.index, Math.round(v) + "%"])
                    }
                }
            }
        }
    }

    // ── AudioRow ─────────────────────────────────────────────────────────────
    // One row: [icon/glyph]  [label]  [━━━━━━━━slider━━━━━━━━]  [vol%]
    // Clicking the icon toggles mute. No separate mute button.
    component AudioRow: Item {
        id: row
        height: 34

        // System row props (glyph-based)
        property string glyph:  ""
        property string label:  ""
        // App row props
        property bool   isApp:   false
        property string appName: ""
        property string rawIcon: ""
        // Shared
        property real   vol:     100
        property real   maxVol:  100   // 100 for system, 150 for apps
        property bool   muted:   false
        property color  accent:  T.Theme.color4

        signal toggleMute()
        signal setVol(real v)

        RowLayout {
            anchors.fill: parent
            spacing: 10

            // ── Icon / glyph — click to mute ──────────────────────────────────
            Item {
                width: 18; height: 18
                Layout.alignment: Qt.AlignVCenter

                // App icon loader
                Loader {
                    id: appIconLdr
                    anchors.fill: parent
                    active: row.isApp
                    property var _paths: row.isApp
                        ? root.resolvedIconPaths(row.appName, row.rawIcon) : []
                    sourceComponent: Component {
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            smooth: true; asynchronous: true
                            property int _i: 0
                            source: appIconLdr._paths.length > 0 ? appIconLdr._paths[0] : ""
                            onStatusChanged: {
                                if (status === Image.Error) {
                                    if (_i < appIconLdr._paths.length - 1) {
                                        _i++; source = appIconLdr._paths[_i]
                                    } else {
                                        source = ""  // exhausted — hide silently
                                    }
                                }
                            }
                            visible: status === Image.Ready
                            opacity: row.muted ? 0.30 : 0.85
                            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                        }
                    }
                }

                // Glyph — shown for system rows OR when app icon not found
                Text {
                    anchors.centerIn: parent
                    visible: !row.isApp ||
                             !appIconLdr.active ||
                             (appIconLdr.item && appIconLdr.item.status !== Image.Ready)
                    text: row.isApp ? root.appGlyph(row.appName) : row.glyph
                    color: row.muted ? T.Theme.dimFg : row.accent
                    font.pixelSize: 14; font.family: T.Theme.fontFamily
                    opacity: row.muted ? 0.30 : 1.0
                    Behavior on color   { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: row.toggleMute()
                }
            }

            // ── Label ─────────────────────────────────────────────────────────
            Text {
                text: row.isApp ? row.appName : row.label
                color: T.Theme.fg
                opacity: row.muted ? 0.28 : 0.75
                font.pixelSize: 11; font.family: T.Theme.fontFamily
                font.weight: Font.Medium
                elide: Text.ElideRight
                // Fixed label width so sliders all line up
                Layout.preferredWidth: 62
                Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
            }

            // ── Slider ────────────────────────────────────────────────────────
            AppleSlider {
                Layout.fillWidth: true
                value: row.vol / row.maxVol
                accent: row.accent
                showNotch: row.maxVol > 100
                onMoved: function(v) { row.setVol(Math.round(v * row.maxVol)) }
            }

            // ── Volume % ──────────────────────────────────────────────────────
            Text {
                text: Math.round(row.vol) + "%"
                color: row.muted ? T.Theme.dimFg : row.accent
                opacity: row.muted ? 0.28 : 0.80
                font.pixelSize: 10; font.family: T.Theme.fontFamily
                font.weight: Font.Medium
                Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight
                Behavior on color   { ColorAnimation { duration: T.Theme.animFast } }
                Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
            }
        }
    }

    // ── AppleSlider ───────────────────────────────────────────────────────────
    // Rounded pill track, filled from the left, no floating knob.
    // Track height is chunky enough to grab easily. Clean.
    component AppleSlider: Item {
        id: sl
        height: 14
        property real  value:     0.0
        property color accent:    T.Theme.color4
        property bool  showNotch: false
        signal moved(real v)
        property real _c: Math.max(0, Math.min(1, value))

        Rectangle {
            id: bg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: 2
            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.14)

            // Fill
            Rectangle {
                width: Math.max(bg.radius * 2, bg.width * sl._c)
                height: bg.height; radius: bg.radius
                color: sl.accent; opacity: 0.90
                Behavior on width { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
                Behavior on color { ColorAnimation  { duration: T.Theme.animFast } }
            }

            // 100% notch (only on 150% sliders)
            Rectangle {
                visible: sl.showNotch
                x: bg.width * (100 / 150) - 1
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 7; radius: 1
                color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.38)
            }
        }

        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onPressed:         function(m) { sl.moved(Math.max(0, Math.min(1, m.x / bg.width))) }
            onPositionChanged: function(m) { if (pressed) sl.moved(Math.max(0, Math.min(1, m.x / bg.width))) }
        }
    }

    // ── DeviceRow ─────────────────────────────────────────────────────────────
    // Tiny chips for switching output/input device. Hidden when only one exists.
    component DeviceRow: Item {
        id: drow
        height: visible ? 20 : 0
        property var    devices: []
        property string activeId: ""
        signal pick(string id)

        Flickable {
            anchors.fill: parent
            contentWidth: chips.implicitWidth
            clip: true; flickableDirection: Flickable.HorizontalFlick

            Row {
                id: chips; spacing: 4
                Repeater {
                    model: drow.devices
                    delegate: Rectangle {
                        id: chip
                        height: 18
                        width: cl.implicitWidth + 12; radius: 9
                        property bool on: drow.activeId !== "" ? drow.activeId === modelData.id : index === 0
                        color: on
                            ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.18)
                            : (ch.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.09) : "transparent")
                        border.color: on
                            ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.38)
                            : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.08)
                        border.width: 1
                        Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                        Text {
                            id: cl; anchors.centerIn: parent
                            text: modelData.name.length > 24 ? modelData.name.substring(0, 22) + "…" : modelData.name
                            color: chip.on ? T.Theme.color4 : T.Theme.fg
                            opacity: chip.on ? 0.90 : 0.40
                            font.pixelSize: 9; font.family: T.Theme.fontFamily
                            font.weight: chip.on ? Font.Medium : Font.Normal
                            Behavior on color   { ColorAnimation { duration: T.Theme.animFast } }
                            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                        }
                        MouseArea {
                            id: ch; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { drow.activeId = modelData.id; drow.pick(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
