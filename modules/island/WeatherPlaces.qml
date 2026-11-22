import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── WeatherPlaces ─────────────────────────────────────────────────────────────
// Choosing the place, as a view over the Weather page's middle with a way back (no popup). The places you keep
// are pills (press one to go there, the cross forgets it); a search pill types into Open-Meteo's geocoder once
// you stop typing; a result is a card, and pressing one goes there and keeps it (Weather.choose). `done()`
// says it is closed.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    signal done()

    function focusSearch() { search.forceFocus() }

    // A search per pause, not per key: each one is a request.
    Timer {
        id: pause
        interval: 450
        onTriggered: Weather.search(search.text)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            IslandBadge {
                size: Tokens.iconXl + Tokens.spacingXs
                shape: "squircle"
                symbol: "location_on"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Choose a place")
                    variant: "label"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: Weather.hasLocation ? Translation.tr("Now: %1").arg(StreamMode.mask(Weather.place)) : Translation.tr("No place set yet")
                    variant: "caption"
                    emphasis: "dim"
                }
            }
            ChipButton {
                visible: Weather.hasLocation
                symbol: "close"
                label: Translation.tr("Back")
                tonal: true
                onActivated: root.done()
            }
        }

        SearchPill {
            id: search
            Layout.fillWidth: true
            lead: Translation.tr("Search a city")
            onEdited: function (value) {
                if (value.trim() === "") { pause.stop(); Weather.results = [] }
                else pause.restart()
            }
        }

        // The places you keep.
        Flow {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Weather.cities.length > 1
            spacing: Tokens.spacingSm
            Repeater {
                model: Weather.cities
                delegate: Rectangle {
                    id: keep
                    required property int index
                    required property var modelData
                    readonly property bool here: Weather.isHere(keep.modelData)
                    implicitWidth: keepRow.implicitWidth + Tokens.spacingLg * 2
                    implicitHeight: Tokens.iconXl + Tokens.spacingXs
                    radius: height / 2
                    color: keep.here ? root.palette.primaryContainer : root.palette.plate
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    PopIn { id: keepPop; active: root.visible; index: keep.index }
                    opacity: keepPop.opacity
                    scale: keepPop.scale

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (keep.here) root.done(); else Weather.choose(keep.modelData)
                    }
                    RowLayout {
                        id: keepRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: keep.here ? "check" : "location_on"
                            fill: 1
                            font.pixelSize: Tokens.iconMd
                            color: keep.here ? root.palette.fgOnPrimaryContainer : root.palette.primary
                        }
                        StyledText {
                            text: StreamMode.mask(keep.modelData.name)
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: keep.here ? root.palette.fgOnPrimaryContainer : root.palette.fg
                        }
                        // The place on show cannot be forgotten.
                        MaterialIcon {
                            visible: !keep.here
                            name: "close"
                            font.pixelSize: Tokens.iconMd
                            color: root.palette.fgMuted
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Tokens.spacingSm
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Weather.forget(keep.modelData)
                            }
                        }
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingMd
            Repeater {
                model: Weather.results.slice(0, 4)
                delegate: Rectangle {
                    id: res
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: Tokens.iconXl + Tokens.spacingXl
                    radius: Tokens.radiusSm
                    color: root.palette.plate

                    PopIn { id: pop; active: root.visible; index: res.index }
                    opacity: pop.opacity
                    scale: pop.scale

                    StateLayer {
                        anchors.fill: parent
                        radius: res.radius
                        hovered: tap.containsMouse
                        layerColor: root.ink
                        reveal: true
                        pointerX: tap.mouseX
                        pointerY: tap.mouseY
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingMd
                        MaterialIcon {
                            name: "location_on"
                            fill: 1
                            font.pixelSize: Tokens.iconLg
                            color: root.palette.primary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: res.modelData.name
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: res.modelData.detail
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Weather.choose(res.modelData)
                            search.clear()
                            root.done()
                        }
                    }
                }
            }
        }

        // Nothing to show yet: the wait, or what to do, on a cookie.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Weather.results.length === 0
            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacingMd
                IslandBadge {
                    Layout.alignment: Qt.AlignHCenter
                    size: Tokens.iconXl * 2
                    shape: "cookie9"
                    symbol: Weather.searching ? "hourglass_top" : search.text.trim() === "" ? "search" : "search_off"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Weather.searching ? Translation.tr("Looking…")
                        : search.text.trim() === "" ? Translation.tr("Type a city, then pick it")
                        : Translation.tr("No place by that name")
                    variant: "label"
                    emphasis: "dim"
                }
            }
        }
        Item { Layout.fillHeight: true; visible: Weather.results.length > 0 }
    }
}
