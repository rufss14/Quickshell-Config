pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import "bt.js" as B
import "volumeprofiles.js" as VP
import "../config"

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
        // `?? []`: before PipeWire answers (or while it restarts) `values` is undefined, and
        // assigning that to the tracker's list logs "Unable to assign [undefined] to QList".
        objects: Pipewire.nodes?.values ?? []
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
                // Prefer the .desktop "Name=" ("Discord") — from whichever of the
                // stream's identities has an entry (see _appCandidates). When none does
                // we're left with the raw binary ("spotify"), so title-case it rather
                // than putting a lowercase executable name in the UI.
                const cands = root._appCandidates(node)
                for (let i = 0; i < cands.length; i++) {
                    const desktopName = Icons.nameForAppId(cands[i])
                    if (desktopName && desktopName !== cands[i]) return desktopName
                }
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

    // ── Every name a stream might be known by ─────────────────────────────────
    // appIdFor() returns ONE — the process binary first — and that is often not the name
    // the desktop entry answers to: Zen's binary is `zen-bin`, which matches nothing,
    // while its application.name, `Zen`, matches zen.desktop's StartupWMClass. So the
    // icon (and the display name) tries each identity in turn and takes the first that
    // resolves, instead of giving up on the first.
    function _appCandidates(node) {
        if (!node) return []
        const p = node.properties || {}
        const c = root._clientOf(node)
        const all = [p["application.process.binary"], p["application.id"], p["application.name"],
                     c ? c.binary : "", c ? c.name : "", p["node.name"]]
        return all.filter((x, i) => x && all.indexOf(x) === i)
    }

    // Resolved icon path for a stream row, or "" to fall back to a glyph.
    function iconPathFor(node) {
        const declared = root.iconFor(node)
        const cands = root._appCandidates(node)
        for (let i = 0; i < cands.length; i++) {
            const path = Icons.pathForStream(declared, cands[i])
            if (path) return path
        }
        return ""
    }

    // This app's own playback stream(s) — for a caller that already knows an app's
    // identity from somewhere else (an MPRIS player's desktopEntry, say) and wants to
    // change THAT app's volume rather than the whole sink. Matched the same way the
    // per-app mixer rows are: by appIdFor(), which already falls back through the
    // client resolver for a node (Spotify) that carries no identity of its own.
    // Streams whose app answers to a name CONTAINING `name` (any case) — for a person's "Spotify",
    // where streamsFor wants the exact id (the overview's AI, per-app volume).
    function streamsMatching(name) {
        const q = (name || "").toLowerCase()
        if (!q) return []
        return root.streams.filter(n => root._appCandidates(n).some(c => c.toLowerCase().indexOf(q) >= 0))
    }

    function streamsFor(appId) {
        const id = (appId || "").toLowerCase()
        if (!id) return []
        // Any name the stream answers to, not only appIdFor()'s first pick: Zen's MPRIS
        // desktop entry is "zen" while its stream's binary is "zen-bin" — only its
        // application.name ("Zen") matches, and that is in _appCandidates().
        return root.streams.filter(n => root._appCandidates(n).some(c => c.toLowerCase() === id))
    }

    // ── A scroll step lands on a multiple of 5 ────────────────────────────────
    // The number scrolling starts FROM isn't always round — a per-app PipeWire stream
    // sets its own initial level, and nothing requires that to be a multiple of 5. Adding
    // a flat 5% to 43% forever produces 48, 53, 58… never round, because the step
    // preserves whatever odd remainder it started with. That's what made landing on a
    // specific number a fight.
    //
    // Snapping to the grid FIRST, in the direction being scrolled, fixes the remainder in
    // exactly one step: 43 scrolled up goes to 45, not 48; scrolled down goes to 40, not
    // 38. An already-round volume (45) is untouched by the snap and just moves by 5, same
    // as always. Direction-aware on purpose — "in the direction scrolled" means a scroll
    // up never LOWERS the volume to snap it, which is the one thing that would make the
    // fix feel worse than the problem.
    //
    // Whole percent, not the raw fraction: volumes are noisy at the float level (PipeWire
    // rounding, a per-channel average) in ways that don't matter to a person reading a
    // percentage, and comparing floats for "already a multiple of 5" is exactly the kind
    // of check that quietly stops working the day the fraction is 0.4500000001.
    function steppedLevel(current, up) {
        const pct  = Math.round(current * 100)
        const grid = 5
        const rem  = ((pct % grid) + grid) % grid   // never negative
        const next = rem === 0 ? pct + (up ? grid : -grid)
                                : up ? pct + (grid - rem) : pct - rem
        return next / 100
    }

    // ── Control ───────────────────────────────────────────────────────────────
    // Writes go straight to the node. No subprocess, no debounce needed — this
    // is a property assignment, so dragging a slider is free.
    // Both go through setNodeVolume so that devices and mixer rows share one definition
    // of what setting a level means — in particular, that it preserves balance.
    // `boost` lets the output past unity (to boostCeiling) — the mixer's opt-in; every other
    // caller leaves it off, so a scroll on the bar pill still stops at 100%.
    function setVolume(v, boost) { root.setNodeVolume(root.sink, v, boost === true) }
    // `delta`'s SIGN is what matters — every caller in this shell only ever passes ±0.05
    // (one nominal scroll step), and the actual distance moved now comes from
    // steppedLevel() rather than from delta's magnitude. Kept as a delta rather than an
    // `up` boolean so neither existing call site had to change shape for this.
    function stepVolume(delta) { root.setVolume(root.steppedLevel(root.volume, delta > 0)) }
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
        let ceiling = allowBoost ? root.boostCeiling : 1.0
        // A device's own limit (see the safe-volume block) beats boost.
        const cap = root.capOf(node)
        if (cap > 0) ceiling = Math.min(ceiling, cap)
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
    // ══ A media player's OWN volume, and the named levels ═════════════════════
    // A player has two volumes: its own (MPRIS `Volume` — the slider inside Spotify), and its
    // PipeWire stream, which the player writes whenever it likes. Spotify rewrites the stream
    // on a track change, so a level set on the STREAM did not last the song; its own volume
    // is the one it keeps. So the player's own is what is read and written whenever the
    // player has one (`volumeSupported`), and the stream only for a player that doesn't.
    //
    // PAST 100% there is no "own" volume — MPRIS stops at 1.0 — so the extra is the STREAM's, over-
    // amplified up to the ceiling, with the player's own volume at full. The one level a panel
    // shows is therefore the stream's when it is lifted, the player's otherwise.
    //
    // `appId` is the player's desktop entry, for finding that stream (streamsFor).
    function hasPlayerVolume(player, appId) {
        return (player?.volumeSupported ?? false) || root.streamsFor(appId).length > 0
    }
    function playerLevel(player, appId) {
        const s = root.streamsFor(appId)[0]
        const sl = s ? root.levelOf(s) : 0
        if (player?.volumeSupported) return sl > VP.UNITY ? sl : player.volume
        return sl
    }
    // `boost` allows the level past 100% (to boostCeiling): the panel's bar once Boost has
    // unlocked it. Without it the level stops at the player's own full.
    function setPlayerLevel(player, appId, v, boost) {
        const t = Math.max(0, Math.min(boost === true ? root.boostCeiling : 1, v))
        const s = root.streamsFor(appId)[0]
        if (player?.volumeSupported) {
            player.volume = Math.min(1, t)
            if (!s) return
            if (t > 1) {
                // What the stream was before the lift, for the way back (only the first lift).
                if (root.levelOf(s) <= VP.UNITY) root._streamBeforeBoost = root.levelOf(s)
                root.setNodeVolume(s, t, true)
                root._holdBoostAt(appId, t)
            } else if (root.levelOf(s) > VP.UNITY) {
                // Coming back under 100%: the stream returns to what it was.
                root.setNodeVolume(s, root._streamBeforeBoost > 0 && root._streamBeforeBoost <= 1
                                      ? root._streamBeforeBoost : 1, true)
                root._holdBoostAt("", 0)
            }
        } else if (s) {
            root.setNodeVolume(s, t, boost === true)
            root._holdBoostAt(t > 1 ? appId : "", t)
        }
    }

    // ── The ceiling ───────────────────────────────────────────────────────────
    // The loudest anything goes — the mixer's boost on the output and on an app, and the Boost
    // profile on a player. Past 130% it is distortion rather than volume. One number
    // (volumeprofiles.js), so the mixer's fader range, its clamp and the profile cannot differ.
    readonly property real boostCeiling: VP.CEILING

    // The player's stream level before a Boost lifted it, to give back (-1 = none kept). In
    // memory only: a reload in between loses it and the stream returns to unity, never louder.
    property real _streamBeforeBoost: -1

    // Which profile (volumeprofiles.js PROFILES) this player's levels amount to, or -1. A
    // player with no volume of its own has one level, its stream's; up to unity that is the
    // player level, past it that is the boost.
    function volumeProfileOf(player, appId) {
        const s = root.streamsFor(appId)[0]
        const sl = s ? root.levelOf(s) : 1
        const own = player?.volumeSupported ?? false
        return VP.detect(own ? player.volume : Math.min(1, sl), sl)
    }

    // Soft, medium and max set the player's own volume — and only that, but for putting a
    // boosted stream back. Boost sets it to full AND over-amplifies ITS stream to the ceiling,
    // remembering what the stream was. The output device is never touched: this is one
    // player's volume, and nothing else on the machine gets louder or quieter for it.
    function applyProfile(player, appId, index) {
        const s = root.streamsFor(appId)[0]
        const p = VP.plan(index, s ? root.levelOf(s) : 1, root._streamBeforeBoost)
        // Choosing a level is choosing to hear it.
        if (s?.audio?.muted) s.audio.muted = false

        if (player?.volumeSupported) {
            player.volume = p.player
            if (s && p.stream !== null) root.setNodeVolume(s, p.stream, true)
        } else if (s) {
            // No volume of its own: the stream carries the level, boosted or not.
            root.setNodeVolume(s, VP.PROFILES[index].boost ? p.stream : p.player, true)
        }
        if (p.remember !== null) root._streamBeforeBoost = p.remember

        // A boost has to be held: Spotify writes its stream back to unity on a track change.
        if (VP.PROFILES[index]?.boost) root._holdBoostAt(appId, root.boostCeiling)
        else                           root._holdBoostAt("", 0)
    }

    // ── Holding a boost ───────────────────────────────────────────────────────
    // The stream is the player's to rewrite, and Spotify does on a track change and when its
    // stream is recreated (pause → play): the boost would silently end at the next song. So a
    // boost chosen here is re-asserted after those — and ONLY after those, and only when the
    // stream has come back at exactly unity, which is what Spotify's rewrite looks like. A
    // level the user then set themselves (the mixer, the player's own slider) is never fought.
    property string _boostApp: ""
    property real   _boostLevel: 0
    function _holdBoostAt(appId, level) {
        root._boostApp = (appId || "").toLowerCase()
        root._boostLevel = level
    }
    readonly property var _boostPlayer: root._boostApp === "" ? null
        : (Mpris.players.values.find(p => (p.desktopEntry ?? "").toLowerCase() === root._boostApp) ?? null)

    Connections {
        target: root._boostPlayer
        ignoreUnknownSignals: true
        function onTrackChanged()         { holdBoost.restart() }
        function onPlaybackStateChanged() { holdBoost.restart() }
    }
    Connections {
        target: root
        function onStreamsChanged() { if (root._boostApp !== "") holdBoost.restart() }
    }
    // After the player has finished rewriting, not while it is.
    Timer {
        id: holdBoost
        interval: 800
        onTriggered: {
            if (root._boostApp === "") return
            const s = root.streamsFor(root._boostApp)[0]
            if (!s) return
            if (Math.abs(root.levelOf(s) - 1.0) < 0.02) root.setNodeVolume(s, root._boostLevel, true)
        }
    }

    // ══ Safe volume, and a level per device ═══════════════════════════════════
    // Two small preferences keyed by the sink's node NAME (Config.audioDeviceCaps /
    // audioDeviceLevels): a limit — the loudest an output may be set to, because
    // headphones plugged in after speakers at 80% is how ears get hurt — and the level
    // it was last left at, put back when the output becomes the default.
    //
    // The limit is enforced in setNodeVolume (every write from this shell) AND here, on
    // the default sink's volume changing, so a write from outside the shell — a media
    // key bound to wpctl — is pulled back too. It only ever lowers.
    //
    // 0 means "no limit"; a limit is a fraction in (0, 1).
    function capOf(node) {
        const c = Config.audioDeviceCaps[node?.name ?? ""]
        return (typeof c === "number" && c > 0 && c < 1) ? c : 0
    }

    // frac >= 1 (or 0) removes the limit.
    function setCap(node, frac) {
        if (!node?.name) return
        const m = Object.assign({}, Config.audioDeviceCaps)
        if (!(frac > 0) || frac >= 0.995) delete m[node.name]
        else m[node.name] = Math.max(0.1, Math.min(0.99, frac))
        Config.audioDeviceCaps = m
        root._enforceCap()
    }

    function _enforceCap() {
        const cap = root.capOf(root.sink)
        if (cap > 0 && root.volume > cap + 0.005) root.setNodeVolume(root.sink, cap, false)
    }
    onVolumeChanged: { root._enforceCap(); root._noteLevel() }

    // ── Memory ────────────────────────────────────────────────────────────────
    // The level is tagged with the device it was read from AT THE TIME, and committed
    // after a pause: a switch can land inside the debounce, and committing the new
    // device's native level under its name would overwrite the very memory the
    // restore is about to read. Kept up to the boost ceiling; whether it is put back
    // above 100% is decided at restore time by the boost switch (Config.mixerBoost).
    readonly property string _sinkName: root.sink?.name ?? ""
    property string _pendName: ""
    property real   _pendLevel: 0

    function _noteLevel() {
        if (!Config.audioRememberLevels || !Config.prefsLoaded || root._sinkName === "") return
        root._pendName  = root._sinkName
        root._pendLevel = Math.min(root.boostCeiling, root.volume)
        commitTimer.restart()
    }

    function _restoreLevel() {
        if (!Config.audioRememberLevels || !Config.prefsLoaded || !root.sink) return
        const v = Config.audioDeviceLevels[root._sinkName]
        if (typeof v === "number") root.setNodeVolume(root.sink, v, Config.mixerBoost)   // setNodeVolume applies the ceiling and the limit
    }

    on_SinkNameChanged: restoreTimer.restart()

    // Config loads asynchronously: a restore before it lands would find nothing.
    Connections {
        target: Config
        function onPrefsLoadedChanged() { if (Config.prefsLoaded) restoreTimer.restart() }
    }

    // Long enough for the new node's audio properties to be tracked and readable.
    Timer { id: restoreTimer; interval: 400; onTriggered: root._restoreLevel() }
    Timer {
        id: commitTimer
        interval: 800
        onTriggered: {
            if (root._pendName === "") return
            const m = Object.assign({}, Config.audioDeviceLevels)
            m[root._pendName] = root._pendLevel
            Config.audioDeviceLevels = m
        }
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
    // The same question for any output, not only the default.
    function canBalanceNode(node) { return root._lrIndices(node) !== null }

    // ── Whether a PwNodePeakMonitor can actually meter this node ───────────────
    // Some app streams (Spotify's own client, at least) publish per-channel VOLUMES
    // without ever giving them a position — `node.audio.channels` comes back
    // `[Unknown, Unknown]` for a stereo stream. PwNodePeakMonitor's own capture side
    // still negotiates a real FrontLeft/FrontRight format, so every process callback
    // fails to match either side, logs a `qCCritical` in quickshell.service.pipewire.peak,
    // and never calls back with a level — the meter sits dead at zero while the log
    // fills up in real time. Gate metering on this instead: a hardware sink/source
    // always has real positions, so this is a no-op there.
    function hasKnownChannels(node) {
        const ch = node?.audio?.channels
        if (!ch || ch.length === 0) return false
        for (let i = 0; i < ch.length; i++) {
            if (ch[i] === PwAudioChannel.Unknown) return false
            // A MONO node, too: the capture stream asks for FrontLeft/FrontRight, and Quickshell's peak
            // callback fails on every cycle with "PwNode … is missing channels present in capture stream" —
            // the same dead meter and the same log flood as an Unknown position. A mono source (a headset
            // mic, a virtual device) just has no meter.
            if (ch[i] === PwAudioChannel.Mono) return false
        }
        return true
    }

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
    // ── A Bluetooth device's sink ─────────────────────────────────────────────
    // BlueZ and PipeWire each know half: BlueZ has the device, PipeWire the node its
    // audio flows through. The join is the MAC — bluez5 stamps `api.bluez5.address`
    // on every node it creates (SPA_KEY_API_BLUEZ5_ADDRESS, spa/utils/keys.h). The
    // node name (`bluez_output.F8_5C_…`) carries it too, underscored, and is the
    // fallback in case a session manager's rule rewrites the properties.
    function bluetoothSinkFor(address) {
        if (!address) return null
        const mac = address.toUpperCase()
        const underscored = mac.replace(/:/g, "_")
        for (const n of root.sinks) {
            const p = n.properties || {}
            if ((p["api.bluez5.address"] || "").toUpperCase() === mac) return n
            if ((n.name || "").toUpperCase().indexOf(underscored) >= 0) return n
        }
        return null
    }

    // The negotiated codec, spelled the way people know it. It's the one quality
    // fact a Bluetooth headset has — SBC against LDAC is audible — and the only
    // place to read it is this property. "" when it isn't a bluez5 node. The name
    // table is bt.js's, shared with the codec chips below.
    function bluetoothCodecOf(node) {
        return B.codecLabel((node?.properties ?? {})["api.bluez5.codec"] || "")
    }

    // ── A Bluetooth card: music or calls, and which codec ─────────────────────
    // Quickshell exposes nodes, not cards, so the card's profiles come from one
    // `pactl -f json list cards` read (bt.js parseCard — tested). PipeWire offers a
    // profile per (mode, codec), so the same read and one `set-card-profile` cover
    // both the Music/Calls switch and the codec chips.
    //
    // Asked on demand, never polled: the panel's hero calls watchBluetoothCard() when
    // its device changes, and a profile switch recreates the sink node — the hero sees
    // a new node and asks again. `btCard` is null until the answer lands, or when the
    // device has no audio card at all.
    property string btCardAddress: ""
    property var    btCard: null
    property string _btCardsText: ""

    function watchBluetoothCard(address) {
        if (root.btCardAddress !== (address || "")) root.btCard = null
        root.btCardAddress = address || ""
        root.refreshBluetoothCard()
    }
    function refreshBluetoothCard() {
        if (root.btCardAddress === "") { root.btCard = null; return }
        root._btCardProc.running = false
        root._btCardProc.running = true
    }

    // "music" | "calls"
    function setBluetoothMode(kind) {
        const prof = B.profileFor(root._btCardsText, root.btCardAddress, kind)
        if (prof !== "" && root.btCard) root._setCardProfile(root.btCard.card, prof)
    }
    // A profile from btCard.codecs — checked against that list, so only a name the
    // card itself offered ever reaches pactl.
    function setBluetoothCodec(profile) {
        if (!root.btCard || !root.btCard.codecs.some(c => c.profile === profile)) return
        root._setCardProfile(root.btCard.card, profile)
    }
    function _setCardProfile(card, profile) {
        root._btSetProc.command = ["pactl", "set-card-profile", card, profile]
        root._btSetProc.running = false
        root._btSetProc.running = true
    }

    property Process _btCardProc: Process {
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._btCardsText = text
                root.btCard = B.parseCard(text, root.btCardAddress)
            }
        }
    }
    property Process _btSetProc: Process {
        onExited: function (code) {
            if (code !== 0) console.warn("Audio: pactl set-card-profile failed, exit", code)
            root.refreshBluetoothCard()
        }
    }

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

    // Every playing app onto one output. Skips what's already there, so it is a no-op
    // rather than a burst of redundant pactl calls.
    function moveAllStreams(sink) {
        if (!sink) return
        for (const s of root.streams)
            if (root.sinkOf(s) !== sink) root.moveStream(s, sink)
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

    // ── Presentation helpers ──────────────────────────────────────────────────
    // Linear amplitude → a bar you can read. `peak` (from PwNodePeakMonitor) is
    // linear, and plotting it linearly makes a useless meter: music mastered at a
    // comfortable −20 dBFS reads as 0.1, so the bar sits almost flat and only
    // twitches on the loudest transients. Hearing is logarithmic, so the meter is
    // too — −60 dBFS (near silence) to 0 dBFS (full scale) mapped across the bar.
    //
    // Was a page-local function on SoundPage (the settings mixer's peak meters);
    // promoted here once the bar's volume pill needed the identical mapping for
    // its own peak-driven wave, rather than a second copy of the -60..0 dB curve.
    function meterLevel(peak) {
        if (!peak || peak <= 0) return 0
        const db = 20 * Math.log10(peak)
        return Math.max(0, Math.min(1, (db + 60) / 60))
    }

    // The speaker glyph for a level. Lives here so the bar pill, the mixer, and
    // any future OSD can't disagree about where the thresholds are.
    function glyph(vol, isMuted) {
        if (isMuted || vol <= 0.0) return "󰝟"
        if (vol < 0.35)            return "󰕿"
        if (vol < 0.70)            return "󰖀"
        return "󰕾"
    }

    // Two states, not four: the icon only answers "is anything coming out at all" (the
    // level is the slider beside it). Material Symbols names (2026-10-31; they were the
    // Fluent set's headphones / headphones-sound-wave): silent is the crossed-out headset,
    // so mute reads by shape as well as by VolumePill's danger tint.
    function iconName(vol, isMuted) {
        if (isMuted || vol <= 0.0) return "headset_off"
        return "headphones"
    }
}
