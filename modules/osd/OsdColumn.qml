pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "osdmetrics.js" as Metrics

// ── OsdColumn ─────────────────────────────────────────────────────────────────
// The OSD, once: a vertical card that is either
//   LEVELS    volume, brightness, and the microphone when it was the mic you pressed — an
//             M3E slider each, its shape badge turning into the number while the value
//             moves (FillSlider)
//   a TILE    everything with words — a Bluetooth device connecting, the magnifier's zoom,
//             a media pill's player icon, an IPC kind the shell doesn't know: a badge, a
//             name, and (when there is a level) a meter and its value
// Hosted by TWO things that differ only in where they stand:
//   modules/bar/OsdDock   welded into the screen frame, inside the bar's window
//   OsdSliders            a floating overlay window, for while a window is fullscreen
//                         (Hyprland hides the bar's layer under one — the notification
//                         deck hands off the same way)
//
// ── Created per showing, gone after ───────────────────────────────────────────
// A host puts this behind a Loader that is active only while the OSD is up or fading,
// so a closed OSD costs nothing. It therefore takes its first request in
// Component.onCompleted (the signal fired before it existed) and later ones from
// Osd.requestId.
//
// ── Interactive, unlike the old card ──────────────────────────────────────────
// Levels: drag, scroll, and HOVER holds it open. A tile is read, never touched — but
// hovering it holds it open too, so it does not vanish under a pointer that is reading it.
// It never takes the keyboard: it appears unprompted, and a surface that grabbed it would
// eat the volume key you are holding.
//
// ── Which rows ────────────────────────────────────────────────────────────────
// Volume always. Brightness when the host's screen has a display the shell can dim (two
// monitors each show their own). The microphone only when the mic was what changed — mic
// level is something you set once from the mixer, so a permanent third slider is noise.
//
// ── Local copies, written imperatively ────────────────────────────────────────
// Every value shown is a plain copy taken when a request arrives or when you move
// something here — never a binding. Bound to the services it would blank the instant
// the OSD dismissed and spend its fade-out empty (UpdatesPage's log pane and
// ScreenshotToast's thumbnail hit the same trap), and Brightness.monitors is a lazy model
// that re-enters a binding walking it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: col

    // The screen this column answers for: which display's brightness it shows.
    required property var forScreen

    // ── Geometry: osdmetrics.js, which OsdSliders sizes its window from too ───
    readonly property var m: Metrics.of(Tokens.pillHeight, Tokens.spacingMd, Tokens.spacingLg, Tokens.spacingXl)
    readonly property int sliderW: col.m.sliderW
    readonly property int ctrlH:   col.m.ctrlH
    readonly property int tileW:   col.m.tileW
    readonly property int pad:     col.m.pad
    readonly property int gap:     col.m.gap

    // Each row carries its trailing gap, so a collapsing row takes its gap with it; the
    // last one's is taken back off here.
    implicitWidth:  (col.tile ? col.tileW : col.sliderW) + col.pad * 2
    implicitHeight: (col.tile ? tileBox.implicitHeight : rows.implicitHeight - col.gap) + col.pad * 2

    // ── What this showing is ──────────────────────────────────────────────────
    property bool   tile:            false
    property real   heldVolume:      0
    property bool   heldMuted:       false
    property string glyphVolume:     ""
    property real   heldMic:         0
    property bool   heldMicMuted:    false
    property string glyphMic:        ""
    property real   heldBrightness:  0
    property string glyphBrightness: ""
    // This screen's display in Brightness.monitors, or -1 for "none the shell can dim".
    property int    brightIndex:     -1
    property bool   micRow:          false

    // A tile's own copies (see the note above on why they are not bindings).
    property string tileKind:    ""
    property string tileGlyph:   ""
    property string tileIcon:    ""
    property string tileCaption: ""
    property string tileLabel:   ""
    property real   tileValue:   0
    property bool   tileMeter:   true
    property bool   tileOff:     false

    // The badge's shape says what the thing is; a muted or disconnected one is a circle.
    function shapeFor(kind) {
        switch (kind) {
        case "volume":     return "cookie9"
        case "mic":        return "clover"
        case "brightness": return "sunny"
        case "bluetooth":  return "hexagon"
        case "magnifier":  return "squircle"
        default:           return "burst"
        }
    }

    function refresh() {
        col.heldVolume  = Audio.volume
        col.heldMuted   = Audio.muted
        col.glyphVolume = Audio.glyph(Audio.volume, Audio.muted)

        col.heldMic      = Audio.micVolume
        col.heldMicMuted = Audio.micMuted
        col.glyphMic     = Audio.micMuted ? "󰍭" : "󰍬"

        col.brightIndex = Brightness.indexForPort(col.forScreen?.name ?? "")
        if (col.brightIndex >= 0) {
            col.heldBrightness  = Brightness.monitors.get(col.brightIndex).brightness / 100
            col.glyphBrightness = Osd.glyphFor("brightness", col.heldBrightness, col.heldBrightness <= 0)
        }
    }

    function take() {
        col.tile = !Osd.sliders
        if (col.tile) {
            col.tileKind    = Osd.kind
            col.tileGlyph   = Osd.glyph
            col.tileIcon    = Osd.iconPath
            col.tileCaption = Osd.caption
            col.tileLabel   = Osd.label
            col.tileValue   = Osd.value
            col.tileMeter   = Osd.meter
            col.tileOff     = Osd.off
        } else {
            // The first level you press is also the first moment the shell has any reason
            // to know what can be dimmed: probe now (once per session; a no-op after), so
            // the brightness row is there from the NEXT request on.
            Brightness.ensureProbed()
            col.micRow = Osd.kind === "mic"
            col.refresh()
        }
        life.restart()
        Qt.callLater(col.report)
    }

    // What the layout resolved to, for `osd status` (see Osd.qml for why that exists).
    function report() {
        Osd.diagCardW  = Math.round(col.implicitWidth)
        Osd.diagGlyphW = Math.round(col.sliderW)
        Osd.diagMeterW = Math.round(col.tile ? tileMeterBar.width : vol.width)
        Osd.diagLabelW = Math.round(col.tile ? tileValueText.width : 0)
    }

    Component.onCompleted: col.take()

    Connections {
        target: Osd
        function onRequestIdChanged() { if (Osd.active) col.take() }
    }

    Timer {
        id: life
        interval: Math.max(400, Config.osdMs)
        repeat: false
        // Held open while the pointer is on it or a slider is being dragged.
        onTriggered: {
            if (hover.hovered || vol.pressed || bright.pressed || mic.pressed) life.restart()
            else Osd.dismiss()
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered) life.restart()
    }

    // The service clamps (the laptop floor) and updates its model synchronously, so
    // reading it straight back shows what actually landed.
    function setBrightness(percent) {
        if (col.brightIndex < 0) return
        Brightness.requestBrightness(col.brightIndex, percent)
        col.refresh()
        life.restart()
    }

    // ══ LEVELS ════════════════════════════════════════════════════════════════
    // Each row collapses to zero height rather than hiding, on a spring, so the card
    // around this grows and shrinks as one appears.
    Column {
        id: rows
        visible: !col.tile
        x: col.pad
        y: col.pad

        Item {
            width: col.sliderW
            height: col.ctrlH + col.gap
            FillSlider {
                id: vol
                width: col.sliderW
                height: col.ctrlH
                glyph: col.glyphVolume
                shape: col.shapeFor("volume")
                value: col.heldVolume
                muted: col.heldMuted || col.heldVolume <= 0
                onMoved: v => { Audio.setVolume(v); life.restart() }
                onScrolled: d => { Audio.stepVolume(d); life.restart() }
            }
        }

        Item {
            width: col.sliderW
            height: micOpen.value * (col.ctrlH + col.gap)
            opacity: micOpen.value
            clip: true
            SpringValue { id: micOpen; target: col.micRow ? 1 : 0; spec: Motion.springEffects; epsilon: 0.002 }
            FillSlider {
                id: mic
                width: col.sliderW
                height: col.ctrlH
                glyph: col.glyphMic
                shape: col.shapeFor("mic")
                value: col.heldMic
                muted: col.heldMicMuted
                onMoved: v => { col.heldMic = v; Audio.setMicVolume(v); life.restart() }
                onScrolled: d => {
                    col.heldMic = Audio.steppedLevel(col.heldMic, d > 0)
                    Audio.setMicVolume(col.heldMic)
                    life.restart()
                }
            }
        }

        Item {
            width: col.sliderW
            height: brightOpen.value * (col.ctrlH + col.gap)
            opacity: brightOpen.value
            clip: true
            SpringValue { id: brightOpen; target: col.brightIndex >= 0 ? 1 : 0; spec: Motion.springEffects; epsilon: 0.002 }
            FillSlider {
                id: bright
                width: col.sliderW
                height: col.ctrlH
                glyph: col.glyphBrightness
                shape: col.shapeFor("brightness")
                value: col.heldBrightness
                onMoved: v => col.setBrightness(v * 100)
                onScrolled: d => col.setBrightness(col.heldBrightness * 100 + d * Brightness.keyStep)
            }
        }
    }

    // ══ A TILE ════════════════════════════════════════════════════════════════
    // Badge, name, meter, value — centred in a column. Read, never touched.
    Column {
        id: tileBox
        visible: col.tile
        x: col.pad
        y: col.pad
        width: col.tileW
        spacing: col.gap

        MorphShape {
            id: tileBadge
            anchors.horizontalCenter: parent.horizontalCenter
            width:  col.sliderW
            height: col.sliderW
            shape: col.tileOff ? "circle" : col.shapeFor(col.tileKind)
            fillColor: col.tileOff ? Colors.of(QsWindow.window).surfaceContainer
                                   : Colors.of(QsWindow.window).primaryContainer

            // A real app icon when one is known (the volume OSD hands one in for a media
            // pill's player — Osd.hintNextVolume), the glyph otherwise.
            MaterialIcon {
                anchors.centerIn: parent
                visible: col.tileIcon === ""
                glyph: col.tileGlyph
                variant: "body"
                sizeScale: 1.2
                color: col.tileOff ? Colors.of(QsWindow.window).fgMuted
                                   : Colors.of(QsWindow.window).fgOnPrimaryContainer
            }

            // In its own colours — no tint, no muted-grey recolour: a recoloured brand mark
            // reads as broken rather than as "muted". Opacity carries that instead.
            Image {
                anchors.centerIn: parent
                width:  Tokens.iconXl
                height: Tokens.iconXl
                visible: col.tileIcon !== ""
                opacity: col.tileOff ? 0.5 : 1.0
                source: col.tileIcon
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
                // 2x the drawn size: a .desktop icon is whatever the app shipped, often
                // 512px, and this is built on every screen for the shell's whole life.
                sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
            }
        }

        StyledText {
            width: parent.width
            visible: col.tileCaption !== ""
            text: col.tileCaption
            color: col.tileOff ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fg
            variant: "label"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        // ── Anchored by its own width, never by its neighbours' ──────────────
        // The old card derived the meter's width from its siblings' and closed a circle
        // that silently collapsed it. This is a fixed fraction of the tile, nothing more.
        Meter {
            id: tileMeterBar
            width: parent.width
            height: Tokens.spacingMd
            visible: col.tileMeter
            value: col.tileValue
            // Muted is the absence of the active colour, not a colour of its own.
            accent: col.tileOff ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).primary
            fillDuration: Motion.track
        }

        StyledText {
            id: tileValueText
            width: parent.width
            visible: col.tileLabel !== ""
            text: col.tileLabel
            color: col.tileOff ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fg
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
