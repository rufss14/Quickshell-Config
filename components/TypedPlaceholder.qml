import QtQuick
import Quickshell
import "../config"

// ── TypedPlaceholder ──────────────────────────────────────────────────────────
// The empty search field that TYPES its own hints: "Search apps", then after it the key to
// press in the accent and what it does — `? ask Claude`, `12*8 calculate` — held long enough to
// read, erased faster than it was typed, then the next. It teaches a field's powers while it is
// empty, and goes away the moment you type. This is the launcher's, lifted out of
// LauncherField so the settings search and the wallpaper search have exactly the same one.
//
// One timer whose interval is the current phase's delay: changing the phase changes the
// interval, which restarts the timer, so no step needs its own. With motion off it shows the
// first hint, whole, and never ticks. It only runs while it is actually visible, so a collapsed
// or hidden field costs nothing.
//
// ── What the caller gives it ──────────────────────────────────────────────────
//   lead         what stays put ("Search apps")
//   hints        [{ key, text }] typed after it; `text` may be empty (just a word)
//   placeholder  what shows when there are no hints
//   separator    between the lead and the hint
//
// `visible` is the caller's: bind it to "the field is empty". Nothing in the markup is an
// outside string left unescaped.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: typer

    property string placeholder: ""
    property string lead: ""
    property var    hints: []
    property string separator: "  ·  "
    property string variant: "body"
    property color  textColor: Colors.of(QsWindow.window).fgDim
    property color  keyColor:  Colors.of(QsWindow.window).primary

    clip: true

    readonly property var tails: typer.hints
    readonly property bool typing: typer.hints.length > 0
    readonly property bool cycling: typer.typing && typer.visible && Motion.standard > 0
    property int    idx: 0
    property int    n: 0
    property string phase: "gap"        // type | hold | erase | gap

    readonly property var cur: typer.typing ? typer.tails[typer.idx % typer.tails.length] : null
    readonly property string full: typer.cur
        ? typer.cur.key + ((typer.cur.text ?? "") !== "" ? " " + typer.cur.text : "") : ""
    readonly property string shown:
        Motion.standard > 0 ? typer.full.slice(0, typer.n) : typer.full

    // Hold long enough to read; erase faster than it was typed.
    readonly property int delay: typer.phase === "type" ? 42
                               : typer.phase === "hold" ? 2200
                               : typer.phase === "erase" ? 18 : 380

    // New hints (the provider changed): start over rather than index off the end.
    onTailsChanged: { typer.idx = 0; typer.n = 0; typer.phase = "gap" }

    function advance() {
        if (typer.phase === "type") {
            typer.n++
            if (typer.n >= typer.full.length) typer.phase = "hold"
        } else if (typer.phase === "hold") {
            typer.phase = "erase"
        } else if (typer.phase === "erase") {
            typer.n--
            if (typer.n <= 0) { typer.n = 0; typer.phase = "gap" }
        } else {
            typer.idx = (typer.idx + 1) % typer.tails.length
            typer.phase = "type"
        }
    }

    Timer {
        repeat: true
        interval: typer.delay
        running: typer.cycling
        onTriggered: typer.advance()
    }

    function esc(t) {
        return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // The key you press in the accent, the rest dim. Authored here — no outside string
    // goes into markup unescaped.
    readonly property string markup: {
        if (!typer.typing) return typer.esc(typer.placeholder)
        const k = typer.cur ? typer.cur.key.length : 0
        const keyPart  = typer.shown.slice(0, k)
        const restPart = typer.shown.slice(k)
        return typer.esc(typer.lead)
             + (typer.shown !== ""
                ? typer.separator
                  + '<b><font color="' + typer.keyColor + '">' + typer.esc(keyPart) + "</font></b>"
                  + typer.esc(restPart)
                : "")
    }

    StyledText {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        rich: true
        text: typer.markup
        variant: typer.variant
        color: typer.textColor
        elide: Text.ElideRight
    }
}
