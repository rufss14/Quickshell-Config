pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── SchemeProgress ────────────────────────────────────────────────────────────
// What takes the page's place while an apply goes wrong (a FAILED run always does) or while one runs with the
// apply log on (Config.colorApplyDebug): a plate with the state in a line, the steps of the run, and the two
// ways out. A quiet run shows nothing here; the Apply pill and the loud card say it.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    radius: Tokens.radiusCard
    color: root.palette.section
    visible: root.panel.showProgress

    ViewEnter { target: root; active: root.visible }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            BusyDot { running: ColorScheme.busy; tint: root.palette.primary }
            MaterialIcon {
                visible: !ColorScheme.busy
                name: "close"
                fill: 1
                color: root.palette.warning
                font.pixelSize: Tokens.iconLg
            }
            StyledText {
                Layout.fillWidth: true
                text: ColorScheme.busy
                    ? (ColorScheme.runner.label || Translation.tr("Applying")) + "…"
                    : ColorScheme.runner.failedCount > 0
                    ? Translation.tr("%1 steps failed").arg(ColorScheme.runner.failedCount)
                    : Translation.tr("The run stopped early")
                variant: "title"
                font.weight: Font.DemiBold
                color: ColorScheme.busy ? root.palette.fg : root.palette.warning
                elide: Text.ElideRight
            }
            ChipButton {
                tonal: true
                symbol: root.panel.showDetails ? "keyboard_arrow_up" : "keyboard_arrow_down"
                label: Translation.tr("Steps")
                tint: root.panel.accent
                onActivated: root.panel.showDetails = !root.panel.showDetails
            }
            ChipButton {
                visible: !ColorScheme.busy
                tonal: true
                symbol: "close"
                label: Translation.tr("Dismiss")
                tint: root.panel.accent
                onActivated: ColorScheme.runner.clearResult()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

        Flickable {
            id: steps
            anchors.fill: parent
            contentHeight: stepCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: stepCol
                width: steps.width
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.panel.showDetails ? ColorScheme.runner.steps : []
                    delegate: RowLayout {
                        id: stepRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd

                        MaterialIcon {
                            name: stepRow.modelData.status === "ok"   ? "check"
                                : stepRow.modelData.status === "fail" ? "close"
                                : stepRow.modelData.status === "skip" ? "sleep"
                                : "hourglass_empty"
                            color: stepRow.modelData.status === "ok"   ? root.palette.success
                                 : stepRow.modelData.status === "fail" ? root.palette.danger
                                 : root.palette.fgDim
                            variant: "caption"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: stepRow.modelData.text
                            variant: "caption"
                            emphasis: stepRow.modelData.status === "skip" ? "dim" : "normal"
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
        Scrollbar { flickable: steps }
        }
    }
}
