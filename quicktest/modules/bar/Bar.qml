pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "widgets"

// ── Bar ───────────────────────────────────────────────────────────────────────
// The status bar.
//
// ── It renders Config.layout. It does not know what's in it. ──────────────────
// Every widget used to be written into this file by hand, in a fixed order, inside
// hand-picked groups — and then each one carried a `visible: Config.moduleOn(...)`
// so it could be hidden. That made the bar's order and grouping structural (only an
// edit to this file could change them) while visibility was data. Three facts about
// a module, stored two different ways, and only one of them editable.
//
// Now there's one fact: the layout. `Config.layout` is region → groups → module ids,
// this file walks it, and `moduleFor()` maps an id to a widget. A module absent from
// the layout isn't hidden — it isn't built. Dragging one in the settings page moves
// the real thing, because there is nothing else for it to move.
//
// What that bought, concretely: the `visible:` line on all thirteen widgets, the
// hasToggles/hasMainGroup/hasTray booleans that existed to hide a group once all its
// children were hidden, and the showDivider chains that had to ask "is any VISIBLE
// group ahead of me" — all gone. A group in the layout has modules in it by
// construction (Config prunes empty ones), and it has a divider iff it isn't first.
//
// ── The cost, stated plainly ─────────────────────────────────────────────────
// A Repeater over a JS array rebuilds every delegate when the array is reassigned,
// so editing the layout tears down and rebuilds the bar — cava restarts, the tray
// re-reads its items. That's the right trade here (you edit the layout roughly never,
// and the alternative is hand-diffing a nested structure into an ObjectModel), but it
// is why the drag UI must commit on RELEASE and not per-frame: a rebuild mid-drag
// destroys the delegate holding the mouse grab. That bug has been paid for twice in
// this codebase already — once in the overview's window drag, once in Pins.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    anchors.top:   true
    anchors.left:  true
    anchors.right: true
    // Bar height and inset are user settings now (Settings → Bar).
    //
    // The apron is extra window BELOW the bar, only while fused to the screen
    // frame: the fillets where the edge pills sweep into the ring's side strips
    // land past the bar's own height, and an arc crossing a window boundary gets
    // clipped mid-curve (that clipping used to cap them at barInset — a notch,
    // not a sweep). The zone and mask below keep the apron from reserving space
    // or eating clicks, so to everything but the fillets the bar is still
    // barThickness tall.
    implicitHeight: Config.barThickness + Config.frameApron
    // Explicit, not Auto-derived from the window size — the apron must not push
    // tiled windows down. Same direct-assignment idiom as DesktopClock's zone.
    exclusiveZone: Config.barThickness
    // Clicks in the apron belong to whatever is under it.
    mask: Region { width: root.width; height: Config.barThickness }
    color: "transparent"

    // The screen frame's top edge — the thin band, stubs and top corners, drawn
    // behind every pill. Lives inside this window (not in ScreenFrame) because
    // same-layer surfaces stack by map order; see BarFrameEdge for the full story.
    // `barFrame` draws the identical band on its own, without ScreenFrame's
    // side/bottom strips — the "just merge the bar" toggle.
    BarFrameEdge {
        anchors.fill: parent
        z: -1
        visible: Config.screenFrame || Config.barFrame
    }

    // ── Its own layer namespace, so the compositor can find it ────────────────
    // Blur is not something this shell can draw — it's a Hyprland layer_rule, matched by
    // namespace, applied when the layer is MAPPED. Without this the bar shared the
    // default `quickshell` namespace with every other PanelWindow, so any rule aimed at
    // the bar would have hit the panels and the launcher too.
    //
    // Naming it is all this file can do. The rule itself lives in your Hyprland config,
    // beside the one the overview already relies on:
    //
    //     hl.layer_rule({ match = { namespace = "^quickshell-bar$" }, blur = true })
    //
    // Config.barOpacity is what makes that blur visible — an opaque pill has nothing
    // behind it to blur.
    WlrLayershell.namespace: "quickshell-bar"

    readonly property var hyprMonitor:
        Hyprland.monitors.values.find(m => m.name === root.screen?.name) ?? null

    // The bar's pills float inside the bar's height, inset by barInset — except in
    // square mode, where they run flush to the screen edges.
    // Not readonly: the Behavior needs to drive it through intermediate values as
    // barShape flips, which a readonly property won't allow.
    property int inset: Config.barShape ? 0 : Config.barInset
    Behavior on inset { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // Horizontal inset. Fused, the outermost pills run FLUSH to the screen edge and
    // merge into the ring's side stubs — the pill and the strip become one piece of
    // material, which reads cleaner than a pill floating a flare's width inside a
    // stub it is supposed to have grown out of. So there is nothing to inset past.
    // Not readonly: same Behavior note as `inset`.
    property int sideInset: Config.frameFused ? 0 : inset
    Behavior on sideInset { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // Opening a panel marks this screen as the one that owns it.
    function openLeft(name)  { UiState.activeScreen = root.screen; UiState.toggleLeft(name) }
    function openRight(name) { UiState.activeScreen = root.screen; UiState.toggleRight(name) }

    // ── Which module owns an open panel ───────────────────────────────────────
    // A group keeps its pill expanded while a panel it launched is open, so the panel
    // visibly belongs to the button you pressed. With groups coming from data, the
    // group can't name its panel in advance — it asks whether any module inside it has
    // one open.
    function panelOpenFor(id) {
        switch (id) {
            case "palette":    return UiState.colorSchemeOpen
            case "wallpaper":  return UiState.wallpaperOpen
            case "volume":     return UiState.equalizerOpen
            case "wifi":       return UiState.wifiOpen
            case "update":     return UiState.updateOpen
            case "clock":      return UiState.desktopClockOpen
            default:           return false
        }
    }

    function groupExpanded(group) {
        for (const id of group) if (root.panelOpenFor(id)) return true
        return false
    }

    function regionExpanded(region) {
        for (const g of (Config.layout[region] ?? [])) if (root.groupExpanded(g)) return true
        return false
    }

    // ── The tray is the one module that hides itself ──────────────────────────
    // Not a preference — a fact about the system. An empty tray has nothing to draw, so
    // its group would be an empty pill. This is the only place the bar overrides the
    // layout, and it's why `visible` still exists on exactly one delegate.
    function moduleVisible(id) {
        // The tray hides when empty (a system fact). The notifications pill can be
        // configured to hide unless DND is on, turning it into a discreet "DND is
        // active" indicator rather than a permanent bell.
        if (id === "tray") return SystemTray.items.values.length > 0
        if (id === "notifications")
            return !Config.notifShowOnlyDnd() || Notifications.dnd
        return true
    }

    // ══ The module registry ═══════════════════════════════════════════════════
    // id → widget, with its wiring. The wiring has to live here (it reaches for
    // root.screen, root.hyprMonitor, UiState) — which is exactly why this is a map of
    // Components in the Bar rather than a lookup table in Config. Config knows what
    // modules ARE; only the bar knows how to build one.
    function moduleFor(id) {
        switch (id) {
            case "shapeToggle": return shapeToggleC
            case "modeToggle":  return modeToggleC
            case "palette":     return paletteC
            case "wallpaper":   return wallpaperC
            case "volume":      return volumeC
            case "keyboard":    return keyboardC
            case "update":      return updateC
            case "workspaces":  return workspacesC
            case "reload":      return reloadC
            case "tray":        return trayC
            case "visualizer":  return visualizerC
            case "wifi":        return wifiC
            case "clock":       return clockC
            case "notifications": return notificationsC
            case "overview":    return overviewC
            case "settings":    return settingsC
            default:            return null
        }
    }

    Component {
        id: shapeToggleC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("shapeToggle", Colors.primary)
            icon: Config.barShape ? Icons.asset("winoff") : Icons.asset("winon")
            onClicked: Config.toggleShape()
        }
    }
    Component {
        id: modeToggleC
        IconButton {
            squareMode: Config.barShape
            active:     Config.barMerged
            accent:     Config.moduleAccent("modeToggle", Colors.primary)
            icon:       Icons.asset("barmode")
            onClicked:  Config.toggleMode()
        }
    }
    Component {
        id: paletteC
        IconButton {
            squareMode: Config.barShape
            active:     UiState.colorSchemeOpen
            accent:     Config.moduleAccent("palette", Colors.primary)
            icon:       Icons.asset("Palette")
            onClicked:  root.openLeft("colorScheme")
        }
    }
    Component {
        id: wallpaperC
        IconButton {
            squareMode: Config.barShape
            active:     UiState.wallpaperOpen
            accent:     Config.moduleAccent("wallpaper", Colors.primary)
            icon:       Icons.asset("wallpaper")
            onClicked:  root.openLeft("wallpaper")
        }
    }
    Component {
        id: volumeC
        VolumePill {
            accent: Config.moduleAccent("volume", Colors.focus)
            active: UiState.equalizerOpen
            onToggled: root.openLeft("equalizer")
        }
    }
    Component { id: keyboardC; KeyboardPill { accent: Config.moduleAccent("keyboard", Colors.primary) } }
    Component {
        id: updateC
        UpdatePill {
            accent: Config.moduleAccent("update", Colors.primary)
            onRequested: function(count) {
                UiState.activeScreen       = root.screen
                UiState.pendingUpdateCount = count
                UiState.updateRequestId++
            }
        }
    }
    Component { id: workspacesC; WorkspacesPill {
        accent:  Config.moduleAccent("workspaces", Colors.primary)
        monitor: root.hyprMonitor
    } }
    Component { id: reloadC;     ReloadPill { accent: Config.moduleAccent("reload", Colors.primary) } }
    Component { id: trayC;       TrayPill {
        accent:       Config.moduleAccent("tray", Colors.primary)
        parentWindow: root
    } }
    Component { id: visualizerC; VisualizerPill { accent: Config.moduleAccent("visualizer", Colors.focus) } }
    Component {
        id: wifiC
        WifiPill {
            accent: Config.moduleAccent("wifi", Colors.focus)
            active: UiState.wifiOpen
            onToggled: root.openRight("wifi")
        }
    }
    Component {
        id: clockC
        ClockPill {
            accent: Config.moduleAccent("clock", Colors.primary)
            active: UiState.desktopClockOpen
            onToggled: UiState.toggleDesktopClock()
        }
    }
    // Notifications / Do Not Disturb. Click opens the notification centre in the
    // overview; right-click toggles DND. The bell changes icon AND colour: bell-off
    // in the warning tint while DND is on, info-tinted when notifications are
    // waiting, muted otherwise.
    Component {
        id: notificationsC
        IconButton {
            squareMode: Config.barShape
            active:     UiState.overviewOpen && UiState.overviewTarget === "notifs"
            accent:     Config.moduleAccent("notifications", Colors.primary)
            glyph:      Notifications.dnd ? "󰂛" : "󰂚"
            iconColor:  Notifications.dnd        ? Colors.warning
                      : Notifications.count > 0  ? Colors.info
                      :                            Colors.stateIdleFg
            onClicked:      UiState.openOverviewTo("notifs")
            onRightClicked: Notifications.toggleDnd()
        }
    }
    Component {
        id: overviewC
        IconButton {
            squareMode: Config.barShape
            active:     UiState.overviewOpen
            accent:     Config.moduleAccent("overview", Colors.primary)
            glyph:      "󰕴"
            onClicked:  UiState.toggleOverview()
        }
    }
    Component {
        id: settingsC
        IconButton {
            squareMode: Config.barShape
            active:     UiState.overviewOpen && UiState.overviewTarget === "settings"
            accent:     Config.moduleAccent("settings", Colors.primary)
            icon:       Icons.asset("settings")
            onClicked:  UiState.openOverviewTo("settings")
        }
    }

    // ══ LEFT ══════════════════════════════════════════════════════════════════
    BarRegion {
        anchors.top:        parent.top
        anchors.left:       parent.left
        anchors.topMargin:  root.inset
        anchors.leftMargin: root.sideInset

        // Merged into the ring's left strip when fused: no outer flare, a squared
        // outer edge, and one fillet where its bottom leaves the strip.
        mergeLeft: Config.frameFused

        // Only `sideInset` px of screen exist to its left, so that's all the pill
        // may grow into. Without this it extended past x=0 on hover and the
        // layer-shell surface sliced it off. Merged, the pill is already flush and
        // there is nothing left to grow into on that side.
        outerRoomLeft: root.sideInset

        forceExpanded: root.regionExpanded("left")

        BarGroupRow {
            region: "left"
            roomLeft: root.sideInset
            componentFor:  root.moduleFor
            groupExpanded: root.groupExpanded
            moduleVisible: root.moduleVisible
        }
    }

    // ══ CENTER ════════════════════════════════════════════════════════════════
    // Positioned so the WORKSPACES group lands on the true screen center, rather than
    // centering the region as a whole. Otherwise the workspace dots — the bar's visual
    // anchor — would drift sideways every time an app added or removed a tray icon, or
    // whenever the keyboard-layout tag changed width.
    BarRegion {
        id: center

        anchors.top:       parent.top
        anchors.topMargin: root.inset

        forceExpanded: root.regionExpanded("centre")

        // ── Finding the anchor group, now that groups are data ────────────────
        // This used to read `keyboardGroup.width + gap + mainGroup.width / 2` off two
        // ids, because the layout was written here and those groups were guaranteed to
        // exist. Neither is true now: the user can drag workspaces anywhere, into any
        // group, or remove it entirely.
        //
        // So: find whichever group CONTAINS workspaces, sum the widths of the groups
        // before it, and centre on that group. With workspaces gone there is no anchor
        // to hold, and the region simply centres itself — which is the honest answer,
        // not a fallback.
        readonly property int anchorGroup: {
            // Anchoring turned off: report "no anchor" and let anchorOffset fall through
            // to centring the region as a whole. The no-workspaces case already had to
            // mean exactly that, so the setting doesn't need a second code path — it
            // just takes the one that was already there.
            if (!Config.barCentreAnchor) return -1

            const groups = Config.layout.centre ?? []
            for (let i = 0; i < groups.length; i++)
                if (groups[i].indexOf("workspaces") !== -1) return i
            return -1
        }

        readonly property real anchorOffset: {
            // Touch the repeater's count so this re-runs as groups are built —
            // itemAt() is not itself a bindable dependency, and without this the
            // offset would be computed once against an empty repeater and stick.
            const n = centerGroups.count
            if (center.anchorGroup < 0 || n === 0) return center.width / 2

            let lead = 0
            for (let i = 0; i < center.anchorGroup && i < n; i++) {
                const item = centerGroups.itemAt(i)
                if (item && item.visible) lead += item.width + center.gap
            }
            const anchor = centerGroups.itemAt(center.anchorGroup)
            return center.edgePad + lead + (anchor ? anchor.width / 2 : 0)
        }

        x: Math.round(root.width / 2 - center.anchorOffset)

        BarGroupRow {
            id: centerGroups
            region: "centre"
            componentFor:  root.moduleFor
            groupExpanded: root.groupExpanded
            moduleVisible: root.moduleVisible
        }
    }

    // ══ RIGHT ═════════════════════════════════════════════════════════════════
    BarRegion {
        anchors.top:         parent.top
        anchors.right:       parent.right
        anchors.topMargin:   root.inset
        anchors.rightMargin: root.sideInset

        mergeRight: Config.frameFused

        outerRoomRight: root.sideInset

        forceExpanded: root.regionExpanded("right")

        BarGroupRow {
            region: "right"
            roomRight: root.sideInset
            componentFor:  root.moduleFor
            groupExpanded: root.groupExpanded
            moduleVisible: root.moduleVisible
        }
    }
}
