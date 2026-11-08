pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"

// ── Pointer ───────────────────────────────────────────────────────────────────
// The global cursor position in compositor coordinates, for the wallpaper
// parallax and for following a SUPER-dragged window over the bar's workspace pill
// (`acquireFast`: a tight poll, held only for the length of that drag).
//
// ── Why this polls ────────────────────────────────────────────────────────────
// Hyprland's event socket does NOT emit pointer motion, and Quickshell's Hyprland
// singleton exposes no cursor property (verified against the qmltypes and every
// `Hyprland.*` call in this repo). A background-layer surface can't help either:
// a layer surface only receives pointer events where its input region is set, and
// setting one there would eat every click on the desktop. So the cursor has to be
// asked for.
//
// ── Asked over the socket, not through hyprctl ────────────────────────────────
// Each tick is one `j/cursorpos` request on Hyprland's request socket
// (Hyprland.requestSocketPath): a connect, one write, a 33-byte reply in ~0.03ms.
// It used to spawn `hyprctl -j cursorpos` per tick instead — ~3.3ms of CPU each,
// measured, nine a second for as long as the effect was on.
//
// ── WE close the connection, and that is load-bearing ────────────────────────
// Hyprland closes the request socket after every reply, Qt reports a peer close as
// QLocalSocket::PeerClosedError, and Quickshell's Socket logs every error as a
// WARNING (quickshell.io.socket). Left to Hyprland, this poll wrote nine warnings a
// second. So the parser disconnects the moment the reply's last field (`"y"`)
// lands, which Qt handles before it ever reads the EOF. Measured in a throwaway
// instance: Hyprland closing first, 10 replies / 10 warnings; us first, 20 / 0.
//
// ── A failed connect needs a NEW Socket ───────────────────────────────────────
// After a connect fails, Quickshell's Socket keeps its dead QLocalSocket and
// ignores every later `connected = true` (it only connects while it holds none) —
// measured: four attempts, one error, then silence. The old hyprctl poll retried on
// every tick for free; to keep that, the socket is built from a Component and
// thrown away after a failed connect, and the next attempt, ~5s later, gets a
// fresh one. The pause matters too: Quickshell logs each failure itself.
//
// ponytail: still a ~9/s poll while acquired. Gated hard — the timer only runs
// while something holds a ref AND Config.wallParallaxMouse > 0, so it costs nothing
// unless the effect is on. Upgrade path: a compositor push (Hyprland pointer event)
// or a Quickshell cursor property, whichever lands first.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Global cursor position. Starts at a harmless origin; the first poll
    // (~110ms after the first acquire) replaces it.
    readonly property point pos: Qt.point(root._x, root._y)
    property real _x: 0
    property real _y: 0
    // False until a poll has actually answered. `pos` is (0,0) before that, which a
    // consumer reads as the far corner of the screen: the wallpaper's parallax took it for
    // a pointer at the left edge and panned there, then slid to the real position once the
    // first reply landed — an "adjusting" picture. Wait for this before trusting `pos`.
    property bool known: false
    // `"x"` arrives a line before `"y"`; held until its pair lands, so `pos` never
    // mixes two different polls.
    property real _pendingX: 0

    // Ref-counted, like Hypr.acquire()/release(): the wallpaper surfaces take a
    // ref while the mouse effect is live and drop it when it's off or they're
    // torn down.
    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    // A window drag (Hyprland's own, which emits nothing while it moves) wants
    // the pointer at a rate a hover highlight can follow — and only for as long as
    // the drag lasts, so it isn't gated on the parallax setting.
    property int _fastRefs: 0
    function acquireFast() { root._fastRefs++ }
    function releaseFast() { root._fastRefs = Math.max(0, root._fastRefs - 1) }

    readonly property bool _active: (root._refs > 0 && Config.wallParallaxMouse > 0) || root._fastRefs > 0

    property var _sock: null
    // Ticks to sit out after a failed connect (see the header): 45 × 110ms ≈ 5s.
    property int _backoff: 0

    Timer {
        interval: root._fastRefs > 0 ? 33 : 110
        repeat: true
        running: root._active
        triggeredOnStart: true
        onTriggered: {
            if (root._backoff > 0) { root._backoff--; return }
            if (!root._sock) root._sock = sockComponent.createObject(root)
            // Still connected a whole tick later means a reply never finished: drop
            // it, and the next tick asks again.
            if (root._sock.connected) { root._sock.connected = false; return }
            root._sock.connected = true
        }
    }

    Component {
        id: sockComponent

        Socket {
            id: sock
            path: Hyprland.requestSocketPath

            onConnectionStateChanged: if (sock.connected) { sock.write("j/cursorpos"); sock.flush() }

            // `connected` is still true for a peer close (Hyprland hung up mid-reply
            // — harmless, the next tick asks again) and false for a connect that
            // failed, which is the one that strands this object.
            onError: {
                if (sock.connected) return
                root._backoff = 45
                root._sock = null
                sock.destroy()
            }

            // The reply is `{ "x": N, "y": N }`, one field per line.
            parser: SplitParser {
                onRead: function (line) {
                    const m = /"([xy])":\s*(-?\d+)/.exec(line)
                    if (!m) return
                    if (m[1] === "x") { root._pendingX = +m[2]; return }
                    root._x = root._pendingX
                    root._y = +m[2]
                    root.known = true
                    sock.connected = false
                }
            }
        }
    }
}
