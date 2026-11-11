import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../bar/widgets"

// ── PreviewModules ────────────────────────────────────────────────────────────
// The bar's modules, built for looking at rather than using: the real widgets, with
// none of the wiring that makes them do anything.
//
// ── Why the real widgets ──────────────────────────────────────────────────────
// The settings page used to label its chips "Bar mode", "Wi-Fi", "Visualizer" — which
// tells you the name of a thing you have to go and look at the bar to recognise. These
// are the actual widgets, so a chip IS the pill it stands for, and the bar preview is
// the bar. It also can't drift: change ClockPill and both update, because there's only
// one ClockPill.
//
// ── What "inert" means here ───────────────────────────────────────────────────
// Nothing is hooked to UiState and nothing takes a screen. The CALLER wraps these in
// an `enabled: false` Item, which is what actually stops the clicks — Item.enabled
// propagates down and disables every MouseArea inside. That's why there are no
// `interactive: false` lines below: one wrapper does the whole job, and a widget that
// half-disables itself is worse than one that doesn't.
//
// Two of these are alive on purpose, and it's the right call:
//   · WorkspacesPill has no monitor, so it renders workspace 1 focused. The dots are
//     the shape you're arranging; which one is lit is not.
//   · VisualizerPill still acquires Cava while it's on screen, so the preview's
//     spectrum genuinely moves. That means opening this page starts cava even when the
//     visualizer isn't on your bar. It's refcounted and released when the page closes,
//     and a frozen visualizer would be a worse lie than a brief process.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    function componentFor(id) {
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
            case "bluetooth":   return bluetoothC
            case "battery":     return batteryC
            case "idle":        return idleC
            case "gamemode":    return gamemodeC
            case "clock":       return clockC
            case "notifications": return notificationsC
            case "overview":    return overviewC
            case "settings":    return settingsC
            case "privacy":     return privacyC
            case "nightlight":  return nightLightC
            case "brightness":  return brightnessC
            case "window":      return windowC
            case "layout":      return layoutC
            case "locks":       return locksC
            case "stats":       return side_statsC
            case "clipboard":   return side_clipboardC
            case "timer":       return side_timerC
            case "claude":      return side_claudeC
            case "screentime":  return side_screentimeC
            case "inactivity":  return side_inactivityC
            case "tasks":       return side_tasksC
            case "clips":       return side_clipsC
            case "colour":      return side_colourC
            case "lens":        return side_lensC
            case "power":       return side_powerC
            case "tools":       return side_toolsC
            case "voice":       return side_voiceC
            case "nowplaying":  return nowplayingC
            case "dock":        return dockC
            default:            return null
        }
    }

    property Component _shapeToggleC: Component {
        id: shapeToggleC
        BarIconPill {
            moduleId: "shapeToggle"
            icon:     Config.barShape ? Icons.asset("winoff") : Icons.asset("winon")
        }
    }
    property Component _modeToggleC: Component {
        id: modeToggleC
        BarIconPill {
            moduleId: "modeToggle"
            active:   Config.barAnchored
            icon:     Icons.asset("barmode")
        }
    }
    property Component _paletteC: Component {
        id: paletteC
        BarIconPill {
            moduleId: "palette"
            icon:     Icons.asset("Palette")
        }
    }
    property Component _wallpaperC: Component {
        id: wallpaperC
        BarIconPill {
            moduleId: "wallpaper"
            icon:     Icons.asset("wallpaper")
        }
    }
    property Component _volumeC:     Component { id: volumeC;     VolumePill { accent: Config.moduleAccent("volume", Colors.of(QsWindow.window).primary) } }
    property Component _keyboardC:   Component { id: keyboardC;   KeyboardPill {} }
    property Component _updateC:     Component { id: updateC;     UpdatePill { accent: Config.moduleAccent("update", Colors.of(QsWindow.window).primary) } }
    property Component _workspacesC: Component { id: workspacesC; WorkspacesPill { accent: Config.moduleAccent("workspaces", Colors.of(QsWindow.window).primary) } }
    property Component _reloadC:     Component { id: reloadC;     ReloadPill { accent: Config.moduleAccent("reload", Colors.of(QsWindow.window).primary) } }
    property Component _trayC:       Component { id: trayC;       TrayPill { accent: Config.moduleAccent("tray", Colors.of(QsWindow.window).primary) } }
    property Component _visualizerC: Component { id: visualizerC; VisualizerPill { accent: Config.moduleAccent("visualizer", Colors.of(QsWindow.window).primary) } }
    property Component _wifiC:       Component { id: wifiC;       WifiPill { accent: Config.moduleAccent("wifi", Colors.of(QsWindow.window).primary) } }
    property Component _batteryC:    Component { id: batteryC;    BatteryPill { accent: Config.moduleAccent("battery", Colors.of(QsWindow.window).primary) } }
    property Component _bluetoothC:  Component { id: bluetoothC;  BluetoothPill { accent: Config.moduleAccent("bluetooth", Colors.of(QsWindow.window).primary) } }
    property Component _clockC:      Component { id: clockC;      ClockPill { accent: Config.moduleAccent("clock", Colors.of(QsWindow.window).primary) } }
    property Component _privacyC:    Component { id: privacyC;    PrivacyPill {} }
    property Component _brightnessC: Component { id: brightnessC; BarIconPill { moduleId: "brightness"; symbol: "brightness_6" } }
    property Component _windowC:     Component { id: windowC;     WindowPill { monitorName: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "" } }
    property Component _layoutC:     Component { id: layoutC;     BarIconPill { moduleId: "layout"; symbol: HyprLayout.info.symbol } }
    // A picture of it, not LocksPill: that one installs a key hook into Hyprland while it
    // exists, and a settings preview must not.
    // The sidebar's modules on the bar: the live pill itself (its clicks are off in a
    // preview — BarGroupRow disables the slot).
    property Component _side_statsC: Component { id: side_statsC; SideModulePill { moduleId: "stats" } }
    property Component _side_clipboardC: Component { id: side_clipboardC; SideModulePill { moduleId: "clipboard" } }
    property Component _side_timerC: Component { id: side_timerC; SideModulePill { moduleId: "timer" } }
    property Component _side_claudeC: Component { id: side_claudeC; SideModulePill { moduleId: "claude" } }
    property Component _side_screentimeC: Component { id: side_screentimeC; SideModulePill { moduleId: "screentime" } }
    property Component _side_inactivityC: Component { id: side_inactivityC; SideModulePill { moduleId: "inactivity" } }
    property Component _side_tasksC: Component { id: side_tasksC; SideModulePill { moduleId: "tasks" } }
    property Component _side_clipsC: Component { id: side_clipsC; SideModulePill { moduleId: "clips" } }
    property Component _side_colourC: Component { id: side_colourC; SideModulePill { moduleId: "colour" } }
    property Component _side_lensC: Component { id: side_lensC; SideModulePill { moduleId: "lens" } }
    property Component _side_powerC: Component { id: side_powerC; SideModulePill { moduleId: "power" } }
    property Component _side_toolsC: Component { id: side_toolsC; SideModulePill { moduleId: "tools" } }
    property Component _side_voiceC: Component { id: side_voiceC; SideModulePill { moduleId: "voice" } }
    property Component _nowplayingC: Component { id: nowplayingC; NowPlayingPill {} }
    property Component _dockC: Component { id: dockC; DockPill {} }
    property Component _locksC:      Component { id: locksC;      BarIconPill { moduleId: "locks"; label: "CAPS"; active: true } }

    // Mirrors Bar.qml's nightLightC minus the click wiring, same as every other
    // preview here — live state (visible/active/iconColor), no onClicked.
    property Component _nightLightC: Component {
        id: nightLightC
        BarIconPill {
            id: nightPill
            moduleId:   "nightlight"
            visible:    NightLight.available
            active:     NightLight.shouldBeOn
            symbol:     NightLight.shouldBeOn ? "bedtime" : "brightness_4"
            symbolFill: NightLight.shouldBeOn ? 1 : 0
            iconColor:  NightLight.shouldBeOn ? nightPill.accent : Colors.of(QsWindow.window).stateIdleFg
        }
    }

    // Live, like the visualizer below it: this is a real toggle reading real state, so
    // the preview shows what the pill is doing right now rather than a posed "off".
    property Component _idleC: Component {
        id: idleC
        BarIconPill {
            id: idlePill
            moduleId:   "idle"
            active:     Idle.inhibited
            symbol:     Idle.inhibited ? "coffee" : "no_drinks"
            symbolFill: Idle.inhibited ? 1 : 0
            iconColor:  Idle.manual         ? idlePill.accent
                      : Idle.heldExternally ? Colors.of(QsWindow.window).info
                      :                       Colors.of(QsWindow.window).stateIdleFg
        }
    }

    // Live like the idle preview beside it — and inert only in the sense every preview
    // is: the caller's `enabled: false` wrapper is what stops a click from actually
    // putting the machine into gamemode from the settings page.
    property Component _gamemodeC: Component {
        id: gamemodeC
        BarIconPill {
            id: gamePill
            moduleId:   "gamemode"
            active:     Gamemode.active
            symbol:     Gamemode.active ? "sports_esports" : "videogame_asset_off"
            symbolFill: Gamemode.active ? 1 : 0
            iconColor:  Gamemode.active ? gamePill.accent : Colors.of(QsWindow.window).stateIdleFg
        }
    }

    property Component _notificationsC: Component {
        id: notificationsC
        BarIconPill {
            moduleId: "notifications"
            // Mirrors Bar.qml's real notificationsC: one content type (icon) for
            // all four states, so switching between them never resizes the pill.
            icon: Notifications.quiet       ? Icons.asset("dnd")
                : Notifications.hasCritical ? Icons.asset("bellactive")
                : Notifications.count > 0   ? Icons.asset("bellunread")
                :                             Icons.asset("bell")
            iconColor:  Notifications.quiet       ? Colors.of(QsWindow.window).warning
                      : Notifications.hasCritical ? Colors.of(QsWindow.window).danger
                      : Notifications.count > 0   ? Colors.of(QsWindow.window).info
                      :                             Colors.of(QsWindow.window).stateIdleFg
        }
    }
    property Component _overviewC: Component {
        id: overviewC
        BarIconPill {
            moduleId: "overview"
            icon:     Icons.asset("overview")
        }
    }
    property Component _settingsC: Component {
        id: settingsC
        BarIconPill {
            moduleId: "settings"
            icon:     Icons.asset("settings")
        }
    }
}
