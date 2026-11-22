pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/island.js" as Rules
import "../../../config/islands.js" as Islands
import "../../desktop/widgets/toggles.js" as Toggles
import "island"

Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var layout: UiState.islandLayout
    readonly property int railCount: Islands.SIDES.reduce((n, s) => n + root.layout.rails[s].length, 0)
    readonly property bool dashboardOn: Islands.railOf("today", root.layout) !== ""
    readonly property bool mediaInMiddle: root.layout.rails.center.indexOf("media") >= 0

    // Covers every key in Config.panelZoomNames: the placement list plus the middle island's own two,
    // which have no side to pick but resize like anything else.
    function meta(key) { return Islands.meta(key) }
    // Config.panelZoom is a sparse map (a panel at 1.0 is never written), so everything listed has a size to undo.
    readonly property var resized: Config.panelZoomNames.filter(n => Config.panelZoomed(n))

    // The connected choices inside a row: sized by implicitWidth, as the row's control slot is a plain Item.
    readonly property int pairWidth:  Tokens.fieldHeight * 7
    readonly property int tripleWidth: Tokens.fieldHeight * 10

    // ── Behaviour's scope ─────────────────────────────────────────────────────
    // "all" edits the shared options; a side edits that island's overrides over them.
    property string scope: "all"
    readonly property bool shared: root.scope === "all"
    function value(name) { return root.shared ? UiState.islandShared[name] : UiState.islandOpt(root.scope, name) }
    function own(name) { return !root.shared && Islands.overrides(root.scope, name, Config.islandOverrides) }
    function sharedValue(name) { return Islands.optionOf("", name, UiState.islandShared, {}) }
    function put(name, v) {
        if (!root.shared) { Config.islandOverrides = Islands.withOverride(Config.islandOverrides, root.scope, name, v); return }
        switch (name) {
        case "openBy":  Config.islandOpenBy = v; break
        case "delay":   Config.islandDelay = v; break
        case "linger":  Config.islandLinger = v; break
        case "handle":  Config.islandHandle = v; break
        case "scale":   Config.islandScale = v; break
        case "effects": Config.islandEffects = v; break
        }
    }
    function unset(name) { Config.islandOverrides = Islands.withOverride(Config.islandOverrides, root.scope, name, undefined) }
    readonly property int ownCount: root.shared ? 0 : Islands.overrideCount(root.scope, Config.islandOverrides)

    SettingsPage {
        anchors.fill: parent

        grouped:      true
        // The board has three islands side by side.
        groupedWidth: 800
        glyph:     "󰕮"
        title:     Translation.tr("Islands")
        titleTail: ""
        accent:    root.palette.primary
        subtitle:  !Config.island ? Translation.tr("Off: every panel opens in the plain column on its side")
                 : Translation.tr("%1 islands with pages, %2 pages on their rails")
                       .arg(Islands.SIDES.filter(s => root.layout.rails[s].length > 0).length).arg(root.railCount)

        // The page's one master switch, with its state beside it.
        actions: RowLayout {
            spacing: Tokens.spacingSm
            StyledText {
                text: Config.island ? Translation.tr("Islands on") : Translation.tr("Islands off")
                variant: "label"
                emphasis: "dim"
            }
            Toggle {
                accent: root.palette.primary
                accessibleName: Translation.tr("Islands")
                checked: Config.island
                onToggled: Config.island = !Config.island
            }
        }

        // ══ The board ═════════════════════════════════════════════════════════
        // A tool (drag a page between rails), not a form: one segment of a grouped Section, a whole row wide.
        Section {
            grouped:  true
            fullRow:  true
            symbol:   "view_quilt"
            title:    Config.island ? Translation.tr("Islands") : Translation.tr("Columns")
            subtitle: Config.island ? Translation.tr("Drag a page, or right-click it for a menu")
                                    : Translation.tr("Drag a panel to the column it opens in")
            help:     (Config.island ? Translation.tr("Drag a page between islands, up and down a rail, or to open alone.")
                                     : Translation.tr("The islands are off, so panels open in the plain column on their side. Switch them on for rails.")) + " "
                      + Translation.tr("A rail is the column of pages inside an island, top first: the island opens on the one it was last on. A panel that opens alone drops from the bar in that side's plain column, as it does with the islands off. An island with no pages has no handle. Dashboard, Performance and Weather have no panel of their own, so off every rail they wait under the board; Media off every rail opens as Now Playing.")

            actions: ChipButton {
                visible: Config.island
                symbol: "restart_alt"
                label: resetLayout.armed ? Translation.tr("Sure?") : Translation.tr("Reset")
                on: resetLayout.armed
                ArmLatch {
                    id: resetLayout
                    onConfirmed: Config.islandRails = Islands.defaultRails()
                }
                onActivated: resetLayout.trigger()
                HoverTip { text: Translation.tr("Put every page back on the island it ships on"); alignEnd: true }
            }

            IslandBoard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                scope: root.scope
                onTuned: side => root.scope = side
            }
        }

        // ══ Behaviour ═════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "tune"
            title:    Translation.tr("Behaviour")
            subtitle: root.shared ? Translation.tr("Shared by every island, unless one has its own")
                    : root.ownCount === 0 ? Translation.tr("%1 island: all shared").arg(Translation.tr(Islands.sideMeta(root.scope).label))
                    : Translation.tr("%1 island: %2 of its own").arg(Translation.tr(Islands.sideMeta(root.scope).label)).arg(root.ownCount)
            enabled: Config.island
            opacity: Config.island ? 1 : 0.55

            actions: ChipButton {
                visible: !root.shared && root.ownCount > 0
                symbol: "undo"
                label: Translation.tr("All shared")
                onActivated: {
                    let m = Config.islandOverrides
                    for (const name in Islands.OPTIONS) m = Islands.withOverride(m, root.scope, name, undefined)
                    Config.islandOverrides = m
                }
            }

            // Which island the rows below edit: all of them, or one's own values over the shared ones.
            TabStrip {
                Layout.fillWidth: true
                Layout.fillHeight: false
                connected: true
                accent: root.palette.primary
                model: [{ value: "all", label: Translation.tr("All islands"), icon: "" }].concat(Islands.SIDES.map(s => ({
                    value: s,
                    label: Translation.tr(Islands.sideMeta(s).label) + (Islands.overrideCount(s, Config.islandOverrides) > 0 ? " •" : ""),
                    icon: ""
                })))
                current: root.scope
                onPicked: v => root.scope = v
            }

            SettingRow {
                label:  Translation.tr("Opens on")
                detail: root.own("openBy") ? Translation.tr("This island only") : !root.shared ? Translation.tr("Shared") : ""
                help:   Translation.tr("Resting the pointer opens it after a moment; a click on the handle then keeps it open. With Click, only a click opens it, so a pointer passing along the bar never does.")
                // A Row: the slot is a plain Item and would stack the two.
                Row {
                    spacing: Tokens.spacingSm
                    TabStrip {
                        anchors.verticalCenter: parent.verticalCenter
                        connected: true
                        implicitWidth: root.pairWidth
                        accent: root.palette.primary
                        model: [
                            { value: "hover", label: Translation.tr("Hover") },
                            { value: "click", label: Translation.tr("Click") }
                        ]
                        current: root.value("openBy")
                        onPicked: v => root.put("openBy", v)
                    }
                    IslandResetChip {
                        anchors.verticalCenter: parent.verticalCenter
                        page: root; name: "openBy"
                        shown: root.sharedValue("openBy") === "click" ? Translation.tr("Click") : Translation.tr("Hover")
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.value("openBy") !== "click"
                SliderRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Opens after")
                    help:  Translation.tr("How long the pointer rests on the handle before the card opens. Longer keeps a pointer that is only passing along the bar from opening it.")
                    from: 0
                    to: 600
                    step: 20
                    value: root.value("delay")
                    readout: Math.round(root.value("delay")) + " ms"
                    numberWidth: 72
                    onCommit: function (v) { root.put("delay", Math.round(v)) }
                }
                IslandResetChip { page: root; name: "delay"; shown: Math.round(root.sharedValue("delay")) + " ms" }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                SliderRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Closes after")
                    help:  Translation.tr("How long the pointer must be off the card before it goes. A pin keeps it open.")
                    from: 150
                    to: 1500
                    step: 50
                    value: root.value("linger")
                    readout: Math.round(root.value("linger")) + " ms"
                    numberWidth: 72
                    onCommit: function (v) { root.put("linger", Math.round(v)) }
                }
                IslandResetChip { page: root; name: "linger"; shown: Math.round(root.sharedValue("linger")) + " ms" }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                SliderRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Handle length")
                    help:  Translation.tr("How long the handle is, on the bar's top edge. A longer one is easier to land on.")
                    from: 24
                    to: 320
                    step: 8
                    value: root.value("handle")
                    readout: Math.round(root.value("handle")) + " px"
                    numberWidth: 72
                    onCommit: function (v) { root.put("handle", Math.round(v)) }
                }
                IslandResetChip { page: root; name: "handle"; shown: Math.round(root.sharedValue("handle")) + " px" }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                SliderRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Size")
                    help:  Translation.tr("The whole card, text and icons together.")
                    from: 80
                    to: 125
                    step: 5
                    value: Math.round(root.value("scale") * 100)
                    readout: Math.round(root.value("scale") * 100) + " %"
                    numberWidth: 64
                    onCommit: function (v) { root.put("scale", Math.round(v) / 100) }
                }
                IslandResetChip { page: root; name: "scale"; shown: Math.round(root.sharedValue("scale") * 100) + " %" }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Effects")
                detail: (root.value("effects") ? Translation.tr("Weather drifts behind the cards; shapes breathe with the music") : Translation.tr("Still cards"))
                        + (root.own("effects") ? "  ·  " + Translation.tr("this island only") : "")
                onTapped: root.put("effects", !root.value("effects"))
                Row {
                    spacing: Tokens.spacingSm
                    IslandResetChip {
                        anchors.verticalCenter: parent.verticalCenter
                        page: root; name: "effects"
                        shown: root.sharedValue("effects") ? Translation.tr("On") : Translation.tr("Off")
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        accent: root.palette.primary
                        checked: root.value("effects")
                        onToggled: root.put("effects", !root.value("effects"))
                    }
                }
            }
        }

        // ══ Switches ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            enabled:  root.dashboardOn
            opacity:  root.dashboardOn ? 1 : 0.55
            symbol:   "dashboard"
            title:    Translation.tr("Dashboard switches")
            subtitle: root.dashboardOn ? Translation.tr("Up to six, in the order you pick them") : Translation.tr("The Dashboard is on no island")

            PickOrderList {
                Layout.fillWidth: true
                table: Toggles.PICKABLE
                allIds: Toggles.ALL
                shown: Config.islandSwitches
                max: 6
                onPicked: list => Config.islandSwitches = list
            }
        }

        // ══ The middle's handle ═══════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "pip"
            title:   Translation.tr("Handle")
            help:    Translation.tr("Where the middle island's handle sits, and what it shows at rest. The side islands' handles stand over the cards they open. Keys open it too: qs ipc call island toggle, or island show media.")
            enabled: Config.island
            opacity: Config.island ? 1 : 0.55

            actions: ChipButton {
                visible: Config.island
                symbol: "play_arrow"
                label: Translation.tr("Try it")
                solid: true
                enabled: root.layout.rails.center.length > 0
                onActivated: UiState.openIsland("center", {})
            }

            SettingRow {
                label:  Translation.tr("Position")
                detail: Config.islandAlign === "left"  ? Translation.tr("Towards the left of the bar")
                      : Config.islandAlign === "right" ? Translation.tr("Towards the right of the bar")
                      :                                  Translation.tr("In the middle of the bar")
                TabStrip {
                    connected: true
                    implicitWidth: root.tripleWidth
                    accent: root.palette.primary
                    model: [
                        { value: "left",   label: Translation.tr("Left") },
                        { value: "centre", label: Translation.tr("Middle") },
                        { value: "right",  label: Translation.tr("Right") }
                    ]
                    current: Config.islandAlign
                    onPicked: v => Config.islandAlign = v
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Live handle")
                detail: Config.islandLive ? Translation.tr("A small pill shows the song or a timer") : Translation.tr("A thin line; a recording still shows")
                help:   Translation.tr("While a song plays or a timer runs, the middle island's handle hangs out of the bar as a small pill that says so, and the card grows out of it. A recording always shows, and a click on it stops the recording. An empty middle island has no handle and no pill.")
                onTapped: Config.islandLive = !Config.islandLive
                Toggle { accent: root.palette.primary; checked: Config.islandLive; onToggled: Config.islandLive = !Config.islandLive }
            }
            SettingRow {
                rowTap: true
                visible: Config.islandLive
                enabled: root.mediaInMiddle
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Open on the song")
                detail: !root.mediaInMiddle ? Translation.tr("Needs Media on the middle island")
                      : Config.islandFollow ? Translation.tr("Opened from a song, the card shows Media") : Translation.tr("Always the page you were on")
                onTapped: Config.islandFollow = !Config.islandFollow
                Toggle {
                    accent: root.palette.primary
                    checked: Config.islandFollow && root.mediaInMiddle
                    onToggled: Config.islandFollow = !Config.islandFollow
                }
            }
        }

        // ══ This window ═══════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "settings"
            title:   Translation.tr("Settings window")
            subtitle: Config.settingsPanel ? Translation.tr("A panel on the bottom edge") : Translation.tr("A floating window")
            help:    Translation.tr("Window: a floating window the compositor places, like any other app. Panel: pinned to the bottom edge and merged into the frame, so it never covers the bar.")

            TabStrip {
                Layout.fillWidth: true
                connected: true
                accent: root.palette.primary
                model: [
                    { value: false, label: Translation.tr("Window"), icon: "desktop_mac" },
                    { value: true,  label: Translation.tr("Panel"),  icon: "dashboard" }
                ]
                current: Config.settingsPanel
                onPicked: function (v) { Config.settingsPanel = v }
            }

            // Where the panel stands: only a panel has a place to pick.
            TabStrip {
                Layout.fillWidth: true
                connected: true
                enabled: Config.settingsPanel
                opacity: enabled ? 1 : 0.4
                accent: root.palette.primary
                // Every icon name needs an icons.js entry or a machine without the Material Symbols font
                // renders "?": the align_horizontal_* family has none, so these say the same thing with
                // mapped glyphs.
                model: [
                    { value: "left",   label: Translation.tr("Left"),   icon: "chevron_left" },
                    { value: "center", label: Translation.tr("Centre"), icon: "circle" },
                    { value: "right",  label: Translation.tr("Right"),  icon: "chevron_right" }
                ]
                current: Config.settingsPanelSide
                onPicked: function (v) { Config.settingsPanelSide = v }
            }
        }

        // ══ Panels ════════════════════════════════════════════════════════════
        // The surfaces a bar module opens: undo a resize, their backdrop, and the cookies carried onto the
        // rest of the shell's material.
        Section {
            grouped:  true
            symbol:   "web"
            title:    Translation.tr("Panels")
            subtitle: root.resized.length > 0 ? Translation.tr("%1 resized").arg(root.resized.length) : Translation.tr("None resized")

            // Lists only what has been changed (the zoom map is sparse), so a chip here always has a size to
            // undo and "Reset all" is never a no-op button.
            SettingRow {
                label:  Translation.tr("Resized panels")
                detail: root.resized.length === 0 ? Translation.tr("None") : Translation.tr("%1 resized").arg(root.resized.length)
                help:   Translation.tr("Drag a panel's outer bottom corner to resize it. Click one here to put it back to its default size.")

                // One button for all of them, and only once there is more than one to be worth it. ArmLatch,
                // not a bare click: it throws every size away at once and there is no undo.
                PanelButton {
                    visible: root.resized.length > 1
                    capsule: true
                    ArmLatch {
                        id: resetAllZoom
                        onConfirmed: Config.resetPanelZooms()
                    }
                    label:   resetAllZoom.armed ? Translation.tr("Sure?") : Translation.tr("Reset all")
                    variant: resetAllZoom.armed ? "primary" : "ghost"
                    accent:  root.palette.primary
                    onActivated: resetAllZoom.trigger()
                }
            }

            // A chip per resized panel: the only action is "put it back".
            Flow {
                Layout.fillWidth: true
                visible: root.resized.length > 0
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.resized

                    delegate: Rectangle {
                        id: zoomChip
                        required property var modelData
                        readonly property real zoom: Config.panelZoomFor(zoomChip.modelData)

                        implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: 32
                        radius: Tokens.radiusPill
                        // A wash, not an outline: a row of options spends its weight on what it says.
                        color: root.palette.alpha(root.palette.fg, chipHover.hovered ? 0.12 : 0.06)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Config.resetPanelZoom(zoomChip.modelData) }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm

                            MaterialIcon {
                                name: root.meta(zoomChip.modelData).icon
                                fill: 0
                                font.pixelSize: Tokens.iconSm
                                color: root.palette.fgMuted
                            }
                            StyledText {
                                text: root.meta(zoomChip.modelData).label
                                variant: "caption"
                            }
                            StyledText {
                                text: Math.round(zoomChip.zoom * 100) + "%"
                                variant: "caption"
                                emphasis: "muted"
                            }
                            MaterialIcon {
                                name: "restart_alt"
                                fill: 0
                                font.pixelSize: Tokens.iconSm
                                color: chipHover.hovered ? root.palette.primary : root.palette.fgDim
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }
                        }
                    }
                }
            }

            // One shared field of soft shapes that every open panel looks onto, so two panels side by side, or
            // one swapping for another, show the same drift.
            SettingRow {
                rowTap: true
                label:  Translation.tr("Panel backdrop")
                detail: Config.panelCookies ? (Config.motionEnabled ? Translation.tr("Drifting") : Translation.tr("Still, motion is off")) : Translation.tr("Panels stay plain")
                help:   Translation.tr("Soft cookie shapes drifting behind every panel. They hold still when animations are switched off, and cost nothing while no panel is open.")
                onTapped: Config.panelCookies = !Config.panelCookies
                Toggle {
                    accent: root.palette.primary
                    checked: Config.panelCookies
                    onToggled: Config.panelCookies = !Config.panelCookies
                }
            }

            // The same field, continuing onto the rest of the shell's material (FrameDrift). Two ways to have
            // it, so it is a choice and not a fixed behaviour.
            SettingRow {
                rowTap: true
                label:  Translation.tr("Cookies on the bar, sidebar & frame")
                detail: !Config.barCookies ? Translation.tr("Cookies stay inside the panels")
                      : !Config.motionEnabled ? Translation.tr("Still, motion is off")
                      : Config.barCookiesFrom === "everywhere" ? Translation.tr("Everywhere") : Translation.tr("From panels")
                help:   Config.barCookiesFrom === "everywhere"
                        ? Translation.tr("A field of their own behind the bar, the sidebar and the frame, each shape coming and going on a slow life, and around an open panel the panel's own, so a cookie crossing into it stays whole. Keeps the bar redrawing. Stands down in Game mode and under a fullscreen window.")
                        : Translation.tr("Cookies show here only around an open panel or after drifting out of one. Then they keep drifting, across the bar, the sidebar and the frame, until they leave the screen. A cookie crossing between a panel and the bar stays whole. Stands down in Game mode and under a fullscreen window.")
                onTapped: Config.barCookies = !Config.barCookies
                Toggle {
                    accent: root.palette.primary
                    checked: Config.barCookies
                    onToggled: Config.barCookies = !Config.barCookies
                }
            }
            SettingRow {
                enabled: Config.barCookies
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Cookies from")
                detail: Config.barCookiesFrom === "everywhere" ? Translation.tr("Their own field behind everything")
                                                               : Translation.tr("Only what drifts out of a panel")
                TabStrip {
                    connected: true
                    implicitWidth: root.pairWidth
                    accent: root.palette.primary
                    model: [
                        { value: "panels",     label: Translation.tr("From panels"), icon: "" },
                        { value: "everywhere", label: Translation.tr("Everywhere"),  icon: "" }
                    ]
                    current: Config.barCookiesFrom === "everywhere" ? "everywhere" : "panels"
                    onPicked: function (v) { Config.barCookiesFrom = v }
                }
            }
        }
    }
}
