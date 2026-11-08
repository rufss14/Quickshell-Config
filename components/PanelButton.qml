import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── PanelButton ───────────────────────────────────────────────────────────────
// The action button inside a panel: "Connect", "Apply", "Cancel", "Save".
//
// Three variants, and they are not interchangeable:
//
//   primary   filled with the accent. The one thing this dialog is FOR. At most
//             one per row — if two buttons are both primary, neither is.
//   normal    outlined on a container fill. Secondary actions.
//   ghost     no chrome until hovered. For icon-only affordances (rescan, close,
//             reveal) where a border would be visual noise.
//
// Every panel had its own; WifiPanel alone had two (DialogButton + HeaderButton)
// that differed only in whether they had a label.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    Accessible.role: Accessible.Button
    Accessible.name: root.label !== "" ? root.label : root.symbol
    Accessible.onPressAction: root.activated()

    property string label:   ""
    property string glyph:   ""
    property string variant: "normal"     // "primary" | "normal" | "ghost"
    property color  accent:  Colors.of(QsWindow.window).primary
    // A capsule, with no outline, like the colours, clock and media panels' chips (the
    // settings pages ask for it; every other panel keeps the control corner).
    property bool   capsule: false

    // Tint the glyph independently — the wifi panel's eye toggle dims when the IP
    // is hidden and lights up when revealed.
    property color glyphTint: root.variant === "primary" ? Colors.of(QsWindow.window).fgOnPrimary
                                                         : Colors.of(QsWindow.window).fgMuted

    // ── symbol / symbolFill ───────────────────────────────────────────────────
    // A Material Symbols ligature name, e.g. "refresh". Wins over `glyph` when
    // set; `glyph` is untouched, so un-migrated call sites render exactly as
    // before and the migration can go one panel at a time. Same additive pattern
    // as IconButton — see the note there for why `symbolFill` is the point.
    property string symbol:     ""
    property real   symbolFill: 0
    // An SVG drawn as a stencil in the glyph's colour (TintedIcon), for a mark no
    // font has — Quickshell's gear on the shell-update button. Wins over glyph/symbol.
    property url    iconSource: ""
    // Rotates only the icon/glyph, not the button chrome — for a "working" spin
    // that shouldn't drag the hover fill around with it.
    property real   iconAngle:  0

    signal activated()

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isGhost:   variant === "ghost"

    implicitHeight: 32
    implicitWidth:  label !== ""
        ? Math.ceil(content.implicitWidth) + Tokens.spacingXl
        : implicitHeight                                  // icon-only ⇒ square

    // radiusPill, not radiusSm. Tokens is explicit that pill is "the interactive-
    // control corner" and card is the surface corner — a button at radiusSm was
    // opted out of the corner language, which is why a row of these sitting on a
    // radiusCard surface read as a set of little boxes rather than as controls
    // belonging to it.
    radius: root.capsule ? height / 2 : Tokens.radiusPill

    // NOTE: no `property bool enabled` — Item already has one, and redeclaring it
    // shadows the property QML uses to gate input. Item.enabled also propagates to
    // the MouseArea for free.
    opacity: enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    color: root.isPrimary
        ? Colors.of(QsWindow.window).alpha(root.accent, hover.containsMouse ? 0.92 : 0.78)
        : root.isGhost
            ? (hover.containsMouse ? Colors.of(QsWindow.window).alpha(root.accent, 0.18) : "transparent")
            : (hover.containsMouse ? Colors.of(QsWindow.window).stateHoverBg : Colors.of(QsWindow.window).surfaceContainer)

    border.width: (root.isPrimary || root.isGhost) ? 0 : Tokens.borderWidth
    border.color: root.capsule ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                               : Colors.of(QsWindow.window).outline

    Behavior on color { ColorAnimation { duration: Motion.respond } }

    // ── Lift and dip ──────────────────────────────────────────────────────────
    // The ripple below says WHERE you pressed; this says THAT you pressed. Together
    // they make a button feel like an object rather than a coloured rectangle that
    // changes shade. Both scales are small — a button that jumps is a button that
    // moves out from under the finger.
    scale: hover.pressed ? 0.95 : (hover.containsMouse && root.enabled ? 1.03 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: Motion.respond
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring
        }
    }

    // ── The press wave ────────────────────────────────────────────────────────
    // Declared before the content so it paints over this Rectangle's fill and under
    // the label — where M3 puts a state layer.
    //
    // `hoverOpacity: 0`: the fill above already answers hover, in three different
    // ways depending on variant. A second wash on top would just make hover darker
    // and undo the variant distinction.
    //
    // A PRIMARY button is filled with the accent, so an accent-coloured wave on it
    // would be invisible — it draws in the same colour its label does, which is the
    // only thing guaranteed to contrast against its own fill.
    StateLayer {
        id: ripple
        anchors.fill: parent
        layerColor: root.isPrimary ? Colors.of(QsWindow.window).fgOnPrimary : root.accent
        hovered: false
        hoverOpacity: 0
        radius: root.radius
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 5

        // Behind a Loader: PanelButton is everywhere and almost none set this, and a
        // TintedIcon is an Image + a MultiEffect mask. No size on the Loader — it
        // would pin the item (CLAUDE.md, API caution); it follows the icon's.
        Loader {
            active:  root.iconSource.toString() !== ""
            visible: active
            rotation: root.iconAngle
            sourceComponent: TintedIcon {
                source: root.iconSource
                color:  root.glyphTint
                size:   Tokens.iconMd
            }
        }

        MaterialIcon {
            visible: root.glyph !== "" && root.symbol === "" && root.iconSource.toString() === ""
            glyph:    root.glyph
            color:   root.glyphTint
            variant: "body"
            rotation: root.iconAngle
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        // Additive: wins where `symbol` is set, `glyph` sites fall through untouched.
        MaterialIcon {
            visible: root.symbol !== "" && root.iconSource.toString() === ""
            name:    root.symbol
            fill:    root.symbolFill
            color:   root.glyphTint
            rotation: root.iconAngle
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        // "label", not "caption". A button's text is the only thing telling you
        // what the button does — captions are for the footnote UNDER a row, and
        // rendering an action at footnote size and 70% opacity is what made a row
        // of these read as decoration rather than as things you can press.
        StyledText {
            visible: root.label !== ""
            text:    root.label
            color:   root.isPrimary ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
            opacity: root.isPrimary ? 1.0 : 0.85
            variant: "label"
            font.weight: root.isPrimary ? Font.DemiBold : Font.Medium
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()

        // onCanceled as well as onReleased — dragging off the button never fires a
        // release, and the wave would hang at full strength until the next press.
        onPressed:  function(m) { ripple.press(m.x, m.y) }
        onReleased: ripple.release()
        onCanceled: ripple.release()
    }
}
