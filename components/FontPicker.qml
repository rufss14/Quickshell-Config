pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── FontPicker ────────────────────────────────────────────────────────────────
// One role's typeface, chosen from the families that are actually installed.
//
// A row (label, what it is for, the current pick) that opens a searchable list. Every
// entry shows its own name in the shell's face and a sample in ITS face, so you choose by
// looking, not by remembering what "Fira Sans Condensed" is.
//
// ── Why a list and not a text field ───────────────────────────────────────────
// It was a text field, and Qt falls back to a system font SILENTLY on a name it does not
// know: a typo left the shell in the wrong face with nothing saying so. Picking from
// `Tokens.families` cannot misspell. The one remaining way to hold a name that is not
// here — a config copied from another machine — is reported on the row, and Tokens
// renders the default meanwhile.
//
// ── Lazy ──────────────────────────────────────────────────────────────────────
// The list is behind a Loader, so a closed picker is one row, and the ListView only
// builds the handful of delegates in view — it does not lay out hundreds of families.
//
// `value` is Config's stored name ("" = the default); `fallback` is what the default
// resolves to, so the "Default" entry can say what it is. The caller owns the write:
//     FontPicker { value: Config.fontFamily; fallback: Tokens.defaultFamily
//                  onPicked: function (name) { Config.fontFamily = name } }
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string label:    ""
    property string detail:   ""
    // The explanation, as a tip on the label (HelpTip) rather than a line under it.
    property string help:     ""
    property string value:    ""
    property string fallback: ""
    property color  accent:   Colors.of(QsWindow.window).primary

    // Opened lazily, closed again on a pick.
    property bool open: false

    signal picked(string name)

    readonly property bool missing: root.value !== "" && !Tokens.installed(root.value)

    Layout.fillWidth: true
    spacing: Tokens.spacingXs

    SettingRow {
        Layout.fillHeight: false
        label:  root.label
        help:   root.help
        detail: root.missing
                ? "“" + root.value + "” isn’t installed here — using " + root.fallback + "."
                : root.detail
        wrapDetail: true

        PanelButton {
            variant: "normal"
            symbol:  root.open ? "expand_less" : "expand_more"
            label:   root.value === "" ? "Default" : root.value
            onActivated: root.open = !root.open
        }
    }

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: false
        active: root.open
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacingSm

            InputField {
                id: search
                Layout.fillWidth: true
                Layout.fillHeight: false
                placeholder: "Search " + Tokens.families.length + " fonts"
                icon: "search"
                Component.onCompleted: forceFocus()
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.fieldHeight * 6

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // "" first = the default. Filtered case-insensitively on the name.
                    model: {
                        const q = search.text.trim().toLowerCase()
                        const hit = q === "" ? Tokens.families
                                             : Tokens.families.filter(n => n.toLowerCase().includes(q))
                        return [""].concat(hit)
                    }

                    delegate: Rectangle {
                        id: row
                        required property string modelData

                        readonly property bool isDefault: modelData === ""
                        readonly property bool current:   modelData === root.value
                        readonly property string face:    isDefault ? root.fallback : modelData

                        width:  list.width
                        height: Tokens.fieldHeight
                        radius: Tokens.radiusSm
                        color:  current ? Colors.of(QsWindow.window).alpha(root.accent, 0.18)
                              : hover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                              : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin:  Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingMd

                            StyledText {
                                Layout.fillWidth: true
                                text: row.isDefault ? "Default (" + root.fallback + ")" : row.modelData
                                variant: "body"
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            // The face itself, so the choice is made by looking.
                            StyledText {
                                text: Translation.tr("Aa 0123")
                                variant: "body"
                                font.family: row.face
                            }
                        }

                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                root.picked(row.modelData)
                                root.open = false
                            }
                        }
                    }
                }

                Scrollbar { flickable: list }
            }
        }
    }
}
