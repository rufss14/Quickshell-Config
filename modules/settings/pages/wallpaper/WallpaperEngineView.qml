pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperEngineView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
// ── ENGINE ──────────────────────────────────────────────────────
// The same cards: every switch is a tile whose line says what it does in the
// state it is in; sliders and the monitor table are cards.
Flickable {
    id: engFlick
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    anchors.fill: parent
    contentWidth: width
    contentHeight: engGrid.implicitHeight - engGrid.topTrim
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: page.view === "engine"

    opacity: page.view === "engine" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    BentoGrid {
        id: engGrid
        y: -engGrid.topTrim
        width: engFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
        bentoCols: page.colsFor(engFlick.width)
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingLg

            Section {
                span: 3
                glyph: "󰕧"
                title: Translation.tr("Renderer")
                subtitle: Translation.tr("Options apply on Refresh.")
                padding: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    BusyDot {
                        running: WallpaperEngine.busy
                        tint: WallpaperEngine.running ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).primary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: page.engineStatus
                        variant: "body"
                        elide: Text.ElideRight
                    }
                    PanelButton {
                        capsule: true
                        variant: "primary"; accent: Colors.of(QsWindow.window).primary; label: "Refresh"
                        visible: WallpaperEngine.needsRefresh
                        onActivated: WallpaperEngine.refresh()
                    }
                    PanelButton {
                        capsule: true
                        variant: "ghost"; symbol: "stop"; label: "Stop"
                        visible: WallpaperEngine.running && !WallpaperEngine.busy
                        onActivated: WallpaperEngine.stop()
                    }
                    PanelButton {
                        capsule: true
                        variant: "ghost"; symbol: "play_arrow"; label: "Start"
                        visible: !WallpaperEngine.running && !WallpaperEngine.busy
                                 && Config.wpeCurrent !== ""
                        enabled: page.blocked === ""
                        onActivated: WallpaperEngine.apply(Config.wpeCurrent)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WrapAnywhere
                    variant: "caption"
                    color: Colors.of(QsWindow.window).danger
                    visible: WallpaperEngine.lastError !== "" && !WallpaperEngine.busy
                    text: WallpaperEngine.lastError
                }
            }

            Section {
                span: 2
                glyph: "󰝟"
                title: Translation.tr("Playback & rendering")
                padding: Tokens.spacingMd

                Fader {
                    accent: Colors.of(QsWindow.window).primary
                    label: Translation.tr("Frame rate")
                    from: Config.wpeFpsMin; to: Config.wpeFpsMax
                    value: Config.wpeFps
                    readout: Config.wpeFps + " fps"
                    onCommit: function(v) { Config.wpeFps = v }
                }
                Fader {
                    accent: Colors.of(QsWindow.window).primary
                    label: Translation.tr("Volume")
                    from: 0; to: 100
                    value: Config.wpeVolume
                    readout: Config.wpeVolume + "%"
                    enabled: !Config.wpeMute
                    onCommit: function(v) { Config.wpeVolume = v }
                }
            }

            QuickToggleTile {
                roomy: true
                symbol: "speed"
                label:  Translation.tr("V-Sync")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeVsync
                subLabel: Config.wpeVsync ? "Frames wait for the display's refresh" : "Frames aren't synced to the display"
                onToggled: Config.wpeVsync = !Config.wpeVsync
            }

            QuickToggleTile {
                roomy: true
                symbol: "volume_off"
                label:  Translation.tr("Mute")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeMute
                subLabel: Config.wpeMute ? "Scenes are silent" : "Scenes play their sound"
                onToggled: Config.wpeMute = !Config.wpeMute
            }

            QuickToggleTile {
                roomy: true
                symbol: "volume_up"
                label:  Translation.tr("Keep audio")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeKeepAudio
                subLabel: Config.wpeKeepAudio ? "A scene keeps its sound over other apps' audio" : "A scene's sound yields to other audio"
                onToggled: Config.wpeKeepAudio = !Config.wpeKeepAudio
            }

            QuickToggleTile {
                roomy: true
                symbol: "equalizer"
                label:  Translation.tr("React to audio")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeAudioProcessing
                subLabel: Config.wpeAudioProcessing ? "Scenes animate to what is playing" : "Scenes ignore the audio"
                onToggled: Config.wpeAudioProcessing = !Config.wpeAudioProcessing
            }

            QuickToggleTile {
                roomy: true
                symbol: "mouse"
                label:  Translation.tr("Follow the mouse")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeMouse
                subLabel: Config.wpeMouse ? "Scenes react to the pointer" : "Scenes ignore the pointer"
                onToggled: Config.wpeMouse = !Config.wpeMouse
            }

            QuickToggleTile {
                roomy: true
                symbol: "layers"
                label:  Translation.tr("Parallax")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeParallax
                subLabel: Config.wpeParallax ? "The scene drifts with the pointer" : "The scene stays put"
                onToggled: Config.wpeParallax = !Config.wpeParallax
            }

            QuickToggleTile {
                roomy: true
                symbol: "auto_awesome"
                label:  Translation.tr("Particles")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeParticles
                subLabel: (WallpaperEngine.particlesAutoDisabledFor !== "" && WallpaperEngine.running)
                    ? "This scene crashed and was restarted with particles off. Turn on to try again"
                    : Config.wpeParticles ? "Particle effects are drawn — some scenes crash the renderer on them"
                    :                       "Off — the fix if a scene won't stay up"
                onToggled: Config.wpeParticles = !Config.wpeParticles
            }

            QuickToggleTile {
                roomy: true
                symbol: "fullscreen"
                label:  Translation.tr("Pause when fullscreen")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpePauseFullscreen
                subLabel: Config.wpePauseFullscreen ? "Rendering pauses while a window is fullscreen" : "Keeps rendering under fullscreen windows"
                onToggled: Config.wpePauseFullscreen = !Config.wpePauseFullscreen
            }

            QuickToggleTile {
                roomy: true
                symbol: "power_settings_new"
                label:  Translation.tr("Start with the shell")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeAutoStart
                subLabel: Config.wpeAutoStart ? "The last scene starts when the shell does" : "The renderer waits until you apply a scene"
                onToggled: Config.wpeAutoStart = !Config.wpeAutoStart
            }

            QuickToggleTile {
                roomy: true
                symbol: "palette"
                label:  Translation.tr("Scene colours")
                accent: Colors.of(QsWindow.window).primary
                active: Config.wpeScenePalette
                subLabel: Config.wpeScenePalette ? "The shell's colours come from the scene's preview" : "A scene doesn't change the shell's colours"
                onToggled: Config.wpeScenePalette = !Config.wpeScenePalette
            }

            Section {
                span: 3
                glyph: "󰍹"
                title: Translation.tr("Monitors")
                subtitle: Translation.tr("One scene per screen, or one spanned across several.")
                padding: Tokens.spacingMd
                visible: Quickshell.screens.length > 1

                StyledText { text: "Default plays on"; variant: "caption"; emphasis: "dim" }
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "", label: "All" }].concat(
                        Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                    current: Config.wpeTarget
                    onPicked: function(v) { Config.wpeTarget = v }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingLg

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        StyledText { text: "Default scaling"; variant: "caption"; emphasis: "dim" }
                        ChipRow {
                            accent: Colors.of(QsWindow.window).primary
                            model: [
                                { value: "default", label: "Default" },
                                { value: "fill",    label: "Fill" },
                                { value: "fit",     label: "Fit" },
                                { value: "stretch", label: "Stretch" }
                            ]
                            current: Config.wpeScaling
                            onPicked: function(v) { Config.wpeScaling = v }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        StyledText { text: "Default clamp"; variant: "caption"; emphasis: "dim" }
                        ChipRow {
                            accent: Colors.of(QsWindow.window).primary
                            model: [
                                { value: "clamp",  label: "Clamp" },
                                { value: "border", label: "Border" },
                                { value: "repeat", label: "Repeat" }
                            ]
                            current: Config.wpeClamp
                            onPicked: function(v) { Config.wpeClamp = v }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: Translation.tr("Pinning one monitor is also the cure for a scene whose ")
                        + "sound doubles across screens — one screen, one soundtrack."
                }

                Divider {}

                // ── Per-monitor overrides ─────────────────────────
                // A screen with no override here plays the default
                // scene above. "Span" turns the per-row Choose…
                // buttons into an Include/Included toggle: pick two
                // or more, then choose one scene once to stretch
                // across all of them.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Per-monitor scenes")
                        variant: "body"
                        font.weight: Font.DemiBold
                    }
                    PanelButton {
                        capsule: true
                        variant: page.monitorSpanMode ? "primary" : "ghost"
                        accent: Colors.of(QsWindow.window).primary
                        label: Translation.tr("Span")
                        onActivated: {
                            page.monitorSpanMode = !page.monitorSpanMode
                            page.pickingScreens = []
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: Quickshell.screens
                        delegate: RowLayout {
                            id: monRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            readonly property string screenName: monRow.modelData.name
                            readonly property string assignedId:
                                WallpaperEngine.monitorFor(monRow.screenName)
                            readonly property bool spanned: (Config.wpeMonitors || [])
                                .some(m => m.screens.indexOf(monRow.screenName) !== -1
                                        && m.screens.length > 1)
                            readonly property bool included:
                                page.pickingScreens.indexOf(monRow.screenName) !== -1

                            StyledText {
                                Layout.preferredWidth: 90
                                text: monRow.screenName
                                variant: "caption"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                text: WallpaperEngine.assignmentLabel(monRow.screenName)
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                            PanelButton {
                                capsule: true
                                visible: !page.monitorSpanMode
                                    && (monRow.assignedId !== "" || monRow.spanned)
                                variant: "ghost"
                                label: Translation.tr("Default")
                                onActivated: WallpaperEngine.unassignMonitor(monRow.screenName)
                            }
                            PanelButton {
                                capsule: true
                                visible: !page.monitorSpanMode
                                variant: "normal"
                                label: Translation.tr("Choose…")
                                onActivated: {
                                    page.pickingForScreen = monRow.screenName
                                    page.source = "engine"
                                    page.view = "gallery"
                                }
                            }
                            PanelButton {
                                capsule: true
                                visible: page.monitorSpanMode
                                variant: monRow.included ? "primary" : "ghost"
                                accent: Colors.of(QsWindow.window).primary
                                label: monRow.included ? "Included" : "Include"
                                onActivated: {
                                    page.pickingScreens = monRow.included
                                        ? page.pickingScreens.filter(s => s !== monRow.screenName)
                                        : page.pickingScreens.concat([monRow.screenName])
                                }
                            }
                        }
                    }
                }

                PanelButton {
                    capsule: true
                    Layout.alignment: Qt.AlignHCenter
                    visible: page.monitorSpanMode
                    variant: "primary"
                    accent: Colors.of(QsWindow.window).primary
                    label: "Choose a scene for " + page.pickingScreens.length + " screens"
                    enabled: page.pickingScreens.length >= 2
                    onActivated: {
                        page.source = "engine"
                        page.view = "gallery"
                    }
                }
            }


            Section {
                span: 3
                glyph: "󰉋"
                title: Translation.tr("Library")
                subtitle: Translation.tr("Blank = the default folder.")
                padding: Tokens.spacingMd

                // Committed rather than live: every change rescans, and
                // doing that per keystroke fires a `find` for every prefix.
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: "~/wallpapers/walls"
                    seed: Config.wallLibraryDir
                    onCommitted: function(value) { Config.wallLibraryDir = value.trim() }
                }
                StyledText {
                    Layout.fillWidth: true
                    variant: "caption"
                    emphasis: "dim"
                    // env("HOME") is a QVariant, undefined when unset —
                    // String.replace(undefined, …) matches the literal
                    // "undefined", so guard and skip the substitution.
                    text: {
                        const home = Quickshell.env("HOME") || ""
                        const dir  = Wallpaper.libraryDir
                        return Wallpaper.wallpapers.length + " images · "
                             + (home ? dir.replace(home, "~") : dir)
                    }
                }
            }
    }
}
