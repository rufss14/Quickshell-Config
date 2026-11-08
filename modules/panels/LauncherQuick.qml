import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── LauncherQuick ─────────────────────────────────────────────────────────────
// What you can do with the app you are on, in place of the results (Tab, or right-click on
// its row): open it, its own desktop actions ("New private window"), pin it to the dock,
// forget what the launcher learned about it. The panel hands it the `items` it got from
// Launcher.quickActions and runs what is picked — this file only shows them.
//
// Same language as the result list: the selection is ONE tonal plate that glides between
// rows on a spring, and each row arrives a hair after the one above. It is a body of the
// panel, not a popup: ContextMenu is scene-anchored and would clip inside the card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // [{ id, name, symbol, fill, closes, run }]
    property var items: []
    property int currentIndex: 0
    // The app the actions are for.
    property string title: ""
    property string iconPath: ""

    signal picked(int index)

    readonly property var c: Colors.of(QsWindow.window)

    readonly property int pad:     Tokens.spacingSm
    readonly property int headH:   Tokens.iconXl + Tokens.spacingMd * 2
    readonly property int rowH:    Tokens.iconLg + Tokens.spacingMd * 2
    readonly property int gap:     Tokens.spacingXs
    implicitHeight: root.pad * 2 + root.headH + root.items.length * root.rowH
                    + Math.max(0, root.items.length - 1) * root.gap

    function step(by) {
        root.currentIndex = Math.max(0, Math.min(root.currentIndex + by, root.items.length - 1))
    }

    // ── The app ───────────────────────────────────────────────────────────────
    RowLayout {
        x: root.pad + Tokens.spacingMd
        y: root.pad
        width: root.width - (root.pad + Tokens.spacingMd) * 2
        height: root.headH
        spacing: Tokens.spacingLg

        Image {
            Layout.preferredWidth:  Tokens.iconXl
            Layout.preferredHeight: Tokens.iconXl
            Layout.alignment: Qt.AlignVCenter
            visible: root.iconPath !== ""
            source: root.iconPath
            sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
            fillMode: Image.PreserveAspectFit
            mipmap: true
            smooth: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                text: Translation.tr("Quick actions")
                variant: "caption"
                emphasis: "dim"
            }
        }
    }

    // ── The plate, behind the rows ────────────────────────────────────────────
    SpringValue {
        id: plateY
        spec: Motion.springSpatial
        target: root.pad + root.headH + root.currentIndex * (root.rowH + root.gap)
    }
    Rectangle {
        x: root.pad
        width: root.width - root.pad * 2
        y: plateY.value
        height: root.rowH
        radius: Tokens.radiusSm
        color: root.c.primaryContainer
        visible: root.items.length > 0
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: item
            required property var modelData
            required property int index
            readonly property bool current: root.currentIndex === item.index

            x: root.pad
            width: root.width - root.pad * 2
            y: root.pad + root.headH + item.index * (root.rowH + root.gap)
            height: root.rowH

            SpringValue { id: fade; spec: Motion.springEffects; epsilon: 0.002 }
            Timer {
                id: arrive
                interval: Math.min((item.index + 1) * Motion.stagger, Motion.staggerCap)
                onTriggered: fade.target = 1
            }
            Component.onCompleted: arrive.start()
            opacity: Math.max(0, Math.min(1, fade.value))

            HoverHandler {
                onHoveredChanged: if (hovered) root.currentIndex = item.index
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: { root.currentIndex = item.index; root.picked(item.index) }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingLg
                anchors.rightMargin: Tokens.spacingLg
                spacing: Tokens.spacingLg

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: item.modelData.symbol
                    fill: item.modelData.fill ?? 0
                    color: item.current ? root.c.fgOnPrimaryContainer : root.c.fgMuted
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: item.modelData.name
                    variant: "body"
                    color: item.current ? root.c.fgOnPrimaryContainer : root.c.fg
                    font.weight: item.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
        }
    }
}
