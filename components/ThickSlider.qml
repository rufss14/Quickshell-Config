import QtQuick
import Quickshell
import "../config"

// ── ThickSlider ───────────────────────────────────────────────────────────────
// A fat slider: a tall rounded pill filled with the accent, a thin vertical handle bar
// standing a little clear of the fill, the rest of the track beyond it, and a small dot at
// the very end. The shape Caelestia's audio settings use for a volume, and the one this
// shell now uses for a player's own volume in the media panel. The look is borrowed; the
// code is this shell's own.
//
// ValueSlider is the hairline one (a 3px rail and a pinhead) for dense rows, WaveSlider the
// wavy one for a track you are scrubbing; this is for a level you set once and want to see.
//
// ── Three parts, with gaps ────────────────────────────────────────────────────
// [filled][gap][handle][gap][rest] — never one bar with a knob on it. The handle is a
// separate bar, taller than the track (and taller still while held), so it reads as
// something to grab even at 0% or 100%. At full the rest has no room left and fades away
// with its dot, instead of being drawn as a sliver.
//
// ── Where a press lands ───────────────────────────────────────────────────────
// A drag moves the value RELATIVE to where it was grabbed, so taking hold of the handle
// does not make it jump to the pointer; a plain click (no movement) puts it where you
// clicked. While held the fill follows the pointer with no easing at all — any lag between
// a hand and what it holds is felt as the slider being broken.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    property string accessibleName: ""
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName

    property real value:   0.0     // 0..maximum
    property real maximum: 1.0
    property color accent: enabled ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgFaint

    // ── An over-the-line zone, for a bar that has been unlocked past 100% ─────────
    // `notchAt` (in `value`'s units; -1 = none) marks where the ordinary range ends: a tick
    // across the track there, and the fill and handle turn `notchColor` once the value is
    // past it. A boost is a different thing from a level, and the bar says so while you drag.
    property real  notchAt:    -1
    property color notchColor: root.accent
    readonly property bool _over: root.notchAt > 0 && root.value > root.notchAt + 1e-6
    readonly property color _tone: root._over ? root.notchColor : root.accent

    // Emitted continuously while dragging, and once on a click.
    signal moved(real value)
    // +1 up, −1 down; the consumer decides the step.
    signal scrolled(int delta)

    readonly property alias pressed: area.pressed

    implicitWidth:  200
    // 18: thick enough to read as a fill and to grab, not the full 24 of the first cut.
    implicitHeight: Tokens.spacingXl + Tokens.spacingXs

    // ── Blocky, not a pill ────────────────────────────────────────────────────
    // The corners are a fixed share of the height (30%) instead of half of it, so the ends are
    // squared-off rather than round — the handle bar and the end dot follow. `_small` is the
    // tighter corner the fill and the rest turn toward the handle.
    property real radius: Math.round(root.height * 0.3)

    readonly property real _gap:     Tokens.spacingXs * 2
    readonly property real _handleW: Tokens.spacingXs * 2
    readonly property real _small:   Math.max(1, Math.round(root.radius * 0.4))   // the corners that face the handle

    property real _drag: 0
    readonly property real _frac: Math.max(0, Math.min(1, area.pressed ? root._drag : root.value / Math.max(1e-9, root.maximum)))

    // The fill's width. Eased on a key or a service change, pinned while held.
    property real _filled: (root.width - root._handleW - root._gap) * root._frac
    Behavior on _filled {
        enabled: !area.pressed
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    readonly property real _restW: Math.max(0, root.width - root._filled - root._handleW - root._gap * 2)
    // The rest fades as it runs out of room (below ~a dozen pixels) rather than as a sliver.
    readonly property real _restK: Math.min(root._restW, 12) / 12

    // The rest of the track.
    Rectangle {
        x: root._filled + root._handleW + root._gap * 2
        anchors.verticalCenter: parent.verticalCenter
        width:  root._restW
        height: root.height * root._restK
        opacity: root._restK
        radius: root.radius
        topLeftRadius:    root._small
        bottomLeftRadius: root._small
        color: Colors.of(QsWindow.window).alpha(root.accent, 0.22)
    }
    // …and its end dot.
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: root._gap * 2
        anchors.verticalCenter: parent.verticalCenter
        width: Tokens.spacingXs * 2 * root._restK
        height: width
        radius: width * 0.3
        opacity: root._restK
        color: root.accent
    }

    // The fill.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width:  root._filled
        height: root.height
        radius: root.radius
        topRightRadius:    root._small
        bottomRightRadius: root._small
        color: root._tone
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // The tick where the ordinary range ends. On the track it is the notch colour; once the fill
    // has passed it, the track's own dark, so it stays legible on the fill.
    Rectangle {
        visible: root.notchAt > 0 && root.notchAt < root.maximum
        readonly property real at: (root.width - root._handleW - root._gap) * (root.notchAt / Math.max(1e-9, root.maximum))
                                   + root._gap + root._handleW / 2
        x: at - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.height * 0.6
        radius: 1
        color: root._over ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.55)
                          : Colors.of(QsWindow.window).alpha(root.notchColor, 0.8)
    }

    // The handle: a bar a little taller than the track, taller still while held.
    Rectangle {
        id: handle
        x: root._filled + root._gap
        anchors.verticalCenter: parent.verticalCenter
        width:  root._handleW
        height: root.height * (area.pressed ? 1.5 : 1.2)
        radius: Math.min(width / 2, root._small)
        color:  root._tone
        Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Motion.respondCurve } }
        Behavior on color  { ColorAnimation  { duration: Motion.respond } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        // Reach a little past the track, so the taller handle is easy to take hold of.
        anchors.topMargin:    -Tokens.spacingSm
        anchors.bottomMargin: -Tokens.spacingSm
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        property real pressX: 0
        property real startFrac: 0
        property bool dragged: false

        function span() { return Math.max(1, root.width - root._handleW - root._gap) }

        onPressed: function (m) {
            area.pressX = m.x
            area.startFrac = root._frac
            area.dragged = false
            root._drag = root._frac
        }
        onPositionChanged: function (m) {
            if (!pressed) return
            if (Math.abs(m.x - area.pressX) > 2) area.dragged = true
            if (!area.dragged) return
            root._drag = Math.max(0, Math.min(1, area.startFrac + (m.x - area.pressX) / area.span()))
            root.moved(root._drag * root.maximum)
        }
        onReleased: function (m) {
            // A click that never moved goes where it was made.
            if (area.dragged) return
            const f = Math.max(0, Math.min(1, (m.x - root._handleW / 2) / area.span()))
            root._drag = f
            root.moved(f * root.maximum)
        }
        onWheel: function (w) { root.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
