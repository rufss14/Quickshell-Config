pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../state"
import "../../../desktop/widgets"
import "../../../desktop/widgets/toggles.js" as Toggles
import "../.."

// ── WidgetsPresetsSection ── two related but separate ideas that the old copy both called "layout".
// A PRESET is a named snapshot you load back onto any screen, once, like Bar's own presets. A wallpaper's OWN
// WIDGETS is live and automatic: whenever a screen shows that wallpaper, its tiles replace the normal ones, with
// no load step, and it can start from a preset without becoming one. One group says both, in that order,
// because starting a wallpaper's own widgets from a preset is the common path.
// Part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to.
Section {
    id: presetSection
    required property var page

    grouped:  true
    symbol:   "bookmarks"
    title:    Translation.tr("Layout presets")
    readonly property string key: DesktopWidgets.wallKeys[page.layoutScreen] ?? ""
    readonly property string bound: DesktopWidgets.layoutForKey(presetSection.key)
    readonly property string wallLabel: DesktopWidgets.wallName(presetSection.key)
    subtitle: DesktopWidgets.presetNames.length === 0 ? Translation.tr("None saved")
            : Translation.tr("%1 saved").arg(DesktopWidgets.presetNames.length)
    help:     Translation.tr("Click a preset to load it once, on the chosen screen. Right-click one to give the screen's wallpaper that preset LIVE instead: switch to the wallpaper and its tiles take over automatically; switch away and your normal ones return. Follows the colour scheme panel's own click-to-load / right-click-to-bind split.")

    // Which screen a preset lands on, and whose wallpaper the row below acts on.
    SettingRow {
        visible: Quickshell.screens.length > 1
        label:   Translation.tr("Screen")
        detail:  Translation.tr("Where a preset lands")

        TabStrip {
            connected: true
            implicitWidth: Tokens.fieldHeight * 5 * Quickshell.screens.length
            model: Quickshell.screens.map(s => ({ value: s.name, label: s.name, icon: "monitor" }))
            current: page.layoutScreen
            onPicked: function (v) { page.layoutScreen = v }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        StyledText {
            text: DesktopWidgets.presetNames.length === 0 ? Translation.tr("Save your first preset below")
                : Translation.tr("Tap to load · right-click to give %1 that preset, live")
                      .arg(presetSection.key !== "" ? presetSection.wallLabel : Translation.tr("this wallpaper"))
            variant: "caption"
            emphasis: "dim"
        }
        PresetChips {
            accent:    Colors.of(QsWindow.window).primary
            renamable: false
            presets:   DesktopWidgets.presetNames.map(n => ({ name: n }))
            badgeFor:  function (p) { return (DesktopWidgets.presets[p.name] || []).length + "" }
            savePlaceholder: Translation.tr("Name this preset")
            onLoad: function (name) { DesktopWidgets.applyPreset(name, page.layoutScreen) }
            onSave: function (name) {
                if (DesktopWidgets.shown.length > 0) DesktopWidgets.savePreset(name)
            }
            onRemove: function (name) {
                // The preset itself, captured before the delete.
                const keep = DesktopWidgets.presets[name]
                DesktopWidgets.deletePreset(name)
                page.undoBar.show(Translation.tr("Deleted preset “%1”").arg(name),
                             function () { DesktopWidgets.restorePreset(name, keep) })
            }
            onRightClicked: function (name) {
                DesktopWidgets.newLayoutFor(presetSection.key, page.layoutScreen, "preset:" + name)
            }
        }
    }

    // ── This wallpaper: where its widgets come from, and the one or two ways to change that ──
    SettingRow {
        visible: presetSection.key !== ""
        label:   presetSection.wallLabel
        detail:  presetSection.bound !== "" ? Translation.tr("Its own widgets") : Translation.tr("Your normal widgets")

        ChipTray {
            ChipButton {
                visible: presetSection.bound === ""
                symbol:  "content_copy"
                label:   Translation.tr("Give it these widgets")
                tint:    Colors.of(QsWindow.window).primary
                onActivated: DesktopWidgets.newLayoutFor(presetSection.key, page.layoutScreen, "copy")
            }
            ChipButton {
                visible: presetSection.bound === ""
                symbol:  "add"
                tint:    Colors.of(QsWindow.window).primary
                onActivated: DesktopWidgets.newLayoutFor(presetSection.key, page.layoutScreen, "empty")
            }
            ChipButton {
                visible: presetSection.bound !== ""
                symbol:  "undo"
                label:   Translation.tr("Use my normal widgets")
                tint:    Colors.of(QsWindow.window).primary
                onActivated: DesktopWidgets.unbindWallpaper(presetSection.key)
            }
            ChipButton {
                visible: presetSection.bound !== ""
                symbol:  "delete"
                tint:    Colors.of(QsWindow.window).danger
                onActivated: {
                    const name = presetSection.bound
                    const gone = DesktopWidgets.deleteLayout(name)
                    page.undoBar.show(Translation.tr("Deleted %1’s widgets").arg(presetSection.wallLabel),
                                 function () { DesktopWidgets.restoreLayout(gone) })
                }
            }
        }
    }

    // ── Shared with other wallpapers already ──
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: presetSection.key !== "" && DesktopWidgets.layouts.length > 0
        spacing: Tokens.spacingSm

        StyledText {
            text: Translation.tr("Another wallpaper's own widgets: tap to share them here too")
            variant: "caption"
            emphasis: "dim"
        }
        ChipRow {
            Layout.fillHeight: false
            accent: Colors.of(QsWindow.window).primary
            model: DesktopWidgets.layouts.map(l => ({
                value: l.name,
                label: l.name + " · " + l.keys.length + (l.keys.length === 1 ? " wallpaper" : " wallpapers") }))
            current: presetSection.bound
            onPicked: function (v) { DesktopWidgets.bindWallpaper(presetSection.key, v) }
        }
    }
}
