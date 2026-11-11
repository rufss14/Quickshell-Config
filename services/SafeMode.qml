pragma Singleton
import QtQuick
import Quickshell

// ── SafeMode ──────────────────────────────────────────────────────────────────
// QS_SAFE=1: the shell crashed twice while starting (scripts/shell-run.sh), so this run
// leaves out what can take the whole process down with it:
//   · the native blob plugin (state/Morph reports it unavailable: the plain QML morph)
//   · the ambient effects that run custom shaders and helpers (PowerSaver.quiet: the
//     cava background, wallpaper music effects, music pulse, the cookies)
// A reload (ALT+Q) starts a normal shell again. shell-run.sh posts the notification.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    readonly property bool on: (Quickshell.env("QS_SAFE") || "") === "1"
}
