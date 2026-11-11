import QtQuick
import "../config"

// ── SpringReveal ── a page's entrances (Screen time, the voice board) ──────────────────────────────────────────────
// 0 → 1 on a spring when `when` turns true, `delay` ms late (a row of bars passes it its place in the row, so
// they rise one after another); straight back to 0 when it turns false. A page binds `when` to "I am the page
// on show", so what it draws grows in each time the page slides in — a bar chart that was already full when
// you looked at it has nothing to show you.
//
// The default spring overshoots a little, so a bar lands with a bounce. Bind `value` to a size or a scale;
// anything that fades wants `Math.min(1, value)`.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property bool when: false
    property int delay: 0
    property var spec: Motion.springSpatialSlow

    readonly property real value: root._sp.value

    property bool _up: false
    onWhenChanged: { if (root.when) root._t.restart(); else root._up = false }
    Component.onCompleted: if (root.when) root._t.restart()

    property Timer _t: Timer {
        interval: Math.max(1, root.delay)
        onTriggered: root._up = root.when
    }
    property SpringValue _sp: SpringValue {
        target: root._up ? 1 : 0
        spec: root.spec
    }
}
