import QtQuick
import "../config"

// ── ArmLatch ──────────────────────────────────────────────────────────────────
// Click once to arm, again to confirm. Disarms itself after a few seconds.
//
// ── Why a latch and not an ArmedButton ────────────────────────────────────────
// There were five copies of this — WallpaperPanel's tile and row, WallpaperPage's
// tile, StoragePage's clean button, SoundPage's restart button — and the obvious
// extraction, a button component, was the wrong one: their VISUALS have nothing in
// common. One is a ✕ on a hovered tile, one is a row's trailing icon, two are
// PanelButtons that swap their own label to ask the question ("Remove them?", "Sure?
// Audio will cut out"). Only the state machine repeated.
//
// So this is non-visual. The caller keeps its own appearance and binds it to `armed`.
//
// ── What the copies had drifted on ────────────────────────────────────────────
//   · Two used `Timer { running: armed }` and two used `disarm.restart()`. The first
//     form is the correct one — it restarts on every re-arm for free — and the second
//     only worked because every caller remembered to call restart() by hand.
//   · The 4000ms was written out five times.
//   · StoragePage's copy arms only for its "risky" case and fires immediately
//     otherwise, which is a real requirement (`armWhen`), not an inconsistency.
//
// ── Use ───────────────────────────────────────────────────────────────────────
//     ArmLatch { id: latch; onConfirmed: Wallpaper.remove(tile.key) }
//     ...
//     onClicked: latch.trigger()
//     label: latch.armed ? "Remove it?" : "Remove"
//
// A latch that goes away while armed (a tile scrolled out of a Repeater, a panel
// closed) simply takes its state with it — there is nothing to clean up, which is why
// this holds no reference to whatever it is guarding.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // Long enough to read the question and act on it, short enough that a button left
    // armed can't be confirmed by an unrelated click a minute later — which is the
    // whole failure mode the timeout exists to prevent.
    property int timeoutMs: 4000

    // Set false to fire on the first trigger() without arming. For a control that is
    // only sometimes destructive: StoragePage arms for orphan removal and goes straight
    // through for everything else, from one code path.
    property bool armWhen: true

    readonly property bool armed: root._armed
    property bool _armed: false

    signal confirmed()

    // The whole interaction. Returns true if this call CONFIRMED (so a caller that
    // wants to do something else on the arming click can tell the two apart); false if
    // it only armed.
    function trigger() {
        if (!root.armWhen) { root.confirmed(); return true }
        if (root._armed) {
            root._armed = false
            root.confirmed()
            return true
        }
        root._armed = true
        return false
    }

    // Cancel without firing — for a caller that arms and then has the ground move under
    // it (the list it belongs to reloads, the panel switches view).
    function disarm() { root._armed = false }

    // `running: _armed` rather than an explicit restart(): re-arming stops and starts
    // the timer on its own, so no caller has to remember to.
    property Timer _disarm: Timer {
        running: root._armed
        interval: root.timeoutMs
        onTriggered: root._armed = false
    }
}
