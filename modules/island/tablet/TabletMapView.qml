pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../"

// ── TabletMapView ─────────────────────────────────────────────────────────────
// The Tablet page's map controls: which screen the pen lands on, how much of the tablet it uses, and which
// way up the tablet is. What changes shows at once in the card beside it (TabletMap), so each control is the
// smallest thing that says what it does.
//
//   Screen       a card for the whole desktop and one for each monitor; the chosen one goes round and blooms.
//   Area         the size in millimetres as the page's numeral, and three tools: fill the screen, the whole
//                tablet, and whether the area keeps the screen's shape while it is resized.
//   Orientation  the four quarter-turns, as arrows (which way the top of the tablet points), and absolute or
//                relative input.
//
// The values live in the profile (services/Tablet.qml); this shows and sets.
// ─────────────────────────────────────────────────────────────────────────────
Flickable {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var prof: Tablet.profile

    contentWidth: width
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function _mm(n) { return String(Math.round(n * 10) / 10) }

    ColumnLayout {
        id: col
        width: root.width
        spacing: Tokens.spacingMd

        // ══ Screen ════════════════════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: screenCol.implicitHeight + Tokens.spacingLg * 2
            order: 1

            ColumnLayout {
                id: screenCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                TabletPlateTitle {
                    symbol: "monitor"
                    shape: "cookie9"
                    title: Translation.tr("Screen")
                    note: root.prof && root.prof.output !== "" ? root.prof.output : Translation.tr("The whole desktop")
                }

                Flow {
                    id: screens
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm
                    readonly property real cardW: Math.floor((width - spacing) / 2)

                    OptionCard {
                        width: screens.cardW
                        symbol: "monitor"
                        label: Translation.tr("All screens")
                        detail: Translation.tr("The whole desktop")
                        shape: "cookie9"
                        on: root.prof !== null && root.prof.output === ""
                        enabled: Tablet.ready
                        onActivated: Tablet.setOutput("")
                    }
                    Repeater {
                        model: Quickshell.screens
                        delegate: OptionCard {
                            id: card
                            required property var modelData
                            required property int index
                            width: screens.cardW
                            symbol: "monitor"
                            label: card.modelData.name
                            detail: card.modelData.width + " × " + card.modelData.height
                            shape: ["clover", "sunny", "squircle", "pentagon"][card.index % 4]
                            on: root.prof !== null && root.prof.output === card.modelData.name
                            enabled: Tablet.ready
                            onActivated: Tablet.setOutput(card.modelData.name)
                        }
                    }
                }
            }
        }

        // ══ Area ══════════════════════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: areaCol.implicitHeight + Tokens.spacingLg * 2
            order: 2

            ColumnLayout {
                id: areaCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                TabletPlateTitle {
                    symbol: "crop"
                    shape: "clover"
                    title: Translation.tr("Area")
                    note: Tablet.profile && Tablet.targetSize.w > 0
                        ? Translation.tr("Maps to %1 × %2 pixels").arg(Tablet.targetSize.w).arg(Tablet.targetSize.h)
                        : Translation.tr("Drag the block on the tablet to move it")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingLg

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.prof ? root._mm(root.prof.area.w) + " × " + root._mm(root.prof.area.h) : "–"
                            font.pixelSize: Tokens.fontDisplay * 1.5
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            fontSizeMode: Text.HorizontalFit
                            color: root.palette.fg
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.prof
                                ? Translation.tr("mm · from %1, %2").arg(root._mm(root.prof.area.x)).arg(root._mm(root.prof.area.y))
                                : ""
                            variant: "caption"
                            color: root.palette.fgMuted
                            elide: Text.ElideRight
                        }
                    }

                    Flow {
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.round(areaCol.width * 0.55)
                        spacing: Tokens.spacingSm

                        ChipButton {
                            tonal: true
                            symbol: "fullscreen"
                            label: Translation.tr("Fill screen")
                            enabled: Tablet.ready && Tablet.targetSize.w > 0
                            onActivated: Tablet.fitToScreen()
                            HoverTip { text: Translation.tr("The biggest area with the screen's shape") }
                        }
                        ChipButton {
                            tonal: true
                            symbol: "crop_free"
                            label: Translation.tr("Whole tablet")
                            enabled: Tablet.ready
                            onActivated: Tablet.fullArea()
                            HoverTip { text: Translation.tr("Use the entire surface, whatever its shape") }
                        }
                        ChipButton {
                            tonal: true
                            on: root.prof !== null && root.prof.lockRatio
                            symbol: root.prof && root.prof.lockRatio ? "lock" : "lock_open"
                            label: Translation.tr("Screen shape")
                            enabled: Tablet.ready
                            onActivated: Tablet.setLockRatio(!(root.prof && root.prof.lockRatio))
                            HoverTip { text: Translation.tr("Keep the area the same shape as the screen while you resize it, so circles stay round") }
                        }
                    }
                }
            }
        }

        // ══ Orientation and mode ══════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: turnCol.implicitHeight + Tokens.spacingLg * 2
            order: 3

            ColumnLayout {
                id: turnCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                TabletPlateTitle {
                    symbol: "arrow_upward"
                    shape: "sunny"
                    title: Translation.tr("Orientation")
                    note: root.prof && root.prof.relative
                        ? Translation.tr("Relative: the pen moves the pointer like a mouse")
                        : Translation.tr("Absolute: a spot on the tablet is a spot on the screen")
                }

                SegmentSwitch {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    current: root.prof ? root.prof.rotation : 0
                    model: [
                        { value: 0,   label: "0°",   icon: "arrow_upward" },
                        { value: 90,  label: "90°",  icon: "arrow_right" },
                        { value: 180, label: "180°", icon: "arrow_downward" },
                        { value: 270, label: "270°", icon: "arrow_left" }
                    ]
                    onPicked: v => Tablet.setRotation(v)
                }
                SegmentSwitch {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    current: root.prof && root.prof.relative ? "relative" : "absolute"
                    model: [
                        { value: "absolute", label: Translation.tr("Absolute"), icon: "ads_click" },
                        { value: "relative", label: Translation.tr("Relative"), icon: "mouse" }
                    ]
                    onPicked: v => Tablet.setRelative(v === "relative")
                }
            }
        }
    }
}
