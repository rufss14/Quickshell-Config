pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── NetApps ─────────────────────────────────────────────────────────────────
// Which applications are using the network, and what each is moving right now.
//
// ── Where the bytes come from, and why this needs no root ─────────────────────
// There is no per-process network byte counter in /proc — /proc/<pid>/io is DISK I/O,
// and /proc/<pid>/net/dev is per network NAMESPACE, so it reports identical interface
// totals for every process in it. The tools that do measure per-app throughput
// (nethogs, bandwhich) sniff packets and need root.
//
// But a TCP socket carries cumulative bytes_sent / bytes_received in TCP_INFO, and
// `ss -i` prints them for the caller's own sockets WITHOUT privilege. That's the whole
// mechanism: no root, no daemon, no new dependency.
//
// ── Why this is a RATE and not a session total ────────────────────────────────
// It was briefly a cumulative total, and that was the wrong call — recorded here so it
// doesn't get "fixed" back.
//
// A per-app total invites exactly one comparison: against the session figure beside it
// (NetStats' interface counters). It can never survive that comparison, because two
// chunks of traffic are permanently unattributable — connections that opened AND closed
// before this service started (the kernel kept no per-process record to find), and all
// QUIC traffic, which rides UDP/443 and has no TCP_INFO whatsoever. So the totals came
// out at a few hundred MB beside a 69 GB session and simply read as broken.
//
// A rate makes no such claim. "Right now, this app is moving X" is true on its own terms
// and isn't a share of anything, so the missing history costs it nothing. The interface
// counters stay the complete truth about the link; this stays the live, attributable
// slice — and the two no longer look like they disagree.
//
// ── Why a subprocess lives here and not in NetStats ───────────────────────────
// NetStats is FileView-only on purpose (its header explains why). This needs `ss`, a
// process, so it stays out of NetStats in its own refcounted service on a slow cadence,
// running only while something's looking.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }
    readonly property bool active: root._refs > 0

    // [{ name, connections, rxRate, txRate }] — bytes/sec, busiest first.
    readonly property var apps: root._apps
    property var _apps: []

    // Doubles as the rate window: rate is (bytes this sample) / interval.
    readonly property int interval: 2000

    // Per-socket cumulative bytes from the PREVIOUS sample, keyed "local|peer".
    // This map is the whole reason the numbers are trustworthy — see _parse.
    property var _prevSock: ({})

    Timer {
        running: root.active
        interval: root.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!ssProc.running) ssProc.running = true
    }

    // Clear on release so a reopened page starts from a clean baseline rather than
    // deltaing against sockets last seen minutes ago.
    onActiveChanged: {
        if (root.active) return
        root._apps = []
        root._prevSock = ({})
    }

    Process {
        id: ssProc
        // -t tcp, -i TCP_INFO (the byte counters), -n numeric (NO reverse DNS, or ss
        // blocks doing lookups on the very network it's reporting on), -p owning process.
        command: ["ss", "-tinp"]

        property var _lines: []
        stdout: SplitParser {
            onRead: function(line) { ssProc._lines.push(line) }
        }
        onExited: function(code) {
            root._parse(ssProc._lines)
            ssProc._lines = []
        }
    }

    // ── Parse ss -tinp ────────────────────────────────────────────────────────
    // TWO lines per socket:
    //   ESTAB 0 0  192.168.1.246:57621  192.168.1.133:50530  users:(("spotify",pid=88804))
    //        cubic wscale:6,10 ... bytes_sent:303 bytes_acked:303 bytes_received:417 ...
    // so the info line is attached to the connection line pending above it.
    //
    // Note the columns: WITHOUT -u there is no Netid column, so Local is [3] and Peer [4]
    // (with -tunp they were [4] and [5] — an easy off-by-one when changing the flags).
    //
    // Skipped:
    //   · non-ESTAB rows — a LISTEN socket is waiting, not carrying anything.
    //   · loopback peers (127.0.0.0/8, [::1]) — they never cross the wireless interface
    //     the traffic graph measures, so counting them would disagree with the graph.
    //     Not hypothetical: steam↔steamwebhelper sit on 127.0.0.1 having moved 725 KB,
    //     which would otherwise put steam top of the list for local IPC.
    //   · rows with no users:(()) — a kernel socket or another user's process; nothing we
    //     can name, and nothing we're privileged to attribute.
    function _parse(lines) {
        const socks = []
        let cur = null

        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim()
            if (t === "") continue

            // The info line for the connection parsed just above.
            if (t.indexOf("bytes_") !== -1 && cur !== null) {
                const mr = t.match(/bytes_received:(\d+)/)
                const ms = t.match(/bytes_sent:(\d+)/)
                cur.rx = mr ? parseInt(mr[1], 10) : 0
                cur.tx = ms ? parseInt(ms[1], 10) : 0
                socks.push(cur)
                cur = null
                continue
            }

            // Otherwise it should be a connection line; anything else clears the pending
            // one so a stray line can't glue the wrong bytes onto the wrong socket.
            if (t.indexOf("ESTAB") !== 0) { cur = null; continue }

            const cols = t.split(/\s+/)
            if (cols.length < 5) { cur = null; continue }

            const peer = cols[4]
            if (peer.startsWith("127.") || peer.startsWith("[::1]")) { cur = null; continue }

            // First named process on the socket. A forked socket lists several, but
            // they're the same program, so the first name is the answer.
            const m = lines[i].match(/users:\(\("([^"]+)"/)
            if (!m) { cur = null; continue }

            cur = { key: cols[3] + "|" + cols[4], proc: m[1], rx: 0, tx: 0 }
        }

        // ── Cumulative → rate, PER SOCKET ─────────────────────────────────────
        // Deltaing an app's SUMMED cumulative bytes would be wrong in both directions:
        // when a socket closes its bytes drop out of the sum and the delta goes negative,
        // and when one opens its pre-existing bytes appear as a burst that never
        // happened. Sockets churn constantly, so that error is the normal case, not an
        // edge case.
        //
        // So each socket is deltaed against its OWN previous value, and a first sighting
        // contributes 0 — it only establishes the baseline the next sample measures from.
        const prev = root._prevSock
        const next = ({})
        const rxBy = ({}), txBy = ({}), connBy = ({})

        for (let i = 0; i < socks.length; i++) {
            const s = socks[i]
            next[s.key] = { rx: s.rx, tx: s.tx }

            connBy[s.proc] = (connBy[s.proc] || 0) + 1
            if (!(s.proc in rxBy)) { rxBy[s.proc] = 0; txBy[s.proc] = 0 }

            const p = prev[s.key]
            if (!p) continue                       // first sight: baseline only
            // Clamped: a counter should never go backwards, but a reused key would look
            // like it had, and a negative would silently eat another socket's traffic.
            rxBy[s.proc] += Math.max(0, s.rx - p.rx)
            txBy[s.proc] += Math.max(0, s.tx - p.tx)
        }

        root._prevSock = next

        const dt = root.interval / 1000
        const out = []
        for (const name in connBy) {
            out.push({
                name:        name,
                connections: connBy[name],
                rxRate:      rxBy[name] / dt,
                txRate:      txBy[name] / dt
            })
        }
        // Busiest first — that's the question this list answers. Connection count breaks
        // ties so the order doesn't shuffle randomly among the idle ones.
        out.sort(function(a, b) {
            const d = (b.rxRate + b.txRate) - (a.rxRate + a.txRate)
            return d !== 0 ? d : b.connections - a.connections
        })
        root._apps = out
    }
}
