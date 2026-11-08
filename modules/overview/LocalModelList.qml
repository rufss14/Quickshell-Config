import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── LocalModelList ────────────────────────────────────────────────────────────
// The local AI's models (services/LocalAi): the catalogue, then anything else already pulled. A row
// is a model's name, size and what it's good at, with one button — Get (then a progress bar while it
// downloads, Stop to cancel), Use, or In use. Used by the setup card's third step (LocalAiSetup) and
// by the Ask page's provider picker once the local AI is running.
// ─────────────────────────────────────────────────────────────────────────────
Column {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    spacing: Tokens.spacingXs

    function _gb(bytes) { return bytes > 0 ? (bytes / 1e9).toFixed(1) + " GB" : "" }
    readonly property var rows: {
        const cat = LocalAi.catalog
        const known = n => cat.some(c => n === c.name || n === c.name + ":latest")
        return cat.concat(LocalAi.models.filter(m => !known(m.name))
                          .map(m => ({ name: m.name, label: m.name, size: root._gb(m.size), note: Translation.tr("Already on this computer") })))
    }

    Repeater {
        model: root.rows
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool here: LocalAi.has(row.modelData.name)
            readonly property bool inUse: row.here && (LocalAi.model === row.modelData.name || LocalAi.model === row.modelData.name + ":latest")
            readonly property bool fetching: LocalAi.pulling === row.modelData.name
            width: root.width
            height: rowCol.implicitHeight + Tokens.spacingSm * 2
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).fade(row.inUse
                       ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.16)
                       : rowHover.hovered ? Colors.of(QsWindow.window).surfaceHigh : Colors.of(QsWindow.window).surfaceContainer, 0.9)
            border.width: row.inUse ? Tokens.borderWidth : 0
            border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.5)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            HoverHandler { id: rowHover }

            Column {
                id: rowCol
                x: Tokens.spacingMd
                y: Tokens.spacingSm
                width: row.width - Tokens.spacingMd * 2
                spacing: Tokens.spacingXs

                Item {
                    width: rowCol.width
                    height: Math.max(rowText.implicitHeight, rowButton.height)
                    Column {
                        id: rowText
                        anchors.left: parent.left
                        anchors.right: rowButton.left
                        anchors.rightMargin: Tokens.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            spacing: Tokens.spacingSm
                            StyledText {
                                text: row.modelData.label
                                variant: "caption"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: row.modelData.size
                                variant: "micro"
                                emphasis: "dim"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        StyledText {
                            width: parent.width
                            text: row.modelData.note
                            variant: "micro"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                    ChipButton {
                        id: rowButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        symbol: row.fetching ? "stop" : row.inUse ? "check" : row.here ? "" : "download"
                        label: row.fetching ? "" : row.inUse ? Translation.tr("In use") : row.here ? Translation.tr("Use") : Translation.tr("Get")
                        on: row.inUse
                        solid: !row.here && !row.fetching && row.index === 0 && LocalAi.models.length === 0
                        tint: root.accent
                        enabled: row.fetching || row.here || (LocalAi.running && LocalAi.pulling === "")
                        opacity: enabled ? 1 : 0.45
                        onActivated: row.fetching ? LocalAi.cancelPull() : row.here ? LocalAi.use(row.modelData.name) : LocalAi.pull(row.modelData.name)
                    }
                }

                // ── Downloading ───────────────────────────────────────────────────
                Column {
                    visible: row.fetching
                    width: rowCol.width
                    spacing: 2
                    Meter {
                        width: parent.width
                        value: LocalAi.pullDone
                        accent: root.accent
                    }
                    StyledText {
                        text: Math.round(LocalAi.pullDone * 100) + "%  ·  " + LocalAi.pullStatus
                        variant: "micro"
                        emphasis: "dim"
                    }
                }
            }
        }
    }
}
