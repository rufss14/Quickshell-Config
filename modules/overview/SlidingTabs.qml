import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── SlidingTabs ───────────────────────────────────────────────────────────────
// A tray of stops (icon, and the name on the one you're on) with a lit pill that slides between
// them. `position` is a REAL, so a caller mid-swipe (OverviewFeed's rail, `at`) has the pill — and
// the name's reveal — follow the pointer between two stops; a caller with a plain index gets the
// slide from `Behavior` here (`animate`). Used by the left face's rail and the News topics.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    // Each: { symbol, label, badge (optional: a dot — something new there) }.
    property var model: []
    property real position: 0
    property color accent: Colors.of(QsWindow.window).primary
    // Glide `position` changes here (a caller that sets an index); off for one that animates its own.
    property bool animate: false
    signal picked(int index)

    // A caller with a plain index gets the slide on an M3E spring; one that animates its own (a swipe) is followed as is.
    SpringValue { id: posSpring; target: root.position; spec: Motion.springSpatial; epsilon: 0.002 }
    readonly property real _pos: root.animate ? posSpring.value : root.position

    // The lit pill is the tonal container; the palette's own accent gets Material's pair, another accent a mix.
    readonly property bool _paletteAccent: Qt.colorEqual(root.accent, Colors.of(QsWindow.window).primary)
    readonly property color _container: root._paletteAccent
        ? Colors.of(QsWindow.window).primaryContainer
        : Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.26)
    readonly property color _ink: root._paletteAccent ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.accent

    readonly property int pad: Tokens.spacingXs
    readonly property int count: root.model.length
    implicitWidth: stops.width + root.pad * 2
    implicitHeight: Tokens.iconXl + root.pad * 2
    radius: height / 2
    color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, 0.9)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

    Rectangle {
        id: lit
        readonly property real at: Math.max(0, Math.min(root.count - 1, root._pos))
        readonly property int i0: Math.floor(lit.at)
        readonly property int i1: Math.min(root.count - 1, lit.i0 + 1)
        readonly property real f: lit.at - lit.i0
        readonly property Item a: stopsRep.count > lit.i0 ? stopsRep.itemAt(lit.i0) : null
        readonly property Item b: stopsRep.count > lit.i1 ? stopsRep.itemAt(lit.i1) : null
        visible: root.count > 0
        x: root.pad + (lit.a && lit.b ? lit.a.x + (lit.b.x - lit.a.x) * lit.f : 0)
        y: root.pad
        width: lit.a && lit.b ? lit.a.width + (lit.b.width - lit.a.width) * lit.f : 0
        height: Tokens.iconXl
        radius: height / 2
        color: root._container
    }

    Row {
        id: stops
        x: root.pad
        y: root.pad
        spacing: Tokens.spacingXs

        Repeater {
            id: stopsRep
            model: root.model
            delegate: Item {
                id: stop
                required property var modelData
                required property int index
                // How near the position is to this stop (1 = on it).
                readonly property real near: Math.max(0, 1 - Math.abs(root._pos - stop.index))
                width: Tokens.iconXl + stop.near * (stopLabel.implicitWidth + Tokens.spacingSm)
                height: Tokens.iconXl
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, stopHover.hovered && stop.near < 0.5 ? 0.06 : 0)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                Item {
                    anchors.fill: parent
                    clip: true
                    MaterialIcon {
                        x: (Tokens.iconXl - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        name: stop.modelData.symbol
                        fill: stop.near > 0.5 ? 1 : 0
                        color: stop.near > 0.5 ? root._ink : stopHover.hovered ? root.accent : Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconSm
                        SpringValue { id: stopLean; target: stopTap.pressed ? 0.85 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                        scale: stopLean.value
                    }
                    StyledText {
                        id: stopLabel
                        x: Tokens.iconXl - Tokens.spacingXs
                        anchors.verticalCenter: parent.verticalCenter
                        text: stop.modelData.label
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: root._ink
                        opacity: stop.near
                    }
                }
                // Something new there: a dot on the icon's shoulder.
                Rectangle {
                    visible: !!stop.modelData.badge
                    x: Tokens.iconXl / 2 + Tokens.spacingXs
                    y: Tokens.spacingXs
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.accent
                    border.width: 1
                    border.color: root.color
                }
                HoverHandler { id: stopHover; cursorShape: Qt.PointingHandCursor }
                // An icon-only stop says its name (the current one already wears it).
                HoverTip { text: stop.modelData.tip ?? stop.modelData.label }
                TapHandler { id: stopTap; onTapped: root.picked(stop.index) }
            }
        }
    }
}
