pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"

// ── ModuleInspector ───────────────────────────────────────────────────────────
// What a module is, and everything about it you can change. Selecting a chip in the
// layout editor — or right-clicking one on the bar preview — points this at it.
//
// It replaced a read-only description box. The description was the right instinct
// (thirteen near-identical pills need naming) but it was a dead end: it told you what
// the thing did and then offered you nothing to do about it. Same space, same trigger,
// but now the panel is where the module's settings live.
//
// ── Why nothing here is a colour picker ───────────────────────────────────────
// The accent is chosen from the PALETTE'S ROLES, not from a colour wheel. Every colour
// in this shell is derived from the wallpaper, and a picker would let you pin a literal
// hex that then survives every future wallpaper — the one failure the palette exists to
// prevent. Picking "Green" picks ramp2, and ramp2 is whatever this wallpaper says green
// is. Change the wallpaper and the choice follows.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    // "" ⇒ nothing selected; the panel shows the how-to instead.
    property string moduleId: ""

    readonly property var info:  Config.moduleInfo(root.moduleId)
    // `rightInfo`, not `right`: Item.right is an ANCHOR LINE, and shadowing it would
    // quietly break anchoring for this whole component. Third instance of this trap in
    // the codebase after `state` and `enabled` — qmllint catches it every time.
    readonly property var rightInfo: Config.rightClickInfo(root.moduleId)
    readonly property bool placed: root.moduleId !== "" && Config.isPlaced(root.moduleId)

    elevation: Tokens.elevationNested

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        // ── Nothing selected ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.info === null
            spacing: Tokens.spacingXs

            StyledText {
                text: "Modules"
                variant: "body"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                rich: true
                text: "<b>Click</b> a module to configure it. <b>Drag</b> one onto another to put them in the same pill; drop it in a <b>gap</b> to give it its own, or on <b>Not on the bar</b> to remove it."
                variant:  "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                rich: true
                text: "<i>Everything applies live — the preview above is the real bar.</i>"
                variant:  "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── A module ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.info !== null
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                StyledText {
                    text: root.info ? root.info.label : ""
                    variant: "title"
                    font.weight: Font.DemiBold
                }

                // Says where it is, so the panel is self-contained when you got here by
                // right-clicking the preview rather than by clicking a chip.
                Rectangle {
                    visible: root.placed
                    implicitWidth:  whereText.implicitWidth + Tokens.spacingMd
                    implicitHeight: 18
                    radius: Tokens.radiusSm - 2
                    color: Colors.alpha(Colors.focus, 0.16)

                    StyledText {
                        id: whereText
                        anchors.centerIn: parent
                        text: {
                            const at = Config.locate(root.moduleId)
                            return at ? Config.regionLabel(at.region) : ""
                        }
                        color: Colors.focus
                        variant: "caption"
                    }
                }

                Item { Layout.fillWidth: true }

                PanelButton {
                    visible: Config.moduleCustomised(root.moduleId)
                    label:   "Reset"
                    variant: "ghost"
                    onActivated: Config.resetModule(root.moduleId)
                }
            }

            StyledText {
                Layout.fillWidth: true
                rich: true
                text: root.info ? root.info.description : ""
                variant:  "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            Divider {}

            // ── Accent ────────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.preferredWidth: 150
                    spacing: 0
                    StyledText { text: "Accent"; variant: "body" }
                    StyledText {
                        Layout.fillWidth: true
                        rich: true
                        text: "<i>From the palette, so it follows the wallpaper</i>"
                        variant:  "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: Config.accentRoles

                        Rectangle {
                            id: swatch
                            required property var modelData

                            readonly property bool isCurrent:
                                Config.moduleAccentRole(root.moduleId) === swatch.modelData.id
                            // "" is Default — it has no colour of its own, so it draws
                            // as an outlined chip rather than a lying swatch.
                            readonly property bool isDefault: swatch.modelData.id === ""

                            implicitWidth:  swatch.isDefault ? defaultLabel.implicitWidth + Tokens.spacingMd : 26
                            implicitHeight: 26
                            radius: Tokens.radiusSm - 2

                            color: swatch.isDefault
                                ? "transparent"
                                : Colors.role(swatch.modelData.id, Colors.primary)

                            border.width: swatch.isCurrent ? 2 : Tokens.borderWidth
                            border.color: swatch.isCurrent ? Colors.fg
                                        : swatchHover.hovered ? Colors.outlineFocus
                                        : Colors.outline
                            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                            StyledText {
                                id: defaultLabel
                                anchors.centerIn: parent
                                visible: swatch.isDefault
                                text:    "Default"
                                variant: "caption"
                                emphasis: swatch.isCurrent ? "normal" : "dim"
                            }

                            HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: Config.setModuleSetting(root.moduleId, "accent",
                                                                  swatch.modelData.id)
                            }
                        }
                    }
                }
            }

            // ── Right-click ───────────────────────────────────────────────────
            // Only the three modules that have a second face.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.rightInfo !== null
                spacing: Tokens.spacingSm

                Divider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "Remember right-click"; variant: "body" }
                        StyledText {
                            Layout.fillWidth: true
                            rich: true
                            text: root.rightInfo
                                ? "Right-click switches between <b>" + root.rightInfo.off
                                  + "</b> and <b>" + root.rightInfo.on
                                  + "</b>. <i>Normally that resets when the shell reloads</i> — turn this on to keep it."
                                : ""
                            variant:  "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }

                    Toggle {
                        checked: Config.modulePersist(root.moduleId)
                        onToggled: Config.setModulePersist(root.moduleId,
                                                           !Config.modulePersist(root.moduleId))
                    }
                }

                // Which state to remember. Only meaningful once you've opted in — and
                // it's disabled rather than hidden, so the toggle above visibly has a
                // consequence instead of appearing to do nothing.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.spacingLg
                    spacing: Tokens.spacingMd
                    enabled: Config.modulePersist(root.moduleId)
                    opacity: enabled ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.rightInfo ? root.rightInfo.label : ""
                        variant: "body"
                    }
                    StyledText {
                        text: root.rightInfo
                            ? (Config.moduleRightState(root.moduleId) ? root.rightInfo.on : root.rightInfo.off)
                            : ""
                        variant:  "caption"
                        emphasis: "dim"
                    }
                    Toggle {
                        checked: Config.moduleRightState(root.moduleId)
                        onToggled: Config.setModuleRightState(root.moduleId,
                                                              !Config.moduleRightState(root.moduleId))
                    }
                }
            }

            // ── Notifications: show only while Do Not Disturb is on ─────────────
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.moduleId === "notifications"
                spacing: Tokens.spacingSm

                Divider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "Only show while DND is on"; variant: "body" }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Hides the bell unless Do Not Disturb is active, so it "
                                + "reads as a discreet “DND is on” indicator rather "
                                + "than a permanent icon."
                            variant:  "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }

                    Toggle {
                        checked: Config.notifShowOnlyDnd()
                        onToggled: Config.setNotifShowOnlyDnd(!Config.notifShowOnlyDnd())
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
