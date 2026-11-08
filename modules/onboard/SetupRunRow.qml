import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SetupRunRow ───────────────────────────────────────────────────────────────
// One step of a running (or finished) plan: its state mark, name and time; the live output while it runs;
// why it was skipped; what a failure means and the last of its output. `item` is one of Setup.run.items.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: rr

    property var item: ({})
    readonly property string st: rr.item.state
    readonly property bool failed: rr.st === "failed"

    spacing: Tokens.spacingXs

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 34
        spacing: Tokens.spacingMd

        Item {
            Layout.preferredWidth: Tokens.iconMd
            Layout.preferredHeight: Tokens.iconMd
            Layout.alignment: Qt.AlignVCenter
            BusyDot { anchors.centerIn: parent; visible: rr.st === "running"; running: rr.st === "running"; tint: Colors.of(QsWindow.window).primary }
            MaterialIcon {
                anchors.centerIn: parent
                visible: rr.st !== "running"
                name: rr.st === "ok" ? "check_circle" : rr.st === "failed" ? "cancel" : rr.st === "skipped" ? "remove" : "radio_button_unchecked"
                fill: rr.st === "ok" || rr.st === "failed" ? 1 : 0
                color: rr.st === "ok" ? Verdict.tint(true) : rr.st === "failed" ? Verdict.tint(false) : Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconMd
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: rr.item.title + (rr.item.auto ? "  (needed by another step)" : "")
            variant: "body"
            font.weight: rr.st === "running" ? Font.DemiBold : Font.Normal
            emphasis: rr.st === "queued" || rr.st === "skipped" ? "dim" : "normal"
            elide: Text.ElideRight
        }
        StyledText {
            visible: rr.st === "ok" || rr.st === "failed"
            text: Math.max(1, Math.round((rr.item.endedAt - rr.item.startedAt) / 1000)) + " s"
            variant: "caption"; emphasis: "dim"
        }
    }

    // Live output of the step that is running.
    Surface {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 96
        Layout.leftMargin: Tokens.iconMd + Tokens.spacingMd
        visible: rr.st === "running"
        elevation: Tokens.elevationNested
        clip: true
        ListView {
            id: logView
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            clip: true
            model: Setup.logLines
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            delegate: StyledText {
                required property var modelData
                width: ListView.view.width
                text: modelData.text
                variant: "caption"
                color: modelData.err ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                font.family: Tokens.fontMono
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
            onCountChanged: Qt.callLater(() => logView.positionViewAtEnd())
        }
    }

    // Why it was skipped.
    StyledText {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.leftMargin: Tokens.iconMd + Tokens.spacingMd
        visible: rr.st === "skipped" && rr.item.why !== ""
        text: rr.item.why
        variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
    }

    // What a failure means, and the last of its output.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.leftMargin: Tokens.iconMd + Tokens.spacingMd
        visible: rr.failed
        spacing: Tokens.spacingXs
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: rr.item.explain ? rr.item.explain.title : "It didn't finish"
            variant: "caption"; font.weight: Font.DemiBold; color: Colors.of(QsWindow.window).danger
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: rr.item.explain ? rr.item.explain.text : "The output below has the details."
            variant: "caption"; wrapMode: Text.WordWrap
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: rr.item.log.slice(-4).map(l => l.text).join("\n")
            variant: "caption"; emphasis: "dim"; font.family: Tokens.fontMono
            wrapMode: Text.NoWrap; elide: Text.ElideRight
        }
    }
}
