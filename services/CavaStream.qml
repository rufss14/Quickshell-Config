import Quickshell.Io
import QtQuick

// ── CavaStream ────────────────────────────────────────────────────────────────
// One `cava` process and its parsed output. NOT a singleton — instantiate one per
// distinct signal you want analysed.
//
// ── Why this exists separately from the Cava singleton ────────────────────────
// Cava is a singleton because the bar, the desktop background and the settings page all
// want THE SAME spectrum — the default output — and running three processes to draw one
// spectrum is the bug that service was created to fix.
//
// The microphone test wants a genuinely DIFFERENT signal. That's not the duplication the
// singleton prevents; it's a second question, and it needs a second process because cava
// analyses one input per instance. So the process and its parsing live here, the
// singleton wraps one of these for the shared case, and the mic test owns another.
// One implementation, two instances — rather than one implementation copied twice.
//
// ── Lifecycle is the caller's ─────────────────────────────────────────────────
// This has no refcount. It runs while `running` is true, and stops when it isn't. The
// singleton adds refcounting on top because it has many consumers; a caller with exactly
// one consumer (the mic test) doesn't need it and shouldn't pay for it.
// ─────────────────────────────────────────────────────────────────────────────
// Item, not QtObject, purely so the Process below has somewhere to attach: QtObject has
// no default property, so a child object is a hard error there. Nothing here draws.
Item {
    id: root

    // Empty = cava's default input, which is the default OUTPUT's monitor. Set to a
    // PipeWire node name (e.g. Audio.source.name) to analyse that instead.
    property string source: ""

    property bool running: false

    readonly property int frameRate: 60

    // ── Tuning ────────────────────────────────────────────────────────────────
    // The spectrum every visualiser shares is the defaults. MusicPulse runs its own, tuned for
    // finding beats (2026-10-31): fewer bars over 40 Hz–8 kHz so the kick has bars of its own,
    // half the sensitivity so the bass stops sitting at its ceiling, less smoothing so an attack
    // stays an attack. `tag` keeps two streams on one source from sharing a config file.
    // A cutoff of 0 leaves cava's own (50 Hz–10 kHz).
    property int    barCount: 32
    property int    sensitivity: 200
    property real   noiseReduction: 0.2
    property int    lowerCutoff: 0
    property int    higherCutoff: 0
    property string tag: ""

    // Raw magnitudes, 0..1, low frequency → high. Empty until cava produces a frame.
    property var bars: []
    readonly property bool hasData: root.bars.length > 0

    // Assigning `bars` re-runs every binding that reads it (each spectrum's path, the
    // resamplers, the pills), so an identical frame — silence, a paused track — must not
    // assign. Measured: the assignment was the top JS frame of the desktop spectrum.
    function _sameBars(a) {
        if (a.length !== root.bars.length) return false
        for (let i = 0; i < a.length; i++) if (a[i] !== root.bars[i]) return false
        return true
    }

    Process {
        id: proc
        // `!root._cycling` is the source-change restart (see onSourceChanged) — a
        // declarative dip, so this stays a BINDING. Assigning `proc.running` directly
        // would destroy it, and the process would then never stop again.
        running: root.running && !root._cycling

        // ── cava exiting on its own ───────────────────────────────────────────
        // It happens (PipeWire restarting under it; a node vanishing at login — this
        // shell logged "Pipewire error … no global 46 any more" in the same second the
        // desktop spectrum went flat). A Process that exits by itself stays exited while
        // its `running` binding still reads true, because nothing the binding depends
        // on changed — so the spectrum stayed flat until something dropped the last
        // reference and took it again, which on the desktop background meant until the
        // next reload. Restart through the same `_cycling` dip, backing off 1s → 30s so
        // a cava that cannot start at all doesn't spin; a run that lasted is a clean
        // slate. The last stderr line is kept so the warning says WHY.
        onExited: function(code) {
            // We stopped it (no consumer, or the source-change dip, whose replacement
            // may already be up): nothing to restart.
            if (!root.running || root._cycling || proc.running) return
            const lasted = Date.now() - root._startedAt > 30000
            root._backoffMs = lasted ? 1000 : Math.min(30000, root._backoffMs * 2)
            console.warn("CavaStream: cava exited (" + code + ")"
                         + (root._lastErr !== "" ? ": " + root._lastErr : "")
                         + " — restarting in " + Math.round(root._backoffMs / 1000) + "s")
            restartTimer.interval = root._backoffMs
            restartTimer.restart()
        }
        onStarted: root._startedAt = Date.now()

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { if (line.trim() !== "") root._lastErr = line.trim() }
        }

        // cava has no CLI form for this config, so it gets written to a temp file that's
        // removed as soon as cava has read it.
        //
        // The [input] section is emitted only when a source is named. Without it cava
        // picks its own default, which is what every consumer but the mic test wants —
        // and hardcoding the default output's name instead would break the moment you
        // switched output device.
        readonly property string inputSection:
            root.source === "" ? ""
                               : "[input]\\nmethod=pipewire\\nsource=" + root.source + "\\n"

        // ── A stable path, not mktemp ─────────────────────────────────────────
        // `mktemp` + a trailing `rm` looks tidy and leaks a file per restart. Quickshell
        // stops a Process by SIGTERMing its group: cava dies, bash dies with it, and the
        // `rm` after it never runs. Measured on this machine: 43 orphaned
        // /tmp/cava-qs-*.ini in one session, one per source change, forever.
        //
        // A name derived from the SOURCE is bounded instead — one file per distinct
        // stream, rewritten rather than accumulated, however the process goes down
        // (SIGKILL included, which no trap can cover). The trap below is then only for
        // tidiness on a clean stop.
        //
        // In XDG_RUNTIME_DIR rather than /tmp because a predictable name in a
        // world-writable directory is a symlink the next user can plant. The runtime dir
        // is 0700 and per-user; the fallback is too. No literal path, no uid.
        readonly property string configKey:
            (root.tag !== "" ? root.tag.replace(/[^A-Za-z0-9._-]/g, "_") + "-" : "")
            + (root.source === "" ? "default" : root.source.replace(/[^A-Za-z0-9._-]/g, "_"))
        readonly property string cutoffs:
            (root.lowerCutoff > 0 ? "\\nlower_cutoff_freq=" + root.lowerCutoff : "")
            + (root.higherCutoff > 0 ? "\\nhigher_cutoff_freq=" + root.higherCutoff : "")

        command: ["bash", "-c",
            "dir=\"${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}\"\n" +
            "mkdir -p \"$dir\"\n" +
            "cfg=\"$dir/cava-qs-" + proc.configKey + ".ini\"\n" +
            "trap 'rm -f \"$cfg\"' EXIT HUP INT TERM\n" +
            "umask 077\n" +
            "printf '[general]\\nbars=" + root.barCount +
            "\\nframerate=" + root.frameRate +
            // Raised from 130/0.35: autosens (below) normalises to roughly the same
            // peak regardless of volume GIVEN a second or two to adapt, but that
            // adaptation starts over on every process restart — and a source-targeted
            // stream (Cava.acquireSource) restarts far more often than the old shared
            // one did, on every player switch rather than rarely. A higher baseline
            // sensitivity and lower noise_reduction (less smoothing, snappier to
            // transients) means the FIRST couple of seconds after a cold start already
            // read as lively instead of flat while autosens is still catching up —
            // measured against this machine's own input, comparing the two side by
            // side at reduced system volume.
            "\\nsensitivity=" + root.sensitivity + "\\nautosens=1\\nnoise_reduction=" + root.noiseReduction +
            proc.cutoffs + "\\n" +
            proc.inputSection +
            "[output]\\nmethod=raw\\ndata_format=ascii\\nascii_max_range=1000\\n" +
            "raw_target=/dev/stdout\\nbar_delimiter=59\\nframe_delimiter=10\\nchannels=mono\\n' > \"$cfg\"\n" +
            "cava -p \"$cfg\""
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (!t) return
                const parts = t.split(";")
                const out = []
                for (let i = 0; i < parts.length; i++) {
                    const s = parts[i].trim()
                    if (!s) continue
                    const v = parseInt(s)
                    if (!isNaN(v)) out.push(Math.max(0, Math.min(1, v / 1000.0)))
                }
                if (out.length >= 2 && !root._sameBars(out)) root.bars = out
            }
        }

        // Clear on stop so a consumer that comes back doesn't briefly render the
        // spectrum from whenever the last one left.
        onRunningChanged: if (!running) root.bars = []
    }

    // Restart on a source change: cava reads its input once, at startup, so a running
    // process would keep analysing the old device forever.
    //
    // ── Why a flag and not `proc.running = false; proc.running = true` ────────
    // That was the original, and it was a permanent leak. `proc.running` is BOUND to
    // `root.running`; an imperative assignment to a bound property destroys the
    // binding. So the first source change (VisualizerPill switching player) unhooked
    // this process from its own refcount for good: `releaseSource()` dropped the
    // refs, `root.running` went false, and `proc.running` — no longer listening —
    // stayed true. cava kept decoding audio at 60fps forever, invisibly, which is
    // precisely the duplication the Cava service exists to prevent. It also stopped
    // `onRunningChanged` from ever clearing `bars`, so `Cava.sourceBars` went on
    // firing 60 times a second at every binding that reads it.
    //
    // Dipping a flag the binding reads keeps it a binding. `Qt.callLater` lands the
    // restart on the next event-loop pass rather than back-to-back inside one
    // handler, which also gives the old process a moment to go down.
    property bool _cycling: false

    onSourceChanged: {
        if (!root.running || root._cycling) return
        root._cycling = true
        Qt.callLater(() => root._cycling = false)
    }

    // ── The unexpected-exit restart (see proc.onExited) ─────────────────────
    property double _startedAt: 0
    property int _backoffMs: 500         // doubled before first use → 1s
    property string _lastErr: ""
    Timer {
        id: restartTimer
        onTriggered: {
            if (!root.running || proc.running) return
            root._lastErr = ""
            root._cycling = true
            root._cycling = false
        }
    }
    onRunningChanged: if (!root.running) { restartTimer.stop(); root._backoffMs = 500 }
}
