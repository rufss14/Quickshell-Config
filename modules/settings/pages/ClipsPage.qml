pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/clips.js" as ClipsJs

// ── ClipsPage — Sidebar & dock › Clips ────────────────────────────────────────
// gpu-screen-recorder's settings: the replay buffer behind "clip it", recording, and
// what a clip is made of. services/Clips owns the recorder; this shows and sets.
//
// ── Laid out by job ───────────────────────────────────────────────────────────
// The recorder's buttons across the top (what is happening now), then what is
// captured beside how far back a clip reaches, then the picture's quality beside its
// format, then what happens after a save. It was one card per setting behind a
// "Capture, quality and files" fold; the fold is gone because a tab has the room, and
// the paragraphs under each card are tips. The most technical page in Settings, so it
// is allowed to run a little past the window's edge.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property string blocked: Clips.blocker()
    readonly property bool usable: Config.clips && root.blocked === ""

    // Buffer lengths as steps rather than a 5..1800 slider.
    readonly property var bufferSteps: [15, 30, 60, 90, 120, 180, 300, 600, 900, 1200, 1800]
    function nearest(list, v) {
        let best = 0
        for (let i = 0; i < list.length; i++)
            if (Math.abs(list[i] - v) < Math.abs(list[best] - v)) best = i
        return best
    }
    readonly property int bufferIndex: root.nearest(root.bufferSteps, Config.clipsBufferSeconds)

    // Bitrate steps in kbit/s, for constant-bitrate mode.
    readonly property var kbpsSteps: [5000, 8000, 12000, 20000, 30000, 40000, 60000, 80000, 100000]
    readonly property int kbpsIndex: root.nearest(root.kbpsSteps, Config.clipsKbps)

    readonly property int ramMiB: ClipsJs.bufferMiB(Clips.opts)

    // A caption + ChipRow line, for the format rows.
    component FormatRow: RowLayout {
        property string label: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd
        StyledText {
            Layout.preferredWidth: 78
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Tokens.spacingMd
            text: parent.label
            variant: "caption"
            emphasis: "dim"
        }
        Item {
            id: slot
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
        }
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F0567}"
        title:     Translation.tr("Clips")
        titleTail: "& recording"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.clips ? "Off"
                 : root.blocked !== "" ? root.blocked
                 : [Clips.mode === "record" ? "recording"
                    : Config.clipsBuffer ? "clipping on" : "clipping off",
                    ClipsJs.span(Clips.bufferSeconds) + " buffer",
                    ClipsJs.summary(Clips.opts)].join("  ·  ")

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            checked: Config.clips
            onToggled: Config.sidebarToggle("clips")
        }

        // ══ Now ═══════════════════════════════════════════════════════════════
        Section {
            span:    3
            enabled: Config.clips
            opacity: Config.clips ? 1 : 0.5
            glyph:   "\u{F0459}"                                  // 󰑙 replay
            title:   Translation.tr("Recorder")
            accent:  Colors.of(QsWindow.window).primary
            subtitle: root.blocked !== "" ? root.blocked + " — sudo pacman -S gpu-screen-recorder"
                    : Clips.recording ? "Recording"
                    : Clips.buffering ? "Clipping — Alt+F10 saves the last " + ClipsJs.span(Clips.bufferSeconds)
                    : "Idle"
            help: Translation.tr("Clipping keeps a replay buffer running — across reloads and reboots — so Alt+F10 always has something to save. ")
                + "Alt+Shift+F10 turns clipping on and off, Alt+F9 records, Alt+Shift+F9 records a region (which pauses clipping while it runs). "
                + "Settings below are startup arguments: they apply when the buffer restarts."

            // A Flow, so the two quiet actions wrap under the four main ones in a narrow
            // window instead of running off the card.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                PanelButton {
                    capsule: true
                    variant: Config.clipsBuffer ? "primary" : "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "replay"
                    label: Config.clipsBuffer ? "Clipping on" : "Clipping off"
                    enabled: root.usable
                    onActivated: Clips.toggleClipping()
                }
                PanelButton {
                    capsule: true
                    variant: "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "save"
                    label: Translation.tr("Clip it")
                    enabled: root.usable && Clips.buffering
                    onActivated: Clips.saveClip(0)
                }
                PanelButton {
                    capsule: true
                    variant: Clips.recording ? "primary" : "normal"
                    accent: Colors.of(QsWindow.window).danger
                    symbol: Clips.recording ? "stop" : "fiber_manual_record"
                    symbolFill: 1
                    label: Clips.recording ? "Stop" : "Record"
                    enabled: root.usable
                    onActivated: Clips.toggleRecord()
                }
                PanelButton {
                    capsule: true
                    variant: "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "crop_free"
                    label: Translation.tr("Region")
                    enabled: root.usable && Clips.mode !== "record" && Clips.hasSlurp
                    onActivated: Clips.recordRegion()
                }
                // Settings are startup arguments; this applies them now (the buffer's
                // contents go with it).
                PanelButton {
                    capsule: true
                    visible: Clips.buffering
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "restart_alt"
                    label: Translation.tr("Restart")
                    onActivated: Clips.restartBuffer()
                }
                PanelButton {
                    capsule: true
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "video_library"
                    label: Translation.tr("Gallery")
                    enabled: Config.clips
                    onActivated: Clips.openGallery()
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Media.checked && !Media.available
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: "dim"
                text: Translation.tr("The editor's built-in player needs qt6-multimedia and qt6-multimedia-ffmpeg; cutting and exporting work without it.")
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Clips.lastError !== ""
                wrapMode: Text.WordWrap
                variant: "caption"
                color: Colors.of(QsWindow.window).danger
                text: Clips.lastError
            }
        }

        // ══ What is captured ══════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F0379}"                                  // 󰍹 monitor
            title:   Translation.tr("Capture")
            help:    Translation.tr("Focused follows whichever monitor you're on when it starts. Portal asks once through the desktop portal and remembers.")
            accent:  Colors.of(QsWindow.window).primary

            ChipRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "", label: "Focused" }]
                       .concat(Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                       .concat([{ value: "portal", label: "Portal" }])
                current: Config.clipsTarget
                onPicked: function (v) { Config.clipsTarget = v }
            }

            // What goes into the file besides the picture: a set, so chips.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                ToggleChip {
                    symbol: "volume_up"
                    label:  Translation.tr("Desktop audio")
                    hint:   Translation.tr("What you hear — the default output.")
                    active: Config.clipsDesktopAudio
                    onToggled: Config.clipsDesktopAudio = !Config.clipsDesktopAudio
                }
                ToggleChip {
                    symbol: "mic"
                    label:  Translation.tr("Microphone")
                    hint:   Translation.tr("Your voice — the default input.")
                    active: Config.clipsMic
                    onToggled: Config.clipsMic = !Config.clipsMic
                }
                ToggleChip {
                    symbol: "arrow_selector_tool"
                    label:  Translation.tr("Cursor")
                    hint:   Translation.tr("Draw the pointer into the video.")
                    active: Config.clipsCursor
                    onToggled: Config.clipsCursor = !Config.clipsCursor
                }
            }

            // The trap this names: with it on, the mic is recorded but UNHEARD almost
            // everywhere — players, browsers and Discord play only track 1.
            SettingRow {
                enabled: Config.clipsDesktopAudio && Config.clipsMic
                label:  Translation.tr("Separate tracks")
                detail: Config.clipsSplitAudio ? "Mic on its own track — editors only" : "One mixed track, heard everywhere"
                help:   Translation.tr("On, the mic gets a track of its own, for editing. Players, browsers and Discord play only the first track — export with Mixed audio to share.")
                Toggle {
                    checked: Config.clipsSplitAudio
                    onToggled: Config.clipsSplitAudio = !Config.clipsSplitAudio
                }
            }
        }

        // ══ The buffer ════════════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F02DA}"                                  // 󰋚 history
            title:   Translation.tr("Replay buffer")
            subtitle: root.ramMiB > 0
                ? "About " + root.ramMiB + " MiB in " + (Config.clipsStorage === "disk" ? "a temp file" : "memory")
                : "Size follows what's on screen"
            help:    Translation.tr("How far back a clip can reach. In quality mode its size follows what's on screen; bitrate mode fixes it.")
            accent:  Colors.of(QsWindow.window).primary

            SliderRow {
                label: Translation.tr("Length")
                stepper: false
                from:  0
                to:    root.bufferSteps.length - 1
                step:  1
                value: root.bufferIndex
                readout: ClipsJs.span(root.bufferSteps[root.bufferIndex])
                onCommit: function (v) { Config.clipsBufferSeconds = root.bufferSteps[Math.round(v)] }
            }

            // What "clip it" keeps. Only lengths the recorder can cut on a signal, and
            // only shorter than the buffer.
            FormatRow {
                label: Translation.tr("A clip keeps")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: "All" }]
                           .concat([10, 30, 60, 300, 600]
                                   .filter(n => n < Clips.bufferSeconds)
                                   .map(n => ({ value: n, label: ClipsJs.span(n) })))
                    current: Config.clipsSaveSeconds < Clips.bufferSeconds ? Config.clipsSaveSeconds : 0
                    onPicked: function (v) { Config.clipsSaveSeconds = v }
                }
            }

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "ram",  label: "In memory", icon: "memory" },
                        { value: "disk", label: "On disk",   icon: "hard_drive" }]
                current: Config.clipsStorage
                onPicked: function (v) { Config.clipsStorage = v }
            }
        }

        // ══ Quality ═══════════════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F0E2C}"                                  // 󰸬 high-definition
            title:   Translation.tr("Quality")
            subtitle: Config.clipsBitrateMode === "cbr" ? "Fixed bitrate" : "Constant quality"
            help:    Translation.tr("Constant quality stays sharp in motion and its size varies. A fixed bitrate gives a predictable file and buffer size.")
            accent:  Colors.of(QsWindow.window).primary

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "auto", label: "Quality", icon: "tune" },
                        { value: "cbr",  label: "Bitrate", icon: "speed" }]
                current: Config.clipsBitrateMode === "cbr" ? "cbr" : "auto"
                onPicked: function (v) { Config.clipsBitrateMode = v }
            }
            ChipRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Config.clipsBitrateMode !== "cbr"
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "medium", label: "Medium" }, { value: "high", label: "High" },
                        { value: "very_high", label: "Very high" }, { value: "ultra", label: "Ultra" }]
                current: Clips.settings.quality
                onPicked: function (v) { Config.clipsQuality = v }
            }
            SliderRow {
                visible: Config.clipsBitrateMode === "cbr"
                label: Translation.tr("Bitrate")
                stepper: false
                from:  0
                to:    root.kbpsSteps.length - 1
                step:  1
                value: root.kbpsIndex
                readout: Math.round(root.kbpsSteps[root.kbpsIndex] / 1000) + " Mbit/s"
                onCommit: function (v) { Config.clipsKbps = root.kbpsSteps[Math.round(v)] }
            }
            FormatRow {
                label: Translation.tr("Resolution")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "original", label: "Native" }, { value: "1440", label: "1440p" },
                            { value: "1080", label: "1080p" }, { value: "720", label: "720p" }]
                    current: Clips.settings.resolution
                    onPicked: function (v) { Config.clipsResolution = v }
                }
            }
            FormatRow {
                label: Translation.tr("Frame rate")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [30, 60, 120, 144, 165, 240].map(n => ({ value: n, label: String(n) }))
                    current: Clips.settings.fps
                    onPicked: function (v) { Config.clipsFps = v }
                }
            }
        }

        // ══ Format and where it lands ═══════════════════════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F0567}"                                  // 󰕧 video
            title:   Translation.tr("Files")
            subtitle: (Clips.settings.codec === "auto" ? "H.264" : String(Clips.settings.codec).toUpperCase())
                      + " in " + String(Clips.settings.container).toUpperCase()
            help:    Translation.tr("H.264 in MP4 plays everywhere (Discord and browsers don't play HEVC); Auto picks H.264. MKV survives a crash mid-recording; MP4 doesn't. ")
                   + "Clips, recordings and trims all land in the folder; deleting from the gallery moves a clip to the trash."
            accent:  Colors.of(QsWindow.window).primary

            FormatRow {
                label: Translation.tr("Codec")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "auto", label: "Auto" }, { value: "h264", label: "H.264" },
                            { value: "hevc", label: "HEVC" }, { value: "av1", label: "AV1" }]
                    current: Clips.settings.codec
                    onPicked: function (v) { Config.clipsCodec = v }
                }
            }
            FormatRow {
                label: Translation.tr("Container")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "mp4", label: "MP4" }, { value: "mkv", label: "MKV" }]
                    current: Clips.settings.container
                    onPicked: function (v) { Config.clipsContainer = v }
                }
            }

            // "Open folder" and "show in folder" open in a file manager, never the default handler (which can
            // be a terminal browser). Automatic = Nautilus when it is installed.
            FormatRow {
                label: Translation.tr("File manager")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "", label: "Auto" }].concat(ClipsJs.FILE_MANAGERS
                               .filter(f => Clips.fileManagers.indexOf(f.id) >= 0)
                               .map(f => ({ value: f.id, label: f.label })))
                    current: Config.clipsFileManager
                    onPicked: function (v) { Config.clipsFileManager = v }
                }
            }
            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                mono: true
                seed: Config.clipsDir
                placeholder: "~/Videos/Clips"
                onCommitted: function (v) { Config.clipsDir = v.trim() }
            }
            SettingRow {
                label:  Translation.tr("Peek")
                detail: Config.clipsPeek ? "A card with its thumbnail" : "Off"
                help:   Translation.tr("A saved clip opens a card beside the sidebar button for a moment, with its thumbnail.")
                Toggle {
                    checked: Config.clipsPeek
                    onToggled: Config.clipsPeek = !Config.clipsPeek
                }
            }
            SettingRow {
                label:  Translation.tr("Notify")
                detail: Config.clipsNotify ? "A notification per clip" : "Off"
                help:   Translation.tr("Also send a notification per saved clip — for when the sidebar is hidden.")
                Toggle {
                    checked: Config.clipsNotify
                    onToggled: Config.clipsNotify = !Config.clipsNotify
                }
            }
        }

        // ══ When you clip, and when you record ═════════════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F0567}"                                  // 󰕧 video
            title:   Translation.tr("Clip & record")
            subtitle: (Config.clipsAhead > 0 ? "+" + Config.clipsAhead + "s after a clip" : "Clips save at once")
                      + (Config.clipsRecordLimit !== "off" ? " · stops after " + ClipsJs.limitOf(Config.clipsRecordLimit).label : "")
            help:    Translation.tr("Keep recording a few seconds after you press Clip it — so a play you only reacted to afterwards is in the clip. ")
                   + "It only applies to the button; the Alt+F10 keybind always saves at once. A recording stops by itself at its limit."
            accent:  Colors.of(QsWindow.window).primary

            FormatRow {
                label: Translation.tr("After a clip")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: "Save at once" }, { value: 10, label: "+10s" },
                            { value: 20, label: "+20s" }, { value: 30, label: "+30s" }]
                    current: Config.clipsAhead
                    onPicked: function (v) { Config.clipsAhead = v }
                }
            }
            FormatRow {
                label: Translation.tr("Stop a recording")
                ChipRow {
                    width: parent.width
                    accent: Colors.of(QsWindow.window).primary
                    model: ClipsJs.RECORD_LIMITS.map(l => ({ value: l.id, label: l.id === "off" ? "Never" : l.label }))
                    current: Config.clipsRecordLimit
                    onPicked: function (v) { Config.clipsRecordLimit = v }
                }
            }
            SettingRow {
                label:  Translation.tr("Name by game")
                detail: Config.clipsNameByWindow ? "Elden-Ring_Replay_… " : "The recorder's own names"
                help:   Translation.tr("Name a clip after the window you cut it in, so the library can group by game. A game under Steam, Proton ")
                      + "or Wine is named by its title, anything else by its program."
                Toggle {
                    checked: Config.clipsNameByWindow
                    onToggled: Config.clipsNameByWindow = !Config.clipsNameByWindow
                }
            }
        }

    }
}
