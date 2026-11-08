pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperPropertiesView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
// ── PROPERTIES ──────────────────────────────────────────────────
// Author-defined sliders/colours/checkboxes/combos for one scene —
// opened from a tile's "Tune" hover action. Reads
// WallpaperEngine.propertySchema (the scene's declared defaults) and
// overrideFor() (what's actually saved) side by side; each row falls
// back to the schema's own default when nothing is overridden.
Flickable {
    id: propFlick
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    anchors.fill: parent
    contentWidth: width
    contentHeight: propCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: page.view === "properties"

    opacity: page.view === "properties" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    ColumnLayout {
        id: propCol
        width: propFlick.width
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            PanelButton {
                capsule: true
                variant: "ghost"
                symbol: "arrow_left"
                label: Translation.tr("Back")
                onActivated: page.view = "engine"
            }
            StyledText {
                Layout.fillWidth: true
                text: WallpaperEngine.titleFor(page.propertiesForId) + " · Properties"
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        readonly property bool schemaReady:
            WallpaperEngine.propertySchemaFor === page.propertiesForId

        StyledText {
            Layout.fillWidth: true
            visible: !propCol.schemaReady || WallpaperEngine.propertiesLoading
            text: Translation.tr("Loading…")
            variant: "caption"
            emphasis: "dim"
        }
        StyledText {
            Layout.fillWidth: true
            visible: propCol.schemaReady && !WallpaperEngine.propertiesLoading
                  && WallpaperEngine.propertySchema.length === 0
            text: Translation.tr("This scene has nothing to customise.")
            variant: "caption"
            emphasis: "dim"
        }

        Repeater {
            model: propCol.schemaReady ? WallpaperEngine.propertySchema : []
            delegate: ColumnLayout {
                id: propRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.spacingXs

                readonly property string pKey: propRow.modelData.key
                readonly property var ov:
                    WallpaperEngine.overrideFor(page.propertiesForId, propRow.pKey)
                readonly property bool overridden: propRow.ov !== undefined
                // Only meaningful for a "bool" row; harmless to compute
                // for the others since it just reads modelData.value.
                readonly property bool boolValue: propRow.overridden
                    ? (propRow.ov === "1" || propRow.ov === "true")
                    : !!propRow.modelData.value

                RowLayout {
                    Layout.fillWidth: true
                    visible: propRow.modelData.type === "slider"
                    spacing: Tokens.spacingSm

                    Fader {
                        Layout.fillWidth: true
                        accent: Colors.of(QsWindow.window).primary
                        label: propRow.modelData.text
                        from: propRow.modelData.min ?? 0
                        to:   propRow.modelData.max ?? 1
                        step: propRow.modelData.step ?? 0.1
                        value: propRow.overridden ? Number(propRow.ov)
                                                  : Number(propRow.modelData.value)
                        readout: (propRow.overridden ? Number(propRow.ov)
                                 : Number(propRow.modelData.value)).toFixed(2)
                        onCommit: function(v) {
                            WallpaperEngine.setPropertyOverride(
                                page.propertiesForId, propRow.pKey, String(v))
                        }
                    }
                    PanelButton {
                        capsule: true
                        visible: propRow.overridden
                        variant: "ghost"
                        symbol: "restart_alt"
                        onActivated: WallpaperEngine.clearPropertyOverride(
                            page.propertiesForId, propRow.pKey)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: propRow.modelData.type === "bool"
                    spacing: Tokens.spacingSm

                    SettingRow {
                        Layout.fillWidth: true
                        label: propRow.modelData.text
                        // propRow.boolValue, by ID — never `parent` (Toggle's
                        // parent is SettingRow, which has no boolValue of its own).
                        Toggle {
                            checked: propRow.boolValue
                            onToggled: WallpaperEngine.setPropertyOverride(
                                page.propertiesForId, propRow.pKey,
                                propRow.boolValue ? "0" : "1")
                        }
                    }
                    PanelButton {
                        capsule: true
                        visible: propRow.overridden
                        variant: "ghost"
                        symbol: "restart_alt"
                        onActivated: WallpaperEngine.clearPropertyOverride(
                            page.propertiesForId, propRow.pKey)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: propRow.modelData.type === "combo"
                    spacing: Tokens.spacingSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        StyledText {
                            text: propRow.modelData.text
                            variant: "body"
                            font.weight: Font.DemiBold
                        }
                        ChipRow {
                            accent: Colors.of(QsWindow.window).primary
                            model: propRow.modelData.options ?? []
                            current: propRow.overridden ? propRow.ov : propRow.modelData.value
                            onPicked: function(v) {
                                WallpaperEngine.setPropertyOverride(
                                    page.propertiesForId, propRow.pKey, String(v))
                            }
                        }
                    }
                    PanelButton {
                        capsule: true
                        visible: propRow.overridden
                        variant: "ghost"
                        symbol: "restart_alt"
                        onActivated: WallpaperEngine.clearPropertyOverride(
                            page.propertiesForId, propRow.pKey)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: propRow.modelData.type === "color"
                    spacing: Tokens.spacingSm

                    ColorField {
                        Layout.fillWidth: true
                        label: propRow.modelData.text
                        value: propRow.overridden ? String(propRow.ov)
                                                  : String(propRow.modelData.value)
                        onCommit: function(hex) {
                            WallpaperEngine.setPropertyOverride(
                                page.propertiesForId, propRow.pKey, hex)
                        }
                    }
                    PanelButton {
                        capsule: true
                        visible: propRow.overridden
                        variant: "ghost"
                        symbol: "restart_alt"
                        onActivated: WallpaperEngine.clearPropertyOverride(
                            page.propertiesForId, propRow.pKey)
                    }
                }
            }
        }
    }
}
