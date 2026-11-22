pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../.."

// ── WallpaperEngineView — Wallpaper › Scenes ──────────────────────────────────
// The rail page `WallpaperPage.qml#scenes`: the linux-wallpaperengine renderer, every
// launch option, the monitors, and where the image library lives. Grouped rows
// (docs/settings-style.md §1.6) in balanced columns under a hero: the scene the renderer plays,
// with its Start / Stop / Refresh (WallpaperNowCard). Reads and writes the page's state
// through `page` (WallpaperPage.qml's root), which shows this while `page.view === "scenes"`.
//
// The renderer has no IPC, so every option here is a launch argument collected and spent
// by one Refresh (docs/wallpaper-and-wave.md). The hero's Start / Stop / Refresh are the
// page's only ones: the gallery's header does not repeat them.
SettingsPage {
    id: view
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page

    anchors.fill: parent
    // Disabled while hidden: SettingsPage.reveal() answers only an enabled page, so a hidden
    // view never consumes a search hit meant for the one on show. Turning on reveals it.
    enabled: page.view === "scenes"
    onEnabledChanged: if (view.enabled) view.reveal()
    opacity: page.view === "scenes" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity {
        enabled: view.page.viewMotion
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // A connected group of four (scaling) and three (clamp) named segments.
    readonly property int choiceWidth: Tokens.fieldHeight * 9

    // A pick the gallery finishes comes back here (WallpaperPage.beginPick / endPick).
    function pickInGallery() {
        view.page.source = "engine"
        view.page.beginPick("WallpaperPage.qml#scenes")
    }

    grouped:     true
    headerShape: "clover"
    glyph:       "\u{F0567}"
    title:       Translation.tr("Wallpaper")
    titleTail:   Translation.tr("Scenes")
    accent:      Colors.of(QsWindow.window).primary
    subtitle:    WallpaperEngine.blocker() !== "" ? WallpaperEngine.blocker() : view.page.engineStatus

    // ══ What the renderer is playing ══════════════════════════════════════════
    // The scene, and the renderer's Start / Stop / Refresh. Its state is the header's line.
    WallpaperNowCard { page: view.page; renderer: true }

    // The groups below pair up in columns: speed, sound, and how a scene answers you.
    // ══ Performance ═══════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "speed"
        title:   Translation.tr("Performance")
        help:    Translation.tr("Options apply on Refresh.")

        Fader {
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Frame rate")
            from: Config.wpeFpsMin; to: Config.wpeFpsMax
            value: Config.wpeFps
            readout: Config.wpeFps + " fps"
            onCommit: function(v) { Config.wpeFps = v }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("V-Sync")
            detail: Config.wpeVsync ? "Frames wait for the display's refresh" : "Frames aren't synced to the display"
            onTapped: Config.wpeVsync = !Config.wpeVsync
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeVsync
                onToggled: Config.wpeVsync = !Config.wpeVsync
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Pause when fullscreen")
            detail: Config.wpePauseFullscreen ? "Rendering pauses while a window is fullscreen" : "Keeps rendering under fullscreen windows"
            onTapped: Config.wpePauseFullscreen = !Config.wpePauseFullscreen
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpePauseFullscreen
                onToggled: Config.wpePauseFullscreen = !Config.wpePauseFullscreen
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Particles")
            wrapDetail: WallpaperEngine.particlesAutoDisabledFor !== "" && WallpaperEngine.running
            detail: (WallpaperEngine.particlesAutoDisabledFor !== "" && WallpaperEngine.running)
                ? Translation.tr("This scene crashed and was restarted with particles off. Turn on to try again")
                : Config.wpeParticles ? Translation.tr("Particle effects are drawn. Some scenes crash the renderer on them")
                :                       Translation.tr("Particle effects are skipped, which stops those crashes")
            onTapped: Config.wpeParticles = !Config.wpeParticles
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeParticles
                onToggled: Config.wpeParticles = !Config.wpeParticles
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Start with the shell")
            detail: Config.wpeAutoStart ? "The last scene starts when the shell does" : "The renderer waits until you apply a scene"
            onTapped: Config.wpeAutoStart = !Config.wpeAutoStart
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeAutoStart
                onToggled: Config.wpeAutoStart = !Config.wpeAutoStart
            }
        }
    }

    // ══ Sound ═════════════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "volume_up"
        title:   Translation.tr("Sound")

        Fader {
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Volume")
            from: 0; to: 100
            value: Config.wpeVolume
            readout: Config.wpeVolume + "%"
            enabled: !Config.wpeMute
            opacity: enabled ? 1 : 0.4
            onCommit: function(v) { Config.wpeVolume = v }
        }

        SettingRow {
            rowTap: true
            label:  Translation.tr("Mute")
            detail: Config.wpeMute ? "Scenes are silent" : "Scenes play their sound"
            onTapped: Config.wpeMute = !Config.wpeMute
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeMute
                onToggled: Config.wpeMute = !Config.wpeMute
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Keep audio")
            detail: Config.wpeKeepAudio ? "A scene keeps its sound over other apps' audio" : "A scene's sound yields to other audio"
            onTapped: Config.wpeKeepAudio = !Config.wpeKeepAudio
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeKeepAudio
                onToggled: Config.wpeKeepAudio = !Config.wpeKeepAudio
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("React to audio")
            detail: Config.wpeAudioProcessing ? "Scenes animate to what is playing" : "Scenes ignore the audio"
            onTapped: Config.wpeAudioProcessing = !Config.wpeAudioProcessing
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeAudioProcessing
                onToggled: Config.wpeAudioProcessing = !Config.wpeAudioProcessing
            }
        }
    }

    // ══ Interaction and colour ════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "tune"
        title:   Translation.tr("Interaction and colour")

        SettingRow {
            rowTap: true
            label:  Translation.tr("Follow the mouse")
            detail: Config.wpeMouse ? "Scenes react to the pointer" : "Scenes ignore the pointer"
            onTapped: Config.wpeMouse = !Config.wpeMouse
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeMouse
                onToggled: Config.wpeMouse = !Config.wpeMouse
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Parallax")
            detail: Config.wpeParallax ? "The scene drifts with the pointer" : "The scene stays put"
            onTapped: Config.wpeParallax = !Config.wpeParallax
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeParallax
                onToggled: Config.wpeParallax = !Config.wpeParallax
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Scene colours")
            detail: Config.wpeScenePalette ? "The shell's colours come from the scene's preview" : "A scene doesn't change the shell's colours"
            onTapped: Config.wpeScenePalette = !Config.wpeScenePalette
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpeScenePalette
                onToggled: Config.wpeScenePalette = !Config.wpeScenePalette
            }
        }
        // Scenes that workspaces own, and the shared scene, play in windows the shell
        // captures (services/ScenePreload), which is what lets the pointer move them.
        SettingRow {
            rowTap: true
            label:  Translation.tr("Play scenes through the shell")
            detail: Config.wpePreload ? Translation.tr("Parallax follows the pointer anywhere, workspace switches are instant")
                                      : Translation.tr("The scene's own renderer plays them")
            help:   Translation.tr("On, each scene keeps using the GPU while it waits. Off, a scene's own parallax works only over a bare desktop.")
            onTapped: Config.wpePreload = !Config.wpePreload
            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wpePreload
                onToggled: Config.wpePreload = !Config.wpePreload
            }
        }
    }

    // ══ Monitors ══════════════════════════════════════════════════════════════
    // A screen with no override plays the default scene. "Span" turns the per-row Choose…
    // buttons into an Include/Included toggle: pick two or more, then choose one scene once
    // to stretch across all of them. Either pick happens in the gallery and comes back here.
    Section {
        grouped: true
        visible: Quickshell.screens.length > 1
        symbol:  "monitor"
        title:   Translation.tr("Monitors")
        help:    Translation.tr("One scene per screen, or one spanned across several.")
               + " " + Translation.tr("Pinning one monitor is also the cure for a scene whose ")
               + "sound doubles across screens: one screen, one soundtrack."
        subtitle: Config.wpeTarget === "" ? Translation.tr("Every screen") : Config.wpeTarget

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            SettingRow { label: Translation.tr("Default plays on") }
            ChipRow {
                Layout.fillHeight: false
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "", label: "All" }].concat(
                    Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                current: Config.wpeTarget
                onPicked: function(v) { Config.wpeTarget = v }
            }
        }

        SettingRow {
            label: Translation.tr("Default scaling")
            TabStrip {
                connected: true
                implicitWidth: view.choiceWidth
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
        SettingRow {
            label: Translation.tr("Default clamp")
            TabStrip {
                connected: true
                implicitWidth: view.choiceWidth
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

        SettingRow {
            label:  Translation.tr("Per-monitor scenes")
            detail: view.page.monitorSpanMode ? Translation.tr("Include two or more, then choose one scene")
                                              : Translation.tr("Choose a scene for one screen")
            PanelButton {
                capsule: true
                variant: view.page.monitorSpanMode ? "primary" : "ghost"
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Span")
                onActivated: {
                    view.page.monitorSpanMode = !view.page.monitorSpanMode
                    view.page.pickingScreens = []
                }
            }
        }

        Repeater {
            model: Quickshell.screens
            delegate: SettingRow {
                id: monRow
                required property var modelData

                readonly property string screenName: monRow.modelData.name
                readonly property string assignedId:
                    WallpaperEngine.monitorFor(monRow.screenName)
                readonly property bool spanned: (Config.wpeMonitors || [])
                    .some(m => m.screens.indexOf(monRow.screenName) !== -1
                            && m.screens.length > 1)
                readonly property bool included:
                    view.page.pickingScreens.indexOf(monRow.screenName) !== -1

                label:  monRow.screenName
                detail: WallpaperEngine.assignmentLabel(monRow.screenName)

                RowLayout {
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    PanelButton {
                        capsule: true
                        visible: !view.page.monitorSpanMode
                            && (monRow.assignedId !== "" || monRow.spanned)
                        variant: "ghost"
                        label: Translation.tr("Default")
                        onActivated: WallpaperEngine.unassignMonitor(monRow.screenName)
                    }
                    PanelButton {
                        capsule: true
                        visible: !view.page.monitorSpanMode
                        variant: "normal"
                        label: Translation.tr("Choose…")
                        onActivated: {
                            view.page.dropPick()
                            view.page.pickingForScreen = monRow.screenName
                            view.pickInGallery()
                        }
                    }
                    PanelButton {
                        capsule: true
                        visible: view.page.monitorSpanMode
                        variant: monRow.included ? "primary" : "ghost"
                        accent: Colors.of(QsWindow.window).primary
                        label: monRow.included ? "Included" : "Include"
                        onActivated: {
                            view.page.pickingScreens = monRow.included
                                ? view.page.pickingScreens.filter(s => s !== monRow.screenName)
                                : view.page.pickingScreens.concat([monRow.screenName])
                        }
                    }
                }
            }
        }

        PanelButton {
            capsule: true
            Layout.alignment: Qt.AlignHCenter
            visible: view.page.monitorSpanMode
            variant: "primary"
            accent: Colors.of(QsWindow.window).primary
            label: "Choose a scene for " + view.page.pickingScreens.length + " screens"
            enabled: view.page.pickingScreens.length >= 2
            onActivated: view.pickInGallery()
        }
    }

    // ══ Library ═══════════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "folder"
        title:   Translation.tr("Library")
        help:    Translation.tr("Blank = the default folder.")
        subtitle: Wallpaper.wallpapers.length + " images"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

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
                elide: Text.ElideMiddle
                // env("HOME") is a QVariant, undefined when unset —
                // String.replace(undefined, …) matches the literal
                // "undefined", so guard and skip the substitution.
                text: {
                    const home = Quickshell.env("HOME") || ""
                    const dir  = Wallpaper.libraryDir
                    return home ? dir.replace(home, "~") : dir
                }
            }
        }
    }
}
