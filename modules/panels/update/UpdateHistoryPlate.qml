pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── UpdateHistoryPlate ── the update page's last runs (island only; 2026-11-15). ──────────────────────────────
// pacman's own log (Updates.history, read when the plate appears): the last eight transactions as small blocky
// columns, oldest on the left, each as tall as the number of packages it touched. A full upgrade (-Syu) wears the
// accent, a one-off install or removal the quiet tone. Under them: how many packages the newest one moved, and
// how long since the last full upgrade. The columns grow in once, on the shell's spatial curve.
// (parseHistory keeps completed transactions only, so there is no failed run to mark.)
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var runs: Updates.history.slice(0, 8).reverse()
    readonly property int most: root.runs.reduce((m, t) => Math.max(m, t.count), 1)
    readonly property var newest: Updates.history.length > 0 ? Updates.history[0] : null
    property bool grown: false

    Component.onCompleted: Updates.loadHistory()
    onRunsChanged: if (root.runs.length > 0) Qt.callLater(() => root.grown = true)

    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusXl
    color: root.palette.plate

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            MaterialIcon {
                name: "history"
                fill: 1
                color: root.palette.fgDim
                font.pixelSize: Tokens.iconMd
            }
            StyledText {
                text: Translation.tr("Last runs")
                variant: "micro"
                color: root.palette.fgDim
            }
        }

        Item {
            id: chart
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Tokens.spacingXl + Tokens.spacingSm
            readonly property real gap: Tokens.spacingXs
            readonly property int slots: 8
            readonly property real colW: (chart.width - chart.gap * (chart.slots - 1)) / chart.slots

            StyledText {
                anchors.centerIn: parent
                visible: root.runs.length === 0
                text: Updates.historyLoading ? Translation.tr("Reading the log…") : Translation.tr("No runs yet")
                variant: "caption"
                color: root.palette.fgDim
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: chart.gap
                Repeater {
                    model: root.runs
                    delegate: Item {
                        id: run
                        required property var modelData
                        width: chart.colW
                        height: chart.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: root.grown
                                ? Math.max(Tokens.spacingXs * 2, run.height * run.modelData.count / root.most)
                                : Tokens.spacingXs
                            radius: Math.max(1, Math.round(Math.min(width, height) * 0.3))
                            color: run.modelData.full ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.28)
                            Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.newest
                ? (root.newest.count === 1 ? Translation.tr("1 package last time")
                                           : Translation.tr("%1 packages last time").arg(root.newest.count))
                : " "
            variant: "caption"
            font.features: ({ tnum: 1 })
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            text: Updates.lastUpgradeText
            variant: "micro"
            color: root.palette.fgDim
            elide: Text.ElideRight
        }
    }
}
