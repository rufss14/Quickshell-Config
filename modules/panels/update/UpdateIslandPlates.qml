import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── UpdateIslandPlates ── the update page's bottom row on an island (2026-11-15). ─────────────────────────────
// The user's three picks for the room under the buttons, side by side and of one height: will it fit
// (UpdateSpacePlate), what the last runs looked like (UpdateHistoryPlate), and the newest Arch news
// (UpdateNewsCard). Under the main view and the caught-up view alike; nothing in the bar's slot, whose height
// is capped. Loaded only on an island, so the bar's copy reads no log and fetches no feed.
RowLayout {
    id: root
    required property var panel
    property bool shown: false
    property int delay: 0

    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: root.panel.island
    spacing: Tokens.spacingSm
    ViewEnter { target: root; active: root.shown && root.panel.island; delay: root.delay; rise: Tokens.spacingMd }

    Loader {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        active: root.panel.island
        sourceComponent: UpdateSpacePlate {}
    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        active: root.panel.island
        sourceComponent: UpdateHistoryPlate {}
    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        active: root.panel.island
        sourceComponent: UpdateNewsCard {}
    }
}
