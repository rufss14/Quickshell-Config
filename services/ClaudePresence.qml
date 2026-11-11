pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── ClaudePresence ────────────────────────────────────────────────────────────
// Announces the Claude Code session you're sitting in as Discord Rich Presence.
//
// ── Where the work happens ────────────────────────────────────────────────────
// Not here. Discord's RPC is a BINARY protocol — little-endian u32 opcode, u32 length,
// JSON body — and Quickshell's Socket is line oriented, so QML cannot speak it. Same
// split as Discord/discord-rpc.py and Lyrics/lyrics.py: scripts/claude-presence.py does
// the framing, the session watching, the rate limiting and the reconnects, and talks
// JSON lines. This file is its QML face.
//
// ── Why it is NOT part of services/Discord.qml ────────────────────────────────
// The bold first line of a rich presence card is the Discord APPLICATION'S NAME, not
// anything the payload can set. Measured against the voice app:
//
//     {"cmd":"SET_ACTIVITY","data":{…,"name":"Quicktest",
//      "application_id":"1531634092607668244"},"evt":null}
//
// Sharing that connection would title every Claude session "Quicktest". A second
// application id means a second connection, which means a second helper — the two have
// nothing in common but the socket path.
//
// ── Setup ─────────────────────────────────────────────────────────────────────
// Needs `presenceClientId` in ~/.local/state/quicktest/secrets/discord-rpc.json, from an app you own
// named "Claude Code", plus an art asset keyed `claude`. A CLIENT ID ONLY: unlike the
// voice panel there is no secret, no OAuth and no token on disk, because SET_ACTIVITY
// turns out not to need authenticating despite the docs saying every RPC command does.
// `blocker()` reports what's missing, same contract as Discord.pressBlocker() and
// WallpaperEngine.blocker() — a control that can't work is disabled with a reason
// rather than failing on click.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── State, as published by the helper ─────────────────────────────────────
    // Not `readonly`: the parser below assigns them. Read-only from outside.
    property bool   connected: false     // handshake done, Discord is listening
    property int    sessionCount: 0      // live interactive sessions, not just the shown one
    property var    session: null        // { name, title, cwd, status, version, startedAt }
    property string workspace: ""        // Hyprland workspace name, "" when unplaceable
    property string model: ""            // "Opus 5", "" before the first assistant turn
    property int    context: 0           // tokens currently in the window

    // What the card currently reads, straight from the helper rather than rebuilt here.
    // Two implementations of the same string is how the settings preview and the actual
    // presence end up disagreeing.
    property string details: ""
    property string state:   ""

    // "" | "no-client-id" | "no-discord" | "unauthorized"
    property string stage: ""
    property string lastError: ""

    readonly property bool enabled:    Config.claudePresenceEnabled
    readonly property bool needsSetup: root.stage === "no-client-id"

    // Whether a session is being shown right now — the honest answer to "is this
    // working", which is neither `connected` nor `enabled` alone.
    readonly property bool showing: root.connected && root.session !== null

    // ── The blocker contract ──────────────────────────────────────────────────
    // "" means the feature can work. Anything else is a sentence the page shows in
    // place of enabled controls. Deliberately not a boolean: "it's off" and "you never
    // made the Discord app" want different words, and a toggle that silently does
    // nothing is the failure mode this exists to prevent.
    function blocker() {
        if (root.stage === "no-client-id")
            return "No presence app configured. Create an application named "
                 + "\"Claude Code\" at discord.com/developers, then add its ID to "
                 + "discord-rpc.json as \"presenceClientId\", or into the keyring with "
                 + "echo '{\"presenceClientId\":\"ID\"}' | python3 scripts/discord-credentials.py"
        if (root.stage === "unauthorized")
            return "Discord rejected the activity as unauthenticated (4006). This "
                 + "worked without OAuth when it was built — the API may have changed."
        return ""
    }

    // What to say when there is nothing wrong but also nothing showing.
    readonly property string statusText: {
        if (!root.enabled)              return "Off"
        if (root.stage === "no-client-id") return "Needs setup"
        if (!root.connected)            return "Waiting for Discord"
        if (!root.session)              return "No session running"
        if (root.sessionCount > 1)
            return "Showing 1 of " + root.sessionCount + " sessions"
        return "Showing " + (root.details || "your session")
    }

    // ── Commands ──────────────────────────────────────────────────────────────
    // After editing discord-rpc.json by hand. The helper re-reads the file rather than
    // being restarted, so a live presence isn't cleared just to pick up an id.
    function reloadClientId() { root._send({ c: "reloadClientId" }) }
    function refresh()        { root._send({ c: "refresh" }) }

    // ══ The daemon is NOT a child of this shell ═══════════════════════════════
    // As a plain `Process { running: enabled }`, every reload would drop the presence
    // off the profile until the shell came back — made worse by Discord's
    // rate limit, which meant the reconnect could not immediately re-publish. The
    // presence describes a TERMINAL, which is still sitting there while the bar is
    // being rebuilt; tying its lifetime to the shell's was simply wrong.
    //
    // So it is `setsid`-detached and reparented to init, exactly like update-run.sh.
    // That costs the two things a child process gave for free, and each is replaced by
    // a FILE — because a pipe has exactly one reader and a file has none:
    //
    //   stdout → state.json     written atomically by the daemon, watched here.
    //   stdin  → options.json   written here, polled by the daemon.
    //
    // Neither end cares whether the other exists, which is the whole point: this shell
    // can die and come back and the daemon never notices.

    // XDG_CACHE_HOME, not a hardcoded ~/.cache — this config is published and installs
    // on machines that set it. The `||` idiom because env() returns a QVariant, so an
    // unset variable is `undefined` rather than "".
    readonly property string _cacheDir:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string _dir:        root._cacheDir + "/quickshell-claude-presence"
    readonly property string _statePath:  root._dir + "/state.json"
    readonly property string _runnerPath: Quickshell.shellPath("scripts/claude-presence-run.sh")

    // ── Starting is idempotent, so there is no "is it running" to race ────────
    // The runner takes an flock and exits 75 if it cannot. That means this can be
    // called unconditionally on every shell start: if a daemon survived the reload it
    // refuses, and if none did, one starts. No PID check, no separate reattach path,
    // and no window in which two daemons both think they own the profile.
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
        if (Config.claudePresenceEnabled) root._start()
    }

    Connections {
        target: Config
        function onClaudePresenceEnabledChanged() {
            if (Config.claudePresenceEnabled) root._start()
            else                              root._stop()
        }
    }

    // ── State in ──────────────────────────────────────────────────────────────
    // `onFileChanged: reload()` rather than trusting the watcher alone, for the same
    // reason Clipboard.qml does it: the daemon publishes by rename(2), which a watcher
    // can report as a delete rather than a modification.
    property FileView _state: FileView {
        path: root._statePath
        watchChanges: true
        onFileChanged: root._state.reload()
        onLoaded: root._ingest(root._state.text())
        // No state file yet is the normal state before the daemon's first write — it
        // means "starting", not "broken".
        onLoadFailed: {
            root.connected = false
            root.session = null
        }
    }

    // Re-reading discord-rpc.json is something the daemon does when it notices the
    // options file change, so both of these only have to touch that one file.
    function _send(obj) { root._pushOptions() }

    // The art asset key, which must match a name in the application's asset library
    // EXACTLY. Discord names an uploaded asset after its FILENAME, so this is
    // "claude-orange-on-black" rather than a tidier "claude" — renaming it in the
    // portal would work equally well, but the filename is what's actually there.
    //
    // Getting it wrong fails in the worst possible way: Discord accepts the frame,
    // answers success, and SILENTLY DROPS the large_image field from the activity.
    // The card renders perfectly with no picture and nothing anywhere says why. The
    // asset list is readable without auth if this ever needs checking again:
    //   curl -s https://discord.com/api/v9/oauth2/applications/<id>/assets
    //
    // It is a URL now, not a key: Discord animates a presence image only when it comes
    // from an external URL (an uploaded asset is always a still). The GIF is
    // assets/logos/claude-presence.gif (scripts/claude-presence-gif.py), served from the
    // published repo. "claude-orange-on-black" is still in the library, and is the
    // daemon's own default until this speaks. Bump `?v=` after regenerating the GIF —
    // Discord caches the image per URL.
    readonly property string assetKey: "https://raw.githubusercontent.com/rufss14/Quickshell-Config/main/assets/logos/claude-presence.gif?v=1"

    // The bold first line. Sent explicitly rather than left to default, because it
    // otherwise falls back to the Discord APPLICATION's name — and the portal refuses
    // to register an app called "Claude Code", so the app behind this is actually named
    // "Claw'd Code". Without this the card announces that misspelling. Verified to be
    // honoured by SET_ACTIVITY even though the docs only describe `name` for gateway
    // activities.
    readonly property string displayName: "Claude Code"

    // ── Options out ───────────────────────────────────────────────────────────
    // A JsonStore because it OWNS its file: nothing else writes options.json, which is
    // exactly the case JsonStore is built for — it deliberately doesn't watch the path,
    // so a save can't bounce back as a reload and then as another save.
    property JsonStore _options: JsonStore {
        path: root._dir + "/options.json"
        defaults: ({})
    }

    function _pushOptions() {
        if (!root._options.ready) return
        root._options.value = {
            useAiTitle:       Config.claudePresenceUseAiTitle,
            showWorkspace:    Config.claudePresenceShowWorkspace,
            showModel:        Config.claudePresenceShowModel,
            showTokens:       Config.claudePresenceShowTokens,
            showSessionCount: Config.claudePresenceShowSessionCount,
            largeImage:       root.assetKey,
            appName:          root.displayName
        }
    }

    // Pushed once the store is readable, not only when a toggle moves: the daemon comes
    // up on its own defaults, so a shell that boots with "use AI title" already set
    // would otherwise show the short name until that setting was next touched.
    Connections {
        target: root._options
        function onLoaded() { root._pushOptions() }
    }

    // ── Parsing ───────────────────────────────────────────────────────────────
    function _ingest(text) {
        // An empty read is not a fault: the watcher can fire between the daemon's
        // rename(2) and the content being visible, and FileView reports "" for a file
        // that exists but hasn't been filled yet. Warning about it would put a line in
        // the log on a perfectly ordinary startup.
        if (!text) return

        let msg
        try {
            msg = JSON.parse(text)
        } catch (e) {
            console.warn("ClaudePresence: unparseable state file:",
                         String(text).substring(0, 120))
            return
        }

        root.stage        = msg.stage ?? ""
        root.connected    = msg.connected ?? false
        root.sessionCount = msg.sessionCount ?? 0
        root.session      = msg.session ?? null
        root.workspace    = msg.workspace ?? ""
        root.model        = msg.model ?? ""
        root.context      = msg.context ?? 0
        root.details      = msg.details ?? ""
        root.state        = msg.state ?? ""
        root.lastError    = msg.error ?? ""
    }

    // ── Settings, forwarded ───────────────────────────────────────────────────
    // The helper owns the string building, so a changed option is a message rather than
    // a recomputation up here.
    Connections {
        target: Config
        function onClaudePresenceUseAiTitleChanged()       { root._pushOptions() }
        function onClaudePresenceShowWorkspaceChanged()    { root._pushOptions() }
        function onClaudePresenceShowModelChanged()        { root._pushOptions() }
        function onClaudePresenceShowTokensChanged()       { root._pushOptions() }
        function onClaudePresenceShowSessionCountChanged() { root._pushOptions() }
    }
}
