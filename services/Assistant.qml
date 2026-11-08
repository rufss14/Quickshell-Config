pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "../config"
import "../state"
import "assistant.js" as AJ

// ── Assistant ─────────────────────────────────────────────────────────────────
// The overview's AI page (OverviewFeed → FeedAssistant): a chat that can CHANGE the shell. It
// talks through the same scripts/ai-ask.py as the launcher's `?` (same provider, same keys —
// `Ai` owns both), but it is its own conversation: its own thread here, its own Claude Pro
// session in ai-ask.py ("Overview"), and its own system prompt — services/assistant.js's, which
// lists what may be changed and how it is set right now.
//
// ── What it can reach ─────────────────────────────────────────────────────────
// Settings, colour schemes (made or saved), and the shell itself through assistant.js's fixed lists —
// ShellActions' entries, volume, brightness, a wallpaper, media keys, a workspace, an app, a timer.
// No command line, no files, nothing that deletes or closes; lock, reload, the power menu, recording
// and Settings wait for an OK on their card (`confirm`). See assistant.js for the three layers.
//
// ── It just flips them ────────────────────────────────────────────────────────
// A reply can end in action blocks (a colour scheme, a setting). assistant.js checks them against
// a fixed list, and what passes is APPLIED as the reply lands (the user, 2026-10-24: "it should just
// flip settings, so it's as fast as possible" — it used to wait for an Apply click). Each becomes a
// card saying what changed, with Undo: every apply keeps what it replaced. Nothing off the list can
// be applied at all; that is the guard, not a click.
//
// ── Memory only ───────────────────────────────────────────────────────────────
// The thread lives here for the session — it survives the overview closing, not a reload — and
// is never written to disk, the launcher's rule (services/Ai.qml). A new thread starts a new
// Claude Pro session, so the model can't remember what the page no longer shows.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // {role: "user"|"model", text (shown), raw (sent back), actions: [validated, assistant.js]}.
    // Reassigned, never mutated (a JS array property only notifies on assignment).
    property var messages: []
    property bool busy: false
    property bool thinking: false
    property string error: ""
    property string pending: ""
    readonly property bool hasThread: root.messages.length > 0

    // Per card, "m-a" (message index, action index) → { state: "applied"|"undone"|"failed"|"ask"|"skipped",
    // note, undo }. "ask": an action that waits for the user's OK (assistant.js `confirm`).
    property var applied: ({})

    // A thread belongs to the model that answered it (Ai's rule).
    readonly property string provider: Config.aiProvider
    onProviderChanged: root.clear()

    // What exists on THIS machine, for the prompt and for checking a reply against: the library's
    // wallpapers by file name, the saved schemes, the shell actions' names and their states now.
    function _names() {
        const ctx = { wallpapers: Wallpaper.wallpapers.map(p => p.split("/").pop()),
                      scenes: WallpaperEngine.blocker() === "" ? WallpaperEngine.scenes.map(i => i.title).filter(t => !!t) : [],
                      presets: ColorScheme.presets.map(p => p.name),
                      names: ({}), states: ({}),
                      volume: Math.round(Audio.volume * 100) }
        for (const a of ShellActions.table) {
            ctx.names[a.id] = a.name
            const st = ShellActions.stateOf(a.id)
            if (st !== "") ctx.states[a.id] = st
        }
        ctx.nowMs = Date.now()
        ctx.windowApps = Hypr.windows.filter(w => w.workspaceId > 0 && w.appClass)
            .map(w => w.appClass).filter((c, i, all) => all.indexOf(c) === i)
        ctx.outputs = Audio.sinks.map(n => Audio.labelFor(n)).filter(l => !!l)
        ctx.bluetooth = Bt.known.map(d => d.name).filter(n => !!n)
        ctx.memory = (Config.aiMemory || []).slice(-20)
        ctx.appCeiling = Math.round(Audio.boostCeiling * 100)
        ctx.discordUsers = Discord.inCall ? Discord.users.filter(u => !u.isSelf && u.name).map(u => u.name) : []
        ctx.now = root._nowLines()
        return ctx
    }

    // ── What the shell knows right now, for questions ("how hot is my GPU?", "what did I miss?") ──
    // Read off the services that already hold it — nothing is fetched for this. A service that has
    // nothing yet (weather never asked for, no battery) is left out rather than reported as zero.
    function _nowLines() {
        const out = []
        const d = new Date()
        out.push("Time: " + d.toLocaleString(Qt.locale(), "dddd d MMMM yyyy, HH:mm"))
        if (Weather.ready && Weather.hasLocation)
            out.push("Weather in " + Config.weatherPlace + ": " + Weather.temp(Weather.tempC) + Weather.unit + ", "
                     + Weather.describe(Weather.code).toLowerCase() + ", feels " + Weather.temp(Weather.feelsC) + Weather.unit
                     + ", humidity " + Weather.humidity + "%, wind " + Weather.wind(Weather.windKph))
        const sys = []
        if (SysInfo.cpu > 0) sys.push("CPU " + Math.round(SysInfo.cpu * 100) + "%" + (SysInfo.cpuTemp > 0 ? " at " + SysInfo.cpuTemp + "°C" : ""))
        if (SysInfo.hasGpu) sys.push("GPU " + Math.round(SysInfo.gpu * 100) + "%" + (SysInfo.hasGpuTemp ? " at " + SysInfo.gpuTemp + "°C" : ""))
        if (SysInfo.memTotal > 0) sys.push("RAM " + SysInfo.memUsed.toFixed(1) + " of " + SysInfo.memTotal.toFixed(0) + " GB")
        if (sys.length) out.push("System: " + sys.join(", "))
        if (SysStats.hasBattery) out.push("Battery: " + Math.round((SysStats.battery?.percentage ?? 0) * 100) + "%")
        const p = root._player()
        if (p && (p.trackTitle || "") !== "")
            out.push("Music: " + (p.isPlaying ? "playing " : "paused on ") + "“" + p.trackTitle + "”"
                     + (p.trackArtist ? " by " + p.trackArtist : "") + " in " + (p.identity || "a player"))
        out.push("Volume: " + Math.round(Audio.volume * 100) + "%" + (Audio.muted ? " (muted)" : "")
                 + (Audio.sink ? ", out of " + Audio.labelFor(Audio.sink) : ""))
        const recs = Notifications.records.slice(-6).reverse()
        out.push("Notifications: " + Notifications.records.length + (recs.length
                 ? " — newest: " + recs.map(r => (r.appName || "?") + ": " + (r.summary || "").slice(0, 60)).join("; ") : ""))
        const wins = Hypr.windows.filter(w => w.workspaceId > 0).slice(0, 16)
        if (wins.length) out.push("Windows: " + wins.map(w => (w.appClass || "?") + " on workspace " + w.workspaceId
                                   + (w.floating ? " (floating)" : "")).join("; ") + ". You're on workspace " + Hypr.focusedWorkspaceId + ".")
        // Each app's own volume: a player's own level (past 100% when boosted), else its stream's.
        const apps = []
        for (const pl of Mpris.players.values) {
            const de = pl.desktopEntry || ""
            if (Audio.hasPlayerVolume(pl, de)) apps.push((pl.identity || de) + " " + Math.round(Audio.playerLevel(pl, de) * 100) + "%")
        }
        for (const n of Audio.streams) {
            const name = Audio.labelFor(n)
            if (name && !apps.some(a => a.toLowerCase().startsWith(name.toLowerCase())))
                apps.push(name + " " + Math.round(Audio.levelOf(n) * 100) + "%")
        }
        if (apps.length) out.push("App volumes (each can go to " + Math.round(Audio.boostCeiling * 100) + "%): " + apps.slice(0, 10).join(", "))
        if (Discord.inCall && Discord.channel)
            out.push("Discord call: " + Discord.channelName + (Discord.guildName ? " in " + Discord.guildName : "")
                     + " with " + (Discord.users.filter(u => !u.isSelf).map(u => u.name + (u.mute ? " (muted by you)" : "")).join(", ") || "nobody else")
                     + (Discord.mute ? "; you're muted" : "") + (Discord.deaf ? "; deafened" : "")
                     + "; mic " + Discord.inputVolume + "%, output " + Discord.outputVolume + "%"
                     + (Discord.inputMode === "PUSH_TO_TALK" ? ", push to talk" : "")
                     + (Discord.processing.noise ? ", noise suppression on" : ""))
        else if (Discord.connected) out.push("Discord: not in a call")
        if (Reminders.openCount > 0) {
            const next = Reminders.sorted.find(r => !r.done)
            out.push("Reminders: " + Reminders.openCount + " open" + (next ? ", next: “" + next.text + "” " + Reminders.dueLabel(next) : ""))
        }
        if (Tasks.openCount > 0) out.push("To-do: " + Tasks.items.filter(t => !t.done).slice(0, 8).map(t => t.text).join("; "))
        if (Timers.alarms.length > 0) out.push("Alarms: " + Timers.alarms.map(a => Timers.pad(a.h) + ":" + Timers.pad(a.m) + (a.enabled ? "" : " (off)")).join(", "))
        return out
    }
    function _context() {
        const current = {}
        for (const k in AJ.SETTINGS) current[k] = Config[k]
        return AJ.systemPrompt(current, ColorScheme.live, new Date().toISOString().slice(0, 10),
                               root.provider === "ollama", root._names())
    }

    function ask(q) {
        const text = (q || "").trim()
        if (text === "" || root.busy || Ai.blocker() !== "") return
        const fresh = root.messages.length === 0
        root.messages = root.messages.concat([{ role: "user", text: text, raw: text, actions: [] }])
        root.busy = true
        root.thinking = true
        root.error = ""
        root.pending = ""
        // A new thread on Claude Pro starts a new CLI session first (see the header).
        if (fresh && root.provider === "claudecode") { resetProc.then = true; resetProc.running = true }
        else root._send()
    }

    function _send() { askProc.running = false; askProc.running = true }

    function stop() {
        askProc.running = false
        root.busy = false
        root.thinking = false
        if (root.pending !== "") root._land(root.pending)
        root.pending = ""
    }

    function clear() {
        askProc.running = false
        root.messages = []
        root.applied = ({})
        root.error = ""
        root.busy = false
        root.thinking = false
        root.pending = ""
    }

    function _land(raw) {
        const r = AJ.parseReply(raw, root._names())
        root.messages = root.messages.concat([{ role: "model", text: r.text, raw: raw, actions: r.actions }])
        const m = root.messages.length - 1
        let leave = false
        for (let a = 0; a < r.actions.length; a++) {
            const act = r.actions[a]
            if (act.confirm) { root._mark(m, a, { state: "ask", note: "", undo: null }); continue }
            if (root.apply(m, a) && act.leaves) leave = true
        }
        // A panel, a picker, another workspace: the overview steps aside once, after them all.
        if (leave) root._leaveSoon()
    }

    // The OK on an "ask" card (lock, reload, power menu, recording, Settings) — or not.
    function confirm(m, a) {
        const act = root.messages[m]?.actions?.[a]
        if (!act || root.stateOf(m, a)?.state !== "ask") return
        if (root.apply(m, a) && act.leaves) root._leaveSoon()
    }
    function skip(m, a) {
        if (root.stateOf(m, a)?.state === "ask") root._mark(m, a, { state: "skipped", note: "", undo: null })
    }
    function _leaveSoon() { leaveTimer.restart() }
    // The snip tool wants the screen clear: after the overview has gone.
    property Timer snipSoon: Timer { interval: Motion.spatial + Motion.standard; onTriggered: Snip.start("") }
    property Timer leaveTimer: Timer { interval: Motion.spatial; onTriggered: UiState.leaveOverview(-1) }

    function _on(id) { return ["On", "Muted", "Hidden", "Recording", "Light"].indexOf(ShellActions.stateOf(id)) >= 0 }
    function _player() {
        const ps = Mpris.players.values
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null
    }

    function stateOf(m, a) { return root.applied[m + "-" + a] ?? null }
    function _mark(m, a, rec) {
        const next = Object.assign({}, root.applied)
        next[m + "-" + a] = rec
        root.applied = next
    }

    // Does card `a` of message `m` through the service that owns the job, keeping what it replaced
    // (the card's Undo). true when it ran. Everything here was checked by assistant.js first.
    function apply(m, a) {
        const act = root.messages[m]?.actions?.[a]
        if (!act || act.do === "invalid") return false
        const done = (undo, note) => { root._mark(m, a, { state: "applied", note: note || "", undo: undo || null }); return true }
        const fail = note => { root._mark(m, a, { state: "failed", note: note, undo: null }); return false }

        switch (act.do) {
        case "set": {
            const before = Config[act.key]
            // The mode re-derives the palette (ColorScheme.switchMode); writing the property alone
            // wouldn't (the user, 2026-10-24: "asking to change theme, it doesn't apply"). Already in
            // that mode — say an earlier write left the mode flipped and the colours not — derive anew.
            if (act.key === "themeMode") {
                if (Config.themeMode === act.value) Wallpaper.reapplyPalette()
                else ColorScheme.switchMode(act.value)
            } else Config[act.key] = act.value
            return done({ do: "set", key: act.key, value: before })
        }
        case "scheme":
        case "preset": {
            if (ColorScheme.busy) return fail("Colours are still changing — try again in a moment")
            const pal = act.do === "scheme" ? act.palette : ColorScheme.schemePalette(act.name)
            if (!pal) return fail("That scheme isn't there any more")
            const live = ColorScheme.live ?? ({})
            const before = { special: Object.assign({}, live.special ?? ({})), colors: Object.assign({}, live.colors ?? ({})) }
            ColorScheme.applyPalette(pal, act.name)
            return done({ do: "scheme", palette: before })
        }
        case "action": {
            const why = ShellActions.blockerOf(act.id)
            if (why !== "") return fail(why)
            if (act.toggle && act.on !== undefined && root._on(act.id) === act.on)
                return done(null, act.on ? "Already on" : "Already off")
            if (!ShellActions.run(act.id)) return fail("Couldn't do that")
            return done(act.toggle ? { do: "action", id: act.id } : null)
        }
        case "volume": {
            if (!Audio.ready) return fail("Audio isn't ready")
            const before = Audio.volume
            Audio.setVolume(act.value / 100)
            return done({ do: "volume", value: before })
        }
        case "brightness": {
            Brightness.ensureProbed()
            const before = []
            for (let i = 0; i < Brightness.count; i++) {
                const mon = Brightness.monitors.get(i)
                if (!mon.controllable) continue
                before.push({ i: i, v: mon.brightness })
                Brightness.requestBrightness(i, act.value)
            }
            if (before.length === 0) return fail("No screen here takes a brightness change")
            return done({ do: "brightness", list: before })
        }
        case "wallpaper": {
            if (act.random) {
                if (Wallpaper.wallpapers.length < 2) return fail("No other pictures in your library")
                const was = Wallpaper.currentPath
                Wallpaper.shuffleNow(true)
                return done(was ? { do: "wallpaper", path: was } : null)
            }
            const path = Wallpaper.wallpapers.find(p => p.split("/").pop() === act.name)
            if (!path) return fail("That picture isn't in your library any more")
            const was = Wallpaper.currentPath
            Wallpaper.apply(path)
            return done(was ? { do: "wallpaper", path: was } : null)
        }
        case "media": {
            const p = root._player()
            if (!p) return fail("Nothing is playing")
            if (act.command === "play") p.play()
            else if (act.command === "pause") p.pause()
            else if (act.command === "toggle") p.togglePlaying()
            else if (act.command === "next") p.next()
            else p.previous()
            return done(null)
        }
        case "scene": {
            const why = WallpaperEngine.blocker()
            if (why !== "") return fail(why)
            const it = WallpaperEngine.scenes.find(i => i.title === act.name)
            if (!it) return fail("That scene isn't installed any more")
            const was = { scene: WallpaperEngine.running ? WallpaperEngine.current : "", path: Wallpaper.currentPath }
            Wallpaper.pickScene(it.id)
            return done({ do: "wallpaper", scene: was.scene, path: was.path })
        }
        case "play": {
            if (playProc.running) return fail("Still starting the last one")
            playProc.m = m
            playProc.a = a
            playProc.command = ["python3", Quickshell.shellPath("scripts/music-play.py"), act.query, "--kind", act.kind]
            playProc.running = true
            root._mark(m, a, { state: "working", note: Translation.tr("Finding it on Spotify…"), undo: null })
            return true
        }
        case "open":
            Qt.openUrlExternally(act.url)
            return done(null)
        case "search":
            Qt.openUrlExternally(Config.webSearchUrl.replace("%s", encodeURIComponent(act.query)))
            return done(null)
        case "workspace":
            Hypr.focusWorkspace(act.id, true, null)
            return done(null)
        case "launch": {
            const hit = Launcher.search(act.app, 8).find(r => r.kind === "app")
            if (!hit) return fail("No app called “" + act.app + "”")
            Launcher.launch(hit.entry)
            return done(null, hit.name)
        }
        case "timer":
            Timers.startTimerFor(Math.round(act.minutes * 60))
            return done({ do: "timer" })
        case "remind": {
            const err = Reminders.addDue(act.text, act.due)
            if (err) return fail(err)
            return done({ do: "remind", text: act.text, due: act.due })
        }
        case "todo":
            Tasks.add(act.text)
            return done(null)
        case "alarm": {
            const before = Timers.alarms.map(x => x.id)
            Timers.addAlarm(act.h, act.m, act.days)
            const made = Timers.alarms.find(x => before.indexOf(x.id) < 0)
            return done(made ? { do: "alarm", id: made.id } : null)
        }
        case "window": {
            const w = Hypr.windows.find(x => (x.appClass || "") === act.app)
            if (!w) return fail("That window isn't open any more")
            const u = { do: "window", address: w.address, ws: -1, float: false }
            if (act.workspace !== undefined && act.workspace !== w.workspaceId) {
                u.ws = w.workspaceId
                Hypr.moveWindowToWorkspace(w.address, act.workspace, "", "")
            }
            if (act.float !== undefined && act.float !== w.floating) { ActiveWindow.toggleFloating(w.address); u.float = true }
            // Only when it differs — a toggle sent for `fullscreen: false` would MAKE it fullscreen. The state
            // is Hyprland's own record of the client; unknown, only an explicit "yes" acts.
            if (act.fullscreen !== undefined) {
                const fsNow = w.toplevel?.lastIpcObject?.fullscreen
                const isFs = fsNow === undefined ? !act.fullscreen : Number(fsNow) > 0
                if (isFs !== act.fullscreen) ActiveWindow.toggleFullscreen(w.address)
            }
            if (act.focus) Hypr.focusWindow(w.address)
            return done(u.ws > 0 || u.float ? u : null)
        }
        case "output": {
            const node = Audio.sinks.find(n => Audio.labelFor(n) === act.device)
            if (!node) return fail("That output isn't there any more")
            const was = Audio.sink
            Audio.setDefaultSink(node)
            return done(was ? { do: "output", node: was } : null)
        }
        case "appvolume": {
            // A media player (Spotify) by its OWN volume and, past 100%, the boost — Audio.setPlayerLevel,
            // the volume profiles' path, so it lasts the song (Spotify rewrites its stream on a track
            // change). Anything else by its stream.
            const q = act.app.toLowerCase()
            const pl = Mpris.players.values.find(x => (x.identity || "").toLowerCase().indexOf(q) >= 0
                                                    || (x.desktopEntry || "").toLowerCase().indexOf(q) >= 0)
            const de = pl ? (pl.desktopEntry || "") : ""
            if (pl && Audio.hasPlayerVolume(pl, de)) {
                const was = Audio.playerLevel(pl, de)
                Audio.setPlayerLevel(pl, de, act.value / 100, act.value > 100)
                return done({ do: "playerlevel", player: pl, app: de, value: was })
            }
            const nodes = Audio.streamsMatching(act.app)
            if (nodes.length === 0) return fail("“" + act.app + "” isn't playing any sound")
            const before = nodes.map(n => ({ node: n, v: Audio.levelOf(n) }))
            for (const n of nodes) Audio.setNodeVolume(n, act.value / 100, act.value > 100)
            return done({ do: "appvolume", list: before })
        }
        case "bluetooth": {
            const dev = Bt.known.find(x => x.name === act.device)
            if (!dev) return fail("That device isn't paired any more")
            if (dev.connected === act.connect) return done(null, act.connect ? "Already connected" : "Already disconnected")
            Bt.toggleConnection(dev)
            return done({ do: "bluetooth", device: act.device })
        }
        case "clip": {
            const why = Clips.blocker()
            if (why !== "") return fail(why)
            if (!Clips.buffering) return fail("Clipping is off — ask me to turn it on first")
            Clips.saveClip(act.seconds)
            return done(null)
        }
        case "screenshot":
            snipSoon.restart()
            return done(null)
        case "look": {
            const u = { do: "look", walls: Object.assign({}, Config.wallWorkspaces), schemes: Object.assign({}, Config.schemeWorkspaces) }
            if (act.wallpaper) {
                const path = Wallpaper.wallpapers.find(x => x.split("/").pop() === act.wallpaper)
                if (!path) return fail("That picture isn't in your library any more")
                Wallpaper.assign(path, act.workspaces)
            }
            if (act.scheme) ColorScheme.assign(act.scheme, act.workspaces)
            return done(u)
        }
        case "discord": {
            if (!Discord.connected) return fail("Discord isn't connected to the shell")
            if (act.command === "camera" || act.command === "screenshare") {
                const key = act.command === "camera" ? Discord.cameraKey : Discord.screenShareKey
                const why = Discord.pressBlocker(key)
                if (why !== "") return fail(why)
                if (act.command === "camera") Discord.toggleCamera(); else Discord.toggleScreenShare()
                return done(null)
            }
            if (!Discord.inCall) return fail("You're not in a Discord call")
            if (act.command === "leave") {
                Discord.disconnect()
                return done(null, Discord.channelName ? "Left " + Discord.channelName : "")
            }
            const wantMute = act.command === "mute", wantDeaf = act.command === "deafen"
            if (act.command === "mute" || act.command === "unmute") {
                if (Discord.mute === wantMute) return done(null, wantMute ? "Already muted" : "Already unmuted")
                Discord.toggleMute()
                return done({ do: "discord", which: "mute" })
            }
            if (Discord.deaf === wantDeaf) return done(null, wantDeaf ? "Already deafened" : "Already undeafened")
            Discord.toggleDeaf()
            return done({ do: "discord", which: "deaf" })
        }
        case "discordvolume": {
            if (!Discord.connected) return fail("Discord isn't connected to the shell")
            if (act.target === "input") { const was = Discord.inputVolume; Discord.setInputVolume(act.value); return done({ do: "discordvolume", target: "input", value: was }) }
            if (act.target === "output") { const was = Discord.outputVolume; Discord.setOutputVolume(act.value); return done({ do: "discordvolume", target: "output", value: was }) }
            const u = Discord.users.find(x => x.name === act.target)
            if (!u) return fail(act.target + " isn't in the call any more")
            const was = u.volume
            Discord.setUserVolume(u.id, act.value)
            return done({ do: "discordvolume", target: u.id, value: was })
        }
        case "discorduser": {
            const u = Discord.users.find(x => x.name === act.user)
            if (!u) return fail(act.user + " isn't in the call any more")
            if (!!u.mute === act.mute) return done(null, act.mute ? "Already muted" : "Already unmuted")
            Discord.setUserMute(u.id, act.mute)
            return done({ do: "discorduser", id: u.id, mute: !act.mute })
        }
        case "discordsetting": {
            if (!Discord.connected) return fail("Discord isn't connected to the shell")
            if (act.setting === "pushtotalk") {
                const was = Discord.inputMode
                Discord.setInputMode(act.on ? "PUSH_TO_TALK" : "VOICE_ACTIVITY")
                return done({ do: "discordmode", value: was })
            }
            const was = !!Discord.processing[act.setting]
            Discord.setProcessing(act.setting, act.on)
            return done({ do: "discordsetting", key: act.setting, on: was })
        }
        case "findsetting": {
            const hit = SettingsIndex.search(act.query, 1)[0]
            if (!hit) return fail("No setting matches “" + act.query + "”")
            UiState.openSettingsTo(hit.file)
            return done(null, hit.title || "")
        }
        case "remember": {
            const before = (Config.aiMemory || []).slice()
            Config.aiMemory = before.filter(x => x !== act.fact).concat([act.fact]).slice(-20)
            return done({ do: "memory", list: before })
        }
        case "forget": {
            const before = (Config.aiMemory || []).slice()
            const f = act.fact.toLowerCase()
            Config.aiMemory = f === "all" ? [] : before.filter(x => x.toLowerCase().indexOf(f) < 0)
            return done({ do: "memory", list: before })
        }
        }
        return fail("Unknown action")
    }

    function undo(m, a) {
        const rec = root.stateOf(m, a)
        if (!rec || rec.state !== "applied" || !rec.undo) return
        const u = rec.undo
        switch (u.do) {
        case "set":
            if (u.key === "themeMode") ColorScheme.switchMode(u.value)
            else Config[u.key] = u.value
            break
        case "scheme":
            if (ColorScheme.busy) return
            ColorScheme.applyPalette(u.palette, "Previous colours")
            break
        case "action":     ShellActions.run(u.id); break
        case "volume":     Audio.setVolume(u.value); break
        case "brightness": for (const b of u.list) Brightness.requestBrightness(b.i, b.v); break
        case "wallpaper":
            if (u.scene) Wallpaper.pickScene(u.scene)
            else if (u.path) Wallpaper.apply(u.path)
            break
        case "timer":      Timers.stopTimer(); break
        case "remind": {
            const r = Reminders.items.find(x => x.text === u.text && x.due === u.due)
            if (r) Reminders.remove(r.id)
            break
        }
        case "alarm":      Timers.removeAlarm(u.id); break
        case "window":
            if (u.ws > 0) Hypr.moveWindowToWorkspace(u.address, u.ws, "", "")
            if (u.float) ActiveWindow.toggleFloating(u.address)
            break
        case "output":     Audio.setDefaultSink(u.node); break
        case "appvolume":  for (const b of u.list) Audio.setNodeVolume(b.node, b.v, false); break
        case "bluetooth": {
            const dev = Bt.known.find(x => x.name === u.device)
            if (dev) Bt.toggleConnection(dev)
            break
        }
        case "look":
            Config.wallWorkspaces = u.walls
            Config.schemeWorkspaces = u.schemes
            break
        case "discord":    if (u.which === "mute") Discord.toggleMute(); else Discord.toggleDeaf(); break
        case "playerlevel": Audio.setPlayerLevel(u.player, u.app, u.value, u.value > 1); break
        case "discordvolume":
            if (u.target === "input") Discord.setInputVolume(u.value)
            else if (u.target === "output") Discord.setOutputVolume(u.value)
            else Discord.setUserVolume(u.target, u.value)
            break
        case "discorduser":    Discord.setUserMute(u.id, u.mute); break
        case "discordmode":    Discord.setInputMode(u.value); break
        case "discordsetting": Discord.setProcessing(u.key, u.on); break
        case "memory":     Config.aiMemory = u.list; break
        }
        root._mark(m, a, { state: "undone", note: "", undo: null })
    }
    // Undo again: the card runs once more (an "undone" card's Redo).
    function redo(m, a) { if (root.stateOf(m, a)?.state === "undone") root.apply(m, a) }

    // "play X": scripts/music-play.py has Spotify find and play it (through the bridge's mailbox; a web
    // search when that can't) — a second or two, so the card says "working" until it answers. It never
    // touches what's playing unless it found something to play.
    property Process playProc: Process {
        property int m: -1
        property int a: -1
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) { d = { ok: false, error: "no answer" } }
                const note = !d.ok ? (d.error || "Couldn't play that")
                           : d.how === "opened" ? Translation.tr("Opened in Spotify") + (d.title ? " · " + d.title : "")
                           : (d.title || Translation.tr("Playing"))
                root._mark(playProc.m, playProc.a, { state: d.ok ? "applied" : "failed", note: note, undo: null })
            }
        }
    }

    property Process resetProc: Process {
        property bool then: false
        command: ["python3", Quickshell.shellPath("scripts/ai-ask.py"), "--reset-session", "Overview"]
        onExited: if (resetProc.then) { resetProc.then = false; root._send() }
    }

    property Process askProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai-ask.py"), "--stream"]
        stdinEnabled: true
        // Re-armed on every start — see Ai.askProc (stdin is closed after each write).
        onRunningChanged: if (running) stdinEnabled = true
        onStarted: {
            write(JSON.stringify({
                // The last few turns: enough for "and make it darker", and a small model stays on
                // the instructions instead of drowning in an old thread.
                messages: root.messages.slice(-10).map(x => ({ role: x.role, text: x.raw })),
                provider: root.provider,
                model: Config.aiModel,
                // A palette is ~16 colours of JSON on top of one sentence; anything past that is a
                // model rambling, and every token is time on a local one.
                maxTokens: 700,
                grounding: false,
                effort: Config.aiEffort,
                session: "Overview",
                system: root._context(),
                localUrl: Config.aiLocalUrl,
                // A local model answers in a constrained JSON shape (ai-ask.py ACTION_SCHEMA), with the
                // worked examples as earlier turns (assistant.js exampleTurns — why there, see systemPrompt).
                structured: root.provider === "ollama",
                examples: root.provider === "ollama" ? AJ.exampleTurns() : []
            }) + "\n")
            stdinEnabled = false
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.t === "thinking") { root.thinking = true; return }
                if (d.t === "delta") { root.thinking = false; root.pending += (d.text || ""); return }
                if (d.t === "error") root.error = d.error || "request failed"
            }
        }
        // Landed on exit, like Ai's: a turn that dies mid-stream still keeps what it said.
        onExited: {
            root.busy = false
            root.thinking = false
            if (root.pending !== "") root._land(root.pending)
            else if (root.error === "") root.error = "empty answer"
            root.pending = ""
        }
    }
}
