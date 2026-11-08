import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/karaoke.js" as KJ

// ── KaraokeScoresView ─────────────────────────────────────────────────────────
// The scores tab of the media panel: every song you have finished, with its cover, its best rank and
// accuracy, and how many times you have played it (services/KaraokeScores). A row opens to its
// judgment counts, its last runs as a small bar chart, and a delete that wants two clicks.
//
// Built when the tab is opened and gone when it is left (the panel puts it behind a Loader), so the
// list slides in afresh each visit — the entrance is the ListView's `populate`, each row a beat after
// the one above it.
//
// A song with no saved cover yet draws the player's own URL, and a note glyph if it has neither.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    readonly property var pal: Colors.of(QsWindow.window)

    spacing: Tokens.spacingSm

    // A badge nobody sees, kept for its colour lookup (rank → palette role).
    KaraokeRank { id: inks; visible: false; rank: "S" }

    // ── The header ────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd
        visible: KaraokeScores.summary.songs > 0

        StyledText {
            text: KaraokeScores.summary.songs + (KaraokeScores.summary.songs === 1 ? " song" : " songs")
                  + "  ·  " + KaraokeScores.summary.plays + (KaraokeScores.summary.plays === 1 ? " play" : " plays")
            variant: "caption"
            emphasis: "dim"
        }
        Item { Layout.fillWidth: true }
        // How many songs sit at each best rank, for the ranks that have any.
        Repeater {
            model: ["SS+", "SS", "S", "A", "B", "C", "F"].filter(r => KaraokeScores.summary.ranks[r] > 0)
            delegate: Row {
                required property string modelData
                spacing: Tokens.spacingXs
                KaraokeRank {
                    anchors.verticalCenter: parent.verticalCenter
                    rank: modelData
                    size: Tokens.iconLg
                    lively: false
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: KaraokeScores.summary.ranks[modelData]
                    variant: "caption"
                    font.family: Tokens.fontMono
                    font.bold: true
                }
            }
        }
    }

    // ── Nothing yet ───────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: Tokens.spacingXl
        Layout.bottomMargin: Tokens.spacingXl
        spacing: Tokens.spacingSm
        visible: KaraokeScores.songs.length === 0

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            name: "star"
            font.pixelSize: Tokens.iconXl * 2
            color: root.pal.fgMuted
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("No scores yet")
            font.bold: true
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            variant: "caption"
            emphasis: "dim"
            text: Translation.tr("Turn on the mic in the header and sing a song with synced lyrics through to the end.")
        }
    }

    // ── The songs ─────────────────────────────────────────────────────────────
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: false
        // Hugs its rows up to a height, then scrolls (the panel sizes itself to its content).
        Layout.preferredHeight: Math.min(list.contentHeight, Tokens.spacingXl * 13)
        visible: list.count > 0
        clip: true
        spacing: Tokens.spacingXs
        boundsBehavior: Flickable.StopAtBounds
        model: KaraokeScores.songs

        // Each row slides in a beat after the one above.
        populate: Transition {
            SequentialAnimation {
                PropertyAction { properties: "opacity"; value: 0 }
                PauseAnimation { duration: ViewTransition.index * 40 }
                ParallelAnimation {
                    NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: Motion.standard }
                    NumberAnimation { properties: "x"; from: Tokens.spacingXl; to: 0; duration: Motion.slow; easing.type: Motion.travel }
                }
            }
        }
        add: Transition {
            NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: Motion.standard }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { properties: "opacity"; to: 0; duration: Motion.respond }
                NumberAnimation { properties: "x"; to: -Tokens.spacingXl; duration: Motion.respond }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Motion.standard; easing.type: Motion.travel }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            property bool expanded: false

            width: ListView.view.width
            height: col.implicitHeight + Tokens.spacingSm * 2
            radius: Tokens.radiusSm
            clip: true
            color: hover.hovered ? root.pal.alpha(root.accent, 0.1) : root.pal.surfaceContainer
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

            HoverHandler { id: hover }
            TapHandler { onTapped: row.expanded = !row.expanded }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.spacingSm
                spacing: Tokens.spacingSm

                // ── The row ───────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: Tokens.radiusXs
                        color: root.pal.surfaceHigh
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: KaraokeScores.coverUrl(row.modelData)
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(96, 96)
                            asynchronous: true
                            smooth: true
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "music_note"
                            font.pixelSize: Tokens.iconLg
                            color: root.pal.fgMuted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: (row.modelData.artist !== "" ? row.modelData.artist + "  ·  " : "")
                                  + row.modelData.plays + (row.modelData.plays === 1 ? " play" : " plays")
                                  + (row.modelData.best.mods !== "" ? "  ·  " + Karaoke.modsText(row.modelData.best.mods) : "")
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.fillHeight: false
                        spacing: 0
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: row.modelData.best.accuracy.toFixed(1) + "%"
                            color: root.pal.fg
                            font.family: Tokens.fontMono
                            font.bold: true
                            font.pixelSize: Tokens.fontBody
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: KJ.formatScore(row.modelData.best.score)
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                    }

                    KaraokeRank {
                        rank: row.modelData.best.rank
                        size: 44
                        // Only a row you can see breathes.
                        lively: row.y + row.height > list.contentY && row.y < list.contentY + list.height
                    }
                }

                // ── The details ───────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    visible: row.expanded
                    opacity: row.expanded ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingLg

                        Repeater {
                            model: [
                                { label: "PERFECT", n: row.modelData.best.perfect, ink: root.pal.primary },
                                { label: "GREAT",   n: row.modelData.best.great,   ink: root.pal.focus },
                                { label: "GOOD",    n: row.modelData.best.good,    ink: root.pal.info },
                                { label: "MISS",    n: row.modelData.best.miss,    ink: root.pal.danger }
                            ]
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillHeight: false
                                spacing: 0
                                Text {
                                    text: modelData.label
                                    color: modelData.ink
                                    font.family: Tokens.fontFamily
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.pixelSize: Tokens.fontMicro
                                }
                                Text {
                                    text: modelData.n
                                    color: root.pal.fg
                                    font.family: Tokens.fontMono
                                    font.bold: true
                                    font.pixelSize: Tokens.fontLabel
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillHeight: false
                            spacing: 0
                            Text {
                                text: "COMBO"
                                color: root.pal.fgMuted
                                font.family: Tokens.fontFamily
                                font.bold: true
                                font.letterSpacing: 1
                                font.pixelSize: Tokens.fontMicro
                            }
                            Text {
                                text: row.modelData.best.maxCombo + "×"
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontLabel
                            }
                        }
                        // The mods the best was played with, and their multiplier.
                        ColumnLayout {
                            visible: row.modelData.best.mods !== ""
                            Layout.fillHeight: false
                            spacing: 0
                            Text {
                                text: "MODS"
                                color: root.pal.info
                                font.family: Tokens.fontFamily
                                font.bold: true
                                font.letterSpacing: 1
                                font.pixelSize: Tokens.fontMicro
                            }
                            Text {
                                text: Karaoke.modsText(row.modelData.best.mods) + "  ×" + Karaoke.modsMult(row.modelData.best.mods).toFixed(2)
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontLabel
                            }
                        }
                        Item { Layout.fillWidth: true }
                        // Full combo, where the best was one.
                        Text {
                            visible: row.modelData.best.fullCombo
                            text: "FULL COMBO"
                            color: root.pal.success
                            font.family: Tokens.fontFamily
                            font.bold: true
                            font.letterSpacing: 1
                            font.pixelSize: Tokens.fontMicro
                        }
                    }

                    // The last runs, oldest to newest: a bar each, in its rank's colour.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: row.modelData.history.slice().reverse()
                            delegate: Rectangle {
                                required property var modelData
                                Layout.alignment: Qt.AlignBottom
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: Math.max(3, Math.round(modelData.accuracy / 100 * 32))
                                radius: 2
                                color: inks.inkFor(modelData.rank)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: "last " + new Date(row.modelData.last.at * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            text: "Best of " + row.modelData.best.lines + " / " + row.modelData.best.total + " lines"
                            variant: "caption"
                            emphasis: "dim"
                        }
                        Item { Layout.fillWidth: true }
                        ArmLatch {
                            id: forget
                            onConfirmed: KaraokeScores.remove(row.modelData.key)
                        }
                        PanelButton {
                            label: forget.armed ? "Sure?" : ""
                            symbol: "delete"
                            variant: "ghost"
                            accent: forget.armed ? root.pal.danger : root.accent
                            onActivated: forget.trigger()
                        }
                    }
                }
            }
        }
    }
}
