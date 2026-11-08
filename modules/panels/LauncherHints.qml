import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"

// ── LauncherHints ─────────────────────────────────────────────────────────────
// The launcher's footer: the keys that do something RIGHT NOW, as keycap + verb.
// It is how the panel explains itself without a manual — what Enter will do changes
// with the mode, and a line that says so beats a help sheet you have to know to open.
//
//     hints: [["↑↓", "Select"], ["↵", "Open"], ["Esc", "Clear"]]
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property var hints: []

    spacing: Tokens.spacingLg
    implicitHeight: Tokens.iconLg

    Repeater {
        model: root.hints

        delegate: RowLayout {
            id: hint
            required property var modelData
            spacing: Tokens.spacingSm

            Surface {
                Layout.alignment: Qt.AlignVCenter
                elevation: Tokens.elevationNested
                cornerRadius: Tokens.radiusXs
                implicitWidth:  Math.max(key.implicitWidth + Tokens.spacingMd * 2,
                                         implicitHeight)
                implicitHeight: key.implicitHeight + Tokens.spacingXs * 2
                StyledText {
                    id: key
                    anchors.centerIn: parent
                    text: hint.modelData[0]
                    variant: "caption"
                    font.family: Tokens.fontMono
                    emphasis: "muted"
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: hint.modelData[1]
                variant: "caption"
                emphasis: "dim"
            }
        }
    }

    Item { Layout.fillWidth: true }
}
