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

// ── WidgetsPresetsSection ── part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to. ──
Section {
    id: presetSection
    required property var page
    span:     3
    visible:  page.viewMode === "content"
    glyph:    "󰸖"
    title:    Translation.tr("Presets")
    readonly property string key: DesktopWidgets.wallKeys[page.layoutScreen] ?? ""
    readonly property string bound: DesktopWidgets.layoutForKey(presetSection.key)
    readonly property string wallLabel: DesktopWidgets.wallName(presetSection.key)
    subtitle: DesktopWidgets.presetNames.length === 0 ? "None saved"
            : DesktopWidgets.presetNames.length + " saved"
    help:     Translation.tr("Click a preset to load it once, on the chosen screen. Right-click one to give the screen's wallpaper that preset LIVE instead: switch to the wallpaper and its tiles take over automatically; switch away and your normal ones return. Follows the colour scheme panel's own click-to-load / right-click-to-bind split.")
    accent:   Colors.of(QsWindow.window).primary

    // Which screen a preset lands on, and whose wallpaper the status strip below acts on.
    actions: TabStrip {
        visible: Quickshell.screens.length > 1
        implicitWidth: 90 * Quickshell.screens.length
        accent: Colors.of(QsWindow.window).primary
        model: Quickshell.screens.map(s => ({ value: s.name, label: s.name, icon: "monitor" }))
        current: page.layoutScreen
        onPicked: function (v) { page.layoutScreen = v }
    }

    StyledText {
        text: DesktopWidgets.presetNames.length === 0 ? "Save your first preset below"
            : "Tap to load · right-click to give " + (presetSection.key !== "" ? presetSection.wallLabel : "this wallpaper") + " that preset, live"
        variant: "caption"
        emphasis: "dim"
    }
    PresetChips {
        accent:    Colors.of(QsWindow.window).primary
        renamable: false
        presets:   DesktopWidgets.presetNames.map(n => ({ name: n }))
        badgeFor:  function (p) { return (DesktopWidgets.presets[p.name] || []).length + "" }
        savePlaceholder: "Name this preset"
        onLoad: function (name) { DesktopWidgets.applyPreset(name, page.layoutScreen) }
        onSave: function (name) {
            if (DesktopWidgets.shown.length > 0) DesktopWidgets.savePreset(name)
        }
        onRemove: function (name) {
            // The preset itself, captured before the delete.
            const keep = DesktopWidgets.presets[name]
            DesktopWidgets.deletePreset(name)
            page.undoBar.show("Deleted preset “" + name + "”",
                         function () { DesktopWidgets.restorePreset(name, keep) })
        }
        onRightClicked: function (name) {
            DesktopWidgets.newLayoutFor(presetSection.key, page.layoutScreen, "preset:" + name)
        }
    }

    Divider { Layout.fillWidth: true }

    // ── This wallpaper, one status pill + its one or two actions ───────
    // The colour panel's footer again: a pill states where the current state
    // comes from, a tight tray next to it is the only way to change it — no
    // branching button stacks to read through first.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm
        visible: presetSection.key !== ""

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                radius: height / 2
                color: Colors.of(QsWindow.window).surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: presetSection.bound !== "" ? "widgets" : "wallpaper"
                        fill: presetSection.bound !== "" ? 1 : 0
                        color: presetSection.bound !== "" ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: (presetSection.bound !== "" ? "Its own widgets" : "Your normal widgets")
                              + "  ·  " + presetSection.wallLabel
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }

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
                        page.undoBar.show("Deleted " + presetSection.wallLabel + "’s widgets",
                                     function () { DesktopWidgets.restoreLayout(gone) })
                    }
                }
            }
        }

        // ── Shared with other wallpapers already ───────────────────────
        StyledText {
            visible: DesktopWidgets.layouts.length > 0
            text: Translation.tr("Another wallpaper's own widgets — tap to share them here too")
            variant: "caption"
            emphasis: "dim"
        }
        ChipRow {
            Layout.fillHeight: false
            visible: DesktopWidgets.layouts.length > 0
            accent: Colors.of(QsWindow.window).primary
            model: DesktopWidgets.layouts.map(l => ({
                value: l.name,
                label: l.name + " · " + l.keys.length + (l.keys.length === 1 ? " wallpaper" : " wallpapers") }))
            current: presetSection.bound
            onPicked: function (v) { DesktopWidgets.bindWallpaper(presetSection.key, v) }
        }
    }
}
