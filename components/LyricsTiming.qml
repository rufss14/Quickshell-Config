import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"

// ── LyricsTiming ──────────────────────────────────────────────────────────────
// The one control for a lyrics card's timing, drawn as the page switch is (SegmentSwitch): a full pill on the container
// fill. The lyrics' source is the filled accent indicator inside it; the timing is 0.1 s earlier or later (tap the
// readout to put it back at 0); Resync appears only when the card has been scrolled off the sung line.
//
//   shown        on screen (a hover, or always)
//   canResync    there is a scroll to undo
//   provenance   the lyrics' source ("" = none)
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool shown: true
    property bool canResync: false
    property string provenance: ""
    property color accent: Colors.of(QsWindow.window).primary
    property color ink: Colors.of(QsWindow.window).fg
    signal resync()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property real pillH: Tokens.iconXl + Tokens.spacingMd

    implicitWidth: row.implicitWidth + Tokens.spacingXs * 2
    implicitHeight: root.pillH
    height: root.pillH
    radius: height / 2
    color: root.palette.plateLow
    border.width: Tokens.borderWidth
    border.color: root.palette.alpha(root.palette.fg, 0.06)
    opacity: root.shown && Lyrics.hasSynced ? 1 : 0
    visible: opacity > 0.005
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    // A small icon that lights under the pointer, the way the page's own tools do.
    component Tool: Item {
        id: tool
        property string symbol: ""
        property string label: ""
        signal activated()
        implicitWidth: Tokens.iconXl
        implicitHeight: Tokens.iconXl
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.palette.alpha(root.accent, 0.16)
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: tool.symbol
            font.pixelSize: Tokens.iconMd
            color: hover.hovered ? root.accent : root.ink
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tool.activated() }
        HoverTip { text: tool.label }
        Accessible.role: Accessible.Button
        Accessible.name: tool.label
        Accessible.onPressAction: tool.activated()
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingXs

        // The source, as the indicator: a filled accent capsule with its name on it.
        Rectangle {
            visible: root.provenance !== ""
            // A fixed cap, not a share of the pill: a share of a width that depends on this child cropped it.
            readonly property real cap: Tokens.spacingXxl * 3
            implicitHeight: root.pillH - Tokens.spacingXs * 2
            implicitWidth: Math.min(srcName.implicitWidth, cap) + Tokens.spacingLg * 2
            radius: height / 2
            color: root.accent
            StyledText {
                id: srcName
                anchors.centerIn: parent
                width: parent.cap
                horizontalAlignment: Text.AlignHCenter
                text: root.provenance
                variant: "micro"
                font.weight: Font.DemiBold
                color: root.palette.fgOnPrimary
                elide: Text.ElideRight
            }
        }

        Tool {
            visible: root.canResync
            symbol: "my_location"
            label: Translation.tr("Resync")
            onActivated: root.resync()
        }
        Tool {
            symbol: "remove"
            label: Translation.tr("Earlier by 0.1 s")
            onActivated: Lyrics.nudge(-0.1)
        }

        // The timing. Zero is quiet; a correction takes the accent. A tap puts it back at zero.
        Item {
            implicitWidth: Tokens.spacingXxl * 2
            implicitHeight: Tokens.iconXl
            StyledText {
                anchors.centerIn: parent
                text: (Lyrics.offset > 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s"
                variant: "label"
                font.family: Tokens.fontMono
                font.weight: Lyrics.offset === 0 ? Font.Normal : Font.DemiBold
                color: Lyrics.offset === 0 ? root.palette.fgMuted : root.accent
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Lyrics.resetOffset()
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Timing back to zero")
                Accessible.onPressAction: Lyrics.resetOffset()
            }
        }

        Tool {
            symbol: "add"
            label: Translation.tr("Later by 0.1 s")
            onActivated: Lyrics.nudge(0.1)
        }
    }
}
