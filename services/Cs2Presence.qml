pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Cs2Presence ───────────────────────────────────────────────────────────────
// Announces the Counter-Strike 2 match you're in as Discord Rich Presence.
//
// ── Why this exists ───────────────────────────────────────────────────────────
// Discord's own game detection can't show CS2 on Linux: its detectables database
// lists only a Windows `cs2.exe`, so a native `cs2` process matches nothing and shows
// as the bare word "cs2" with no art. CS2 ships no Discord presence of its own. The
// helper, scripts/cs2-presence.py, fills both gaps — it reads the game's Game State
// Integration feed and publishes a proper card. This file is its QML face, and it is
// deliberately the same shape as ClaudePresence.qml down to the detached-daemon
// plumbing; read that file's header for the reasoning behind all of it.
//
// ── No application to register ────────────────────────────────────────────────
// Unlike the Claude Code card, this one needs no Discord app set up: the helper
// handshakes as Valve's own registered "Counter-Strike 2" application, so the card's
// title and icon are correct out of the box. What it DOES need is the GSI feed, which
// `scripts/install-cs2-gsi.sh` switches on — `blocker()` says so when it's missing.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── State, as published by the helper ────────────────────────────────────
    property bool   connected: false     // handshake done, Discord is listening
    property bool   inMatch:   false     // in a live match (menu is a separate flag)
    property bool   inMenu:    false     // online, between matches
    property string map:   ""            // "Dust II", pretty
    property string mode:  ""            // "Competitive", pretty
    property int    ct:    -1            // round score, -1 when unknown
    property int    tScore: -1
    property int    kills:  -1           // your match stats, -1 when unknown
    property int    deaths: -1

    // What the card actually reads, straight from the helper — not rebuilt here, so
    // the settings preview and the real presence can't disagree.
    property string details: ""
    property string state:   ""

    // "" | "no-discord" | "unauthorized" | "port-unavailable"
    property string stage: ""
    property string lastError: ""
    property int    port: 0

    readonly property bool enabled: Config.cs2PresenceEnabled

    // The installer writes cs2-gsi.json; its absence is the one "you haven't done the
    // setup" signal the helper can't give us (it can't tell "CS2 is closed" from
    // "no cfg"). Checked here instead.
    property bool gsiConfigured: false
    readonly property bool needsSetup: root.stage === "port-unavailable"
                                       || (root.enabled && !root.gsiConfigured)

    // The honest answer to "is this working": a card is on the profile right now.
    readonly property bool showing: root.connected && (root.inMatch || root.inMenu)

    // ── The blocker contract ────────────────────────────────────────────────
    // "" means it can work. Anything else is a sentence the page shows in place of
    // enabled controls — same contract as ClaudePresence.blocker().
    function blocker() {
        if (root.stage === "unauthorized")
            return "Discord rejected the activity as unauthenticated (4006). This "
                 + "worked without OAuth when it was built — the API may have changed."
        if (root.stage === "port-unavailable")
            return "Port " + (root.port || 3000) + " is already in use. Free it, or "
                 + "reinstall the feed on another port: "
                 + "scripts/install-cs2-gsi.sh --port <n>."
        if (root.enabled && !root.gsiConfigured)
            return "CS2's match feed isn't switched on yet. Run "
                 + "scripts/install-cs2-gsi.sh, then restart Counter-Strike 2."
        return ""
    }

    readonly property string statusText: {
        if (!root.enabled)                return "Off"
        if (root.blocker() !== "")        return "Needs setup"
        if (!root.connected)              return "Waiting for Discord"
        if (root.inMatch)                 return "Showing " + (root.details || "your match")
        if (root.inMenu)                  return "In the main menu"
        return "Waiting for Counter-Strike 2"
    }

    // ── Commands ────────────────────────────────────────────────────────────
    function reloadClientId() { root._pushOptions() }
    function refresh()        { root._pushOptions() }

    // ══ The daemon is NOT a child of this shell ═════════════════════════════
    // setsid-detached and reparented to init, exactly like ClaudePresence's and for
    // the same reason: a shell reload must not drop the presence off your profile, and
    // Discord's rate limit means a reconnect can't re-publish immediately. stdout is a
    // state FILE watched here; stdin is an options FILE polled by the daemon.
    readonly property string _cacheDir:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string _dir:        root._cacheDir + "/quickshell-cs2-presence"
    readonly property string _statePath:  root._dir + "/state.json"
    readonly property string _runnerPath: Quickshell.shellPath("scripts/cs2-presence-run.sh")

    // Outside the repo since 2026-11-08 (scripts/qspaths.py). The old place is still
    // honoured until cs2-presence.py's first run moves the file.
    readonly property string _gsiConfigPath:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/quicktest/secrets/cs2-gsi.json"
    readonly property string _gsiLegacyPath:
        (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
        + "/quicktest/cs2-gsi.json"

    function _start() {
        launchProc.command = ["bash", "-c",
            'setsid bash "$0" run "$1" < /dev/null > /dev/null 2>&1 & disown; exit 0',
            root._runnerPath, root._dir]
        launchProc.running = false
        launchProc.running = true
    }

    function _stop() {
        stopProc.command = ["bash", root._runnerPath, "stop", root._dir]
        stopProc.running = false
        stopProc.running = true
    }

    property Process launchProc: Process { running: false }
    property Process stopProc:   Process { running: false }

    Component.onCompleted: {
        if (Config.cs2PresenceEnabled) root._start()
    }

    Connections {
        target: Config
        function onCs2PresenceEnabledChanged() {
            if (Config.cs2PresenceEnabled) root._start()
            else                           root._stop()
        }
    }

    // ── State in ───────────────────────────────────────────────────────────
    // `_everLoaded` guards the failure path: once the daemon has written a good state
    // once, a failed read is the rename(2) publish racing the watcher, NOT the daemon
    // going away — blanking the card on it is the flicker, not the fix. A genuine
    // "daemon stopped" arrives as its next write saying connected:false, or as the
    // disable path. Before the first successful read, a failure really does mean
    // "not started yet" and clearing is right.
    property bool _everLoaded: false
    property FileView _state: FileView {
        path: root._statePath
        watchChanges: true
        onFileChanged: root._state.reload()
        onLoaded: {
            root._everLoaded = true
            root._ingest(root._state.text())
        }
        onLoadFailed: {
            if (root._everLoaded) return
            root.connected = false
            root.inMatch = false
            root.inMenu = false
        }
    }

    // Just an existence check — reloaded whenever it appears or disappears.
    property bool _gsiNew: false
    property bool _gsiOld: false
    property FileView _gsiConfig: FileView {
        printErrors: false   // absent is the normal case (no CS2, or not installed)
        path: root._gsiConfigPath
        watchChanges: true
        onFileChanged: root._gsiConfig.reload()
        onLoaded:     { root._gsiNew = true;  root.gsiConfigured = root._gsiNew || root._gsiOld }
        onLoadFailed: { root._gsiNew = false; root.gsiConfigured = root._gsiNew || root._gsiOld }
    }
    property FileView _gsiLegacy: FileView {
        printErrors: false   // absent is the normal case (no CS2, or not installed)
        path: root._gsiLegacyPath
        watchChanges: true
        onFileChanged: root._gsiLegacy.reload()
        onLoaded:     { root._gsiOld = true;  root.gsiConfigured = root._gsiNew || root._gsiOld }
        onLoadFailed: { root._gsiOld = false; root.gsiConfigured = root._gsiNew || root._gsiOld }
    }

    function _send(obj) { root._pushOptions() }

    // The bold first line and the icon come from Valve's registered CS2 app the helper
    // handshakes as, so there's no asset key to get right here. Left overridable only
    // for someone running their own app via `cs2PresenceClientId` in discord-rpc.json.
    readonly property string displayName: "Counter-Strike 2"

    property JsonStore _options: JsonStore {
        path: root._dir + "/options.json"
        defaults: ({})
    }

    function _pushOptions() {
        if (!root._options.ready) return
        root._options.value = {
            showScore: Config.cs2PresenceShowScore,
            showKd:    Config.cs2PresenceShowKd,
            showMode:  Config.cs2PresenceShowMode,
            appName:   root.displayName
        }
    }

    Connections {
        target: root._options
        function onLoaded() { root._pushOptions() }
    }

    // ── Parsing ────────────────────────────────────────────────────────────
    function _ingest(text) {
        if (!text) return
        let msg
        try {
            msg = JSON.parse(text)
        } catch (e) {
            console.warn("Cs2Presence: unparseable state file:",
                         String(text).substring(0, 120))
            return
        }
        root.stage     = msg.stage ?? ""
        root.connected = msg.connected ?? false
        root.inMatch   = msg.inMatch ?? false
        root.inMenu    = msg.inMenu ?? false
        root.map       = msg.map ?? ""
        root.mode      = msg.mode ?? ""
        root.ct        = (msg.ct ?? null) === null ? -1 : msg.ct
        root.tScore    = (msg.t ?? null) === null ? -1 : msg.t
        root.kills     = (msg.kills ?? null) === null ? -1 : msg.kills
        root.deaths    = (msg.deaths ?? null) === null ? -1 : msg.deaths
        root.details   = msg.details ?? ""
        root.state     = msg.state ?? ""
        root.port      = msg.port ?? 0
        root.lastError = msg.error ?? ""
    }

    // ── Settings, forwarded ────────────────────────────────────────────────
    Connections {
        target: Config
        function onCs2PresenceShowScoreChanged() { root._pushOptions() }
        function onCs2PresenceShowKdChanged()    { root._pushOptions() }
        function onCs2PresenceShowModeChanged()  { root._pushOptions() }
    }
}
