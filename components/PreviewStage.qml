import QtQuick
import Quickshell
import "../config"

// ── PreviewStage ──────────────────────────────────────────────────────────────
// The recessed box a live preview sits in. One shape for every "what will this look
// like" on the settings pages, so a specimen, a mock window and a lock-screen
// schematic all read as the same kind of object: a thing being SHOWN to you, not
// another control you can touch.
//
// ── Why it is recessed and checkered ──────────────────────────────────────────
// Two of the things previews here have to show — surface opacity and cast shadow —
// are invisible against a flat fill of the same colour. A card at 70% opacity on top
// of a plain card just looks like a slightly different card; over a checkerboard it
// obviously has something behind it. The checks are deliberately low-contrast: they
// are a backdrop, not a pattern anyone should be reading.
//
// The stage is DARKER than the card it sits in (mixed toward `base`), which is what
// makes it read as a well rather than a tile — the same inversion the elevation
// ladder uses everywhere else in the shell.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property int padding: Tokens.spacingLg

    // Checks are sized in device pixels, not scaled by density: they are texture,
    // and texture that grows with the type scale stops being texture.
    property int checkSize: 8
    property bool checkered: true

    default property alias content: inner.data

    radius: Tokens.radiusSm
    color:  Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested), Colors.of(QsWindow.window).base, 0.65)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
    clip: true

    // ── The CALLER sizes the stage ────────────────────────────────────────────
    // This was `inner.childrenRect.height + padding * 2`, and it is a binding loop
    // whenever the content fills the stage — MiscPage's hover MouseArea and
    // HyprTuningPage's mock window both do `anchors.fill: parent`, so the child's
    // height came from the stage's height, which came from the child's.
    // ("Binding loop detected for property implicitHeight", on every open.) Every
    // call site already sets Layout.preferredHeight, or derives it from its content
    // the way WidgetStylePage does (`tiles.implicitHeight + stage.padding * 2`) —
    // so this is only the floor for one that forgets: an empty well, not a loop.
    implicitHeight: root.padding * 2

    Canvas {
        id: checks
        anchors.fill: parent
        visible: root.checkered
        opacity: 0.5

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: Colors
            function onDataChanged() { checks.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const s = Math.max(2, root.checkSize)
            // One tone over the stage's own fill: the squares are a shade of the
            // surface, never a hardcoded grey, so the backdrop follows the palette.
            ctx.fillStyle = Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
            for (let y = 0; y < height; y += s) {
                for (let x = 0; x < width; x += s) {
                    if (((x / s) + (y / s)) % 2 === 0) continue
                    ctx.fillRect(x, y, s, s)
                }
            }
        }
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
