pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// ── Audio ─────────────────────────────────────────────────────────────────────
// The shell's single audio authority, backed by the native PipeWire service.
//
// This replaces every `wpctl` / `pactl` / `python3` subprocess in the shell.
// Before, three widgets each ran their own poller — EqualizerButton every 2s,
// EqualizerPanel every 3s (five subprocesses per tick, two of them piping JSON
// through python3), and each existed twice over because the status bar builds
// both its layouts. Volume was therefore up to ~0.5s stale, and moving a slider
// meant spawning a process per drag frame.
//
// PipeWire pushes. Nothing here polls, and there is one instance of it no
// matter how many widgets are watching.
//
// ── On reading the graph ──────────────────────────────────────────────────────
// Node classification goes through `properties["media.class"]` rather than the
// isSink/isStream flags. media.class is a PipeWire-level fact ("Audio/Sink",
// "Stream/Output/Audio"), so it distinguishes a *device* from an *application
// stream* unambiguously and in the direction we actually mean. The flags
// require knowing how Quickshell chose to project direction onto streams, which
// is exactly the kind of assumption that silently inverts on a version bump.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Default devices ───────────────────────────────────────────────────────
    readonly property PwNode sink:   Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // Loudest channel, not the average — see the channel block near the bottom for why
    // those differ and why this is the one everything should read.
    readonly property real volume: root.levelOf(root.sink)
    readonly property bool muted:  sink?.audio?.muted ?? false

    readonly property real micVolume: root.levelOf(root.source)
    readonly property bool micMuted:  source?.audio?.muted ?? false

    readonly property bool ready: Pipewire.ready && sink !== null

    // ── Graph ─────────────────────────────────────────────────────────────────
    function _classOf(node) {
        return (node && node.properties) ? (node.properties["media.class"] || "") : ""
    }

    // Output devices the user can pick between.
    readonly property var sinks: Pipewire.nodes.values.filter(
        n => root._classOf(n) === "Audio/Sink")

    // Input devices, minus the loopback ".monitor" nodes every sink creates —
    // those are not microphones and listing them is just noise.
    readonly property var sources: Pipewire.nodes.values.filter(
        n => root._classOf(n) === "Audio/Source" && !(n.name || "").endsWith(".monitor"))

    // ── Monitoring streams are not applications ───────────────────────────────
    // A meter is a real PipeWire stream. PwNodePeakMonitor connects one per node it
    // watches, and it lands in the graph as `Stream/Input/Audio` with
    // `application.name: "Quickshell Peak Detect"` — indistinguishable, by class alone,
    // from an app recording you.
    //
    // That made recordStreams self-feeding, and the loop is unbounded: the settings page
    // puts a meter on every recording row → the meter's own node becomes a recording row
    // → which gets a meter → which adds a node. It runs away in seconds, and the visible
    // symptom is a flood of `no global N any more` as the tracker chases nodes that
    // existed for a few milliseconds.
    //
    // Filtered on `media.category`/`stream.monitor` rather than on the display name,
    // because those are what the properties MEAN — "this stream observes, it does not
    // consume." That's true of any monitoring client, not just ours, and it's the right
    // answer for a "who is listening to me" list regardless of this bug: a meter reading
    // your mic is not an app recording you.
    function _isMonitor(node) {
        const p = node?.properties ?? {}
        return p["media.category"] === "Monitor"
            || String(p["stream.monitor"] ?? "").toLowerCase() === "true"
    }

    // Applications currently playing audio — the per-app mixer rows.
    readonly property var streams: Pipewire.nodes.values.filter(
        n => root._classOf(n) === "Stream/Output/Audio" && !root._isMonitor(n))

    // ── Capturing the OUTPUT is not recording YOU ─────────────────────────────
    // `stream.capture.sink` marks a stream that reads a sink's output rather than an
    // input device. cava sets it (that's how a visualiser sees what's playing), and so
    // does anything else that watches playback.
    //
    // Such a stream is physically incapable of hearing your microphone, so listing it
    // under "Recording" — a list whose whole purpose is answering "what is listening to
    // me" — is not just noise, it's the wrong answer. Same reasoning as _isMonitor
    // above, one layer out: both observe output, neither records you.
    function _capturesSink(node) {
        const p = node?.properties ?? {}
        return String(p["stream.capture.sink"] ?? "").toLowerCase() === "true"
    }

    // Applications currently capturing audio, one entry per app.
    //
    // ── Why this is grouped and the playback list isn't ───────────────────────
    // An app may hold several capture streams at once, and they are NOT redundant:
    // Discord runs one for your microphone and another for game audio, and it can hold
    // two of the latter simultaneously. Ungrouped, that renders as "Discord, Discord,
    // Discord" — three rows that look like a bug because nothing on them differs.
    //
    // The answer this list exists to give is "which applications can hear me", and that
    // is one row per app. The stream count rides along for the apps holding more than
    // one, so the extra streams are still visible without being three identical rows.
    //
    // `nodes` keeps ALL of an app's streams, because the meter has to watch every one —
    // metering only the first would show a flat bar whenever the live stream happened to
    // be the second.
    readonly property var recordingApps: {
        const out = []
        const byApp = ({})
        const nodes = Pipewire.nodes.values

        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i]
            if (root._classOf(n) !== "Stream/Input/Audio") continue
            if (root._isMonitor(n) || root._capturesSink(n)) continue

            // Key on the resolved app, falling back to the label so an unidentifiable
            // stream still gets its own row instead of merging with another one.
            const key = root.appIdFor(n) || root.labelFor(n)
            if (key in byApp) {
                const e = byApp[key]
                e.count++
                e.nodes.push(n)
                continue
            }
            const entry = { key: key, node: n, nodes: [n], count: 1 }
            byApp[key] = entry
            out.push(entry)
        }
        return out
    }

    // The ungrouped list, still exposed: the count in `recordingApps` is derived from it,
    // and a consumer that genuinely wants per-stream detail shouldn't have to re-filter.
    readonly property var recordStreams: Pipewire.nodes.values.filter(
        n => root._classOf(n) === "Stream/Input/Audio"
             && !root._isMonitor(n) && !root._capturesSink(n))

    // ── The tracker MUST cover every node, not the filtered lists ─────────────
    // PwObjectTracker is not just "bind the volume of the things I care about" —
    // it is what makes the registry populate AT ALL. With no tracker,
    // `Pipewire.nodes.values` is literally empty (verified: 0 nodes).
    //
    // So tracking the derived lists is circular, and silently yields nothing:
    //
    //     objects: [...root.streams]        // streams needs node.properties
    //     streams: nodes.filter(byMediaClass)  // properties needs tracking
    //                                          // tracking needs streams …
    //
    // Nothing gets tracked → no properties → no streams → nothing to track. The
    // mixer's app list could never have populated. Track everything instead; the
    // node count is small (~16 on a normal desktop) and this is the only way the
    // lists below have any data to filter.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // ══ Client identity resolution ════════════════════════════════════════════
    // Some apps put NO identity on their stream node at all. Spotify is the
    // headline case: its node carries no application.name, no process.binary,
    // nothing — just `node.name: "audio-src"` and a `client.id`. That's why it
    // showed up in the mixer as "audio-src" with a generic speaker glyph.
    //
    // The identity is there, it's just on the PipeWire CLIENT object:
    //
    //     pw-cli info 139  →  application.name         = "spotify"
    //                         application.process.binary = "spotify"
    //
    // Quickshell's Pipewire module exposes nodes, links and trackers, but there
    // is no client type — so this is genuinely unreachable from the QML API. The
    // only way to it is to ask PipeWire directly.
    //
    // `pw-dump <client.id>` returns just that one object (~2KB, versus ~380KB for
    // the whole graph). So: when a stream appears whose node has no identity, we
    // resolve its client ONCE and cache it. This is not a poll — it fires only
    // when a genuinely new unidentified stream shows up, i.e. when you start
    // playing something in an app that doesn't tag its node.
    property var _clients: ({})     // client.id → { name, binary }
    property var _queue:   []       // client.ids awaiting resolution
    property int _inFlight: -1

    function _clientIdOf(node) {
        const p = node?.properties ?? {}
        // Already self-identifying — no lookup needed.
        if (p["application.process.binary"] || p["application.name"]) return -1
        const cid = p["client.id"]
        return cid === undefined ? -1 : parseInt(cid)
    }

    onStreamsChanged: root._resolveUnknownClients()

    function _resolveUnknownClients() {
        const queued = root._queue.slice()
        for (let i = 0; i < root.streams.length; i++) {
            const cid = root._clientIdOf(root.streams[i])
            if (cid < 0) continue
            if (root._clients[cid] !== undefined) continue     // already known
            if (queued.indexOf(cid) >= 0) continue             // already queued
            queued.push(cid)
        }
        root._queue = queued
        root._pump()
    }

    function _pump() {
        if (root._inFlight >= 0 || root._queue.length === 0) return
        const next = root._queue[0]
        root._queue = root._queue.slice(1)
        root._inFlight = next
        clientProbe.command = ["pw-dump", String(next)]
        clientProbe.running = true
    }

    Process {
        id: clientProbe
        running: false
        stdout: StdioCollector { id: clientOut }

        onExited: function(code) {
            const cid = root._inFlight
            root._inFlight = -1

            if (code === 0 && cid >= 0) {
                try {
                    const objs = JSON.parse(clientOut.text)
                    for (let i = 0; i < objs.length; i++) {
                        const props = objs[i]?.info?.props ?? {}
                        if (!props["application.name"] && !props["application.process.binary"]) continue

                        // Reassign the map rather than mutating it — QML only
                        // re-evaluates bindings on a property CHANGE, and mutating
                        // an object in place doesn't fire one. Without this, the
                        // mixer would resolve the name and never redraw with it.
                        const updated = Object.assign({}, root._clients)
                        updated[cid] = {
                            name:   props["application.name"] || "",
                            binary: props["application.process.binary"] || ""
                        }
                        root._clients = updated
                        break
                    }
                } catch (e) {
                    console.warn("Audio: could not parse pw-dump for client", cid, "—", e)
                }
            }
            root._pump()   // next in queue, if any
        }
    }

    // The resolved client record for a node, or null.
    function _clientOf(node) {
        const cid = root._clientIdOf(node)
        return cid < 0 ? null : (root._clients[cid] ?? null)
    }

    // ── Naming ────────────────────────────────────────────────────────────────
    // What to call a row in the mixer.
    //
    // `application.name` is NOT the app's name — it's whatever string the audio
    // library happened to register with. Discord registers its stream as
    // "WEBRTC VoiceEngine"; Chromium-based apps do similar. Preferring it (which
    // this used to) put "WEBRTC VoiceEngine" in the mixer instead of "Discord".
    //
    // `application.process.binary` is the reliable identifier — it's the actual
    // executable, and it's what the .desktop file is named after, so it resolves
    // through the desktop-entry database to a real display name AND a real icon.
    //
    // Devices have no process at all, so they fall through to description
    // ("Arctis Nova 3 Analog Stereo"), which is exactly right for them.
    // A node with NO identity at all (Spotify) falls through to the resolved
    // client. Until that resolves — one pw-dump, typically a few ms — the row
    // shows its raw node name; it then updates in place, because `_clients` is a
    // property and the binding re-evaluates when it changes.
    function labelFor(node) {
        if (!node) return "Unknown"
        const props = node.properties || {}

        // Devices have no process; they want their description, not a lookup.
        const isStream = (props["media.class"] || "").startsWith("Stream/")

        if (isStream) {
            const appId = root.appIdFor(node)     // node identity, else client
            if (appId) {
                // Prefer the .desktop "Name=" ("Discord"). When there's no desktop
                // entry we're left with the raw binary ("spotify"), so title-case
                // it rather than putting a lowercase executable name in the UI.
                const desktopName = Icons.nameForAppId(appId)
                if (desktopName && desktopName !== appId) return desktopName
                return appId.charAt(0).toUpperCase() + appId.slice(1)
            }
        }

        return node.description
            || node.nickname
            || props["application.name"]
            || props["media.name"]
            || node.name
            || "Unknown"
    }

    // ── Short device names ────────────────────────────────────────────────────
    // `labelFor` returns node.description, which for a device is the full PipeWire
    // description and is genuinely enormous: measured on this machine at 60, 57 and 27
    // characters ("Starship/Matisse HD Audio Controller Digital Stereo (IEC958)"). That
    // is fine for a wide card and hopeless in a menu row or a pill.
    //
    // `alsa.card_name` is the same device in 12–16 characters ("HD-Audio Generic",
    // "Arctis Nova 3", "HDA ATI HDMI"), and the profile carries the rest of the meaning,
    // so the two split cleanly into a name and a qualifier instead of one long run-on.
    function shortLabelFor(node) {
        if (!node) return "None"
        const p = node.properties || {}
        return p["alsa.card_name"] || node.nickname || root.labelFor(node)
    }

    // The qualifier — "Analog Stereo", "Digital Stereo (HDMI)". Empty when the device
    // doesn't publish one, so callers can omit the separator rather than print a stray.
    function profileOf(node) {
        return (node?.properties ?? {})["device.profile.description"] || ""
    }

    // ── What KIND of thing this is ────────────────────────────────────────────
    // Beginner-facing: "HD-Audio Generic" tells you nothing about where the sound will
    // come out, but a headphone or screen icon does. Matched on the ALSA path and node
    // name, which encode the physical connection — hdmi:1, iec958:2, usb-…
    function deviceGlyph(node) {
        if (!node) return "󰓃"                                   // speaker
        const p = node.properties || {}
        const hay = ((p["api.alsa.path"] || "") + " " + (node.name || "")).toLowerCase()

        if (hay.indexOf("hdmi") >= 0)   return "󰡁"              // monitor / TV
        if (hay.indexOf("iec958") >= 0) return "󰽟"              // md-monitor_speaker (S/PDIF)
        if (hay.indexOf("usb") >= 0)    return "󰋋"              // headset
        if ((p["media.class"] || "").indexOf("Source") >= 0) return "󰍬"
        return "󰓃"
    }

    // The icon name an app declares for itself, if any. Empty string means the
    // caller should fall back to a glyph.
    function iconFor(node) {
        if (!node) return ""
        const props = node.properties || {}
        return props["application.icon_name"] || ""
    }

    // The best identifier to look this app up by in the desktop-entry database.
    // The process binary is the most reliable — "spotify", "firefox" — because
    // it's what the .desktop file is usually named after. application.name is a
    // display string ("Spotify Premium") and matches far less often.
    //
    // If the NODE carries no identity (Spotify), fall back to the resolved CLIENT
    // — see the client-resolution block above.
    function appIdFor(node) {
        if (!node) return ""
        const props = node.properties || {}

        const direct = props["application.process.binary"]
            || props["application.id"]
            || props["application.name"]
        if (direct) return direct

        const client = root._clientOf(node)
        return client ? (client.binary || client.name || "") : ""
    }

    // Resolved icon path for a stream row, or "" to fall back to a glyph.
    function iconPathFor(node) {
        return Icons.pathForStream(root.iconFor(node), root.appIdFor(node))
    }

    // ── Control ───────────────────────────────────────────────────────────────
    // Writes go straight to the node. No subprocess, no debounce needed — this
    // is a property assignment, so dragging a slider is free.
    // Both go through setNodeVolume so that devices and mixer rows share one definition
    // of what setting a level means — in particular, that it preserves balance.
    function setVolume(v)      { root.setNodeVolume(root.sink, v, false) }
    function stepVolume(delta) { root.setVolume(root.volume + delta) }
    function toggleMute()      { if (sink?.audio)   sink.audio.muted = !sink.audio.muted }

    function setMicVolume(v)   { root.setNodeVolume(root.source, v, false) }
    function toggleMicMute()   { if (source?.audio) source.audio.muted = !source.audio.muted }

    // Per-node control, for the mixer rows. Streams may exceed 1.0 (PipeWire
    // allows overamplification); devices are clamped to unity.
    //
    // This writes `volumes` (the per-channel list) rather than `volume`, and SCALES
    // the existing channels to hit the target instead of flattening them — otherwise
    // touching the volume slider would silently destroy any balance the user had set.
    // See the balance block below for why the target is the loudest channel.
    //
    // `volume` is PwNodeAudio's *average*; assigning it is a documented write, but what
    // it does to unequal channels is not something this shell should be guessing about.
    // Writing the list is unambiguous, so that's what we do whenever there IS a list.
    function setNodeVolume(node, v, allowBoost) {
        if (!node?.audio) return
        const ceiling = allowBoost ? 1.5 : 1.0
        const t = Math.max(0, Math.min(ceiling, v))

        const vols = root._volumesOf(node)
        if (vols.length < 2) { node.audio.volume = t; return }

        const peak = Math.max.apply(null, vols)
        // At zero there is no ratio left to preserve — every channel is 0, so scaling
        // can only produce 0 and the slider would appear stuck. Set them flat instead.
        node.audio.volumes = peak > 0
            ? vols.map(x => Math.min(ceiling, x * (t / peak)))
            : vols.map(() => t)
    }
    function toggleNodeMute(node) {
        if (node?.audio) node.audio.muted = !node.audio.muted
    }

    // ── Channels: level and balance ───────────────────────────────────────────
    // PwNodeAudio carries a per-channel `volumes` list (writable) alongside `channels`
    // (the speaker each entry drives). Everything above works in terms of one number,
    // so this block is what turns the list into that number and back.
    //
    // ── "Volume" is the LOUDEST channel, not the average ──────────────────────
    // PwNodeAudio.volume reads the average, and while every channel is equal — which is
    // always, until someone sets a balance — average and max are the same number, so
    // nothing observable changes for the bar pill or the OSD.
    //
    // They diverge the moment you pan. Pan hard left and the average halves: the pill
    // would drop to 50% and the glyph would step down a level, reporting that you turned
    // the volume DOWN when you moved it sideways. Worse, it feeds back — the slider
    // shows 50%, setNodeVolume scales toward 50%, and the volume walks itself to zero
    // over a few drags.
    //
    // Max has neither problem: panning doesn't change how loud the loudest channel is,
    // which is what "volume" means to a person. It's also the measure setNodeVolume
    // targets, so read and write agree and the slider stays where you put it.
    function _volumesOf(node) {
        const v = node?.audio?.volumes
        return v ? Array.prototype.slice.call(v) : []
    }

    function levelOf(node) {
        if (!node?.audio) return 0.0
        const v = root._volumesOf(node)
        return v.length ? Math.max.apply(null, v) : node.audio.volume
    }

    // Indices of the front L/R pair, or null if this node has no such pair (mono, or a
    // layout we shouldn't pretend to understand). Matched by CHANNEL, never by position:
    // index 0 is not reliably left, and on a surround layout it certainly isn't.
    function _lrIndices(node) {
        const ch = node?.audio?.channels
        if (!ch) return null
        let l = -1, r = -1
        for (let i = 0; i < ch.length; i++) {
            if (ch[i] === PwAudioChannel.FrontLeft)  l = i
            if (ch[i] === PwAudioChannel.FrontRight) r = i
        }
        return (l >= 0 && r >= 0) ? ({ l: l, r: r }) : null
    }

    // Whether a balance control means anything for the current output.
    readonly property bool canBalance: root._lrIndices(root.sink) !== null

    // −1 hard left · 0 centre · +1 hard right.
    //
    // Panning ATTENUATES the far side rather than boosting the near one: at −1 the left
    // channel keeps the level it had and the right goes silent. Boosting instead would
    // make panning a volume increase, and would clip a stream already at unity.
    function balanceOf(node) {
        const ix = root._lrIndices(node)
        if (!ix) return 0.0
        const v = root._volumesOf(node)
        const m = Math.max(v[ix.l], v[ix.r])
        if (m <= 0) return 0.0      // silent: no ratio to read, and 0/0 is not centre
        return (v[ix.r] - v[ix.l]) / m
    }

    function setBalance(node, b) {
        const ix = root._lrIndices(node)
        if (!ix || !node?.audio) return
        const bal = Math.max(-1, Math.min(1, b))
        const v = root._volumesOf(node)
        const m = Math.max(v[ix.l], v[ix.r])
        // Inverse of balanceOf: the near side holds `m`, the far side is attenuated by
        // the offset. Round-trips exactly, so the handle doesn't drift while dragging.
        v[ix.l] = m * Math.min(1, 1 - bal)
        v[ix.r] = m * Math.min(1, 1 + bal)
        node.audio.volumes = v
    }

    function centreBalance(node) { root.setBalance(node, 0) }

    // Switching the default device. `preferredDefault*` is the writable one —
    // `defaultAudioSink` is read-only and reflects what PipeWire settled on.
    function setDefaultSink(node)   { if (node) Pipewire.preferredDefaultAudioSink   = node }
    function setDefaultSource(node) { if (node) Pipewire.preferredDefaultAudioSource = node }

    // ══ Routing ═══════════════════════════════════════════════════════════════
    // Which output an individual app plays into, and how to change it.
    //
    // ── Reading is native; writing is not ─────────────────────────────────────
    // `Pipewire.linkGroups` exposes source/target as real PwNodes, so the CURRENT route
    // is a property read — no subprocess, and it updates itself when the graph changes
    // (verified: a move made externally showed up in linkGroups on the next tick without
    // anything polling). Quickshell has no API for CHANGING a route, so the write goes
    // through `pactl move-sink-input`.
    //
    // ── The ID trap ───────────────────────────────────────────────────────────
    // pactl addresses streams by `object.serial`. `PwNode.id` is the object ID, and they
    // are DIFFERENT numbers: this machine's Arctis sink is id 102, serial 4053. Passing
    // the id would address some other object entirely.
    //
    // Measured, so it's on record: the two coincide for at least one sink here (id 54,
    // serial 54), which is exactly the sort of accident that makes a wrong implementation
    // look correct in a quick test. Verified that a wrong id fails loudly —
    // `Failure: No such entity`, exit 1 — rather than silently misrouting.
    //
    // The DESTINATION is passed by NAME, not by number, because a sink's name is stable
    // and needs no mapping at all.
    // ── A stream links to MORE than its output device ─────────────────────────
    // This originally returned the first link group with a matching source, and that is
    // wrong — badly and visibly. A playing stream is commonly linked to several things at
    // once, and only one of them is where the sound is going:
    //
    //     Zen  ->  discord_capture          (Discord tapping game audio)
    //     Zen  ->  Quickshell Peak Detect   (this page's own level meter)
    //     Zen  ->  alsa_output.…Arctis…     (the actual output)
    //
    // Whichever came first won, so the UI reported Spotify as playing to "Discord" and
    // Discord as playing to "Quickshell Peak Detect". Both were real link groups; neither
    // was a sink.
    //
    // Requiring Audio/Sink makes the question match its answer — "which OUTPUT DEVICE is
    // this playing into" — instead of "what is this connected to". The meters made it
    // visible, but the bug predates them: Discord's capture links alone were enough.
    function sinkOf(stream) {
        if (!stream) return null
        const groups = Pipewire.linkGroups.values
        for (let i = 0; i < groups.length; i++) {
            const g = groups[i]
            if (g.source !== stream) continue
            if (root._classOf(g.target) !== "Audio/Sink") continue
            return g.target
        }
        return null
    }

    // One pending move at most. A move is a click, so this queue never grows — it exists
    // so that clicking twice quickly can't rewrite `command` out from under a running
    // process, which would send the second move's arguments nowhere.
    property var _moveQueue: []

    function moveStream(stream, sink) {
        if (!stream || !sink) return
        const serial = stream.properties?.["object.serial"]
        // Bail rather than guess. A stream with no serial cannot be addressed, and
        // inventing a fallback here is how the wrong object gets moved.
        if (serial === undefined || !sink.name) {
            console.warn("Audio: cannot route stream — missing serial or sink name")
            return
        }
        root._moveQueue = root._moveQueue.concat([[String(serial), sink.name]])
        root._pumpMove()
    }

    function _pumpMove() {
        if (moveProc.running || root._moveQueue.length === 0) return
        const next = root._moveQueue[0]
        root._moveQueue = root._moveQueue.slice(1)
        moveProc.command = ["pactl", "move-sink-input", next[0], next[1]]
        moveProc.running = true
    }

    Process {
        id: moveProc
        running: false
        onExited: function(code) {
            // Surfaced rather than swallowed: the failure mode is a stream that just
            // doesn't move, which is otherwise indistinguishable from a UI that didn't
            // register the click.
            if (code !== 0) console.warn("Audio: pactl move-sink-input failed, exit", code)
            root._pumpMove()
        }
    }

    // ══ Restarting the audio stack ════════════════════════════════════════════
    // The "have you tried turning it off and on again" for sound, and it genuinely is the
    // fix for a decent share of PipeWire faults — a device that won't appear, a stream
    // stuck silent, a sample-rate negotiation that wedged.
    //
    // Unit names verified against `systemctl --user list-units` on this machine rather
    // than copied from a wiki: pipewire.service, pipewire-pulse.service and
    // wireplumber.service are all loaded and running. Note `pipewire-media-session` is
    // NOT-FOUND here — wireplumber replaced it — so naming it would make the whole
    // command fail.
    //
    // ── This is disruptive, and the UI must treat it that way ─────────────────
    // Audio drops for a second or two, and applications that hold a stream may not
    // recover it — some re-open, some go silent until restarted. So the button that calls
    // this asks for confirmation; that is not ceremony.
    readonly property bool restarting: restartProc.running

    function restartStack() {
        if (restartProc.running) return
        restartProc.running = true
    }

    Process {
        id: restartProc
        running: false
        command: ["systemctl", "--user", "restart",
                  "pipewire.service", "pipewire-pulse.service", "wireplumber.service"]
        onExited: function(code) {
            if (code !== 0) console.warn("Audio: audio stack restart failed, exit", code)
        }
    }

    // ── Presentation helper ───────────────────────────────────────────────────
    // The speaker glyph for a level. Lives here so the bar pill, the mixer, and
    // any future OSD can't disagree about where the thresholds are.
    function glyph(vol, isMuted) {
        if (isMuted || vol <= 0.0) return "󰝟"
        if (vol < 0.35)            return "󰕿"
        if (vol < 0.70)            return "󰖀"
        return "󰕾"
    }
}
