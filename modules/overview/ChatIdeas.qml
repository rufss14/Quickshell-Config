import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── ChatIdeas ─────────────────────────────────────────────────────────────────
// What the Ask page shows before anything's been said: the chip, what it's for, and four things to
// ask as slim rows — a tap sends that sentence. The four are drawn at random from a bigger pool each
// time a conversation starts (the user, 2026-10-24: the tiles were too big — the rows came back —
// and "more, but appearing randomly by convo"). They rise in one after another.
// ─────────────────────────────────────────────────────────────────────────────
Column {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    property int count: 4
    signal picked(string text)

    spacing: Tokens.spacingMd
    topPadding: Tokens.spacingSm

    readonly property var pool: [
        { symbol: "palette",           text: Translation.tr("Make me a calmer colour scheme") },
        { symbol: "light_mode",        text: Translation.tr("Switch to light mode") },
        { symbol: "dark_mode",         text: Translation.tr("Back to dark mode") },
        { symbol: "shuffle",           text: Translation.tr("Give me a random wallpaper") },
        { symbol: "wallpaper",         text: Translation.tr("Put on a Wallpaper Engine scene") },
        { symbol: "nights_stay",       text: Translation.tr("Turn the night light on") },
        { symbol: "volume_up",         text: Translation.tr("Set the volume to 30%") },
        { symbol: "brightness_6",      text: Translation.tr("Dim the screens to 40%") },
        { symbol: "timer",             text: Translation.tr("Start a 25-minute focus timer") },
        { symbol: "music_note",        text: Translation.tr("Play some lofi on Spotify") },
        { symbol: "skip_next",         text: Translation.tr("Skip this song") },
        { symbol: "notifications_off", text: Translation.tr("Don't disturb me for a while") },
        { symbol: "sports_esports",    text: Translation.tr("Turn game mode on") },
        { symbol: "coffee",            text: Translation.tr("Keep the screen awake") },
        { symbol: "tune",              text: Translation.tr("Rounder corners and softer shadows") },
        { symbol: "speed",             text: Translation.tr("Make the animations snappier") },
        { symbol: "language",          text: Translation.tr("Open YouTube") },
        { symbol: "search",            text: Translation.tr("Search the weather for today") },
        { symbol: "open_in_new",       text: Translation.tr("Open the file manager") },
        { symbol: "grid_view",         text: Translation.tr("Take me to workspace 3") },
        { symbol: "text_fields",       text: Translation.tr("Copy some text from the screen") },
        { symbol: "colorize",          text: Translation.tr("Pick a colour from the screen") },
        { symbol: "movie",             text: Translation.tr("Save a clip of what just happened") }
    ]
    property var shown: []
    // A fresh draw: shuffled, the first `count`.
    function draw() {
        const p = root.pool.slice()
        for (let i = p.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const t = p[i]; p[i] = p[j]; p[j] = t
        }
        root.shown = p.slice(0, root.count)
    }
    Component.onCompleted: root.draw()
    // Shown again = a new conversation (the thread was cleared): new ideas.
    onVisibleChanged: if (root.visible) root.draw()

    ScallopChip {
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: 56
        implicitHeight: 56
        symbol: "auto_awesome"
        tint: root.accent
        hot: chipHover.hovered
        HoverHandler { id: chipHover }
    }
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Translation.tr("Ask for a change")
        variant: "body"
        font.weight: Font.DemiBold
    }
    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("Colours, settings, wallpaper, music, apps — done at once, each with an Undo.")
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.Wrap
    }

    Repeater {
        model: root.shown
        delegate: Rectangle {
            id: idea
            required property var modelData
            required property int index
            width: root.width
            height: ideaRow.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusCard - Tokens.spacingXs
            color: Colors.of(QsWindow.window).fade(ideaHover.hovered
                       ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, root.accent, 0.12)
                       : Colors.of(QsWindow.window).surfaceContainer, 0.88)
            SpringValue { id: ideaLean; target: ideaTap.pressed ? 0.98 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
            scale: ideaLean.value
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            ViewEnter { target: idea; active: root.visible; delay: Motion.stagger * (2 + idea.index) }

            Row {
                id: ideaRow
                x: Tokens.spacingMd
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacingMd
                MaterialIcon {
                    id: ideaIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: idea.modelData.symbol
                    fill: ideaHover.hovered ? 1 : 0
                    color: root.accent
                    font.pixelSize: Tokens.iconMd
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: idea.width - ideaIcon.width - Tokens.spacingMd * 3
                    text: idea.modelData.text
                    variant: "caption"
                    wrapMode: Text.Wrap
                }
            }
            HoverHandler { id: ideaHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: ideaTap; onTapped: root.picked(idea.modelData.text) }
        }
    }
}
