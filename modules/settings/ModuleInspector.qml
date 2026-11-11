pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../config/modules.js" as Catalogue

// ── ModuleInspector ───────────────────────────────────────────────────────────
// What a module is, where it stands, and everything about it you can change — for a
// module on the bar, on the sidebar, or on neither. Pressing one on the real bar or
// sidebar (armed while Bar › Modules is open) or clicking a library tile points this at it.
//
// ── One inspector for both surfaces (2026-11-08) ──────────────────────────────
// It was the bar's alone; the sidebar had a row of on/off chips and a single hero
// picker. A module has one place (config/modules.js), so it has one set of settings,
// and they follow it between surfaces: where it stands is a control here like any other
// (`On`: Bar / Sidebar / Off, then the region on that surface).
//
// Which controls show is the CATALOGUE's answer, not a list kept here: a form's `opts`
// names the extras that form's widget really reads (spacing, right-click memory, DND,
// panel header, peeks). A control for something the widget ignores is a slider that
// moves nothing — so it isn't drawn.
//
// The dock and Stats bring their own block (DockOptions, StatsOptions): they were tabs
// of their own until the user folded them in (2026-11-08).
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

    // The whole module (both forms), and where it stands: "bar" | "side" | "".
    readonly property var info: root.moduleId !== "" ? Catalogue.info(root.moduleId) : null
    readonly property string where: {
        void Config.layout; void Config.sidebarLayout
        return root.moduleId !== "" ? Config.surfaceOf(root.moduleId) : ""
    }
    readonly property bool placed: root.where !== ""
    // The form that describes it: where it stands, else where "+ Add" would put it.
    readonly property string formSurface: root.where !== "" ? root.where : (root.info ? root.info.native : "bar")
    readonly property var form: root.info ? root.info[root.formSurface] : null
    function opt(key) { return root.where !== "" && Catalogue.hasOpt(root.moduleId, root.where, key) }

    readonly property string blocker: root.moduleId !== "" ? BarModules.blocker(root.moduleId) : ""

    // `rightInfo`, not `right`: Item.right is an ANCHOR LINE, and shadowing it would
    // quietly break anchoring for this whole component.
    readonly property var rightInfo: Config.rightClickInfo(root.moduleId)

    // Group spacing is per GROUP: who else a change moves.
    readonly property var  groupMembers: root.placed ? Config.groupMembers(root.moduleId) : []
    readonly property bool spacingSupported: root.opt("spacing") && root.groupMembers.length > 1
    // What an untouched group already looks like (Tokens.pillPadding each side), so the
    // first touch of the slider moves nothing.
    readonly property int _defaultSpacing: Tokens.pillPadding * 2
    readonly property int groupSpacingValue: {
        const v = root.moduleId !== "" ? Config.groupSpacing(root.moduleId) : -1
        return v >= 0 ? v : root._defaultSpacing
    }

    // The accent and the inner pill follow a module onto either surface: the sidebar's
    // cells read moduleAccent (SideCell.moduleId) and its pills split round a module
    // that opted out (SideRegionPills). The dock draws app icons, so no accent of its own.
    readonly property bool accentWorks: root.moduleId !== "dock"
    readonly property bool innerPillWorks: root.where === "bar" || root.where === "side"

    // Hero: one per surface. Which module it would take the chip from.
    readonly property string heroNow: root.where === "bar" ? Config.barHero : root.where === "side" ? Config.sidebarHero : ""
    readonly property string heroOther: root.heroNow !== "" && root.heroNow !== root.moduleId
        && Config.surfaceOf(root.heroNow) === root.where ? root.heroNow : ""

    // Peeks: one switch each, in Config under its own name.
    readonly property var _peekKey: ({ timer: "peekTimer", claude: "peekClaude", colour: "peekColour",
                                       clipboard: "peekClipboard", clips: "clipsPeek" })
    readonly property string peekKey: root._peekKey[root.moduleId] ?? ""

    // Anything the page's Reset button would undo: the module's own settings, or its
    // group's spacing (stored per group, so resetModule alone leaves it behind).
    readonly property bool customised: root.moduleId !== ""
        && (Config.moduleCustomised(root.moduleId) || Config.groupSpacing(root.moduleId) >= 0)
    function reset() {
        Config.resetModule(root.moduleId)
        Config.clearGroupSpacing(root.moduleId)
    }

    function _label(id) { return Catalogue.info(id)?.label ?? id }

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
            Layout.fillHeight: false
            spacing: 0
            StyledText {
                text: Translation.tr("Nothing selected")
                variant: "body"
                font.weight: Font.Medium
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Press a module on the bar or the sidebar, or one in the library below")
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

        // ── What it is, where it stands, its colour ───────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                rich: true
                text: root.form ? root.form.description : ""
                variant:  "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            // A missing tool: said once, here, and the surfaces can't be picked.
            StyledText {
                Layout.fillWidth: true
                visible: root.blocker !== "" && !root.placed
                text: root.blocker
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            // ── Where it stands ───────────────────────────────────────────────
            // Clicks, not only drags: dragging crosses Wayland surfaces and wants a
            // steady hand at pill scale, and it's the only way in for a trackball, a
            // touchpad or a compositor that fumbles the drag. These are the floor —
            // every module can be put on either surface, in a region, or taken off,
            // without one. (WHICH group and where in it is dragging's job.)
            SettingRow {
                label: Translation.tr("On")
                detail: !root.info ? ""
                      : !root.info.bar ? Translation.tr("Only the sidebar has a form for it")
                      : !root.info.side ? Translation.tr("Only the bar has a form for it")
                      : ""
                SegmentSwitch {
                    implicitWidth: 260
                    enabled: root.placed || root.blocker === ""
                    accent: Colors.of(QsWindow.window).primary
                    model: (root.info && root.info.bar ? [{ value: "bar", label: "Bar", icon: "dashboard" }] : [])
                        .concat(root.info && root.info.side ? [{ value: "side", label: "Sidebar", icon: "view_quilt" }] : [])
                        .concat([{ value: "", label: "Off", icon: "block" }])
                    current: root.where
                    onPicked: function (v) { Config.placeModule(root.moduleId, v) }
                }
            }

            SettingRow {
                visible: root.placed
                label: Translation.tr("Region")
                SegmentSwitch {
                    implicitWidth: 260
                    accent: Colors.of(QsWindow.window).primary
                    model: root.where === "bar"
                        ? [{ value: "left",   label: "Left",   icon: "chevron_left" },
                           { value: "centre", label: "Centre", icon: "circle" },
                           { value: "right",  label: "Right",  icon: "chevron_right" }]
                        : Config.sidebarRegionIds.map(r => ({ value: r, label: Config.sidebarRegionLabel(r),
                                                              icon: r === "start" ? "keyboard_arrow_up"
                                                                  : r === "centre" ? "circle"
                                                                  : "keyboard_arrow_down" }))
                    current: {
                        void Config.layout; void Config.sidebarLayout
                        return root.where === "bar" ? (Config.locate(root.moduleId)?.region ?? "")
                             : root.where === "side" ? Config.sidebarRegionOf(root.moduleId) : ""
                    }
                    // Its own group at the end of that region — the landing a returning
                    // module gets, rather than silently joining whatever is there.
                    onPicked: function (v) {
                        if (root.where === "bar") Config.moveToOwnGroup(root.moduleId, v, 9999)
                        else Config.sidebarMoveToOwnGroup(root.moduleId, v, 9999)
                    }
                }
            }

            // ── Accent ────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.accentWorks
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    HelpTip { id: accentTip; text: Translation.tr("Picked from the palette by role, so it follows the next wallpaper.") }
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
                            // "" is Default — no colour of its own, so an outlined chip
                            // rather than a lying swatch.
                            readonly property bool isDefault: swatch.modelData.id === ""

                            implicitWidth:  swatch.isDefault ? defaultLabel.implicitWidth + Tokens.spacingMd * 2 : Tokens.iconXl
                            implicitHeight: Tokens.iconXl
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
                                onTapped: Config.setModuleSetting(root.moduleId, "accent", swatch.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── Its switches ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingSm

            SettingRow {
                visible: root.innerPillWorks
                label: Translation.tr("Inner pill")
                detail: Config.moduleInnerPill(root.moduleId) ? "On its own lighter chip" : "Straight on the group's pill"
                help: Translation.tr("Off sits this module directly on the group's own pill instead of the lighter shared chip.")
                Toggle {
                    checked: Config.moduleInnerPill(root.moduleId)
                    onToggled: Config.setModuleInnerPill(root.moduleId, !Config.moduleInnerPill(root.moduleId))
                }
            }

            // One hero per surface (Config.barHero / sidebarHero): turning it on here
            // takes the chip from the module that has it, and the row says which.
            SettingRow {
                visible: root.info?.heroable === true && root.placed
                label: Translation.tr("Hero")
                detail: Config.moduleHero(root.moduleId) ? "On the accent's container"
                      : root.heroOther !== "" ? "Takes it from " + root._label(root.heroOther)
                      : "Like the rest of the " + (root.where === "bar" ? "bar" : "sidebar")
                help: Translation.tr("Puts this module on a tinted chip in your accent — the surface's one emphasised pill, as a desktop widget's hero. Each surface has one.")
                Toggle {
                    checked: Config.moduleHero(root.moduleId)
                    onToggled: Config.setModuleHero(root.moduleId, !Config.moduleHero(root.moduleId))
                }
            }

            // Per-GROUP, not per-module (Config.groupSpacing) — editing it from any one
            // member changes the whole cluster, which is why the tip names every member.
            SliderRow {
                visible: root.spacingSupported
                label: Translation.tr("Group spacing")
                help: Translation.tr("Distance between icons in this group: ")
                    + root.groupMembers.map(id => root._label(id)).join(", ") + "."
                from: 0
                to:   32
                step: 1
                value: root.groupSpacingValue
                readout: Math.round(root.groupSpacingValue) + "px"
                numberWidth: 44
                onCommit: function (v) { Config.setGroupSpacing(root.moduleId, v) }
            }

            // ── Right-click: the modules with a second face ───────────────────
            SettingRow {
                visible: root.opt("rightClick") && root.rightInfo !== null
                label: Translation.tr("Remember right-click")
                detail: Config.modulePersist(root.moduleId) ? "Kept across reloads" : "Resets on reload"
                help: root.rightInfo
                    ? "Right-click switches between " + root.rightInfo.off + " and " + root.rightInfo.on
                      + ". Normally that resets when the shell reloads; this keeps it."
                    : ""
                Toggle {
                    checked: Config.modulePersist(root.moduleId)
                    onToggled: Config.setModulePersist(root.moduleId, !Config.modulePersist(root.moduleId))
                }
            }
            // Which state to remember. Disabled rather than hidden, so the switch above
            // visibly has a consequence.
            SettingRow {
                visible: root.opt("rightClick") && root.rightInfo !== null
                enabled: Config.modulePersist(root.moduleId)
                opacity: enabled ? 1.0 : 0.4
                Layout.leftMargin: Tokens.spacingLg
                label: root.rightInfo ? root.rightInfo.label : ""
                detail: root.rightInfo
                    ? (Config.moduleRightState(root.moduleId) ? root.rightInfo.on : root.rightInfo.off)
                    : ""
                Toggle {
                    checked: Config.moduleRightState(root.moduleId)
                    onToggled: Config.setModuleRightState(root.moduleId, !Config.moduleRightState(root.moduleId))
                }
            }

            SettingRow {
                visible: root.opt("dndOnly")
                label: Translation.tr("Only while Do Not Disturb")
                detail: Config.notifShowOnlyDnd() ? "A quiet “DND is on” sign" : "Always shown"
                help: Translation.tr("Hides the bell unless Do Not Disturb is on, so it reads as a discreet indicator rather than a permanent icon.")
                Toggle {
                    checked: Config.notifShowOnlyDnd()
                    onToggled: Config.setNotifShowOnlyDnd(!Config.notifShowOnlyDnd())
                }
            }

            // ── The module's panel: its title row ─────────────────────────────
            SettingRow {
                visible: root.opt("panelHeader")
                label: Translation.tr("Panel header")
                detail: Config.panelHeader(root.moduleId) ? Translation.tr("Icon and title on top") : Translation.tr("Straight onto the panel")
                help: Translation.tr("The title row at the top of this module's panel. Off, the panel opens straight onto its content and is a little shorter.")
                Toggle {
                    checked: Config.panelHeader(root.moduleId)
                    onToggled: Config.setPanelHeader(root.moduleId, !Config.panelHeader(root.moduleId))
                }
            }

            // ── Peek: a card beside it when something happens (EventPeek) ─────
            SettingRow {
                visible: root.opt("peek") && root.peekKey !== ""
                label: Translation.tr("Peek")
                detail: Config[root.peekKey] ? "A card beside it when something happens" : "Off"
                help: Translation.tr("When something happens to it, a card opens beside it for a moment — on the monitor you're on, and never over a panel you opened.")
                Toggle {
                    checked: Config[root.peekKey] === true
                    onToggled: Config[root.peekKey] = !Config[root.peekKey]
                }
            }
        }
    }

    // ── The two modules with settings of their own ────────────────────────────
    DockOptions {
        visible: root.moduleId === "dock"
        Layout.topMargin: Tokens.spacingSm
    }
    StatsOptions {
        visible: root.moduleId === "stats"
        Layout.topMargin: Tokens.spacingSm
    }
}
