pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/clips.js" as ClipsJs

// ── ClipsPage — Apps & tools › Clips ──────────────────────────────────────────
// gpu-screen-recorder's settings: the replay buffer behind "clip it", recording, and
// what a clip is made of. services/Clips owns the recorder; this shows and sets.
//
// ── Laid out by job, as grouped rows ──────────────────────────────────────────
// The recorder's buttons first (what is happening now: one row of tools, not a hero, because
// the page has no picture to show), then what is captured, how far back a clip reaches, the
// picture's quality, the files, and what happens after a save. The master switch stays in the
// header. A paragraph under a group is its tip. The most technical page in Settings, so it
// is allowed to run long.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    ArmLatch {
        id: pruneLatch
        onConfirmed: Clips.prune()
    }
    ArmLatch {
        id: forgetLatch
        onConfirmed: Clips.forgetContexts()
    }

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

    // The two-segment connected choices (quality or bitrate, memory or disk), with their icons.
    readonly property int choiceWidth: Tokens.fieldHeight * 8

    // A connected choice's width for n labelled segments: every value stays named, and in a
    // column too narrow for it SettingRow drops the strip under the label at full width.
    function stripW(n) { return Tokens.fieldHeight * 2.6 * n }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "\u{F0567}"
        title:     Translation.tr("Clips")
        titleTail: Translation.tr("& recording")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.clips ? Translation.tr("Off")
                 : root.blocked !== "" ? root.blocked
                 : [Clips.mode === "record" ? Translation.tr("Recording")
                    : Config.clipsBuffer ? Translation.tr("Clipping on") : Translation.tr("Clipping off"),
                    Translation.tr("%1 buffer").arg(ClipsJs.span(Clips.bufferSeconds)),
                    ClipsJs.summary(Clips.opts)].join("  ·  ")

        // The master switch names itself and says which way it is set.
        actions: [
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Config.clips ? Translation.tr("Clips on") : Translation.tr("Clips off")
                variant: "label"
                emphasis: "dim"
            },
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                accessibleName: Translation.tr("Clips")
                checked: Config.clips
                onToggled: Config.sidebarToggle("clips")
            }
        ]

        // ══ Now ═══════════════════════════════════════════════════════════════
        Section {
            grouped: true
            // The buttons are one line at this width and the rest are columns beneath them.
            fullRow: true
            enabled: Config.clips
            opacity: Config.clips ? 1 : 0.5
            symbol:  "replay"
            title:   Translation.tr("Recorder")
            subtitle: root.blocked !== "" ? root.blocked
                    : Clips.recording ? Translation.tr("Recording")
                    : Clips.buffering ? Translation.tr("Clipping. Alt+F10 saves the last %1").arg(ClipsJs.span(Clips.bufferSeconds))
                    : Translation.tr("Idle")
            help: Translation.tr("Clipping keeps a replay buffer running, across reloads and reboots, so Alt+F10 always has something to save. ")
                + Translation.tr("Alt+Shift+F10 turns clipping on and off, Alt+F9 records, Alt+Shift+F9 records a region (which pauses clipping while it runs). ")
                + Translation.tr("Settings below are startup arguments: they apply when the buffer restarts.")

            // One segment of tools. A Flow, so the two quiet actions wrap under the four main
            // ones in a narrow window instead of running off the card.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                PanelButton {
                    capsule: true
                    variant: Config.clipsBuffer ? "primary" : "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "replay"
                    label: Config.clipsBuffer ? Translation.tr("Clipping on") : Translation.tr("Clipping off")
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
                    label: Clips.recording ? Translation.tr("Stop") : Translation.tr("Record")
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
                    variant: "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "restart_alt"
                    label: Translation.tr("Restart")
                    onActivated: Clips.restartBuffer()
                }
                PanelButton {
                    capsule: true
                    variant: "normal"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "video_library"
                    label: Translation.tr("Gallery")
                    enabled: Config.clips
                    onActivated: Clips.openGallery()
                }
            }
            // The install line for a missing recorder.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.blocked !== ""
                text: "sudo pacman -S gpu-screen-recorder"
                variant: "caption"
                font.family: Tokens.fontMono
                emphasis: "dim"
                wrapMode: Text.WordWrap
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
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "monitor"
            title:   Translation.tr("Capture")
            help:    Translation.tr("Focused follows whichever monitor you're on when it starts. Portal asks once through the desktop portal and remembers.")

            SettingRow {
                label:  Translation.tr("Screen")
                detail: Translation.tr("Which monitor is recorded")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "", label: Translation.tr("Focused") }]
                           .concat(Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                           .concat([{ value: "portal", label: Translation.tr("Portal") }])
                    current: Config.clipsTarget
                    onPicked: function (v) { Config.clipsTarget = v }
                }
            }

            // What goes into the file besides the picture: a set, so chips, on the row's right.
            SettingRow {
                label:  Translation.tr("Include")
                detail: Translation.tr("Besides the picture")
                Flow {
                    spacing: Tokens.spacingSm
                    ToggleChip {
                        symbol: "volume_up"
                        label:  Translation.tr("Desktop audio")
                        hint:   Translation.tr("What you hear: the default output.")
                        active: Config.clipsDesktopAudio
                        onToggled: Config.clipsDesktopAudio = !Config.clipsDesktopAudio
                    }
                    ToggleChip {
                        symbol: "mic"
                        label:  Translation.tr("Microphone")
                        hint:   Translation.tr("Your voice: the default input.")
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
            }

            // The trap this names: with it on, the mic is recorded but UNHEARD almost
            // everywhere: players, browsers and Discord play only track 1.
            SettingRow {
                rowTap: true
                enabled: Config.clipsDesktopAudio && Config.clipsMic
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Separate tracks")
                detail: Config.clipsSplitAudio ? Translation.tr("Mic on its own track, editors only") : Translation.tr("One mixed track, heard everywhere")
                help:   Translation.tr("On, the mic gets a track of its own, for editing. Players, browsers and Discord play only the first track, so export with Mixed audio to share.")
                onTapped: Config.clipsSplitAudio = !Config.clipsSplitAudio
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsSplitAudio
                    onToggled: Config.clipsSplitAudio = !Config.clipsSplitAudio
                }
            }
        }

        // ══ The buffer ════════════════════════════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "history"
            title:   Translation.tr("Replay buffer")
            subtitle: root.ramMiB > 0
                ? (Config.clipsStorage === "disk" ? Translation.tr("About %1 MiB in a temp file") : Translation.tr("About %1 MiB in memory")).arg(root.ramMiB)
                : Translation.tr("Size follows what's on screen")
            help:    Translation.tr("How far back a clip can reach. In quality mode its size follows what's on screen; bitrate mode fixes it.")

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
            SettingRow {
                label:  Translation.tr("A clip keeps")
                detail: Translation.tr("The newest part of the buffer")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: Translation.tr("All") }]
                           .concat([10, 30, 60, 300, 600]
                                   .filter(n => n < Clips.bufferSeconds)
                                   .map(n => ({ value: n, label: ClipsJs.span(n) })))
                    current: Config.clipsSaveSeconds < Clips.bufferSeconds ? Config.clipsSaveSeconds : 0
                    onPicked: function (v) { Config.clipsSaveSeconds = v }
                }
            }

            SettingRow {
                label: Translation.tr("Stored")
                help:  Translation.tr("Memory is the fastest. A temp file on disk spares RAM for a long buffer.")

                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.choiceWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "ram",  label: Translation.tr("In memory"), icon: "memory" },
                            { value: "disk", label: Translation.tr("On disk"),   icon: "hard_drive" }]
                    current: Config.clipsStorage
                    onPicked: function (v) { Config.clipsStorage = v }
                }
            }
        }

        // ══ Quality ═══════════════════════════════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "tune"
            title:   Translation.tr("Quality")
            subtitle: Config.clipsBitrateMode === "cbr" ? Translation.tr("Predictable file size") : Translation.tr("Sharp in motion, size varies")
            help:    Translation.tr("Constant quality stays sharp in motion and its size varies. A fixed bitrate gives a predictable file and buffer size.")

            SettingRow {
                label: Translation.tr("Mode")

                TabStrip {
                    connected: true
                    implicitWidth: root.choiceWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "auto", label: Translation.tr("Quality"), icon: "tune" },
                            { value: "cbr",  label: Translation.tr("Bitrate"), icon: "speed" }]
                    current: Config.clipsBitrateMode === "cbr" ? "cbr" : "auto"
                    onPicked: function (v) { Config.clipsBitrateMode = v }
                }
            }
            SettingRow {
                visible: Config.clipsBitrateMode !== "cbr"
                label: Translation.tr("Level")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "medium", label: Translation.tr("Medium") }, { value: "high", label: Translation.tr("High") },
                            { value: "very_high", label: Translation.tr("Very high") }, { value: "ultra", label: Translation.tr("Ultra") }]
                    current: Clips.settings.quality
                    onPicked: function (v) { Config.clipsQuality = v }
                }
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
            SettingRow {
                label: Translation.tr("Resolution")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "original", label: Translation.tr("Native") }, { value: "1440", label: "1440p" },
                            { value: "1080", label: "1080p" }, { value: "720", label: "720p" }]
                    current: Clips.settings.resolution
                    onPicked: function (v) { Config.clipsResolution = v }
                }
            }
            SettingRow {
                label: Translation.tr("Frame rate")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [30, 60, 120, 144, 165, 240].map(n => ({ value: n, label: String(n) }))
                    current: Clips.settings.fps
                    onPicked: function (v) { Config.clipsFps = v }
                }
            }
        }

        // ══ Format and where it lands ═══════════════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "folder"
            title:   Translation.tr("Files")
            subtitle: Translation.tr("%1 in %2")
                      .arg(Clips.settings.codec === "auto" ? "H.264" : String(Clips.settings.codec).toUpperCase())
                      .arg(String(Clips.settings.container).toUpperCase())
            help:    Translation.tr("H.264 in MP4 plays everywhere (Discord and browsers don't play HEVC); Auto picks H.264. MKV survives a crash mid-recording; MP4 doesn't. ")
                   + Translation.tr("Clips, recordings and trims all land in the folder; deleting from the gallery moves a clip to the trash.")

            SettingRow {
                label: Translation.tr("Codec")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "auto", label: Translation.tr("Auto") }, { value: "h264", label: "H.264" },
                            { value: "hevc", label: "HEVC" }, { value: "av1", label: "AV1" }]
                    current: Clips.settings.codec
                    onPicked: function (v) { Config.clipsCodec = v }
                }
            }
            SettingRow {
                label: Translation.tr("Container")
                TabStrip {
                    connected: true
                    implicitWidth: root.choiceWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "mp4", label: "MP4" }, { value: "mkv", label: "MKV" }]
                    current: Clips.settings.container
                    onPicked: function (v) { Config.clipsContainer = v }
                }
            }

            // "Open folder" and "show in folder" open in a file manager, never the default handler (which can
            // be a terminal browser). Automatic = Nautilus when it is installed.
            SettingRow {
                label: Translation.tr("File manager")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "", label: Translation.tr("Auto") }].concat(ClipsJs.FILE_MANAGERS
                               .filter(f => Clips.fileManagers.indexOf(f.id) >= 0)
                               .map(f => ({ value: f.id, label: f.label })))
                    current: Config.clipsFileManager
                    onPicked: function (v) { Config.clipsFileManager = v }
                }
            }
            SettingRow {
                label: Translation.tr("Folder")
                InputField {
                    cornerRadius: implicitHeight / 2
                    implicitWidth: Tokens.fieldHeight * 8
                    mono: true
                    seed: Config.clipsDir
                    placeholder: "~/Videos/Clips"
                    onCommitted: function (v) { Config.clipsDir = v.trim() }
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Peek")
                detail: Config.clipsPeek ? Translation.tr("A card with its thumbnail") : Translation.tr("Nothing shows after a save")
                help:   Translation.tr("A saved clip opens a card beside the sidebar button for a moment, with its thumbnail.")
                onTapped: Config.clipsPeek = !Config.clipsPeek
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsPeek
                    onToggled: Config.clipsPeek = !Config.clipsPeek
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Notify")
                detail: Config.clipsNotify ? Translation.tr("A notification per clip") : Translation.tr("Saved quietly")
                help:   Translation.tr("Also send a notification per saved clip, for when the sidebar is hidden.")
                onTapped: Config.clipsNotify = !Config.clipsNotify
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsNotify
                    onToggled: Config.clipsNotify = !Config.clipsNotify
                }
            }
        }

        // ══ When you clip, and when you record ═════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "movie"
            title:   Translation.tr("Clip & record")
            subtitle: (Config.clipsAhead > 0 ? Translation.tr("+%1s after a clip").arg(Config.clipsAhead) : Translation.tr("Clips save at once"))
                      + (Config.clipsRecordLimit !== "off" ? " · " + Translation.tr("stops after %1").arg(ClipsJs.limitOf(Config.clipsRecordLimit).label) : "")
            help:    Translation.tr("Keep recording a few seconds after you press Clip it, so a play you only reacted to afterwards is in the clip. ")
                   + Translation.tr("It only applies to the button; the Alt+F10 keybind always saves at once. A recording stops by itself at its limit.")

            SettingRow {
                label: Translation.tr("After a clip")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: Translation.tr("At once") }, { value: 10, label: "+10s" },
                            { value: 20, label: "+20s" }, { value: 30, label: "+30s" }]
                    current: Config.clipsAhead
                    onPicked: function (v) { Config.clipsAhead = v }
                }
            }
            SettingRow {
                label: Translation.tr("Stop a recording")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: ClipsJs.RECORD_LIMITS.map(l => ({ value: l.id, label: l.id === "off" ? Translation.tr("Never") : l.label }))
                    current: Config.clipsRecordLimit
                    onPicked: function (v) { Config.clipsRecordLimit = v }
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Name by game")
                detail: Config.clipsNameByWindow ? "Elden-Ring_Replay_…" : Translation.tr("The recorder's own names")
                help:   Translation.tr("Name a clip after the window you cut it in, so the library can group by game. A game under Steam, Proton ")
                      + Translation.tr("or Wine is named by its title, anything else by its program.")
                onTapped: Config.clipsNameByWindow = !Config.clipsNameByWindow
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsNameByWindow
                    onToggled: Config.clipsNameByWindow = !Config.clipsNameByWindow
                }
            }
        }

        // ══ Sharing ═══════════════════════════════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "ios_share"
            title:   Translation.tr("Share")
            subtitle: Translation.tr("Discord upload size and what a clip remembers")
            help:    Translation.tr("Send to Discord shrinks a clip that is over the upload cap, then copies it. A saved clip can remember the song that was playing and who was in your Discord call.")

            SettingRow {
                label: Translation.tr("Discord upload cap")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: ClipsJs.DISCORD_CAPS.map(c => ({ value: c, label: c + " MB" }))
                    current: Config.clipsDiscordMB
                    onPicked: function (v) { Config.clipsDiscordMB = v }
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Remember the song")
                detail: Config.clipsStampMusic ? Translation.tr("A clip knows what was playing") : Translation.tr("Clips carry no song")
                help:   Translation.tr("Stamp a saved clip with the song your media player was playing (Spotify included). It shows in the library and can be searched.")
                onTapped: Config.clipsStampMusic = !Config.clipsStampMusic
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsStampMusic
                    onToggled: Config.clipsStampMusic = !Config.clipsStampMusic
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Remember who was in the call")
                detail: Config.clipsStampCall ? Translation.tr("Names of people in your Discord call") : Translation.tr("Clips carry no names")
                help:   Translation.tr("Stamp a saved clip with the names of the people in your Discord voice channel. The names are written to a file in your state folder; they are never sent anywhere.")
                onTapped: Config.clipsStampCall = !Config.clipsStampCall
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.clipsStampCall
                    onToggled: Config.clipsStampCall = !Config.clipsStampCall
                }
            }
            SettingRow {
                label:  Translation.tr("Forget what clips remember")
                detail: Translation.tr("%1 stamped").arg(Object.keys(Clips.contexts).length)
                PanelButton {
                    capsule: true
                    label: forgetLatch.armed ? Translation.tr("Sure?") : Translation.tr("Forget")
                    variant: forgetLatch.armed ? "primary" : "ghost"
                    accent: Colors.of(QsWindow.window).danger
                    enabled: Object.keys(Clips.contexts).length > 0
                    onActivated: forgetLatch.trigger()
                }
            }
        }

        // ══ Keeping the library in check ══════════════════════════════════════
        Section {
            grouped: true
            enabled: Config.clips
            opacity: enabled ? 1 : 0.5
            symbol:  "delete"
            title:   Translation.tr("Clean-up")
            subtitle: Translation.tr("Only when you press the button")
            help:    Translation.tr("Clean-up only ever trashes what these limits name, never a favourite, and only when you press the button.")

            SettingRow {
                label: Translation.tr("Older than")
                TabStrip {
                    connected: true
                    implicitWidth: root.stripW(4)
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: Translation.tr("Never") }, { value: 30, label: Translation.tr("30 days") },
                            { value: 60, label: Translation.tr("60 days") }, { value: 90, label: Translation.tr("90 days") }]
                    current: Config.clipsPruneDays
                    onPicked: function (v) { Config.clipsPruneDays = v }
                }
            }
            SettingRow {
                label: Translation.tr("Library over")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: 0, label: Translation.tr("No limit") }, { value: 10, label: "10 GB" }, { value: 50, label: "50 GB" },
                            { value: 100, label: "100 GB" }, { value: 250, label: "250 GB" }]
                    current: Config.clipsPruneGB
                    onPicked: function (v) { Config.clipsPruneGB = v }
                }
            }
            SettingRow {
                label:  Translation.tr("Clean up now")
                detail: Clips.prunePreview.count > 0
                        ? Translation.tr("%1 clips would go to the trash (%2)").arg(Clips.prunePreview.count).arg(ClipsJs.bytesText(Clips.prunePreview.bytes))
                        : Translation.tr("Nothing the limits name")
                PanelButton {
                    capsule: true
                    label: pruneLatch.armed ? Translation.tr("Sure?") : Translation.tr("Clean up")
                    variant: pruneLatch.armed ? "primary" : "ghost"
                    accent: Colors.of(QsWindow.window).warning
                    enabled: Clips.prunePreview.count > 0
                    onActivated: pruneLatch.trigger()
                }
            }
        }
    }
}
