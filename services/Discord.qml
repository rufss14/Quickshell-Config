pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "."          // Hypr, for the window address the keystroke injection needs

// ── Discord ───────────────────────────────────────────────────────────────────
// The state of your Discord voice call, and the controls for it.
//
// ── Where the work happens ────────────────────────────────────────────────────
// Not here. Discord's RPC is a BINARY protocol over a unix socket — little-endian u32
// opcode, u32 length, JSON body — and Quickshell's `Socket` is line oriented, so QML
// cannot speak it. `scripts/discord-rpc.py` does the framing, the OAuth and the
// reconnects, and talks JSON lines over stdin/stdout. This file is the QML face of it:
// hand it a command, read back state. Same split as Lyrics/lyrics.py.
//
// ── What Discord actually exposes ─────────────────────────────────────────────
// Mute, deafen, input/output volume and devices, voice activity / push-to-talk, noise
// suppression / echo cancellation / automatic gain, per-user volume, mute and balance,
// leaving the call, the participant list, who's speaking, connection state and ping.
// All first-class, all real RPC.
//
// SCREEN SHARE AND CAMERA ARE NOT IN THE API. There is no RPC command for either — not
// gated behind a scope, simply absent. `pressInDiscord()` at the bottom drives those by
// focusing Discord and injecting a keystroke, which is a genuinely different and more
// fragile mechanism. It is deliberately quarantined down there, away from everything
// above it, and it is the only part of this file that can fail silently.
//
// ── Setup ─────────────────────────────────────────────────────────────────────
// Works with no setup: the helper signs in as Discord's own StreamKit app (see
// SHARED_CLIENT_ID in scripts/discord-rpc.py — undocumented, so it can break). An app
// of your own in ~/.local/state/quicktest/secrets/discord-rpc.json (`clientId` + `clientSecret`)
// always wins, and `"sharedApp": false` turns the fallback off. `authStage` reports
// "no-credentials" only in that last case, and the card renders it as a setup prompt
// rather than as a fault.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── State, as published by the helper ─────────────────────────────────────
    // Not `readonly`: the parser below assigns them. Treat them as read-only from
    // outside — the commands are the supported way to change anything.
    property bool   connected: false      // authenticated RPC session is live
    property bool   inCall:    false
    property var    channel:   null       // { id, name, guild, guildId }
    property bool   mute:      false
    property bool   deaf:      false
    // [{ id, isSelf, name, avatar, speaking, selfMute, selfDeaf, serverMute, serverDeaf,
    //    mute (muted BY YOU), volume (0–200, for you), pan (-1 left … 1 right, for
    //    you), bot }]
    property var    users:     []
    property int    inputVolume:  100     // 0-100
    property int    outputVolume: 100     // 0-200, as Discord allows
    // The rest of Discord's Voice & Video page that RPC reaches.
    property var    processing:    ({ noise: false, echo: false, agc: false })
    property string inputMode:     "VOICE_ACTIVITY"     // | "PUSH_TO_TALK"
    property string inputDevice:   ""
    property string outputDevice:  ""
    property var    inputDevices:  []     // [{ id, name }], as Discord lists them
    property var    outputDevices: []
    property int    ping:      0
    property string status:    "DISCONNECTED"

    // "" | "awaiting-consent" | "no-credentials"
    property string authStage: ""
    property string lastError: ""

    readonly property bool enabled:    Config.discordEnabled
    readonly property bool needsSetup: root.authStage === "no-credentials"

    // Discord is showing its consent dialog and waiting on a human. Worth surfacing for
    // the same reason `needsSetup` is: it's a state that can last minutes and produces
    // no call, so a card gated only on `inCall` would show nothing and look broken at
    // exactly the moment the user is being asked to do something.
    readonly property bool awaitingConsent: root.authStage === "awaiting-consent"

    // Any state the user has to act on before this can work.
    readonly property bool needsAttention: root.needsSetup || root.awaitingConsent

    // ── Commands ──────────────────────────────────────────────────────────────
    function toggleMute() { root._setMute(!root.mute) }
    function toggleDeaf() { root._setDeaf(!root.deaf) }

    function disconnect() { root._send({ c: "disconnect" }) }

    function setInputVolume(v) {
        root.inputVolume = Math.round(Math.max(0, Math.min(100, v)))
        root._send({ c: "inputVolume", v: root.inputVolume })
    }

    function setOutputVolume(v) {
        root.outputVolume = Math.round(Math.max(0, Math.min(200, v)))
        root._send({ c: "outputVolume", v: root.outputVolume })
    }

    // Someone else's volume (0–200), balance (-1 left … 1 right) and mute, for YOU only —
    // Discord's own per-person controls. Never on yourself: Discord has none for your own
    // account. A slider sends a value per frame; they're coalesced to one command per
    // `_userTimer` beat, the latest winning, so a drag isn't sixty RPC requests a second.
    function setUserVolume(id, v) { root._queueUser("userVolume", id, Math.round(Math.max(0, Math.min(200, v)))) }
    function setUserPan(id, b)    { root._queueUser("userPan", id, Math.max(-1, Math.min(1, b))) }
    function setUserMute(id, on) {
        if (!id) return
        root._send({ c: "userMute", id: id, v: !!on })
    }
    function userById(id) { return root.users.find(u => u.id === id) ?? null }

    property var _userPending: ({})
    function _queueUser(c, id, v) {
        if (!id) return
        root._userPending[c + "\u0001" + id] = { c: c, id: id, v: v }
        if (!root._userTimer.running) root._userTimer.start()
    }
    property Timer _userTimer: Timer {
        interval: 80
        onTriggered: {
            const pending = root._userPending
            root._userPending = {}
            for (const k in pending) root._send(pending[k])
        }
    }

    // Noise suppression / echo cancellation / automatic gain ("noise" | "echo" | "agc"),
    // voice activity vs push-to-talk, and the devices. Shown at once (`_hold` keeps a
    // snapshot from before the change from flicking it back); the helper refuses a key,
    // mode or device id Discord didn't offer.
    function setProcessing(key, on) {
        if (!(key in root.processing)) return
        const next = Object.assign({}, root.processing)
        next[key] = !!on
        root.processing = next
        root._hold("processing")
        root._send({ c: "processing", key: key, v: !!on })
    }
    function setInputMode(mode) {
        if (mode !== "VOICE_ACTIVITY" && mode !== "PUSH_TO_TALK") return
        root.inputMode = mode
        root._hold("inputMode")
        root._send({ c: "inputMode", v: mode })
    }
    function setInputDevice(id)  { root.inputDevice = id;  root._hold("inputDevice");  root._send({ c: "inputDevice",  v: id }) }
    function setOutputDevice(id) { root.outputDevice = id; root._hold("outputDevice"); root._send({ c: "outputDevice", v: id }) }

    // Field → until when (ms) an incoming snapshot may not overwrite it.
    property var _held: ({})
    function _hold(field) { root._held[field] = Date.now() + 1500 }
    function _mayTake(field) { return (root._held[field] ?? 0) < Date.now() }

    // Discord's window to the front (the panel's "open Discord"). Focus warps the
    // pointer (CLAUDE.md), which is what you want here: you're going there.
    function focusWindow() { if (root.windowAddress !== "") Hypr.focusWindow(root.windowAddress) }

    function refresh() { root._send({ c: "refresh" }) }

    // ══ OPTIMISTIC ECHO ═══════════════════════════════════════════════════════
    // A mute round-trips through Discord before VOICE_SETTINGS_UPDATE confirms it, so a
    // button bound straight to `mute` sits visibly dead for ~100ms after every click.
    // The local value flips immediately instead, and the event confirms it.
    //
    // Which creates the race this pending-pair exists for. A snapshot generated BEFORE
    // our command reached Discord is still in flight when we flip, and it says the OLD
    // value — so the button would flick back, then forward again a frame later. So
    // while a change is pending, incoming values for THAT field are ignored until one
    // agrees with what we asked for.
    //
    // The timer is the other half: if the command failed outright (Discord busy, scope
    // rejected), no snapshot will ever agree, and without a deadline the field would be
    // frozen at a lie for the rest of the session. On expiry we stop ignoring reality
    // and the next snapshot corrects the button.
    property int _pendingMute: -1      // -1 = nothing pending, else 0/1
    property int _pendingDeaf: -1

    function _setMute(v) {
        root.mute = v
        root._pendingMute = v ? 1 : 0
        root._pendingTimer.restart()
        root._send({ c: "mute", v: v })
    }

    function _setDeaf(v) {
        root.deaf = v
        root._pendingDeaf = v ? 1 : 0
        root._pendingTimer.restart()
        root._send({ c: "deaf", v: v })
    }

    property Timer _pendingTimer: Timer {
        interval: 1500
        repeat: false
        onTriggered: {
            root._pendingMute = -1
            root._pendingDeaf = -1
        }
    }

    // ── The helper ────────────────────────────────────────────────────────────
    property Process _proc: Process {
        running: Config.discordEnabled
        command: ["python3", Quickshell.shellPath("scripts/discord-rpc.py")]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: function(line) { root._ingest(line) }
        }

        // The helper logs diagnostics here and never secrets — see its header. Kept as
        // console output rather than surfaced in the UI: it's for reading a log with,
        // and `lastError` already carries anything the user can act on.
        stderr: SplitParser {
            onRead: function(line) { console.log("Discord:", line) }
        }

        onExited: function(code) {
            // Only reachable by the helper dying unexpectedly — it has its own
            // reconnect loop, so a shut Discord never gets here.
            root.connected = false
            root.inCall = false
            root.users = []
            root.channel = null
            if (code !== 0) root.lastError = "helper exited (" + code + ")"
        }
    }

    function _send(obj) {
        if (!root._proc.running) return
        root._proc.write(JSON.stringify(obj) + "\n")
    }

    // ── Parsing ───────────────────────────────────────────────────────────────
    function _ingest(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("Discord: unparseable line from helper:", line.substring(0, 120))
            return
        }

        if (msg.t === "state")       root._applyState(msg)
        else if (msg.t === "auth")   root.authStage = msg.stage ?? ""
        else if (msg.t === "error")  root.lastError = msg.msg ?? ""
        else if (msg.t === "config") {
            root._keys = msg.keys ?? ({})
            // Guarded: a helper that predates this field leaves the QML-side default in
            // place rather than blanking the list and disabling injection outright.
            if (Array.isArray(msg.windowClasses) && msg.windowClasses.length > 0)
                root._windowClasses = msg.windowClasses
        }
    }

    function _applyState(s) {
        root.connected = !!s.connected
        root.inCall    = !!s.inCall
        root.channel   = s.channel ?? null
        root.ping      = s.ping ?? 0
        root.status    = s.status ?? "DISCONNECTED"
        root.inputVolume  = s.inputVolume  ?? root.inputVolume
        root.outputVolume = s.outputVolume ?? root.outputVolume
        if (s.processing   && root._mayTake("processing"))   root.processing   = s.processing
        if (s.inputMode    && root._mayTake("inputMode"))    root.inputMode    = s.inputMode
        if (s.inputDevice  !== undefined && root._mayTake("inputDevice"))  root.inputDevice  = s.inputDevice
        if (s.outputDevice !== undefined && root._mayTake("outputDevice")) root.outputDevice = s.outputDevice
        if (Array.isArray(s.inputDevices)  && JSON.stringify(s.inputDevices)  !== JSON.stringify(root.inputDevices))
            root.inputDevices = s.inputDevices
        if (Array.isArray(s.outputDevices) && JSON.stringify(s.outputDevices) !== JSON.stringify(root.outputDevices))
            root.outputDevices = s.outputDevices

        // See the pending-pair note above: ignore a field we're mid-change on, and clear
        // the pending flag as soon as Discord agrees with us.
        const m = !!s.mute
        if (root._pendingMute < 0)           root.mute = m
        else if ((root._pendingMute === 1) === m) { root.mute = m; root._pendingMute = -1 }

        const d = !!s.deaf
        if (root._pendingDeaf < 0)           root.deaf = d
        else if ((root._pendingDeaf === 1) === d) { root.deaf = d; root._pendingDeaf = -1 }

        if (root.connected) root.lastError = ""

        // ── Don't reassign an unchanged participant list ──────────────────────
        // Snapshots arrive on every ping update and every speaking change. Assigning
        // `users` rebuilds every delegate in the Repeater bound to it — avatars
        // re-fetched, speaking-ring animations restarted from zero. The helper already
        // suppresses byte-identical snapshots, but a ping change alone still produces a
        // new line with the SAME users, and that must not churn the list.
        // (Same guard, same reason, as Hypr's `_snapshot`.)
        const next = s.users ?? []
        const stamp = JSON.stringify(next)
        if (stamp !== root._usersStamp) {
            root._usersStamp = stamp
            root.users = next
        }
    }

    property string _usersStamp: ""

    // ── Call duration ─────────────────────────────────────────────────────────
    // Discord's RPC does not report when a call started, so it's timed from when this
    // shell first saw the channel. That makes it "how long you've had this call open
    // here", which is the same number in every normal case and honestly can't be
    // better without data Discord doesn't send.
    //
    // Keyed on the CHANNEL ID rather than on `inCall`, for two reasons:
    //   · hopping channels restarts the clock, which is what you'd expect;
    //   · the helper losing Discord and reconnecting does NOT, because `channel`
    //     briefly going null while `connected` is false isn't you leaving the call.
    // Timing off `inCall` alone would silently reset the clock on every reconnect.
    property double callStartedAt: 0
    property string _timedChannel: ""

    onChannelChanged: {
        const id = root.channel?.id ?? ""
        if (id !== "" && id !== root._timedChannel) {
            root._timedChannel = id
            root.callStartedAt = Date.now()
        } else if (id === "" && root.connected) {
            root._timedChannel = ""
            root.callStartedAt = 0
        }
    }

    // mm:ss, growing to h:mm:ss past the hour. Callers pass `Date.now()` from their own
    // ticker — this service does NOT run a 1Hz timer, because a clock nobody is looking
    // at has no business ticking (same rule as the overview's own clock).
    function durationText(now) {
        if (root.callStartedAt <= 0) return ""
        const s = Math.max(0, Math.floor((now - root.callStartedAt) / 1000))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const sec = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec)
                     : pad(m) + ":" + pad(sec)
    }

    // ── Derived, for the card ─────────────────────────────────────────────────
    readonly property string channelName: root.channel?.name ?? ""
    readonly property string guildName:   root.channel?.guild ?? ""

    // ── What to call this call ────────────────────────────────────────────────
    // A guild voice channel has a name. A DM call does NOT — Discord sends an empty
    // name and a null guild_id — so "Voice" would be the title for every DM you ever
    // take. Naming it after who you're actually talking to is more useful, and is what
    // Discord itself does.
    readonly property string callTitle: {
        if (root.channelName !== "") return root.channelName

        const others = root.users.filter(u => !(u.isSelf ?? false)).map(u => u.name)
        if (others.length === 1) return others[0]
        if (others.length > 1)   return others[0] + " +" + (others.length - 1)
        return "Voice"
    }

    // Discord's own three-state signal. VOICE_CONNECTED is the only fully-good one;
    // everything mid-handshake is amber, and the failure states are red.
    readonly property string quality: {
        if (!root.inCall) return "none"
        switch (root.status) {
        case "VOICE_CONNECTED":
        case "CONNECTED":            return "good"
        case "NO_ROUTE":
        case "ICE_CHECKING":
        case "DISCONNECTED":
        case "VOICE_DISCONNECTED":   return "bad"
        default:                     return "connecting"
        }
    }

    // ══ SCREEN SHARE AND CAMERA ═══════════════════════════════════════════════
    // Everything above this line is real RPC. This is not.
    //
    // Discord exposes no command for either, so the only route left is to act like a
    // user: focus Discord's window and press its keybind. That means it is fragile in
    // ways nothing else here is — it depends on the keybind existing, on Discord being
    // open, and on the shell letting go of the keyboard first.
    //
    // ── Why the caller must close the overview ────────────────────────────────
    // The overview is a layer-shell surface holding WlrKeyboardFocus.Exclusive. While
    // it's up, the COMPOSITOR gives it the keyboard, so an injected keystroke lands on
    // the overview and never reaches Discord. Closing it is not a nicety, it's the
    // precondition — and it's the caller's job because closing the overview is a UI
    // decision, and this file has no business reaching into UiState.
    //
    // It also happens to be the right UX: Go Live opens a source picker in Discord, so
    // you want to be there anyway.

    // ══ CREDENTIALS ═══════════════════════════════════════════════════════════
    // Read and written through scripts/discord-credentials.py, never by QML directly.
    // Two reasons, both in that script's header: Quickshell can't create a file 0600,
    // and the secret must not pass through argv where `ps` would show it.
    //
    // ── The secret is write-only from up here ─────────────────────────────────
    // `hasSecret` is a boolean and there is deliberately no property holding the value.
    // The settings page needs to know one is SET, never what it is — so it never holds
    // it, and saving without a `clientSecret` key leaves the stored one untouched. That
    // is what lets the page edit the client ID or a keybind without the secret ever
    // entering the QML layer at all.
    readonly property string clientId:    root._cred.clientId    ?? ""
    readonly property string redirectUri: root._cred.redirectUri ?? ""
    readonly property bool   hasSecret:   root._cred.hasSecret   ?? false
    readonly property string configPath:  root._cred.path        ?? ""
    readonly property bool   hasCredentials: root.clientId !== "" && root.hasSecret
    readonly property bool   sharedApp:   root._cred.sharedApp   ?? true

    property var  _cred: ({})
    property bool credentialsBusy: false
    property string credentialsError: ""

    // false-then-true, not a bare true: an assignment to a property that already holds
    // that value changes nothing, so a bare `running = true` on a process that hasn't
    // exited yet is silently a no-op. Same restart idiom as Updates.qml.
    function refreshCredentials() {
        root._statusProc.running = false
        root._statusProc.running = true
    }

    // `patch` is merged, not replaced — omit a field to leave it alone. Omitting
    // `clientSecret` specifically means "keep the stored secret", which is the normal
    // case for every save that isn't setting a new one.
    function saveCredentials(patch) {
        if (root.credentialsBusy) return
        root.credentialsBusy = true
        root.credentialsError = ""
        root._saveProc.pending = JSON.stringify(patch)
        // Re-enabled every time: onStarted closes it to signal EOF, so without this the
        // SECOND save would start with stdin already shut and hand the script nothing.
        root._saveProc.stdinEnabled = true
        root._saveProc.running = false
        root._saveProc.running = true
    }

    property Process _statusProc: Process {
        running: false
        command: ["python3", Quickshell.shellPath("scripts/discord-credentials.py"),
                  "--status"]
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    root._cred = JSON.parse(line)
                } catch (e) {
                    console.warn("Discord: bad credentials status:", line.substring(0, 120))
                }
            }
        }
    }

    property Process _saveProc: Process {
        property string pending: ""
        running: false
        stdinEnabled: true
        command: ["python3", Quickshell.shellPath("scripts/discord-credentials.py")]

        // `onStarted`, NOT onRunningChanged: `running` flips true on assignment, before
        // the process exists, and a write into a process that hasn't spawned goes
        // nowhere. Then stdin is closed, because the script reads to EOF and would
        // otherwise wait forever. Both halves are Updates.qml's fifoWriter idiom.
        onStarted: {
            if (pending === "") return
            write(pending + "\n")
            pending = ""
            stdinEnabled = false
        }

        // The script replies with a fresh status, so state comes from what was actually
        // stored rather than from what we hoped we sent.
        stdout: SplitParser {
            onRead: function(line) {
                try { root._cred = JSON.parse(line) } catch (e) {}
            }
        }
        stderr: SplitParser {
            onRead: function(line) { root.credentialsError = line }
        }

        onExited: function(code) {
            root.credentialsBusy = false
            if (code !== 0 && root.credentialsError === "")
                root.credentialsError = "could not save (exit " + code + ")"
            // No reload needed: the helper re-stats the credentials file every few
            // seconds precisely so writing it takes effect on its own.
            if (code === 0) root.lastError = ""
        }
    }

    Component.onCompleted: root.refreshCredentials()

    // Populated from discord-rpc.json by the helper, which strips the credentials out
    // of it first. Empty spec ⇒ the button is disabled rather than firing nothing.
    property var _keys: ({})

    readonly property string cameraKey:     root._keys.camera     ?? "ctrl+shift+v"
    readonly property string screenShareKey: root._keys.screenshare ?? ""

    // ── Which Discord is this? ────────────────────────────────────────────────
    // The RPC half of this service never has to ask: every client — official, Vesktop,
    // WebCord, Legcord — writes the same `discord-ipc-0` socket, so mute, deafen, the
    // participant list and hangup work on all of them without knowing which is which.
    //
    // Injection is the exception, because it has to FIND A WINDOW. The list comes from
    // discord-rpc.json via the helper (see DEFAULT_WINDOW_CLASSES there, including which
    // entries are actually verified), so an unrecognised client is a config line rather
    // than a code change.
    // The fallback is only for the window between shell start and the helper's first
    // `config` line — and for a helper too old to send one. discord-rpc.py's
    // DEFAULT_WINDOW_CLASSES is the copy that governs; this one is deliberately the
    // same values so the two can't disagree about behaviour, only about timing.
    readonly property var windowClasses: root._windowClasses.length > 0
        ? root._windowClasses
        : ["discord", "vesktop", "webcord", "legcord", "armcord", "dorion"]
    property var _windowClasses: []

    // Prefix, not equality: `discord` has to also match discordcanary and discordptb,
    // which are the same app with the same keybinds.
    readonly property var _window: {
        const w = Hypr.windows.filter(x => {
            const c = (x.appClass ?? "").toLowerCase()
            return root.windowClasses.some(p => c.startsWith(p))
        })
        return w.length > 0 ? w[0] : null
    }

    readonly property string windowAddress: root._window ? root._window.address : ""

    // ── Which injector this window needs ──────────────────────────────────────
    // Not interchangeable, and picking wrong fails silently in both directions: wtype
    // against an XWayland client exits 0 having delivered nothing (the bug that made
    // screen share "do nothing" for a while), and xdotool can't see a native Wayland
    // window at all. So the requirement is derived from the window, not assumed.
    readonly property bool windowIsXwayland: root._window ? (root._window.xwayland ?? false) : false
    readonly property bool hasInjector: root.windowIsXwayland ? root._hasXdotool : root._hasWtype

    property bool _hasXdotool: false
    property bool _hasWtype:   false
    property bool _probed:     false

    // One run at startup. `--probe` presses nothing and always exits 0; it exists so a
    // missing tool disables the button with a reason, instead of being discovered by
    // clicking it and having nothing happen.
    property Process _probeProc: Process {
        running: Config.discordEnabled
        command: ["python3", Quickshell.shellPath("scripts/discord-press.py"), "--probe"]
        stdout: SplitParser {
            onRead: function(line) {
                root._hasXdotool = line.indexOf("xdotool=1") >= 0
                root._hasWtype   = line.indexOf("wtype=1")   >= 0
                root._probed = true
            }
        }
    }

    readonly property bool canInject: root.windowAddress !== "" && root.hasInjector

    function canPress(spec) { return root.canInject && (spec ?? "") !== "" }

    // Why a button is disabled, in the order the user has to fix them. Empty when the
    // press would actually work. Lives here rather than in the card because it's about
    // the machine, not the layout — a bar module would need exactly the same string.
    function pressBlocker(spec) {
        if (root.windowAddress === "")
            return "Discord isn't running"
        if (!root._probed)
            return ""
        if (!root.hasInjector)
            return root.windowIsXwayland
                ? "Install xdotool — this Discord runs under XWayland"
                : "Install wtype to send keystrokes to Discord"
        if ((spec ?? "") === "")
            return "No keybind set — see keys in discord-rpc.json"
        return ""
    }

    function toggleCamera()     { root.pressInDiscord(root.cameraKey) }
    function toggleScreenShare() { root.pressInDiscord(root.screenShareKey) }

    // ── Pressing a key inside Discord ─────────────────────────────────────────
    // Finding the window, focusing it and injecting all live in scripts/discord-press.py
    // — see there for WHY, which is the whole story: Discord runs under XWayland, so
    // `wtype` delivers keystrokes nowhere while exiting 0. That needs xdotool and a
    // synchronous window activation, and none of it is expressible as one QML Process
    // without a shell string.
    //
    // Every argument is a separate argv entry, so a keyspec out of a config file can
    // never become a command.
    function pressInDiscord(spec) {
        if (!root.canPress(spec)) return

        root._pendingSpec = spec

        // A beat before pressing, so the overview has actually released the keyboard.
        // The caller sets `overviewOpen = false` immediately before this, but that's a
        // compositor round-trip — inject too early and the layer surface still owns
        // focus. A Timer, NOT a sleep in a command: this runs on the UI thread, and a
        // blocking sleep would stall the whole shell for its duration.
        root._injectTimer.restart()
    }

    property string _pendingSpec: ""

    property Timer _injectTimer: Timer {
        interval: 150
        repeat: false
        onTriggered: {
            if (root._pendingSpec === "") return
            // Repeated --class, one entry per argv slot. The script's own default only
            // applies to running it by hand.
            const classArgs = root.windowClasses.reduce(
                (acc, c) => acc.concat(["--class", c]), [])

            root._injectProc.command = [
                "python3", Quickshell.shellPath("scripts/discord-press.py"),
                root._pendingSpec, "--address", root.windowAddress
            ].concat(classArgs)
            root._pendingSpec = ""
            root._injectProc.running = true
        }
    }

    property Process _injectProc: Process {
        running: false

        stderr: SplitParser { onRead: function(line) { console.log("Discord press:", line) } }

        onExited: function(code) {
            // This is the one path in the file that can fail without Discord ever
            // hearing about it, so it says so rather than leaving a button that
            // appears to do nothing. The codes come from discord-press.py.
            if (code === 0) return
            root.lastError =
                  code === 2 ? "couldn't focus Discord's window"
                : code === 3 ? "no xdotool or wtype installed"
                : code === 4 ? "bad keybind in discord-rpc.json"
                :              "keystroke failed (exit " + code + ")"
        }
    }
}
