pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import ".."

// ── HyprTuningPage — Window manager › Tuning ──────────────────────────────────
// Compositor tunables — gaps, borders, opacity, blur, input, animation speeds — read
// from and written to ~/.config/hypr through HyprConfig.
//
// ── The preview is the point ──────────────────────────────────────────────────
// Every setting in the first card is geometry: "rounding 12" and "gaps 8" mean
// nothing as numbers, and the only way to judge them used to be to apply them to the
// whole compositor and look at your actual windows. Two mock windows to scale answer
// it in place — including the distinction people get wrong, which is that outer gaps
// go around the arrangement and inner gaps go between the windows.
//
// ── Writes on RELEASE, not per drag ───────────────────────────────────────────
// Each write spawns the script (a backup + a syntax check), so committing per
// drag-pixel would be a process storm. That is why these rows are local components
// and not components/SliderRow, which commits on every move.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted: HyprConfig.acquire()
    Component.onDestruction: HyprConfig.release()

    // One appearance value as text, or an em-dash while the parse hasn't landed.
    function shown(key) {
        const d = HyprConfig.appearance[key]
        return d ? String(d.value) : "—"
    }

    // The raw number, with a fallback for "not parsed yet".
    function value(key, fallback) {
        const d = HyprConfig.appearance[key]
        return d ? Number(d.value) : fallback
    }

    // The same number at preview scale. The stage stands in for a 1920px screen, so
    // everything drawn on it is divided by that ratio — without this, a 20px gap on a
    // 420px stage looks like a canyon instead of like 20px.
    function scaled(key, stageWidth) {
        const ratio = Math.max(4, 1920 / Math.max(1, stageWidth))
        return root.value(key, 0) / ratio
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰂵"
        title:     Translation.tr("Window")
        titleTail: "tuning"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  HyprConfig.loaded
                   ? "gaps " + root.shown("gaps_in") + "/" + root.shown("gaps_out")
                     + "  ·  rounding " + root.shown("rounding")
                     + "  ·  border " + root.shown("border_size")
                     + "  ·  writes ~/.config/hypr"
                   : "Reading ~/.config/hypr…"

        banner: HyprApplyBar {}

        // ══ Preview ═══════════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰖯"
            title:    Translation.tr("Preview")
            help:     Translation.tr("Two tiled windows drawn from your live config: gaps, border, rounding and opacity.")
            accent:   Colors.of(QsWindow.window).primary

            PreviewStage {
                id: stage
                Layout.fillWidth: true
                Layout.preferredHeight: 128

                RowLayout {
                    anchors.fill: parent
                    // Outer gaps run around the whole arrangement, inner gaps sit
                    // between the windows — the preview draws both, because that is
                    // exactly the pair people mix up.
                    anchors.margins: root.scaled("gaps_out", stage.width)
                    spacing: root.scaled("gaps_in", stage.width)

                    MockWindow {
                        active: true
                        label:  "active"
                    }
                    MockWindow {
                        active: false
                        label:  "inactive"
                    }
                }
            }
        }

        // ══ Appearance & blur ═════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰘇"
            title:    Translation.tr("Shape")
            help:     Translation.tr("Gaps, borders and how opaque a window is. Written to your Hyprland config when you let go of a slider.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            TuneSlider { label: "Inner gaps";  skey: "gaps_in";      to: 40; suffix: "px" }
            TuneSlider { label: "Outer gaps";  skey: "gaps_out";     to: 60; suffix: "px" }
            TuneSlider { label: "Border size"; skey: "border_size";  to: 8;  suffix: "px" }
            TuneSlider { label: "Rounding";    skey: "rounding";     to: 30; suffix: "px" }
            TuneSlider { label: "Active opacity";   skey: "active_opacity";   to: 1; isFloat: true; decimals: 2 }
            TuneSlider { label: "Inactive opacity"; skey: "inactive_opacity"; to: 1; isFloat: true; decimals: 2 }
        }

        // ══ Blur ══════════════════════════════════════════════════════════════
        // Split out of Shape: blur is what happens BEHIND a window, and it is the one
        // group here the preview cannot show (the stage has nothing behind it).
        Section {
            span:     1
            glyph:    "󰂵"
            title:    Translation.tr("Blur & shadow")
            help:     Translation.tr("What sits behind a translucent window — the one thing the preview can't show.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            TuneToggle { label: "Shadow"; skey: "shadow_enabled" }
            TuneToggle { label: "Blur";   skey: "blur_enabled" }
            TuneSlider { label: "Blur size";   skey: "blur_size";    to: 20 }
            TuneSlider { label: "Blur passes"; skey: "blur_passes";  from: 1; to: 5 }
            TuneSlider { label: "Vibrancy";    skey: "blur_vibrancy"; to: 1; isFloat: true; decimals: 2 }
        }

        // ══ Wobble ════════════════════════════════════════════════════════════
        // Hyprland 0.57+: windows deform like jelly while moved or resized. The four
        // numbers are the spring (stiffer = snappier, more damping = less jiggle).
        Section {
            span:     1
            glyph:    "󰪐"
            title:    Translation.tr("Window wobble")
            help:     Translation.tr("Windows stretch like jelly while you drag or resize them. Needs Hyprland 0.57 or newer.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            TuneToggle { label: "Wobble"; skey: "wobble_enabled" }
            TuneSlider { label: "Stiffness"; skey: "wobble_stiffness"; from: 20; to: 600 }
            TuneSlider { label: "Damping";   skey: "wobble_damping";   to: 40; isFloat: true; decimals: 1 }
            TuneSlider { label: "Mass";      skey: "wobble_mass";      from: 0.2; to: 5; isFloat: true; decimals: 1 }
            TuneSlider { label: "Mesh";      skey: "wobble_mesh";      from: 2; to: 32 }
        }

        // ══ Input ═════════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰆿"
            title:    Translation.tr("Input")
            help:     Translation.tr("Pointer and focus behaviour, and the keyboard layouts Hyprland starts with.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                StyledText {
                    text: Translation.tr("Layouts")
                    Layout.preferredWidth: 96
                    variant: "body"
                    font.weight: Font.Medium
                }
                InputField {
                    cornerRadius: implicitHeight / 2
                    id: kbLayoutField
                    Layout.fillWidth: true
                    mono: true
                    // `seed`, not a `text:` binding — applied only while unfocused, so
                    // typing doesn't fight a round-tripping write.
                    seed: HyprConfig.input.kb_layout ? HyprConfig.input.kb_layout.value : ""
                    onAccepted: {
                        const d = HyprConfig.input.kb_layout
                        if (d) HyprConfig.setValue(d.file, d.line, "kb_layout", "str", kbLayoutField.text)
                    }
                }
            }

            // Pointer speed and scrolling moved to Devices › Keyboard & mouse (one home each).
            TuneToggle { label: "Focus follows mouse"; group: "input"; skey: "follow_mouse"; kind: "int" }
            // The shell's, not Hyprland's (services/Snap): Config, not HyprConfig.
            SettingRow {
                label: Translation.tr("Snap floating windows")
                help:  Translation.tr("SUPER-drag a floating window to an edge or corner to fill a half, a quarter or the screen.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.snapZones
                    onToggled: Config.snapZones = !Config.snapZones
                }
            }
            SettingRow {
                label: Translation.tr("Snap windows to the widget grid")
                help:  Translation.tr("A floating window you SUPER-drag lands on the same grid as your desktop widgets (set in Desktop › Widgets). Dropping in a zone above still wins.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.snapToGrid
                    onToggled: Config.snapToGrid = !Config.snapToGrid
                }
            }
        }

        // ══ Animations ════════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰪐"
            title:    Translation.tr("Animations")
            subtitle: HyprConfig.animations.length + " curves"
            help:     Translation.tr("Each animation's speed (lower is faster), and whether it runs at all.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            Repeater {
                model: HyprConfig.animations
                AnimRow { required property var modelData; anim: modelData }
            }
        }
    }

    // ── MockWindow — one window in the preview ───────────────────────────────
    // Drawn from the live config through root.scaled(), so it is the settings rather
    // than a picture of some settings.
    component MockWindow: Rectangle {
        id: mock
        property bool active: true
        property string label: ""

        Layout.fillWidth: true
        Layout.fillHeight: true

        radius: root.scaled("rounding", stage.width)
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceHigh,
                            root.value(mock.active ? "active_opacity" : "inactive_opacity", 1))
        // At least a pixel: a border set to 0 in the config should read as "none",
        // but a sub-pixel border reads as a rendering fault.
        border.width: root.value("border_size", 0) > 0
                      ? Math.max(1, root.scaled("border_size", stage.width)) : 0
        border.color: mock.active ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).outline

        Behavior on radius       { NumberAnimation { duration: Motion.respond } }
        Behavior on border.width { NumberAnimation { duration: Motion.respond } }
        Behavior on color        { ColorAnimation  { duration: Motion.respond } }

        StyledText {
            anchors.centerIn: parent
            text: mock.label
            variant: "caption"
            color: mock.active ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
        }
    }

    // A labelled numeric slider bound to a settings key. `from` lets a range start
    // below zero (mouse sensitivity is −1..1); the slider is always 0..(to−from).
    // Drawn in the shared slider shape (components/SliderRow: label and value on one
    // line, the thick rail under them) but kept local, because it commits only on
    // RELEASE — each write spawns a backup and a syntax check — and the draft moves
    // live so the preview follows the drag.
    component TuneSlider: ColumnLayout {
        id: sr
        property string label
        property string skey
        property string group: "appearance"
        property real from: 0
        property real to: 1
        property bool isFloat: false
        property int decimals: 0
        property string suffix: ""
        readonly property var desc:
            (sr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[sr.skey] ?? null
        readonly property real cfgValue: sr.desc ? Number(sr.desc.value) : 0
        property real draft: 0
        onCfgValueChanged: if (!slider.pressed) sr.draft = sr.cfgValue
        Component.onCompleted: sr.draft = sr.cfgValue

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs
        enabled: sr.desc !== null
        opacity: sr.enabled ? 1 : 0.4

        function _commit() {
            if (!sr.desc) return
            const v = sr.isFloat ? Number(sr.draft.toFixed(sr.decimals)) : Math.round(sr.draft)
            HyprConfig.setValue(sr.desc.file, sr.desc.line, sr.skey, sr.isFloat ? "float" : "int", v)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.minimumHeight: 22
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: sr.label
                variant: "body"
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            StyledText {
                text: (sr.isFloat ? sr.draft.toFixed(sr.decimals) : Math.round(sr.draft)) + sr.suffix
                variant: "body"
                emphasis: "dim"
                font.weight: Font.Medium
            }
        }
        ValueSlider {
            id: slider
            Layout.fillWidth: true
            thickness: 14
            accent: Colors.of(QsWindow.window).primary
            maximum: sr.to - sr.from
            value:   sr.draft - sr.from
            // The draft moves live so the PREVIEW follows your finger; only the
            // write waits for the release.
            onMoved: sr.draft = sr.from + value
            onScrolled: function (d) {
                sr.draft = Math.max(sr.from, Math.min(sr.to,
                    sr.draft + d * (sr.isFloat ? Math.pow(10, -sr.decimals) : 1)))
                sr._commit()
            }
            onPressedChanged: if (!pressed) sr._commit()
        }
    }

    component TuneToggle: RowLayout {
        id: tr
        property string label
        property string skey
        property string group: "appearance"
        property string kind: "bool"     // "bool" or "int" (0/1)
        readonly property var desc:
            (tr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[tr.skey] ?? null
        readonly property bool on: tr.kind === "bool"
            ? (tr.desc ? tr.desc.value === true : false)
            : (tr.desc ? Number(tr.desc.value) !== 0 : false)

        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.minimumHeight: 40
        enabled: tr.desc !== null

        StyledText { text: tr.label; Layout.fillWidth: true; variant: "body"; font.weight: Font.Medium; elide: Text.ElideRight }
        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: tr.on
            onToggled: {
                if (!tr.desc) return
                const nv = tr.kind === "bool" ? (!tr.on) : (tr.on ? 0 : 1)
                HyprConfig.setValue(tr.desc.file, tr.desc.line, tr.skey, tr.kind, nv)
            }
        }
    }

    component AnimRow: RowLayout {
        id: ar
        required property var anim

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        property real draft: 0
        Component.onCompleted: ar.draft = ar.anim.speed

        StyledText {
            text: ar.anim.leaf
            Layout.preferredWidth: 110
            variant: "body"
            emphasis: ar.anim.enabled ? "normal" : "dim"
            elide: Text.ElideRight
        }
        ValueSlider {
            Layout.fillWidth: true
            accent: Colors.of(QsWindow.window).primary
            enabled: ar.anim.enabled
            maximum: 30
            value: ar.draft
            onMoved: ar.draft = value
            onPressedChanged: if (!pressed) HyprConfig.setAnim(ar.anim.line, "speed", Number(ar.draft.toFixed(1)))
        }
        StyledText {
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignRight
            text: ar.draft.toFixed(1)
            variant: "body"
            emphasis: "dim"
        }
        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: ar.anim.enabled
            onToggled: HyprConfig.setAnim(ar.anim.line, "enabled", !ar.anim.enabled)
        }
    }
}
