import QtQuick
import "../theming" as T

// ── SplitPill ───────────────────────────────────────────────────────────────
// Lightweight reusable pill for split/barMode = true.
// Replaces massive duplicated animation blocks — huge perf win.
PillRect {
    id: root

    // Required from StatusBarRoot
    property bool barMode: false

    // Children (buttons, layouts, etc.) go here
    default property alias content: contentArea.children

    visible: true
    opacity: barMode ? 0.0 : 1.0

    // Simple clean fade (no more y-slide + pause + parallel + sequential per pill)
    Behavior on opacity {
        NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic }
    }

    // Keep behaviors needed for barShape changes
    Behavior on anchors.topMargin    { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on anchors.bottomMargin { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on anchors.leftMargin   { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on anchors.rightMargin  { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on radius               { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on border.color         { ColorAnimation  { duration: T.Theme.animFast } }

    Item {
        id: contentArea
        anchors.fill: parent
    }
}