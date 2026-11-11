pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clips.js" as ClipsJs

// ── ClipEditor ────────────────────────────────────────────────────────────────
// One clip, opened from the library: watch it, find the moment, cut it, export it.
//
//   the stage      the clip playing (components/media/ClipPlayer, only when
//                  qt6-multimedia is installed — state/Media probes it; without it
//                  the poster stands in and the editor still cuts and exports).
//   the transport  play/pause, a frame either way, speed, volume, loop the cut.
//   the timeline   a filmstrip with the playhead and two handles; click or drag
//                  to seek, drag a handle to cut. I / O set a handle at the
//                  playhead.
//   export         the cut: a fast lossless copy or a precise re-encode, sized for
//                  Discord (10/25/50 MB), downscaled, with or without the mic
//                  track, or as a GIF — clips-lib.py `export`, beside the original,
//                  never over it. Save frame: the frame under the playhead as a PNG.
//
// Keys: Space play/pause · ←/→ 1s (Shift 5s) · , . a frame · I / O in / out ·
// L loop · Home/End · Esc back to the library.
//
// ── Two modes: the PLAYER and the editor (2026-10-18) ─────────────────────────
// `viewOnly` is the player: the clip starts playing, with a transport, a seek strip, the name and
// the file's actions — no cut handles, no export. It is what "Play" means everywhere in the clips
// UI, so a clip plays in THIS shell instead of in whatever app the system uses for video. The
// "Edit" chip flips to the editor (`editRequested`). Same component, same player, so a clip you
// were watching is exactly where you left it when you start cutting.
//
// Restyled to the media / colours panels' look: ChipTray toolbars, a CookieButton for play, flat
// section cards (no outline) for the export options.
//
// Shows things and calls services/Clips; nothing here touches a file.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: ed

    // The entry being edited. The gallery hands over a plain copy that it never
    // clears, so a refresh (after a rename) can't blank the editor mid-edit.
    // `entry`, not `clip`: that is Item.clip, and redeclaring it shadows the base.
    property var entry: null
    // Just watch it (see the header): autoplays, no cut or export; "Edit" asks the gallery to flip.
    property bool viewOnly: false
    signal back()
    signal editRequested()

    focus: true

    // ══ Time ══════════════════════════════════════════════════════════════════
    readonly property var player: stage.player
    // ms. The player's once it knows, else the index's (ffprobe's).
    readonly property real durMs: ed.player && ed.player.duration > 0 ? ed.player.duration
                                                                      : (ed.entry?.duration ?? 0) * 1000
    // The playhead: the player's, or — without one — where the timeline was clicked.
    property real cursorMs: 0
    readonly property real posMs: ed.player ? ed.player.position : ed.cursorMs
    function seek(ms) {
        const t = Math.max(0, Math.min(ed.durMs, ms))
        ed.cursorMs = t
        if (ed.player) ed.player.seek(t)
    }

    // The cut, as fractions of the clip.
    property real a: 0
    property real b: 1
    readonly property var span: ClipsJs.trimSpan(ed.a, ed.b, ed.durMs / 1000)
    readonly property bool cut: ed.a > 0.001 || ed.b < 0.999
    function setIn()  { ed.a = Math.min(ed.posMs / Math.max(1, ed.durMs), ed.b - ed.minGap) }
    function setOut() { ed.b = Math.max(ed.posMs / Math.max(1, ed.durMs), ed.a + ed.minGap) }
    function resetCut() { ed.a = 0; ed.b = 1 }
    // Handles keep a sliver apart and never cross.
    readonly property real minGap: 0.02

    onEntryChanged: {
        ed.resetCut()
        ed.cursorMs = 0
        if (ed.entry) Clips.loadStrip(ed.entry.path, timeline.frames)
    }

    // ══ Export options ════════════════════════════════════════════════════════
    property bool precise: false
    property int sizeMB: 0
    property int outHeight: 0          // not `height` — Item has one
    // "mix" by default: a player, a browser and Discord play only the FIRST audio
    // track, so a clip recorded with separate tracks loses the voice otherwise.
    property string audio: "mix"
    property string format: "mp4"
    // Anything that changes the picture or the size is a re-encode (clips-lib.py).
    readonly property bool reencodes: ed.format === "gif" || ed.precise || ed.sizeMB > 0
                                      || (ed.outHeight > 0 && ed.outHeight < (ed.entry?.height ?? 0))
    function doExport() {
        if (!ed.entry || !ed.span) return
        Clips.exportClip(ed.entry.path, ed.span.start, ed.span.end,
                         { precise: ed.precise, sizeMB: ed.sizeMB, height: ed.outHeight,
                           audio: ed.audio, format: ed.format })
    }

    // ══ Keys ══════════════════════════════════════════════════════════════════
    Keys.onPressed: function (e) {
        const big = (e.modifiers & Qt.ShiftModifier) ? 5000 : 1000
        switch (e.key) {
        case Qt.Key_Space:  if (ed.player) ed.player.toggle(); break
        case Qt.Key_Left:   ed.seek(ed.posMs - big); break
        case Qt.Key_Right:  ed.seek(ed.posMs + big); break
        case Qt.Key_Comma:  if (ed.player) ed.player.step(-1); break
        case Qt.Key_Period: if (ed.player) ed.player.step(1); break
        case Qt.Key_I:      if (!ed.viewOnly) ed.setIn(); break
        case Qt.Key_O:      if (!ed.viewOnly) ed.setOut(); break
        case Qt.Key_L:      stage.loop = !stage.loop; break
        case Qt.Key_Home:   ed.seek(ed.viewOnly ? 0 : ed.a * ed.durMs); break
        case Qt.Key_End:    ed.seek(ed.viewOnly ? ed.durMs : ed.b * ed.durMs); break
        case Qt.Key_E:      if (ed.viewOnly) ed.editRequested(); else return; break
        case Qt.Key_Escape: ed.back(); break
        default: return
        }
        e.accepted = true
    }

    ArmLatch {
        id: deleteLatch
        onConfirmed: {
            if (ed.entry) Clips.trashClip(ed.entry.path)
            ed.back()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ The toolbar: back, the name, the file's actions ═══════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            ChipTray {
                ChipButton {
                    symbol: "arrow_back"
                    label: Translation.tr("Library")
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: ed.back()
                }
            }
            InputField {
                Layout.fillWidth: true
                cornerRadius: implicitHeight / 2
                seed: ed.entry?.name ?? ""
                placeholder: Translation.tr("Name")
                onCommitted: function (v) {
                    if (ed.entry && v.trim() !== "" && v.trim() !== ed.entry.name) Clips.rename(ed.entry.path, v.trim())
                }
            }
            // Watching it: one chip to start cutting.
            ChipTray {
                groupShown: ed.viewOnly
                ChipButton {
                    symbol: "content_cut"
                    label: Translation.tr("Edit")
                    on: true
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: ed.editRequested()
                }
            }
            ChipTray {
                ChipButton {
                    symbol: "star"
                    on: ed.entry !== null && Clips.isFavourite(ed.entry.path)
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: if (ed.entry) Clips.toggleFavourite(ed.entry.path)
                }
                ChipButton {
                    symbol: "content_copy"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: if (ed.entry) Clips.copyClip(ed.entry.path)
                }
                ChipButton {
                    symbol: "send"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: if (ed.entry) Clips.sendToDiscord(ed.entry.path)
                }
                // The system's own player, for when you want it: this is what "Play" used to do.
                ChipButton {
                    symbol: "open_in_new"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: if (ed.entry) Clips.openClip(ed.entry.path)
                }
                ChipButton {
                    symbol: "folder_open"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: if (ed.entry) Clips.showInFolder(ed.entry.path)
                }
                ChipButton {
                    symbol: "delete"
                    label: deleteLatch.armed ? "Sure?" : ""
                    on: deleteLatch.armed
                    tint: Colors.of(QsWindow.window).danger
                    onActivated: deleteLatch.trigger()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingLg

            // ══ The stage, the transport, the timeline ════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingSm

                ClippingRectangle {
                    id: stage
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.radiusCard
                    // Letterbox: the palette's constant black (Colors.shadow), as a
                    // video's bars are — not a sixth kind of hardcoded colour.
                    color: Colors.of(QsWindow.window).shadow

                    property bool loop: false
                    readonly property var player: playerLoader.status === Loader.Ready ? playerLoader.item : null

                    // The poster: the thumbnail, until the video has a frame up.
                    ClipThumb {
                        anchors.fill: parent
                        radius: 0
                        color: "transparent"
                        entry: ed.entry
                        showDuration: false
                        decodeWidth: 960
                        visible: !(stage.player && stage.player.showing)
                    }

                    Loader {
                        id: playerLoader
                        anchors.fill: parent
                        active: Media.available && ed.entry !== null
                        source: Media.playerUrl
                        onLoaded: {
                            item.source = Qt.binding(() => ed.entry?.path ?? "")
                            item.loopSpan = Qt.binding(() => stage.loop)
                            item.loopStart = Qt.binding(() => ed.a * ed.durMs)
                            item.loopEnd = Qt.binding(() => ed.b * ed.durMs)
                            item.muted = Qt.binding(() => transport.muted)
                            item.volume = Qt.binding(() => transport.volume)
                            item.rate = Qt.binding(() => transport.rate)
                            item.autoplay = ed.viewOnly
                        }
                    }

                    // Click the picture: play/pause, the way every player does.
                    MouseArea {
                        anchors.fill: parent
                        enabled: stage.player !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { stage.player.toggle(); ed.forceActiveFocus() }
                    }
                    // Paused: a big play button in the middle (a CookieButton, as the media panel's).
                    CookieButton {
                        anchors.centerIn: parent
                        width: Tokens.iconXl * 3
                        height: width
                        name: "play_arrow"
                        primary: true
                        tint: Colors.of(QsWindow.window).primary
                        opacity: stage.player !== null && !stage.player.playing ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        onActivated: { stage.player.toggle(); ed.forceActiveFocus() }
                    }

                    // Without qt6-multimedia: say so, and how.
                    Rectangle {
                        visible: Media.checked && !Media.available
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: Tokens.spacingLg
                        width: noPlay.implicitWidth + Tokens.spacingXl
                        height: noPlay.implicitHeight + Tokens.spacingMd
                        radius: height / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.7)
                        StyledText {
                            id: noPlay
                            anchors.centerIn: parent
                            variant: "caption"
                            color: Colors.of(QsWindow.window).fg
                            text: Translation.tr("Playback needs qt6-multimedia qt6-multimedia-ffmpeg — cutting and export still work")
                        }
                    }
                    StyledText {
                        visible: (stage.player?.error ?? "") !== ""
                        anchors.centerIn: parent
                        variant: "label"
                        color: Colors.of(QsWindow.window).danger
                        text: stage.player?.error ?? ""
                    }
                }

                // ── Transport ─────────────────────────────────────────────────
                RowLayout {
                    id: transport
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    property real rate: 1
                    property real volume: 1
                    property bool muted: false

                    CookieButton {
                        Layout.preferredWidth: Tokens.iconXl * 2
                        Layout.preferredHeight: Tokens.iconXl * 2
                        name: stage.player?.playing ? "pause" : "play_arrow"
                        primary: true
                        tint: Colors.of(QsWindow.window).primary
                        enabled: stage.player !== null
                        onActivated: { stage.player.toggle(); ed.forceActiveFocus() }
                    }
                    ChipTray {
                        ChipButton {
                            symbol: "skip_previous"
                            tint: Colors.of(QsWindow.window).primary
                            enabled: stage.player !== null
                            onActivated: stage.player.step(-1)
                        }
                        ChipButton {
                            symbol: "skip_next"
                            tint: Colors.of(QsWindow.window).primary
                            enabled: stage.player !== null
                            onActivated: stage.player.step(1)
                        }
                    }
                    StyledText {
                        variant: "label"
                        font.family: Tokens.fontMono
                        text: ClipsJs.stamp(ed.posMs / 1000) + " / " + ClipsJs.stamp(ed.durMs / 1000)
                    }
                    Item { Layout.fillWidth: true }
                    ChipTray {
                        Repeater {
                            model: [0.5, 1, 1.5, 2]
                            delegate: ChipButton {
                                required property real modelData
                                label: modelData + "×"
                                on: transport.rate === modelData
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: transport.rate = modelData
                            }
                        }
                    }
                    ChipTray {
                        ChipButton {
                            symbol: "repeat"
                            on: stage.loop
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: stage.loop = !stage.loop
                        }
                        ChipButton {
                            symbol: transport.muted || transport.volume === 0 ? "volume_off" : "volume_up"
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: transport.muted = !transport.muted
                        }
                    }
                    ValueSlider {
                        Layout.preferredWidth: ed.width / 10
                        value: transport.muted ? 0 : transport.volume
                        onMoved: function (v) { transport.volume = v; transport.muted = false }
                    }
                }

                // ── Timeline: filmstrip, playhead, the cut ────────────────────
                Item {
                    id: timeline
                    Layout.fillWidth: true
                    Layout.preferredHeight: timeline.stripH + timeline.handleW * 2

                    readonly property int frames: 12
                    readonly property real stripH: Math.round(timeline.width / timeline.frames * 9 / 16)
                    readonly property int handleW: Tokens.spacingMd
                    readonly property var frameFiles:
                        ed.entry && Clips.strip.path === ed.entry.path ? Clips.strip.frames : []
                    function fracAt(x) { return Math.max(0, Math.min(1, x / timeline.width)) }

                    ClippingRectangle {
                        id: strip
                        y: timeline.handleW
                        width: parent.width
                        height: timeline.stripH
                        radius: Tokens.radiusSm
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                        Row {
                            Repeater {
                                model: timeline.frameFiles
                                delegate: Image {
                                    required property string modelData
                                    width: strip.width / timeline.frames
                                    height: strip.height
                                    source: modelData !== "" ? "file://" + modelData : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 160
                                }
                            }
                        }
                        BusyDot {
                            anchors.centerIn: parent
                            running: timeline.frameFiles.length === 0 && ed.entry !== null
                            visible: running
                        }
                        // Dimmed outside the cut, outlined inside it (the editor only).
                        Rectangle { visible: !ed.viewOnly; width: strip.width * ed.a; height: parent.height
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.65) }
                        Rectangle { visible: !ed.viewOnly; x: strip.width * ed.b; width: strip.width * (1 - ed.b); height: parent.height
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.65) }
                        Rectangle {
                            visible: !ed.viewOnly
                            x: strip.width * ed.a
                            width: strip.width * (ed.b - ed.a)
                            height: parent.height
                            color: "transparent"
                            border.width: Tokens.borderWidth * 2
                            border.color: Colors.of(QsWindow.window).primary
                            radius: Tokens.radiusXs
                        }
                    }

                    // Click or drag anywhere on the strip: seek.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        preventStealing: true
                        onPressed: function (m) { ed.seek(timeline.fracAt(m.x) * ed.durMs); ed.forceActiveFocus() }
                        onPositionChanged: function (m) { if (pressed) ed.seek(timeline.fracAt(m.x) * ed.durMs) }
                    }

                    // The playhead: follows the video, no easing (a line the hand drives).
                    Rectangle {
                        x: Math.round(timeline.width * (ed.durMs > 0 ? ed.posMs / ed.durMs : 0) - width / 2)
                        width: Tokens.borderWidth * 2
                        height: timeline.height
                        radius: width / 2
                        color: Colors.of(QsWindow.window).fg
                    }

                    // The two handles, over the seek area.
                    Repeater {
                        model: ed.viewOnly ? 0 : 2
                        delegate: Rectangle {
                            id: handle
                            required property int index
                            readonly property bool isIn: handle.index === 0
                            x: Math.round(timeline.width * (handle.isIn ? ed.a : ed.b) - timeline.handleW / 2)
                            width: timeline.handleW
                            height: timeline.height
                            radius: timeline.handleW / 2
                            color: Colors.of(QsWindow.window).primary
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Tokens.spacingSm
                                cursorShape: Qt.SizeHorCursor
                                preventStealing: true
                                onPositionChanged: function (m) {
                                    if (!pressed) return
                                    const v = timeline.fracAt(mapToItem(timeline, m.x, m.y).x)
                                    if (handle.isIn) ed.a = Math.min(v, ed.b - ed.minGap)
                                    else             ed.b = Math.max(v, ed.a + ed.minGap)
                                    // Scrub to the handle, so you SEE where the cut lands.
                                    ed.seek((handle.isIn ? ed.a : ed.b) * ed.durMs)
                                }
                            }
                        }
                    }
                }

                // ── The cut, and a frame ──────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    visible: !ed.viewOnly
                    ChipTray {
                        ChipButton { label: "In · I"; symbol: "first_page"; tint: Colors.of(QsWindow.window).primary
                                     onActivated: ed.setIn() }
                        ChipButton { label: "Out · O"; symbol: "last_page"; tint: Colors.of(QsWindow.window).primary
                                     onActivated: ed.setOut() }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        variant: "caption"
                        text: ed.span
                              ? ClipsJs.stamp(ed.span.start) + " → " + ClipsJs.stamp(ed.span.end)
                                + "  ·  " + ClipsJs.span(ed.span.end - ed.span.start)
                              : "Too short to keep"
                    }
                    ChipTray {
                        ChipButton { visible: ed.cut; symbol: "restart_alt"; tint: Colors.of(QsWindow.window).primary
                                     onActivated: ed.resetCut() }
                        ChipButton {
                            symbol: "photo_camera"; label: "Save frame"
                            tint: Colors.of(QsWindow.window).primary
                            enabled: ed.entry !== null && !Clips.acting
                            onActivated: Clips.saveFrame(ed.entry.path, ed.posMs / 1000)
                        }
                    }
                }
                // Watching: a frame can still be kept.
                ChipTray {
                    Layout.alignment: Qt.AlignLeft
                    groupShown: ed.viewOnly
                    ChipButton {
                        symbol: "photo_camera"; label: "Save frame"
                        tint: Colors.of(QsWindow.window).primary
                        enabled: ed.entry !== null && !Clips.acting
                        onActivated: Clips.saveFrame(ed.entry.path, ed.posMs / 1000)
                    }
                }
            }

            // ══ Export ════════════════════════════════════════════════════════
            Rectangle {
                visible: !ed.viewOnly
                Layout.preferredWidth: ed.viewOnly ? 0 : ed.exportW
                Layout.fillHeight: true
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).section

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    IconLine { glyph: "\u{F0207}"; text: "Export the cut" }          // 󰈇 export

                    ExportLabel { text: Translation.tr("Format") }
                    ExportChips {
                        model: [{ value: "mp4", label: "Video" }, { value: "gif", label: "GIF" }]
                        current: ed.format
                        onPicked: function (v) { ed.format = v }
                    }
                    ExportLabel { text: Translation.tr("Cut"); visible: ed.format === "mp4" }
                    ExportChips {
                        visible: ed.format === "mp4"
                        model: [{ value: false, label: "Fast" }, { value: true, label: "Precise" }]
                        current: ed.precise
                        onPicked: function (v) { ed.precise = v }
                    }
                    ExportLabel { text: Translation.tr("Size"); visible: ed.format === "mp4" }
                    ExportChips {
                        visible: ed.format === "mp4"
                        model: [{ value: 0, label: "Any" }, { value: 10, label: "10 MB" },
                                { value: 25, label: "25 MB" }, { value: 50, label: "50 MB" }]
                        current: ed.sizeMB
                        onPicked: function (v) { ed.sizeMB = v }
                    }
                    ExportLabel { text: Translation.tr("Resolution") }
                    ExportChips {
                        model: [{ value: 0, label: "As recorded" }, { value: 1080, label: "1080p" },
                                { value: 720, label: "720p" }, { value: 480, label: "480p" }]
                        current: ed.outHeight
                        onPicked: function (v) { ed.outHeight = v }
                    }
                    ExportLabel { text: Translation.tr("Audio"); visible: ed.format === "mp4" }
                    ExportChips {
                        visible: ed.format === "mp4"
                        model: [{ value: "mix", label: "Mixed" }, { value: "all", label: "Separate" },
                                { value: "first", label: "No mic" }, { value: "none", label: "Mute" }]
                        current: ed.audio
                        onPicked: function (v) { ed.audio = v }
                    }

                    // What will actually happen, in words.
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacingSm
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        emphasis: "dim"
                        text: ed.format === "gif"
                              ? "A looping GIF, 15 fps, no sound. Keep it short — GIFs are big."
                              : ed.reencodes
                                ? "Re-encoded: frame-exact" + (ed.sizeMB > 0 ? ", under " + ed.sizeMB + " MB" : "")
                                  + ". Takes a moment." + ed.audioNote
                                : "A lossless copy: instant, but it starts on the keyframe just before the in point."
                                  + ed.audioNote
                    }

                    Item { Layout.fillHeight: true }

                    Meter {
                        Layout.fillWidth: true
                        visible: Clips.exporting
                        value: Clips.exportProgress
                        fillDuration: Motion.track
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== "" && !Clips.exporting
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        color: Clips.actionResult.ok ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).danger
                        text: Clips.actionResult.text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        PanelButton {
                            Layout.fillWidth: true
                            variant: "primary"
                            accent: Colors.of(QsWindow.window).primary
                            symbol: Clips.exporting ? "hourglass_top" : "file_export"
                            label: Clips.exporting ? Math.round(Clips.exportProgress * 100) + "%" : "Export"
                            enabled: !Clips.exporting && ed.span !== null
                            onActivated: ed.doExport()
                        }
                        PanelButton {
                            visible: Clips.exporting
                            variant: "normal"
                            accent: Colors.of(QsWindow.window).danger
                            symbol: "close"
                            onActivated: Clips.cancelExport()
                        }
                    }
                }
            }
        }
    }

    readonly property int exportW: 300

    // What the audio choice means, when it isn't obvious.
    readonly property string audioNote:
          ed.audio === "mix"   ? " Every audio track mixed into one, so any player hears your mic."
        : ed.audio === "all"   ? " Tracks kept separate — most players and Discord play only the first, "
                                 + "so a separately recorded mic won't be heard outside an editor."
        : ed.audio === "first" ? " Keeps the first track — the desktop, when the mic was recorded separately."
        :                        ""

    component ExportLabel: StyledText { variant: "caption"; emphasis: "dim"; Layout.topMargin: Tokens.spacingXs }
    component ExportChips: ChipRow { Layout.fillWidth: true; Layout.fillHeight: false; accent: Colors.of(QsWindow.window).primary }
}
