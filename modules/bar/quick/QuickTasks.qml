import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickTasks ────────────────────────────────────────────────────────────────
// The to-do pill's card: the first open tasks, each one press from done (`Tasks.toggle`). Adding and
// editing stay in the panel, where there is a field to type in.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var open: Tasks.items.filter(t => !t.done).slice(0, 4)

    symbol: "checklist"
    shape: "squircle"
    title: Translation.tr("To do")
    value: ModuleGlance.value("tasks")

    Repeater {
        model: root.open
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: "radio_button_unchecked"
            label: modelData.text
            shape: "cookie9"
            onActivated: Tasks.toggle(modelData.id)
        }
    }
    StyledText {
        visible: root.open.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        text: Translation.tr("Nothing to do.")
    }
    ChipButton {
        symbol: "checklist"
        label: Translation.tr("All tasks")
        tint: root.palette.primary
        onActivated: root.openPanel("tasks")
    }
}
