import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── SideCell ──────────────────────────────────────────────────────────────────
// One cell of a small sidebar module (SidePower, SideTools): a glyph in a sidebar
// cell (Config.sidebarCell), answering like a top-bar control — CellFeedback's tint
// on hover and ripple on press, the accent on the glyph while hovered or `active`.
//
// `armed` is a click-twice action one click away from firing (ArmLatch): the cell
// holds its warning tint, filled, until it fires or disarms itself — the colour
// can't be the only warning (on some palettes `danger` and `primary` are one
// ramp), so the glyph swaps to `armedGlyph` too, saying what the next click does.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: cell

    property string glyph: ""
    // A Material Symbols name instead of a codepoint (wins over `glyph`) — for the bar's
    // modules drawn as cells (SideBarModule), which name theirs. Either way the glyph
    // FILLS while `active` (its panel open, its state on).
    property string symbol: ""
    property string armedGlyph: ""
    property bool   active: false
    property bool   armed: false
    property color  accent: Colors.of(QsWindow.window).primary
    // What the glyph wears at rest: the top bar's idle foreground.
    property color  tint: Colors.of(QsWindow.window).stateIdleFg
    property color  warn: Colors.of(QsWindow.window).danger
    // For a module that animates its glyph (SideNotifications' bell swinging on an
    // arrival, SideClipboard's pop on a copy): turned and scaled about its centre.
    property real   glyphAngle: 0
    property real   glyphScale: 1
    // A live state behind the glyph (components/LiveShape): "" = nothing live. The glyph
    // shrinks onto the shape and wears `liveInk` there; `liveBeat` ticks a working state round.
    property string liveShape: ""
    // On the hero's chip (primaryContainer already) a live shape is filled `primary` instead,
    // or it would vanish into the chip.
    property color  liveTone: cell.hero ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).primaryContainer
    property color  liveInk:  cell.hero ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgOnPrimaryContainer
    property bool   liveBeat: false
    // The module's id, for its hover chip (modules/panels/HoverCard): resting on the cell
    // opens a chip of its name and state beside it (components/SideHover decides when).
    // "" = none. Not while its own panel is open (`active`) or while armed.
    property string hoverKind: ""
    // The sidebar's hero (Config.sidebarHero; SideRegionPills draws its chip). `hoverKind` is
    // the module's id, so the cell knows it is the one; its glyph wears the container's ink.
    readonly property bool hero: cell.hoverKind !== "" && Config.sidebarHero === cell.hoverKind
    // A value under the glyph — the top bar's "100%" / "18°C", in a cell: a count, a
    // reading. "" for none.
    property string caption: ""
    readonly property bool _captioned: cell.caption !== ""
    // The glyph itself, for something that rides its corner (the bell's count badge,
    // where the top bar puts one).
    readonly property Item glyphItem: glyphText

    readonly property bool hovered: mouse.containsMouse
    // The glyph rises a hair under the pointer, as the top bar's IconButton does. Its own
    // factor, so it never fights glyphScale (the bell's pop, the clipboard's).
    // The glyph also leans toward the pointer, a pixel at most (the top bar's magnet).
    MagnetLean {
        id: magnet
        active: cell.hovered && !cell.armed
        pointerX: mouse.mouseX
        pointerY: mouse.mouseY
        extentW: cell.width
        extentH: cell.height
    }
    // On the plate's own hover spring (CellFeedback.lift; its `hovered` is this same test).
    readonly property real _lift: feedback.lift

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    // Wheel over the cell, +1 up / -1 down — only for a module that sets `wheel`
    // (brightness, layout), so every other cell lets the wheel pass through.
    property bool wheel: false
    signal scrolled(int delta)

    width:  Config.sidebarCell
    height: Config.sidebarCell

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: cell.hovered && !cell.armed
        accent: cell.accent
        pointerX: mouse.mouseX
        pointerY: mouse.mouseY
        active: cell.active && !cell.armed
    }

    // Armed: the warning's own fill, standing, not only on hover.
    Rectangle {
        anchors.fill: parent
        radius: feedback.radius
        color: Colors.of(QsWindow.window).alpha(cell.warn, 0.22)
        opacity: cell.armed ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    LiveShape {
        id: live
        anchors.centerIn: parent
        width:  Config.sidebarCell - Tokens.spacingXs * 2
        height: width
        shape: cell.armed ? "" : cell.liveShape
        tone:  cell.liveTone
        beat:  cell.liveBeat
    }

    // The glyph, and under it the caption when there is one — then both at the TOP
    // BAR's sizes (its glyph, Tokens.iconMd × barIconScale; its label text, bold), so a
    // captioned cell reads like the bar's "☁ 18°C" turned on its side. Heights are the
    // pixel sizes, not the fonts' line boxes (a Nerd glyph's line box is far taller than
    // its ink), so the pair centres on what you see.
    Column {
        anchors.centerIn: parent
        spacing: cell._captioned ? Tokens.spacingXs : 0
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }

        MaterialIcon {
            id: glyphText
            anchors.horizontalCenter: parent.horizontalCenter
            height: font.pixelSize
            verticalAlignment: Text.AlignVCenter
            name: cell.armed ? "" : cell.symbol
            // Any cell, not only the ones that name a symbol: `glyph` resolves to a name
            // too, and a brand mark (no Material twin) has no axes, so ignores it.
            fill: cell.active ? 1 : 0
            weight: Config.sidebarGlyphWeight
            glyph: cell.armed && cell.armedGlyph !== "" ? cell.armedGlyph : cell.glyph
            font.pixelSize: cell._captioned ? Math.round(Tokens.iconMd * Config.barIconScale)
                                            : Config.sidebarGlyphPx
            rotation: cell.glyphAngle
            scale: cell.glyphScale * cell._lift * live.glyphScale
            color: cell.armed ? cell.warn
                 : live.live ? cell.liveInk
                 : cell.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                 : cell.hovered || cell.active ? cell.accent
                 : cell.tint
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: cell._captioned
            height: font.pixelSize
            verticalAlignment: Text.AlignVCenter
            text: cell.caption
            variant: "caption"
            sizeScale: Config.barFontScale
            font.bold: true
            color: glyphText.color
        }
    }

    SideHover {
        hovered: cell.hovered && cell.hoverKind !== ""
        from:    cell.hoverKind
        arg:     cell.hoverKind
        screen:  QsWindow.window ? QsWindow.window.screen : null
        enabled: !cell.active && !cell.armed
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feedback.press(m.x, m.y) }
        onReleased: feedback.release()
        onCanceled: feedback.release()
        onWheel: function (w) {
            if (!cell.wheel || w.angleDelta.y === 0) { w.accepted = false; return }
            cell.scrolled(w.angleDelta.y > 0 ? 1 : -1)
        }
        onClicked: function (m) {
            if (m.button === Qt.RightButton)       cell.rightClicked()
            else if (m.button === Qt.MiddleButton) cell.middleClicked()
            else                                   cell.clicked()
        }
    }
}
