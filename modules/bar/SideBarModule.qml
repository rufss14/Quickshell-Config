import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../../config"
import "../../services"
import "../../state"

// ── SideBarModule ─────────────────────────────────────────────────────────────
// The top bar's one-click modules as sidebar cells, so a module can live on either
// surface (config/modules.js gives each of them a `side` form pointing here). One
// file, keyed by `moduleId` (SideGroupHost hands it over), because each is a glyph,
// sometimes a reading under it, and a click: the SAME services the pills call,
// nothing re-derived. A module whose panel is portable opens it in the sidebar's
// dock, beside this cell; wallpaper and updates keep their bar panels (the gallery
// is a fixed 620-wide pin, the update panel is driven by the bar's request id).
//
//   click     what the pill's click does      right   Settings › Sidebar
//   middle    the pill's secondary action     wheel   volume only
//
// Workspaces, the tray and the visualizer are rows of live things, not a glyph: each
// has its own file (SideWorkspaces, SideTray, SideVisualizer — sidecells.js).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null
    property string moduleId: ""

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    function sideOpen(key) { return UiState.sidePanel === key && root.ownsPanel }
    function toggleSide(key) { UiState.toggleSidePanel(key, root.moduleId, root.screen) }
    function toggleBar(key) { UiState.activeScreen = root.screen; UiState.togglePanel(key) }

    readonly property var battery: UPower.displayDevice
    readonly property bool charging: root.battery
        && (root.battery.state === UPowerDeviceState.Charging
            || root.battery.state === UPowerDeviceState.PendingCharge)

    // What each module looks like and does. `symbol` is a Material name, `glyph` a
    // codepoint the services already speak (Net.glyph, Audio.glyph).
    // A bar pill's second face (the SSID, the device, the percentage) is shown unless it
    // was collapsed with right-click AND remembered (the bar's own rule: an unremembered
    // collapse is that pill's alone, and resets on reload).
    function detailOn(id) { return !(Config.modulePersist(id) && Config.moduleRightState(id)) }

    // ── The bar's face, turned (2026-11-08) ───────────────────────────────────
    // "Same face on both surfaces" (the user, after a module moved and looked like a
    // different thing): each case shows what the module's BAR pill shows — its symbol, its
    // word, its badge, its second face — in a cell. Keep these in step with Bar.qml's
    // pills and the widgets/ *Pill files; a symbol that differs here is a bug.
    readonly property var spec: {
        const w = Colors.of(QsWindow.window)
        switch (root.moduleId) {
        case "shapeToggle": return { symbol: Config.barShape ? "fullscreen_exit" : "fullscreen" }
        case "modeToggle":  return { symbol: "menu", active: Config.barAnchored }
        case "palette":     return { symbol: "palette",   active: UiState.isOpen("colorScheme") || root.sideOpen("colorScheme") }
        case "wallpaper":   return { symbol: "format_paint", active: UiState.isOpen("wallpaper") }
        case "volume":      return { glyph: Audio.glyph(Audio.volume, Audio.muted),
                                     caption: Audio.muted ? "mut" : Math.round(Audio.volume * 100) + "",
                                     tint: Audio.muted ? w.danger : undefined,
                                     active: root.sideOpen("equalizer"), wheel: true }
        case "keyboard":    return { label: Keyboard.layout }
        case "update":      return { symbol: "terminal",
                                     badge: Updates.total + (ShellUpdate.available ? 1 : 0),
                                     badgeTint: Updates.hasError ? w.warning : w.primary,
                                     active: UiState.updateOpen }
        case "reload":      return { symbol: "refresh" }
        case "wifi":        return { glyph: Net.glyph(), active: root.sideOpen("wifi"),
                                     caption: !root.detailOn("wifi") ? ""
                                            : Net.wiredConnected ? "Ethernet" : Net.ssid !== "" ? Net.ssid : "Wi-Fi" }
        case "bluetooth":   return { symbol: !Bt.powered ? "bluetooth_disabled"
                                           : Bt.connectedCount > 0 ? "bluetooth_connected" : "bluetooth",
                                     active: root.sideOpen("bluetooth"),
                                     caption: !root.detailOn("bluetooth") ? ""
                                            : !Bt.powered ? "Off"
                                            : Bt.connectedCount === 0 ? ""
                                            : Bt.connectedCount === 1 ? (Bt.primary?.name || Bt.primary?.address || "")
                                            : Bt.connectedCount + "" }
        case "battery":     return !(root.battery && root.battery.isPresent) ? { symbol: "power" }
                                 : { symbol: root.charging ? "battery_charging_full" : "battery_full",
                                     caption: root.detailOn("battery") ? Math.round(root.battery.percentage * 100) + "%" : "" }
        case "overview":    return { symbol: "menu", active: UiState.overviewOpen }
        case "settings":    return { symbol: "settings" }
        case "privacy":     return { symbol: "mic", active: Audio.recordingApps.length > 0,
                                     tint: Audio.recordingApps.length > 0 ? w.danger : undefined }
        case "nightlight":  return { symbol: NightLight.shouldBeOn ? "bedtime" : "brightness_4",
                                     active: NightLight.shouldBeOn }
        case "idle":        return { symbol: Idle.inhibited ? "coffee" : "no_drinks", active: Idle.inhibited,
                                     tint: Idle.heldExternally && !Idle.manual ? w.info : undefined }
        case "gamemode":    return { symbol: Gamemode.active ? "sports_esports" : "videogame_asset_off",
                                     active: Gamemode.active || root.sideOpen("gaming") }
        default:            return { symbol: "help" }
        }
    }

    function click() {
        switch (root.moduleId) {
        case "shapeToggle": Config.toggleShape(); break
        case "modeToggle":  Config.cycleBarLayout(); break
        case "palette":     root.toggleSide("colorScheme"); break
        case "wallpaper":   root.toggleBar("wallpaper"); break
        case "volume":      root.toggleSide("equalizer"); break
        case "keyboard":    Keyboard.next(); break
        case "update":
            UiState.activeScreen       = root.screen
            UiState.pendingUpdateCount = Updates.total
            UiState.updateRequestId++
            break
        // The bar's ReloadPill guard: never restart the shell under a live update.
        case "reload":      if (!Updates.runBusy) Quickshell.reload(false); break
        case "wifi":        root.toggleSide("wifi"); break
        case "bluetooth":   root.toggleSide("bluetooth"); break
        case "battery":     UiState.openSettingsTo("BatteryPage.qml"); break
        case "overview":    UiState.toggleOverview(); break
        case "settings":    UiState.toggleSettingsWindow(); break
        case "privacy":     UiState.openSettingsTo("SoundPage.qml"); break
        case "nightlight":  NightLight.toggle(); break
        case "idle":        Idle.toggleManual(); break
        case "gamemode":    root.toggleSide("gaming"); break
        }
    }
    function middle() {
        switch (root.moduleId) {
        case "volume":   Audio.toggleMute(); break
        case "gamemode": Gamemode.toggle(); break
        }
    }

    // Hidden, a cell still holds its slot in the rail (a blank pill), so only the night
    // light hides, as its pill does; a battery that isn't there reads as mains power.
    visible: root.moduleId !== "nightlight" || NightLight.available
    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    SideCell {
        anchors.fill: parent
        symbol:  root.spec.symbol ?? ""
        glyph:   root.spec.glyph ?? ""
        caption: root.spec.caption ?? ""
        label:   root.spec.label ?? ""
        badge:   root.spec.badge ?? 0
        badgeTint: root.spec.badgeTint ?? Colors.of(QsWindow.window).primary
        active:  root.spec.active ?? false
        wheel:   root.spec.wheel ?? false
        tint:    root.spec.tint ?? Colors.of(QsWindow.window).stateIdleFg
        moduleId: root.moduleId
        onScrolled: function (d) { if (root.moduleId === "volume") Audio.stepVolume(d) }
        onClicked:       root.click()
        onMiddleClicked: root.middle()
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }
}
