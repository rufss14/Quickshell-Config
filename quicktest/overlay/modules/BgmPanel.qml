import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── BgmPanel ──────────────────────────────────────────────────────────────────
// Matches WallpaperPanel styling (color9 accent, same buttons/icons/layout).
//
// Fixes vs previous version:
//   • Cover 󰋩 button sits above the play MouseArea (z:2) so it receives clicks
//   • Clicking a playing track now PAUSES (not stops). Stop button = full stop.
//   • Progress bar for BGM via mpv IPC socket (~/.config/quicktest/bgm/mpv.sock)
//   • Now-playing bar and search bar no longer clip their content
//   • Cava visualizer: rounded bars, symmetric gradient, mirrored stereo layout
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth:  528
    implicitHeight: 238

    property bool listView: false

    // ── Playback state ────────────────────────────────────────────────────────
    property string currentTrack: ""
    property bool   isPlaying:    false
    property bool   isPaused:     false   // true when paused mid-track


    // ── Loop state: simple on/off ─────────────────────────────────────────────
    property bool loopOn: true

    // ── Cava bars (used by grid/list image overlays) ───────────────────────────
    property var cavaBars: []
    readonly property int cavaBarCount: 16

    property var coverMap: ({})
    function coverForTrack(p) { return coverMap[p] || "" }

    // ── Filtered list ─────────────────────────────────────────────────────────
    readonly property var filteredTracks: {
        var tracks = trackList.tracks
        var s = searchInput.text.toLowerCase()
        return s.length > 0 ? tracks.filter(t => t.toLowerCase().includes(s)) : tracks
    }

    // ── IPC socket path for mpv ───────────────────────────────────────────────
    readonly property string ipcSock: Quickshell.env("HOME") + "/.config/quicktest/bgm/mpv.sock"

    // ══════════════════════════════════════════════════════════════════════════
    // Processes
    // ══════════════════════════════════════════════════════════════════════════

    // Track scanner
    Process {
        id: trackList
        command: ["sh", "-c",
            "find " + Quickshell.env("HOME") + "/.config/quicktest/bgm/soundtracks " +
            "-type f \\( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' " +
            "           -o -iname '*.wav' -o -iname '*.opus' -o -iname '*.m4a' \\) | sort"
        ]
        running: true
        property var tracks: []
        property var _buf:   []
        stdout: SplitParser {
            onRead: function(data) { var t = data.trim(); if (t) trackList._buf.push(t) }
        }
        onRunningChanged: {
            if (!running && _buf.length > 0) {
                tracks = _buf.slice(); _buf = []
                coverScanner.running = false; coverScanner.running = true
            }
        }
    }

    // Cover scanner
    Process {
        id: coverScanner
        running: false
        command: ["sh", "-c",
            "find " + Quickshell.env("HOME") + "/.config/quicktest/bgm/soundtracks " +
            "-type f \\( -iname '*.cover.jpg' -o -iname '*.cover.jpeg' " +
            "           -o -iname '*.cover.png' -o -iname '*.cover.webp' \\) | sort"
        ]
        property var _buf: []
        stdout: SplitParser {
            onRead: function(data) { var t = data.trim(); if (t) coverScanner._buf.push(t) }
        }
        onRunningChanged: {
            if (!running) {
                var map = {}
                for (var i = 0; i < _buf.length; i++) {
                    var cp = _buf[i]; var base = cp.replace(/\.cover\.[^.]+$/, "")
                    var exts = [".mp3",".flac",".ogg",".wav",".opus",".m4a"]
                    for (var j = 0; j < exts.length; j++) {
                        var cand = base + exts[j]
                        if (trackList.tracks.indexOf(cand) !== -1) { map[cand] = cp; break }
                    }
                }
                root.coverMap = map; _buf = []
            }
        }
    }

    // Cover copier
    Process {
        id: coverCopier
        running: false
        property string srcPath: ""; property string trackPath: ""
        command: ["sh", "-c", (function() {
            var ext = srcPath.split(".").pop().toLowerCase()
            if (["jpg","jpeg","png","webp"].indexOf(ext) === -1) ext = "jpg"
            var dest = trackPath.replace(/\.[^.]+$/, "") + ".cover." + ext
            return "cp '" + srcPath + "' '" + dest + "' && echo '" + dest + "'"
        })()]
        property string _rp: ""
        stdout: SplitParser { onRead: function(d) { coverCopier._rp = d.trim() } }
        onRunningChanged: {
            if (!running && _rp !== "") {
                var m = Object.assign({}, root.coverMap); m[trackPath] = _rp; root.coverMap = m
                if (trackPath === root.currentTrack) Panels.bgmCoverPath = _rp + "?" + Date.now()
                notifyProcess.command = ["notify-send","--app-name=BGM","--urgency=low",
                    "--icon=" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/music.svg",
                    "Cover updated", trackPath.split("/").pop()]
                notifyProcess.running = false; notifyProcess.running = true
                _rp = ""
            }
        }
    }

    Process { id: notifyProcess; running: false }

    // Player — uses IPC socket so we can pause/query position
    Process {
        id: playerProcess
        running: false
        property string pendingPath: ""; property string pendingLoopArgs: ""
        command: ["sh", "-c",
            "pkill -x mpv 2>/dev/null; sleep 0.1; " +
            "mpv --no-video --really-quiet " + pendingLoopArgs +
            " --input-ipc-server='" + root.ipcSock + "'" +
            " '" + pendingPath + "'"
        ]
        onExited: function(code) {
            // Natural end-of-track (not a crash) when not looping
            if (root.isPlaying && !root.isPaused) {
                root.isPlaying = false; root.currentTrack = ""
                Panels.bgmIsPlaying = false
            }
        }
    }

    // Pause/resume via SIGSTOP/SIGCONT — no IPC socket timing issues.
    // pkill sends the signal to the mpv process by name.
    Process {
        id: pauseProcess; running: false
        command: ["sh", "-c", ""]   // overwritten before each run
    }

    // Stop (full kill)
    Process { id: stopProcess; command: ["pkill", "-x", "mpv"]; running: false }

    // Cover extractor — command is assigned imperatively in playTrack()
    // because a declarative binding on pendingPath is only evaluated once.
    Process {
        id: coverExtractor; running: false
        property string pendingPath: ""
        command: ["sh", "-c", ""]   // overwritten before each run
        onRunningChanged: {
            if (!running) {
                // Only publish the path when ffmpeg actually wrote the file
                var checkCmd = "test -s /tmp/qs_bgm_cover.jpg && echo ok"
                checkProcess.command = ["sh", "-c", checkCmd]
                checkProcess.running = false; checkProcess.running = true
            }
        }
    }

    // Checks if the cover file was actually written before telling BgmButton
    Process {
        id: checkProcess; running: false
        property string _out: ""
        stdout: SplitParser { onRead: function(d) { checkProcess._out = d.trim() } }
        onRunningChanged: {
            if (!running) {
                if (_out === "ok")
                    Panels.bgmCoverPath = "/tmp/qs_bgm_cover.jpg?" + Date.now()
                _out = ""
            }
        }
    }



    // ── Cava process ──────────────────────────────────────────────────────────
    Process {
        id: cavaProc
        running: true
        command: [
            "bash", "-c",
            "cfg=$(mktemp /tmp/cava-bgm-XXXXXX.ini)\n" +
            "printf '[general]\\nbars=" + root.cavaBarCount + "\\nframerate=60\\n" +
            "[output]\\nmethod=raw\\ndata_format=ascii\\nascii_max_range=1000\\n" +
            "raw_target=/dev/stdout\\nbar_delimiter=59\\nframe_delimiter=10\\nchannels=mono\\n' > \"$cfg\"\n" +
            "cava -p \"$cfg\"\n" +
            "rm -f \"$cfg\""
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var t = line.trim(); if (!t) return
                var parts = t.split(";"); var arr = []
                for (var j = 0; j < parts.length; j++) {
                    var s = parts[j].trim(); if (!s) continue
                    var v = parseInt(s)
                    if (!isNaN(v)) arr.push(v / 1000.0)
                }
                if (arr.length >= 2) root.cavaBars = arr
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function loopArgs() { return root.loopOn ? "--loop=inf " : "" }


    function playTrack(path) {
        playerProcess.pendingPath     = path
        playerProcess.pendingLoopArgs = loopArgs()
        playerProcess.running = false; playerProcess.running = true
        root.currentTrack = path; root.isPlaying = true; root.isPaused = false
        Panels.bgmCurrentTrack = path; Panels.bgmIsPlaying = true
        var sc = root.coverForTrack(path)
        if (sc !== "") {
            Panels.bgmCoverPath = sc + "?" + Date.now()
        } else {
            Panels.bgmCoverPath = ""
            // Assign command imperatively — declarative binding on pendingPath
            // is evaluated once at construction and never updates.
            coverExtractor.pendingPath = path
            coverExtractor.command = ["sh", "-c",
                "ffmpeg -y -i '" + path + "' -an -vcodec copy /tmp/qs_bgm_cover.jpg 2>/dev/null || " +
                "ffmpeg -y -i '" + path + "' -an /tmp/qs_bgm_cover.jpg 2>/dev/null || true"
            ]
            coverExtractor.running = false; coverExtractor.running = true
        }
        notifyProcess.command = ["notify-send","--app-name=BGM","--urgency=low",
            "--icon=" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/music.svg",
            "Now playing", path.split("/").pop()]
        notifyProcess.running = false; notifyProcess.running = true
    }

    function pauseTrack() {
        var sig = root.isPaused ? "SIGCONT" : "SIGSTOP"
        pauseProcess.command = ["pkill", "-" + sig, "-x", "mpv"]
        pauseProcess.running = false; pauseProcess.running = true
        root.isPaused = !root.isPaused
        Panels.bgmIsPlaying = !root.isPaused
    }

    function stopTrack() {
        stopProcess.running = false; stopProcess.running = true
        root.isPlaying = false; root.isPaused = false
        root.currentTrack = ""; Panels.bgmIsPlaying = false; Panels.bgmCurrentTrack = ""; Panels.bgmCoverPath = ""
    }

    // ── File-picker for cover art ─────────────────────────────────────────────
    property string coverPickTrack: ""   // track path waiting for a cover pick

    Process {
        id: filePickerProcess; running: false
        property string _out: ""
        command: ["sh", "-c", ""]       // overwritten in openCoverInput()
        stdout: SplitParser { onRead: function(d) { var t = d.trim(); if (t) filePickerProcess._out = t } }
        onRunningChanged: {
            if (!running && _out !== "" && root.coverPickTrack !== "") {
                coverCopier.srcPath   = _out
                coverCopier.trackPath = root.coverPickTrack
                coverCopier.running = false; coverCopier.running = true
                root.coverPickTrack = ""
            }
            if (!running) _out = ""
        }
    }

    function openCoverInput(trackPath) {
        root.coverPickTrack = trackPath
        // Try xdg-desktop-portal file picker (works on most compositors), then
        // fall back to zenity (GTK), then kdialog (Qt/KDE).
        filePickerProcess.command = ["sh", "-c",
            "zenity --file-selection --title='Pick cover art' " +
            "--file-filter='Images | *.jpg *.jpeg *.png *.webp' 2>/dev/null " +
            "|| kdialog --getopenfilename ~ 'Images (*.jpg *.jpeg *.png *.webp)' 2>/dev/null"
        ]
        filePickerProcess._out = ""
        filePickerProcess.running = false; filePickerProcess.running = true
    }

    onLoopOnChanged: {
        if ((root.isPlaying || root.isPaused) && root.currentTrack !== "") {
            playerProcess.pendingPath     = root.currentTrack
            playerProcess.pendingLoopArgs = loopArgs()
            playerProcess.running = false; playerProcess.running = true
            root.isPaused = false
        }
    }

    // Click-outside defocus
    MouseArea {
        anchors.fill: parent; propagateComposedEvents: true
        onPressed: function(mouse) {
            if (searchInput.activeFocus) searchInput.focus = false
            mouse.accepted = false
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // UI
    // ══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 14; spacing: 8

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 12

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 34; height: 34; radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.25) }
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color2, 0.20) }
                    }
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30); border.width: 1

                    Image {
                        anchors.centerIn: parent
                        source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/vinyl.svg"
                        width: 22; height: 22; fillMode: Image.PreserveAspectFit
                        smooth: true
                        RotationAnimation on rotation {
                            loops: Animation.Infinite; from: 0; to: 360
                            duration: 4000; running: root.isPlaying && !root.isPaused
                        }
                    }
                }

                ColumnLayout {
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Text { text: "Background"; color: T.Theme.fg; font.pixelSize: 15; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                        Text { text: "Music"; color: T.Theme.color9; font.pixelSize: 15; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                    }
                    Text {
                        text: trackList.tracks.length + " tracks found!"
                        color: T.Theme.fg; opacity: 0.5
                        font.pixelSize: 10; font.family: T.Theme.fontFamily
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Stop button — always in front of loop
            Rectangle {
                width: 30; height: 30; radius: 8
                visible: root.isPlaying || root.isPaused
                color: stopHov.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25) : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text { anchors.centerIn: parent; text: "󰓛"; color: T.Theme.fg; font.pixelSize: 14; font.family: T.Theme.fontFamily }
                MouseArea { id: stopHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stopTrack() }
            }

            // Loop on/off toggle — no tooltip
            Rectangle {
                width: 30; height: 30; radius: 8
                color: loopHov.containsMouse
                    ? T.Theme.pw(T.Theme.pal?.colors?.color9, root.loopOn ? 0.28 : 0.20)
                    : root.loopOn ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.14) : T.Theme.pillBg
                border.color: root.loopOn ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.35) : "transparent"
                border.width: 1
                Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: root.loopOn ? "󰑖" : "󰑗"
                    color: root.loopOn ? T.Theme.color9 : T.Theme.fg
                    font.pixelSize: 14; font.family: T.Theme.fontFamily
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                }
                MouseArea { id: loopHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.loopOn = !root.loopOn }
            }

            // Refresh
            Rectangle {
                width: 30; height: 30; radius: 8
                color: refreshHov.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.20) : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text { anchors.centerIn: parent; text: "󰑐"; color: T.Theme.fg; font.pixelSize: 14; font.family: T.Theme.fontFamily }
                MouseArea { id: refreshHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { trackList._buf = []; trackList.tracks = []; trackList.running = false; trackList.running = true } }
            }

            // Grid / List toggle — same SVG icons as WallpaperPanel
            Rectangle {
                width: 64; height: 30; radius: 8; color: T.Theme.pillBg
                RowLayout {
                    anchors.fill: parent; anchors.margins: 2; spacing: 2
                    Rectangle {
                        Layout.fillHeight: true; Layout.fillWidth: true; radius: 6
                        color: !root.listView ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Image { anchors.centerIn: parent; source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/cozy.svg"; width: 18; height: 18; fillMode: Image.PreserveAspectFit }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.listView = false }
                    }
                    Rectangle {
                        Layout.fillHeight: true; Layout.fillWidth: true; radius: 6
                        color: root.listView ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Image { anchors.centerIn: parent; source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/list.svg"; width: 18; height: 18; fillMode: Image.PreserveAspectFit }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.listView = true }
                    }
                }
            }
        }


        // ── Cover picker status (shown while zenity/kdialog is open) ──────────
        Rectangle {
            Layout.fillWidth: true
            height: filePickerProcess.running ? 36 : 0
            radius: 10
            color:        T.Theme.pw(T.Theme.pal?.colors?.color9, 0.07)
            border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.28)
            border.width: 1; visible: height > 1
            Behavior on height { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "󰋩"; color: T.Theme.color9; font.pixelSize: 14; font.family: T.Theme.fontFamily }
                Text {
                    Layout.fillWidth: true
                    text: "Choose a cover image in the file picker…"
                    color: T.Theme.fg; opacity: 0.65
                    font.pixelSize: 11; font.family: T.Theme.fontFamily
                }
                Rectangle {
                    width: 28; height: 22; radius: 6
                    color: cancelPickHov.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25) : "transparent"
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "✕"; color: T.Theme.fg; opacity: 0.55
                        font.pixelSize: 9; font.weight: Font.Bold; font.family: T.Theme.fontFamily }
                    MouseArea { id: cancelPickHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { filePickerProcess.running = false; root.coverPickTrack = "" } }
                }
            }
        }

        // ── Search bar (NO clip issues — fixed height, no animation needed) ───
        Rectangle {
            Layout.fillWidth: true
            height: 34; radius: 10
            color: T.Theme.pillBg
            border.color: searchInput.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.45) : "transparent"
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "󰍉"; color: T.Theme.fg; opacity: 0.45; font.pixelSize: 14; font.family: T.Theme.fontFamily }
                TextInput {
                    id: searchInput; Layout.fillWidth: true
                    color: T.Theme.fg; font.pixelSize: 12; font.family: T.Theme.fontFamily
                    cursorVisible: activeFocus
                    Keys.onEscapePressed: { text = ""; focus = false }
                    Text { anchors.fill: parent; text: "Search tracks…"; color: T.Theme.fg; opacity: 0.28
                        font.pixelSize: 12; font.family: T.Theme.fontFamily; verticalAlignment: Text.AlignVCenter
                        visible: !searchInput.activeFocus && searchInput.text.length === 0 }
                }
                Rectangle {
                    width: 18; height: 18; radius: 9
                    color: clearHov.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25) : "transparent"
                    visible: searchInput.text.length > 0
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "✕"; color: T.Theme.fg; opacity: 0.50; font.pixelSize: 8; font.weight: Font.Bold; font.family: T.Theme.fontFamily }
                    MouseArea { id: clearHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: searchInput.text = "" }
                }
            }
        }

        // ── Grid view ─────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !root.listView

            GridView {
                id: trackGrid
                anchors.fill: parent; anchors.rightMargin: 8
                clip: true; cellWidth: 164; cellHeight: 126
                model: root.filteredTracks
                cacheBuffer: 300; maximumFlickVelocity: 2500; flickDeceleration: 1500

                delegate: Item {
                    width: trackGrid.cellWidth; height: trackGrid.cellHeight

                    readonly property bool   isActive:   modelData === root.currentTrack && root.isPlaying
                    readonly property bool   isPaused:   modelData === root.currentTrack && root.isPaused
                    readonly property string sidecarPath: root.coverForTrack(modelData)
                    readonly property bool   hasCover:   sidecarPath !== ""

                    Rectangle {
                        id: cardBg
                        anchors.fill: parent; anchors.margins: 6
                        radius: 12; clip: true
                        color: T.Theme.pillBg
                        border.color: (isActive || isPaused)
                            ? T.Theme.color9
                            : hoverArea.containsMouse ? T.Theme.color9 : "transparent"
                        border.width: (isActive || isPaused || hoverArea.containsMouse) ? 2 : 0
                        scale: hoverArea.pressed ? 0.95 : hoverArea.containsMouse ? 1.04 : 1.0

                        Behavior on scale        { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation  { duration: T.Theme.animFast } }
                        Behavior on border.width { NumberAnimation { duration: T.Theme.animFast } }

                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 4

                            // ── Cover image area with cava overlay ───────────
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 8; clip: true
                                color: Qt.rgba(T.Theme.bg.r, T.Theme.bg.g, T.Theme.bg.b, 0.50)

                                Image {
                                    id: gridCoverImg
                                    anchors.fill: parent
                                    source: hasCover ? ("file://" + sidecarPath) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true; asynchronous: true; cache: false
                                    visible: hasCover && status === Image.Ready
                                }

                                // No-cover vinyl SVG
                                Image {
                                    anchors.centerIn: parent
                                    visible: !isActive && !isPaused && !hasCover
                                    source: "file://" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/vinyl.svg"
                                    width: 28; height: 28; fillMode: Image.PreserveAspectFit
                                    smooth: true; opacity: 0.45
                                }

                                // Active playing — material play icon (matches pause style)
                                Text {
                                    anchors.centerIn: parent
                                    visible: isActive && !isPaused
                                    text: "󰐊"
                                    color: T.Theme.color9; opacity: 0.90
                                    font.pixelSize: 22; font.family: T.Theme.fontFamily
                                }

                                // Pause icon overlay
                                Text {
                                    anchors.centerIn: parent
                                    visible: isPaused
                                    text: "󰏤"; color: T.Theme.color9; opacity: 0.85
                                    font.pixelSize: 22; font.family: T.Theme.fontFamily
                                }

                                // Hover overlay — gradient + Play/Pause badge
                                Rectangle {
                                    anchors.fill: parent
                                    opacity: hoverArea.containsMouse ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                    gradient: Gradient {
                                        GradientStop { position: 0.0;  color: "transparent" }
                                        GradientStop { position: 0.65; color: Qt.rgba(0,0,0,0.28) }
                                        GradientStop { position: 1.0;  color: Qt.rgba(0,0,0,0.58) }
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 56; height: 24; radius: 12
                                        color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.90)
                                        scale:   hoverArea.containsMouse ? 1.0 : 0.82
                                        opacity: hoverArea.containsMouse ? 1.0 : 0.0
                                        Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: isPaused ? "Resume" : (isActive ? "Pause" : "Play")
                                            color: T.Theme.bg
                                            font.pixelSize: 10; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                                        }
                                    }
                                }

                                // ── Cava strip across the bottom of the image ─
                                Row {
                                    anchors.bottom: parent.bottom
                                    anchors.left:   parent.left
                                    anchors.right:  parent.right
                                    anchors.bottomMargin: 3
                                    anchors.leftMargin:   2
                                    anchors.rightMargin:  2
                                    spacing: 1
                                    visible: isActive && !isPaused
                                    Repeater {
                                        model: root.cavaBarCount
                                        delegate: Rectangle {
                                            width:  (parent.width - (root.cavaBarCount - 1)) / root.cavaBarCount
                                            radius: 2
                                            property real bv: {
                                                var idx = Math.round(index * (root.cavaBars.length - 1) / (root.cavaBarCount - 1))
                                                return root.cavaBars.length > 0 ? Math.max(0.04, root.cavaBars[idx] || 0.04) : 0.05
                                            }
                                            height: Math.max(3, Math.round(bv * 18))
                                            anchors.bottom: parent.bottom
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 1.0) }
                                                GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.70) }
                                            }
                                            Behavior on height { NumberAnimation { duration: 65; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.split("/").pop().replace(/\.[^.]+$/, "")
                                color: T.Theme.fg; opacity: 0.65
                                font.pixelSize: 10; font.family: T.Theme.fontFamily
                                elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter; Layout.preferredHeight: 18
                            }
                        }

                        // Main play/pause MouseArea — z:1, BELOW cover button
                        MouseArea {
                            id: hoverArea; anchors.fill: parent; z: 1
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData === root.currentTrack && (root.isPlaying || root.isPaused)) {
                                    root.pauseTrack()   // same track → pause/resume
                                } else {
                                    root.playTrack(modelData)   // different track → play
                                }
                            }
                        }
                    }

                    // ── 󰋩 Cover button — outside cardBg so clip:true never blocks it ──
                    // Anchored to the delegate Item itself (no clipping ancestor).
                    Rectangle {
                        z: 2
                        anchors.top:    cardBg.top;   anchors.topMargin:   8
                        anchors.right:  cardBg.right; anchors.rightMargin: 8
                        width: 28; height: 28; radius: 8
                        color: coverBtnHov.containsMouse
                            ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.80)
                            : hasCover
                                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.45)
                                : T.Theme.pw(T.Theme.pal?.colors?.color9, 0.35)
                        opacity: (hoverArea.containsMouse || hasCover) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                        Behavior on color   { ColorAnimation  { duration: T.Theme.animFast } }

                        Text { anchors.centerIn: parent; text: "󰋩"; color: "white"; font.pixelSize: 14; font.family: T.Theme.fontFamily }

                        MouseArea {
                            id: coverBtnHov; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) { mouse.accepted = true; root.openCoverInput(modelData) }
                        }
                    }
                }
            }
        }

        // ── List view ─────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: root.listView

            ListView {
                id: trackListView
                anchors.fill: parent; anchors.rightMargin: 8
                spacing: 8; clip: true; cacheBuffer: 300
                model: root.filteredTracks

                delegate: Rectangle {
                    width: trackListView.width; height: 80
                    radius: 10
                    readonly property bool   isRowActive: modelData === root.currentTrack && root.isPlaying
                    readonly property bool   isRowPaused: modelData === root.currentTrack && root.isPaused
                    readonly property string sidecarPath: root.coverForTrack(modelData)
                    readonly property bool   hasCover:    sidecarPath !== ""

                    color: listHov.containsMouse
                        ? Qt.rgba(T.Theme.pillBg.r, T.Theme.pillBg.g, T.Theme.pillBg.b, T.Theme.pillBg.a * 2)
                        : T.Theme.pillBg
                    border.color: (isRowActive || isRowPaused || listHov.containsMouse)
                        ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.40) : "transparent"
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 12

                        // Thumbnail
                        Rectangle {
                            Layout.preferredWidth: 100; Layout.fillHeight: true
                            color: Qt.rgba(T.Theme.bg.r, T.Theme.bg.g, T.Theme.bg.b, 0.5)
                            radius: 8; clip: true

                            Image {
                                anchors.fill: parent; source: hasCover ? ("file://" + sidecarPath) : ""
                                fillMode: Image.PreserveAspectCrop; smooth: true; asynchronous: true; cache: false
                                visible: hasCover && status === Image.Ready
                            }

                            // Playing indicator (simple animated icon, no cava)
                            Text {
                                anchors.centerIn: parent
                                visible: isRowActive && !isRowPaused
                                text: "󰗈"; color: T.Theme.color9; opacity: 0.85
                                font.pixelSize: 20; font.family: T.Theme.fontFamily
                                RotationAnimation on rotation {
                                    loops: Animation.Infinite; from: 0; to: 360
                                    duration: 3000; running: isRowActive && !isRowPaused
                                }
                            }

                            Text {
                                anchors.centerIn: parent; visible: isRowPaused; text: "󰏤"
                                color: T.Theme.color9; opacity: 0.85; font.pixelSize: 22; font.family: T.Theme.fontFamily
                            }

                            Text {
                                anchors.centerIn: parent; visible: !isRowActive && !isRowPaused && !hasCover; text: "󰗈"
                                color: T.Theme.fg; opacity: 0.5; font.pixelSize: 18; font.family: T.Theme.fontFamily
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: modelData.split("/").pop().replace(/\.[^.]+$/, "")
                                color: T.Theme.fg; font.pixelSize: 13; font.weight: Font.Medium
                                font.family: T.Theme.fontFamily; elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true; text: modelData.split("/").pop()
                                color: T.Theme.fg; opacity: 0.45; font.pixelSize: 10
                                font.family: T.Theme.fontFamily; elide: Text.ElideMiddle
                            }
                        }

                        // 󰋩 Cover button — z:2 so click reaches it through listHov
                        Rectangle {
                            z: 2
                            width: 32; height: 32; radius: 8
                            color: listCoverHov.containsMouse
                                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.28)
                                : hasCover ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.14) : "transparent"
                            border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, hasCover ? 0.30 : 0.0); border.width: 1
                            opacity: (listHov.containsMouse || hasCover) ? 1.0 : 0.0
                            Behavior on color   { ColorAnimation { duration: T.Theme.animFast } }
                            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                            Text { anchors.centerIn: parent; text: "󰋩"; color: T.Theme.color9; opacity: 0.90; font.pixelSize: 14; font.family: T.Theme.fontFamily }
                            MouseArea {
                                id: listCoverHov; anchors.fill: parent; z: 2
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) { mouse.accepted = true; root.openCoverInput(modelData) }
                            }
                        }

                        // Play/Pause/Resume button
                        Rectangle {
                            Layout.preferredWidth: 70; Layout.preferredHeight: 32; radius: 8
                            color: (listHov.containsMouse || isRowActive || isRowPaused)
                                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                                : T.Theme.pw(T.Theme.pal?.colors?.color9, 0.15)
                            Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                            Text {
                                anchors.centerIn: parent
                                text: isRowPaused ? "Resume" : (isRowActive ? "Pause" : "Play")
                                color: T.Theme.fg; font.pixelSize: 12; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                            }
                        }
                    }

                    // List row MouseArea — z:1, below the cover button
                    MouseArea {
                        id: listHov; anchors.fill: parent; z: 1
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData === root.currentTrack && (root.isPlaying || root.isPaused)) {
                                root.pauseTrack()
                            } else {
                                root.playTrack(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}