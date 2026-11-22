pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/deskmenu.js" as Menus
import "../../desktop/widgets/toggles.js" as Toggles

// ── DeskMenuPage — Desktop › Desktop menu ─────────────────────────────────────
// The menu a right-click on the empty desktop opens (modules/desktop/DeskMenu): how many of your
// pictures it shows, which round buttons it carries, and which places it lists, each in the order
// you put them. "Try it" opens it in the middle of the screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰕮"
        title:     Translation.tr("Desktop")
        titleTail: Translation.tr("menu")
        accent:    root.palette.primary
        subtitle:  Config.deskMenu ? Translation.tr("Right-click the empty desktop")
                                   : Translation.tr("Off, a right-click on the desktop does nothing")

        // The master switch with its own label: a bare switch in a header says nothing about what it turns off.
        actions: RowLayout {
            spacing: Tokens.spacingSm

            StyledText {
                text: Translation.tr("Desktop menu")
                variant: "label"
            }
            Toggle {
                accent: root.palette.primary
                accessibleName: Translation.tr("Desktop menu")
                checked: Config.deskMenu
                onToggled: Config.deskMenu = !Config.deskMenu
            }
        }

        // ══ Pictures ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  Config.deskMenu
            opacity:  Config.deskMenu ? 1 : 0.5
            symbol:   "wallpaper"
            title:    Translation.tr("Pictures")
            subtitle: Config.deskMenuWallpapers === 0 ? Translation.tr("Hidden")
                                                      : Translation.tr("%1 under Personalize").arg(Config.deskMenuWallpapers)

            SliderRow {
                label: Translation.tr("Shown")
                help:  Translation.tr("How many pictures Personalize shows: the one on the desktop, then your newest. 0 hides them.")
                from: 0
                to: 5
                step: 1
                value: Config.deskMenuWallpapers
                readout: Config.deskMenuWallpapers === 0 ? Translation.tr("Off") : "" + Config.deskMenuWallpapers
                numberWidth: 52
                onCommit: function (v) { Config.deskMenuWallpapers = Math.round(v) }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Preview the menu")
                detail: Translation.tr("Opens it in the middle of the screen")
                onTapped: UiState.openDeskMenu("", -1, -1)

                ChipButton {
                    symbol: "play_arrow"
                    label: Translation.tr("Try it")
                    solid: true
                    onActivated: UiState.openDeskMenu("", -1, -1)
                }
            }
        }

        // ══ Round buttons ═════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  Config.deskMenu
            opacity:  Config.deskMenu ? 1 : 0.5
            symbol:   "dashboard"
            title:    Translation.tr("Quick settings")
            subtitle: Translation.tr("%1 chosen, 6 at most").arg(Config.deskMenuSwitches.length)
            help:     Translation.tr("Up to six round switches. Switches stay open for the next one; one-offs close the menu.")

            PickOrderList {
                Layout.fillWidth: true
                table: Toggles.PICKABLE
                allIds: Toggles.ALL
                shown: Config.deskMenuSwitches
                max: 6
                onPicked: list => Config.deskMenuSwitches = list
            }
        }

        // ══ Places ════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  Config.deskMenu
            opacity:  Config.deskMenu ? 1 : 0.5
            symbol:   "view_quilt"
            title:    Translation.tr("More options")
            subtitle: Translation.tr("%1 of %2 listed").arg(Config.deskMenuPlaces.length).arg(Menus.PLACE_ORDER.length)
            help:     Translation.tr("Tap a place to list it under Show more options; the arrows set the order.")

            PickOrderList {
                Layout.fillWidth: true
                table: Menus.PLACES
                allIds: Menus.PLACE_ORDER
                shown: Config.deskMenuPlaces
                onPicked: list => Config.deskMenuPlaces = list
            }
        }

        // ══ Tools ═════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  Config.deskMenu
            opacity:  Config.deskMenu ? 1 : 0.5
            symbol:   "photo_camera"
            title:    Translation.tr("Icon row")
            subtitle: Translation.tr("%1 chosen, 6 at most").arg(Config.deskMenuTools.length)
            help:     Translation.tr("Up to six, along the top. A capture closes the menu; a recording stays.")

            PickOrderList {
                Layout.fillWidth: true
                table: Menus.TOOLS
                allIds: Menus.TOOL_ORDER
                shown: Config.deskMenuTools
                max: 6
                onPicked: list => Config.deskMenuTools = list
            }
        }
    }
}
