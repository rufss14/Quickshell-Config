import QtQuick
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
            case "clock":       return clockC
            case "notifications": return notificationsC
            case "overview":    return overviewC
            case "settings":    return settingsC
            default:            return null
        }
    }

    property Component _shapeToggleC: Component {
        id: shapeToggleC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("shapeToggle", Colors.primary)
            icon: Config.barShape ? Icons.asset("winoff") : Icons.asset("winon")
        }
    }
    property Component _modeToggleC: Component {
        id: modeToggleC
        IconButton {
            squareMode: Config.barShape
            active:     Config.barMerged
            accent:     Config.moduleAccent("modeToggle", Colors.primary)
            icon:       Icons.asset("barmode")
        }
    }
    property Component _paletteC: Component {
        id: paletteC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("palette", Colors.primary)
            icon:       Icons.asset("Palette")
        }
    }
    property Component _wallpaperC: Component {
        id: wallpaperC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("wallpaper", Colors.primary)
            icon:       Icons.asset("wallpaper")
        }
    }
    property Component _volumeC:     Component { id: volumeC;     VolumePill { accent: Config.moduleAccent("volume", Colors.focus) } }
    property Component _keyboardC:   Component { id: keyboardC;   KeyboardPill { accent: Config.moduleAccent("keyboard", Colors.primary) } }
    property Component _updateC:     Component { id: updateC;     UpdatePill { accent: Config.moduleAccent("update", Colors.primary) } }
    property Component _workspacesC: Component { id: workspacesC; WorkspacesPill { accent: Config.moduleAccent("workspaces", Colors.primary) } }
    property Component _reloadC:     Component { id: reloadC;     ReloadPill { accent: Config.moduleAccent("reload", Colors.primary) } }
    property Component _trayC:       Component { id: trayC;       TrayPill { accent: Config.moduleAccent("tray", Colors.primary) } }
    property Component _visualizerC: Component { id: visualizerC; VisualizerPill { accent: Config.moduleAccent("visualizer", Colors.focus) } }
    property Component _wifiC:       Component { id: wifiC;       WifiPill { accent: Config.moduleAccent("wifi", Colors.focus) } }
    property Component _clockC:      Component { id: clockC;      ClockPill { accent: Config.moduleAccent("clock", Colors.primary) } }

    property Component _notificationsC: Component {
        id: notificationsC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("notifications", Colors.primary)
            glyph:      Notifications.dnd ? "󰂛" : "󰂚"
            iconColor:  Notifications.dnd ? Colors.warning
                      : Notifications.count > 0 ? Colors.info : Colors.stateIdleFg
        }
    }
    property Component _overviewC: Component {
        id: overviewC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("overview", Colors.primary)
            glyph:      "󰕴"
        }
    }
    property Component _settingsC: Component {
        id: settingsC
        IconButton {
            squareMode: Config.barShape
            accent:     Config.moduleAccent("settings", Colors.primary)
            icon:       Icons.asset("settings")
        }
    }
}
