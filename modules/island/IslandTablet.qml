pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "tablet"

// ── IslandTablet ──────────────────────────────────────────────────────────────
// A drawing tablet on the bottom-left island, the daily half of Settings › Tablet: where the pen lands, how
// much of the tablet it uses, which profile is in use, and a pad to try it on.
//
//   left    the loud card. The tablet drawn to its real shape with the part the pen uses as a block of accent you
//           can drag and resize, a dot where the pen is (swelling with the pressure), the express keys as discs
//           that bloom while held, a pressure bar. Under it a rail: Map, Profiles, Test.
//   Map     the screen the pen lands on, the area's size and its three tools, the orientation and absolute or
//           relative input.
//   Profiles  the tablet's sets of settings; one is in use.
//   Test    a pad whose line follows the pressure, with the numbers the tablet reports.
//
// The rules are services/tablet.js (pure, `bun scripts/test-tablet.js`); services/Tablet.qml holds the profiles,
// sends them to Hyprland and runs the helper behind the live pen. This shows and calls. The rare settings
// (pressure range, eraser, express-key actions, the one-time permission) are on Settings › Tablet.
//
// ── Four faces before it is a page ────────────────────────────────────────────
// Off (the switch), looking, no tablet, and no udevadm each say so in the PanelEmpty the panels use, with the
// one thing that helps. Nothing here starts a process of its own: the service is created by Config.tabletOn.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 16 + Tokens.spacingSm

    // "map" | "profiles" | "test"
    property string view: "map"

    // "off" | "looking" | "udev" | "none" | "ready"
    readonly property string stage: !Config.tabletOn ? "off"
        : !Tablet.probed ? "looking"
        : Tablet.udevMissing ? "udev"
        : !Tablet.present ? "none"
        : "ready"

    // The pen is read only while this page is on screen. `island part tablet profiles` opens on a view.
    Component.onCompleted: {
        const asked = UiState.islandPartFor("tablet")
        if (asked === "map" || asked === "profiles" || asked === "test") root.view = asked
        Tablet.reprobe()
        Tablet.acquireLive()
    }
    Component.onDestruction: Tablet.releaseLive()

    // ══ Not a page yet ════════════════════════════════════════════════════════
    IslandPlate {
        anchors.fill: parent
        visible: root.stage !== "ready"
        order: 0
        radius: Tokens.radiusXl

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.spacingXl * 2, Tokens.iconXl * 14)
            spacing: Tokens.spacingMd

            PanelEmpty {
                symbol: "tablet"
                quiet: root.stage !== "off"
                shape: "cookie9"
                title: root.stage === "off" ? Translation.tr("Tablet is off")
                     : root.stage === "looking" ? Translation.tr("Looking for a tablet")
                     : root.stage === "udev" ? Translation.tr("Needs udevadm")
                     : Translation.tr("No tablet found")
                text: root.stage === "off" ? Translation.tr("Turn it on to map your pen to a screen, set its pressure and use its express keys.")
                    : root.stage === "udev" ? Translation.tr("It comes with systemd, and finds tablets by their size.")
                    : root.stage === "none" ? Translation.tr("Plug it in, then look again.")
                    : ""
            }
            ChipButton {
                Layout.alignment: Qt.AlignHCenter
                visible: root.stage === "off" || root.stage === "none"
                solid: root.stage === "off"
                tonal: root.stage !== "off"
                symbol: root.stage === "off" ? "power_settings_new" : "refresh"
                label: root.stage === "off" ? Translation.tr("Turn on") : Translation.tr("Look again")
                onActivated: { if (root.stage === "off") Config.tabletOn = true; else Tablet.reprobe() }
            }
        }
    }

    // ══ The page ══════════════════════════════════════════════════════════════
    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd
        visible: root.stage === "ready"

        // ── The loud card ─────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                id: hero
                Layout.fillWidth: true
                Layout.fillHeight: true
                hero: true
                order: 0
                radius: Tokens.radiusXl

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        IslandBadge {
                            filled: true
                            size: Tokens.iconXl + Tokens.spacingMd
                            symbol: "tablet"
                            shape: "cookie9"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Tablet.present ? (Tablet.device.model !== "" ? Tablet.device.model : Tablet.device.name) : ""
                                variant: "label"
                                font.weight: Font.DemiBold
                                color: hero.ink
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Tablet.present
                                    ? Translation.tr("%1 × %2 mm").arg(Math.round(Tablet.device.widthMm)).arg(Math.round(Tablet.device.heightMm))
                                    : ""
                                variant: "caption"
                                font.features: ({ tnum: 1 })
                                color: hero.inkDim
                            }
                        }
                        StyledText {
                            Layout.fillWidth: false
                            Layout.maximumWidth: Tokens.iconXl * 4
                            text: Tablet.profile ? Tablet.profile.name : ""
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }

                    TabletMap {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ink: hero.ink
                    }

                    TabletKeys {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: false
                        ink: hero.ink
                    }

                    // The pressure, live. Without the live pen it rests at nothing.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd
                        visible: Tablet.liveBlocker() === ""

                        StyledText {
                            text: Translation.tr("Pressure")
                            variant: "caption"
                            color: hero.inkDim
                        }
                        Meter {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            value: Tablet.pen !== null && Tablet.pen.in === true ? Tablet.pen.p : 0
                            accent: root.palette.primary
                            fillDuration: Motion.track
                        }
                    }

                    // Not allowed to read the tablet yet: one line and the one button.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        visible: Tablet.present && !Tablet.device.access

                        StyledText {
                            Layout.fillWidth: true
                            text: Tablet.rule === "installed"
                                ? Translation.tr("Allowed. Unplug the tablet and plug it back in")
                                : Translation.tr("The live pen and express keys need permission to read the tablet, once")
                            variant: "caption"
                            color: hero.inkDim
                            wrapMode: Text.WordWrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: Tablet.accessError !== ""
                            text: Tablet.accessError
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: hero.ink
                            wrapMode: Text.WordWrap
                        }
                        ChipButton {
                            Layout.fillWidth: true
                            visible: Tablet.rule !== "installed"
                            tonal: true
                            tint: hero.ink
                            symbol: "key"
                            label: Tablet.accessBusy ? Translation.tr("Waiting for permission") : Translation.tr("Allow live pen")
                            enabled: !Tablet.accessBusy
                            onActivated: Tablet.grantAccess()
                        }
                    }
                }
            }

            SourceRail {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 3 * (Tokens.iconXl + Tokens.spacingMd) + Tokens.spacingSm * 2 + Tokens.spacingXs * 2
                current: root.view
                model: [
                    { value: "map", label: Translation.tr("Map"), icon: "crop", shape: "cookie9",
                      figure: Tablet.profile && Tablet.profile.output !== "" ? Tablet.profile.output : Translation.tr("All"), big: false },
                    { value: "profiles", label: Translation.tr("Profiles"), icon: "layers", shape: "clover",
                      figure: String(Tablet.profiles.length) },
                    { value: "test", label: Translation.tr("Test"), icon: "edit", shape: "sunny",
                      figure: Tablet.pen !== null && Tablet.pen.in === true ? Translation.tr("Pen") : "–",
                      big: false, live: Tablet.pen !== null && Tablet.pen.in === true }
                ]
                onPicked: v => root.view = v
            }
        }

        // ── The page ──────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TabletMapView {
                id: pageMap
                anchors.fill: parent
                opacity: root.view === "map" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transform: Translate { x: (1 - pageMap.opacity) * -16 }
            }
            TabletProfilesView {
                id: pageProfiles
                anchors.fill: parent
                opacity: root.view === "profiles" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transform: Translate { x: (1 - pageProfiles.opacity) * -16 }
            }
            TabletTestView {
                id: pageTest
                anchors.fill: parent
                opacity: root.view === "test" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transform: Translate { x: (1 - pageTest.opacity) * -16 }
            }
        }
    }
}
