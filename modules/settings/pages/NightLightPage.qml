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
// picture: the loud card is a strip running from neutral daylight to the temperature
// you chose, the number large with its name in words, the slider, and the page's one
// master switch. It stands pinned in the page's left column (SettingsPage, grouped);
// the groups beside it are about WHEN, as grouped rows you tap anywhere on. At the
// window's opening size the whole page fits without scrolling.
//
// ── "Night" is set once, the schedule is a separate switch ────────────────────
// Not one Manual / Fixed / Sun choice: `nightLightFollowSun` matters even while the
// schedule is off, because AntiFlash's "only at night" reads NightLight.inNightWindow,
// which follows the sun (or the fixed hours) either way.
//
// ── It says which tool is doing it ────────────────────────────────────────────
// Two different programs can be behind this and both are optional, so night light
// behaving differently on two machines is expected rather than a bug.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property string blocker: NightLight.blocker()
    readonly property bool   usable:  root.blocker === ""

    // kelvin.js names 6500K with a dash ("Neutral — no adjustment"), which UI text does not use.
    readonly property string warmthName: Config.nightLightTemp >= 6400
        ? Translation.tr("Neutral, no change")
        : Translation.tr(Kelvin.describe(Config.nightLightTemp))

    // Room for "20:00" in a field, with its padding.
    readonly property int timeFieldWidth: Tokens.fieldHeight * 2 + Tokens.spacingLg
    // Two named segments of the connected choice, each with its icon and label.
    readonly property int choiceWidth: Tokens.fieldHeight * 10

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        // The warmth card pinned beside the "when" groups: the one page where a live picture
        // stays in view while you set it.
        groupLayout: "columns"
        glyph:     "󰖔"
        title:     Translation.tr("Night")
        titleTail: "light"
        accent:    Colors.of(QsWindow.window).primary
        // The service's own summary, so the page and the bar pill agree.
        subtitle:  root.usable ? NightLight.statusText : root.blocker

        // ══ Not installed ═════════════════════════════════════════════════════
        // A missing optional tool disables the controls with a reason rather than
        // letting you flip a switch that silently does nothing.
        // Under the hero: it explains why the hero is greyed out.
        Section {
            fullRow:  true
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
            id: warmCard
            hero:    true
            enabled: root.usable
            opacity: root.usable ? 1 : 0.5

            // The colours here are computed from the temperature (services/kelvin.js,
            // tested) rather than taken from the palette — the same sanctioned case as
            // SpectrumPicker's hue wheel: this is the gamut you choose FROM, and
            // theming it would stop it showing the one thing it exists to show.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                // Concentric with the card: its radius less the card's padding.
                radius: Tokens.radiusXl - warmCard.padding

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Kelvin.hex(6500) }
                    GradientStop { position: 1.0; color: Kelvin.hex(Config.nightLightTemp) }
                }

                // Drawn on the swatch, so it must stay legible against it: black,
                // which every temperature from candlelight to daylight is light enough
                // to carry. Colors.shadow is the palette's one constant black.
                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("6500K neutral")
                    variant: "micro"
                    color: Colors.of(QsWindow.window).shadow
                    opacity: 0.6
                }
            }

            // The number, its name, and the page's one master switch.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    StyledText {
                        text: Config.nightLightTemp + "K"
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: warmCard.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: NightLight.available
                            ? Translation.tr("%1 · via %2").arg(root.warmthName).arg(NightLight.backend)
                            : root.warmthName
                        variant: "caption"
                        color: warmCard.inkDim
                        elide: Text.ElideRight
                    }
                }

                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    accent:  Colors.of(QsWindow.window).primary
                    accessibleName: Translation.tr("Night light")
                    checked: Config.nightLight
                    onToggled: Config.nightLight = !Config.nightLight
                }
            }

            // SliderRow, not Fader: kelvin in 100K steps is a number you land on.
            SliderRow {
                label: Translation.tr("Temperature")
                help:  Translation.tr("Lower is warmer. 6500K is daylight, no change at all.")
                from:  Config.nightLightTempMin
                to:    Config.nightLightTempMax
                step:  100
                value: Config.nightLightTemp
                readout: Config.nightLightTemp + "K"
                numberWidth: 54
                ink: warmCard.ink
                inkDim: warmCard.inkDim
                onCommit: function (v) { Config.nightLightTemp = Math.round(v) }
            }
        }

        // ══ When it is night ═══════════════════════════════════════════════════
        // What "night" means is one choice shared by two features: the schedule below
        // and anti-flashbang's "only at night" both read NightLight.inNightWindow, so the
        // hours (or the sun) are set here once, whether or not the schedule is on.
        Section {
            grouped:  true
            enabled:  root.usable
            symbol:   "bedtime"
            title:    Translation.tr("Night")
            subtitle: NightLight.haveSun
                ? Translation.tr("Tonight %1 until %2").arg(NightLight.startText).arg(NightLight.endText)
                : Translation.tr("%1 until %2").arg(Config.nightLightFrom).arg(Config.nightLightTo)

            SettingRow {
                label:  Translation.tr("Night is")
                detail: Config.nightLightFollowSun && !Weather.hasLocation
                    ? Translation.tr("Needs a weather location: System › Language & region")
                    : ""
                help:   Translation.tr("Sunset to sunrise comes from your weather location. Without one, the fixed hours are used.")

                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.choiceWidth
                    model: [
                        { value: false, label: Translation.tr("Fixed hours"),       icon: "schedule" },
                        { value: true,  label: Translation.tr("Sunset to sunrise"), icon: "wb_twilight" }
                    ]
                    current: Config.nightLightFollowSun
                    onPicked: function (v) { Config.nightLightFollowSun = v }
                }
            }

            // The fixed hours, only while they are what is actually in use: a pair of
            // fields the sun is silently overriding would be controls that lie.
            SettingRow {
                visible: !NightLight.haveSun
                label:   Translation.tr("Hours")
                help:    Translation.tr("From and until, as HH:MM. Crossing midnight (20:00 until 07:00) is the normal case.")

                RowLayout {
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.preferredWidth: root.timeFieldWidth
                        placeholder: "20:00"
                        seed: Config.nightLightFrom
                        onCommitted: function (v) { Config.nightLightFrom = v.trim() }
                    }
                    StyledText { text: Translation.tr("until"); variant: "caption"; emphasis: "dim" }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.preferredWidth: root.timeFieldWidth
                        placeholder: "07:00"
                        seed: Config.nightLightTo
                        onCommitted: function (v) { Config.nightLightTo = v.trim() }
                    }
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Turn on at night")
                help:   Translation.tr("Warms the screen only during the night hours. The switch above still has to be on.")
                detail: Config.nightLightAuto ? Translation.tr("Off during the day")
                                              : Translation.tr("Stays on until you turn it off")
                onTapped: Config.nightLightAuto = !Config.nightLightAuto

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.nightLightAuto
                    onToggled: Config.nightLightAuto = !Config.nightLightAuto
                }
            }
        }

        // ══ Anti-flashbang ════════════════════════════════════════════════════
        // Independent of the warmth backend: it's a Hyprland screen shader
        // (services/AntiFlash), so it works without hyprsunset or gammastep.
        Section {
            grouped:  true
            symbol:   "brightness_6"
            title:    Translation.tr("Anti-flashbang")
            help:     Translation.tr("A Hyprland screen shader, so it works without hyprsunset or gammastep. It measures the focused screen once a second.")
            subtitle: Config.antiFlash && AntiFlash.brightness >= 0
                ? Translation.tr("Now %1% bright").arg(Math.round(AntiFlash.brightness * 100))
                : ""

            SettingRow {
                rowTap: true
                label:  Translation.tr("Use anti-flashbang")
                detail: !Config.antiFlash ? Translation.tr("Dims the screen while what's on it is glaring")
                      : !AntiFlash.active ? Translation.tr("Waiting for night")
                      : AntiFlash.gain < 0.999 ? Translation.tr("Dimmed to %1%").arg(Math.round(AntiFlash.gain * 100))
                      : Translation.tr("Watching, nothing glaring")
                onTapped: Config.antiFlash = !Config.antiFlash

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.antiFlash
                    onToggled: Config.antiFlash = !Config.antiFlash
                }
            }

            SettingRow {
                rowTap: true
                enabled: Config.antiFlash
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Only at night")
                help:   Translation.tr("Night light's hours, from its schedule or the sun, even while Night light itself is off.")
                detail: Config.antiFlashNightOnly ? Translation.tr("During Night light's hours")
                                                  : Translation.tr("Day and night")
                onTapped: Config.antiFlashNightOnly = !Config.antiFlashNightOnly

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.antiFlashNightOnly
                    onToggled: Config.antiFlashNightOnly = !Config.antiFlashNightOnly
                }
            }

            SliderRow {
                enabled: Config.antiFlash
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
                enabled: Config.antiFlash
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
