pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import ".."

// ── HyprTuningPage — Window manager › Windows ─────────────────────────────────
// Compositor tunables — gaps, borders, opacity, blur, input, animation speeds — read
// from and written to ~/.config/hypr through HyprConfig.
//
// ── The preview is the point ──────────────────────────────────────────────────
// Every setting in the Shape group is geometry: "rounding 12" and "gaps 8" mean
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

    // The animation the stage plays: the row under the pointer or the slider being held.
    property string stageLeaf: ""
    property real stageSpeed: 0
    property bool stageOn: true
    property string stageCurve: ""
    property bool stageHeld: false

    // One appearance value as text, or "?" while the parse hasn't landed.
    function shown(key) {
        const d = HyprConfig.appearance[key]
        return d ? String(d.value) : "?"
    }

    // A boolean appearance key (shadow, blur, wobble): what a dependent slider dims on.
    function flagOn(key) {
        const d = HyprConfig.appearance[key]
        return !!d && d.value === true
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

        grouped:   true
        glyph:     "󰂵"
        title:     Translation.tr("Windows")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  HyprConfig.loaded
                   ? Translation.tr("Gaps %1 inside, %2 outside  ·  rounding %3  ·  border %4")
                         .arg(root.shown("gaps_in")).arg(root.shown("gaps_out"))
                         .arg(root.shown("rounding")).arg(root.shown("border_size"))
                   : Translation.tr("Reading ~/.config/hypr…")

        banner: HyprApplyBar {}

        // ══ Preview: two tiled windows drawn from your live config ═══════════
        // The hero because it IS the live subject: gaps, border, rounding and opacity are geometry, and
        // "rounding 12" means nothing until you see it. It reads HyprConfig, so it cannot disagree with
        // the numbers beside it. The stage is a screen-shaped box on the left and the four figures it
        // draws are on the right, so the card's width carries something instead of one long strip.
        Section {
            id: previewCard
            hero: true

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 560 ? 2 : 1
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingMd

                PreviewStage {
                    id: stage
                    Layout.fillWidth: true
                    Layout.maximumWidth: 480
                    Layout.preferredHeight: 170
                    Layout.alignment: Qt.AlignTop

                    RowLayout {
                        anchors.fill: parent
                        // Outer gaps run around the whole arrangement, inner gaps sit
                        // between the windows: the preview draws both, because that is
                        // exactly the pair people mix up.
                        anchors.margins: root.scaled("gaps_out", stage.width)
                        spacing: root.scaled("gaps_in", stage.width)

                        MockWindow {
                            active: true
                            label:  Translation.tr("active")
                        }
                        MockWindow {
                            active: false
                            label:  Translation.tr("inactive")
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 200
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingMd

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Two tiled windows drawn from your live config. Drag a slider and they follow; it is written when you let go.")
                        variant: "caption"
                        color: previewCard.inkDim
                        wrapMode: Text.WordWrap
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        columns: 2
                        columnSpacing: Tokens.spacingLg
                        rowSpacing: Tokens.spacingSm

                        Repeater {
                            model: [
                                { label: Translation.tr("Inner gaps"), key: "gaps_in" },
                                { label: Translation.tr("Outer gaps"), key: "gaps_out" },
                                { label: Translation.tr("Border"),     key: "border_size" },
                                { label: Translation.tr("Rounding"),   key: "rounding" }
                            ]

                            ColumnLayout {
                                id: fig
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: false
                                spacing: 0

                                StyledText {
                                    text: root.shown(fig.modelData.key) + (root.shown(fig.modelData.key) === "?" ? "" : "px")
                                    font.pixelSize: Tokens.fontTitle
                                    font.weight: Font.Bold
                                    font.features: ({ tnum: 1 })
                                    color: previewCard.ink
                                }
                                StyledText {
                                    text: fig.modelData.label
                                    variant: "caption"
                                    color: previewCard.inkDim
                                }
                            }
                        }
                    }
                }
            }
        }

        // ══ Shape ═════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "rounded_corner"
            title:    Translation.tr("Shape")
            subtitle: Translation.tr("Gaps, border, rounding, opacity")
            help:     Translation.tr("Gaps, borders and how opaque a window is. Written to your Hyprland config when you let go of a slider.")

            TuneSlider { label: Translation.tr("Inner gaps");  skey: "gaps_in";      to: 40; suffix: "px" }
            TuneSlider { label: Translation.tr("Outer gaps");  skey: "gaps_out";     to: 60; suffix: "px" }
            TuneSlider { label: Translation.tr("Border size"); skey: "border_size";  to: 8;  suffix: "px" }
            TuneSlider { label: Translation.tr("Rounding");    skey: "rounding";     to: 30; suffix: "px" }
            TuneSlider { label: Translation.tr("Active opacity");   skey: "active_opacity";   to: 1; isFloat: true; decimals: 2 }
            TuneSlider { label: Translation.tr("Inactive opacity"); skey: "inactive_opacity"; to: 1; isFloat: true; decimals: 2 }
        }

        // ══ Blur ══════════════════════════════════════════════════════════════
        // Blur is what happens BEHIND a window, and it is the one group here the preview cannot show
        // (the stage has nothing behind it). Its three sliders dim while blur is off.
        Section {
            grouped:  true
            symbol:   "blur_on"
            title:    Translation.tr("Blur & shadow")
            subtitle: Translation.tr("Behind translucent windows")
            help:     Translation.tr("What sits behind a translucent window, the one thing the preview can't show.")

            TuneToggle { label: Translation.tr("Shadow"); skey: "shadow_enabled" }
            TuneToggle { label: Translation.tr("Blur");   skey: "blur_enabled" }
            TuneSlider { label: Translation.tr("Blur size");   skey: "blur_size";    to: 20; dep: root.flagOn("blur_enabled") }
            TuneSlider { label: Translation.tr("Blur passes"); skey: "blur_passes";  from: 1; to: 5; dep: root.flagOn("blur_enabled") }
            TuneSlider { label: Translation.tr("Vibrancy");    skey: "blur_vibrancy"; to: 1; isFloat: true; decimals: 2; dep: root.flagOn("blur_enabled") }
        }

        // ══ Wobble ════════════════════════════════════════════════════════════
        // Hyprland 0.57+: windows deform like jelly while moved or resized. The four
        // numbers are the spring (stiffer = snappier, more damping = less jiggle).
        Section {
            grouped:  true
            symbol:   "animation"
            title:    Translation.tr("Window wobble")
            subtitle: Translation.tr("Jelly while you drag")
            help:     Translation.tr("Windows stretch like jelly while you drag or resize them. Needs Hyprland 0.57 or newer.")

            TuneToggle { label: Translation.tr("Wobble"); skey: "wobble_enabled" }
            TuneSlider { label: Translation.tr("Stiffness"); skey: "wobble_stiffness"; from: 20; to: 600; dep: root.flagOn("wobble_enabled") }
            TuneSlider { label: Translation.tr("Damping");   skey: "wobble_damping";   to: 40; isFloat: true; decimals: 1; dep: root.flagOn("wobble_enabled") }
            TuneSlider { label: Translation.tr("Mass");      skey: "wobble_mass";      from: 0.2; to: 5; isFloat: true; decimals: 1; dep: root.flagOn("wobble_enabled") }
            TuneSlider { label: Translation.tr("Mesh");      skey: "wobble_mesh";      from: 2; to: 32; dep: root.flagOn("wobble_enabled") }
        }

        // ══ Input ═════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "mouse"
            title:    Translation.tr("Input")
            subtitle: Translation.tr("Focus and snapping")
            help:     Translation.tr("Focus behaviour and window snapping.")

            // Keyboard layouts, pointer speed and scrolling live only on Devices › Keyboard &
            // mouse, so each setting has one writer.
            TuneToggle { label: Translation.tr("Focus follows mouse"); group: "input"; skey: "follow_mouse"; kind: "int" }
            // The shell's, not Hyprland's (services/Snap): Config, not HyprConfig.
            SettingRow {
                rowTap: true
                label:  Translation.tr("Snap floating windows")
                detail: Config.snapZones ? Translation.tr("Edges and corners fill a half, a quarter or the screen")
                                         : Translation.tr("Windows stay where you drop them")
                help:   Translation.tr("SUPER-drag a floating window to an edge or corner to fill a half, a quarter or the screen.")
                onTapped: Config.snapZones = !Config.snapZones

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.snapZones
                    onToggled: Config.snapZones = !Config.snapZones
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Snap windows to the widget grid")
                detail: Config.snapToGrid ? Translation.tr("On the same grid as your widgets") : Translation.tr("Windows land anywhere")
                help:   Translation.tr("A floating window you SUPER-drag lands on the same grid as your desktop widgets (set in Desktop › Widgets). Dropping in a zone above still wins.")
                onTapped: Config.snapToGrid = !Config.snapToGrid

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.snapToGrid
                    onToggled: Config.snapToGrid = !Config.snapToGrid
                }
            }
        }

        // ══ Animations ════════════════════════════════════════════════════════
        Section {
            grouped:  true
            // A list of thirty short rows: the whole row, in two columns, rather than one tall strip.
            fullRow:  true
            symbol:   "animation"
            title:    Translation.tr("Animations")
            subtitle: Translation.tr("%1 animations").arg(HyprConfig.animations.length)
            help:     Translation.tr("Each animation's speed (lower is faster), and whether it runs at all.")

            // Plays the animation you point at, at the speed on its slider (drag it and it follows).
            MotionStage {
                id: motion
                Layout.fillWidth: true
                playing: root.stageHeld
                leaf: root.stageLeaf
                speed: root.stageSpeed
                on: root.stageOn
                curveName: root.stageCurve
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 640 ? 2 : 1
                columnSpacing: Tokens.spacingXl
                rowSpacing: Tokens.spacingSm
                uniformCellWidths: true

                Repeater {
                    model: HyprConfig.animations
                    AnimRow { required property var modelData; anim: modelData }
                }
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
    // above zero (blur passes are 1..5); the slider is always 0..(to−from).
    // Drawn in the shared expressive slider shape (components/SliderRow: label and value on one
    // line, the thick rail with its bar handle under them) but kept local, because it commits only on
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
        // False dims it: a setting whose switch (blur, wobble) is off.
        property bool dep: true
        readonly property var desc:
            (sr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[sr.skey] ?? null
        readonly property real cfgValue: sr.desc ? Number(sr.desc.value) : 0
        property real draft: 0
        onCfgValueChanged: if (!slider.pressed) sr.draft = sr.cfgValue
        Component.onCompleted: sr.draft = sr.cfgValue

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs
        enabled: sr.desc !== null && sr.dep
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
            thickness: 16
            expressive: true
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

    // A boolean Hyprland key as a row you tap anywhere. `label` and `detail` are SettingRow's.
    component TuneToggle: SettingRow {
        id: tr
        property string skey
        property string group: "appearance"
        property string kind: "bool"     // "bool" or "int" (0/1)
        readonly property var desc:
            (tr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[tr.skey] ?? null
        readonly property bool on: tr.kind === "bool"
            ? (tr.desc ? tr.desc.value === true : false)
            : (tr.desc ? Number(tr.desc.value) !== 0 : false)

        function flip() {
            if (!tr.desc) return
            const nv = tr.kind === "bool" ? (!tr.on) : (tr.on ? 0 : 1)
            HyprConfig.setValue(tr.desc.file, tr.desc.line, tr.skey, tr.kind, nv)
        }

        rowTap: true
        enabled: tr.desc !== null
        opacity: tr.enabled ? 1 : 0.4
        onTapped: tr.flip()

        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: tr.on
            onToggled: tr.flip()
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

        // The stage follows this row while it is pointed at or its slider is held (the draft, live).
        HoverHandler { id: rowHover }
        readonly property bool held: rowHover.hovered || slider.pressed
        function _stage() {
            root.stageLeaf = ar.anim.leaf
            root.stageSpeed = ar.draft
            root.stageOn = ar.anim.enabled
            root.stageCurve = ar.anim.bezier ?? ""
        }
        onHeldChanged: { if (ar.held) ar._stage(); root.stageHeld = ar.held }
        onDraftChanged: if (ar.held) ar._stage()

        StyledText {
            text: ar.anim.leaf
            Layout.preferredWidth: 110
            variant: "body"
            emphasis: ar.anim.enabled ? "normal" : "dim"
            elide: Text.ElideRight
        }
        ValueSlider {
            id: slider
            Layout.fillWidth: true
            thickness: 10
            expressive: true
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
            onToggled: { HyprConfig.setAnim(ar.anim.line, "enabled", !ar.anim.enabled); root.stageOn = !ar.anim.enabled }
        }
    }
}
