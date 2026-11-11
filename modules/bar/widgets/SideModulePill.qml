import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../../state"
import "../sidecells.js" as SideCells

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
// ── Same face on both surfaces ────────────────────────────────────────────────
// The pill draws the module's REAL sidebar cell (sidecells.js), laid along the bar
// (`vertical: false`) and scaled so its glyph is the bar's glyph size — the stats'
// level bars, the timer's ring, the tasks' ring, the clips' buffer, not a bare glyph
// that made a module look like another one when it moved (the user, 2026-11-08:
// "same face, turned"). The cell is inert (`enabled: false`); every click is this
// pill's, so it opens in the bar's dock, not beside a sidebar the module isn't on.
// Tools draws two cells: a click on the second half is the cheatsheet's. The glyph
// below only shows when the cell fails to load.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    property var screen: null

    function toggleBar(key) { UiState.activeScreen = root.screen; UiState.togglePanel(key) }

    readonly property bool micMuted: Discord.inCall ? Discord.mute : (Audio.source?.audio?.muted ?? false)

    // The cell drawn at the bar's glyph size: the sidebar draws its glyphs at
    // sidebarGlyphPx in a cell sidebarCellPad bigger a side.
    readonly property real faceScale: root.glyphSize / Math.max(1, Config.sidebarGlyphPx)
    readonly property bool faceReady: face.status === Loader.Ready && face.item !== null
    readonly property real faceW: root.faceReady ? face.item.implicitWidth : 0
    readonly property real faceH: root.faceReady ? face.item.implicitHeight : 0

    implicitWidth: root.faceReady
        ? Math.max(root.spacing >= 0 ? 0 : Tokens.pillIconWidth,
                   Math.ceil((root.faceW - Config.sidebarCellPad * 2) * root.faceScale) + root._hPad * 2)
        : Math.max(root.spacing >= 0 ? 0 : Tokens.pillIconWidth, root.contentExtent + root._hPad * 2)
    implicitHeight: Math.max(Tokens.pillHeight,
                             Math.ceil(root.faceH * root.faceScale),
                             root.contentExtent + Tokens.spacingSm * 2)

    // No size of its own (a Loader sized explicitly resizes its item); scaled about
    // its centre, which is the pill's.
    Loader {
        id: face
        anchors.centerIn: parent
        enabled: false
        scale: root.faceScale
        source: SideCells.file(root.moduleId) !== "" ? Qt.resolvedUrl("../" + SideCells.file(root.moduleId)) : ""
        onLoaded: {
            const m = face.item
            if (!m) return
            if (m.vertical !== undefined) m.vertical = false
            if (m.screen !== undefined) m.screen = Qt.binding(() => root.screen)
            if (m.moduleId !== undefined) m.moduleId = root.moduleId
        }
    }

    glyph: root.faceReady ? "" : root.fallbackGlyph
    readonly property string fallbackGlyph: {
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
        case "nowplaying": return UiState.isOpen("media")
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

    // Where the pointer is: tools' second cell (the right half) is the cheatsheet.
    HoverHandler { id: hoverAt }
    onClicked: {
        switch (root.moduleId) {
        case "stats": case "clipboard": case "timer": case "claude": case "screentime": case "clips": case "inactivity": case "tasks":
            root.toggleBar(root.moduleId); break
        case "nowplaying": root.toggleBar("media"); break
        case "colour": ColorPicker.pick(); break
        case "lens":   Lens.start("text"); break
        case "power":  UiState.powerMenuOpen = !UiState.powerMenuOpen; break
        case "tools":
            if (root.faceReady && hoverAt.point.position.x > root.width / 2) { UiState.toggleCheatsheet(); break }
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
        case "nowplaying": if (MusicPulse.player) MusicPulse.player.togglePlaying(); break
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
