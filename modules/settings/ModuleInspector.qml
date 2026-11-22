pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../config/modules.js" as Catalogue

// ── ModuleInspector ───────────────────────────────────────────────────────────
// What a module is, where it stands, and everything about it you can change — for a
// module on the bar, on the sidebar, or on neither. Pressing one on the real bar or
// sidebar (while Arrange is on in Bar › Modules) or clicking a library tile points this at it.
//
// ── One inspector for both surfaces ───────────────────────────────────────────
// A module has one place (config/modules.js), so it has one set of settings, and they
// follow it between surfaces: where it stands is a control here like any other
// (`On`: Bar / Sidebar / Off, then the region on that surface).
//
// Which controls show is the CATALOGUE's answer, not a list kept here: a form's `opts`
// names the extras that form's widget really reads (spacing, right-click memory, DND,
// panel header, peeks). A control for something the widget ignores is a slider that
// moves nothing — so it isn't drawn.
//
// The dock and Stats bring their own block (DockOptions, StatsOptions): the dock is a
// module like the rest, so its settings are where every module's are.
//
// ── Grouped Sections, side by side ────────────────────────────────────────────
// Bar › Modules is a grouped page, so the inspector is two grouped Sections: where it stands and
// how it looks (On, Region, accent, chip), and its switches. Each row is one segment. It is a single
// full-row cell of the page (`fullRow`), so the page's columns do not split the two halves apart.
//
// ── Placed by arithmetic, not by a layout ─────────────────────────────────────
// The root is a Column (a positioner) and the two cards sit in a plain Item at x/y worked out from its
// width. Not a ColumnLayout holding a GridLayout: a layout child that was hidden when the page was made
// kept its slot. Measured in a headless sandbox (Qt 6.12): reopening the page with a module already
// picked left the "Nothing selected" card's 54px in the layout, so the cards stood 54px low and the
// Library below was placed from the true height and drew over the last row. A positioner reads
// visibility as it is now, and the page reads this item's `implicitHeight`.
//
// ── Why nothing here is a colour picker ───────────────────────────────────────
// The accent is chosen from the PALETTE'S ROLES, not from a colour wheel. Every colour
// in this shell is derived from the wallpaper, and a picker would let you pin a literal
// hex that then survives every future wallpaper — the one failure the palette exists to
// prevent. Picking "Green" picks ramp2, and ramp2 is whatever this wallpaper says green
// is. Change the wallpaper and the choice follows.
// ─────────────────────────────────────────────────────────────────────────────
Column {
    id: root

    // "" ⇒ nothing selected; the panel shows how to pick one instead.
    property string moduleId: ""

    // Read by SettingsPage: this is one whole row of the page, not a group to flow into a column.
    property bool fullRow: true

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

    // Peeks: one switch each, in Config under its own name. Clips has none here: its switch is on the Clips page.
    readonly property var _peekKey: ({ timer: "peekTimer", claude: "peekClaude", colour: "peekColour",
                                       clipboard: "peekClipboard" })
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

    // The catalogue's descriptions carry <b>/<i> markup and spaced dashes for the old rich-text caption;
    // shown as plain sentences now.
    function plain(t) { return String(t ?? "").replace(/<[^>]+>/g, "").replace(/\s—\s/g, ", ") }

    // Whether the options group has anything to show for this module.
    readonly property bool hasOptions: root.spacingSupported || root.opt("spacer")
        || (root.opt("rightClick") && root.rightInfo !== null) || root.opt("dndOnly")
        || root.moduleId === "stream" || root.opt("panelHeader")
        || (root.opt("peek") && (root.peekKey !== "" || root.moduleId === "clips"))

    // What the spacer can follow: "none", then every module Config lets it (the ones on its surface).
    readonly property var spacerTargets: {
        void Config.layout; void Config.sidebarLayout
        const out = [{ value: "", label: Translation.tr("None") }]
        const seen = []
        for (const l of [Config.layout, Config.sidebarLayout])
            for (const r of Object.keys(l))
                for (const g of (l[r] ?? []))
                    for (const id of g)
                        if (Config.spacerCanFollow(id) && seen.indexOf(id) === -1) {
                            seen.push(id)
                            out.push({ value: id, label: root._label(id) })
                        }
        return out
    }

    readonly property bool wide: root.width >= 640
    // The connected choices (On, Region): room for every name beside its icon (a segment under ~104px
    // shows the icon alone). A SettingRow's control slot is a plain Item: sized by implicitWidth.
    readonly property int choiceWidth: Tokens.fieldHeight * 10
    readonly property int pairWidth:   Tokens.fieldHeight * 7

    spacing: Tokens.spacingLg

    // ── Nothing selected ──────────────────────────────────────────────────────
    Section {
        grouped: true
        width: root.width
        height: implicitHeight
        visible: root.info === null
        symbol:  "ads_click"
        title:   Translation.tr("Nothing selected")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Press a module on the bar or the sidebar, or one in the library below")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }

    // ── A module ──────────────────────────────────────────────────────────────
    Item {
        id: moduleBlock
        width: root.width
        visible: root.info !== null

        readonly property real gap: Tokens.spacingLg
        // Side by side when there is room and a second card to show; alone it takes the whole row.
        readonly property bool paired: root.wide && root.hasOptions
        readonly property real colW: moduleBlock.paired ? Math.floor((moduleBlock.width - moduleBlock.gap) / 2)
                                                        : moduleBlock.width
        height: moduleBlock.paired ? Math.max(whereCard.height, optionsCard.height)
              : whereCard.height + (root.hasOptions ? moduleBlock.gap + optionsCard.height : 0)

        // ── What it is, where it stands, its colour ───────────────────────────
        Section {
            id: whereCard
            grouped: true
            x: 0
            y: 0
            width: moduleBlock.colW
            height: implicitHeight
            symbol:   root.info ? (Catalogue.CATEGORIES.find(c => c.id === root.info.category)?.symbol ?? "widgets") : "widgets"
            title:    root.info ? root.info.label : ""
            subtitle: root.where === "bar"  ? Translation.tr("On the bar")
                    : root.where === "side" ? Translation.tr("On the sidebar")
                    :                         Translation.tr("Not placed")

            actions: PanelButton {
                capsule: true
                visible: root.customised
                label:   Translation.tr("Reset")
                symbol:  "restart_alt"
                variant: "ghost"
                onActivated: root.reset()
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.plain(root.form ? root.form.description : "")
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
            // touchpad or a compositor that fumbles the drag. These are the floor:
            // every module can be put on either surface, in a region, or taken off,
            // without one. (WHICH group and where in it is dragging's job.)
            //
            // Connected groups with room for every name: a segment under ~104px shows its icon
            // alone, and the row stacks the strip under its label when the column is narrow.
            SettingRow {
                label: Translation.tr("On")
                detail: !root.info ? ""
                      : !root.info.bar ? Translation.tr("Only the sidebar has a form for it")
                      : !root.info.side ? Translation.tr("Only the bar has a form for it")
                      : ""
                TabStrip {
                    connected: true
                    implicitWidth: root.choiceWidth
                    enabled: root.placed || root.blocker === ""
                    accent: Colors.of(QsWindow.window).primary
                    model: (root.info && root.info.bar ? [{ value: "bar", label: Translation.tr("Bar"), icon: "dashboard" }] : [])
                        .concat(root.info && root.info.side ? [{ value: "side", label: Translation.tr("Sidebar"), icon: "view_quilt" }] : [])
                        .concat([{ value: "", label: Translation.tr("Off"), icon: "block" }])
                    current: root.where
                    onPicked: function (v) { Config.placeModule(root.moduleId, v) }
                }
            }

            SettingRow {
                visible: root.placed
                label: Translation.tr("Region")
                TabStrip {
                    connected: true
                    implicitWidth: root.choiceWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: root.where === "bar"
                        ? [{ value: "left",   label: Translation.tr("Left"),   icon: "chevron_left" },
                           { value: "centre", label: Translation.tr("Centre"), icon: "circle" },
                           { value: "right",  label: Translation.tr("Right"),  icon: "chevron_right" }]
                        : Config.sidebarRegionIds.map(r => ({ value: r, label: Config.sidebarRegionLabel(r),
                                                              icon: r === "start" ? "keyboard_arrow_up"
                                                                  : r === "centre" ? "circle"
                                                                  : "keyboard_arrow_down" }))
                    current: {
                        void Config.layout; void Config.sidebarLayout
                        return root.where === "bar" ? (Config.locate(root.moduleId)?.region ?? "")
                             : root.where === "side" ? Config.sidebarRegionOf(root.moduleId) : ""
                    }
                    // Its own group at the end of that region: the landing a returning
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
                    StyledText { text: Translation.tr("Accent"); variant: "body"; font.weight: Font.Medium }
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
                            // "" is Default: no colour of its own, so an outlined chip
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

            SettingRow {
                rowTap: true
                visible: root.innerPillWorks
                label: Translation.tr("Inner pill")
                detail: Config.moduleInnerPill(root.moduleId) ? Translation.tr("On its own lighter chip") : Translation.tr("Straight on the group's pill")
                help: Translation.tr("Off sits this module directly on the group's own pill instead of the lighter shared chip.")
                onTapped: Config.setModuleInnerPill(root.moduleId, !Config.moduleInnerPill(root.moduleId))
                Toggle {
                    checked: Config.moduleInnerPill(root.moduleId)
                    onToggled: Config.setModuleInnerPill(root.moduleId, !Config.moduleInnerPill(root.moduleId))
                }
            }

            // One hero per surface (Config.barHero / sidebarHero): turning it on here
            // takes the chip from the module that has it, and the row says which.
            SettingRow {
                rowTap: true
                visible: root.info?.heroable === true && root.placed
                label: Translation.tr("Hero")
                detail: Config.moduleHero(root.moduleId) ? Translation.tr("On the accent's container")
                      : root.heroOther !== "" ? Translation.tr("Takes it from %1").arg(root._label(root.heroOther))
                      : root.where === "bar" ? Translation.tr("Like the rest of the bar") : Translation.tr("Like the rest of the sidebar")
                help: Translation.tr("Puts this module on a tinted chip in your accent: the surface's one emphasised pill, as a desktop widget's hero. Each surface has one.")
                onTapped: Config.setModuleHero(root.moduleId, !Config.moduleHero(root.moduleId))
                Toggle {
                    checked: Config.moduleHero(root.moduleId)
                    onToggled: Config.setModuleHero(root.moduleId, !Config.moduleHero(root.moduleId))
                }
            }
        }

        // ── Its switches ──────────────────────────────────────────────────────
        Section {
            id: optionsCard
            grouped: true
            x: moduleBlock.paired ? moduleBlock.colW + moduleBlock.gap : 0
            y: moduleBlock.paired ? 0 : whereCard.height + moduleBlock.gap
            width: moduleBlock.colW
            height: implicitHeight
            visible: root.hasOptions
            symbol:   "tune"
            title:    Translation.tr("Options")

            // Per-GROUP, not per-module (Config.groupSpacing): editing it from any one
            // member changes the whole cluster, which is why the tip names every member.
            SliderRow {
                visible: root.spacingSupported
                label: Translation.tr("Group spacing")
                help: Translation.tr("Distance between icons in this group: %1.")
                    .arg(root.groupMembers.map(id => root._label(id)).join(", "))
                from: 0
                to:   32
                step: 1
                value: root.groupSpacingValue
                readout: Math.round(root.groupSpacingValue) + "px"
                numberWidth: 44
                onCommit: function (v) { Config.setGroupSpacing(root.moduleId, v) }
            }

            // ── The spacer: its width, and the module it follows ──────────────
            SliderRow {
                visible: root.opt("spacer")
                label: Translation.tr("Size")
                help: Translation.tr("How much room this takes, in pixels. With a module to follow, this is the part that doesn't change.")
                from: 0
                to:   Config.spacerMax
                step: 1
                value: Config.spacerSize()
                readout: Math.round(Config.spacerSize()) + "px"
                numberWidth: 52
                onCommit: function (v) { Config.setSpacerSize(v) }
            }
            // Every module on the bar is a chip, so this is a block of its own and not a row's control.
            ColumnLayout {
                visible: root.opt("spacer")
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                StyledText {
                    text: Translation.tr("Follow a module")
                    variant: "body"
                    font.weight: Font.Medium
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The spacer takes the width of that module as well, so it changes when the module grows or hides.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
                ChipRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    accent: Colors.of(QsWindow.window).primary
                    current: Config.spacerFollow()
                    model: root.spacerTargets
                    onPicked: function (v) { Config.setSpacerFollow(v) }
                }
            }
            SettingRow {
                visible: root.opt("spacer") && Config.spacerFollow() !== ""
                label: Translation.tr("When it grows")
                detail: Config.spacerFill() ? Translation.tr("The spacer shrinks, so the two stay one width") : Translation.tr("The spacer grows with it")
                help: Translation.tr("Grow adds the module's width to the size. Fill takes it away from the size, never below nothing, so the module and the spacer together stay as wide as the size.")
                TabStrip {
                    connected: true
                    implicitWidth: root.pairWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "grow", label: Translation.tr("Grow"), icon: "add" },
                        { value: "fill", label: Translation.tr("Fill"), icon: "swap_horiz" }
                    ]
                    current: Config.spacerFill() ? "fill" : "grow"
                    onPicked: function (v) { Config.setSpacerFill(v === "fill") }
                }
            }

            // ── Right-click: the modules with a second face ───────────────────
            SettingRow {
                rowTap: true
                visible: root.opt("rightClick") && root.rightInfo !== null
                label: Translation.tr("Remember right-click")
                detail: Config.modulePersist(root.moduleId) ? Translation.tr("Kept across reloads") : Translation.tr("Resets on reload")
                help: root.rightInfo
                    ? Translation.tr("Right-click switches between %1 and %2. Normally that resets when the shell reloads; this keeps it.")
                        .arg(root.rightInfo.off).arg(root.rightInfo.on)
                    : ""
                onTapped: Config.setModulePersist(root.moduleId, !Config.modulePersist(root.moduleId))
                Toggle {
                    checked: Config.modulePersist(root.moduleId)
                    onToggled: Config.setModulePersist(root.moduleId, !Config.modulePersist(root.moduleId))
                }
            }
            // Which state to remember. Disabled rather than hidden, so the switch above
            // visibly has a consequence.
            SettingRow {
                rowTap: true
                visible: root.opt("rightClick") && root.rightInfo !== null
                enabled: Config.modulePersist(root.moduleId)
                opacity: enabled ? 1.0 : 0.4
                label: root.rightInfo ? root.rightInfo.label : ""
                detail: root.rightInfo
                    ? (Config.moduleRightState(root.moduleId) ? root.rightInfo.on : root.rightInfo.off)
                    : ""
                onTapped: Config.setModuleRightState(root.moduleId, !Config.moduleRightState(root.moduleId))
                Toggle {
                    checked: Config.moduleRightState(root.moduleId)
                    onToggled: Config.setModuleRightState(root.moduleId, !Config.moduleRightState(root.moduleId))
                }
            }

            SettingRow {
                rowTap: true
                visible: root.opt("dndOnly")
                label: Translation.tr("Only while Do Not Disturb")
                detail: Config.notifShowOnlyDnd() ? Translation.tr("A quiet “DND is on” sign") : Translation.tr("Always shown")
                help: Translation.tr("Hides the bell unless Do Not Disturb is on, so it reads as a discreet indicator rather than a permanent icon.")
                onTapped: Config.setNotifShowOnlyDnd(!Config.notifShowOnlyDnd())
                Toggle {
                    checked: Config.notifShowOnlyDnd()
                    onToggled: Config.setNotifShowOnlyDnd(!Config.notifShowOnlyDnd())
                }
            }

            // Stream mode's manual switch (Config.streamMode). Without it only a capture turns
            // the hiding on, so there was no way to hide notifications ahead of going live.
            // StreamMode.toggle also clears the pill's "turned off" (Config.streamOff), or
            // switching this on while that is set would change nothing.
            SettingRow {
                rowTap: true
                visible: root.moduleId === "stream"
                label: Translation.tr("Always on")
                detail: Config.streamMode ? Translation.tr("Hidden from capture all the time") : Translation.tr("Only while something captures the screen")
                help: Translation.tr("Hides notifications and the overview from screen capture even when nothing is streaming. The pill's click still pauses it.")
                onTapped: StreamMode.toggle()
                Toggle {
                    checked: Config.streamMode
                    onToggled: StreamMode.toggle()
                }
            }

            // ── The module's panel: its title row ─────────────────────────────
            SettingRow {
                rowTap: true
                visible: root.opt("panelHeader")
                label: Translation.tr("Panel header")
                detail: Config.panelHeader(root.moduleId) ? Translation.tr("Icon and title on top") : Translation.tr("Straight onto the panel")
                help: Translation.tr("The title row at the top of this module's panel. Off, the panel opens straight onto its content and is a little shorter.")
                onTapped: Config.setPanelHeader(root.moduleId, !Config.panelHeader(root.moduleId))
                Toggle {
                    checked: Config.panelHeader(root.moduleId)
                    onToggled: Config.setPanelHeader(root.moduleId, !Config.panelHeader(root.moduleId))
                }
            }

            // ── Peek: a card beside it when something happens (EventPeek) ─────
            SettingRow {
                rowTap: true
                visible: root.opt("peek") && root.peekKey !== ""
                label: Translation.tr("Peek")
                detail: Config[root.peekKey] ? Translation.tr("A card beside it when something happens") : Translation.tr("Only its own panel")
                help: Translation.tr("When something happens to it, a card opens beside it for a moment, on the monitor you're on and never over a panel you opened.")
                onTapped: Config[root.peekKey] = !Config[root.peekKey]
                Toggle {
                    checked: Config[root.peekKey] === true
                    onToggled: Config[root.peekKey] = !Config[root.peekKey]
                }
            }
            // Clips keeps its one Peek switch on the Clips page (it sits beside what the card shows), so
            // here the row points there rather than offering a second copy of the same setting.
            SettingRow {
                rowTap: true
                visible: root.opt("peek") && root.moduleId === "clips"
                label: Translation.tr("Peek is set on the Clips page")
                onTapped: UiState.openSettingsTo("ClipsPage.qml")
                MaterialIcon {
                    name: "chevron_right"
                    color: Colors.of(QsWindow.window).fgDim
                    font.pixelSize: Tokens.iconMd
                }
            }
        }
    }

    // ── The two modules with settings of their own ────────────────────────────
    DockOptions {
        width: root.width
        height: implicitHeight
        visible: root.moduleId === "dock"
    }
    StatsOptions {
        width: root.width
        height: implicitHeight
        visible: root.moduleId === "stats"
    }
}
