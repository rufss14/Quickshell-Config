import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── ToggleChip ────────────────────────────────────────────────────────────────
// One yes/no in a checklist: an icon and a name, filled when on. For a SET of
// booleans that belong together (which modules stand on the sidebar) where thirteen
// roomy tiles would be thirteen cards each saying one word and one sentence.
//
// A tile (QuickToggleTile) is for a setting worth a sentence of its own. A chip is
// for membership — "is this one in the set" — and its state is the fill, the same
// way a selected ChipRow chip reads: filled accent wash when on, outline when off,
// so the chosen ones are the only weight in the row.
//
// `hint` is what the chip would do or why it can't; it is not drawn (there is no
// room) — it is the chip's tip (HelpTip) and what search matches it by
// (scripts/build-settings-index.py).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.description: root.hint
    Accessible.checkable: true
    Accessible.checked: root.active
    Accessible.onPressAction: if (root.available) root.toggled()

    property string symbol: ""      // a Material Symbols name…
    property string glyph:  ""      // …or the Nerd glyph a service's table still spells
    property string label:  ""
    property string hint:   ""
    property bool   active: false
    // A missing optional tool dims the chip and ignores the tap. The caller says why
    // somewhere visible (CLAUDE.md: disable with a reason, never fail on click).
    property bool   available: true
    property color  accent: Colors.of(QsWindow.window).primary

    signal toggled()

    readonly property bool hovered: hover.hovered && root.available

    implicitHeight: Tokens.fieldHeight
    implicitWidth:  row.implicitWidth + Tokens.spacingLg * 2
    radius: height / 2

    // A capsule with no outline (2026-10-26, the panels' chips): on is an accent wash, off a
    // fainter one that lifts under the pointer.
    color: root.active
        ? Colors.of(QsWindow.window).alpha(root.accent, root.hovered ? 0.30 : 0.22)
        : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, root.hovered ? 0.11 : 0.05)
    opacity: root.available ? 1.0 : 0.45

    Behavior on color { ColorAnimation { duration: Motion.respond } }
    Behavior on opacity      { NumberAnimation { duration: Motion.fast } }

    // Turning one on pops it (and off, a small dip) — the same acknowledgement a
    // picked ChipRow chip and a tile's chip make. Driven by the change, so a chip that
    // is merely on doesn't pulse.
    property real _pop: 1.0
    onActiveChanged: {
        popAnim.stop()
        popUp.to = root.active ? 1.10 : 0.94
        popAnim.start()
    }
    SequentialAnimation {
        id: popAnim
        NumberAnimation { id: popUp; target: root; property: "_pop"; duration: Motion.respond; easing.type: Motion.respondCurve }
        NumberAnimation {
            target: root; property: "_pop"; to: 1.0
            duration: Motion.standard
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
        }
    }
    scale: root._pop * (tap.pressed ? 0.95 : 1.0)

    HelpTip { text: root.hint }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            name:  root.symbol
            glyph: root.glyph
            fill:  root.active ? 1 : 0
            color: root.active ? root.accent : Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconMd
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text:    root.label
            variant: "caption"
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color:   root.active ? root.accent : Colors.of(QsWindow.window).fg
        }
    }

    HoverHandler { id: hover; cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler   { id: tap; enabled: root.available; onTapped: root.toggled() }
}
