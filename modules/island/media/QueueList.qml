pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/queuemodel.js" as QueueModel

// ── QueueList ─────────────────────────────────────────────────────────────────
// Spotify's queue as a list: the Jam, what plays now, then what is next. The next rows are grouped the way Spotify keeps them: added by hand, from the album or playlist, autoplay,
// each under a divider with its count. Drag a row by its grip to move it; the move is sent to Spotify and the list shows
// the order Spotify confirms. A row can be removed under the pointer.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    // The album's colour scheme, as the lyrics card takes it (Config.albumCardColors); the palette when that is off.
    readonly property color cAccent: Config.albumCardColors ? AlbumArt.accent : root.palette.primary
    readonly property color cFg:     Config.albumCardColors ? AlbumArt.fg     : root.palette.fg
    readonly property color cMuted:  Config.albumCardColors ? AlbumArt.fgMuted : root.palette.fgMuted
    readonly property color cRow:    root.palette.alpha(root.cAccent, 0.10)
    readonly property color cNow:    root.palette.alpha(root.cAccent, 0.26)
    readonly property var queue: SpotifyBridge.queue
    readonly property var rows: root.queue ? root.queue.next : []
    readonly property real rowH: Tokens.iconXl * 2 + Tokens.spacingSm
    readonly property real headH: Tokens.iconMd + Tokens.spacingMd * 2
    readonly property bool hasQueue: root.queue !== null
    readonly property var runList: QueueModel.runs(root.rows)

    // A row's own album palette (QueuePalettes), or null while it is being read: the row keeps the plain tone then.
    function paletteFor(r) { return QueuePalettes.of(r ? r.image : "") }

    // The group a row belongs to, for its divider.
    function groupName(p) {
        if (p === "queue") return Translation.tr("Added to the queue")
        if (p === "autoplay") return Translation.tr("Autoplay")
        return root.queue && root.queue.context !== "" ? Translation.tr("From %1").arg(root.queue.context) : Translation.tr("Next from the album or playlist")
    }
    // The run that starts at row i, or null when i is in the middle of one.
    function runStarting(i) {
        for (let k = 0; k < root.runList.length; k++) if (root.runList[k].from === i) return root.runList[k]
        return null
    }

    // The row being dragged: its index and its place (the drop target) while the grip is held.
    property int dragIndex: -1
    property int dropIndex: -1

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Tokens.spacingXs

            // Not connected to Spotify yet.
            StyledText {
                Layout.fillWidth: true
                visible: !root.hasQueue
                text: !SpotifyBridge.available
                    ? Translation.tr("No queue yet. It appears once Spotify is playing with the Quicktest extension loaded.")
                    : Translation.tr("Spotify is playing but has sent no queue. The Quicktest extension must be applied (spicetify apply) and Spotify restarted.")
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            // The header: the queue's count.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.hasQueue
                spacing: Tokens.spacingMd
                StyledText {
                    Layout.fillWidth: true
                    text: root.rows.length > 0 || (root.queue && root.queue.more > 0)
                        ? Translation.tr("Next up") + (root.queue && root.queue.more > 0 ? "  ·  " + Translation.tr("%1 more").arg(root.queue.more) : "")
                        : Translation.tr("Nothing queued")
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }

            JamPanel {
                Layout.fillWidth: true
                accent: root.cAccent
                ink: root.cFg
                muted: root.cMuted
            }

            // Now playing: the song on, in its own album's colours.
            StyledText {
                Layout.fillWidth: true
                visible: root.hasQueue && root.queue.current !== null
                text: Translation.tr("Now playing")
                variant: "micro"
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: root.cFg
            }
            Rectangle {
                id: nowRow
                readonly property var pal: root.paletteFor(root.queue ? root.queue.current : null)
                Layout.fillWidth: true
                visible: root.hasQueue && root.queue.current !== null
                implicitHeight: root.rowH
                radius: Tokens.radiusSm
                color: "transparent"
                QueueBackdrop {
                    anchors.fill: parent
                    image: root.queue && root.queue.current ? root.queue.current.image : ""
                    tint: nowRow.pal ? nowRow.pal.bg : root.cNow
                    base: root.cNow
                }
                QueueRowContent {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    row: root.queue ? root.queue.current : null
                    jam: root.queue ? root.queue.jam : null
                    ink: nowRow.pal ? nowRow.pal.fg : root.cFg
                    inkDim: nowRow.pal ? root.palette.alpha(nowRow.pal.fg, 0.9) : root.cMuted
                }
            }

            // Loud on purpose: with the DJ on there is no queue to manage, and that should be the first thing seen.
            Rectangle {
                Layout.fillWidth: true
                visible: root.hasQueue && root.queue.dj
                implicitHeight: djRow.implicitHeight + Tokens.spacingLg * 2
                radius: Tokens.radiusSm + Tokens.spacingXs
                color: root.cAccent
                RowLayout {
                    id: djRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd
                    MorphShape {
                        Layout.preferredWidth: Tokens.iconXl
                        Layout.preferredHeight: Tokens.iconXl
                        shape: "cookie9"
                        fillColor: root.palette.fgOnPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("The DJ is on: it picks the songs as it goes, so there is no queue to show.")
                        variant: "label"
                        font.weight: Font.Normal
                        color: root.palette.fgOnPrimary
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Repeater {
                model: root.rows
                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    // A divider above the first row of each group, when dividers are on.
                    readonly property var run: root.runStarting(slot.index)
                    readonly property real hdr: slot.run !== null ? root.headH : 0
                    implicitHeight: root.rowH + slot.hdr
                    // While dragged the row follows the pointer; the others make room at the drop point.
                    readonly property bool dragging: root.dragIndex === slot.index
                    // This song's own album palette: its background and text. Plain while it is read.
                    readonly property var pal: root.paletteFor(slot.modelData)
                    readonly property int shift: root.dragIndex < 0 ? 0
                        : (!slot.dragging && root.dropIndex > root.dragIndex && slot.index > root.dragIndex && slot.index <= root.dropIndex) ? -1
                        : (!slot.dragging && root.dropIndex < root.dragIndex && slot.index >= root.dropIndex && slot.index < root.dragIndex) ? 1
                        : 0
                    z: slot.dragging ? 5 : 0

                    // The divider: a hairline, the group's name and its count.
                    Item {
                        visible: slot.run !== null
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: root.headH
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingXs
                            anchors.rightMargin: Tokens.spacingXs
                            spacing: Tokens.spacingMd
                            StyledText {
                                text: slot.run !== null ? root.groupName(slot.run.provider) : ""
                                variant: "micro"
                                font.weight: Font.DemiBold
                                color: root.cAccent
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.borderWidth
                                color: root.palette.outlineNested
                            }
                            StyledText {
                                text: slot.run !== null ? String(slot.run.to - slot.run.from) : ""
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                    }

                    Rectangle {
                        id: card
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: root.rowH
                        y: slot.hdr + (slot.dragging ? dragY.value : slot.shift * root.rowH)
                        radius: Tokens.radiusSm
                        Behavior on y { enabled: !slot.dragging; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                        QueueBackdrop {
                            anchors.fill: parent
                            image: slot.modelData.image
                            tint: slot.pal ? slot.pal.bg : root.cRow
                            base: slot.dragging ? root.cNow : root.cRow
                        }

                        SpringValue { id: dragY; target: 0; spec: Motion.springSpatialFast; epsilon: 0.5 }

                        QueueRowContent {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.iconXl + Tokens.spacingSm
                            anchors.rightMargin: Tokens.iconXl + Tokens.spacingSm
                            row: slot.modelData
                            jam: root.queue ? root.queue.jam : null
                            ink: slot.pal ? slot.pal.fg : root.cFg
                            inkDim: slot.pal ? root.palette.alpha(slot.pal.fg, 0.9) : root.cMuted
                        }

                        // The grip: drag to move.
                        MaterialIcon {
                            id: grip
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.spacingXs
                            anchors.verticalCenter: parent.verticalCenter
                            name: "drag_indicator"
                            font.pixelSize: Tokens.iconMd
                            color: root.cMuted
                        }
                        DragHandler {
                            id: dh
                            target: null
                            yAxis.enabled: true
                            xAxis.enabled: false
                            cursorShape: Qt.SizeVerCursor
                            enabled: !SpotifyBridge.queueBusy
                            onActiveChanged: {
                                if (active) {
                                    root.dragIndex = slot.index
                                    root.dropIndex = slot.index
                                } else {
                                    const from = root.dragIndex
                                    const to = root.dropIndex
                                    root.dragIndex = -1
                                    root.dropIndex = -1
                                    dragY.target = 0
                                    if (from >= 0 && to >= 0 && to !== from) root.commitMove(from, to)
                                }
                            }
                            onTranslationChanged: {
                                if (!dh.active) return
                                const d = Math.round(dh.translation.y / root.rowH)
                                root.dropIndex = Math.max(0, Math.min(root.rows.length - 1, slot.index + d))
                                dragY.target = dh.translation.y
                                dragY.value = dh.translation.y
                            }
                        }

                        // Remove, under the pointer.
                        HoverHandler { id: rowHover }
                        Rectangle {
                            id: removeBtn
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.spacingXs
                            anchors.verticalCenter: parent.verticalCenter
                            width: Tokens.iconXl; height: width; radius: width / 2
                            color: root.cRow
                            opacity: rowHover.hovered || rmTap.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "close"
                                font.pixelSize: Tokens.iconMd
                                color: root.cFg
                            }
                            HoverHandler { id: rmTap }
                            TapHandler { enabled: !SpotifyBridge.queueBusy; onTapped: SpotifyBridge.queueRemove(slot.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: Translation.tr("Remove from the queue")
                            Accessible.onPressAction: SpotifyBridge.queueRemove(slot.modelData)
                        }
                    }
                }
            }

            // A refusal from Spotify, said once, in place.
            StyledText {
                Layout.fillWidth: true
                visible: SpotifyBridge.queueError !== ""
                text: SpotifyBridge.queueError
                variant: "caption"
                color: root.palette.warning
                wrapMode: Text.WordWrap
            }
        }
    }
    Scrollbar { flickable: flick }

    // Move the row at `from` to `to` (indexes into `rows`): the pure function says where it lands and what Spotify
    // is asked. The anchor is the row it goes before (or after, at the end).
    function commitMove(from, to) {
        const res = QueueModel.moveTo(root.rows, root.rows[from].uid, to)
        if (res === null) return
        const anchor = root.rows.find(r => r.uid === res.anchor)
        if (!anchor) return
        SpotifyBridge.queueMove(root.rows[from], anchor, res.where)
    }
}
