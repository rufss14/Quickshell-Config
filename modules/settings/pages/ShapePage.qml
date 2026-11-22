pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ShapePage — Appearance › Type, shape & motion ────────────────────────────
// The shell-wide design tokens: type, density, corner roundness, surface opacity,
// shadows and motion. Everything here reaches Tokens itself, not one widget's slice of it:
// an untouched slider changes nothing, because every scale defaults to 1.0 / "" and
// Tokens' baseline constants are exactly what they were before this page existed.
//
// ── The specimen is the page's subject ────────────────────────────────────────
// The settings window is itself built from these tokens, so it already previews type and
// spacing. It cannot preview the two that matter most: surface opacity and shadow are
// invisible against more of the same surface. On the checkered stage they are obvious, and
// the specimen answers "what does 0.7 actually look like" without applying it to the whole
// shell. It is built from the REAL components (Surface, StyledText, PanelButton, Toggle),
// so it cannot drift from what the shell will do.
//
// Beside the card, the three faces in use, set in their own fonts. Under it, grouped rows in
// two balanced columns: Type and Surfaces on one side, Shape and Motion on the other (the
// card's source order is Type, Shape, Surfaces, Motion, so the masonry pairs them that way).
// Each control says its name; why it exists is its `help` tip.
//
// The settings window's own mode (window or docked panel) is not here: it is set with the
// islands, where the panel opens.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // What differs from the defaults, for the header — a state line, so an untouched
    // page says so instead of listing five "1.00×".
    readonly property string changed: {
        const out = []
        if (Config.fontFamily !== "" || Config.fontMonoFamily !== "" || Config.fontBlockFamily !== "")
            out.push("custom fonts")
        if (Config.fontScale !== 1.0)     out.push(Config.fontScale.toFixed(2) + "× text")
        if (Config.densityScale !== 1.0)  out.push(Config.densityScale.toFixed(2) + "× spacing")
        if (Config.radiusScale !== 1.0)   out.push(Config.radiusScale.toFixed(2) + "× corners")
        if (Config.barShape)              out.push("square corners")
        if (Config.cornerStyle !== "default") out.push("rounder corners")
        if (Config.iconShape !== "default")   out.push(Config.iconShape + " icons")
        if (Config.highContrast)          out.push("high contrast")
        else if (Config.surfaceOpacity !== Defaults.surfaceOpacity)
            out.push(Math.round(Config.surfaceOpacity * 100) + "% opaque")
        if (Config.shadowScale !== 1.0)   out.push(Config.shadowScale === 0 ? "no shadows"
                                                   : Config.shadowScale.toFixed(2) + "× shadows")
        if (!Config.motionEnabled)        out.push("no motion")
        else if (Config.motionReduced)    out.push("reduced motion")
        else if (Config.motionScale !== 1.0) out.push((1 / Config.motionScale).toFixed(1) + "× motion")
        return out.length ? out.join("  ·  ") : "Everything at its default"
    }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰛖"
        title:     Translation.tr("Type, shape")
        titleTail: Translation.tr("& motion")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.changed

        actions: ChipTray {
            ChipButton {
                symbol: "restart_alt"
                label:  Translation.tr("Reset")
                tint:   Colors.of(QsWindow.window).primary
                onActivated: {
                    Config.fontFamily      = ""
                    Config.fontMonoFamily  = ""
                    Config.fontBlockFamily = ""
                    Config.fontScale      = 1.0
                    Config.densityScale   = 1.0
                    Config.radiusScale    = 1.0
                    Config.cornerStyle    = "default"
                    Config.barShape       = false
                    Config.iconShape      = "default"
                    Config.surfaceOpacity = Defaults.surfaceOpacity
                    Config.shadowScale    = 1.0
                    // Motion lives on this page now, so Reset owns it too.
                    Config.motionEnabled  = true
                    Config.motionScale    = 1.0
                    Config.motionReduced  = false
                    Config.highContrast   = false
                }
            }
        }

        // ══ The specimen ══════════════════════════════════════════════════════
        Section {
            id: specimenCard
            hero:  true
            title: Translation.tr("Preview")
            help:  Translation.tr("A card drawn at your settings, from the shell's real components. Everything on this page changes it.")

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                // Small on purpose: it only has to answer "what does 0.7 opacity look
                // like", not stand in for the whole card gallery.
                PreviewStage {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.preferredHeight: 112

                    // The real thing, not a drawing of it: a Surface at the same
                    // elevation a settings card uses, so its fill, corner, shadow and
                    // opacity are literally the ones the shell will draw.
                    Surface {
                        anchors.centerIn: parent
                        width:  Math.min(parent.width, 300)
                        implicitHeight: specimen.implicitHeight + Tokens.spacingMd * 2
                        elevation: Tokens.elevationNested
                        cornerRadius: Tokens.radiusCard

                        ColumnLayout {
                            id: specimen
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingXs

                            RowLayout {
                                Layout.fillHeight: false
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                ScallopChip {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    glyph: "󰛖"
                                    tint:  Colors.of(QsWindow.window).primary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: Translation.tr("A card, at this scale")
                                        variant: "body"
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: Translation.tr("Caption text runs at this size")
                                        variant: "micro"
                                        emphasis: "dim"
                                    }
                                }
                                Toggle { accent: Colors.of(QsWindow.window).primary; checked: true }
                            }

                            RowLayout {
                                Layout.fillHeight: false
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                PanelButton {
                                    capsule: true
                                    variant: "primary"
                                    accent: Colors.of(QsWindow.window).primary
                                    label: Translation.tr("Primary")
                                }
                                PanelButton { capsule: true; variant: "normal"; label: Translation.tr("Normal") }
                                PanelButton { capsule: true; variant: "ghost";  label: Translation.tr("Ghost") }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // The three faces as set now, each in its own font and at the scale above.
                ColumnLayout {
                    Layout.preferredWidth: Tokens.fieldHeight * 8
                    Layout.maximumWidth: Tokens.fieldHeight * 8
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: [
                            { sample: "Aa Bb 123", name: Translation.tr("Text"),     face: Tokens.fontFamily },
                            { sample: "0123 4567", name: Translation.tr("Numerals"), face: Tokens.fontMono },
                            { sample: "12:34",     name: Translation.tr("Display"),  face: Tokens.fontBlock }
                        ]

                        RowLayout {
                            id: faceRow
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingMd

                            StyledText {
                                Layout.fillWidth: true
                                text: faceRow.modelData.sample
                                variant: "headline"
                                font.family: faceRow.modelData.face
                                font.features: ({ tnum: 1 })
                                color: specimenCard.ink
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: faceRow.modelData.name
                                variant: "caption"
                                color: specimenCard.inkDim
                            }
                        }
                    }
                }
            }
        }

        // ══ Type ══════════════════════════════════════════════════════════════
        // Picked from what is installed, never typed: Qt falls back to a system font
        // SILENTLY on a name it doesn't know, so a typo left the shell in the wrong
        // face with nothing saying so. (Each picker is also a labelled row, which is
        // what puts it in the search index: scripts/build-settings-index.py reads
        // labels, and a bare field dropped this setting out of search once.)
        //
        // Three, because they do three jobs and a mono or a display face cannot be
        // derived from a prose one. Icons are unaffected: Material Symbols draws them,
        // and the brand marks fall back to the Nerd Font per glyph.
        Section {
            grouped: true
            symbol:  "text_fields"
            title:   Translation.tr("Type")
            subtitle: Config.fontFamily !== "" || Config.fontMonoFamily !== "" || Config.fontBlockFamily !== ""
                ? Translation.tr("Custom fonts") : ""

            FontPicker {
                label:    Translation.tr("Text")
                detail:   Translation.tr("In use: %1").arg(Tokens.fontFamily)
                help:     Translation.tr("The font for labels, titles and body copy everywhere in the shell.")
                value:    Config.fontFamily
                fallback: Tokens.defaultFamily
                onPicked: function (name) { Config.fontFamily = name }
            }

            FontPicker {
                label:    Translation.tr("Numerals")
                detail:   Translation.tr("In use: %1").arg(Tokens.fontMono)
                help:     Translation.tr("The font for throughput, timers and other figures that must line up. A monospace face is best.")
                value:    Config.fontMonoFamily
                fallback: Tokens.defaultMono
                onPicked: function (name) { Config.fontMonoFamily = name }
            }

            FontPicker {
                label:    Translation.tr("Display")
                detail:   Translation.tr("In use: %1").arg(Tokens.fontBlock)
                help:     Translation.tr("The font for the big clock on the lock and login screens. Heavier faces read best.")
                value:    Config.fontBlockFamily
                fallback: Tokens.defaultBlock
                onPicked: function (name) { Config.fontBlockFamily = name }
            }

            Fader {
                label:  Translation.tr("Text scale")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.fontScaleMin
                to:     Config.fontScaleMax
                step:   0.05
                value:  Config.fontScale
                readout: Config.fontScale.toFixed(2) + "×"
                onCommit: function (v) { Config.fontScale = v }
            }
        }

        // ══ Shape ═════════════════════════════════════════════════════════════
        // Density, corners and the shape that holds an icon.
        Section {
            grouped: true
            symbol:  "rounded_corner"
            title:   Translation.tr("Shape")

            Fader {
                label:  Translation.tr("Spacing")
                help:   Translation.tr("How tightly everything packs: padding, gaps, row heights.")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.densityScaleMin
                to:     Config.densityScaleMax
                step:   0.05
                value:  Config.densityScale
                readout: Config.densityScale.toFixed(2) + "×"
                onCommit: function (v) { Config.densityScale = v }
            }
            Fader {
                label:  Translation.tr("Roundness")
                help:   Translation.tr("Corner radius of cards, panels and controls. The bar and desktop widgets keep their own.")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.radiusScaleMin
                to:     Config.radiusScaleMax
                step:   0.05
                value:  Config.radiusScale
                readout: Config.radiusScale.toFixed(2) + "×"
                onCommit: function (v) { Config.radiusScale = v }
            }
            // Global: every panel, card, button and field, and the bar, flush to the edges. The
            // one home of this switch (the bar's own style settings do not repeat it).
            SettingRow {
                rowTap: true
                label:  Translation.tr("Square corners")
                detail: Config.barShape ? Translation.tr("Everywhere, and the bar edge to edge")
                                        : Translation.tr("Rounded, at the radius set here")
                onTapped: Config.toggleShape()

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.barShape
                    onToggled: Config.toggleShape()
                }
            }
            // Which ladder the radius scales: the shell's own, or End-4's rounder one.
            SettingRow {
                label:  Translation.tr("Corner style")
                detail: Config.cornerStyle === "ii" ? Translation.tr("A rounder ladder of radii")
                                                    : Translation.tr("The shell's own ladder of radii")

                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: Tokens.fieldHeight * 7
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "default", label: Translation.tr("Corners"),    icon: "crop_free" },
                        { value: "ii",      label: Translation.tr("Rounder"),    icon: "rounded_corner" }
                    ]
                    current: Config.cornerStyle
                    onPicked: function (v) { Config.cornerStyle = v }
                }
            }
            // What holds an icon in a panel header and a settings section. Five values, so
            // chips that wrap rather than a connected group.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    text: Translation.tr("Icon shape")
                    variant: "body"
                    font.weight: Font.Medium
                }
                StyledText {
                    text: Translation.tr("What holds an icon in a panel header")
                    variant: "caption"
                    emphasis: "dim"
                }
                ChipRow {
                    Layout.fillHeight: false
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "default",  label: Translation.tr("Default") },
                        { value: "squircle", label: Translation.tr("Squircle") },
                        { value: "cookie",   label: Translation.tr("Cookie") },
                        { value: "clover",   label: Translation.tr("Clover") },
                        { value: "circle",   label: Translation.tr("Circle") }
                    ]
                    current: Config.iconShape
                    onPicked: function (v) { Config.iconShape = v }
                }
            }
        }

        // ══ Surfaces ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "layers"
            title:    Translation.tr("Surfaces")
            subtitle: Config.highContrast ? Translation.tr("High contrast") : ""

            Fader {
                label:  Translation.tr("Opacity")
                help:   Translation.tr("How much of the desktop shows through the shell's surfaces.")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.surfaceOpacityMin
                to:     1.0
                step:   0.01
                value:  Config.surfaceOpacity
                readout: Math.round(Config.surfaceOpacity * 100) + "%"
                enabled: !Config.highContrast
                onCommit: function (v) { Config.surfaceOpacity = v }
            }
            // Overrides the opacity above (and the bar's and widgets'): every surface solid,
            // text and accents at 7:1, 2px solid borders. PaletteRoles and Tokens read it.
            SettingRow {
                rowTap: true
                label:  Translation.tr("High contrast")
                detail: Config.highContrast ? Translation.tr("Solid surfaces, stronger text")
                                            : Translation.tr("Surfaces keep the opacity above")
                help:   Translation.tr("Stronger text and accent colours, solid borders and fully opaque surfaces. The opacity sliders keep their values for when you switch it off.")
                onTapped: Config.highContrast = !Config.highContrast

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.highContrast
                    onToggled: Config.highContrast = !Config.highContrast
                }
            }
            Fader {
                label:  Translation.tr("Shadows")
                help:   Translation.tr("How far surfaces float. At zero the shell stops drawing shadows altogether.")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.shadowScaleMin
                to:     Config.shadowScaleMax
                step:   0.05
                value:  Config.shadowScale
                // At 0 the shell stops drawing shadows at all, not just faintly.
                readout: Config.shadowScale === 0 ? Translation.tr("Off") : Config.shadowScale.toFixed(2) + "×"
                onCommit: function (v) { Config.shadowScale = v }
            }
        }

        // ══ Motion ════════════════════════════════════════════════════════════
        // Shell-wide, and it always was: `Motion._d()` runs every duration in the app
        // through these two, so a panel, a notification, the lock screen and the bar
        // all slow down together. That is why it lives here and not on the Bar page.
        //
        // One wrinkle worth knowing: a BAR PRESET snapshots these along with the bar's
        // own settings (Config's preset writer takes motionEnabled/motionScale), so
        // loading a preset can change the whole shell's motion. Left as it is: the
        // shipped presets round-trip through that shape.
        //
        // The master is the group's first row, named, so the switch is never a bare control.
        Section {
            grouped:  true
            symbol:   "animation"
            title:    Translation.tr("Motion")
            help:     Translation.tr("Every animation in the shell (panels, notifications, the lock screen, the bar) runs through these two.")

            SettingRow {
                rowTap: true
                label:  Translation.tr("Animations")
                detail: Config.motionEnabled ? Translation.tr("Every change plays out")
                                             : Translation.tr("Every change is instant")
                onTapped: Config.motionEnabled = !Config.motionEnabled

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    accessibleName: Translation.tr("Animations")
                    checked: Config.motionEnabled
                    onToggled: Config.motionEnabled = !Config.motionEnabled
                }
            }

            Fader {
                label: Translation.tr("Speed")
                accent: Colors.of(QsWindow.window).primary
                from: Config.motionScaleMin
                to:   Config.motionScaleMax
                step: 0.05
                value: Config.motionScale
                // Inverted: a bigger number is faster. motionScale is a duration
                // multiplier, so 0.5× duration is 2× speed.
                readout: (1 / Config.motionScale).toFixed(1) + "×"
                enabled: Config.motionEnabled
                onCommit: function (v) { Config.motionScale = v }
            }

            // Between full and off: fades stay, bounce / parallax / drifting shapes / the colour
            // wave / idle spinning go (Motion.reduced, Motion.ambientOn). Not part of a bar
            // preset or a look bundle: it is the user's accessibility choice.
            SettingRow {
                rowTap: true
                enabled: Config.motionEnabled
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Reduced motion")
                detail: Config.motionReduced ? Translation.tr("Fades only") : Translation.tr("Full motion")
                help:   Translation.tr("Keeps fades and state changes, drops bounce, parallax, drifting shapes, the colour-change wave and idle spinning.")
                onTapped: Config.motionReduced = !Config.motionReduced

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.motionReduced
                    onToggled: Config.motionReduced = !Config.motionReduced
                }
            }
        }
    }
}
