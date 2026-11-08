import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../../state"

// ── SideModulePill ────────────────────────────────────────────────────────────
// The sidebar's modules as top-bar pills, so a module can live on either surface
// (config/modules.js gives each a `bar` form pointing here). One file keyed by
// `moduleId`: the cell's glyph and its click, calling the same services. A module
// with a self-contained panel opens it in the BAR's dock (BarPanelDock registers
// them); voice's panel follows the call people and stays a sidebar thing, so its
// pill is the mute switch, as the cell's own mic button is.
//
//   click     the cell's click       middle   the cell's middle-click
//   right     Settings › Sidebar
//
// The dock itself has no pill: it is the sidebar.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    property var screen: null

    function toggleBar(key) { UiState.activeScreen = root.screen; UiState.togglePanel(key) }

    readonly property bool micMuted: Discord.inCall ? Discord.mute : (Audio.source?.audio?.muted ?? false)

    glyph: {
        switch (root.moduleId) {
        case "stats":      return "\u{F0EE0}"                                // 󰻠 cpu
        case "clipboard":  return "\u{F014D}"                                // 󰅍 clipboard
        case "timer":      return Timers.mode === "alarm" ? "\u{F0020}" : "\u{F051B}"
        case "claude":     return "\u{F06C4}"
        case "screentime": return "\u{F051F}"
        case "tasks":      return "\u{F0139}"                                // 󰄹 checklist
        case "inactivity": return "\u{F03E5}"                               // 󰏥 pause-circle
        case "clips":      return Clips.recording ? "\u{F04DB}" : "\u{F01A4}"   // 󰓛 stop / 󰆤 crosshairs
        case "colour":     return "\u{F020A}"                                // 󰈊 eyedropper
        case "lens":       return "\u{F113D}"
        case "power":      return "\u{F0425}"                                // 󰐥 power
        case "tools":      return "\u{F003B}"                                // 󰀻 apps
        case "voice":      return root.micMuted ? "\u{F036D}" : "\u{F036C}"  // 󰍭 / 󰍬 mic
        default:           return ""
        }
    }
    active: {
        switch (root.moduleId) {
        case "stats": case "clipboard": case "timer": case "claude": case "screentime": case "clips": case "inactivity": case "tasks":
            return UiState.isOpen(root.moduleId)
        case "power": return UiState.powerMenuOpen
        case "tools": return UiState.launcherOpen
        default:      return false
        }
    }
    iconColor: (root.moduleId === "clips" && Clips.recording) || (root.moduleId === "voice" && root.micMuted)
               ? Colors.of(QsWindow.window).danger
             : root.moduleId === "claude" && ClaudeSessions.needsYou.length > 0
               ? root.accent
             : root.active ? root.accent : Colors.of(QsWindow.window).stateIdleFg

    onClicked: {
        switch (root.moduleId) {
        case "stats": case "clipboard": case "timer": case "claude": case "screentime": case "clips": case "inactivity": case "tasks":
            root.toggleBar(root.moduleId); break
        case "colour": ColorPicker.pick(); break
        case "lens":   Lens.start("text"); break
        case "power":  UiState.powerMenuOpen = !UiState.powerMenuOpen; break
        case "tools":
            UiState.overviewOpen = false
            UiState.activeScreen = root.screen
            UiState.launcherOpen = !UiState.launcherOpen
            break
        case "voice":  Discord.inCall ? Discord.toggleMute() : Audio.toggleMicMute(); break
        }
    }
    onMiddleClicked: {
        switch (root.moduleId) {
        case "stats":  SysStats.openMonitor(); break
        case "clips":  Clips.saveClip(0); break
        case "lens":   Lens.start("translate"); break
        case "power":  Session.lock(); break
        case "tools":  UiState.toggleCheatsheet(); break
        case "voice":  if (Discord.inCall) Discord.toggleDeaf(); break
        case "claude": {
            const s = ClaudeSessions.needsYou[0] ?? ClaudeSessions.sessions[0]
            if (s) ClaudeSessions.focus(s.pid)
            break
        }
        }
    }
    onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
}
