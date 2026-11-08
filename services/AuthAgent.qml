pragma Singleton
import Quickshell
import Quickshell.Services.Polkit
import QtQuick
import "../config"

// ── AuthAgent ─────────────────────────────────────────────────────────────────
// The shell as the session's polkit authentication agent: when `pkexec`, a
// settings app or a package manager needs a password, the dialog is the shell's own
// (modules/panels/PolkitPopup) instead of a stock Qt window in the wrong colours.
//
// ── Opt-in, and exclusive by nature ───────────────────────────────────────────
// A session has ONE agent. If hyprpolkitagent / polkit-gnome / polkit-kde is already
// registered, polkit refuses the second and Quickshell logs "failed to register
// listener" — `registered` stays false and `blocker()` says why, rather than the
// toggle looking broken. So `Config.polkitAgent` defaults to off: a published shell
// must not evict somebody's working agent, or run with none if it crashes. Turning it
// on means taking the other one out of the autostart (see the Setup page).
//
// ── Gated by a LazyLoader ─────────────────────────────────────────────────────
// PolkitAgent registers in componentComplete and unregisters in its destructor, so
// the toggle is the loader's `active`: off, the agent doesn't exist and another one
// can have the session. `path` is left alone — Quickshell refuses to change it once
// set, and its default (/org/quickshell/Polkit) is what we want.
//
// ── What the view gets ────────────────────────────────────────────────────────
// `flow` is null whenever no request is in progress, which is also the instant a
// finished request vanishes — so the popup keeps its own copy of what it shows
// (the same rule as every fading surface here). The strings the request supplies
// belong to other processes; they go through polkit.js before anyone reads them.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.polkitAgent

    readonly property var  agent:      loader.item
    readonly property bool registered: root.agent ? root.agent.isRegistered : false
    readonly property bool active:     root.agent ? root.agent.isActive : false
    readonly property var  flow:       root.agent ? root.agent.flow : null

    // Why the toggle can't do its job, or "" — the same contract as NightLight.blocker().
    // `enabled` with no registration is the other-agent case; before the first
    // registration completes this reads the same for a few milliseconds.
    function blocker() {
        if (!root.enabled) return ""
        if (!root.registered)
            return Translation.tr("Another authentication agent already holds this session — stop hyprpolkitagent / polkit-gnome and restart the shell")
        return ""
    }

    function submit(text) {
        if (root.flow && root.flow.isResponseRequired) root.flow.submit(text)
    }

    function cancel() {
        if (root.flow) root.flow.cancelAuthenticationRequest()
    }

    LazyLoader {
        id: loader
        active: root.enabled

        PolkitAgent {}
    }
}
