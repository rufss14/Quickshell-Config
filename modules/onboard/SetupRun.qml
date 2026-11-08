import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/setupplan.js" as Plan
import "../../state"

// ── SetupRun ──────────────────────────────────────────────────────────────────
// A plan being carried out, and what came of it: the timeline while it runs (one step live with its output,
// the rest queued) and the recap after (what worked, what didn't and what that means, what needs a restart).
// Shown by SetupFlow and by the wizard's last page; it reads Setup.run and holds no state of its own.
//
//   closeRequested   the recap's Done — the host decides what closing means
//   reviewRequested  "Back to the list" / "Review" — the host goes back to choosing
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property bool embedded: false
    property real listMax: 330
    // Called with the password that was used; the host keeps it (the field it typed it in lives there).
    property string password: ""
    signal closeRequested()
    signal reviewRequested()

    spacing: Tokens.spacingMd

    property bool copied: false
    Timer { id: copiedTimer; interval: 2200; onTriggered: root.copied = false }

    readonly property var items: Setup.run.items
    readonly property bool running: Setup.run.active
    readonly property int total: root.items.length
    readonly property int over: root.items.filter(i => i.state === "ok" || i.state === "failed" || i.state === "skipped").length
    readonly property real remaining: root.items.filter(i => i.state === "queued" || i.state === "running").reduce((n, i) => n + i.eta, 0)
    readonly property int okCount: root.items.filter(i => i.state === "ok").length
    readonly property int badCount: root.items.filter(i => i.state === "failed").length
    readonly property int skipCount: root.items.filter(i => i.state === "skipped").length

    function retryFailed() {
        const ids = Setup.run.items.filter(i => i.state === "failed" || i.state === "skipped").map(i => i.id)
        Setup.clearRun()
        Setup.selectOnly(ids)
        if (Setup.plan.root && root.password.length === 0 && !Setup.polkitReady) { root.reviewRequested(); return }
        Setup.startPlan(root.password)
    }

    // ── While it runs ────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.running
        spacing: Tokens.spacingMd
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: Translation.tr("Setting up…")
            variant: "title"; font.weight: Font.DemiBold
        }
        StyledText {
            text: root.over + " of " + root.total + "  ·  " + Plan.etaText(root.remaining) + " left"
            variant: "caption"; emphasis: "dim"
        }
    }
    Meter {
        Layout.fillWidth: true
        visible: root.running
        value: root.total === 0 ? 0 : (root.over + (Setup.busy ? 0.4 : 0)) / root.total
        accent: Colors.of(QsWindow.window).primary
    }

    // ── After it ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !root.running
        spacing: Tokens.spacingMd
        // A turning cookie in the verdict's colour (outlined: a filled one would put the palette's
        // glyph colour on a fixed green or red).
        SetupCookie {
            Layout.alignment: Qt.AlignVCenter
            size: 46
            name: root.badCount === 0 ? "check" : "error"
            turning: true
            tint: Verdict.tint(root.badCount === 0)
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: root.badCount === 0 && root.skipCount === 0 ? "All set"
                    : root.okCount === 0 ? "Nothing could be set up"
                    : "Mostly set up"
                variant: "title"; font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: root.okCount + " done"
                    + (root.badCount > 0 ? "  ·  " + root.badCount + " failed" : "")
                    + (root.skipCount > 0 ? "  ·  " + root.skipCount + " skipped" : "")
                    + "  ·  took " + Plan.etaText(Math.max(1, (Setup.run.ended - Setup.run.started) / 1000)).replace("about ", "")
                variant: "caption"; emphasis: "dim"
            }
        }
    }

    // ── The timeline (both) ──────────────────────────────────────────────────
    // The scrollbar is a SIBLING of the Flickable: it anchors to it, and as a child it would anchor to a non-sibling.
    Item {
        id: flickBox
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: Math.min(root.listMax, runCol.implicitHeight)

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: runCol.implicitHeight
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: runCol
            width: flick.width
            spacing: Tokens.spacingXs
            Repeater {
                model: ScriptModel { values: root.items; objectProp: "id" }
                delegate: SetupRunRow { required property var modelData; item: modelData; width: runCol.width }
            }
        }
        // Follow the step that is running.
        Connections {
            target: Setup
            function onRunChanged() {
                if (Setup.run.current < 0) return
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height,
                                                      Setup.run.current * 40 - flick.height / 3))
            }
        }
    }
    Scrollbar { flickable: flick }
    }

    // The blob plugin and the base packages only take effect in a fresh shell.
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Setup.reloadNeeded
        implicitHeight: rl.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.28)
        RowLayout {
            id: rl
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd
            MaterialIcon { name: "restart_alt"; color: Colors.of(QsWindow.window).primary; font.pixelSize: Tokens.iconSm }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Translation.tr("Restart the shell (ALT+Q) so it picks up what was installed — the morphing plugin is only loaded at start.")
                variant: "caption"; wrapMode: Text.WordWrap
            }
        }
    }

    // The Hyprland step replaced a config: the way back, right where the news is.
    SetupRestore {
        condition: !root.running && root.items.some(i => i.id === "hypr" && i.state === "ok")
    }

    // ── Buttons ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.running
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: Setup._stopAfter ? "Stopping after this step…"
                : Setup.run.polkit ? "Approve the system dialog when it appears." : ""
            variant: "caption"; emphasis: "dim"
        }
        PanelButton {
            variant: "ghost"
            accent: Colors.of(QsWindow.window).primary
            symbol: "stop"; label: "Stop after this step"
            enabled: !Setup._stopAfter
            onActivated: Setup.stopAfterCurrent()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !root.running
        spacing: Tokens.spacingSm
        // For a bug report: the machine, how each step ended, a failure's last lines. Home shown as "~".
        PanelButton {
            variant: "ghost"
            accent: Colors.of(QsWindow.window).primary
            symbol: root.copied ? "check" : "content_copy"
            label: root.copied ? "Copied" : "Copy report"
            onActivated: { Setup.copyReport(); root.copied = true; copiedTimer.restart() }
        }
        Item { Layout.fillWidth: true }
        PanelButton {
            visible: root.badCount + root.skipCount > 0
            variant: root.okCount === 0 ? "primary" : "normal"
            accent: Colors.of(QsWindow.window).primary
            symbol: "refresh"; label: "Try the rest again"
            onActivated: root.retryFailed()
        }
        PanelButton {
            variant: "ghost"
            accent: Colors.of(QsWindow.window).primary
            label: root.embedded ? "Back to the list" : "Review"
            onActivated: { Setup.clearRun(); root.reviewRequested() }
        }
        PanelButton {
            visible: !root.embedded
            variant: root.badCount + root.skipCount > 0 ? "ghost" : "primary"
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Done")
            onActivated: root.closeRequested()
        }
    }
}
