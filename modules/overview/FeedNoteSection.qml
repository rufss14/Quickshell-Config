import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── FeedNoteSection ───────────────────────────────────────────────────────────
// One part of a release's patch notes (FeedChanges): a card with the part's icon, name and count,
// its first three lines, and "+N more" that opens it to all of them — the card grows on a curve,
// the chevron turns, and the new lines rise in one after another. `flat` drops the card (inside an
// older release's own card). `lit`/`delay` are the page's cascade (ViewEnter).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    // { title, symbol, items: ["…"] }
    property var section: ({})
    property color accent: Colors.of(QsWindow.window).primary
    property bool flat: false
    property bool lit: false
    property int delay: 0
    property bool open: false

    readonly property var items: root.section.items ?? []
    readonly property int peek: 3
    readonly property bool more: root.items.length > root.peek
    readonly property int pad: root.flat ? 0 : Tokens.spacingMd

    height: col.implicitHeight + root.pad * 2
    Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    clip: true
    radius: Tokens.radiusCard - Tokens.spacingXs
    color: root.flat ? "transparent"
         : Colors.of(QsWindow.window).fade(headHover.hovered && root.more
               ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, root.accent, 0.06)
               : Colors.of(QsWindow.window).surfaceContainer, 0.88)
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    ViewEnter { target: root; active: root.lit; delay: root.delay }

    Column {
        id: col
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: Tokens.spacingSm

        // ── The part: icon, name, how many, the chevron ─────────────────────────
        Item {
            width: col.width
            height: Math.max(chip.height, title.implicitHeight)
            ScallopChip {
                id: chip
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 28
                implicitHeight: 28
                symbol: root.section.symbol ?? ""
                tint: root.accent
                hot: headHover.hovered
            }
            StyledText {
                id: title
                anchors.left: chip.right
                anchors.leftMargin: Tokens.spacingSm
                anchors.verticalCenter: parent.verticalCenter
                text: root.section.title ?? ""
                variant: "body"
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.left: title.right
                anchors.leftMargin: Tokens.spacingSm
                anchors.verticalCenter: parent.verticalCenter
                width: countText.implicitWidth + Tokens.spacingSm * 2
                height: countText.implicitHeight + 2
                radius: height / 2
                color: Colors.of(QsWindow.window).alpha(root.accent, 0.16)
                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: root.items.length
                    variant: "micro"
                    font.weight: Font.DemiBold
                    color: root.accent
                }
            }
            MaterialIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.more
                name: "expand_more"
                color: headHover.hovered ? root.accent : Colors.of(QsWindow.window).fgMuted
                font.pixelSize: Tokens.iconMd
                rotation: root.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
            }
            HoverHandler { id: headHover; cursorShape: root.more ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: root.more; onTapped: root.open = !root.open }
        }

        // ── The lines ───────────────────────────────────────────────────────────
        Repeater {
            model: root.open ? root.items : root.items.slice(0, root.peek)
            delegate: Item {
                id: line
                required property var modelData
                required property int index
                width: col.width
                height: lineText.implicitHeight
                // A line that came with opening the card rises in, after the one above it.
                readonly property bool late: line.index >= root.peek
                opacity: line.late ? 0 : 1
                transform: Translate { id: lineRise; y: line.late ? Tokens.spacingSm : 0 }
                Component.onCompleted: if (line.late) lineIn.start()
                ParallelAnimation {
                    id: lineIn
                    SequentialAnimation {
                        PauseAnimation { duration: Math.max(0, line.index - root.peek) * Motion.stagger }
                        NumberAnimation { target: line; property: "opacity"; to: 1; duration: Motion.standard }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: Math.max(0, line.index - root.peek) * Motion.stagger }
                        NumberAnimation { target: lineRise; property: "y"; to: 0; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                    }
                }

                Rectangle {
                    x: Tokens.spacingXs + 2
                    y: Math.round(lineText.font.pixelSize * 0.55)
                    width: 6
                    height: 6
                    radius: 3
                    color: Colors.of(QsWindow.window).alpha(root.accent, 0.8)
                }
                StyledText {
                    id: lineText
                    x: Tokens.spacingLg + 2
                    width: line.width - x
                    text: line.modelData
                    variant: "caption"
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── "+N more" ───────────────────────────────────────────────────────────
        StyledText {
            visible: root.more && !root.open
            x: Tokens.spacingLg + 2
            text: Translation.tr("+%1 more").arg(root.items.length - root.peek)
            variant: "caption"
            font.weight: Font.DemiBold
            color: root.accent
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.open = true }
        }
    }
}
