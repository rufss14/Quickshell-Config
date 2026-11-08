pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Idle ──────────────────────────────────────────────────────────────────────
// "Should the screen be allowed to blank right now?" — one answer, with the list of
// who is currently saying no.
//
// ── Why a reason SET and not a boolean ────────────────────────────────────────
// Two independent things want to inhibit idle, and they overlap: you toggle the pill
// to watch something, and gamemode holds it for as long as it is on. With a single
// boolean, whichever one turned off last wins — quit the game while the pill is on
// and the screen starts blanking under you, because gamemode's exit cleared the same
// flag the pill had set.
//
// So holders are named, and the answer is "is anyone holding". Releasing a reason
// nobody is holding is a no-op rather than an error, which is what makes the
// paired-call discipline survivable: a service that crashes between hold and release
// leaks one name, not the whole subsystem.
//
// ── Where the actual Wayland object lives, and why not here ───────────────────
// `IdleInhibitor` requires a WINDOW — it inhibits while that window is mapped and
// visible, which is the protocol's whole model. A singleton has no window, so this
// file cannot own one. Bar.qml holds the real inhibitor and binds it to `inhibited`;
// see the note there about why one per screen is correct rather than wasteful.
//
// This split is deliberate: the POLICY (who wants what, and why) is testable, has no
// Wayland dependency, and is the part everything else talks to. The protocol object
// is three lines in the one place that already has a surface.
//
// ── Nothing here is persisted ─────────────────────────────────────────────────
// On purpose, and it is the whole reason `manual` isn't in Config. An inhibit that
// survives a reload is one you set for a two-hour film in October and rediscover in
// December, when you notice the machine has not slept since. Reload is the backstop
// that cannot be forgotten. Gamemode's hold is transient for the same reason — it is
// released when gamemode goes off, and gamemode itself does not survive a reload.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The pill's own hold ───────────────────────────────────────────────────
    // Kept separate from the named holds rather than being one of them, because it is
    // the only one a PERSON toggles — the pill has to know whether the current state
    // is theirs or somebody else's, and "is 'manual' in the list" reads worse at every
    // call site than a boolean does.
    property bool manual: false

    // ── Named holds ───────────────────────────────────────────────────────────
    // Reassigned wholesale rather than mutated: pushing into a bound array does not
    // notify, so a `holds.push(…)` would inhibit idle without anything on screen
    // changing to say so. The copy is three elements at worst.
    property var holds: []

    function hold(reason) {
        if (root.holds.indexOf(reason) !== -1) return
        root.holds = root.holds.concat([reason])
    }

    function release(reason) {
        const i = root.holds.indexOf(reason)
        if (i === -1) return                    // no-op, deliberately — see header
        const next = root.holds.slice()
        next.splice(i, 1)
        root.holds = next
    }

    function holding(reason) { return root.holds.indexOf(reason) !== -1 }

    function toggleManual() { root.manual = !root.manual }

    // ── The answer ────────────────────────────────────────────────────────────
    readonly property bool inhibited: root.manual || root.holds.length > 0

    // Inhibited by something that isn't the pill. The pill renders this differently:
    // a state you did not set, that your click will not clear, has to look different
    // from one that will — otherwise clicking the lit pill and watching it stay lit
    // reads as a broken button rather than as "the game is holding this".
    readonly property bool heldExternally: root.holds.length > 0

    // For the pill and for anything that wants to explain itself. Names are the raw
    // reason strings, so a holder should pass something a person can read.
    readonly property string reasonText:
          root.holds.length > 0 && root.manual ? "Held by " + root.holds.join(", ") + " and you"
        : root.holds.length > 0                ? "Held by " + root.holds.join(", ")
        : root.manual                          ? "Staying awake"
        :                                        "Normal"

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call idle toggle`
    //
    // Only ever touches `manual` — the named holds belong to the services that took
    // them, and a keybind that could release gamemode's hold behind its back would
    // leave gamemode believing it still had one.
    property var _ipc: IpcHandler {
        target: "idle"

        function toggle(): void { root.toggleManual() }
        function on(): void     { root.manual = true }
        function off(): void    { root.manual = false }

        // Reports the full picture, not just `manual`, because "why is my screen not
        // blanking" is the actual question someone runs this to answer.
        function status(): string { return root.reasonText }
    }
}
