pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../.."

// ── WidgetsDesktopSection ── the page's hero: the screen, small, with every widget where it really is.
// The map is the live subject (DesktopMap draws the real widgets, inert; drag one to move it, click to
// pick it), so it is the loud card. What the picked widget offers is in the groups under it
// (WidgetsPickedSection, WidgetsOptionsSection, WidgetsPhoto*Section). Part of WidgetsPage.qml;
// `page` is the WidgetsPage it belongs to.
Section {
    id: desk
    required property var page

    hero:    true
    visible: DesktopWidgets.shown.length > 0

    // The screen on the left, what it holds and the master switch on the right; a narrow card stacks them.
    // The map is capped so it stays shorter than the groups that act on it.
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        columns: width >= 600 ? 2 : 1
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingMd

        DesktopMap {
            id: map
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.preferredHeight: width * map.sh / map.sw
            Layout.alignment: Qt.AlignTop
            screenName: desk.page.mapScreen
            selectedId: desk.page.selectedId
            onPicked: function (id) { desk.page.selectedId = id }

            // Nothing placed on this screen yet.
            StyledText {
                anchors.centerIn: parent
                visible: DesktopWidgets.forScreen(desk.page.mapScreen).length === 0
                text: Translation.tr("Nothing on %1 yet").arg(desk.page.mapScreen)
                variant: "caption"
                color: Colors.of(QsWindow.window).fg
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 200
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingMd

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: desk.page.selected
                          ? (DesktopWidgets.info(desk.page.selected.type)?.label ?? Translation.tr("Widget"))
                          : Translation.tr("%1 on %2").arg(DesktopWidgets.forScreen(desk.page.mapScreen).length).arg(desk.page.mapScreen)
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: desk.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: desk.page.selected
                          ? Translation.tr("%1 · %2 · drag it on the map to move it").arg(desk.page.selected.screen).arg(desk.page.selected.size)
                          : Translation.tr("Click a widget to change it, drag it to move it")
                    variant: "caption"
                    color: desk.inkDim
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            // The page's one master switch, with its own label and what it does.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Show on desktop")
                        variant: "label"
                        color: desk.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Config.widgetsEnabled ? Translation.tr("Drawn above the wallpaper")
                                                    : Translation.tr("Hidden, your layout is kept")
                        variant: "caption"
                        color: desk.inkDim
                        elide: Text.ElideRight
                    }
                }
                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    accent: Colors.of(QsWindow.window).primary
                    accessibleName: Translation.tr("Desktop widgets")
                    checked: Config.widgetsEnabled
                    onToggled: Config.widgetsEnabled = !Config.widgetsEnabled
                }
            }
        }
    }
}
