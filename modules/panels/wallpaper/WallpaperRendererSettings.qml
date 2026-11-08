import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// The page's system column, at panel width. Every row here is a
// linux-wallpaperengine LAUNCH argument — the renderer has no IPC, so
// changing one is a relaunch. That's why nothing applies on the spot:
// a change is collected and the toolbar's Refresh spends the one
// restart, so fps + volume + monitor together cost one flicker, not three.
Item {
    required property var panel

    Flickable {
        id: settingsPane
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: settingsCol
            width: settingsPane.width
            spacing: Tokens.spacingSm

            // The renderer's dying words — the tail of its own log.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: WallpaperEngine.lastError !== "" && !WallpaperEngine.busy
                text: WallpaperEngine.lastError
                variant: "caption"
                color: Colors.of(QsWindow.window).danger
                wrapMode: Text.WrapAnywhere
            }

            WallpaperOptionRow {
                label: Translation.tr("Scene colours")
                detail: Translation.tr("Recolour the shell from the scene's preview")
                checked: Config.wpeScenePalette
                onToggled: Config.wpeScenePalette = !Config.wpeScenePalette
            }
            WallpaperOptionRow {
                label: Translation.tr("Start with the shell")
                checked: Config.wpeAutoStart
                onToggled: Config.wpeAutoStart = !Config.wpeAutoStart
            }

            Divider {}

            SliderRow {
                label: Translation.tr("Frame rate")
                from:  Config.wpeFpsMin
                to:    Config.wpeFpsMax
                value: Config.wpeFps
                readout: Config.wpeFps + " fps"
                numberWidth: 50
                onCommit: function(v) { Config.wpeFps = v }
            }
            WallpaperOptionRow {
                label: Translation.tr("V-Sync")
                detail: Translation.tr("Stops tearing, through the graphics driver")
                checked: Config.wpeVsync
                onToggled: Config.wpeVsync = !Config.wpeVsync
            }

            Divider {}

            SliderRow {
                label: Translation.tr("Volume")
                from:  0
                to:    100
                value: Config.wpeVolume
                readout: Config.wpeVolume + "%"
                numberWidth: 50
                enabled: !Config.wpeMute
                onCommit: function(v) { Config.wpeVolume = v }
            }
            WallpaperOptionRow {
                label: Translation.tr("Mute")
                checked: Config.wpeMute
                onToggled: Config.wpeMute = !Config.wpeMute
            }
            WallpaperOptionRow {
                label: Translation.tr("Keep audio with other apps")
                detail: Translation.tr("Off: the wallpaper silences itself whenever anything ")
                      + "else plays a sound"
                checked: Config.wpeKeepAudio
                onToggled: Config.wpeKeepAudio = !Config.wpeKeepAudio
            }
            WallpaperOptionRow {
                label: Translation.tr("React to audio")
                checked: Config.wpeAudioProcessing
                onToggled: Config.wpeAudioProcessing = !Config.wpeAudioProcessing
            }

            Divider {}

            WallpaperOptionRow {
                label: Translation.tr("Follow the mouse")
                checked: Config.wpeMouse
                onToggled: Config.wpeMouse = !Config.wpeMouse
            }
            WallpaperOptionRow {
                label: Translation.tr("Parallax")
                checked: Config.wpeParallax
                onToggled: Config.wpeParallax = !Config.wpeParallax
            }
            WallpaperOptionRow {
                label: Translation.tr("Particles")
                detail: Translation.tr("Some scenes crash the renderer on these — off is the fix.")
                checked: Config.wpeParticles
                onToggled: Config.wpeParticles = !Config.wpeParticles
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                wrapMode: Text.WordWrap
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                visible: WallpaperEngine.particlesAutoDisabledFor !== ""
                      && WallpaperEngine.running
                text: Translation.tr("This scene crashed and was restarted with particles off ")
                    + "automatically."
            }
            WallpaperOptionRow {
                label: Translation.tr("Pause when fullscreen")
                checked: Config.wpePauseFullscreen
                onToggled: Config.wpePauseFullscreen = !Config.wpePauseFullscreen
            }

            // ── Which monitor the DEFAULT scene renders on ────────────
            Divider { visible: Quickshell.screens.length > 1 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                visible: Quickshell.screens.length > 1

                StyledText {
                    text: Translation.tr("Default plays on")
                    variant: "body"
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    PanelButton {
                        label: Translation.tr("All")
                        variant: Config.wpeTarget === "" ? "primary" : "ghost"
                        onActivated: Config.wpeTarget = ""
                    }

                    Repeater {
                        model: Quickshell.screens
                        delegate: PanelButton {
                            required property var modelData
                            label: modelData.name
                            variant: Config.wpeTarget === modelData.name
                                ? "primary" : "ghost"
                            onActivated: Config.wpeTarget = modelData.name
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        StyledText { text: "Scaling"; variant: "caption"; emphasis: "dim" }
                        ChipRow {
                            accent: panel.accent
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
                        StyledText { text: "Clamp"; variant: "caption"; emphasis: "dim" }
                        ChipRow {
                            accent: panel.accent
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
            }

            // ── Per-monitor overrides ──────────────────────────────────
            // A screen with no override here plays the default above.
            // "Span" turns each row's Choose… into an Include toggle: pick
            // two or more, then choose one scene once to stretch across them.
            Divider { visible: Quickshell.screens.length > 1 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                visible: Quickshell.screens.length > 1

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
                        variant: panel.monitorSpanMode ? "primary" : "ghost"
                        accent: panel.accent
                        label: Translation.tr("Span")
                        onActivated: {
                            panel.monitorSpanMode = !panel.monitorSpanMode
                            panel.pickingScreens = []
                        }
                    }
                }

                Repeater {
                    model: Quickshell.screens
                    delegate: ColumnLayout {
                        id: monRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs

                        readonly property string screenName: monRow.modelData.name
                        readonly property string assignedId:
                            WallpaperEngine.monitorFor(monRow.screenName)
                        readonly property bool spanned: (Config.wpeMonitors || [])
                            .some(m => m.screens.indexOf(monRow.screenName) !== -1
                                    && m.screens.length > 1)
                        readonly property bool included:
                            panel.pickingScreens.indexOf(monRow.screenName) !== -1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText {
                                Layout.preferredWidth: 68
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
                                visible: !panel.monitorSpanMode
                                    && (monRow.assignedId !== "" || monRow.spanned)
                                variant: "ghost"
                                label: Translation.tr("Default")
                                onActivated: WallpaperEngine.unassignMonitor(monRow.screenName)
                            }
                            PanelButton {
                                visible: !panel.monitorSpanMode
                                variant: "normal"
                                label: Translation.tr("Choose…")
                                onActivated: {
                                    panel.pickingForScreen = monRow.screenName
                                    panel.source = "engine"
                                    panel.view = "gallery"
                                }
                            }
                            PanelButton {
                                visible: panel.monitorSpanMode
                                variant: monRow.included ? "primary" : "ghost"
                                accent: panel.accent
                                label: monRow.included ? "Included" : "Include"
                                onActivated: {
                                    panel.pickingScreens = monRow.included
                                        ? panel.pickingScreens.filter(s => s !== monRow.screenName)
                                        : panel.pickingScreens.concat([monRow.screenName])
                                }
                            }
                        }
                    }
                }

                PanelButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: panel.monitorSpanMode
                    variant: "primary"
                    accent: panel.accent
                    label: "Choose a scene for " + panel.pickingScreens.length + " screens"
                    enabled: panel.pickingScreens.length >= 2
                    onActivated: {
                        panel.source = "engine"
                        panel.view = "gallery"
                    }
                }
            }
        }
    }

    Scrollbar { flickable: settingsPane }
}
