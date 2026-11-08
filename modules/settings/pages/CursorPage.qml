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
// The sheet under "Preview" is drawn by scripts/generate-cursor-theme — the same code
// that draws the cursors — not a QML approximation of them, so it can't show a design
// the theme doesn't have. It exists only while this page does (acquirePreview), and
// it follows the colour choice below even while the feature is off, so you can see
// what you'd get before anything is written to disk.
//
// ── One screen ────────────────────────────────────────────────────────────────
// Preview across the top, then the look beside its presets, then the motion plugin
// beside shake-to-find. The caveat about already-open windows was a card of its own;
// it is the preview's tip now, where the question it answers comes up.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Re-probe on open: the likeliest reason to be here is having just installed the plugin.
    Component.onCompleted: { Cursor.acquirePreview(); CursorEffects.probe() }
    Component.onDestruction: Cursor.releasePreview()

    readonly property string fxBlocker: CursorEffects.blocker()
    readonly property bool   fxUsable:  root.fxBlocker === ""

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F01C0}"
        title:     Translation.tr("Mouse")
        titleTail: "cursor"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  Cursor.statusText

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            checked: Config.cursorTheme
            onToggled: Config.cursorTheme = !Config.cursorTheme
        }

        // ══ Preview ═══════════════════════════════════════════════════════════
        Section {
            span:   3
            glyph:  "󰆽"
            title:  Translation.tr("Preview")
            help:   Translation.tr("Drawn by the script that draws the theme, in the colours below. Hyprland's cursor repaints at once; GTK, Qt and XWayland windows pick new colours up the next time they open.")
            accent: Colors.of(QsWindow.window).primary

            PreviewStage {
                Layout.fillWidth: true
                Layout.preferredHeight: 196
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
        }

        // ══ Look ══════════════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󰸌"
            title:  Translation.tr("Look")
            help:   Translation.tr("The fill colour and the size. The outline is always the shell's background colour.")
            accent: Colors.of(QsWindow.window).primary

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "accent", label: "Accent", icon: "palette" },
                    { value: "text",   label: "Text",   icon: "text_fields" },
                    { value: "custom", label: "Custom", icon: "colorize" }
                ]
                current: Config.cursorColor
                onPicked: function (v) { Config.cursorColor = v }
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

        // ══ Presets ═══════════════════════════════════════════════════════════
        // Saved looks, kept in presets/cursor.json like the bar's. A preset is the
        // colour, size and motion tuning — not the two on/off switches, so loading one
        // never replaces your cursor or loads a plugin on its own.
        Section {
            span:   1
            glyph:  "󰸖"
            title:  Translation.tr("Presets")
            help:   Translation.tr("Colour, size and motion tuning, saved under a name. Loading one never turns the cursor theme or the plugin on or off.")
            accent: Colors.of(QsWindow.window).primary

            PresetChips {
                accent:   Colors.of(QsWindow.window).primary
                presets:  Config.cursorAllPresets
                isActive: function (name) { return Config.cursorPresetActive(name) }
                savePlaceholder: "Name this cursor"
                onLoad:   function (name) { Config.loadCursorPreset(name) }
                onSave:   function (name) { Config.saveCursorPreset(name) }
                onRename: function (from, to) { Config.renameCursorPreset(from, to) }
                onRemove: function (name) { Config.deleteCursorPreset(name) }
            }
        }

        // ══ Motion effects ════════════════════════════════════════════════════
        // The hypr-dynamic-cursors plugin. Optional and third-party, so a missing one
        // DISABLES the controls with a reason instead of letting the switch do nothing.
        Section {
            span:     1
            glyph:    "󰓅"
            title:    Translation.tr("Motion effects")
            subtitle: CursorEffects.statusText
            help:     Translation.tr("Tilt, rotate or stretch the pointer as it moves, with the hypr-dynamic-cursors plugin.")
            accent:   Colors.of(QsWindow.window).primary

            actions: Toggle {
                enabled: root.fxUsable
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.cursorEffects
                onToggled: Config.cursorEffects = !Config.cursorEffects
            }

            // Not installed: the exact commands, like Night light's "needs a backend".
            StyledText {
                visible: !root.fxUsable
                Layout.fillWidth: true
                Layout.preferredWidth: 0
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

            TabStrip {
                Layout.fillWidth: true
                visible: root.fxUsable
                enabled: Config.cursorEffects
                opacity: enabled ? 1 : 0.5
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "tilt",    label: "Tilt" },
                    { value: "rotate",  label: "Rotate" },
                    { value: "stretch", label: "Stretch" },
                    { value: "none",    label: "Shake only" }
                ]
                current: Config.cursorEffectMode
                onPicked: function (v) { Config.cursorEffectMode = v }
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
        }

        QuickToggleTile {
            roomy: true
            symbol: "my_location"
            label:  Translation.tr("Shake to find")
            accent: Colors.of(QsWindow.window).primary
            active: Config.cursorShake
            available: root.fxUsable && Config.cursorEffects
            subLabel: Config.cursorShake ? "The pointer grows when you wiggle it"
                                         : "Wiggling does nothing"
            help: Translation.tr("Part of the motion plugin: a quick shake makes the pointer big for a moment, so you can find it.")
            onToggled: Config.cursorShake = !Config.cursorShake
        }
    }
}
