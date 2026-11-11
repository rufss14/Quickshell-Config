pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/kelvin.js" as Kelvin

// ── NightLightPage — Appearance › Night light ─────────────────────────────────
// The screen-warming controls. services/NightLight.qml owns the backend, the
// schedule arithmetic and the "is it on right now" answer; this page shows and sets.
//
// ── The warmth is the page ────────────────────────────────────────────────────
// A number in kelvin means nothing until you have seen it, so the setting IS a
// picture: a strip running from neutral daylight to the temperature you chose, with
// the slider under it and the warmth named in words. Everything else on the page is
// about WHEN, and those are tiles you tap.
//
// ── It says which tool is doing it ────────────────────────────────────────────
// Two different programs can be behind this and both are optional, so night light
// behaving differently on two machines is expected rather than a bug.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property string blocker: NightLight.blocker()
    readonly property bool   usable:  root.blocker === ""

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰖔"
        title:     Translation.tr("Night")
        titleTail: "light"
        accent:    Colors.of(QsWindow.window).primary
        // The service's own summary, so the page and the bar pill agree.
        subtitle:  root.usable ? NightLight.statusText : root.blocker

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            enabled: root.usable
            checked: Config.nightLight
            onToggled: Config.nightLight = !Config.nightLight
        }

        // ══ Not installed ═════════════════════════════════════════════════════
        // A missing optional tool disables the controls with a reason rather than
        // letting you flip a switch that silently does nothing.
        Section {
            span:     3
            visible:  NightLight.probed && !NightLight.available
            glyph:    "󰀪"
            title:    Translation.tr("Needs a backend")
            subtitle: Translation.tr("Install one, then reload the shell")
            accent:   Colors.of(QsWindow.window).warning

            StyledText {
                Layout.fillWidth: true
                text: "sudo pacman -S hyprsunset    # Hyprland's own\n"
                    + "sudo pacman -S gammastep     # any wlroots compositor"
                variant: "caption"
                font.family: Tokens.fontMono
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ══ The warmth ════════════════════════════════════════════════════════
        Section {
            span:    3
            enabled: root.usable
            opacity: root.usable ? 1 : 0.5
            glyph:   "󰃟"
            title:   Translation.tr("Warmth")
            accent:  Colors.of(QsWindow.window).primary
            subtitle: Kelvin.describe(Config.nightLightTemp) + "  ·  "
                    + Config.nightLightTemp + "K"
                    + (NightLight.available ? "  ·  via " + NightLight.backend : "")

            // The colours here are computed from the temperature (services/kelvin.js,
            // tested) rather than taken from the palette — the same sanctioned case as
            // SpectrumPicker's hue wheel: this is the gamut you choose FROM, and
            // theming it would stop it showing the one thing it exists to show.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: Tokens.radiusSm

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Kelvin.hex(6500) }
                    GradientStop { position: 1.0; color: Kelvin.hex(Config.nightLightTemp) }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    // Drawn on the swatch, so they must stay legible against it:
                    // black, which every temperature from candlelight to daylight is
                    // light enough to carry. Colors.shadow is the palette's one
                    // constant black (#000000 in every generated scheme).
                    StyledText {
                        text: Translation.tr("6500K neutral")
                        variant: "micro"
                        color: Colors.of(QsWindow.window).shadow
                        opacity: 0.6
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Config.nightLightTemp + "K"
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).shadow
                    }
                }
            }

            // SliderRow, not Fader: kelvin in 100K steps is a number you land on.
            SliderRow {
                label: Translation.tr("Temperature")
                help:  Translation.tr("Lower is warmer. 6500K is daylight — no change at all.")
                from:  Config.nightLightTempMin
                to:    Config.nightLightTempMax
                step:  100
                value: Config.nightLightTemp
                readout: Config.nightLightTemp + "K"
                numberWidth: 54
                onCommit: function (v) { Config.nightLightTemp = Math.round(v) }
            }
        }

        // ══ When ══════════════════════════════════════════════════════════════
        QuickToggleTile {
            roomy: true
            symbol: "schedule"
            label:  Translation.tr("On a schedule")
            accent: Colors.of(QsWindow.window).primary
            active: Config.nightLightAuto
            available: root.usable
            subLabel: !Config.nightLightAuto
                ? "Stays on until you turn it off"
                : NightLight.haveSun
                ? "Tonight: " + NightLight.startText + " until " + NightLight.endText
                : Config.nightLightFrom + " until " + Config.nightLightTo
            onToggled: Config.nightLightAuto = !Config.nightLightAuto
        }

        QuickToggleTile {
            roomy: true
            symbol: "wb_twilight"
            label:  Translation.tr("Follow the sun")
            accent: Colors.of(QsWindow.window).primary
            active: Config.nightLightFollowSun && Weather.hasLocation
            // "Needs a location" is actionable; a dead tile is not.
            available: Config.nightLightAuto && Weather.hasLocation && root.usable
            subLabel: !Weather.hasLocation
                ? "Needs a location — set one in Desktop › Style › Weather"
                : "Sunset to sunrise, from your weather location"
            onToggled: Config.nightLightFollowSun = !Config.nightLightFollowSun
        }

        // The fixed times, only while they are what is actually in use — a pair of
        // fields the sun is silently overriding would be controls that lie.
        Section {
            span:    1
            visible: Config.nightLightAuto && !NightLight.haveSun
            enabled: root.usable
            glyph:   "󰅐"
            title:   Translation.tr("Fixed times")
            accent:  Colors.of(QsWindow.window).primary
            help:    Translation.tr("From and until, as HH:MM. Crossing midnight (20:00 until 07:00) is the normal case.")

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: "20:00"
                    seed: Config.nightLightFrom
                    onCommitted: function (v) { Config.nightLightFrom = v.trim() }
                }
                StyledText { text: "until"; variant: "caption"; emphasis: "dim" }
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: "07:00"
                    seed: Config.nightLightTo
                    onCommitted: function (v) { Config.nightLightTo = v.trim() }
                }
            }
        }

        // ══ Anti-flashbang ════════════════════════════════════════════════════
        // Independent of the warmth backend: it's a Hyprland screen shader
        // (services/AntiFlash), so it works without hyprsunset or gammastep.
        QuickToggleTile {
            roomy: true
            symbol: "brightness_6"
            label:  Translation.tr("Anti-flashbang")
            accent: Colors.of(QsWindow.window).primary
            active: Config.antiFlash
            subLabel: !Config.antiFlash ? "Dims the screen while what's on it is glaring"
                    : !AntiFlash.active ? "Waiting for night"
                    : AntiFlash.gain < 0.999 ? "Dimmed to " + Math.round(AntiFlash.gain * 100) + "%"
                    : "Watching — nothing glaring"
            onToggled: Config.antiFlash = !Config.antiFlash
        }

        QuickToggleTile {
            roomy: true
            symbol: "bedtime"
            label:  Translation.tr("Only at night")
            accent: Colors.of(QsWindow.window).primary
            active: Config.antiFlashNightOnly
            available: Config.antiFlash
            subLabel: Config.antiFlashNightOnly ? "During Night light's hours"
                    : "Day and night"
            onToggled: Config.antiFlashNightOnly = !Config.antiFlashNightOnly
        }

        Section {
            span:    1
            visible: Config.antiFlash
            glyph:   "\u{F00DF}"
            title:   Translation.tr("How glaring")
            accent:  Colors.of(QsWindow.window).primary
            subtitle: AntiFlash.brightness >= 0
                ? "Now: " + Math.round(AntiFlash.brightness * 100) + "% bright"
                : "Measures the focused screen once a second"

            SliderRow {
                label: Translation.tr("Dims above")
                from:  30
                to:    90
                step:  5
                value: Math.round(Config.antiFlashThreshold * 100)
                readout: Math.round(Config.antiFlashThreshold * 100) + "%"
                numberWidth: 44
                onCommit: function (v) { Config.antiFlashThreshold = Math.round(v) / 100 }
            }
            SliderRow {
                label: Translation.tr("Never below")
                from:  25
                to:    90
                step:  5
                value: Math.round(Config.antiFlashFloor * 100)
                readout: Math.round(Config.antiFlashFloor * 100) + "%"
                numberWidth: 44
                onCommit: function (v) { Config.antiFlashFloor = Math.round(v) / 100 }
            }
        }
    }
}
