import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ScreenTimePanel ───────────────────────────────────────────────────────────
// Beside the sidebar's Screen time module (SidePanelDock): the week and today's apps
// (components/ScreenTimeView, the same view Settings › Screen time shows), or — while
// tracking is off — what it would record and a switch to start.
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout. Everything real is
// services/ScreenTime; this shows it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it).
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph: "\u{F051F}"
            title: Translation.tr("Screen")
            titleTail: "time"
            accent: Colors.of(QsWindow.window).primary
            subtitle: !Config.screenTime ? "Off — nothing is being recorded"
                : ScreenTime.away ? "Away · today " + (ScreenTime.duration(ScreenTime.todayTotal) || "nothing yet")
                : "Today · " + (ScreenTime.duration(ScreenTime.todayTotal) || "nothing yet")

            ActionGroup {
                PanelButton {
                    variant: "ghost"
                    symbol: "settings"
                    onActivated: UiState.openSettingsTo("ScreenTimePage.qml")
                }
            }
        }

        // ── Off: what it would do, and the switch ────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !Config.screenTime
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Counts how long each app has your focus, only while you're at the machine. ")
                    + "App names and minutes, kept on this computer for " + Config.screenTimeKeepDays
                    + " days — never window titles."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
            PanelButton {
                Layout.alignment: Qt.AlignLeft
                variant: "primary"
                label: Translation.tr("Start counting")
                symbol: "hourglass_top"
                onActivated: Config.screenTime = true
            }
        }

        ScreenTimeView {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Config.screenTime || Object.keys(ScreenTime.days).length > 0
            rows: 6
        }
    }
}
