import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../state"

// ── QuickToggleTile ───────────────────────────────────────────────────────────
// One switch in a quick-toggle grid: an icon, a label, a status
// line, and a single tap. Wi-Fi, Bluetooth, DND, Caffeine, Night Light, Gamemode
// are all this component pointed at a different service — none of them owns its
// own tile markup, so the grid can't drift the way the rest of a panel's rows do.
//
// Deliberately NOT `Toggle` (the switch) wearing a label: a switch is for a row
// that's already read left-to-right (see BluetoothPanel's header). A tile in a
// 2-column grid is tapped as a whole, the way the bar's own IconButton is — so it
// borrows that state ladder (idle / hover / active) rather than pairing an
// unrelated switch beside it.
//
// Also borrows IconButton's ripple wiring outright: a MouseArea driving
// StateLayer.press()/release() at the actual pointer position, not a second
// input handler layered on top (StateLayer's own header explains why that would
// silently steal hover from whatever handler owns the state ladder).
//
// ── The panels' card, with the state in the fill (2026-10-26) ─────────────────
// Off it is Section's flat `section` fill; on, the accent washes into it — no outline
// either way, the fill and the chip carry the state. It no longer lifts under the
// pointer: the light under it (PointerGlow) and the press squish answer the hand.
// The chip is Section's (ShapeBox), so a tile heading and a card heading are one object.
// Arrives like a Section does (see there): a view change stages it, the opening page doesn't.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.checkable: true
    Accessible.checked: root.active
    Accessible.onPressAction: if (root.available) root.toggled()

    property string symbol:   ""
    property string label:    ""
    property string subLabel: ""
    // The sentence that explains the setting — a tip when the pointer rests on the
    // tile (HelpTip). `subLabel` stays the short state line.
    property string help:     ""
    property bool   active:   false
    property color  accent:   Colors.of(QsWindow.window).primary

    // A missing optional backend (no Bluetooth adapter, no night-light tool)
    // disables the tile with its reason still on screen, rather than hiding it —
    // callers that want it hidden entirely just set `visible: false` themselves.
    property bool available: true

    // ── Roomy: the settings variant ───────────────────────────────────────────
    // Same control, twice the room. The compact variant packs these 60px tall into a
    // panel; a settings page gives a boolean a tile of its own, with the chip the rest of
    // the app uses for headings and space for a sentence under the label. One component
    // either way, because it is one control — a thing you tap that lights up.
    property bool roomy: false

    // How many columns of a bento grid this tile takes. Ignored outside one.
    property int span: 1
    // In a BentoGrid the grid widens the tile until its row is flush and the tile
    // stretches to the row's height (see Section). Elsewhere: the old clamp.
    Layout.columnSpan: (root.parent && root.parent.spanFor)
        ? root.parent.spanFor(root)
        : Math.min(root.span, (root.parent && root.parent.columns) ? root.parent.columns : 1)
    Layout.fillWidth: true
    Layout.preferredWidth: (root.parent && root.parent.pack === true) ? 0 : -1
    Layout.fillHeight: !!(root.parent && root.parent.pack === true)

    signal toggled()

    property int cornerRadius: Tokens.radiusCard
    implicitHeight: root.roomy ? 96 : 60

    readonly property bool actionable: root.available
    readonly property bool hovered: mouse.containsMouse && root.actionable

    opacity: root.available ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    scale: mouse.pressed ? 0.98 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.respond
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring
        }
    }

    // ── Arriving (see Section) ────────────────────────────────────────────────
    function _place() {
        const p = root.parent
        if (!p) return 0
        let n = 0
        for (let i = 0; i < p.children.length; i++) {
            const c = p.children[i]
            if (c === root) break
            if (c.visible && c.isAnchor !== true && c.implicitHeight > 0) n++
        }
        return n
    }
    property bool _arrive: false
    Component.onCompleted: {
        if (!UiState.settingsCascade) return
        card.opacity = 0
        enter.delay = Math.min(root._place(), 5) * Motion.stagger * 2
        Qt.callLater(function () { root._arrive = true })
    }
    ViewEnter { id: enter; target: card; active: root._arrive; rise: Tokens.spacingMd }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.cornerRadius

        // Slower than a hover wash: switching ON, the tint spreads in behind the ripple
        // the press started, so the fill reads as growing out of where you clicked.
        color: root.active
            ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).section, root.accent, 0.20)
            : root.hovered
                ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, Colors.of(QsWindow.window).fg, 0.06)
                : Colors.of(QsWindow.window).section
        Behavior on color { ColorAnimation { duration: Motion.emphasized; easing.type: Motion.respondCurve } }

        // The wave, painted above the fill and below the icon/text — same stacking
        // IconButton uses. `hoverOpacity: 0` because the fill above already carries
        // hover, louder; two hover tints would just be a darker hover with extra steps.
        StateLayer {
            id: ripple
            anchors.fill: parent
            visible: root.actionable
            layerColor: root.accent
            hoverOpacity: 0
            pressOpacity: 0.18
            radius: card.radius
        }

        // Passive, beside the MouseArea's own hover: the glow needs the pointer's
        // position, which a MouseArea only reports while it is the one being moved over.
        HoverHandler { id: tileHover; enabled: root.actionable }

        PointerGlow {
            visible: root.roomy
            hover:  tileHover
            color:  root.accent
            radius: card.radius
            edge:   Tokens.borderWidth
        }
    }

    HelpTip { id: tileTip; text: root.help }

    // ── Switching on turns the badge ──────────────────────────────────────────
    // (M3E, 2026-11-09.) The roomy tile's badge is a disc while the setting is off and MORPHS into `shape` on a
    // spring that overshoots when it turns on (MorphShape, as ShapeTile does) — the change itself is what says
    // "you just turned me on", so the old pop-and-settle of a rounded square is gone.
    // Left alone, each tile gets one of these by its label, so a grid of them is not one shape repeated.
    property string shape: {
        const set = ["cookie9", "sunny", "clover", "squircle", "hexagon", "pentagon", "cookie6", "burst"]
        let h = 0
        for (let i = 0; i < root.label.length; i++) h = (h * 31 + root.label.charCodeAt(i)) % 997
        return set[h % set.length]
    }

    // ── Compact ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm
        visible: !root.roomy

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            name:  root.symbol
            fill:  root.active ? 1 : 0
            color: root.active ? root.accent : Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconMd
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text:    root.label
                variant: "caption"
                font.weight: Font.DemiBold
                color:   root.active ? root.accent : Colors.of(QsWindow.window).fg
                elide:   Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible:  root.subLabel !== ""
                text:     root.subLabel
                variant:  "caption"
                emphasis: "dim"
                elide:    Text.ElideRight
            }
        }
    }

    // ── Roomy (settings) ──────────────────────────────────────────────────────
    // The chip is the state indicator: filled and accented when on, quiet when off.
    // No switch anywhere — the tile IS the switch, which is the whole point of
    // giving a boolean this much room.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm
        visible: root.roomy

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth:  Tokens.iconXl + Tokens.spacingMd
                implicitHeight: Tokens.iconXl + Tokens.spacingMd

                MorphShape {
                    anchors.fill: parent
                    shape: root.active ? root.shape : "circle"
                    fillColor: root.active ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgDim, 0.18)
                    Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name:  root.symbol
                    fill:  root.active ? 1 : 0
                    color: root.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgDim
                    font.pixelSize: Tokens.iconMd
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text:    root.label
                variant: "body"
                font.weight: Font.DemiBold
                color:   root.active ? root.accent : Colors.of(QsWindow.window).fg
                elide:   Text.ElideRight
                Behavior on color { ColorAnimation { duration: Motion.emphasized } }
            }
            // There is more to read: only while the pointer rests on a tile with help.
            MaterialIcon {
                visible: root.help !== ""
                name: "info"
                color: Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconSm
                opacity: tileTip.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
            Item { Layout.fillWidth: true }

            // The state in a word, where a switch would have been. It reads at a
            // glance across a grid of tiles, which a switch position does not.
            StyledText {
                text:    root.active ? "On" : "Off"
                variant: "caption"
                font.weight: Font.DemiBold
                color:   root.active ? root.accent : Colors.of(QsWindow.window).fgDim
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.fillHeight: true
            visible:  root.subLabel !== ""
            text:     root.subLabel
            variant:  "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
            elide:    Text.ElideRight
        }
    }

    // Last, so it sits on top for hit-testing — the icon/text above have no
    // input handlers of their own, so nothing here steals a click from them.
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.actionable
        cursorShape: Qt.PointingHandCursor

        onClicked:  root.toggled()
        onPressed:  function(m) { ripple.press(m.x, m.y) }
        onReleased: ripple.release()
        onCanceled: ripple.release()
    }
}
