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

    readonly property int barCount:  32
    readonly property int frameRate: 60

    // Raw magnitudes, 0..1, low frequency → high. Empty until cava produces a frame.
    property var bars: []
    readonly property bool hasData: root.bars.length > 0

    Process {
        id: proc
        running: root.running

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

        command: ["bash", "-c",
            "cfg=$(mktemp /tmp/cava-qs-XXXXXX.ini)\n" +
            "printf '[general]\\nbars=" + root.barCount +
            "\\nframerate=" + root.frameRate +
            "\\nsensitivity=130\\nautosens=1\\nnoise_reduction=0.35\\n" +
            proc.inputSection +
            "[output]\\nmethod=raw\\ndata_format=ascii\\nascii_max_range=1000\\n" +
            "raw_target=/dev/stdout\\nbar_delimiter=59\\nframe_delimiter=10\\nchannels=mono\\n' > \"$cfg\"\n" +
            "cava -p \"$cfg\"\n" +
            "rm -f \"$cfg\""
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
                if (out.length >= 2) root.bars = out
            }
        }

        // Clear on stop so a consumer that comes back doesn't briefly render the
        // spectrum from whenever the last one left.
        onRunningChanged: if (!running) root.bars = []
    }

    // Restart on a source change: cava reads its input once, at startup, so a running
    // process would keep analysing the old device forever.
    onSourceChanged: {
        if (!root.running) return
        proc.running = false
        proc.running = true
    }
}
