import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── HudStats ──────────────────────────────────────────────────────────────────
// CPU, GPU (when there is one) and memory as a ratio bar and a number each — the same
// readouts as the sidebar's stats (SysStats.readout), so the two can't disagree. It holds
// SysInfo sampling while it exists, and it only exists while shown (HudWidget's Loader).
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root
    spacing: Tokens.spacingSm

    Component.onCompleted: SysInfo.acquire()
    Component.onDestruction: SysInfo.release()

    readonly property var keys: SysInfo.hasGpu ? ["cpu", "gpu", "ram"] : ["cpu", "ram"]

    Repeater {
        model: root.keys

        RowLayout {
            id: line
            required property string modelData
            readonly property var r: SysStats.readout(line.modelData)
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            MaterialIcon {
                glyph: line.r.glyph
                font.pixelSize: Tokens.iconSm
                color: Colors.of(QsWindow.window).fgMuted
            }
            StyledText {
                Layout.preferredWidth: Tokens.sideCardUnit
                text: line.r.label
                variant: "caption"
                emphasis: "muted"
            }
            Meter {
                Layout.preferredWidth: Tokens.sideCardUnit * 2
                value: line.r.ratio
                fillDuration: Motion.track
            }
            StyledText {
                Layout.preferredWidth: Tokens.sideCardUnit
                horizontalAlignment: Text.AlignRight
                text: line.r.short + "%"
                font.family: Tokens.fontMono
            }
        }
    }
}
