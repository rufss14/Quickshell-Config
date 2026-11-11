import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideClaude ────────────────────────────────────────────────────────────────
// Your Claude Code sessions (services/ClaudeSessions) as one sidebar cell: Claude's
// mark, monochrome like every glyph on the edge (ClaudeBurst's `tint` — ClaudeGlyph's orange is
// the overview's, not the sidebar's).
//
//   working         the burst plays its animation, then rests a beat and plays again
//                   (components/ClaudeBurst) — not a constant redraw for the hour a
//                   session works (Motion's idle budget). Off with animations.
//   needs you       a warning-coloured dot that pulses, and the mark in the warning
//                   colour: a permission prompt or a question is waiting (hooks)
//   finished        an accent dot: a turn ended since you last opened the panel
//   none running    the mark dimmed
//
//   click   the panel, beside this button (again: shut it)
//   middle  go to the session that needs you (else the latest) in its terminal
//   right   Settings › Sidebar
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "claude" && root.ownsPanel

    readonly property bool working: ClaudeSessions.busyCount > 0
    readonly property bool needsYou: ClaudeSessions.needsYou.length > 0
    readonly property bool none: ClaudeSessions.sessions.length === 0
    // The sidebar's hero (Config.sidebarHero; SideRegionPills draws its chip): the mark wears
    // the container's ink, and a live shape on it is filled `primary` so it doesn't vanish.
    readonly property bool hero: Config.moduleHero("claude")

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // A session starting to need you, or finishing a turn: a peek beside it (EventPeek).
    // Counted against the last count, so a session list loading at start isn't an event.
    SidePeek { id: peek; from: "claude"; screen: root.screen }
    readonly property int needsN: ClaudeSessions.needsYou.length
    readonly property int freshN: ClaudeSessions.fresh.length
    property int _needsSeen: 0
    property int _freshSeen: 0
    onNeedsNChanged: {
        if (ClaudeSessions.ready && root.needsN > root._needsSeen && Config.peekClaude) peek.fire("claude")
        root._needsSeen = root.needsN
    }
    onFreshNChanged: {
        if (ClaudeSessions.ready && root.freshN > root._freshSeen && Config.peekClaude && !root.open) peek.fire("claude")
        root._freshSeen = root.freshN
    }
    Component.onCompleted: { root._needsSeen = root.needsN; root._freshSeen = root.freshN }

    function middle() {
        const s = ClaudeSessions.needsYou[0] ?? ClaudeSessions.sessions[0]
        if (s) ClaudeSessions.focus(s.pid)
    }

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: mouse.containsMouse
        active: root.open
    }

    // ── The state as a shape (LiveShape) ──────────────────────────────────────
    // Working: a cookie on the primary container, a petal's turn each beat. Needs you: a
    // burst in the warning tone. Finished or idle: nothing (the dot says "finished").
    LiveShape {
        id: live
        anchors.centerIn: parent
        width:  Config.sidebarCell - Tokens.spacingXs * 2
        height: width
        shape: root.needsYou ? "burst" : root.working ? "cookie9" : ""
        tone: root.needsYou ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.22)
            : root.hero ? Colors.of(QsWindow.window).primary
            : Colors.of(QsWindow.window).primaryContainer
        beat: root.working && !root.needsYou
    }

    // ── The mark: Claude's burst, playing while a session works ───────────────
    // components/ClaudeBurst (a sprite sheet, tinted like every glyph on the edge).
    // It plays the loop, rests, plays again, and a stop lets the loop finish — never a
    // constant redraw for the hour a session works.
    ClaudeBurst {
        anchors.centerIn: parent
        width:  Config.sidebarGlyphPx
        height: Config.sidebarGlyphPx
        playing: root.working
        tint: root.needsYou ? Colors.of(QsWindow.window).warning
            : root.working ? (root.hero ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgOnPrimaryContainer)
            : root.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer
            : mouse.containsMouse || root.open ? Config.moduleAccent("claude", Colors.of(QsWindow.window).primary)
            : root.none ? Colors.of(QsWindow.window).fgDim
            : Colors.of(QsWindow.window).stateIdleFg
        scale: mouse.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.respondCurve } }
        // Onto the shape, on the shape's own spring: a transform, so the press Behavior
        // above doesn't chase it.
        transform: Scale {
            origin.x: Config.sidebarGlyphPx / 2
            origin.y: Config.sidebarGlyphPx / 2
            xScale: live.glyphScale
            yScale: live.glyphScale
        }
    }

    // ── Needs you / finished ──────────────────────────────────────────────────
    Rectangle {
        id: dot
        readonly property bool shown: (root.needsYou || ClaudeSessions.anyFresh) && !root.open
        readonly property int size: Tokens.spacingSm * 2
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.margins: Config.sidebarCellPad
        width:  dot.size
        height: dot.size
        radius: dot.size / 2
        color: root.needsYou ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).primary
        scale: dot.shown ? 1 : 0
        visible: dot.scale > 0.01
        Behavior on scale {
            NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
        // Needs you: it keeps saying so (a channel — Motion.pulse, like the timer's bell).
        SequentialAnimation on opacity {
            running: root.needsYou && !root.open
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.35; duration: Motion.pulse * 1.5; easing.type: Motion.ambient }
            NumberAnimation { to: 1;    duration: Motion.pulse * 1.5; easing.type: Motion.ambient }
        }
    }

    SideHover {
        hovered: mouse.containsMouse
        from:    "claude"
        arg:     "claude"
        screen:  root.screen
        enabled: !root.open
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feedback.press(m.x, m.y) }
        onReleased: feedback.release()
        onCanceled: feedback.release()
        onClicked: function (m) {
            if (m.button === Qt.RightButton)       UiState.openSettingsTo("SidebarPage.qml")
            else if (m.button === Qt.MiddleButton) root.middle()
            else UiState.toggleSidePanel("claude", "claude", root.screen)
        }
    }
}
