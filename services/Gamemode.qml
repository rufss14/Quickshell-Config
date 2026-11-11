pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "../config"
import "gamemodewatch.js" as Watch
import "gamemodefx.js" as Fx
import "mangohud.js" as MH
import "screentime.js" as St

// ── Gamemode ──────────────────────────────────────────────────────────────────
// One switch for the four things you'd otherwise do by hand before playing: stop the
// screen blanking, stop the notifications, put the CPU on performance, and stop the
// desktop rendering things nobody can see.
//
// ── Never on a fullscreen window, and that is a decision ──────────────────────
// Fullscreen.byMonitor already knows when a window covers an output, so following it
// automatically would be a two-line binding. It is deliberately not done: that signal
// also fires for fullscreen video, a maximised browser and a screen share — and a
// shell that reacts to a fullscreen client on its own is "delightful once and then in
// the way forever". This turns on because you said so, from the pill or from a keybind.
//
// ── …but it may follow gamemode itself (Config.gamemodeAuto) ──────────────────
// A game launched with `gamemoderun` registers with the system gamemoded, and that
// registration is a statement nothing else makes: "this is a game". No video, browser
// or screen share ever registers. So while one is registered the mode is on, and when
// the last one leaves (after a short grace, so a launcher handing over to its game
// doesn't bounce the wallpaper) it goes off — but only if it came on that way: a mode
// you switched on by hand is never switched off by a game exiting. See `auto` and
// gamemodewatch.js, which reads gamemoded's own D-Bus signals — event-driven, no
// polling, and exact about which registrations are the shell's own hold.
//
// ── Suppress, never overwrite ─────────────────────────────────────────────────
// The rule that shapes every branch below: gamemode may not WRITE a stored user
// preference to express a temporary state. A reload or a crash while it is on must
// not leave the config edited.
//
// So it never touches Config.cavaBg (CavaBG reads `active` as a suppression input,
// the same way it already reads Fullscreen), and it never touches Notifications.dnd
// (it takes a named quiet hold instead). The three things it genuinely must mutate are
// SYSTEM state, not config: the power profile, a held gamemoderun session, and whether
// a wallpaper process is running. All are restored on exit, and each restore is guarded.
//
// ── The gamemoderun hold ─────────────────────────────────────────────────────
// `gamemoderun cat`, held for exactly as long as the mode is on. gamemoderun registers
// its own PID with the system gamemoded over D-Bus; gamemoded then applies everything
// its config asks for — renice, ioprio, the CPU governor, the AMD GPU performance level
// (only with a profile: see scripts/gamemode-profile.py) — and reverts every one of
// them when that PID exits. So it is the same shape as the profile and the wallpaper:
// system state we turn on and gamemoded's own refcounted teardown turns back off.
// Nothing is persisted.
//
// `cat` on a stdin pipe the shell holds, not `sleep infinity`. The shell does not
// catch SIGTERM and sets no parent-death signal, so a restart (reload-quickshell.sh's
// pkill) or a crash takes it down with NO cleanup — its children keep running. A
// `sleep infinity` then never ends: it writes nothing, so nothing ever tells it, and
// the orphan keeps gamemode active — the governor (and, with a profile, the GPU at
// full clocks) pinned until someone finds it. The kernel closes the pipe however the
// shell dies; cat reads EOF, exits normally, and a normal exit unregisters at once.
// A game-started mode holds nothing: the game's own registration is what gamemoded
// is serving.
// It is also what makes `PowerProfiles` below redundant on a machine with gamemode but
// no power-profiles-daemon — that branch stays because it is a correct no-op there and
// the right thing where ppd IS present.
//
// ── Every restore checks it is still the owner ────────────────────────────────
// "Save the old value, put it back" is wrong on its own, because the user can change
// the same thing while gamemode is on. Each restore first asks whether the current
// state is still the one gamemode established; if it isn't, somebody else has taken
// over and the saved value is stale, so it is dropped rather than forced back.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Not writable from outside: enabling has side effects that must run in order, and
    // an assignment cannot carry them. `toggle()`/`enable()`/`disable()` are the API.
    readonly property bool active: root._active
    property bool _active: false

    // True while the mode is on BECAUSE a game registered with gamemoded, not because
    // someone switched it on. Only such a mode is switched off when the games leave —
    // see the header. Any manual toggle clears it.
    readonly property bool auto: root._auto
    property bool _auto: false

    // When the mode turned on, epoch ms. -1 while off — the panel's session timer
    // reads this rather than keeping its own clock, same "service owns the fact"
    // rule as everything else here.
    readonly property double enabledAt: root._enabledAt
    property double _enabledAt: -1

    // ── CPU governor — did the performance session actually land? ─────────────
    // gamemoded sets the governor to `performance` through a polkit-gated helper
    // (`/usr/lib/gamemode/cpugovctl`). That helper runs WITHOUT a prompt only for
    // members of the `gamemode` group — so on a machine where the user isn't in it,
    // `gamemode is active` but the governor never moves and nothing says why. This
    // reads it back so the panel can. `performance` from a permanent cpupower/tuned
    // setting counts as fine too — the check only exists to catch the silent failure.
    readonly property string cpuGovernor: root._gov
    property string _gov: ""

    function refreshGovernor() { govFile.reload() }

    property var _govFile: FileView {
        id: govFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        preload: true
        printErrors: false
        onLoaded: root._gov = govFile.text().trim()
    }

    // gamemoded acts asynchronously after the request lands. `_govSettled` gates
    // `sessionStalled` until that re-read has happened, so the warning doesn't flash
    // for two seconds every time the mode is switched on.
    property bool _govSettled: false
    property var _govSettle: Timer {
        id: govSettle
        interval: 2500
        onTriggered: { root._govSettled = true; govFile.reload(); root.refreshGpuLevel() }
    }
    on_ActiveChanged: {
        root._govSettled = false
        govFile.reload()
        govSettle.restart()
        root._onActiveForGame()
    }

    // A gamemode session is genuinely live: our own hold, or the game that turned
    // the mode on. Without one (the session effect off, or no gamemode installed)
    // nothing was ever asked of the governor or the GPU, so neither can be "stalled".
    // `_auto` alone is not enough any more: a mode a Steam window turned on has no registration of
    // its own, so only a registered game or our hold means gamemoded is serving anything.
    readonly property bool _sessionLive: root._active
        && (root._gm.running || (root._auto && root._gamePids.length > 0))

    // The perf session is meant to be doing something, but the governor shows it
    // hasn't. Almost always: not in the `gamemode` group.
    readonly property bool sessionStalled:
        root._sessionLive && root._govSettled
        && root._gov !== "" && root._gov !== "performance"

    // The GPU twin: the system profile asked for `high` and the card isn't there.
    // Usually polkit (not in the group) or a gpu_device that no longer names the card.
    readonly property bool gpuStalled:
        root._sessionLive && root._govSettled && root.systemProfile.gpuLevel !== ""
        && root._gpuLevel !== "" && root._gpuLevel !== root.systemProfile.gpuLevel

    // ── Manual governor pick ──────────────────────────────────────────────────
    // Independent of a gamemode SESSION: this is the user reaching for the same
    // `cpugovctl` helper directly, the way the battery pill's profile picker is a
    // direct, non-reverting choice rather than a suppressed hold. `set()` below is
    // fire-and-forget on purpose — same contract as PowerProfiles.profile = …
    //
    // ── Which governors actually exist here ───────────────────────────────────
    // Read straight from sysfs rather than assumed: an amd-pstate-epp box (this one)
    // exposes only "performance" and "powersave" — no schedutil/ondemand/conservative
    // exist to be a distinct "default". `governorChoices` below only ever offers
    // values this machine actually has.
    readonly property var availableGovernors: root._availGov
    property var _availGov: []

    property var _availGovFile: FileView {
        id: availGovFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
        preload: true
        printErrors: false
        onLoaded: root._availGov = availGovFile.text().trim().split(/\s+/).filter(g => g !== "")
    }

    // "Default" means whichever of these the machine actually offers, in order of
    // how much it behaves like an adaptive, everyday governor. On a box with only
    // performance/powersave (this one) none of these match, so there IS no distinct
    // default — `governorChoices` below drops the button rather than pointing it at
    // powersave a second time.
    readonly property string _defaultGovernor: {
        const order = ["schedutil", "ondemand", "conservative"]
        for (const g of order) if (root._availGov.indexOf(g) !== -1) return g
        return ""
    }

    // { value, label } for exactly the buttons worth showing — 2 or 3, never a
    // duplicate. The panel just repeats this; it carries no governor knowledge itself.
    readonly property var governorChoices: {
        const out = []
        if (root._availGov.indexOf("powersave") !== -1)
            out.push({ value: "powersave", label: "Powersave" })
        if (root._defaultGovernor !== "")
            out.push({ value: root._defaultGovernor, label: "Default" })
        if (root._availGov.indexOf("performance") !== -1)
            out.push({ value: "performance", label: "Performance" })
        return out
    }

    // Same helper gamemoded itself calls, same polkit rule — `com.feralinteractive.
    // GameMode.governor-helper` auto-approves for the `gamemode` group (rules.d/
    // gamemode.rules), so this is silent for anyone gamemode already works for and a
    // normal graphical polkit prompt for anyone else. No revert-on-exit: a direct
    // click here is a persistent choice, same as PowerProfiles.profile, not a
    // suppression gamemode owes you back.
    function setGovernor(name) {
        if (root._setGov.running) return
        root._setGov.command = ["pkexec", "/usr/lib/gamemode/cpugovctl", "set", name]
        root._setGov.running = true
    }
    property var _setGov: Process {
        onExited: function(code) {
            if (code !== 0) console.warn("Gamemode: cpugovctl set exited " + code)
            govFile.reload()
        }
    }

    // ── GPU power level — read-only, the GPU-side twin of the governor readback ──
    // gamemoded's `gpuclockctl` helper does to this what cpugovctl does to the CPU
    // governor, on the SAME card SysInfo already found — no second probe. "auto" is
    // the normal resting value on amdgpu; a session pushes it to "high" and restores
    // it after, same shape as the governor.
    readonly property string gpuPowerLevel: root._gpuLevel
    property string _gpuLevel: ""

    property var _gpuLevelFile: FileView {
        id: gpuLevelFile
        path: SysInfo.gpuPath === "" ? "" : SysInfo.gpuPath + "/power_dpm_force_performance_level"
        preload: true
        printErrors: false
        onLoaded: root._gpuLevel = gpuLevelFile.text().trim()
    }
    function refreshGpuLevel() { if (SysInfo.gpuPath !== "") root._gpuLevelFile.reload() }

    // SysInfo's own probe finds the card asynchronously (one process, on first
    // acquire) — this fires the first read the moment that path lands, the same way
    // SysInfo's own `vramTotalFile.reload()` follows its probe rather than trusting a
    // path BINDING change to imply a fresh load.
    Connections {
        target: SysInfo
        function onGpuPathChanged() { root.refreshGpuLevel() }
    }

    // ── Derived intent, for surfaces that suppress themselves ─────────────────
    // CavaBG and the bar's VisualizerPill bind to this instead of `active` so the
    // visualiser toggle in the Gaming panel is honoured (the pill freezes its spectrum
    // and releases its cava stream). Both operands are plain notifying bools — no
    // lazy-model walk — which is what keeps CavaBG's `suppressed` binding out of the
    // re-entrancy trap its own header describes.
    readonly property bool hidesVisualizer: root._active && Config.gamemodeVisualizer

    // Typing sounds for other apps' keys (services/SfxKeys) stop while this is true, and
    // the compositor hook comes out entirely — nothing rides the event socket in a game.
    readonly property bool silencesKeys: root._active && Config.gamemodeKeys

    // For WallpaperView's takeover card: true whenever the wallpaper effect is
    // doing ANYTHING for this session — covering a scene it genuinely paused,
    // or just standing in for a plain static wallpaper that never needed
    // pausing at all. A user without a scene running still turned gamemode on
    // and still expects to SEE that, and it's the only place a queued pick
    // has anywhere to show feedback. OUTLIVES `active`: disable() sets active
    // false immediately but the relaunch (stop→drain→start→verify) still
    // takes several seconds; gating this on `active` dropped the card the
    // instant you turned gamemode off, exposing that whole window as a
    // static-wallpaper flash. Never true for a scene the user paused by hand
    // outside gamemode, or when Config.gamemodeWallpaper is off.
    readonly property bool wallpaperPaused: root._wallpaperHeld

    // The two halves of wallpaperPaused: still genuinely paused (mode is on) vs
    // mode already ended and just waiting on the relaunch to land. Both keep
    // the takeover card up (that's the whole point above), but they're not the
    // same fact and a surface showing "Game Mode Activated" several seconds
    // after you turned it off would be wrong, not just stale.
    readonly property bool wallpaperRestoring: root._wallpaperHeld && !root._active

    // ── What was here before us ───────────────────────────────────────────────
    // Only meaningful while active or still restoring. Cleared once the restore
    // concludes (or gives up) so a stale value can never be restored by a later run.
    property int    _prevProfile: -1        // -1 = we did not change it
    property string _prevScene:   ""        // the DEFAULT scene id — "" is a valid
                                             // value for a monitors-only setup, so
                                             // this alone can't say whether we owe
                                             // a restore. `_wallpaperStopped` does.
    property bool   _wallpaperHeld:    false // true = the effect is live for this session (card shown)
    property bool   _wallpaperStopped: false // true = we ALSO genuinely stopped a scene, and owe it back

    // A pick made WHILE we're holding the wallpaper down — WallpaperEngine.apply()
    // and Wallpaper.apply() redirect here instead of actually running, rather than
    // starting a scene process (or overriding the takeover card) mid-session. null
    // = nothing queued; the LAST call wins, same as picking a wallpaper normally
    // overwrites whatever was showing before — queueing just holds that overwrite
    // back until the hold ends.
    property var _queuedWallpaper: null   // { kind: "scene"|"image", value }

    // The PICTURE stays held back, but there's no reason its colours have to —
    // _kickScenePalette only ever reads the scene's own Workshop preview off
    // disk, the exact thing that makes repalette() work on a paused scene too.
    // Recolouring now, from the pick itself, is what makes "queued" actually
    // feel like "accepted" instead of "recorded and ignored until later".
    function queueScene(id) {
        root._queuedWallpaper = { kind: "scene", value: id }
        WallpaperEngine._kickScenePalette(id)
    }
    function queueImage(name) {
        root._queuedWallpaper = { kind: "image", value: name }
        ColorScheme.regenerateFrom(name)
    }

    // A human-readable name for whatever's queued, "" when nothing is — the
    // panel's own feedback that a click was actually received rather than
    // silently swallowed. `titleFor` is safe to call with an id it doesn't
    // recognise (returns something sane); an image's queued value is the full
    // path apply() was called with, so it needs the same basename trim the
    // gallery itself uses for a filename, not the whole thing.
    readonly property string queuedWallpaperName:
        !root._queuedWallpaper ? ""
        : root._queuedWallpaper.kind === "scene" ? WallpaperEngine.titleFor(root._queuedWallpaper.value)
        : root._queuedWallpaper.value.split("/").pop()

    // The wallpaper scene is the one action with a visible cost on the way back:
    // linux-wallpaperengine has no IPC, so "pause" does not exist — the process is
    // stopped and relaunched, and the relaunch takes several seconds to appear. That
    // wait is already reported by WallpaperEngine.busy, which the wallpaper surfaces
    // bind to, so gamemode does not publish a second flag saying the same thing.

    function toggle() { if (root._active) root.disable(); else root.enable() }

    function enable() { root._enable(false) }

    // `fromGame`: a registered game turned the mode on (see _onGamesChanged). It skips
    // the hold — the game's own registration is what gamemoded is serving, and a hold
    // of ours would keep gamemode active after the game left. (Only when one IS registered:
    // a Steam window with no gamemoderun behind it has nothing serving it, so `_holdSession`
    // takes the hold for that — see there.)
    function _enable(fromGame) {
        if (root._active) return
        root._active = true
        root._auto = fromGame
        root._enabledAt = Date.now()
        root._loggedAt = root._enabledAt
        root._relabel()

        // Each effect is its own helper, so the Gaming panel can apply a toggle LIVE (see the
        // Connections to Config below) instead of "at the next switch-on". They are all
        // idempotent, which is what makes that safe.
        root._holdIdle(Config.gamemodeIdle)
        root._holdQuiet(Config.gamemodeQuiet)
        root._holdSession(Config.gamemodeSession)
        root._holdWallpaper(Config.gamemodeWallpaper)
        root._holdCompositor(Config.gamemodeCompositor)
    }

    // ── Idle and notifications: named holds, nothing persisted ────────────────
    // Each effect is gated on its Config toggle (the Gaming panel edits those).
    // `release()` on an unheld reason is a documented no-op, so disable() can stay
    // unconditional.
    function _holdIdle(on)  { if (on) Idle.hold("gamemode");                  else Idle.release("gamemode") }
    function _holdQuiet(on) { if (on) Notifications.holdQuiet("gamemode");    else Notifications.releaseQuiet("gamemode") }

    // The daemon offers a performance profile. `PowerSaver.profilesOk` first: see there, the singleton is
    // not touched on a machine without the daemon.
    readonly property bool _perfProfile: PowerSaver.profilesOk && PowerProfiles.hasPerformanceProfile

    // ── gamemoderun session + power profile ───────────────────────────────────
    // Held only where the tools are actually present. Absent, the mode still
    // does everything else — the idle/quiet holds, the wallpaper.
    function _holdSession(on) {
        if (on) {
            // The one case that skips it: a game's own registration is already what gamemoded is
            // serving (auto, with a PID registered).
            if (root._toolsOk && !(root._auto && root._gamePids.length > 0)) root._gm.running = true

            // ── Power profile ─────────────────────────────────────────────────
            // Skipped entirely where power-profiles-daemon has no performance profile —
            // which is most desktops and any machine without the daemon. Asking for a
            // profile that does not exist is how you get a D-Bus error instead of a
            // no-op, and there is nothing to report to a user who never had the feature.
            if (root._perfProfile
                && PowerProfiles.profile !== PowerProfile.Performance
                && root._prevProfile === -1) {
                root._prevProfile = PowerProfiles.profile
                PowerProfiles.profile = PowerProfile.Performance
            }
            return
        }

        // gamemoded deactivates when the PID exits — SIGTERM is enough, and its
        // teardown (governor, GPU level, renice) is its own responsibility.
        root._gm.running = false

        // Only put the profile back if it is still the one we set. If the user picked
        // power-saver mid-session, forcing balanced back on exit would be gamemode
        // overruling a choice made after it.
        if (root._prevProfile !== -1) {
            if (root._perfProfile && PowerProfiles.profile === PowerProfile.Performance)
                PowerProfiles.profile = root._prevProfile
            root._prevProfile = -1
        }
    }

    // ── Wallpaper scene ───────────────────────────────────────────────────────
    function _holdWallpaper(on) {
        // Runs whenever the card went up at all — even a static-wallpaper
        // session with nothing to restore still needs this to check for a
        // queued pick. `_tryRestoreWallpaper` sorts out which of the three
        // cases it actually is. `_wallpaperHeld` itself is NOT cleared here —
        // it has to outlive this call; see that function for why.
        if (!on) {
            if (root._wallpaperHeld) {
                root._wallpaperRestoreTries = 0
                root._tryRestoreWallpaper()
            }
            return
        }

        // The card goes up unconditionally, the moment the effect is on — a
        // plain static wallpaper never needed pausing, but you still turned
        // gamemode on and still expect to see it took effect, and it's the
        // only place a wallpaper queued mid-session has anywhere to show
        // feedback. Whether there's actually a SCENE to stop is a separate
        // question, answered below once a fresh probe comes back.
        if (!WallpaperEngine.installed) return
        root._wallpaperHeld = true

        // `busy` means an apply or a stop is already in flight, and issuing a
        // second one across that is exactly the state WallpaperEngine's phase
        // machine exists to prevent — so gamemode leaves the scene alone
        // rather than racing it. Config.wpeCurrent is NOT touched, so even a
        // crash here loses nothing but a running process, which autostart
        // brings back.
        //
        // `WallpaperEngine.running` is a CACHE — it only refreshes while a
        // panel has acquire()d the poll or mid apply/stop. Deciding off it
        // directly meant a scene started (or changed) since the last probe —
        // the ordinary case when no wallpaper surface has been opened since
        // login — silently never got paused at all: gamemode read `running`
        // as still false and skipped stopping it. Probe fresh and decide off
        // THAT.
        WallpaperEngine.probe(() => {
            if (!root._active) return    // turned back off before the probe landed
            if (!WallpaperEngine.running || WallpaperEngine.busy) return
            // `current` is "" for a monitors-only setup (no default scene) even
            // though something IS running — that's still a real pause, so the
            // flag that gates the restore is `_wallpaperStopped`, never a check
            // on `_prevScene` being non-empty. apply("") is exactly how a
            // monitors-only restore is expressed; WallpaperEngine already
            // accepts it (see refresh() and the autostart timer).
            root._prevScene = WallpaperEngine.current
            root._wallpaperStopped = true
            WallpaperEngine.stop()
        })
    }

    function disable() {
        if (!root._active) return
        root._active = false
        root._auto = false
        root._credit()
        root._enabledAt = -1
        autoOffGrace.stop()
        // Off while a game is still registered = off for that game; see _autoDeclined.
        if (root.gamesLive) root._autoDeclined = true

        root._holdIdle(false)
        root._holdQuiet(false)
        root._holdSession(false)
        root._holdWallpaper(false)
        root._holdCompositor(false)
    }

    // Each effect's toggle, applied the moment it is flipped while the mode is on (the panel
    // used to dim them: "applies at the next switch-on"). Visualiser and typing sounds need
    // nothing here — `hidesVisualizer` / `silencesKeys` already read their Config flag live.
    Connections {
        target: Config
        function onGamemodeIdleChanged()       { if (root._active) root._holdIdle(Config.gamemodeIdle) }
        function onGamemodeQuietChanged()      { if (root._active) root._holdQuiet(Config.gamemodeQuiet) }
        function onGamemodeSessionChanged()    { if (root._active) root._holdSession(Config.gamemodeSession) }
        function onGamemodeWallpaperChanged()  { if (root._active) root._holdWallpaper(Config.gamemodeWallpaper) }
        function onGamemodeCompositorChanged() { if (root._active) root._holdCompositor(Config.gamemodeCompositor) }
        function onGamemodeSteamChanged()      { root._syncSteam() }
    }

    // WallpaperEngine can still be draining the stop() issued at enable() — a
    // fast on/off has no trouble reaching this before that settles. Rather than
    // drop the restore (busy right now doesn't mean busy in a second), retry a
    // few times on a short timer; give up and say so rather than loop forever.
    //
    // `_wallpaperHeld` stays true across the WHOLE relaunch, not just until this
    // function decides to call apply() — apply() only STARTS the stop→drain→
    // start→verify cycle, which still takes several seconds, and WallpaperView's
    // takeover card is keyed off `_wallpaperHeld` specifically so that window
    // doesn't show the static wallpaper. `_restoring` (below) is what actually
    // clears it, once OUR apply cycle — not just any busy WallpaperEngine cycle
    // going idle — has settled.
    property int  _wallpaperRestoreTries: 0
    property bool _restoring: false   // true only from OUR apply() call to it settling

    function _clearWallpaperHold() {
        root._wallpaperHeld    = false
        root._wallpaperStopped = false
        root._prevScene        = ""
        root._queuedWallpaper  = null
    }

    function _tryRestoreWallpaper() {
        if (!WallpaperEngine.installed) { root._clearWallpaperHold(); return }
        if (WallpaperEngine.busy) {
            root._wallpaperRestoreTries++
            if (root._wallpaperRestoreTries <= 5) { root._wallpaperRestoreRetry.restart(); return }
            console.warn("Gamemode: wallpaper still busy, gave up restoring it")
            root._clearWallpaperHold()
            return
        }

        // A pick queued while we were paused wins outright over the old scene —
        // queueScene()/queueImage() exist precisely so it's accepted immediately
        // and only held back from actually RENDERING until now. `_applyNow`
        // bypasses the public apply()'s own gamemode check — that check exists
        // for every OTHER caller, and calling the public name here would just
        // have us re-queue our own restore forever. Checked FIRST regardless of
        // whether a scene was ever actually stopped — a static-wallpaper-only
        // session can still have something queued to apply now.
        if (root._queuedWallpaper) {
            const q = root._queuedWallpaper
            root._queuedWallpaper  = null
            root._prevScene        = ""
            root._wallpaperStopped = false
            root._restoring = true
            // A scene's "settled" signal is WallpaperEngine.busy; a static image
            // never touches that — it runs apply-wallpaper.sh instead, and
            // Wallpaper.current only updates once THAT script finishes. Wait on
            // whichever one this pick actually started, or the card would drop
            // before the new picture's really there.
            if (q.kind === "scene") {
                WallpaperEngine._applyNow(q.value)
                if (!WallpaperEngine.busy) { root._restoring = false; root._wallpaperHeld = false }
            } else {
                Wallpaper._applyNow(q.value)
                if (!Wallpaper.applying) { root._restoring = false; root._wallpaperHeld = false }
            }
            return
        }

        if (!root._wallpaperStopped) {
            // Nothing queued, and nothing was ever actually stopped — a plain
            // static wallpaper, or a scene setup that wasn't running to begin
            // with. The card was purely "gamemode is on"; there's nothing to
            // hand back.
            root._clearWallpaperHold()
            return
        }

        if (WallpaperEngine.running) {
            // Nothing queued through us, but something's running anyway — hand-
            // started outside the shell while we were paused. Leave it alone,
            // same "don't silently override a fresh pick" rule the queue exists
            // to guarantee for the paths that DO go through us.
            root._wallpaperHeld = false; root._wallpaperStopped = false; root._prevScene = ""
            return
        }

        const id = root._prevScene
        root._prevScene        = ""
        root._wallpaperStopped = false
        root._restoring = true
        WallpaperEngine._applyNow(id)
        // apply() is only synchronous about STARTING the relaunch — busy flips
        // true in this same tick if it actually did anything. If it didn't
        // (blocked, nothing to launch), busy never moves, so nothing would ever
        // clear the flags; check for that here rather than holding them forever.
        if (!WallpaperEngine.busy) { root._restoring = false; root._wallpaperHeld = false }
    }
    property var _wallpaperRestoreRetry: Timer {
        interval: 500
        onTriggered: root._tryRestoreWallpaper()
    }

    // "Settled" (busy/applying goes false) isn't the same as PAINTED — pgrep
    // confirming the new scene's process exists, or the apply script exiting,
    // still leaves a beat before the first frame or the file WallpaperView
    // reads actually lands. Same idea as WallpaperEngine's own 250ms post-
    // drain pause before it starts a new process: a short buffer here is what
    // keeps the card up until "the other wallpaper is active", not just
    // "the signal that says so fired".
    Timer {
        id: wallpaperSettle
        interval: 500
        onTriggered: root._wallpaperHeld = false
    }

    // Fires once the relaunch _tryRestoreWallpaper() kicked off actually
    // settles (busy goes false again, whether it landed on `running` or not) —
    // that's the moment the takeover card can start winding down. Gated on
    // `_restoring`, NOT `_wallpaperHeld` directly — WallpaperEngine.busy also
    // toggles for the STOP enable() issues, and busy→false from THAT cycle
    // would clear `_wallpaperHeld` the moment gamemode turns on, long before
    // disable() ever runs. `_restoring` is only ever true during our own
    // apply() call, so a stop we didn't initiate can't trip this.
    Connections {
        target: WallpaperEngine
        function onBusyChanged() {
            if (root._restoring && !WallpaperEngine.busy) {
                root._restoring = false
                wallpaperSettle.restart()
            }
        }
    }
    // Same shape, for a queued IMAGE's apply-wallpaper.sh run instead of a
    // scene's stop→drain→start→verify cycle.
    Connections {
        target: Wallpaper
        function onApplyingChanged() {
            if (root._restoring && !Wallpaper.applying) {
                root._restoring = false
                wallpaperSettle.restart()
            }
        }
    }

    // ── The held session, and the probe that gates it ────────────────────────
    // Probed once at startup rather than assumed: this config is published, and a
    // machine with the shell but not gamemode (or mangohud) is the normal case, not
    // an error. One shell, both answers — `gamemoderun` gates the session below,
    // `mangohud` gates the overlay preset further down.
    // Public so the panel can gate the governor buttons on it — cpugovctl ships in
    // the same package as gamemoderun, so this probe already answers "is cpugovctl
    // there" for free.
    readonly property bool toolsAvailable: root._toolsOk
    property bool _toolsOk: false
    property bool _mhOk: false
    // `gdbus` (glib2) is how "follow games" hears gamemoded; pkexec is how the
    // profile's GPU half reaches /etc. Both near-universal, both still probed.
    property bool _gdbusOk: false
    property bool _pkexecOk: false
    property var _probe: Process {
        command: ["sh", "-c",
                  "command -v gamemoderun >/dev/null && echo gm; "
                + "command -v mangohud   >/dev/null && echo mh; "
                + "command -v gdbus      >/dev/null && echo gd; "
                + "command -v pkexec     >/dev/null && echo pk"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root._toolsOk  = text.indexOf("gm") !== -1
                root._mhOk     = text.indexOf("mh") !== -1
                root._gdbusOk  = text.indexOf("gd") !== -1
                root._pkexecOk = text.indexOf("pk") !== -1
            }
        }
    }

    property var _gm: Process {
        // No StdioCollector — gamemoderun's output isn't ours to show, and holding a
        // read end open across a Quickshell reload is the SIGPIPE trap WallpaperEngine
        // documents. The STDIN pipe is the point: see "The gamemoderun hold" above.
        // gamemoderun execs straight through (`exec env LD_PRELOAD=… "$@"`), so the PID
        // gamemoded registers IS processId — which is how the watcher below tells this
        // hold from a game.
        command: ["gamemoderun", "cat"]
        stdinEnabled: true
        running: false
        onExited: function(code) {
            // A non-zero exit while we still think the mode is on means the session
            // died under us — the governor/GPU level have silently reverted. Report
            // it the way NightLight reports its backend dying.
            if (root._active && code !== 0)
                console.warn("Gamemode: gamemoderun session exited unexpectedly (" + code + ")")
        }
    }

    // ══ Following games ═══════════════════════════════════════════════════════
    // Config.gamemodeAuto. gamemoded's own D-Bus signals say when a process registers
    // and unregisters; gamemodewatch.js turns them into the set of registered GAMES
    // (every PID but our hold's). Non-empty → on (as `auto`); empty for a grace period
    // → off, if it came on that way. One long-lived `gdbus monitor`, asleep in a read()
    // until gamemoded says something — nothing polls.
    readonly property bool followAvailable: root._toolsOk && root._gdbusOk
    readonly property int  gameCount: root._gamePids.length
    property var _gamePids: []
    // "A game is running": a gamemoderun registration, or (Config.gamemodeSteam) a Steam window.
    // The follow rules watch THIS, a bool, so a set that keeps changing under one running game
    // (Proton registers every process it starts) wakes nothing.
    readonly property bool gamesLive: root._gamePids.length > 0 || root._steam.length > 0
    on_SteamChanged: root._relabel()

    // Switched off by hand while a game is registered: stay off for THAT game. Proton
    // registers every process it starts, so the set keeps changing under a running
    // game — without this, each change would switch the mode straight back on against
    // an explicit "off". Cleared when the last registration leaves.
    property bool _autoDeclined: false

    function _onGamesChanged() {
        if (root.gamesLive) {
            autoOffGrace.stop()
            // The two sources are each gated by their own switch (the gdbus watch by gamemodeAuto,
            // the Steam list by gamemodeSteam), so an empty source is simply off.
            if (!root._active && !root._autoDeclined) root._enable(true)
        } else {
            root._autoDeclined = false
            if (root._active && root._auto) autoOffGrace.restart()
        }
    }
    onGamesLiveChanged: root._onGamesChanged()
    on_GamePidsChanged: { gameCommTimer.restart(); root._relabel() }
    function _setGames(next) { if (next !== root._gamePids) root._gamePids = next }

    // A launcher handing over to its game, or a game restarting itself, leaves the set
    // empty for a moment. Turning off for that gap would restart the wallpaper scene —
    // seconds of work — only to stop it again.
    Timer {
        id: autoOffGrace
        interval: 5000
        onTriggered: if (!root.gamesLive && root._active && root._auto) root.disable()
    }

    // gdbus monitor follows gamemoded coming and going on its own, so it should never
    // exit — but a Process that exits by itself stays exited while its `running`
    // BINDING still reads true (nothing it depends on changed). Dip a flag the binding
    // reads to start it again, like CavaStream's `_cycling`; the delay keeps a gdbus
    // that dies at once from spinning.
    property bool _watchCycling: false
    Timer {
        id: watchRestart
        interval: 5000
        onTriggered: { root._watchCycling = true; root._watchCycling = false }
    }

    Process {
        id: gameWatch
        running: Config.gamemodeAuto && root.followAvailable && !root._watchCycling
        onExited: function(code) {
            if (Config.gamemodeAuto && root.followAvailable) {
                console.warn("Gamemode: gdbus monitor exited (" + code + "), restarting in 5s")
                watchRestart.restart()
            }
        }
        // `setpriv --pdeathsig TERM`: see LauncherEntry — a SIGTERM'd shell orphaned one of these per restart.
        command: ["setpriv", "--pdeathsig", "TERM", "gdbus", "monitor", "--session",
                  "--dest", "com.feralinteractive.GameMode",
                  "--object-path", "/com/feralinteractive/GameMode"]
        stdout: SplitParser {
            onRead: function(line) {
                const ev = Watch.parseMonitorLine(line)
                if (!ev) return
                root._setGames(Watch.apply(root._gamePids, ev, root._gm.processId))
                // Anything registered before we were listening — a game already running
                // when the shell (re)started — only shows up in ListGames. Seeded late on
                // purpose: see gameSeedDelay.
                if (ev.kind === "owner" && ev.owned) gameSeedDelay.restart()
            }
        }
        onRunningChanged: {
            if (!running) {
                gameSeedDelay.stop()
                if (root._gamePids.length > 0) root._setGames([])
            }
        }
    }

    // Longer than gamemoded's reaper interval (5s). A hold killed by a shell reload is
    // still registered until the reaper notices it; seeding sooner would count the
    // previous shell's hold as a game and switch the mode on for no one.
    Timer {
        id: gameSeedDelay
        interval: 8000
        onTriggered: if (gameWatch.running) gameList.running = true
    }

    Process {
        id: gameList
        command: ["gdbus", "call", "--session",
                  "--dest", "com.feralinteractive.GameMode",
                  "--object-path", "/com/feralinteractive/GameMode",
                  "--method", "com.feralinteractive.GameMode.ListGames"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!gameWatch.running) return
                const next = Watch.seed(Watch.parseListGames(text), root._gm.processId)
                if (JSON.stringify(next) !== JSON.stringify(root._gamePids)) root._setGames(next)
            }
        }
    }

    // ══ The profile — what gamemoded actually does for a session ═══════════════
    // scripts/gamemode-profile.py writes it, in two halves because gamemoded ignores
    // [gpu] in user-writable files: the user file (priority) and /etc (GPU clocks).
    // Read back here, never written from QML.
    readonly property var userProfile: Watch.parseProfile(root._userIniText)
    readonly property var systemProfile: Watch.parseProfile(root._systemIniText)
    readonly property bool profileInstalled: root.userProfile.installed
    property string _userIniText: ""
    property string _systemIniText: ""

    // The card the profile's GPU half would name — SysInfo's probe already found it,
    // and a machine without an amdgpu DPM knob has no GPU half to offer.
    readonly property bool profileGpuAvailable: root._gpuLevel !== ""

    FileView {
        id: userIni
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/gamemode.ini"
        preload: true            // FileView is lazy; see SysInfo/CLAUDE.md
        printErrors: false       // absent until the profile is set up — not a warning
        onLoaded:     root._userIniText = userIni.text()
        onLoadFailed: root._userIniText = ""
    }
    FileView {
        id: systemIni
        path: "/etc/gamemode.ini"
        preload: true
        printErrors: false
        onLoaded:     root._systemIniText = systemIni.text()
        onLoadFailed: root._systemIniText = ""
    }
    function refreshProfile() { userIni.reload(); systemIni.reload() }

    readonly property bool profileBusy: profileUser.running || profileSystem.running

    // The user half first (no password); then, only if there is a card to set up and
    // /etc doesn't have it yet, the GPU half through pkexec — one polkit prompt.
    function installProfile() { root._runProfile("install") }
    function removeProfile()  { root._runProfile("remove") }

    property string _profileOp: ""      // "install" | "remove" — which run is in flight
    function _runProfile(op) {
        if (root.profileBusy) return
        root._profileOp = op
        profileUser.command = ["python3", Quickshell.shellPath("scripts/gamemode-profile.py"), op]
        profileUser.running = true
    }
    Process {
        id: profileUser
        onExited: function(code) {
            if (code !== 0) console.warn("Gamemode: gamemode-profile.py exited " + code)
            const installing = root._profileOp === "install"
            const wantSystem = installing
                ? root.profileGpuAvailable && !root.systemProfile.installed
                : root.systemProfile.installed
            if (code === 0 && wantSystem && root._pkexecOk) {
                profileSystem.command = ["pkexec", "python3",
                    Quickshell.shellPath("scripts/gamemode-profile.py"), root._profileOp, "--system"]
                profileSystem.running = true
            } else {
                root.refreshProfile()
            }
        }
    }
    Process {
        id: profileSystem
        onExited: function(code) {
            // 126/127 = the polkit prompt was dismissed or refused. Not an error to
            // shout about; the panel simply still shows the GPU half as not set up.
            if (code !== 0 && code !== 126 && code !== 127)
                console.warn("Gamemode: gamemode-profile.py --system exited " + code)
            root.refreshProfile()
            // pkexec's root has no session bus to tell gamemoded; we do.
            if (code === 0) profileRefresh.running = true
        }
    }
    Process {
        id: profileRefresh
        command: ["gdbus", "call", "--session",
                  "--dest", "com.feralinteractive.GameMode",
                  "--object-path", "/com/feralinteractive/GameMode",
                  "--method", "com.feralinteractive.GameMode.RefreshConfig"]
    }

    // ══ The CPU scheduler — read-only ══════════════════════════════════════════
    // Which sched_ext scheduler is loaded, if any (scripts/system-tune.sh can set up
    // scx_lavd). "" = the kernel's own (EEVDF); the panel says so. The ops file only
    // exists while a BPF scheduler is attached, so a failed load IS the answer.
    readonly property string scheduler: root._sched
    readonly property bool schedulerKnown: root._schedKnown
    property string _sched: ""
    property bool _schedKnown: false
    FileView {
        id: schedState
        path: "/sys/kernel/sched_ext/state"
        preload: true
        printErrors: false
        onLoaded: { root._schedKnown = true; schedOps.reload() }
        onLoadFailed: { root._schedKnown = false; root._sched = "" }
    }
    FileView {
        id: schedOps
        path: "/sys/kernel/sched_ext/root/ops"
        preload: true
        printErrors: false
        onLoaded:     root._sched = schedOps.text().trim()
        onLoadFailed: root._sched = ""
    }
    function refreshScheduler() { schedState.reload() }

    // ══ MangoHud ══════════════════════════════════════════════════════════════
    // The in-game overlay is a separate tool with its own config and its own toggle
    // keybind, per game — game mode does NOT turn it on or off. What belongs here is
    // the PRESET: how much it shows. scripts/generate-mangohud-config owns a marked
    // region in MangoHud.conf and stamps `### quicktest:preset=<name>` into it, so
    // that file is the single source of truth and this only reads it back.
    readonly property bool mangohudAvailable: root._mhOk

    // "" before the file is read, or if it carries no marker (a hand-written config
    // from before the generator existed).
    readonly property string mangohudPreset: root._mhPreset
    property string _mhPreset: ""

    readonly property string _mhConfPath:
        (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
        + "/MangoHud/MangoHud.conf"

    FileView {
        id: mhConf
        path: root._mhConfPath
        preload: true            // REQUIRED — FileView is lazy; see SysInfo/CLAUDE.md
        printErrors: false       // absent until the first preset is set — not a warning
        onLoaded: {
            const m = mhConf.text().match(/^###\s*quicktest:preset=(\w+)/m)
            root._mhPreset = m ? m[1] : ""
            root._mhHasConf = true
            root._mhFps = MH.readLimit(mhConf.text()) ?? -1
        }
        onLoadFailed: { root._mhHasConf = false; root._mhFps = -1 }
    }

    // ── The frame cap (the HUD's FPS widget) ──────────────────────────────────
    // `fps_limit=` in the same file: one line rewritten in place (services/mangohud.js,
    // tested), everything else — the generated regions included — untouched. -1 = no
    // cap line; 0 is MangoHud's own "unlimited".
    //
    // There is deliberately NO config file created from here: a MangoHud.conf holding
    // only fps_limit would replace MangoHud's default readout with an empty one. So
    // `mangohudConfigured` gates it, and the preset (above) is what creates the file.
    // A running game picks the change up when MangoHud next reads its config; I have not
    // verified whether that is live or needs the game's reload key.
    readonly property int  mangohudFps: root._mhFps
    readonly property bool mangohudConfigured: root._mhHasConf
    property int  _mhFps: -1
    property bool _mhHasConf: false
    function setMangohudFps(n) {
        const v = MH.parseLimit(String(n))
        if (v === null || !root._mhHasConf) return false
        mhConf.setText(MH.setLimit(mhConf.text(), v))
        mhConf.reload()
        return true
    }

    // Runs the generator; the FileView reload on exit picks the new value up.
    function setMangohudPreset(name) {
        if (root._mhGen.running) return
        root._mhGen.command = ["python3",
            Quickshell.shellPath("scripts/generate-mangohud-config"), "--preset", name]
        root._mhGen.running = true
    }
    property var _mhGen: Process {
        onExited: function(code) {
            if (code !== 0) console.warn("Gamemode: generate-mangohud-config exited " + code)
            else mhConf.reload()
        }
    }

    // ══ Following Steam games too (Config.gamemodeSteam) ═══════════════════════
    // A window of a Steam game is a statement nothing but a Steam game makes, so it can turn the mode on
    // without a `gamemoderun` launch option. That is NOT the old "follow fullscreen" idea, which this file
    // declines above: a video player and a browser are fullscreen just as often. Off by default.
    //
    // Two ways to know a window is a Steam game, merged by address:
    //   · its class is `steam_app_<id>` (Proton) — instant, from Hypr.windows, nothing spawned;
    //   · its process has SteamGameId / SteamAppId in its environment — scripts/gamemode-steam.py. A NATIVE
    //     Linux game wears any class it likes (Hollow Knight: Silksong's is "Hollow Knight Silksong"), so
    //     the class alone missed it (2026-11-07, the user's report). Steam sets the id for every game it
    //     launches, native or Proton, with or without launch options.
    // The script runs (debounced) only when the SET of open windows changes — a title changing wakes
    // nothing — and only while the setting is on. Rows are { address, appClass, title, appId }.
    readonly property var steamWindows: root._steam
    property var _steam: []
    property var _steamEnv: []
    property string _steamKey: ""

    function _steamRows() {
        const byAddr = ({})
        const wins = Hypr.windows
        for (const w of Watch.steamWindows(wins))
            byAddr[w.address] = { address: w.address, appClass: w.appClass, title: w.title, appId: Watch.steamAppId(w.appClass) }
        const open = ({})
        for (const w of wins) open[w.address] = w
        // A scan result for a window that has since closed is dropped here, before the next scan lands.
        for (const g of root._steamEnv)
            if (open[g.address]) byAddr[g.address] = { address: g.address, appClass: g.class, title: g.title, appId: g.appId }
        return Object.values(byAddr)
    }
    function _syncSteam() {
        // The scan also runs while the mode is on whatever the setting says: it is how the panel learns
        // WHICH Steam game this is (its name and picture), not only whether to switch on.
        if (!Config.gamemodeSteam && !root._active) {
            root._steamKey = ""
            if (root._steamEnv.length > 0) root._steamEnv = []
            if (root._steam.length > 0) root._steam = []
            return
        }
        const key = Hypr.windows.map(w => w.address).join(",")
        if (key !== root._steamKey) { root._steamKey = key; steamScanDelay.restart() }
        // The trigger list is the setting's alone; with it off the rows only feed the label.
        if (!Config.gamemodeSteam) {
            if (root._steam.length > 0) root._steam = []
            return
        }
        const next = root._steamRows()
        const same = next.length === root._steam.length
                     && next.every((w, i) => w.address === root._steam[i].address)
        if (!same) root._steam = next
    }
    Timer { id: steamScanDelay; interval: 800; onTriggered: if (Config.gamemodeSteam || root._active) steamScan.running = true }
    Process {
        id: steamScan
        command: ["python3", Quickshell.shellPath("scripts/gamemode-steam.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text)
                    root._steamEnv = o.ok ? o.games : []
                } catch (e) { root._steamEnv = [] }
                root._syncSteam()
                root._relabel()
            }
        }
    }
    Connections {
        target: Hypr
        function onWindowsChanged() { root._syncSteam(); if (root._active) root._relabel() }
    }

    // ══ What game it is — best effort ══════════════════════════════════════════
    // gamemoded registers a PID, not a title. A Steam window's class gives the game's real name
    // (the library's appmanifest, through ScreenTime.nameOf); failing that, the registered
    // process's own name with Proton/Wine plumbing filtered out (gamemodewatch.js labelFor). ""
    // when neither knows — the panel then says "a game" and no more.
    readonly property string gameName: root._gameName
    property string _gameName: ""
    // The Steam app id of the running game ("" = not a Steam game, or not known yet) and its picture.
    readonly property string gameAppId: root._gameAppId
    readonly property string gameArt: root.artPaths[root._gameAppId] ?? ""
    property string _gameAppId: ""
    property var _gameComms: []
    property var _commFor: []

    // What the panel's hero shows after the mode ends: the game and how long it ran.
    property string lastGame: ""
    property string lastAppId: ""
    property real lastSeconds: 0

    // ── The game's picture ────────────────────────────────────────────────────
    // appId → file path ("" = looked, found nothing). scripts/gamemode-art.py takes Steam's own library cache
    // first (what its window already shows; nothing is sent anywhere) and fetches Steam's public header once
    // only for a game Steam never showed. Asked for by whoever shows one — the hero, a history row — in its
    // Component.onCompleted, never inside a binding; the answer lands in `artPaths`, which bindings read.
    property var artPaths: ({})
    readonly property var _artAsked: ({})
    property var _artQueue: []
    function requestArt(appId) {
        if (!/^\d{1,10}$/.test(String(appId)) || root._artAsked[appId]) return
        root._artAsked[appId] = true
        root._artQueue.push(String(appId))
        artDelay.restart()
    }
    Timer {
        id: artDelay
        interval: 120
        onTriggered: {
            if (artProc.running) { artDelay.restart(); return }
            const ids = root._artQueue.slice(0, 20)
            root._artQueue = root._artQueue.slice(20)
            if (ids.length === 0) return
            artProc.command = ["python3", Quickshell.shellPath("scripts/gamemode-art.py")].concat(ids)
            artProc.running = true
        }
    }
    Process {
        id: artProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.artPaths = Object.assign({}, root.artPaths, JSON.parse(text)) } catch (e) {}
                if (root._artQueue.length > 0) artDelay.restart()
            }
        }
    }

    // ── Past sessions ─────────────────────────────────────────────────────────
    // gamemode-sessions.json: one row per session of a minute or more, newest first, 60 kept
    // (gamemodewatch.js addSession / cleanSessions, tested). Written when the mode ends. A row keeps the game's
    // name and the path of its picture (a copy under the cache, see gamemode-art.py) so history reads the same
    // after Steam clears its cache or the game is gone.
    property var sessions: []
    JsonStore {
        id: sessionStore
        path: Quickshell.statePath("gamemode-sessions.json")
        defaults: ({ version: 1, sessions: [] })
        onLoaded: root.sessions = Watch.cleanSessions(sessionStore.value)
    }
    function _recordSession() {
        const next = Watch.addSession(root.sessions, {
            start: root._enabledAt, seconds: (Date.now() - root._enabledAt) / 1000,
            game: root._gameName, appId: root._gameAppId, art: root.artPaths[root._gameAppId] ?? "", auto: root._auto
        }, 60)
        if (next === root.sessions) return
        root.sessions = next
        if (sessionStore.ready) sessionStore.value = ({ version: 1, sessions: next })
    }
    function clearSessions() {
        root.sessions = []
        if (sessionStore.ready) sessionStore.value = ({ version: 1, sessions: [] })
    }

    function _relabel() {
        if (!root._active) return
        const rows = root._steamRows().filter(w => w.appId !== "")
        const names = rows.map(w => ScreenTime.nameOf("steam_app_" + w.appId))
        const appId = rows.length > 0 ? rows[0].appId : ""
        if (appId !== root._gameAppId) { root._gameAppId = appId; if (appId !== "") root.requestArt(appId) }
        // "Steam game 123" is nameOf's placeholder until the library is read; prefer a process
        // name over it, and fall back to it only when there is nothing else.
        const real = names.map(n => /^Steam game \d+$/.test(n) ? "" : n)
        let label = Watch.labelFor(real, root._gameComms)
        if (label === "" && names.length > 0) label = names[0]
        if (label !== root._gameName) root._gameName = label
    }
    // (The `_active` handler itself is the one above, beside the governor's: one per scope.)
    function _onActiveForGame() {
        if (root._active) {
            gameCommTimer.restart()
            root._steamKey = ""          // force a scan: the label wants the game's id even with the trigger off
            root._syncSteam()
            root._relabel()
            return
        }
        // Still before `_enabledAt` and `_auto` are cleared by disable(): keep what the hero shows
        // afterwards, and write the session down.
        if (root._enabledAt > 0) {
            root.lastSeconds = (Date.now() - root._enabledAt) / 1000
            root.lastGame = root._gameName
            root.lastAppId = root._gameAppId
            root._recordSession()
        }
        root._gameName = ""
        root._gameAppId = ""
        root._gameComms = []
        root._syncSteam()
    }
    Connections {
        target: ScreenTime
        function onGameNamesChanged() { root._relabel() }
    }
    // The registered PIDs' process names: one tiny read per change, debounced, never while one
    // is in flight. PIDs are integers from gdbus's own output, passed as arguments.
    Timer {
        id: gameCommTimer
        interval: 400
        onTriggered: root._readComms()
    }
    function _readComms() {
        if (!root._active) return
        if (commProc.running) { gameCommTimer.restart(); return }
        const pids = root._gamePids.filter(p => Number.isInteger(p) && p > 0)
        root._commFor = pids
        if (pids.length === 0) { root._gameComms = []; root._relabel(); return }
        commProc.command = ["sh", "-c",
            'for p; do read -r c < "/proc/$p/comm" 2>/dev/null && echo "$p $c"; done; exit 0', "sh"]
            .concat(pids.map(String))
        commProc.running = true
    }
    Process {
        id: commProc
        stdout: StdioCollector {
            onStreamFinished: { root._gameComms = Watch.parseComms(text, root._commFor); root._relabel() }
        }
    }

    // ══ Time in game mode ══════════════════════════════════════════════════════
    // "Today 1 h 20 m · this week 6 h" in the panel. One key (`gamemode`) in the same shape
    // ScreenTime keeps — `{ version, days: { "YYYY-MM-DD": { key: seconds } } }` — so its
    // helpers (credit across midnight, clip a suspend, prune) do the work. Per-GAME time is
    // ScreenTime's job (it knows the focused window); this only knows that the mode was on.
    // Credited every minute while on and when it ends; a gap longer than 2.5 minutes (a
    // suspend) is clipped to its last 2.5 minutes by St.credit.
    property var _days: ({})
    property double _loggedAt: 0
    JsonStore {
        id: timeStore
        path: Quickshell.statePath("gamemode-time.json")
        defaults: ({ version: 1, days: {} })
        onLoaded: root._days = St.clean(timeStore.value)
    }
    // (Single Component.onCompleted: a second one is "Property value set multiple times".)
    Component.onCompleted: {
        root._syncSteam()
        if (timeStore.ready) root._days = St.clean(timeStore.value)
        if (sessionStore.ready) root.sessions = Watch.cleanSessions(sessionStore.value)
    }

    function _credit() {
        const now = Date.now()
        if (root._loggedAt > 0 && timeStore.ready) {
            root._days = St.prune(St.credit(root._days, "gamemode", root._loggedAt, now, 150000), 30, now)
            timeStore.value = ({ version: 1, days: root._days })
        }
        root._loggedAt = root._active ? now : 0
    }
    Timer { interval: 60000; repeat: true; running: root._active; onTriggered: root._credit() }

    readonly property real todaySeconds: {
        void Clock.now
        return St.total(root._days[St.dayKey(Date.now())] ?? ({}))
    }
    readonly property real weekSeconds: {
        void Clock.now
        return St.lastDays(root._days, Date.now(), 7).reduce((a, d) => a + d.seconds, 0)
    }
    // The last seven days, oldest first: [{ key, label, seconds, today }] — the panel's week chart.
    readonly property var weekDays: {
        void Clock.now
        return St.lastDays(root._days, Date.now(), 7)
    }
    function duration(s) { return St.duration(s) }

    // ══ Clips follows the mode (Config.gamemodeClips) ══════════════════════════
    // Clips.wantBuffer reads this, so the replay buffer runs for as long as the mode does even
    // with Config.clipsBuffer off — a hold, never a write to the user's own switch.
    readonly property bool holdsClips: root._active && Config.gamemodeClips

    // ══ Compositor effects off (Config.gamemodeCompositor) ═════════════════════
    // Blur, shadows and animations, off in Hyprland while the mode is on, put back from what was
    // READ beforehand (services/gamemodefx.js — the user may already run some of them off). Sent as
    // `hyprctl eval 'hl.config(…)'`, the same path HyprLayout and CursorEffects use; only
    // `hl.bind` through eval is known to crash the compositor (docs/gotchas-system.md), not this.
    //
    // The snapshot is also written to disk, because this is system state outside the shell: a
    // crash or a shell restart while the mode is on would otherwise leave the desktop without
    // blur until the next Hyprland start. At the next start the file is read, and if the mode is
    // not on it is put back and emptied (`{}` = nothing owed).
    property bool _fxHeld: false
    property var  _fxSnap: ({})
    readonly property string _fxPath: Quickshell.statePath("gamemode-compositor.json")

    function _holdCompositor(on) {
        if (on) {
            if (root._fxHeld) return
            root._fxHeld = true
            fxRead.command = ["sh", "-c", Fx.READ_SCRIPT, "sh"].concat(Fx.OPTIONS)
            fxRead.running = true
            return
        }
        if (!root._fxHeld) return
        root._fxHeld = false
        root._restoreCompositor(root._fxSnap)
        root._fxSnap = ({})
    }

    function _restoreCompositor(snap) {
        const lua = Fx.restoreLua(snap)
        if (lua !== "") {
            fxBack.command = ["hyprctl", "eval", lua]
            fxBack.running = true
        }
        fxFile.setText("{}")
    }

    Process {
        id: fxRead
        stdout: StdioCollector {
            onStreamFinished: {
                // Turned back off (or the switch flipped) before the answer landed: nothing was
                // changed yet, so there is nothing to put back.
                if (!root._fxHeld || !root._active || !Config.gamemodeCompositor) { root._fxHeld = false; return }
                const snap = Fx.snapshotFrom(text)
                // No answer at all (hyprctl missing): don't turn anything off we can't turn back on.
                if (Object.keys(snap).length === 0) {
                    root._fxHeld = false
                    console.warn("Gamemode: couldn't read Hyprland's effect options")
                    return
                }
                root._fxSnap = snap
                fxFile.setText(JSON.stringify(snap))
                fxOff.command = ["hyprctl", "eval", Fx.offLua()]
                fxOff.running = true
            }
        }
    }
    Process {
        id: fxOff
        stdout: StdioCollector { onStreamFinished: if (/error|expected/i.test(text)) console.warn("Gamemode: effects off: " + text.trim()) }
    }
    Process {
        id: fxBack
        stdout: StdioCollector { onStreamFinished: if (/error|expected/i.test(text)) console.warn("Gamemode: effects back: " + text.trim()) }
    }
    FileView {
        id: fxFile
        path: root._fxPath
        preload: true
        printErrors: false       // absent until the first time it is used — not a warning
        // A snapshot left by a session that never got to put it back. Only a cold start
        // finds one with the mode off; a live session's own file is never read back.
        onLoaded: {
            if (root._active) return
            let snap = ({})
            try { snap = Fx.cleanSnapshot(JSON.parse(fxFile.text())) } catch (e) {}
            if (Object.keys(snap).length > 0) root._restoreCompositor(snap)
        }
    }

    // ══ What to close first ════════════════════════════════════════════════════
    // The biggest open windows by memory, for "close these before you play" — on a box short of
    // RAM, that is what throttles a game first (scripts/gamemode-hogs.py: one /proc read, games
    // never listed). Scanned when the panel asks, never on a timer. Closing asks the window
    // politely (Hyprland's own close), so an app with unsaved work gets to say so; nothing is
    // killed from here.
    property var  hogs: []
    property bool hogsBusy: false
    property bool hogsScanned: false
    function scanHogs() {
        if (hogProc.running) return
        root.hogsBusy = true
        hogProc.running = true
    }
    function closeHog(app) {
        for (const a of (app?.addrs ?? [])) Hypr.closeWindow(a)
        hogRescan.restart()
    }
    Timer { id: hogRescan; interval: 1500; onTriggered: root.scanHogs() }
    Process {
        id: hogProc
        command: ["python3", Quickshell.shellPath("scripts/gamemode-hogs.py"), "4"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hogsBusy = false
                root.hogsScanned = true
                try {
                    const o = JSON.parse(text)
                    root.hogs = o.ok ? o.apps : []
                } catch (e) { root.hogs = [] }
            }
        }
    }

    // ── Why the pill may be unavailable ───────────────────────────────────────
    // Same contract as Discord.pressBlocker() and WallpaperEngine.blocker(): a missing
    // optional piece DISABLES the control with a reason rather than failing on click.
    //
    // Gamemode itself is never fully unavailable — the idle and quiet holds work on
    // any machine — so this returns "" and is used for an explanatory line, not to
    // block the button. What it reports is which parts will do nothing here.
    function limits() {
        const out = []
        if (!root._toolsOk && !root._perfProfile)
            out.push("no gamemode or performance power profile — CPU/GPU stay as-is")
        else if (!root._toolsOk)
            out.push("gamemode not installed — governor/GPU level unchanged")
        if (!WallpaperEngine.installed)
            out.push("linux-wallpaperengine not installed")
        if (Config.gamemodeAuto && root._toolsOk && !root._gdbusOk)
            out.push("gdbus (glib2) missing — can't follow games")
        if (Config.gamemodeClips && Clips.probed && !Clips.installed)
            out.push("gpu-screen-recorder not installed — no clip buffer")
        return out.join("; ")
    }

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call gamemode toggle`
    // Bindable to a key, so it can be turned off without leaving the game to find
    // the bar — which is the whole point of a mode you enter before playing.
    property var _ipc: IpcHandler {
        target: "gamemode"

        function toggle(): void { root.toggle() }
        function on(): void     { root.enable() }
        function off(): void    { root.disable() }

        function status(): string {
            const games = root._gamePids.length > 0 ? ", " + root._gamePids.length + " game pid(s) registered"
                        : root._steam.length > 0    ? ", " + root._steam.length + " Steam window(s)" : ""
            if (!root._active) return "off" + games
            const l = root.limits()
            return "on" + (root._auto ? " (following a game" + games + ")" : "")
                 + (l !== "" ? " (" + l + ")" : "")
        }
    }
}
