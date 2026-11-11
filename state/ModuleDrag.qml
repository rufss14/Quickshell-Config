pragma Singleton

import Quickshell
import QtQuick

// ── ModuleDrag ────────────────────────────────────────────────────────────────
// The ONE module drag in flight, whichever surface it started on or is heading for:
// the top bar, the sidebar, or the settings window (2026-11-08).
//
// BarDrag and SideDrag each used to hold their own `dragId`/`dragging` and their own
// mime type, on purpose: a module could only live on the surface whose catalogue it
// came from, so neither surface's drop targets should light up for the other's. That
// stopped being true when every module grew both forms and the user asked for one
// page arranging both — so the gesture state is shared here, and one mime type means
// a module picked up on the bar can be dropped on the sidebar (and back), on the real
// surfaces and in the settings map alike.
//
// What stays per surface lives in BarDrag / SideDrag: where the pointer is as a target
// on THAT surface (`drop`, drawing only), what dropping there would do in words
// (`describe`), and the commit — through Config's mutators, which already take a
// module off the other surface when it lands on one (the one-place rule).
//
// A platform drag (`Drag.Automatic`, routed by the compositor) — see BarDrag's header
// for the measurements, the mime-type-not-`Drag.keys` rule and why nothing commits
// before the drop. Settings runs in this same process, so `dragId` is set for every
// drag the shell starts, wherever it is dropped; an id arriving with no `dragId` came
// from nowhere we know and is refused by the per-surface `idFromDrop`.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Vendor-prefixed so nothing else on the desktop is taken for a module. Every
    // drag source puts the id under it; every DropArea lists it in `keys`.
    readonly property string mime: "application/x-quickshell-module"

    // The module being dragged, or "".
    property string dragId: ""
    // True while one is in flight (set when the source's drag starts — Qt has applied
    // the platform's start distance by then — and cleared on drop or cancel).
    property bool dragging: false
    // Where it was picked up: "bar" | "side" | "settings".
    property string from: ""

    function begin(id, from) {
        root.dragId   = id
        root.from     = from
        root.dragging = true
    }

    // Dropped, cancelled, or the source's drag finished. BarDrag / SideDrag clear their
    // own `drop` when `dragging` goes false.
    function end() {
        root.dragging = false
        root.dragId   = ""
        root.from     = ""
    }

    // The module id an incoming drag carries, or "" when it isn't one of ours. Which
    // surface may take it is the caller's question (BarDrag / SideDrag idFromDrop).
    function idFromDrop(d) {
        if (!d || !d.formats || d.formats.indexOf(root.mime) === -1) return ""
        return d.getDataAsString(root.mime)
    }
}
