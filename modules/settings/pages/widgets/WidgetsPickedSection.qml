pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../.."

// ── WidgetsPickedSection ── "On this screen": which screen the map shows, the widgets on it to pick
// from, and (once one is picked) what you do TO it: its size, move it to another screen, remove it.
// The picked widget's own options follow in WidgetsOptionsSection / WidgetsPhoto*Section.
// Part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to.
Section {
    id: onScreen
    required property var page

    grouped:  true
    visible:  DesktopWidgets.shown.length > 0
    symbol:   "computer"
    title:    Translation.tr("On this screen")
    subtitle: page.selected ? (DesktopWidgets.info(page.selected.type)?.label ?? Translation.tr("Widget"))
                            : Translation.tr("%1 placed").arg(DesktopWidgets.forScreen(page.mapScreen).length)
    help:     Translation.tr("Pick one here or on the map to change its size and options, or drag it on the map to move it.")

    // The things you do to the picked widget. Removing throws away its size, position and options, all of
    // which are in the record, so the undo bar can put it back exactly.
    actions: ChipTray {
        visible: !!onScreen.page.selected
        ChipButton {
            id: screenBtn
            visible: Quickshell.screens.length > 1
            symbol: "monitor"
            tint: Colors.of(QsWindow.window).primary
            onActivated: onScreen.page.openScreenMenu(screenBtn, onScreen.page.selectedId, onScreen.page.selected.screen)
        }
        ChipButton {
            symbol: "delete"
            tint: Colors.of(QsWindow.window).danger
            onActivated: {
                const keep = onScreen.page.selected
                const name = DesktopWidgets.info(keep.type)?.label ?? keep.type
                onScreen.page.selectedId = -1
                DesktopWidgets.remove(keep.id)
                onScreen.page.undoBar.show(Translation.tr("Removed %1").arg(name),
                                         function () { DesktopWidgets.restoreWidget(keep) })
            }
        }
        ChipButton {
            symbol: "close"
            tint: Colors.of(QsWindow.window).primary
            onActivated: onScreen.page.selectedId = -1
        }
    }

    // Which screen, on a multi-monitor setup.
    SettingRow {
        visible: Quickshell.screens.length > 1
        label:   Translation.tr("Screen")
        detail:  Translation.tr("The one the map shows")

        TabStrip {
            connected: true
            implicitWidth: Tokens.fieldHeight * 5 * Quickshell.screens.length
            model: Quickshell.screens.map(s => ({ value: s.name, label: s.name, icon: "monitor" }))
            current: onScreen.page.mapScreen
            onPicked: function (v) {
                onScreen.page.mapScreen = v
                onScreen.page.selectedId = -1
                onScreen.page.layoutScreen = v
            }
        }
    }

    // The widgets on this screen, to pick from.
    ChipRow {
        Layout.fillHeight: false
        visible: DesktopWidgets.forScreen(onScreen.page.mapScreen).length > 0
        accent: Colors.of(QsWindow.window).primary
        model: DesktopWidgets.forScreen(onScreen.page.mapScreen).map(w => ({
            value: w.id, label: DesktopWidgets.info(w.type)?.label ?? w.type }))
        current: onScreen.page.selectedId
        onPicked: function (v) { onScreen.page.selectedId = v }
    }

    SettingRow {
        visible: !!onScreen.page.selected
                 && (DesktopWidgets.info(onScreen.page.selected.type)?.sizes ?? []).length > 1
        label:   Translation.tr("Size")

        TabStrip {
            connected: true
            implicitWidth: Tokens.fieldHeight * 10
            model: (onScreen.page.selected
                ? (DesktopWidgets.info(onScreen.page.selected.type)?.sizes ?? [])
                : []).map(s => ({
                    value: s,
                    label: s.charAt(0).toUpperCase() + s.slice(1) }))
            current: onScreen.page.selected ? onScreen.page.selected.size : ""
            onPicked: function (v) { DesktopWidgets.setSize(onScreen.page.selectedId, v) }
        }
    }
}
