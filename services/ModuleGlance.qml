pragma Singleton

import QtQuick
import Quickshell
import "../config"
import "../config/modules.js" as Catalogue

// ── ModuleGlance ──────────────────────────────────────────────────────────────
// What a module is doing right now, in a few words: "Timer" + "04:12 left", "Wi-Fi" + "Home · 72%".
// One wording for the two places that say it: the sidebar's hover chip (modules/panels/HoverCard) and a
// bar pill's tooltip (components/HelpTip, drawn by the bar window's TipBubble).
//
// Asked, never bound at rest: `value(id)` reads the module's own service, and reading a service is what
// starts it. A caller evaluates it while its chip or tip is on show and at no other time.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    function label(id) {
        const m = Catalogue.info(id)
        return m ? Translation.tr(m.label) : id
    }

    // "Name" or "Name · what it is doing", for a tooltip.
    function tip(id) {
        const v = root.value(id)
        return v !== "" ? root.label(id) + " · " + v : root.label(id)
    }

    function _n(n, one, many) { return n + " " + (n === 1 ? one : many) }

    function value(kind) {
        switch (kind) {
        case "claude": {
            const need = ClaudeSessions.needsYou.length, busy = ClaudeSessions.busyCount
            const all = ClaudeSessions.sessions.length
            return need > 0 ? root._n(need, "session needs you", "sessions need you")
                 : busy > 0 ? busy + " working" + (all > busy ? " · " + (all - busy) + " idle" : "")
                 : all > 0  ? root._n(all, "session", "sessions") + ", idle"
                 : "No sessions"
        }
        case "tasks":
            return Tasks.openCount > 0 ? Tasks.openCount + " open" + (Tasks.doneCount > 0 ? " · " + Tasks.doneCount + " done" : "")
                 : Tasks.doneCount > 0 ? "All done" : "Nothing to do"
        case "timer":
            if (Timers.ringing)  return "Alarm ringing"
            if (Timers.timerDone) return "Done"
            if (Timers.timerRunning || Timers.timerPaused)
                return (Timers.mode === "focus" ? Timers.pomoLabel + " · " : "")
                     + Timers.clockString(Timers.timerRemain) + (Timers.timerPaused ? " · paused" : " left")
            if (Timers.swRunning) return "Stopwatch · " + Timers.clockString(Math.floor(Timers.swElapsed / 1000))
            return "Nothing running"
        case "clips":
            if (!Clips.installed) return "Needs gpu-screen-recorder"
            if (Clips.recording)  return Clips.paused ? "Recording, paused" : "Recording"
            if (Clips.buffering)  return "Replay buffer · last " + Clips.bufferSeconds + "s"
            return "Replay buffer off"
        case "colour":
            return ColorPicker.picking ? "Picking…"
                 : ColorPicker.lastPicked !== "" ? "Last " + ColorPicker.lastPicked.toUpperCase()
                 : "Pick a colour off the screen"
        case "clipboard":
            return Clipboard.count > 0 ? root._n(Clipboard.count, "item", "items") : "Empty"
        case "stats":
            return SysStats.metrics.slice(0, 3).map(k => {
                const r = SysStats.readout(k)
                return r.label + " " + r.short + "%"
            }).join(" · ")
        case "inactivity":
            return Inactivity.summary
        case "voice":
            return Discord.inCall ? (Discord.channelName || "In a call") + " · " + Discord.users.length + " here"
                 : Audio.micMuted ? "Mic muted" : "Mic on"
        case "power":
            return "Middle-click locks"
        case "nowplaying": {
            const p = MusicPulse.player
            if (!p) return "Nothing playing"
            const what = (p.trackTitle || "") + (p.trackArtist ? " · " + p.trackArtist : "")
            return (MusicPulse.playing ? "" : "Paused · ") + what
        }
        // ── The bar's own modules ─────────────────────────────────────────────
        case "wifi":
            return Net.wiredConnected ? "Ethernet"
                 : Net.connected      ? Net.ssid + " · " + Net.strength + "%"
                 : !Net.wifiEnabled   ? "Off" : "Not connected"
        case "bluetooth":
            return !Bt.powered ? "Off"
                 : Bt.connectedCount > 0 ? root._n(Bt.connectedCount, "device", "devices") + " connected"
                 : "On, nothing connected"
        case "volume":
            return Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
        case "privacy":
            return Audio.micMuted ? "Muted" : "Live"
        case "notifications":
            return Notifications.dnd ? "Do Not Disturb"
                 : Notifications.count > 0 ? root._n(Notifications.count, "notification", "notifications")
                 : "All caught up"
        case "idle":
            return Idle.inhibited ? "Keeping the screen awake" : "Off"
        case "nightlight":
            return NightLight.statusText
        case "gamemode":
            return Gamemode.active ? (Gamemode.gameName !== "" ? "On · " + Gamemode.gameName : "On") : "Off"
        case "update":
            return Updates.checking ? "Checking…"
                 : Updates.total > 0 ? root._n(Updates.total, "update", "updates")
                 : "Up to date"
        case "screentime":
            return !Config.screenTime ? "Off" : ScreenTime.duration(ScreenTime.todayTotal) + " today"
        case "layout":
            return HyprLayout.info.label
        case "keyboard":
            return Keyboard.layout
        case "tools":
            return "Screenshot, record, pick a colour"
        }
        return ""
    }
}
