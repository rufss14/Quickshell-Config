import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../theming" as T

// ── AudioVisualizer ───────────────────────────────────────────────────────────
// Standalone pill. Right-click swaps between the cava visualizer and an inline
// music controller (scrolling title/artist, prev/play/next, seekable progress).
// Right-click again returns to the visualizer.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape: false
    property bool showController: false

    // ── Geometry ──────────────────────────────────────────────────────────────
    readonly property int barCount: 16
    readonly property int barW:     3
    readonly property int barGap:   3
    readonly property int hPad:     12
    readonly property int maxBarH:  T.Theme.pillHeight - 6

    implicitHeight: T.Theme.pillHeight
    // Fixed overhead: left pad(4) + textClip margins(8) + timeRow(~60) + btnRow(~72) + right pad(8)
    readonly property int ctrlOverhead: 4 + 8 + 60 + 72 + 8
    readonly property int ctrlMinWidth: 200
    readonly property int ctrlMaxWidth: 340

    implicitWidth:  showController
                    ? Math.min(ctrlMaxWidth,
                               Math.max(ctrlMinWidth,
                                        (titleText?.implicitWidth ?? 0) + ctrlOverhead))
                    : barCount * (barW + barGap) - barGap + hPad * 2

    Behavior on implicitWidth  { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg
    clip:   true

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    readonly property color accentHigh: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90)
    readonly property color accentLow:  T.Theme.pw(T.Theme.pal?.colors?.color4, 0.25)

    // ── Pick the actively-playing MPRIS player ────────────────────────────────
    // FIX: sticky player — we remember the last seen player and only switch away
    //      if a *different* player starts playing.  Pausing the current player
    //      no longer drops back to all[0].
    property var _lastPlayer: null

    Connections {
        target: Mpris.players
        function onValuesChanged() { root._refreshPlayer() }
    }

    Component.onCompleted: _refreshPlayer()

    function _refreshPlayer() {
        var all = Mpris.players.values
        // Prefer whichever player is actively playing
        for (var i = 0; i < all.length; i++) {
            if (all[i].playbackState === MprisPlaybackState.Playing) {
                _lastPlayer = all[i]
                return
            }
        }
        // Nothing playing — keep last player only if it's still in the list
        for (var j = 0; j < all.length; j++) {
            if (all[j] === _lastPlayer) return   // still valid, keep it
        }
        // Last player is gone (e.g. Firefox closed) — null it out immediately
        // so the position-polling timers stop and don't hit a dead D-Bus object
        _lastPlayer = null
    }

    // Also refresh when any individual player's playback state changes
    Instantiator {
        model: Mpris.players
        delegate: Connections {
            target: modelData
            function onPlaybackStateChanged() { root._refreshPlayer() }
        }
    }

    readonly property var player: _lastPlayer

    // ── Right-click toggles mode ──────────────────────────────────────────────
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.showController = !root.showController
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAVA VISUALIZER
    // ═══════════════════════════════════════════════════════════════════════════
    property var  bars:        []
    property bool hasLiveData: bars.length > 0
    property var  demoBars:    []
    property var  displayBars: hasLiveData ? bars : demoBars

    Process {
        id: cavaProc
        command: [
            "bash", "-c",
            "cfg=$(mktemp /tmp/cava-qs-XXXXXX.ini)\n" +
            "printf '[general]\\nbars=16\\nframerate=60\\n[output]\\nmethod=raw\\ndata_format=ascii\\nascii_max_range=1000\\nraw_target=/dev/stdout\\nbar_delimiter=59\\nframe_delimiter=10\\nchannels=mono\\n' > \"$cfg\"\n" +
            "cava -p \"$cfg\"\n" +
            "rm -f \"$cfg\""
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var t = line.trim()
                if (t.length === 0) return
                var parts = t.split(";")
                var arr = []
                for (var j = 0; j < parts.length; j++) {
                    var s = parts[j].trim()
                    if (s.length === 0) continue
                    var v = parseInt(s)
                    if (!isNaN(v)) arr.push(v / 1000.0)
                }
                if (arr.length >= 2) root.bars = arr
            }
        }
        running: true
    }

    Timer {
        interval: 50
        running:  !root.hasLiveData
        repeat:   true
        onTriggered: {
            var now = Date.now() / 1000
            var arr = []
            for (var i = 0; i < root.barCount; i++) {
                var v = 0.5 + 0.45 * Math.sin(now * 2.1 + i * 0.7)
                           + 0.15 * Math.sin(now * 5.3 + i * 1.3)
                arr.push(Math.max(0.02, Math.min(1.0, v)))
            }
            root.demoBars = arr
        }
    }

    Row {
        id: vizRow
        anchors.centerIn: parent
        spacing: root.barGap
        opacity: root.showController ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        Repeater {
            model: root.displayBars.length
            Item {
                width:  root.barW
                height: root.maxBarH
                property real barVal: index < root.displayBars.length ? root.displayBars[index] : 0
                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: Math.max(2, Math.round(parent.barVal * parent.height))
                    radius: 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90) }
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.35) }
                    }
                    Behavior on height { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MUSIC CONTROLLER
    // Two-row layout inside pillHeight + 26 px:
    //
    //  ┌────────────────────────────────────────────────────┐
    //  │  [scrolling title]              [‹]  [▶]  [›]     │  ← pillHeight (24px)
    //  │  [0:00] ══════════════════════════════════ [4:35]  │  ← 14px + margins
    //  └────────────────────────────────────────────────────┘
    // ═══════════════════════════════════════════════════════════════════════════
    Item {
        id: ctrlView
        anchors.fill: parent
        opacity: root.showController ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

        // ── Track position — always synced regardless of controller visibility ─
        property real trackPos:    0
        property real trackLength: 1

        function syncPos() {
            if (!root.player) { trackPos = 0; trackLength = 1; return }
            trackPos    = root.player.position ?? 0
            trackLength = (root.player.length > 0) ? root.player.length : 1
        }

        // Hard sync every 500ms always
        Timer {
            interval: 500
            running:  root.player !== null
            repeat:   true
            onTriggered: ctrlView.syncPos()
        }

        // Smooth interpolation every 32ms while playing
        Timer {
            interval: 32
            running:  root.player !== null
                   && root.player.playbackState === MprisPlaybackState.Playing
            repeat:   true
            onTriggered: {
                if (ctrlView.trackLength > 0)
                    ctrlView.trackPos = Math.min(ctrlView.trackPos + 0.032,
                                                 ctrlView.trackLength)
            }
        }

        Connections {
            target: root.player ?? null
            function onTrackTitleChanged()    { ctrlView.syncPos(); ctrlView.marqueeReset() }
            function onTrackChanged()         { ctrlView.syncPos(); ctrlView.marqueeReset() }
            function onPlaybackStateChanged() { ctrlView.syncPos() }
            function onLengthChanged()        { ctrlView.syncPos() }
            function onPositionChanged()      { ctrlView.syncPos() }
        }
        Connections {
            target: root
            function onPlayerChanged() { ctrlView.syncPos(); ctrlView.marqueeReset() }
        }
        onVisibleChanged: if (visible) { ctrlView.syncPos(); ctrlView.marqueeReset() }

        function marqueeReset() {
            marqueeAnim.stop()
            titleText.x = 0
            marqueeAnim.restart()
        }

        function fmt(secs) {
            if (!secs || secs <= 0) return "0:00"
            var m = Math.floor(secs / 60)
            var s = Math.floor(secs % 60)
            return m + ":" + (s < 10 ? "0" : "") + s
        }

        // ── Single row: [pos] artist – title … [len]  [‹][⏸][›] ─────────────
        Item {
            id: topRow
            anchors.left:        parent.left
            anchors.right:       parent.right
            anchors.top:         parent.top
            anchors.bottom:      progressStrip.top
            anchors.leftMargin:  8
            anchors.rightMargin: 8

            // Playback buttons pinned to the right
            Row {
                id: btnRow
                anchors.right:          parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Item {
                    width: 20; height: 20
                    opacity: (root.player?.canGoPrevious ?? false) ? 1.0 : 0.30
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        color: T.Theme.fg
                        font { family: T.Theme.fontFamily; pixelSize: 14 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (root.player) root.player.previous()
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Item {
                    width: 20; height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: (root.player?.playbackState === MprisPlaybackState.Playing)
                                ? "../../theming/icons/pause.svg"
                                : "../../theming/icons/play.svg"
                        sourceSize: Qt.size(14, 14)
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!root.player) return
                            if (root.player.playbackState === MprisPlaybackState.Playing)
                                root.player.pause()
                            else
                                root.player.play()
                        }
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Item {
                    width: 20; height: 20
                    opacity: (root.player?.canGoNext ?? false) ? 1.0 : 0.30
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        color: T.Theme.fg
                        font { family: T.Theme.fontFamily; pixelSize: 14 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (root.player) root.player.next()
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            // Timestamps side-by-side, pinned to the left of the buttons
            Row {
                id: timeRow
                anchors.right:          btnRow.left
                anchors.rightMargin:    5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    id: posText
                    text:  ctrlView.fmt(ctrlView.trackPos)
                    color: T.Theme.dimFg
                    font { family: T.Theme.fontFamily; pixelSize: 7; weight: Font.Bold }
                }
                Text {
                    text: " / "
                    color: T.Theme.dimFg
                    font { family: T.Theme.fontFamily; pixelSize: 7; weight: Font.Bold }
                }
                Text {
                    id: lenText
                    text:  ctrlView.fmt(ctrlView.trackLength)
                    color: T.Theme.dimFg
                    font { family: T.Theme.fontFamily; pixelSize: 7; weight: Font.Bold }
                }
            }

            // Scrolling artist – title, from left edge to the timestamp group
            Item {
                id: textClip
                anchors.left:        parent.left
                anchors.right:       timeRow.left
                anchors.leftMargin:  4
                anchors.rightMargin: 4
                anchors.top:         parent.top
                anchors.bottom:      parent.bottom
                clip: true

                Text {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var artist = root.player?.trackArtist ?? ""
                        var title  = root.player?.trackTitle  ?? "No player"
                        return artist.length > 0 ? artist + " - " + title : title
                    }
                    color: T.Theme.fg
                    font { family: T.Theme.fontFamily; pixelSize: 10; weight: Font.Bold }
                }

                NumberAnimation {
                    id: marqueeAnim
                    target:   titleText
                    property: "x"
                    from:     0
                    to:       -(titleText.implicitWidth + 32)
                    duration: Math.max(9000, titleText.implicitWidth * 65)
                    loops:    Animation.Infinite
                    running:  titleText.implicitWidth > textClip.width && root.showController
                    onStopped: titleText.x = 0
                }
            }
        }

        // ── Thin progress strip pinned to the bottom edge ─────────────────────
        Rectangle {
            id: progressStrip
            anchors.left:         parent.left
            anchors.right:        parent.right
            anchors.bottom:       parent.bottom
            anchors.leftMargin:   8
            anchors.rightMargin:  8
            anchors.bottomMargin: 3
            height: 2
            radius: 1
            color:  root.accentLow

            Rectangle {
                id: fillBar
                anchors.left:   parent.left
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                color:  root.accentHigh
                width: ctrlView.trackLength > 0
                       ? progressStrip.width * Math.max(0, Math.min(1,
                             ctrlView.trackPos / ctrlView.trackLength))
                       : 0
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.Linear } }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 4
                color: root.accentHigh
                x: Math.max(0, Math.min(progressStrip.width - width,
                                        fillBar.width - width / 2))
                opacity: seekArea.containsMouse || seekArea.pressed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }

            MouseArea {
                id: seekArea
                anchors.fill:         parent
                anchors.topMargin:    -10
                anchors.bottomMargin: -10
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                enabled: (root.player?.canSeek ?? false) && root.showController
                function doSeek(mx) {
                    if (!root.player || root.player.length <= 0) return
                    var ratio  = Math.max(0, Math.min(1, mx / progressStrip.width))
                    var newPos = ratio * root.player.length
                    root.player.position = newPos
                    ctrlView.trackPos    = newPos
                }
                onClicked:         function(m) { doSeek(m.x) }
                onPositionChanged: function(m) { if (pressed) doSeek(m.x) }
            }
        }
    }
}
