import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"

// ── ClaudeBurst ───────────────────────────────────────────────────────────────
// Claude's burst, animated, in any colour. It is a SPRITE SHEET played by hand —
// assets/logos/claude-burst.png, made from the animated WebP the user supplied by
// scripts/claude-burst.py (which keys the orange plate out and says why Qt can't just
// play the WebP: no image plugin for it here). The sheet is white-on-transparent, so
// `tint` colours it (MultiEffect) like any monochrome glyph on the sidebar.
//
// At rest it shows the first frame — the full burst. While `playing` it plays the
// loop once, comes back to that frame, rests a beat and goes again. The rest is on
// purpose: the sidebar sits in the bar's window, and a constant 25 fps redraw for the
// hour a session works is exactly what the old 45° ticks were avoiding (Motion's idle
// budget). A stop lets the loop in flight finish, so the mark never freezes half-way.
//
// COLS / CELL / FRAMES / STEP_MS below are the sheet's: `scripts/claude-burst.py
// --check` fails if they disagree.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color tint: Colors.of(QsWindow.window).fg
    property bool playing: false

    readonly property int frames: 104
    readonly property int cols: 13
    readonly property int cell: 68
    readonly property int stepMs: 40

    property int frame: 0
    // Sheet pixels → this item's pixels.
    readonly property real k: root.width / root.cell

    implicitWidth: Tokens.iconLg
    implicitHeight: Tokens.iconLg

    SequentialAnimation {
        running: root.playing && Motion.slow > 0
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            target: root
            property: "frame"
            from: 0
            to: root.frames - 1
            duration: root.frames * root.stepMs
        }
        PropertyAction { target: root; property: "frame"; value: 0 }
        PauseAnimation { duration: Motion.slow * 2 }
    }

    // The window onto the sheet: the sheet slides behind a clip one cell wide, rather
    // than re-cutting the image (sourceClipRect) every frame.
    Item {
        id: stage
        width: root.width
        height: root.height
        clip: true
        visible: false          // drawn once, by the effect below

        Image {
            id: sheet
            source: Qt.resolvedUrl("../assets/logos/claude-burst.png")
            x: -(root.frame % root.cols) * root.cell * root.k
            y: -Math.floor(root.frame / root.cols) * root.cell * root.k
            width: sheet.implicitWidth * root.k
            height: sheet.implicitHeight * root.k
            smooth: true
            mipmap: true
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: stage
        colorization: 1.0
        colorizationColor: root.tint
    }
}
