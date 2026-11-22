pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── VoicePeopleGrid ── VoicePanel's People face on an island; `panel` is the VoicePanel. ──────────────────────
// Everyone in the call as a tile (the sidebar's list rows were lost on a card this size): a big face ringed in the
// accent while they speak, the name, what they are doing (speaking, muted, deafened, their level), mute-for-me as
// a lit tool, and their volume as a slider (0 to 200%, 100 marked) right on the tile. Your own tile has your mic
// and headphones and leads to Your audio. Under the tiles, the people you have spent the most time with in calls
// (services/CallLog), which leads to the Board.
//
// Per-person balance stays in the sidebar's list (a tile has no room to say left and right well).
// Everything real is services/Discord and services/CallLog; this shows them and calls them.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Item {
    id: grid
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var users: Discord.users
    readonly property int cols: grid.users.length > 4 ? 3 : 2
    readonly property int rows: Math.max(1, Math.ceil(grid.users.length / grid.cols))
    // A few people share the height, so one or two in a call get tall tiles with big faces stacked over the
    // name. Two rows of two (3 or 4 people) lay each tile out sideways (face left, name right, controls under)
    // so four fit without scrolling; past that the tiles keep a floor and the grid scrolls.
    readonly property bool sideways: grid.cols === 2 && grid.rows > 1
    readonly property real tileFloor: grid.sideways ? Tokens.spacingXl * 7 : Tokens.spacingXl * 10 + Tokens.spacingSm
    readonly property real tileH: Math.max(grid.tileFloor, Math.floor(tiles.height / grid.rows) - Tokens.spacingSm)
    readonly property real faceSize: grid.sideways
        ? Math.max(Tokens.iconXl * 2, Math.min(grid.tileH * 0.5, Tokens.iconXl * 3))
        : Math.max(Tokens.iconXl * 2, Math.min(grid.tileH * 0.42, Tokens.iconXl * 4))

    // The tiles' model is a list of ids kept in step with Discord.users, NOT the array itself: a speaking
    // change reassigns `users`, and a GridView bound to the array rebuilds every tile and replays every PopIn
    // (the whole grid jumped each time someone talked). A tile reads its person from Discord.userById(uid), so
    // speaking only changes bindings; tiles are made and removed only when someone joins or leaves.
    ListModel { id: roster }
    function syncRoster() {
        const ids = grid.users.map(u => u.id ?? "")
        for (let i = roster.count - 1; i >= 0; i--)
            if (ids.indexOf(roster.get(i).uid) < 0) roster.remove(i)
        for (let i = 0; i < ids.length; i++) {
            if (i < roster.count && roster.get(i).uid === ids[i]) continue
            let at = -1
            for (let j = i + 1; j < roster.count; j++) if (roster.get(j).uid === ids[i]) { at = j; break }
            if (at >= 0) roster.move(at, i, 1)
            else roster.insert(i, { uid: ids[i] })
        }
    }
    onUsersChanged: grid.syncRoster()
    Component.onCompleted: grid.syncRoster()

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        GridView {
            id: tiles
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: Math.floor(tiles.width / grid.cols)
            cellHeight: grid.tileH + Tokens.spacingSm
            model: roster

            delegate: Item {
                id: cell
                required property string uid
                required property int index
                readonly property var modelData: Discord.userById(cell.uid) ?? ({})
                readonly property bool self: cell.modelData.isSelf ?? false
                readonly property bool speaking: cell.modelData.speaking ?? false
                readonly property bool mutedForMe: cell.modelData.mute ?? false
                readonly property bool theirMute: (cell.modelData.selfMute ?? false) || (cell.modelData.serverMute ?? false)
                readonly property bool theirDeaf: (cell.modelData.selfDeaf ?? false) || (cell.modelData.serverDeaf ?? false)
                readonly property int volume: cell.modelData.volume ?? 100
                width: tiles.cellWidth
                height: tiles.cellHeight

                PopIn { id: pop; active: true; index: cell.index; cap: 6 }
                opacity: pop.opacity

                Rectangle {
                    id: tile
                    x: Tokens.spacingXs
                    width: cell.width - Tokens.spacingSm
                    height: grid.tileH
                    scale: pop.scale
                    radius: cell.speaking ? Tokens.radiusXl : Tokens.radiusCard
                    color: cell.speaking ? grid.palette.primaryContainer : grid.palette.plate
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    readonly property color ink: cell.speaking ? grid.palette.fgOnPrimaryContainer : grid.palette.fg
                    readonly property color inkDim: cell.speaking ? grid.palette.alpha(grid.palette.fgOnPrimaryContainer, 0.72) : grid.palette.fgMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        Item { Layout.fillHeight: true; visible: !grid.sideways }

                        // Face and words: stacked and centred, or side by side on a short tile.
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: grid.sideways
                            columns: grid.sideways ? 2 : 1
                            columnSpacing: Tokens.spacingMd
                            rowSpacing: Tokens.spacingSm

                        // The face, ringed while they speak.
                        Item {
                            Layout.alignment: grid.sideways ? Qt.AlignVCenter : Qt.AlignHCenter
                            implicitWidth: grid.faceSize
                            implicitHeight: grid.faceSize
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: Tokens.spacingXs + 1
                                border.color: grid.palette.primary
                                opacity: cell.speaking ? 1 : 0
                                scale: cell.speaking ? 1 : 0.85
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                            }
                            Avatar {
                                anchors.centerIn: parent
                                width: parent.width - Tokens.spacingMd
                                height: width
                                source: cell.modelData.avatar ?? ""
                                name: cell.modelData.name ?? ""
                                opacity: cell.mutedForMe || cell.theirDeaf ? 0.45 : 1
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: grid.sideways ? Text.AlignLeft : Text.AlignHCenter
                            text: cell.self ? Translation.tr("%1 (you)").arg(cell.modelData.name ?? "") : (cell.modelData.name ?? "")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: tile.ink
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: grid.sideways ? Text.AlignLeft : Text.AlignHCenter
                            text: cell.speaking ? Translation.tr("Speaking")
                                : cell.theirDeaf ? Translation.tr("Deafened")
                                : cell.theirMute ? Translation.tr("Muted")
                                : cell.self ? Translation.tr("Your audio")
                                : cell.mutedForMe ? Translation.tr("Muted for you")
                                : Translation.tr("%1% for you").arg(cell.volume)
                            variant: "caption"
                            color: tile.inkDim
                            elide: Text.ElideRight
                        }
                        }   // text column
                        }   // GridLayout

                        Item { Layout.fillHeight: true; visible: !grid.sideways }

                        // Theirs: mute for me and their volume. Yours: mic, headphones, and Your audio.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            visible: !cell.self
                            LitTool {
                                symbol: cell.mutedForMe ? "volume_off" : "volume_up"
                                lit: cell.mutedForMe
                                ink: tile.ink
                                tip: cell.mutedForMe ? Translation.tr("Unmute for you") : Translation.tr("Mute for you")
                                onActivated: Discord.setUserMute(cell.uid, !cell.mutedForMe)
                            }
                            // The media page's thick, rounded bar; past 100% it takes the warning tone.
                            ThickSlider {
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight
                                maximum: 200
                                notchAt: 100
                                notchColor: grid.palette.warning
                                value: cell.volume
                                enabled: !cell.mutedForMe
                                accessibleName: Translation.tr("Volume of %1").arg(cell.modelData.name ?? "")
                                onMoved: function (v) { Discord.setUserVolume(cell.uid, Math.round(v)) }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            visible: cell.self
                            LitTool {
                                symbol: Discord.mute ? "mic_off" : "mic"
                                lit: Discord.mute
                                ink: tile.ink
                                tip: Discord.mute ? Translation.tr("Unmute") : Translation.tr("Mute")
                                onActivated: Discord.toggleMute()
                            }
                            LitTool {
                                symbol: "headphones"
                                lit: Discord.deaf
                                ink: tile.ink
                                tip: Discord.deaf ? Translation.tr("Undeafen") : Translation.tr("Deafen")
                                onActivated: Discord.toggleDeaf()
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                symbol: "chevron_right"
                                label: Translation.tr("Your audio")
                                tonal: true
                                onActivated: grid.panel.show("audio")
                            }
                        }
                    }
                }
            }
        }

        // ── Most time together ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingMd * 2
            visible: CallLog.board.length > 0
            radius: Tokens.radiusCard
            color: grid.palette.plate

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: false
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Most time together")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: Translation.tr("%1 in calls").arg(CallLog.duration(CallLog.totalSeconds))
                        variant: "caption"
                        emphasis: "muted"
                    }
                }
                Repeater {
                    model: CallLog.board.slice(0, 3)
                    delegate: RowLayout {
                        id: who
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm
                        Avatar {
                            source: who.modelData.avatar ?? ""
                            name: who.modelData.name ?? ""
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: who.modelData.name ?? ""
                                variant: "caption"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: CallLog.duration(who.modelData.seconds)
                                variant: "micro"
                                emphasis: "muted"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                ChipButton {
                    symbol: "chevron_right"
                    tonal: true
                    Accessible.name: Translation.tr("The whole board")
                    onActivated: grid.panel.show("board")
                }
            }
        }
    }
}
