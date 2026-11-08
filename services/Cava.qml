pragma Singleton
import Quickshell
import QtQuick

// ── Cava ──────────────────────────────────────────────────────────────────────
// One audio spectrum, shared by everything that draws one.
//
// The shell previously ran up to three `cava` processes at once: the status bar
// pill started one unconditionally at 60fps and *never stopped it*, and because
// the bar builds both its split and merged layouts, that pill exists twice — so
// two of them. The desktop background visualizer ran a third. All three analyzed
// the same audio, at the same time, to draw the same spectrum.
//
// Now: one process, started only while something is actually watching, stopped
// the moment nothing is.
//
// ── Refcounting ───────────────────────────────────────────────────────────────
// Consumers call acquire() when they become visible and release() when they
// don't. The process runs iff refs > 0. Pair every acquire with exactly one
// release — the usual shape is:
//
//     onVisibleChanged: visible ? Cava.acquire() : Cava.release()
//     Component.onDestruction: if (visible) Cava.release()
//
// ── Bar counts ────────────────────────────────────────────────────────────────
// The service publishes a fixed `barCount` of raw 0..1 magnitudes. Consumers
// that want fewer bars call resample(); consumers that want a mirrored spectrum
// (bass in the middle) call mirrored(). Neither is cava's job, and making it
// the service's job is what lets one process feed views of different widths.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // 32 is the highest count any consumer currently wants, and downsampling is
    // free while upsampling invents data — so the service always produces the
    // maximum and lets consumers reduce.
    readonly property int barCount:  stream.barCount
    readonly property int frameRate: stream.frameRate

    // Raw magnitudes, 0..1, low frequency → high. Empty until cava produces a
    // frame (or while nothing holds a reference).
    readonly property var bars: stream.bars
    readonly property bool active: _refs > 0
    readonly property bool hasData: stream.hasData

    property int _refs: 0

    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    // The process itself lives in CavaStream, so the microphone test can run a second
    // one against a different input without copying any of it. This singleton is now
    // just "the shared spectrum of the default output, refcounted".
    CavaStream {
        id: stream
        running: root._refs > 0
    }

    // ── One player's own stream ────────────────────────────────────────────────
    // A second, refcounted spectrum, pointed at ONE specific PipeWire node instead
    // of the default output. VisualizerPill wants to react to whatever app is
    // actually playing — Spotify, say — and ignore everything else sharing the
    // speakers at the same time: a Discord call, a notification chime. The
    // default-output signal above can't make that distinction, because PipeWire
    // has already mixed everything together by the time cava sees it; only a
    // stream pointed at that ONE app's own node can.
    //
    // Refcounted rather than one-per-consumer for the same reason the shared
    // spectrum above is — this shell can run a bar on every monitor (`Variants`
    // over `Quickshell.screens` in shell.qml), and two of them showing the same
    // track would otherwise start two identical processes, which is the exact
    // duplication this whole service exists to prevent. `sourceName` is shared
    // rather than tracked per caller: every consumer derives it from the same
    // sticky "current player" rule off the same global MPRIS list, so in practice
    // they agree: this trades a theoretical one-frame mismatch during a player
    // switch for not needing a full keyed pool of processes.
    readonly property var sourceBars: sourceStream.bars
    property string sourceName: ""
    property int _sourceRefs: 0

    function acquireSource(name) {
        root._sourceRefs++
        root.sourceName = name
    }
    function releaseSource() {
        root._sourceRefs = Math.max(0, root._sourceRefs - 1)
    }

    CavaStream {
        id: sourceStream
        source:  root.sourceName
        running: root._sourceRefs > 0 && root.sourceName !== ""
    }

    // ── Shaping ───────────────────────────────────────────────────────────────
    // Reduce to `n` bars by averaging each source window. Averaging rather than
    // picking every k-th bar matters: sampling drops transients entirely, which
    // is exactly the content a visualizer exists to show.
    function resample(src, n) {
        if (!src || src.length === 0) return []
        if (src.length === n) return src
        const out = new Array(n)
        const ratio = src.length / n
        for (let i = 0; i < n; i++) {
            const start = Math.floor(i * ratio)
            const end   = Math.max(start + 1, Math.floor((i + 1) * ratio))
            let sum = 0
            for (let j = start; j < end; j++) sum += src[j]
            out[i] = sum / (end - start)
        }
        return out
    }

    // ── The idle wave ─────────────────────────────────────────────────────────
    // What a spectrum shows when there is nothing to show: a gentle sine across the row,
    // each bar a step along it, crest centred. Cava reflects the SYSTEM's output, so
    // silence and "no player" look identical to it — and a flat row of 2px bars sitting
    // where a spectrum should be reads as broken, not as waiting.
    //
    // It holds STILL, on purpose: a moving idle wave never ends, and anything that redraws
    // at the panel's refresh rate all day for no reason is exactly the cost the shell has
    // measured and removed before (VisualizerPill's comment has the numbers). `peak` is
    // the crest's height, 0..1; the trough is a fixed 0.10.
    function idleWave(n, peak) {
        const top   = peak === undefined ? 0.22 : peak
        const step  = 0.5
        const crest = Math.PI / 2 - (n - 1) * step / 2
        const out = []
        for (let i = 0; i < n; i++)
            out.push(0.10 + (top - 0.10) * (0.5 + 0.5 * Math.sin(crest + i * step)))
        return out
    }

    // Mirror a spectrum outward from the center — bass meeting in the middle,
    // treble at both edges — which is how cava itself presents a stereo field.
    // Produces src.length * 2 bars.
    function mirrored(src) {
        const half = src.length
        const out = new Array(half * 2)
        for (let i = 0; i < half * 2; i++) {
            const idx = i < half ? (half - 1 - i) : (i - half)
            out[i] = Math.max(0, Math.min(1, src[idx] ?? 0))
        }
        return out
    }

    // The shaped spectrum, once per frame for EVERY consumer. CavaBG on each screen and the
    // lock screen each ran shape() (a pow() per bin) and mirrored() per cava frame, 60 a second
    // — twice over in CavaBG (the mirrored and the raw copy), per screen. Same arrays, same
    // exponent, computed here once.
    readonly property var shaped: root.shape(root.bars, 1.25)
    readonly property var shapedMirrored: root.mirrored(root.shaped)
    // The same for the player's own stream (CavaBG's "music only", 2026-10-31), here for the
    // same reason: one copy per frame, not one per screen.
    readonly property var sourceShaped: root.shape(root.sourceBars || [], 1.25)
    readonly property var sourceShapedMirrored: root.mirrored(root.sourceShaped)

    // Expansive curve (exponent > 1): quiet passages sit lower and transients —
    // bass hits especially — shoot up disproportionately, instead of the whole
    // spectrum reading as a flat uniform block.
    function shape(src, exponent) {
        return src.map(v => Math.pow(v, exponent ?? 1.25))
    }
}
