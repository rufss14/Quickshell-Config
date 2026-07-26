pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── SpeedTest ─────────────────────────────────────────────────────────────────
// What the link can do, as opposed to what it happens to be doing. NetStats reads
// counters; this one generates traffic and times it.
//
// ── This is the only thing in the shell that talks to the internet ────────────
// Everything else here reads /proc, /sys, or D-Bus. This sends your IP to
// Cloudflare and moves ~35MB to find out how fast that was. That is a different
// category of act, so:
//   • It NEVER runs on its own. No timer, no run-on-open, no "refresh". It runs
//     when start() is called from a button press and at no other time. A speed
//     test that fires when a page happens to open would burn a phone tether's
//     data allowance for a number nobody asked for.
//   • The endpoint is named in the UI. If something is phoning out, the panel
//     says where to.
//
// ── Why Cloudflare, and what that costs in accuracy ───────────────────────────
// speed.cloudflare.com serves both directions over plain HTTPS, needs no account
// and no installed client — `iw`-style "just add a dependency" was rejected here
// for the same reason it was in NetStats. The honest caveat is that this is a
// SINGLE-STREAM test against ONE endpoint: Ookla and friends open many parallel
// connections precisely because one TCP stream often can't saturate a fast link.
// So this reads low on fast connections, and it is labelled "single-stream" in the
// UI rather than dressed up as an authoritative figure.
//
// Transfer sizes are picked to outrun TCP slow-start: a 5MB download finished in
// 0.29s on this machine, which is mostly ramp and reports well under the real
// rate. 25MB gives the window time to open.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string endpoint: "speed.cloudflare.com"

    // ── The transfer sizes ────────────────────────────────────────────────────
    // 90MB down is not a round-number choice: Cloudflare's __down endpoint 403s above
    // 100,000,000 bytes (99MB returns 200, 100MiB returns 403), and a rejected request
    // still "succeeds" from curl's point of view — it downloads the 1-byte error body
    // at a measured 17 B/s and reports it as your link speed. So 90MB is the cap with
    // headroom, and a duration-driven test that ignores the cap is not buildable here.
    //
    // __up has no such limit at 100MB.
    //
    // Sizes, not durations, for the same reason: the only knob the endpoint gives is
    // bytes. On a fast link that means a shorter test (~2.4s per direction at
    // 306 Mbps); on a slow one it stretches out on its own, which is the right way
    // round — the slower the link, the longer you need to watch it.
    readonly property int downBytes: 90 * 1000 * 1000
    readonly property int upBytes:  200 * 1000 * 1000

    // ── Why the download is chunked, and the upload isn't ─────────────────────
    // One 90MB chunk finished in 1.6s on this link — barely past TCP slow-start, which
    // is the very thing the size was raised to escape. The 100MB cap means the only way
    // to buy more time is more requests, so the download is several chunks on ONE curl
    // invocation: passing the URLs together reuses the connection (verified — the
    // second transfer reports num_connects=0), so there's no second handshake and no
    // second slow-start to pollute the average.
    //
    // The upload can't use the same trick and doesn't need to. Can't, because the
    // payload comes from a pipe and a pipe reads ONCE — a second URL on that command
    // would upload nothing. Doesn't need to, because __up has no size cap (200MB
    // verified), so one bigger transfer buys the same seconds without the chunk seams.
    //
    // Timings at ~450/185 Mbps: 4×90MB ≈ 6.3s down, 200MB ≈ 8.7s up. ~560MB total.
    readonly property int downChunks: 4

    readonly property real totalBytes: root.downBytes * root.downChunks + root.upBytes

    // ── The live trace ────────────────────────────────────────────────────────
    // curl reports once, at the end. A meter that sits at zero for four seconds and
    // then snaps to 306 Mbps tells you the answer but shows you nothing on the way,
    // and "is this link steady or spiky" is exactly what watching a test is for.
    //
    // So the live view is NetStats' interface counters, which already sample at 250ms
    // — the cadence exists for precisely this kind of thing. It is REAL measured
    // throughput, not an animation invented to look busy.
    //
    // The honest caveat: it's the whole interface, so anything else downloading during
    // a test lands in this trace too. During a saturating transfer that's noise on top
    // of a much larger signal, and the authoritative number is still curl's.
    readonly property var  liveTrace: root._liveTrace       // bytes/sec, oldest first
    readonly property real liveBps:   root._liveBps
    readonly property int  traceCapacity: 48                // 12s at 250ms

    property var  _liveTrace: []
    property real _liveBps: 0

    // "idle" | "latency" | "down" | "up" | "done" | "error"
    readonly property string phase: root._phase
    property string _phase: "idle"

    readonly property bool running: root._phase === "latency"
                                 || root._phase === "down"
                                 || root._phase === "up"
    readonly property bool hasResult: root._phase === "done"

    // Bytes/sec, and milliseconds. -1 means "not measured".
    readonly property real downBps:   root._downBps
    readonly property real upBps:     root._upBps
    readonly property real latencyMs: root._latencyMs

    property real _downBps:   -1
    property real _upBps:     -1
    property real _latencyMs: -1

    property string _error: ""
    readonly property string error: root._error

    function start() {
        if (root.running) return
        root._downBps   = -1
        root._upBps     = -1
        root._latencyMs = -1
        root._error     = ""
        root._liveTrace = []
        root._liveBps   = 0
        // The live trace reads NetStats, so this holds it open for the duration. The
        // settings page happens to acquire it too, but leaning on that would make this
        // service silently broken the day anything else calls start().
        NetStats.acquire()
        root._phase = "latency"
        latencyProc.running = true
    }

    function cancel() {
        latencyProc.running = false
        downProc.running    = false
        upProc.running      = false
        root._release()
        root._phase = root._downBps >= 0 ? "done" : "idle"
    }

    function _fail(what) {
        latencyProc.running = false
        downProc.running    = false
        upProc.running      = false
        root._release()
        root._error = what
        root._phase = "error"
    }

    // Paired with the acquire() in start(). Guarded so a cancel() on an already-idle
    // test can't drive NetStats' refcount negative and stop the settings page sampling.
    property bool _held: false
    function _release() {
        if (!root._held) return
        root._held = false
        NetStats.release()
    }

    onPhaseChanged: {
        if (root.phase === "latency") root._held = true

        // The trace resets at each direction's start: down and up are separate
        // measurements, and splicing them into one line would draw a cliff at the
        // handover that reads as the link collapsing.
        if (root.phase === "down" || root.phase === "up") {
            root._liveTrace = []
            root._liveBps   = 0
        }

        // "done" releases here rather than in a Process handler: it's reached from
        // upProc.onExited, which is the one terminal path that routes through neither
        // cancel() nor _fail().
        if (root.phase === "done") root._release()
    }

    // ── Live sampling ─────────────────────────────────────────────────────────
    // Only during the two transfer phases. The latency phase moves 30 bytes; charting
    // it would draw a flat zero and imply the test had stalled.
    Timer {
        running: root.phase === "down" || root.phase === "up"
        interval: NetStats.rateInterval
        repeat: true
        onTriggered: {
            root._liveBps = root.phase === "down" ? NetStats.rxRate : NetStats.txRate
            // capacity+1 for the same reason as NetStats._append: the surplus oldest
            // sample covers the left edge while the trace glides.
            const cap  = root.traceCapacity + 1
            const next = root._liveTrace.concat([root._liveBps])
            root._liveTrace = next.length > cap ? next.slice(next.length - cap) : next
        }
    }

    // ── Latency ───────────────────────────────────────────────────────────────
    // Three TCP handshakes, and the MINIMUM is the answer — not the mean. A single
    // slow sample is scheduling noise or a retransmit, and averaging lets that noise
    // inflate a figure whose whole job is to say how good the path can be.
    //
    // time_connect is the TCP handshake alone: no TLS, no server think-time. Closer
    // to a ping than time_starttransfer, which on this box measured ~80ms against a
    // ~19ms connect — that gap is Cloudflare generating the response, not the link.
    Process {
        id: latencyProc
        command: ["bash", "-c",
                  "for i in 1 2 3; do curl -s -o /dev/null -w '%{time_connect}\\n' "
                + "--max-time 8 'https://" + root.endpoint + "/__down?bytes=10'; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let best = -1
                for (const line of text.trim().split("\n")) {
                    const v = parseFloat(line.trim())
                    if (isNaN(v) || v <= 0) continue
                    if (best < 0 || v < best) best = v
                }
                root._latencyMs = best < 0 ? -1 : best * 1000
            }
        }
        onExited: function(code) {
            if (code !== 0 || root._latencyMs < 0) { root._fail("Couldn't reach " + root.endpoint); return }
            root._phase = "down"
            downProc.running = true
        }
    }

    // ── Download ──────────────────────────────────────────────────────────────
    // One curl, `downChunks` URLs, one -o per URL.
    //
    // That last part is not pedantry: -o applies to ONE transfer, so a single -o with
    // two URLs sends the second body to STDOUT — which here means 90MB of zeros
    // collected into StdioCollector's buffer. It is a silent memory bomb that "works"
    // in the sense that the numbers still parse.
    //
    // -w fires once per transfer, so this emits `downChunks` lines. They're combined as
    // total-bytes over total-time, not by averaging the per-chunk rates: a mean of two
    // rates weights a slow chunk exactly as heavily as a fast one regardless of how
    // long each took, which isn't what "how fast was the transfer" means.
    //
    // Honesty about the size of this: on the real numbers here (1.66s and 1.47s) the
    // two methods differ by 0.4% — the chunks come out near-equal, so it barely
    // matters. It's insurance, not a correction: on chunks of 8s and 1s the mean reads
    // over 30% high, and a stalled first chunk is exactly when you'd want the number to
    // be right.
    property var _downCmd: {
        const cmd = ["curl", "-s"]
        for (let i = 0; i < root.downChunks; i++) cmd.push("-o", "/dev/null")
        // 180s, sized for the slow link rather than this one: 360MB at 20 Mbps is 144s.
        // The timeout is a stuck-connection backstop, not a test duration — cutting a
        // slow link off mid-transfer would report its speed as whatever it managed
        // before the axe fell.
        cmd.push("-w", "%{size_download} %{time_total}\\n", "--max-time", "180")
        for (let i = 0; i < root.downChunks; i++)
            cmd.push("https://" + root.endpoint + "/__down?bytes=" + root.downBytes)
        return cmd
    }

    Process {
        id: downProc
        command: root._downCmd
        stdout: StdioCollector {
            onStreamFinished: {
                let bytes = 0, secs = 0
                for (const line of text.trim().split("\n")) {
                    const p = line.trim().split(/\s+/)
                    if (p.length < 2) continue
                    const b = parseFloat(p[0]), t = parseFloat(p[1])
                    if (isNaN(b) || isNaN(t)) continue
                    bytes += b
                    secs  += t
                }
                // A 403 still "succeeds": curl exits 0 having fetched a 1-byte error
                // body, which would report as a link speed of about 17 B/s. Requiring a
                // plausible payload is what catches that — the endpoint's cap is a
                // moving target and this is the tripwire for the day it moves again.
                root._downBps = (secs > 0 && bytes > root.downBytes / 2) ? bytes / secs : -1
            }
        }
        onExited: function(code) {
            if (code !== 0 || root._downBps < 0) { root._fail("Download test failed"); return }
            root._phase = "up"
            upProc.running = true
        }
    }

    // ── Upload ────────────────────────────────────────────────────────────────
    // /dev/zero through a pipe: no temp file to create, find writable space for, and
    // clean up when the test is cancelled halfway.
    //
    // `-T -` rather than `--data-binary @-`, and the difference is not cosmetic:
    // --data-binary reads stdin to the END before sending, so a 200MB upload becomes
    // 200MB resident in curl. -T streams it. At the old 100MB that was merely wasteful;
    // at 200MB it's a quarter-gig of zeros in RAM to measure a network.
    Process {
        id: upProc
        command: ["bash", "-c",
                  "head -c " + root.upBytes + " /dev/zero | curl -s -o /dev/null "
                + "-w '%{speed_upload}' --max-time 90 "
                + "-H 'Content-Type: application/octet-stream' "
                + "-T - 'https://" + root.endpoint + "/__up'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text.trim())
                root._upBps = isNaN(v) ? -1 : v
            }
        }
        onExited: function(code) {
            if (code !== 0 || root._upBps < 0) { root._fail("Upload test failed"); return }
            root._phase = "done"
        }
    }

    // ── Formatting ────────────────────────────────────────────────────────────
    // DECIMAL megabits, deliberately — and note this disagrees with NetStats.rate(),
    // which uses binary MB/s. Both are right for what they measure: NetStats prints
    // the kernel's byte counters, which are binary quantities, while a link rate is
    // quoted in Mbps by every ISP, router and speed test on earth. Printing "83 MiB/s"
    // next to a plan sold as "500 Mbps" would be technically defensible and useless.
    function mbps(bytesPerSec) {
        if (bytesPerSec < 0) return "—"
        const m = bytesPerSec * 8 / 1000000
        return (m < 10 ? m.toFixed(1) : Math.round(m)) + " Mbps"
    }

    function ms(v) {
        if (v < 0) return "—"
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + " ms"
    }

    // Derived from the transfer sizes rather than typed as a literal — the card used to
    // say "~35 MB" next to constants that had since changed, which is the whole reason
    // to compute it. Decimal MB to match how the sizes are declared.
    readonly property string dataCostLabel: Math.round(root.totalBytes / 1000000) + " MB"

    // ── The meters' ceiling ───────────────────────────────────────────────────
    // A drawing decision, not a measurement — the number beside the bar is the answer.
    //
    // This started as a flat 100 Mbps and that was measured wrong within a minute of
    // writing it: this link tested at 306 Mbps down, so both bars pegged at full and
    // the meter conveyed nothing. The mirror of the dBm axis mistake — a fixed scale
    // covering a range the machine never visits.
    //
    // So it climbs a ladder of round numbers to the first rung above the result. NOT
    // to max(down, up) itself, which would always draw the faster direction as a full
    // bar and render a 5 Mbps line identically to a gigabit one. A rung means the two
    // bars stay comparable to each other AND keep a sense of absolute scale — and the
    // chosen rung is printed, same rule as the throughput peak and the signal axis:
    // a scale that moves is honest exactly as long as it says where it moved to.
    readonly property var _ladderMbps: [10, 25, 50, 100, 250, 500, 1000, 2500]

    readonly property real meterCeilingBps: {
        const best = Math.max(root._downBps, root._upBps)
        if (best <= 0) return root._ladderMbps[3] * 1000000 / 8      // un-run: 100 Mbps
        const mbps = best * 8 / 1000000
        for (const rung of root._ladderMbps)
            if (mbps <= rung) return rung * 1000000 / 8
        return root._ladderMbps[root._ladderMbps.length - 1] * 1000000 / 8
    }

    readonly property string meterCeilingLabel: Math.round(root.meterCeilingBps * 8 / 1000000)
                                              + " Mbps"
}
