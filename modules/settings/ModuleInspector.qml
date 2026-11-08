pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── ModuleInspector ───────────────────────────────────────────────────────────
// What a module is, and everything about it you can change. Selecting a chip in the
// layout editor — or right-clicking one on the bar preview — points this at it.
//
// It replaced a read-only description box. The description was the right instinct
// (thirteen near-identical pills need naming) but it was a dead end: it told you what
// the thing did and then offered you nothing to do about it. Same space, same trigger,
// but now the panel is where the module's settings live.
//
// ── Flat, and two columns when there is room ──────────────────────────────────
// It was a card inside the "Selected module" card — a second border and fill around
// rows that already had one — with hand-built label/caption/switch rows and a
// paragraph under each. Now it is the card's body: what the module is, where it sits
// and its accent on the left; its switches on the right (SettingRow, the explanation
// in each row's tip). Below ~640px the two columns stack.
//
// ── Why nothing here is a colour picker ───────────────────────────────────────
// The accent is chosen from the PALETTE'S ROLES, not from a colour wheel. Every colour
// in this shell is derived from the wallpaper, and a picker would let you pin a literal
// hex that then survives every future wallpaper — the one failure the palette exists to
// prevent. Picking "Green" picks ramp2, and ramp2 is whatever this wallpaper says green
// is. Change the wallpaper and the choice follows.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // "" ⇒ nothing selected; the panel shows how to pick one instead.
    property string moduleId: ""

    readonly property var info:  Config.moduleInfo(root.moduleId)
    // `rightInfo`, not `right`: Item.right is an ANCHOR LINE, and shadowing it would
    // quietly break anchoring for this whole component. Third instance of this trap in
    // the codebase after `state` and `enabled` — qmllint catches it every time.
    readonly property var rightInfo: Config.rightClickInfo(root.moduleId)
    readonly property bool placed: root.moduleId !== "" && Config.isPlaced(root.moduleId)

    // Which modules actually read Config.groupSpacing back. The control is hidden
    // everywhere else rather than shown and silently doing nothing, and it needs at
    // least one neighbour to mean anything.
    //
    // Two groups, and the first one grew: every BarIconPill module honours spacing now,
    // because the base wires `spacing: Config.groupSpacing(moduleId)` once instead of
    // each of the ten inline entries in Bar.qml repeating it (seven did, the rest
    // didn't — which is how this list came to be a list). The second group is the three
    // widgets that lay themselves out by hand and read it for their own padding:
    // TrayPill, BluetoothPill, WifiPill.
    //
    // Still a list rather than a derived fact, because what it encodes is "the widget
    // consumes this", and only the widget knows. A module added here that does NOT read
    // it is a slider that moves nothing — check the widget before adding a row.
    readonly property var _spacingSupported: [
        // BarIconPill-based
        "shapeToggle", "modeToggle", "palette", "wallpaper", "keyboard", "notifications",
        "idle", "nightlight", "gamemode", "overview", "settings", "privacy",
        // Hand-laid-out
        "tray", "bluetooth", "wifi"]
    readonly property var  groupMembers: root.moduleId !== "" ? Config.groupMembers(root.moduleId) : []
    readonly property bool spacingSupported:
        root._spacingSupported.indexOf(root.moduleId) !== -1 && root.groupMembers.length > 1

    // What the slider shows before the group has ever been touched: today's
    // effective padding on each side of a plain icon (Tokens.pillPadding), doubled
    // — i.e. exactly what an untouched group already looks like, so dragging the
    // slider starts from "no visible change" rather than jumping the icons on
    // first touch.
    readonly property int _defaultSpacing: Tokens.pillPadding * 2
    readonly property int groupSpacingValue: {
        const v = root.moduleId !== "" ? Config.groupSpacing(root.moduleId) : -1
        return v >= 0 ? v : root._defaultSpacing
    }

    // Anything the page's Reset button would undo: the module's own settings, or its
    // group's spacing (stored per group, so resetModule alone leaves it behind).
    readonly property bool customised: root.moduleId !== ""
        && (Config.moduleCustomised(root.moduleId) || Config.groupSpacing(root.moduleId) >= 0)
    function reset() {
        Config.resetModule(root.moduleId)
        Config.clearGroupSpacing(root.moduleId)
    }

    readonly property bool wide: root.width >= 640

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingMd

    // ── Nothing selected ──────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.info === null
        spacing: Tokens.spacingMd

        MaterialIcon {
            name: "ads_click"
            color: Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconXl
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: Translation.tr("Nothing selected")
                variant: "body"
                font.weight: Font.Medium
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Press Arrange, then click a module on the bar — or press one above")
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── A module ──────────────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.info !== null
        columns: root.wide ? 2 : 1
        columnSpacing: Tokens.spacingXxl
        rowSpacing: Tokens.spacingMd

        // ── What it is, where it sits, its colour ─────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                rich: true
                text: root.info ? root.info.description : ""
                variant:  "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            // ── Where it sits ─────────────────────────────────────────────────
            // A control rather than a chip reading "Left", for a reason that is not
            // tidiness: placing a module was drag-ONLY. That gesture crosses two
            // Wayland surfaces (ModuleTray's header records how), it needs a steady
            // hand at pill scale, and it is the only way in for someone on a
            // trackball, a touchpad, or a compositor that fumbles the drag.
            //
            // Three buttons and a cross are not a replacement for dragging — you
            // still cannot say WHICH group or WHERE in the row from here, which is
            // exactly what the bar's own editor is for. They are the floor: every
            // module can be put in a region and taken off the bar without a drag.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    text: root.placed ? "Where" : "Not on the bar"
                    variant: "body"
                    font.weight: Font.Medium
                }

                Item { Layout.fillWidth: true }

                TabStrip {
                    visible: root.placed
                    Layout.preferredWidth: 126
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "left",   label: "", icon: "chevron_left" },
                        { value: "centre", label: "", icon: "circle" },
                        { value: "right",  label: "", icon: "chevron_right" }
                    ]
                    current: {
                        const at = Config.locate(root.moduleId)
                        return at ? at.region : ""
                    }
                    // Its own group at the end of that region — the same landing
                    // `addModule` gives a returning module, rather than silently
                    // joining whatever cluster happens to be there.
                    onPicked: function (v) {
                        Config.moveToOwnGroup(root.moduleId, v, 9999)
                    }
                }

                PanelButton {
                    capsule: true
                    visible: root.placed
                    variant: "ghost"
                    symbol:  "close"
                    accent:  Colors.of(QsWindow.window).danger
                    // No confirm and no undo bar: the module lands in "Not on the
                    // bar" one card away, and putting it back is one click.
                    onActivated: Config.removeModule(root.moduleId)
                }

                PanelButton {
                    capsule: true
                    visible: !root.placed && root.moduleId !== ""
                    variant: "primary"
                    accent:  Colors.of(QsWindow.window).primary
                    symbol:  "add"
                    label:   Translation.tr("Add to bar")
                    onActivated: Config.addModule(root.moduleId)
                }
            }

            // ── Accent ────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    HelpTip { id: accentTip; text: "Picked from the palette by role, so it follows the next wallpaper." }
                    StyledText { text: "Accent"; variant: "body"; font.weight: Font.Medium }
                    MaterialIcon {
                        name: "info"
                        color: Colors.of(QsWindow.window).fgDim
                        font.pixelSize: Tokens.iconSm
                        opacity: accentTip.active ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                    Item { Layout.fillWidth: true }
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

                            implicitWidth:  swatch.isDefault ? defaultLabel.implicitWidth + Tokens.spacingMd * 2 : 28
                            implicitHeight: 28
                            radius: Tokens.radiusSm

                            color: swatch.isDefault
                                ? "transparent"
                                : Colors.of(QsWindow.window).role(swatch.modelData.id, Colors.of(QsWindow.window).primary)

                            border.width: swatch.isCurrent ? 2 : Tokens.borderWidth
                            border.color: swatch.isCurrent ? Colors.of(QsWindow.window).fg
                                        : swatchHover.hovered ? Colors.of(QsWindow.window).outlineFocus
                                        : Colors.of(QsWindow.window).outline
                            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                            scale: swatchHover.hovered && !swatch.isCurrent ? 1.08 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.respond
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring
                                }
                            }

                            StyledText {
                                id: defaultLabel
                                anchors.centerIn: parent
                                visible: swatch.isDefault
                                text:    Translation.tr("Default")
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
        }

        // ── Its switches ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingSm

            SettingRow {
                label: Translation.tr("Inner pill")
                detail: Config.moduleInnerPill(root.moduleId) ? "On its own lighter chip" : "Straight on the group's pill"
                help: Translation.tr("Off sits this module directly on the group's own pill instead of the lighter shared chip.")
                Toggle {
                    checked: Config.moduleInnerPill(root.moduleId)
                    onToggled: Config.setModuleInnerPill(root.moduleId,
                                                         !Config.moduleInnerPill(root.moduleId))
                }
            }

            // Only for a module that can be the hero (its bar form says so, config/modules.js).
            SettingRow {
                visible: root.info?.hero === true
                label: Translation.tr("Hero")
                detail: Config.moduleHero(root.moduleId) ? "On the accent's container" : "Like the rest of the bar"
                help: Translation.tr("Puts this module on a tinted chip in your accent, the bar's one emphasised pill — as a desktop widget's hero.")
                Toggle {
                    checked: Config.moduleHero(root.moduleId)
                    onToggled: Config.setModuleHero(root.moduleId, !Config.moduleHero(root.moduleId))
                }
            }

            // Per-GROUP, not per-module (Config.groupSpacing) — editing it from any
            // one member changes the whole cluster, which is why the tip names every
            // member rather than just this one. Only where it actually does something
            // — see spacingSupported above.
            SliderRow {
                visible: root.spacingSupported
                label: Translation.tr("Group spacing")
                help: Translation.tr("Distance between icons in this group: ")
                    + root.groupMembers.map(id => Config.moduleInfo(id).label).join(", ") + "."
                from: 0
                to:   32
                step: 1
                value: root.groupSpacingValue
                readout: Math.round(root.groupSpacingValue) + "px"
                numberWidth: 44
                onCommit: function (v) { Config.setGroupSpacing(root.moduleId, v) }
            }

            // ── Right-click: only the three modules that have a second face ───
            SettingRow {
                visible: root.rightInfo !== null
                label: Translation.tr("Remember right-click")
                detail: Config.modulePersist(root.moduleId) ? "Kept across reloads" : "Resets on reload"
                help: root.rightInfo
                    ? "Right-click switches between " + root.rightInfo.off + " and " + root.rightInfo.on
                      + ". Normally that resets when the shell reloads; this keeps it."
                    : ""
                Toggle {
                    checked: Config.modulePersist(root.moduleId)
                    onToggled: Config.setModulePersist(root.moduleId,
                                                       !Config.modulePersist(root.moduleId))
                }
            }

            // Which state to remember. Only meaningful once you've opted in — and
            // it's disabled rather than hidden, so the switch above visibly has a
            // consequence instead of appearing to do nothing.
            SettingRow {
                visible: root.rightInfo !== null
                enabled: Config.modulePersist(root.moduleId)
                opacity: enabled ? 1.0 : 0.4
                Layout.leftMargin: Tokens.spacingLg
                label: root.rightInfo ? root.rightInfo.label : ""
                detail: root.rightInfo
                    ? (Config.moduleRightState(root.moduleId) ? root.rightInfo.on : root.rightInfo.off)
                    : ""
                Toggle {
                    checked: Config.moduleRightState(root.moduleId)
                    onToggled: Config.setModuleRightState(root.moduleId,
                                                          !Config.moduleRightState(root.moduleId))
                }
            }

            // ── Notifications: show only while Do Not Disturb is on ─────────────
            SettingRow {
                visible: root.moduleId === "notifications"
                label: Translation.tr("Only while Do Not Disturb")
                detail: Config.notifShowOnlyDnd() ? "A quiet “DND is on” sign" : "Always shown"
                help: Translation.tr("Hides the bell unless Do Not Disturb is on, so it reads as a discreet indicator rather than a permanent icon.")
                Toggle {
                    checked: Config.notifShowOnlyDnd()
                    onToggled: Config.setNotifShowOnlyDnd(!Config.notifShowOnlyDnd())
                }
            }

            // ── Game mode: the panel's title row ──────────────────────────────
            SettingRow {
                visible: root.moduleId === "gamemode"
                label: Translation.tr("Panel header")
                detail: Config.gamemodePanelHeader() ? "Icon and title on top" : "Straight onto the pages"
                help: Translation.tr("The title row at the top of the Game Mode panel. Off, the panel opens straight onto its Play / Effects / Tune / Setup pages.")
                Toggle {
                    checked: Config.gamemodePanelHeader()
                    onToggled: Config.setGamemodePanelHeader(!Config.gamemodePanelHeader())
                }
            }

            // ── Volume: the mixer panel's title row ───────────────────────────
            SettingRow {
                visible: root.moduleId === "volume"
                label: Translation.tr("Panel header")
                detail: Config.mixerPanelHeader() ? "Icon and title on top" : "Straight onto the pages"
                help: Translation.tr("The title row at the top of the Audio Mixer panel. Off, the panel opens straight onto its Mix / Devices / Mic / Presets pages.")
                Toggle {
                    checked: Config.mixerPanelHeader()
                    onToggled: Config.setMixerPanelHeader(!Config.mixerPanelHeader())
                }
            }

            // ── Clock: the panel's header card ────────────────────────────────
            SettingRow {
                visible: root.moduleId === "clock"
                label: Translation.tr("Panel header")
                detail: Config.clockPanelHeader() ? "Icon, title and place on top" : "Straight onto the tabs"
                help: Translation.tr("The card at the top of the clock panel — its icon, title and place. Off, the panel opens straight onto its tabs.")
                Toggle {
                    checked: Config.clockPanelHeader()
                    onToggled: Config.setClockPanelHeader(!Config.clockPanelHeader())
                }
            }
        }
    }
}
