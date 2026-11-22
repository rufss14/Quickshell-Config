import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickClipboard ────────────────────────────────────────────────────────────
// The clipboard pill's card: the latest copies, a press puts one back on the clipboard (`Clipboard.copy`).
// The service masks text while stream mode is on (`Clipboard.label`), so a card on a stream shows nothing private.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var latest: Clipboard.entries.slice(0, 4)

    symbol: "content_paste"
    shape: "pentagon"
    title: Translation.tr("Clipboard")
    value: Clipboard.count > 0 ? Translation.tr("%1 items").arg(Clipboard.count) : Translation.tr("Empty")

    Repeater {
        model: root.latest
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: modelData.kind === "image" ? "image" : "content_copy"
            label: Clipboard.label(modelData)
            detail: Clipboard.detail(modelData)
            shape: "pentagon"
            onActivated: Clipboard.copy(modelData)
        }
    }
    StyledText {
        visible: root.latest.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        text: Translation.tr("Nothing copied yet.")
    }
    ChipButton {
        symbol: "content_paste"
        label: Translation.tr("History")
        tint: root.palette.primary
        onActivated: root.openPanel("clipboard")
    }
}
