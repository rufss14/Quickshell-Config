pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── CursorPage — Appearance › Cursor ──────────────────────────────────────────
// The mouse pointer, in the shell's colours. services/Cursor.qml owns the work
// (regenerating the theme when the palette moves, telling Hyprland); this page shows
// and sets.
//
// ── The preview is the real thing ─────────────────────────────────────────────
// The sheet on the loud card is drawn by scripts/generate-cursor-theme — the same code
// that draws the cursors — not a QML approximation of them, so it can't show a design
// the theme doesn't have. It exists only while this page does (acquirePreview), and
// it follows the colour choice below even while the feature is off, so you can see
// what you'd get before anything is written to disk.
//
// ── Layout ────────────────────────────────────────────────────────────────────
// The sheet is the page's subject and carries the page's master switch (the cursor theme),
// labelled, on the loud card. Under it the groups balance in columns: the look and the presets
// on one side, the motion plugin with shake-to-find on the other. The caveat about
// already-open windows is the card's own line, where the question it answers comes up.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Re-probe on open: the likeliest reason to be here is having just installed the plugin.
    Component.onCompleted: { Cursor.acquirePreview(); CursorEffects.probe() }
    Component.onDestruction: Cursor.releasePreview()

    readonly property string fxBlocker: CursorEffects.blocker()
    readonly property bool   fxUsable:  root.fxBlocker === ""

    // The service's own summary has a dash in it, which UI text here does not use.
    readonly property string status: Cursor.lastError !== "" ? Cursor.lastError
        : !Config.cursorTheme ? Translation.tr("Off, the system cursor is untouched")
        : Translation.tr("Following the colour scheme")

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "\u{F01C0}"
        title:     Translation.tr("Mouse")
        titleTail: "cursor"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.status

        // ══ Preview ═══════════════════════════════════════════════════════════
        Section {
            id: sheetCard
            hero: true

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                PreviewStage {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.preferredHeight: 156
                    checkered: false

                    Image {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        source:   Cursor.previewUrl
                        cache:    false
                        fillMode: Image.PreserveAspectFit
                        smooth:   true
                        mipmap:   true
                    }
                }

                // The page's one master switch, named, beside the thing it turns on.
                ColumnLayout {
                    Layout.preferredWidth: Tokens.fieldHeight * 8
                    Layout.maximumWidth: Tokens.fieldHeight * 8
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Cursor theme")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: sheetCard.ink
                            elide: Text.ElideRight
                        }
                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            accent:  Colors.of(QsWindow.window).primary
                            accessibleName: Translation.tr("Cursor theme")
                            checked: Config.cursorTheme
                            onToggled: Config.cursorTheme = !Config.cursorTheme
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: Translation.tr("Drawn by the script that draws the theme, in the colours below. Hyprland repaints at once; GTK, Qt and XWayland windows pick new colours up the next time they open.")
                        variant: "caption"
                        color: sheetCard.inkDim
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ══ Look ══════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "palette"
            title:    Translation.tr("Look")
            help:     Translation.tr("The fill colour and the size. The outline is always the shell's background colour.")

            SettingRow {
                label:  Translation.tr("Fill")
                detail: Config.cursorColor === "accent" ? Translation.tr("The shell's accent colour")
                      : Config.cursorColor === "text"   ? Translation.tr("The text colour of the palette")
                      :                                   Translation.tr("A colour of your own")

                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: Tokens.fieldHeight * 9
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "accent", label: Translation.tr("Accent"), icon: "palette" },
                        { value: "text",   label: Translation.tr("Text"),   icon: "text_fields" },
                        { value: "custom", label: Translation.tr("Custom"), icon: "colorize" }
                    ]
                    current: Config.cursorColor
                    onPicked: function (v) { Config.cursorColor = v }
                }
            }

            ColorField {
                visible: Config.cursorColor === "custom"
                label:   Translation.tr("Colour")
                value:   Config.cursorCustom
                onCommit: function (hex) { Config.cursorCustom = hex }
            }

            SliderRow {
                label: Translation.tr("Size")
                from:  Config.cursorSizeMin
                to:    Config.cursorSizeMax
                step:  2
                value: Config.cursorSize
                readout: Config.cursorSize + "px"
                numberWidth: 44
                onCommit: function (v) { Config.cursorSize = Math.round(v) }
            }
        }

        // ══ Motion effects ════════════════════════════════════════════════════
        // The hypr-dynamic-cursors plugin. Optional and third-party, so a missing one
        // DISABLES the master with the reason (and shows it OFF, never on and dead) instead of
        // letting the switch do nothing. Shake-to-find is the plugin's too, so it sits here and
        // dims with it. Listed before the presets so the two columns end level.
        Section {
            grouped:  true
            symbol:   "speed"
            title:    Translation.tr("Motion effects")
            subtitle: CursorEffects.lastError !== "" ? CursorEffects.lastError : root.fxBlocker
            help:     Translation.tr("Tilt, rotate or stretch the pointer as it moves, with the hypr-dynamic-cursors plugin.")

            SettingRow {
                rowTap: true
                enabled: root.fxUsable
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Motion effects")
                detail: !root.fxUsable ? Translation.tr("Install the plugin below to switch this on")
                      : Config.cursorEffects ? Translation.tr("The pointer reacts as it moves")
                      :                        Translation.tr("The pointer moves plainly")
                onTapped: Config.cursorEffects = !Config.cursorEffects

                Toggle {
                    enabled: root.fxUsable
                    accent:  Colors.of(QsWindow.window).primary
                    accessibleName: Translation.tr("Motion effects")
                    checked: root.fxUsable && Config.cursorEffects
                    onToggled: Config.cursorEffects = !Config.cursorEffects
                }
            }

            // Not installed: the exact commands, like Night light's "needs a backend".
            Rectangle {
                visible: !root.fxUsable
                Layout.fillWidth: true
                implicitHeight: commands.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).surfaceHigh

                StyledText {
                    id: commands
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingMd
                    text: (CursorEffects.state === "nohyprpm"
                            ? "sudo pacman -S hyprpm\n" : "")
                        + "hyprpm update\n"
                        + "hyprpm add https://github.com/virtcode/hypr-dynamic-cursors\n"
                        + "hyprpm enable dynamic-cursors"
                    variant: "caption"
                    font.family: Tokens.fontMono
                    emphasis: "dim"
                    wrapMode: Text.WrapAnywhere
                }
            }

            // Four values: a connected group.
            SettingRow {
                visible: root.fxUsable
                enabled: Config.cursorEffects
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Effect")
                detail: Config.cursorEffectMode === "tilt"    ? Translation.tr("Leans with the direction of travel")
                      : Config.cursorEffectMode === "rotate"  ? Translation.tr("Turns to face where it is going")
                      : Config.cursorEffectMode === "stretch" ? Translation.tr("Stretches along the motion")
                      :                                         Translation.tr("No effect, only shake to find")

                TabStrip {
                    connected: true
                    implicitWidth: Tokens.fieldHeight * 10
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "tilt",    label: Translation.tr("Tilt") },
                        { value: "rotate",  label: Translation.tr("Rotate") },
                        { value: "stretch", label: Translation.tr("Stretch") },
                        { value: "none",    label: Translation.tr("Shake only") }
                    ]
                    current: Config.cursorEffectMode
                    onPicked: function (v) { Config.cursorEffectMode = v }
                }
            }

            SliderRow {
                visible: root.fxUsable
                enabled: Config.cursorEffects
                label: Translation.tr("Sensitivity")
                from:  Config.cursorEffectSensitivityMin
                to:    Config.cursorEffectSensitivityMax
                step:  10
                value: Config.cursorEffectSensitivity
                readout: Config.cursorEffectSensitivity + "%"
                numberWidth: 48
                onCommit: function (v) { Config.cursorEffectSensitivity = Math.round(v) }
            }

            SettingRow {
                rowTap: true
                enabled: root.fxUsable && Config.cursorEffects
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Shake to find")
                detail: Config.cursorShake ? Translation.tr("The pointer grows when you wiggle it")
                                           : Translation.tr("Wiggling does nothing")
                help:   Translation.tr("Part of the motion plugin: a quick shake makes the pointer big for a moment, so you can find it.")
                onTapped: Config.cursorShake = !Config.cursorShake

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.cursorShake
                    onToggled: Config.cursorShake = !Config.cursorShake
                }
            }
        }

        // ══ Presets ═══════════════════════════════════════════════════════════
        // Saved looks, kept in presets/cursor.json like the bar's. A preset is the
        // colour, size and motion tuning, not the two on/off switches, so loading one
        // never replaces your cursor or loads a plugin on its own.
        Section {
            grouped: true
            symbol:  "bookmark"
            title:   Translation.tr("Presets")
            help:    Translation.tr("Colour, size and motion tuning, saved under a name. Loading one never turns the cursor theme or the plugin on or off.")

            PresetChips {
                accent:   Colors.of(QsWindow.window).primary
                presets:  Config.cursorAllPresets
                isActive: function (name) { return Config.cursorPresetActive(name) }
                savePlaceholder: Translation.tr("Name this cursor")
                onLoad:   function (name) { Config.loadCursorPreset(name) }
                onSave:   function (name) { Config.saveCursorPreset(name) }
                onRename: function (from, to) { Config.renameCursorPreset(from, to) }
                onRemove: function (name) { Config.deleteCursorPreset(name) }
            }
        }
    }
}
