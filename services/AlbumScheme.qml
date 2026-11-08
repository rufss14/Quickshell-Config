pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "../config"
import "mediasource.js" as MediaSource
import "albumscheme.js" as Decide

// ── AlbumScheme ───────────────────────────────────────────────────────────────
// The shell wears the cover of whatever is playing, and hands the colours back to the
// wallpaper when the music stops.
//
// This is the big sibling of AlbumArt.qml. That one dresses the media CARDS in three
// colours off the cover; this one derives a whole eighteen-slot palette
// (`album-colors.py --scheme`) and puts it on the entire shell.
//
// ── Two reaches, and only one of them touches the disk ────────────────────────
// Shell only (the default): the palette is pushed into `Colors.overlay`, which outranks
// colors.json in memory. A track change is a repaint. Switching it off is one
// assignment and the wallpaper's palette is simply back — nothing was ever lost.
//
// System-wide (`Config.albumSchemeSystem`): colors.json is written and reload-theme.sh
// pushes it to GTK, Qt, kitty, cava and Hyprland, exactly as a wallpaper change does.
// Consistent everywhere, and much more expensive — that path flips the global GTK theme
// and signals every terminal, which is a fine thing to do occasionally and a lot to do
// every three minutes. It is opt-in for that reason, and reverting from it costs a
// regeneration from the wallpaper rather than dropping an overlay.
//
// ── It has to work with the overlay closed ────────────────────────────────────
// Player selection used to live in OverviewNowPlaying, which is inside the lazy-loaded
// overview — so the answer to "what is playing" only existed while the overlay was
// open. That is correct for a card and useless here. The rule moved to
// `mediasource.js:pickPlayer()`, shared by both, and this singleton watches Mpris
// directly.
//
// ── A third reach: only some workspaces ──────────────────────────────────────
// `Config.albumScope` narrows WHERE it goes: "workspaces" (a chosen set) or "spotify" (the one
// Spotify's window is on). Then nothing global is touched — `Colors.overlay` stays empty and
// colors.json is never written; the merged palette is published as `scopedPalette` and
// services/WorkspaceTheme dresses just those workspaces with it: the shell on the screen showing
// one, and the windows, terminals, Discord and Spotify on it. (Whether it is on screen depends on
// whether you are on that workspace; the apps wear it wherever you are.) "Everything"
// (systemWide) can't be narrowed — it IS the global files — so it is ignored under a scope.
//
// ── Everything you pinned still wins ──────────────────────────────────────────
// The album palette is merged UNDER `ColorScheme.overrides`, so a colour you pinned by
// hand stays pinned while the music re-themes the rest. That matches what the
// system-wide path does anyway (reload-theme.sh merges overrides last), and the
// alternative was two reaches that disagreed about whose colour won.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Is anything actually being followed ───────────────────────────────────
    readonly property bool enabled: Config.albumScheme
    // Narrower than the whole shell: see "A third reach" above.
    readonly property bool scoped: Config.albumScope === "workspaces" || Config.albumScope === "spotify"
    readonly property bool systemWide: Config.albumSchemeSystem && !root.scoped
    // The palette a scoped reach publishes for WorkspaceTheme (null while it isn't showing, or global).
    property var scopedPalette: null

    // Locked: the album palette wins while the music plays — a full override set or an
    // applied scheme no longer stops it, and it merges ON TOP of held colours. See
    // Config.albumSchemeLock.
    readonly property bool locked: Config.albumSchemeLock

    property var  player: null
    readonly property bool playing: root.player?.isPlaying ?? false

    // The cover the palette is derived from. MPRIS's own url — NOT AlbumArt.hiRes(),
    // which exists to draw a sharp picture. Downloading 437KB instead of 89KB to
    // quantise a 128px thumbnail would be pure waste, the same reasoning AlbumArt
    // records for its own extraction.
    readonly property string artUrl: root.player?.trackArtUrl ?? ""

    // Only sources that reliably hand over real per-track cover art. The allowlist
    // lives in mediasource.js next to the lyrics one — YouTube's "cover" is a video
    // thumbnail, and letting a black frame or a face pick the desktop's accent is
    // precisely what this must not do.
    readonly property bool eligible: root.player ? MediaSource.schemeEligible(root.player) : false

    // ── What the shell is currently wearing, and why it isn't ─────────────────
    // `reason` is the diagnostic. Every failure mode here is invisible from outside —
    // an ineligible player, a colourless sleeve, a cover that 404'd and a palette held
    // by pins all look identical: the desktop simply doesn't change. The lyrics work in
    // this repo cost four rounds to the same shape of problem, so the explanation is
    // built in rather than inferred later.
    property bool   active: false
    property string reason: "off"
    property string appliedUrl: ""
    property var    palette: null
    readonly property real saturation: root.palette?.sat ?? 0

    readonly property string reasonText: {
        switch (root.reason) {
        case "off":        return "Album colours are off."
        case "no-player":  return "Nothing is playing."
        case "stopped":    return "Playback stopped — the wallpaper's colours are back."
        case "ineligible": return "This source doesn't provide reliable cover art, so its "
                                + "colours are ignored."
        case "no-art":     return "This track has no cover art."
        case "failed":     return "The cover's colours could not be read."
        case "held":       return "Your pinned colours cover the whole palette, so the album "
                                + "has nothing left to change."
        case "active":     return "Following the album cover."
        default:           return root.reason
        }
    }

    // Every slot pinned by hand means the album can never show. Same test
    // apply-wallpaper.sh makes before it bothers running pywal at all.
    readonly property bool fullyHeld: {
        const o = ColorScheme.overrides ?? ({})
        const have = Object.assign({}, o.special ?? ({}), o.colors ?? ({}))
        if (have.background === undefined || have.foreground === undefined) return false
        for (let i = 0; i < 16; i++) if (have["color" + i] === undefined) return false
        return true
    }

    // ── Player tracking ───────────────────────────────────────────────────────
    // No pin: the desktop's colour follows what is PLAYING, not what some tile happens
    // to be displaying. `pin` is a per-card display preference and has no business
    // deciding the shell's palette.
    function _repick() { root.player = MediaSource.pickPlayer(Mpris.players.values, root.player, "") }

    Component.onCompleted: root._repick()

    Connections {
        target: Mpris.players
        function onValuesChanged() { root._repick() }
    }

    // Each player's own isPlaying, or a pause in a background player never re-picks.
    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { root._repick() }
        }
    }

    // ── The grace period ──────────────────────────────────────────────────────
    // The gap between two tracks is a moment where `isPlaying` goes false, `trackArtUrl`
    // goes empty, and — while a player is starting or stopping — the pick can land
    // somewhere ineligible. Acting on any of those immediately strobes the whole desktop
    // back to the wallpaper and forward again on every song boundary. On the system-wide
    // reach that is not a flicker but a full pywal regeneration and app repaint, twice,
    // between two tracks off the same record.
    //
    // So every transient reason to STOP showing an album palette is held for this long
    // and re-evaluated. Only turning the feature off is immediate, because that one is
    // the user asking and they should see it happen.
    readonly property int graceMs: 20000

    // ── The startup window ────────────────────────────────────────────────────
    // A restored palette is put up before MPRIS has reported anything, held under the
    // same "wait and see" rule. MPRIS is usually quick, but a cold boot — or a hot
    // reload while several players exist — can take a good deal longer than a couple
    // of seconds to list players and fill in metadata. Too short and the restored
    // palette drops before the music is readable; the `startupSettle` poll below then
    // has to bring it back, which is a visible flash. So `grace` re-arms this for the
    // poll's whole window: nothing playing → it clears once, when the poll ends; music
    // IS playing → the poll catches it well before then and `_push()` stops the timer.
    // The value only sets how often a still-restoring palette is re-checked.
    readonly property int restoreGraceMs: 8000
    property bool _restoring: false

    // MPRIS can populate slowly at launch, and the signal that would re-run _settle()
    // (a player's isPlaying / trackArtUrl changing) may fire before this singleton has
    // wired its Connections, or not at all if the player came up already-playing. So
    // re-settle on a timer for the first stretch after start — a no-op the moment the
    // answer is stable. This is what makes "album colours are on" take effect on a
    // reboot without opening any panel.
    Timer {
        id: startupSettle
        interval: 1500
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            root._settle()
            if (++startupSettle.ticks >= 10) startupSettle.stop()   // ~15s
        }
    }

    Timer {
        id: grace
        interval: root._restoring ? root.restoreGraceMs : root.graceMs
        // Re-evaluate rather than clear outright: the reason may well have resolved
        // itself, which is the entire point of waiting.
        //
        // The flag is what makes this terminate. Without it _settle() calls _hide(),
        // which sees the timer idle and starts it again — a grace period that renews
        // itself forever and never reverts anything.
        onTriggered: {
            // During the startup poll a RESTORED palette is held right through the
            // window: MPRIS may still be coming up, and dropping the colours only to
            // bring them back a tick later is the flash the restore exists to avoid.
            // Once the poll ends (music never arrived) this expires normally.
            if (root._restoring && startupSettle.running) { grace.restart(); return }
            root._graceExpired = true
            root._settle()
            root._graceExpired = false
        }
    }

    property bool _graceExpired: false

    onPlayingChanged: root._settle()
    // Turning it on (or Config finishing its async load with it already on) tries the
    // restore; turning it off just settles, which clears.
    onEnabledChanged: root.enabled ? root._restore() : root._settle()
    onArtUrlChanged: root._settle()
    onEligibleChanged: root._settle()
    // Lock toggled mid-playback: re-decide (a fully-held palette may now show) and
    // re-merge (album moves above/below the held colours).
    onLockedChanged: { if (root.active) root._push(); root._settle() }

    // The palette depends on the mode, so flipping light/dark has to re-derive rather
    // than keep showing a dark palette in light mode.
    Connections {
        target: Config
        function onThemeModeChanged() { root._settle() }

        // ── Narrowing the reach has to clean up after itself ──────────────────
        // Going system-wide → shell-only leaves the album's palette sitting in
        // colors.json, because that is where the system-wide path put it. _settle()
        // alone would happily carry on — it would set the in-memory overlay and report
        // everything fine, while the file underneath stayed the last track's colours
        // forever, surviving reboots, with nothing on screen saying so.
        function onAlbumSchemeSystemChanged() {
            // Under a scope the flag does nothing (there is no global file to clean up).
            if (root.active && !Config.albumSchemeSystem && !root.scoped) {
                Colors.overlay = ({})
                ColorScheme.regenerate()
            }
            root._settle()
        }

        // ── Moving between reaches has to clean up after the one it leaves ────
        // Global → scoped: the overlay is dropped, and if the system-wide reach had written the album
        // into colors.json the wallpaper's palette has to be derived back. Scoped → global: _push()
        // puts it up in the new reach.
        function onAlbumScopeChanged() { root._rescope() }
    }

    function _rescope() {
        if (!root.active) { root._settle(); return }
        Colors.overlay = ({})
        root.scopedPalette = null
        if (root.scoped && Config.albumSchemeSystem) ColorScheme.regenerate()
        root._push()
    }

    // Pinning a colour while the music is playing has to re-merge, or the pin does not
    // appear until the next track.
    Connections {
        target: ColorScheme
        function onOverridesChanged() { if (root.active) root._push() }
    }

    // ── The one place that decides what should be on screen ───────────────────
    // Everything above funnels here rather than each calling _apply()/_clear() itself.
    // The decision itself is in albumscheme.js so it can be tested against sequences
    // (`bun scripts/test-albumscheme.js`); this half only carries it out.
    function _settle() {
        const d = Decide.decide({
            enabled:      root.enabled,
            hasPlayer:    !!root.player,
            playing:      root.playing,
            eligible:     root.eligible,
            hasArt:       root.artUrl !== "",
            // Locked, the album ignores a fully-pinned palette instead of standing down.
            fullyHeld:    root.fullyHeld && !root.locked,
            cached:       root._cache[root._key(root.artUrl)],
            active:       root.active,
            graceExpired: root._graceExpired
        })

        switch (d.action) {
        case "show": {
            grace.stop()
            // Already showing this exact palette (the startupSettle poll calls this
            // every couple of seconds) — don't re-push, which rewrites the state file
            // and re-assigns Colors.overlay on every tick.
            const hit = root._cache[root._key(root.artUrl)]
            if (root.active && root.palette === hit) break
            root.palette = hit
            root._push()
            break
        }
        case "extract":
            root._extract(root.artUrl)
            break
        case "hold":
            // Keep the current palette on screen and wait the reason out.
            root.reason = d.reason
            if (!grace.running) grace.start()
            break
        default:
            grace.stop()
            root._clear(d.reason)
        }
    }

    // ── Reload ────────────────────────────────────────────────────────────────
    // Re-derive the palette from the cover on screen and put it back up — what the colours panel's
    // refresh does WHILE THE ALBUM IS DRIVING THE SHELL. That button's usual job (rebuild from the
    // wallpaper) would hand the shell back to the wallpaper: in the shell-only reach the overlay would
    // sit over a colour file that just changed, and in the system-wide one it OVERWRITES colors.json,
    // which is the album's palette, with the wallpaper's — and nothing here would re-push it.
    // Forgets the cached palette first, so it is a real re-extraction (a new mode, an edited cover).
    // Returns false when there is nothing to reload (not active, or no cover).
    readonly property bool extracting: proc.running
    function reload() {
        if (!root.active || root.artUrl === "") return false
        delete root._cache[root._key(root.artUrl)]
        root._extract(root.artUrl)
        return true
    }

    function _key(url) {
        return url + "|" + (Config.themeMode === "light" ? "l" : "d")
    }

    // ── Extraction ────────────────────────────────────────────────────────────
    property var _cache: ({})       // key → palette, or null for "declined"
    property string _pending: ""

    readonly property string scriptPath: Quickshell.shellPath("scripts/album-colors.py")

    function _extract(url) {
        // Already working on this exact cover. Restarting would throw away a run that
        // is about to answer and spawn another for the same result — and _settle() is
        // called often enough (every metadata field a player touches) that this is the
        // common case, not the rare one.
        if (proc.running && root._pending === url) return

        // Stopped BEFORE the command is reassigned: changing a Process's command while
        // it runs is undefined, and this genuinely happens — skipping tracks faster
        // than an extraction completes is one keypress.
        proc.running = false
        root._pending = url
        proc.command = ["python3", root.scriptPath, "--scheme"]
            .concat(Config.themeMode === "light" ? ["--light"] : [])
            .concat([url])
        proc.running = true
    }

    Process {
        id: proc
        running: false
        property string out: ""

        stdout: SplitParser {
            onRead: function(line) { proc.out += line }
        }

        onExited: {
            const text = proc.out
            const url = root._pending
            proc.out = ""

            // The track moved on while we were working. Dropping the result is right;
            // _settle() has already been called for whatever is playing now.
            if (url !== root.artUrl) return

            let d = null
            try {
                d = JSON.parse(text)
            } catch (e) {
                console.warn("[AlbumScheme] palette output was not JSON —", e)
            }

            if (!d || !d.ok) {
                root._cache[root._key(url)] = null
                root._clear("failed")
                return
            }

            // ── A colourless sleeve is NOT a failure ──────────────────────────
            // This used to decline any cover whose saturation fell under a threshold,
            // on the reasoning that a grey sleeve has no hue worth trusting. That was
            // the wrong call and it is gone: black and white are colours, and a
            // monochrome cover should give a monochrome desktop rather than silently
            // leaving the wallpaper's palette up with no visible reason.
            //
            // What made it safe to remove is that album-colors.py no longer invents a
            // hue for such a cover — it works in Lab, where a colourless pixel has no
            // chroma to amplify, so a grey sleeve now yields greys instead of the
            // confident lilac the old HLS maths produced. The threshold was guarding
            // against that bug, not against greyness.
            root._cache[root._key(url)] = d
            root.palette = d
            root._push()
        }
    }

    // ── Pushing it out ────────────────────────────────────────────────────────
    // Overrides merge LAST, so a colour pinned by hand outranks the album — the same
    // order reload-theme.sh uses, so the two reaches cannot disagree about who wins.
    function _merged() {
        const p = root.palette
        if (!p) return ({})
        const o = ColorScheme.overrides ?? ({})
        // Unlocked: pins on top (a colour you set by hand wins while the music re-themes
        // the rest). Locked: the album on top — nothing overwrites it until playback stops.
        if (root.locked)
            return ({
                special: Object.assign({}, o.special ?? ({}), p.special),
                colors:  Object.assign({}, o.colors  ?? ({}), p.colors)
            })
        return ({
            special: Object.assign({}, p.special, o.special ?? ({})),
            colors:  Object.assign({}, p.colors,  o.colors  ?? ({}))
        })
    }

    // ── Surviving a restart ───────────────────────────────────────────────────
    // The palette on screen is remembered, and put back the instant the shell starts.
    //
    // Without it, every reload dropped to the wallpaper's colours and stayed there
    // until MPRIS had repopulated and an extraction had run — a visible flash on a
    // hot reload, and a wasted download of a cover we had already read.
    //
    // The shell-only reach puts the overlay straight back; the system-wide reach only
    // needs its `active` flag restored so `_settle()` can regenerate the wallpaper's
    // palette if the music turns out to have stopped (colors.json still holds the last
    // album's colours until then).
    //
    // ── The Config-load race ─────────────────────────────────────────────────
    // This can fire before Config's async JSON has loaded, when albumScheme still
    // reads its default (false). So the restore is retried on the Config load — and
    // `startupSettle` polls _settle() regardless, so a missed restore still resolves.
    JsonStore {
        id: store
        path: Quickshell.statePath("album-scheme.json")
        onLoaded: root._restore()
    }

    function _restore() {
        if (root.active || !store.ready) return
        const v = store.value ?? ({})
        if (!v.key || !v.palette || !v.active || !Config.albumScheme) { root._settle(); return }

        // The cache alone makes a reload-while-playing free: _settle() finds the
        // current cover already extracted and shows it without spawning anything.
        root._cache[v.key] = v.palette
        root.palette = v.palette
        root.appliedUrl = ""
        root.active = true
        root.reason = "active"
        root._restoring = true

        // Shell-only: put the overlay back now (no flash). System-wide: colors.json is
        // already the album's, so there is nothing to paint — just hold the flag. A scope: the
        // workspaces' palette, which WorkspaceTheme reads.
        if (root.scoped) root.scopedPalette = root._merged()
        else if (!Config.albumSchemeSystem) Colors.overlay = root._merged()

        grace.restart()
        root._settle()
    }

    // `active` is flipped WITHOUT touching the stored palette, because _clear() nulls
    // `root.palette` before it gets here — reserialising from live state would write
    // `palette: null` and destroy the very thing this exists to keep. Clearing means
    // "don't put this back up next time", not "forget it": the same record played
    // again should still hit the cache.
    function _remember(active) {
        if (!store.ready) return
        if (!active) {
            const v = store.value ?? ({})
            if (!v.key) return
            store.value = ({ key: v.key, palette: v.palette, active: false })
            return
        }
        store.value = ({
            key: root._key(root.appliedUrl),
            palette: root.palette,
            active: true
        })
    }

    function _push() {
        const merged = root._merged()
        grace.stop()                      // whatever we were waiting out has resolved
        root._restoring = false
        root.active = true
        root.reason = "active"
        root.appliedUrl = root.artUrl

        if (root.systemWide) {
            // The overlay is dropped on the way in: the shell reads colors.json like
            // everything else once the file is the album's, and leaving both in place
            // would mean two sources of the same palette drifting apart.
            Colors.overlay = ({})
            root.scopedPalette = null
            root._writeSystem(merged)
        } else if (root.scoped) {
            // Only some workspaces: nothing global moves, WorkspaceTheme places it.
            Colors.overlay = ({})
            root.scopedPalette = merged
        } else {
            root.scopedPalette = null
            Colors.overlay = merged
        }
        root._remember(true)
    }

    function _clear(why) {
        root.reason = why
        root.palette = null
        root.scopedPalette = null
        root._pending = ""
        root._restoring = false
        if (!root.active) return          // already clear; don't regenerate on every tick

        root.active = false
        root.appliedUrl = ""
        // The palette is kept on disk, only its `active` flag is cleared: the next
        // start should not put it back up, but the cache is still worth having when
        // the same record is played again.
        root._remember(false)

        if (root.systemWide) {
            // colors.json really is the album's now, so the wallpaper's palette only
            // comes back by re-deriving it. Costly, which is exactly why the shell-only
            // reach is the default.
            ColorScheme.regenerate()
        } else {
            Colors.overlay = ({})
        }
    }

    // ── System-wide write ─────────────────────────────────────────────────────
    // Deliberately NOT ColorScheme's ThemeRunner: that one notifies on every run, and a
    // "Colours applied" toast per track would be intolerable. Same script, quiet.
    //
    // Written straight to colors.json rather than through the overrides file, because
    // this is not an edit the user made — it is a palette that should vanish when the
    // music does, and the overrides file is explicitly the thing that SURVIVES.
    readonly property string colorsPath:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/wal/colors.json"

    property var _queued: null

    function _writeSystem(palette) {
        if (writer.running) { root._queued = palette; return }
        writer.payload = JSON.stringify(palette, null, 2)
        writer.running = false
        writer.running = true
    }

    Process {
        id: writer
        running: false
        property string payload: ""
        environment: ({ "AS_PALETTE": writer.payload })
        // The palette goes over the ENVIRONMENT, not argv: a colors.json is a few
        // hundred bytes of argument that would show up in `ps` for every process on the
        // machine, and the repo already made that call for Discord's client secret.
        command: ["bash", "-c",
            'mkdir -p "$(dirname "$1")" && printf %s "$AS_PALETTE" > "$1" '
          + '&& exec bash "$2" >/dev/null 2>&1',
            "_", root.colorsPath, Quickshell.shellPath("scripts/reload-theme.sh")]
        onExited: function(code) {
            if (code !== 0)
                console.warn("[AlbumScheme] system-wide apply failed with code", code)
            if (root._queued) {
                const next = root._queued
                root._queued = null
                root._writeSystem(next)
            }
        }
    }

    // ── Diagnostic ────────────────────────────────────────────────────────────
    // `qs ipc -c ~/.config/quicktest call albumscheme status`. Counts and states only —
    // never a cover url beyond its filename, and never the palette itself.
    IpcHandler {
        target: "albumscheme"

        function status(): string {
            return "enabled=" + Config.albumScheme
                 + " systemWide=" + Config.albumSchemeSystem
                 + " locked=" + Config.albumSchemeLock
                 + " scope=" + Config.albumScope
                 + " active=" + root.active
                 + " reason=" + root.reason
                 + " player=" + (root.player?.identity || "-")
                 + " playing=" + root.playing
                 + " eligible=" + root.eligible
                 + " hasArt=" + (root.artUrl !== "")
                 + " sat=" + root.saturation
                 + " fullyHeld=" + root.fullyHeld
                 + " cached=" + Object.keys(root._cache).length
        }
    }
}
