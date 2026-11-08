pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ShapePage — Appearance › Type & shape ─────────────────────────────────────
// The shell-wide design tokens: type, density, corner roundness, surface opacity and
// shadows. Everything here reaches Tokens itself, not one widget's slice of it — an
// untouched slider changes nothing, because every scale defaults to 1.0 / "" and
// Tokens' baseline constants are exactly what they were before this page existed.
//
// ── The specimen earns its place now ──────────────────────────────────────────
// A preview card was removed from this page once, on the reasoning that the settings
// window is ITSELF built from these tokens and therefore already the preview. That
// is true of type and spacing and false of the two that matter most: surface opacity
// and shadow are invisible against more of the same surface. On the checkered stage
// they are obvious, and the specimen answers "what does 0.7 actually look like"
// without you having to apply it to the whole shell to find out.
//
// It is built from the REAL components (Surface, StyledText, PanelButton, Toggle), so
// it cannot drift from what the shell will do — a hand-drawn mock would be a second
// implementation to keep in step.
//
// ── Fits the window ───────────────────────────────────────────────────────────
// Preview across the top, then two rows of two cards matched in height (Type beside
// Shape's four sliders, Motion beside the window mode), so the page ends at the
// window's edge at 1200×740 instead of scrolling. Each control says its name; why it
// exists is its `help` tip.
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
        if (Config.surfaceOpacity !== Defaults.surfaceOpacity)
            out.push(Math.round(Config.surfaceOpacity * 100) + "% opaque")
        if (Config.shadowScale !== 1.0)   out.push(Config.shadowScale === 0 ? "no shadows"
                                                   : Config.shadowScale.toFixed(2) + "× shadows")
        if (!Config.motionEnabled)        out.push("no motion")
        else if (Config.motionScale !== 1.0) out.push((1 / Config.motionScale).toFixed(1) + "× motion")
        return out.length ? out.join("  ·  ") : "Everything at its default"
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰛖"
        title:     Translation.tr("Type")
        titleTail: "& shape"
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
                }
            }
        }

        // ══ The specimen ══════════════════════════════════════════════════════
        Section {
            span:   3
            glyph:  "󰛐"
            title:  Translation.tr("Preview")
            help:   Translation.tr("A card drawn at your settings, from the shell's real components. Everything on this page changes it.")
            accent: Colors.of(QsWindow.window).primary

            // Small on purpose — it only has to answer "what does 0.7 opacity look
            // like", not stand in for the whole card gallery.
            PreviewStage {
                Layout.fillWidth: true
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
                            PanelButton { capsule: true; variant: "normal"; label: "Normal" }
                            PanelButton { capsule: true; variant: "ghost";  label: "Ghost" }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }

        // ══ Type ══════════════════════════════════════════════════════════════
        // Picked from what is installed, never typed: Qt falls back to a system font
        // SILENTLY on a name it doesn't know, so a typo left the shell in the wrong
        // face with nothing saying so. (Each picker is also a labelled row, which is
        // what puts it in the search index — scripts/build-settings-index.py reads
        // labels, and a bare field dropped this setting out of search once.)
        //
        // Three, because they do three jobs and a mono or a display face cannot be
        // derived from a prose one. Icons are unaffected: Material Symbols draws them,
        // and the brand marks fall back to the Nerd Font per glyph.
        Section {
            span:   1
            glyph:  "󰛖"
            title:  Translation.tr("Type")
            accent: Colors.of(QsWindow.window).primary

            FontPicker {
                label:    Translation.tr("Text")
                help:     Translation.tr("The font for labels, titles and body copy everywhere in the shell.")
                value:    Config.fontFamily
                fallback: Tokens.defaultFamily
                onPicked: function (name) { Config.fontFamily = name }
            }

            FontPicker {
                label:    Translation.tr("Numerals")
                help:     Translation.tr("The font for throughput, timers and other figures that must line up. A monospace face is best.")
                value:    Config.fontMonoFamily
                fallback: Tokens.defaultMono
                onPicked: function (name) { Config.fontMonoFamily = name }
            }

            FontPicker {
                label:    Translation.tr("Display")
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
        // Density, corners, opacity and shadow in one card: four sliders of the same
        // kind, the same height as the Type card beside them, so the row is flush.
        Section {
            span:   1
            glyph:  "󰘇"
            title:  Translation.tr("Shape")
            accent: Colors.of(QsWindow.window).primary

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
            // Which ladder the radius scales: the shell's own, or End-4's rounder one.
            // Global: every panel, card, button and field — and the bar, flush to the edges.
            QuickToggleTile {
                Layout.fillWidth: true
                roomy:  true
                symbol: "square"
                label:  Translation.tr("Square corners")
                accent: Colors.of(QsWindow.window).primary
                active: Config.barShape
                subLabel: Config.barShape ? Translation.tr("Everywhere, and the bar edge to edge")
                                          : Translation.tr("Rounded, at the radius set here")
                onToggled: Config.toggleShape()
            }
            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "default", label: Translation.tr("Corners"),    icon: "crop_free" },
                    { value: "ii",      label: Translation.tr("Rounder"),    icon: "rounded_corner" }
                ]
                current: Config.cornerStyle
                onPicked: function (v) { Config.cornerStyle = v }
            }
            // What holds an icon in a panel header and a settings section.
            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "default",  label: Translation.tr("Default"),  icon: "settings" },
                    { value: "squircle", label: Translation.tr("Squircle"), icon: "square" },
                    { value: "cookie",   label: Translation.tr("Cookie"),   icon: "sunny" },
                    { value: "clover",   label: Translation.tr("Clover"),   icon: "star" },
                    { value: "circle",   label: Translation.tr("Circle"),   icon: "circle" }
                ]
                current: Config.iconShape
                onPicked: function (v) { Config.iconShape = v }
            }
            Fader {
                label:  Translation.tr("Opacity")
                help:   Translation.tr("How much of the desktop shows through the shell's surfaces.")
                accent: Colors.of(QsWindow.window).primary
                from:   Config.surfaceOpacityMin
                to:     1.0
                step:   0.01
                value:  Config.surfaceOpacity
                readout: Math.round(Config.surfaceOpacity * 100) + "%"
                onCommit: function (v) { Config.surfaceOpacity = v }
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
                readout: Config.shadowScale === 0 ? "Off" : Config.shadowScale.toFixed(2) + "×"
                onCommit: function (v) { Config.shadowScale = v }
            }
        }

        // ══ Motion ════════════════════════════════════════════════════════════
        // Shell-wide, and it always was: `Motion._d()` runs every duration in the app
        // through these two, so a panel, a notification, the lock screen and the bar
        // all slow down together. It used to be set from the Bar page, which is where
        // it happened to be written first — a category error that only looked harmless
        // because nowhere else offered it.
        //
        // One wrinkle worth knowing: a BAR PRESET snapshots these along with the bar's
        // own settings (Config's preset writer takes motionEnabled/motionScale), so
        // loading a preset can change the whole shell's motion. Left as it is — the
        // shipped presets round-trip through that shape.
        //
        // The switch is the card's own (its heading), so the body is just the speed.
        Section {
            span:     1
            glyph:    "󰓞"
            title:    Translation.tr("Motion")
            subtitle: Config.motionEnabled ? "" : "Off — every change is instant"
            help:     Translation.tr("Every animation in the shell — panels, notifications, the lock screen, the bar — runs through these two.")
            accent:   Colors.of(QsWindow.window).primary

            actions: Toggle {
                accent: Colors.of(QsWindow.window).primary
                checked: Config.motionEnabled
                onToggled: Config.motionEnabled = !Config.motionEnabled
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
        }

        // ══ This window ═══════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󰗋"
            title:  Translation.tr("Settings window")
            help:   Translation.tr("Window: a floating window the compositor places, like any other app. Panel: pinned to the bottom edge and merged into the frame, so it never covers the bar.")
            accent: Colors.of(QsWindow.window).primary

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: false, label: "Window", icon: "desktop_mac" },
                    { value: true,  label: "Panel",  icon: "dashboard" }
                ]
                current: Config.settingsPanel
                onPicked: function (v) { Config.settingsPanel = v }
            }

            TabStrip {
                Layout.fillWidth: true
                visible: Config.settingsPanel
                accent: Colors.of(QsWindow.window).primary
                // Every icon name needs an icons.js entry or a machine without the
                // Material Symbols font renders "?" — the align_horizontal_* family
                // has none, so these say the same thing with mapped glyphs.
                model: [
                    { value: "left",   label: "Left",   icon: "chevron_left" },
                    { value: "center", label: "Centre", icon: "circle" },
                    { value: "right",  label: "Right",  icon: "chevron_right" }
                ]
                current: Config.settingsPanelSide
                onPicked: function (v) { Config.settingsPanelSide = v }
            }
        }
    }
}
