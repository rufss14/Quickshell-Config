import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickClips ────────────────────────────────────────────────────────────────
// The clips pill's card: record on or off, save the replay buffer, and the buffer's own switch. Same
// calls as the Clips panel (`clipIt` honours "keep recording a few seconds more"). `Clips.blocker()`
// (no gpu-screen-recorder) disables the controls with its reason.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property string blocked: Clips.blocker()

    symbol: "videocam"
    shape: "cookie6"
    title: Translation.tr("Clips")
    value: ModuleGlance.value("clips")

    trailing: ChipButton {
        symbol: "fiber_manual_record"
        tint: root.palette.primary
        solid: true
        on: Clips.mode === "record"
        enabled: root.blocked === ""
        onActivated: Clips.toggleRecord()
    }

    StyledText {
        visible: root.blocked !== ""
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: root.blocked
    }

    OptionCard {
        width: parent.width
        symbol: "history"
        label: Translation.tr("Save the replay")
        detail: Clips.buffering ? Translation.tr("Last %1 s").arg(Clips.bufferSeconds) : Translation.tr("Buffer is off")
        shape: "cookie6"
        enabled: root.blocked === "" && Clips.buffering
        onActivated: Clips.clipIt(Config.clipsSaveSeconds)
    }

    OptionCard {
        width: parent.width
        symbol: "videocam"
        label: Translation.tr("Replay buffer")
        shape: "cookie9"
        on: Config.clipsBuffer
        enabled: root.blocked === ""
        onActivated: Clips.toggleClipping()
    }
}
