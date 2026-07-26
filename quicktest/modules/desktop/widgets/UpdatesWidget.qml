pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── UpdatesWidget ─────────────────────────────────────────────────────────────
// How many packages are waiting. Click to open the Updates page.
//
// It does NOT drive the check on its own cadence: the Flatpak half hits the network and
// is the slowest of the three sources, so it stays on the Updates service's own
// schedule, shared with the bar's pill. This tile reports; it does not poll.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    readonly property int total: Updates.total

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: UiState.openOverviewTo("settings")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Updates.checking ? "󰇚" : root.total === 0 ? "󰄬" : "󰚰"
            font.pixelSize: 28
            color: root.total === 0 ? Colors.success : root.accent
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacingXs
            visible: root.total > 0
            text: root.total
            font.pixelSize: 38
            font.weight: Font.Bold
            color: Colors.fg
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Updates.checking ? "Checking…"
                : Updates.hasError ? "Check failed"
                : root.total === 0  ? "Up to date"
                : root.total === 1  ? "update available"
                                    : "updates available"
            variant: "caption"
            emphasis: "muted"
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.size !== "small" && root.total > 0
            text: Updates.count + " official · " + Updates.aurCount + " AUR · "
                  + Updates.flatpakCount + " flatpak"
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }
}
