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

// ── WidgetsCatalogueSection ── part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to. ──
Section {
    id: widgetsCatalogueSection
    required property var page
    property alias galPager: galPager
    span:    3
    visible: page.adding
    symbol:  "widgets"
    title:   Translation.tr("Add a widget")
    subtitle: Translation.tr("Click one to place it")
    accent:  Colors.of(QsWindow.window).primary

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            ChipRow {
                Layout.fillHeight: false
                visible: Quickshell.screens.length > 1
                accent: Colors.of(QsWindow.window).primary
                model: Quickshell.screens.map(s => ({ value: s.name, label: s.name }))
                current: page.targetScreen
                onPicked: function (v) { page.targetScreen = v }
            }

            Item { Layout.fillWidth: true }

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.preferredWidth: 220
                placeholder: Translation.tr("Search widgets…")
                onEdited: function (t) { page.gallerySearch = t }
            }
        }

        // ── The sliding gallery ────────────────────────────────────────
        Item {
            id: galHost
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 330

            readonly property int cols: 3
            readonly property int rows: 2
            readonly property real cellW:
                Math.floor((galHost.width - Tokens.spacingMd * (galHost.cols - 1)) / galHost.cols)
            readonly property real cellH:
                Math.floor((galHost.height - Tokens.spacingMd * (galHost.rows - 1)) / galHost.rows)

            ListView {
                id: galPager
                anchors.fill: parent
                orientation: ListView.Horizontal
                clip: true
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: Motion.standard * 2
                highlightMoveVelocity: -1
                boundsBehavior: Flickable.StopAtBounds
                model: page.galPageCount

                delegate: Item {
                    id: galPage
                    required property int index
                    width: galPager.width
                    height: galPager.height

                    Grid {
                        anchors.fill: parent
                        columns: galHost.cols
                        columnSpacing: Tokens.spacingMd
                        rowSpacing: Tokens.spacingMd

                        Repeater {
                            model: page.filteredCatalogue.slice(
                                galPage.index * page.galPageSize,
                                (galPage.index + 1) * page.galPageSize)
                            delegate: WidgetsGalleryCard {
                                host: page
                                required property var modelData
                                entry: modelData
                                width:  galHost.cellW
                                height: galHost.cellH
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: page.filteredCatalogue.length === 0
                text: "Nothing matches “" + page.gallerySearch + "”."
                variant: "body"
                emphasis: "dim"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            visible: page.galPageCount > 1

            StyledText {
                text: (galPager.currentIndex + 1) + " / " + page.galPageCount
                variant: "caption"
                emphasis: "dim"
            }
            ValueSlider {
                Layout.fillWidth: true
                maximum: 1.0
                value: galPager.width > 0 && page.galPageCount > 1
                    ? galPager.contentX / (galPager.width * (page.galPageCount - 1))
                    : 0
                onMoved: function (v) {
                    galPager.currentIndex = Math.round(v * (page.galPageCount - 1))
                }
            }
        }
}
