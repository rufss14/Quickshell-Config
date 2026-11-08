import QtQuick
import Quickshell
import "../config"

// ── Scrollbar ─────────────────────────────────────────────────────────────────
// A thin indicator strapped to a Flickable. Shows while you scroll, fades when you
// stop, thickens under the pointer, and drags.
//
// ── Why not QtQuick.Controls.ScrollBar ────────────────────────────────────────
// Because this shell contains zero QtQuick.Controls, and one scrollbar is a poor
// reason to start. Controls brings a styling system with its own opinions about
// palettes, fonts and control sizing — a second design system living beside the one
// in config/, and every widget that ever touches it has to be argued back into line.
// The visible part of a scrollbar is a rounded rect; the fiddly part is the geometry,
// and that's twenty lines either way.
//
// ── The geometry, since it's the only real content here ───────────────────────
// Flickable gives contentY (how far down), contentHeight (how tall the content is)
// and height (how tall the window is). From those:
//     size     = height / contentHeight        → the handle's fraction of the track
//     position = contentY / contentHeight      → the handle's offset down the track
// Both are fractions of the CONTENT, which is why the handle shrinks as content grows
// — that's the length cue that tells you how much you can't see.
//
// Usage — attach, don't nest:
//     Flickable { id: flick; ... }
//     Scrollbar { flickable: flick }
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property Flickable flickable

    // Thin at rest, thicker when you're actually aiming at it. A scrollbar is furniture
    // until you reach for it, and then it's a target.
    property int thickness: 4
    property int hoverThickness: 8

    // ── Where it lives ────────────────────────────────────────────────────────
    // Reparented to the Flickable's PARENT and anchored across it — NOT parented to the
    // Flickable itself, which is the obvious move and is wrong: a Flickable reparents
    // its children into `contentItem`, so a scrollbar declared inside one scrolls away
    // with the content it's supposed to be measuring.
    //
    // Done here rather than at the call site because there is exactly one sane position
    // for a vertical scrollbar, and making six call sites restate it is how they drift
    // apart by a pixel. Declare it as a sibling of the Flickable and it puts itself in
    // the right place:
    //     Flickable { id: flick; ... }
    //     Scrollbar { flickable: flick }
    parent: root.flickable.parent
    anchors.right:  root.flickable.right
    anchors.top:    root.flickable.top
    anchors.bottom: root.flickable.bottom
    anchors.rightMargin: Tokens.spacingXs
    width: root.hoverThickness

    // ── Present only when it means something ──────────────────────────────────
    // A scrollbar on content that fits is a control that can't do anything: the handle
    // fills the track and dragging it moves nothing. Absent is the honest state, and
    // it's why every Flickable in the shell can take one of these unconditionally.
    readonly property bool scrollable: root.flickable.contentHeight > root.flickable.height + 1

    readonly property real _size: root.scrollable
        ? Math.max(root.flickable.height / root.flickable.contentHeight, 0.06)
        : 1
    readonly property real _pos: root.scrollable
        ? Math.max(0, Math.min(1 - root._size,
                   root.flickable.contentY / root.flickable.contentHeight))
        : 0

    visible: root.scrollable

    // ── When it shows ─────────────────────────────────────────────────────────
    // Visible while moving, while you're pointing at it, and while you're dragging it —
    // then it fades. `moving` covers flicks and wheel; the drag case has to be explicit
    // because dragging the handle sets contentY directly and never makes the Flickable
    // "move" in its own sense.
    readonly property bool _active: root.flickable.moving || hover.hovered || drag.active

    opacity: root._active ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // The track. Only under the pointer: a permanent groove is a line down the edge of
    // every panel, and the handle alone says everything the groove would.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: width / 2
        color: hover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        width: hover.hovered || drag.active ? root.hoverThickness : root.thickness
        radius: width / 2
        color: drag.active  ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.55)
             : hover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.42)
                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.28)

        y:      root._pos  * root.height
        height: root._size * root.height

        Behavior on width { NumberAnimation { duration: Motion.fast } }
        Behavior on color { ColorAnimation  { duration: Motion.fast } }
        // NOTE: no Behavior on y or height. They track contentY, which is already
        // animated by the Flickable's own physics — a Behavior here would be a second
        // animation chasing the first, which is the exact trap Motion.qml documents.
    }

    HoverHandler { id: hover }

    // ── The wheel ─────────────────────────────────────────────────────────────
    // Flickable's own wheel is a flick: each notch adds velocity and the page coasts on, which
    // the user found "weird" (2026-10-31). Every Flickable with one of these instead moves
    // `wheelStep` per notch, eased (Motion.fast, a notch mid-ease adds to where it is going),
    // and a touchpad's pixel delta exactly that far, unanimated. At either end the event is
    // left alone, so an outer page can scroll on. A slider under the pointer passes a plain
    // wheel up (ValueSlider.wheelNeedsModifier), so scrolling past one no longer moves it.
    //
    // The handler is created AS the Flickable's child — a handler declared here and given
    // `parent: flickable` stays on this item (measured, Qt 6.12, qmltestrunner) — and it lands
    // on the content item, under everything the Flickable scrolls. Accepting keeps the
    // Flickable from flicking. `smoothWheel: false` gives a Flickable its own wheel back.
    property bool smoothWheel: true
    property real wheelStep: Tokens.spacingXl * 4
    property real _wheelTo: 0
    NumberAnimation {
        id: wheelAnim
        target: root.flickable
        property: "contentY"
        duration: Motion.fast
        easing.type: Motion.travel
    }
    function _wheel(e) {
        const f = root.flickable
        const lo = f.originY, hi = f.originY + Math.max(0, f.contentHeight - f.height)
        const clamp = y => Math.max(lo, Math.min(hi, y))
        if (!root.smoothWheel || hi <= lo || (e.angleDelta.y === 0 && e.pixelDelta.y === 0)) {
            e.accepted = false
            return
        }
        if (e.pixelDelta.y !== 0) {
            wheelAnim.stop()
            const y = clamp(f.contentY - e.pixelDelta.y)
            e.accepted = y !== f.contentY
            f.contentY = y
            return
        }
        const from = wheelAnim.running ? root._wheelTo : f.contentY
        const to = clamp(from - e.angleDelta.y / 120 * root.wheelStep)
        if (to === from) { e.accepted = false; return }
        root._wheelTo = to
        wheelAnim.to = to
        wheelAnim.restart()
        e.accepted = true
    }
    Component {
        id: wheelComponent
        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (e) { root._wheel(e) }
        }
    }
    property var _wheelHandler: null
    Component.onCompleted: root._wheelHandler = wheelComponent.createObject(root.flickable)
    Component.onDestruction: if (root._wheelHandler) root._wheelHandler.destroy()

    DragHandler {
        id: drag
        target: null
        xAxis.enabled: false
        cursorShape: Qt.PointingHandCursor

        // Translate handle travel into content travel. The handle moves across
        // (1 - size) of the track while the content moves across (contentHeight -
        // height), so the ratio between them is the scale factor. Without it the
        // content lags the pointer by exactly the amount you can't see.
        property real _grabY: 0
        onActiveChanged: {
            if (drag.active) drag._grabY = root.flickable.contentY
            else root.flickable.returnToBounds()
        }
        onTranslationChanged: {
            if (!drag.active || !root.scrollable) return
            const travel = root.height * (1 - root._size)
            if (travel <= 0) return
            const scale = (root.flickable.contentHeight - root.flickable.height) / travel
            root.flickable.contentY = Math.max(0, Math.min(
                root.flickable.contentHeight - root.flickable.height,
                drag._grabY + drag.translation.y * scale))
        }
    }
}
