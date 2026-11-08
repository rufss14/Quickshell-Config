import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"


// ── One scene's custom properties, at panel scale ──────────────────────────
// Reads WallpaperEngine.propertySchema (the scene's declared defaults) side
// by side with overrideFor() (what's actually saved); a row falls back to
// the schema's own default when nothing is overridden. Same four branches
// as the settings page's Properties view — see there for the fuller comment.
Item {
    required property var panel

    Flickable {
        id: propPane
        anchors.fill: parent
        contentWidth: width
        contentHeight: propCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: propCol
            width: propPane.width
            spacing: Tokens.spacingSm

            readonly property bool schemaReady:
                WallpaperEngine.propertySchemaFor === panel.propertiesForId

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
                        WallpaperEngine.overrideFor(panel.propertiesForId, propRow.pKey)
                    readonly property bool overridden: propRow.ov !== undefined
                    readonly property bool boolValue: propRow.overridden
                        ? (propRow.ov === "1" || propRow.ov === "true")
                        : !!propRow.modelData.value

                    RowLayout {
                        Layout.fillWidth: true
                        visible: propRow.modelData.type === "slider"
                        spacing: Tokens.spacingSm

                        Fader {
                            Layout.fillWidth: true
                            accent: panel.accent
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
                                    panel.propertiesForId, propRow.pKey, String(v))
                            }
                        }
                        PanelButton {
                            visible: propRow.overridden
                            variant: "ghost"
                            symbol: "restart_alt"
                            onActivated: WallpaperEngine.clearPropertyOverride(
                                panel.propertiesForId, propRow.pKey)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: propRow.modelData.type === "bool"
                        spacing: Tokens.spacingSm

                        WallpaperOptionRow {
                            Layout.fillWidth: true
                            label: propRow.modelData.text
                            checked: propRow.boolValue
                            onToggled: WallpaperEngine.setPropertyOverride(
                                panel.propertiesForId, propRow.pKey,
                                propRow.boolValue ? "0" : "1")
                        }
                        PanelButton {
                            visible: propRow.overridden
                            variant: "ghost"
                            symbol: "restart_alt"
                            onActivated: WallpaperEngine.clearPropertyOverride(
                                panel.propertiesForId, propRow.pKey)
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
                                accent: panel.accent
                                model: propRow.modelData.options ?? []
                                current: propRow.overridden ? propRow.ov : propRow.modelData.value
                                onPicked: function(v) {
                                    WallpaperEngine.setPropertyOverride(
                                        panel.propertiesForId, propRow.pKey, String(v))
                                }
                            }
                        }
                        PanelButton {
                            visible: propRow.overridden
                            variant: "ghost"
                            symbol: "restart_alt"
                            onActivated: WallpaperEngine.clearPropertyOverride(
                                panel.propertiesForId, propRow.pKey)
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
                                    panel.propertiesForId, propRow.pKey, hex)
                            }
                        }
                        PanelButton {
                            visible: propRow.overridden
                            variant: "ghost"
                            symbol: "restart_alt"
                            onActivated: WallpaperEngine.clearPropertyOverride(
                                panel.propertiesForId, propRow.pKey)
                        }
                    }
                }
            }
        }
    }
    Scrollbar { flickable: propPane }
}
