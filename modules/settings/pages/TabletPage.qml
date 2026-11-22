pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── TabletPage: Devices › Tablet ──────────────────────────────────────────────
// A drawing tablet's rare settings: the pressure range, what each express key does, the one-time permission
// that lets the shell read the pen, and what the device reports. The daily half (where the pen lands on the
// screen, the area, the profiles, a pad to test on) is the Tablet page on the bottom-left island.
// services/Tablet.qml owns all of it; this shows and sets.
//
// ── Why some of it is switched off with a reason ──────────────────────────────
// The pressure range is Hyprland's and always works. The live pressure bar and the express keys are read
// from the tablet's input nodes, which need permission once (`tablet-access.sh`, a udev rule), and a key that
// sends a key chord needs `wtype`. Each says what it is waiting for instead of doing nothing on a click.
//
// Express keys run a key chord, a command (no shell: what the field says is what runs) or switch profiles.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var prof: Tablet.profile
    readonly property bool here: Tablet.present
    readonly property string liveBlocker: Tablet.liveBlocker()
    readonly property int keyCount: Tablet.present ? Tablet.device.keys : 0

    // Looking at the page is a reason to look for the tablet again, and to read the pen for the live bar.
    Component.onCompleted: { Tablet.reprobe(); Tablet.acquireLive() }
    Component.onDestruction: Tablet.releaseLive()

    readonly property string status: !Config.tabletOn ? Translation.tr("Off")
        : !Tablet.probed ? Translation.tr("Looking for a tablet")
        : Tablet.udevMissing ? Translation.tr("Needs udevadm, which comes with systemd")
        : !Tablet.present ? Translation.tr("No tablet found")
        : Tablet.lastError !== "" ? Tablet.lastError
        : Tablet.device.widthMm + " × " + Tablet.device.heightMm + " mm"

    function _pct(v) { return Math.round(v * 100) + "%" }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        groupLayout: "columns"
        glyph:     "\u{F03EB}"
        title:     Translation.tr("Draw")
        titleTail: "tablet"
        accent:    root.palette.primary
        subtitle:  root.status

        actions: ChipTray {
            ChipButton {
                ArmLatch {
                    id: resetProfile
                    onConfirmed: Tablet.resetProfile()
                }
                visible: root.here
                label:  resetProfile.armed ? Translation.tr("Reset this profile?") : Translation.tr("Reset profile")
                symbol: resetProfile.armed ? "warning" : "restart_alt"
                on:     resetProfile.armed
                tint:   resetProfile.armed ? root.palette.danger : root.palette.primary
                onActivated: resetProfile.trigger()
            }
        }

        // ══ The tablet ════════════════════════════════════════════════════════
        Section {
            id: card
            hero: true

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.here ? (Tablet.device.model !== "" ? Tablet.device.model : Tablet.device.name) : Translation.tr("Tablet")
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        color: card.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.status
                        variant: "caption"
                        color: card.inkDim
                        elide: Text.ElideRight
                    }
                }
                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    accent: root.palette.primary
                    accessibleName: Translation.tr("Tablet")
                    checked: Config.tabletOn
                    onToggled: Config.tabletOn = !Config.tabletOn
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.prof ? Translation.tr("Profile: %1").arg(root.prof.name) : ""
                visible: text !== ""
                variant: "caption"
                font.weight: Font.DemiBold
                color: card.inkDim
            }
        }

        // ══ Pressure ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  root.here && Tablet.ready
            symbol:   "tune"
            title:    Translation.tr("Pen pressure")
            subtitle: root.prof ? Translation.tr("From %1 to %2").arg(root._pct(root.prof.pressure.min)).arg(root._pct(root.prof.pressure.max))
                                : Translation.tr("No tablet")

            SliderRow {
                label: Translation.tr("Light touch")
                help:  Translation.tr("How hard you press before the pen starts to draw. Raise it to ignore a pen that just rests on the surface.")
                from:  0
                to:    0.9
                step:  0.01
                value: root.prof ? root.prof.pressure.min : 0
                readout: root.prof ? root._pct(root.prof.pressure.min) : "–"
                numberWidth: 48
                onCommit: function (v) { Tablet.setPressure(v, root.prof ? root.prof.pressure.max : 1) }
            }
            SliderRow {
                label: Translation.tr("Full press")
                help:  Translation.tr("The pressure that counts as all the way down. Lower it to reach full strokes with a lighter hand.")
                from:  0.1
                to:    1
                step:  0.01
                value: root.prof ? root.prof.pressure.max : 1
                readout: root.prof ? root._pct(root.prof.pressure.max) : "–"
                numberWidth: 48
                onCommit: function (v) { Tablet.setPressure(root.prof ? root.prof.pressure.min : 0, v) }
            }
            SettingRow {
                label:  Translation.tr("Live pressure")
                detail: root.liveBlocker
                help:   Translation.tr("What the pen reports right now, before the range above is applied.")

                Meter {
                    implicitWidth: Tokens.fieldHeight * 5
                    value: Tablet.pen !== null && Tablet.pen.in === true ? Tablet.pen.p : 0
                    fillDuration: Motion.track
                    opacity: root.liveBlocker === "" ? 1 : 0.4
                }
            }
        }

        // ══ Express keys ══════════════════════════════════════════════════════
        Section {
            grouped:  true
            visible:  root.keyCount > 0
            enabled:  root.here && Tablet.ready && root.liveBlocker === ""
            symbol:   "keyboard"
            title:    Translation.tr("Express keys")
            subtitle: root.liveBlocker !== "" ? root.liveBlocker
                    : Tablet.keyNote !== "" ? Tablet.keyNote
                    : Translation.tr("Press a key on the tablet to try it")

            Repeater {
                model: root.keyCount
                delegate: SettingRow {
                    id: keyRow
                    required property int index
                    readonly property var binding: Tablet.keys[keyRow.index] ?? ({ kind: "none", value: "" })
                    readonly property bool held: Tablet.padDown[keyRow.index] === true

                    label:  Translation.tr("Key %1").arg(keyRow.index + 1)
                    symbol: "bolt"
                    symbolFill: keyRow.held ? 1 : 0
                    symbolColor: keyRow.held ? root.palette.primary : root.palette.fgMuted
                    detail: keyRow.binding.kind === "chord" && Tablet.chordBlocker() !== "" ? Tablet.chordBlocker() : ""

                    RowLayout {
                        spacing: Tokens.spacingMd

                        TabStrip {
                            connected: true
                            implicitWidth: Tokens.fieldHeight * 8
                            model: [
                                { value: "none",    label: Translation.tr("Nothing"), icon: "block" },
                                { value: "chord",   label: Translation.tr("Keys"),    icon: "keyboard" },
                                { value: "command", label: Translation.tr("Command"), icon: "terminal" },
                                { value: "profile", label: Translation.tr("Profile"), icon: "layers" }
                            ]
                            current: keyRow.binding.kind
                            onPicked: function (v) { Tablet.setKey(keyRow.index, { kind: v, value: v === "profile" ? "next" : "" }) }
                        }
                        InputField {
                            Layout.preferredWidth: Tokens.fieldHeight * 5
                            visible: keyRow.binding.kind === "chord" || keyRow.binding.kind === "command"
                            mono: keyRow.binding.kind === "chord"
                            placeholder: keyRow.binding.kind === "chord" ? Translation.tr("ctrl+z") : Translation.tr("notify-send hello")
                            seed: keyRow.binding.value
                            onCommitted: function (v) { Tablet.setKey(keyRow.index, { kind: keyRow.binding.kind, value: v }) }
                        }
                        TabStrip {
                            connected: true
                            implicitWidth: Tokens.fieldHeight * 5
                            visible: keyRow.binding.kind === "profile"
                            model: [
                                { value: "next", label: Translation.tr("Next") },
                                { value: "prev", label: Translation.tr("Previous") }
                            ]
                            current: keyRow.binding.value
                            onPicked: function (v) { Tablet.setKey(keyRow.index, { kind: "profile", value: v }) }
                        }
                    }
                }
            }
        }

        // ══ Permission ════════════════════════════════════════════════════════
        Section {
            grouped:  true
            visible:  root.here
            symbol:   "key"
            title:    Translation.tr("Live pen")
            subtitle: Tablet.present && Tablet.device.access ? Translation.tr("Allowed")
                    : Tablet.rule === "installed" ? Translation.tr("Allowed, waiting for the tablet to be plugged in again")
                    : Translation.tr("Needs permission, once")

            SettingRow {
                label:  Translation.tr("Read the tablet")
                detail: Tablet.accessError
                help:   Translation.tr("The live pen and the express keys come from the tablet's input device, which only the system may open. This adds one udev rule that lets you, while you are logged in, and nothing else. It asks for your password once.")
                wrapDetail: true

                ChipButton {
                    tonal: true
                    symbol: Tablet.rule === "installed" ? "delete" : "key"
                    label: Tablet.accessBusy ? Translation.tr("Waiting for permission")
                         : Tablet.rule === "installed" ? Translation.tr("Remove the rule") : Translation.tr("Allow live pen")
                    enabled: !Tablet.accessBusy
                    onActivated: Tablet.rule === "installed" ? Tablet.removeAccess() : Tablet.grantAccess()
                }
            }
        }

        // ══ The device ════════════════════════════════════════════════════════
        Section {
            grouped:  true
            visible:  root.here
            symbol:   "tablet"
            title:    Translation.tr("Device")
            subtitle: Tablet.present ? Tablet.device.name : ""

            SettingRow {
                label: Translation.tr("Size")
                StyledText {
                    text: Tablet.present ? Tablet.device.widthMm + " × " + Tablet.device.heightMm + " mm" : ""
                    font.features: ({ tnum: 1 })
                    color: root.palette.fgMuted
                }
            }
            SettingRow {
                label: Translation.tr("Express keys")
                StyledText {
                    text: String(root.keyCount)
                    font.features: ({ tnum: 1 })
                    color: root.palette.fgMuted
                }
            }
            SettingRow {
                label:  Translation.tr("Pressure levels")
                detail: Tablet.info === null ? Translation.tr("Shown once the live pen is on") : ""
                StyledText {
                    text: Tablet.info !== null ? String((Tablet.info.p | 0) + 1) : "–"
                    font.features: ({ tnum: 1 })
                    color: root.palette.fgMuted
                }
            }
            SettingRow {
                label:  Translation.tr("Reports a second")
                detail: Tablet.rate === 0 ? Translation.tr("Shown while the pen is on the tablet") : ""
                StyledText {
                    text: Tablet.rate > 0 ? String(Tablet.rate) : "–"
                    font.features: ({ tnum: 1 })
                    color: root.palette.fgMuted
                }
            }
            SettingRow {
                label: Translation.tr("Name in Hyprland")
                StyledText {
                    text: Tablet.present ? Tablet.device.hypr : ""
                    font.family: Tokens.fontMono
                    color: root.palette.fgMuted
                }
            }
        }
    }
}
