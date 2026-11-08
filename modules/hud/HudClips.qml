import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/clips.js" as ClipsJs

// ── HudClips ──────────────────────────────────────────────────────────────────
// Over a game: is the replay buffer rolling (a dot and its length), save it, record. Pin it
// with click-through off to use it; the overview's clips card is the full director. A
// missing recorder disables the buttons and says why, like every optional tool here.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root
    spacing: Tokens.spacingSm

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property string blocked: Clips.blocker()

    // Rolling, recording, or neither — a dot says which before any word does.
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Tokens.spacingMd
        implicitHeight: implicitWidth
        radius: width / 2
        color: Clips.mode === "record" ? root.pal.danger
             : Clips.buffering ? root.pal.focus
             : root.pal.alpha(root.pal.fg, 0.25)
        SequentialAnimation on opacity {
            running: Clips.mode === "record" && !Clips.paused && Config.motionEnabled
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.35; duration: Motion.pulse }
            NumberAnimation { to: 1;    duration: Motion.pulse }
        }
    }
    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: root.blocked !== "" ? root.blocked
            : Clips.mode === "record" ? Translation.tr("Recording")
            : Clips.buffering ? Translation.tr("Replay %1").arg(ClipsJs.span(Clips.bufferSeconds))
            : Translation.tr("Buffer off")
        variant: "label"
        font.weight: Font.Medium
    }
    ChipButton {
        symbol: "save"
        label: Translation.tr("Save")
        solid: true
        tint: root.pal.focus
        enabled: root.blocked === "" && Clips.buffering
        onActivated: Clips.saveClip(0)
    }
    ChipButton {
        symbol: Clips.mode === "record" ? "stop" : "fiber_manual_record"
        on: Clips.mode === "record"
        tint: root.pal.danger
        enabled: root.blocked === ""
        onActivated: Clips.toggleRecord()
    }
}
