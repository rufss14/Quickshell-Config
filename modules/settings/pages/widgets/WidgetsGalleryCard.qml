pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../state"
import "../../../desktop/widgets"
import "../../../desktop/widgets/toggles.js" as Toggles
import "../.."

// One catalogue tile: a live preview, the name and whether it is placed. `host` is the WidgetsPage.
// A tile lifted on the gallery's plate (surfaceHigh); one that is already on the screen is the
// chosen card (primaryContainer), so the state reads without an outline.
Rectangle {
    id: card
    required property var host
    property var entry

    readonly property bool placed:
        DesktopWidgets.has(card.entry.type, host.targetScreen)
    // A type you may place more than once (the photo frame) is never "done": the card
    // counts what is there and always adds another.
    readonly property bool multi: card.entry.multiple === true
    readonly property int placedCount:
        card.multi ? DesktopWidgets.count(card.entry.type, host.targetScreen) : 0

    // Rounder under the pointer, on a spring.
    SpringValue {
        id: rounding
        target: cardMouse.containsMouse ? Tokens.radiusXl : Tokens.radiusCard
        spec: Motion.springSpatialFast
    }
    radius: rounding.value
    color: card.placed ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).surfaceHigh
    Behavior on color { ColorAnimation { duration: Motion.respond } }
    clip: true

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WidgetPreview {
                anchors.centerIn: parent
                type: card.entry.type
                opts: DesktopWidgets.sampleOpts(card.entry.type)
                boxWidth:  card.width - Tokens.spacingLg * 2
                maxHeight: parent.height - Tokens.spacingMd * 2
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: card.entry.label
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: card.placed ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fg
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.multi && card.placedCount > 0 ? card.placedCount + " here · add another"
                        : card.placed ? "On this screen" : card.entry.detail
                    variant: "caption"
                    color: card.placed ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)
                                       : Colors.of(QsWindow.window).fgDim
                    elide: Text.ElideRight
                }
            }
            MaterialIcon {
                name: card.placed && !card.multi ? "check_circle" : "add_circle"
                fill: card.placed ? 1 : 0
                variant: "body"
                color: card.placed             ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                     : cardMouse.containsMouse ? Colors.of(QsWindow.window).fg
                     :                           Colors.of(QsWindow.window).fgDim
            }
        }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const id = DesktopWidgets.add(card.entry.type, host.targetScreen)
            if (id !== -1) {
                host.selectedId = id
                host._addRequested = false
            }
        }
    }
}
