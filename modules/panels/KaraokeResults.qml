import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/karaoke.js" as KJ

// ── KaraokeResults ────────────────────────────────────────────────────────────
// The screen at the end of a song, as a rhythm game stamps it. Over the whole media panel; a click
// outside the card, or Close, puts it away.
//
//   the cover        blurred behind everything, so the screen wears the song
//   the headline     a word for the rank (FLAWLESS … TRY AGAIN), in the rank's colour
//   the rank         slams in; S and SS throw confetti, SS keeps breathing, F lands and shakes
//   the numbers      accuracy (with how far it is from your best, and a rank-up chip), score, max
//                    combo, and the words you hit — each counts up
//   the song, line   a column per judged line, coloured by its judgment, that sweeps in left to right:
//   by line          WHERE in the song you were good, and where you lost it
//   the judgments    four bars filling
//   the actions      Play again, Next song, Scores — and Close. The player is held at the end of the
//                    song while this is up (Config.karaokeStayAtEnd), so the next song is YOURS to start
//
// ── It is one timeline ────────────────────────────────────────────────────────
// Six numbers (cardIn, rankIn, ringT, countT, barsIn, graphIn, burst, shakeT — each 0..1) run in
// sequence, and every piece reads the one it belongs to; nothing animates on its own clock. That is
// what keeps the rank landing BEFORE the figures start counting, whatever else changes.
//
// Every colour is a palette role; every duration a Motion token or a multiple of one. The confetti's
// scatter is fixed arithmetic on the particle's index, not Math.random: the same run always lands the
// same way, and a binding that re-read a random number would redraw it.
//
// `result` is a copy (Karaoke.result) taken when the song ended, so the screen does not empty as the
// next song's numbers arrive under it.
//
// ── It always fits the panel ──────────────────────────────────────────────────
// The card is a FitCard: laid out at its natural size, then scaled to the room it has, so it resizes
// with the panel instead of spilling past an edge (it used to fall back to a scroll area, which on a
// short panel left the buttons below the fold). When the room gets small the optional sections drop
// out — the line-by-line graph first, then the judgment bars — so a short panel gets a shorter card,
// not only a smaller one.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var result
    property color accent: Colors.of(QsWindow.window).primary
    signal closed()
    signal openScores()

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property string rank: root.result ? root.result.rank : ""
    readonly property bool lively: root.rank === "SS+" || root.rank === "SS" || root.rank === "S"
    readonly property int confettiCount: root.rank === "SS+" ? 56 : root.rank === "SS" ? 34 : root.rank === "S" ? 20 : 0
    readonly property color ink: rankBadge.inkFor(root.rank)

    readonly property var headlines: ({ "SS+": "PERFECTION", SS: "FLAWLESS", S: "SUPERB", A: "GREAT SHOW", B: "NICE ONE", C: "GETTING THERE", F: "TRY AGAIN" })
    readonly property var order: ["SS+", "SS", "S", "A", "B", "C", "F"]
    // Against the best you had BEFORE this run (null on a first run, or one that did not rank).
    readonly property var before: root.result ? root.result.previousBest : null
    readonly property real delta: root.before ? root.result.accuracy - root.before.accuracy : 0
    readonly property bool rankedUp: !!(root.before && root.order.indexOf(root.rank) < root.order.indexOf(root.before.rank))

    function judgmentInk(j) {
        return j === "perfect" ? root.pal.primary : j === "great" ? root.pal.focus
             : j === "good" ? root.pal.info : root.pal.danger
    }

    // ══ The timeline ══════════════════════════════════════════════════════════
    property real cardIn: 0
    property real rankIn: 0
    property real ringT: 0
    property real countT: 0
    property real barsIn: 0
    property real graphIn: 0
    property real burst: 0
    property real shakeT: 0

    function play() { entrance.restart() }
    Component.onCompleted: root.play()
    onResultChanged: if (root.result) root.play()

    SequentialAnimation {
        id: entrance
        ScriptAction { script: { root.cardIn = 0; root.rankIn = 0; root.ringT = 0; root.countT = 0; root.barsIn = 0; root.graphIn = 0; root.burst = 0; root.shakeT = 0 } }
        NumberAnimation { target: root; property: "cardIn"; to: 1; duration: Motion.slow; easing.type: Motion.travel }
        NumberAnimation { target: root; property: "rankIn"; to: 1; duration: Motion.slow * 1.6; easing.type: Motion.overshoot; easing.overshoot: 2.4 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "ringT"; to: 1; duration: Motion.glide; easing.type: Motion.travel }
            NumberAnimation { target: root; property: "countT"; to: 1; duration: Motion.glide * 1.5; easing.type: Motion.travel }
            NumberAnimation { target: root; property: "barsIn"; to: 1; duration: Motion.glide; easing.type: Motion.travel }
            NumberAnimation { target: root; property: "graphIn"; to: 1; duration: Motion.glide * 2; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "burst"; to: root.lively ? 1 : 0; duration: Motion.glide * 1.8; easing.type: Motion.travel }
            NumberAnimation { target: root; property: "shakeT"; to: root.rank === "F" ? 1 : 0; duration: Motion.slow * 1.4; easing.type: Easing.Linear }
        }
    }

    // ══ Backdrop: the cover, blurred; a click outside the card closes it ═════
    Rectangle {
        anchors.fill: parent
        color: root.pal.alpha(root.pal.surface, 0.94)
        opacity: root.cardIn
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }
    // A tiny decode, blown up and blurred further: the cover as colour and light, not as a picture.
    Image {
        id: backdropArt
        anchors.fill: parent
        source: root.result ? root.result.art : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(64, 64)
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: backdropArt
        visible: backdropArt.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: -0.2
        opacity: 0.34 * root.cardIn
    }

    // ══ The card ══════════════════════════════════════════════════════════════
    FitCard {
        id: card
        idealWidth: 580
        offsetY: (1 - root.cardIn) * Tokens.spacingXl
        opacity: root.cardIn
        // What the room allows, for the sections that can be left out.
        readonly property bool roomForGraph: card.availH >= 460
        readonly property bool roomForBars:  card.availH >= 340

        Item {
            id: flick
            width: card.innerWidth
            height: body.implicitHeight

            ColumnLayout {
                id: body
                width: flick.width
                spacing: Tokens.spacingMd

                // ── The headline ──────────────────────────────────────────────
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.headlines[root.rank] ?? ""
                    color: root.ink
                    font.family: Tokens.fontFamily
                    font.bold: true
                    font.letterSpacing: 4
                    font.pixelSize: Tokens.fontLabel
                    // Letters spread out as it arrives.
                    opacity: root.cardIn
                    scale: 0.9 + 0.1 * root.cardIn
                }

                // ── The song ──────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        radius: Tokens.radiusSm
                        color: root.pal.surfaceHigh
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: root.result ? root.result.art : ""
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(128, 128)
                            asynchronous: true
                            smooth: true
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "music_note"
                            font.pixelSize: Tokens.iconXl
                            color: root.pal.fgMuted
                            visible: !(root.result && root.result.art !== "")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.result ? (root.result.title || "Unknown") : ""
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.result ? root.result.artist : ""
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingXs
                            // NEW BEST: the one pill that moves.
                            Rectangle {
                                visible: !!(root.result && root.result.newBest && root.result.ranked)
                                width: bestText.implicitWidth + Tokens.spacingMd * 2
                                height: bestText.implicitHeight + Tokens.spacingXs * 2
                                radius: height / 2
                                color: root.pal.alpha(root.ink, 0.2)
                                border.width: Tokens.borderWidth
                                border.color: root.pal.alpha(root.ink, 0.7)
                                opacity: root.countT
                                SequentialAnimation on scale {
                                    running: parent.visible && root.countT >= 1
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.08; duration: Motion.glide; easing.type: Motion.ambient }
                                    NumberAnimation { to: 1.0; duration: Motion.glide; easing.type: Motion.ambient }
                                }
                                Text {
                                    id: bestText
                                    anchors.centerIn: parent
                                    text: Translation.tr("NEW BEST")
                                    color: root.ink
                                    font.family: Tokens.fontFamily
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.pixelSize: Tokens.fontMicro
                                }
                            }
                            // A better tier than your best: "S → SS".
                            Rectangle {
                                visible: root.rankedUp
                                width: upText.implicitWidth + Tokens.spacingMd * 2
                                height: upText.implicitHeight + Tokens.spacingXs * 2
                                radius: height / 2
                                color: root.pal.alpha(root.ink, 0.14)
                                opacity: root.countT
                                Text {
                                    id: upText
                                    anchors.centerIn: parent
                                    text: (root.before ? root.before.rank : "") + "  →  " + root.rank
                                    color: root.ink
                                    font.family: Tokens.fontFamily
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.pixelSize: Tokens.fontMicro
                                }
                            }
                            // The mods it was played with, and what they were worth.
                            Repeater {
                                model: root.result && root.result.mods ? root.result.mods.split("+").filter(m => m !== "") : []
                                delegate: Rectangle {
                                    required property string modelData
                                    width: modText.implicitWidth + Tokens.spacingMd * 2
                                    height: modText.implicitHeight + Tokens.spacingXs * 2
                                    radius: height / 2
                                    color: root.pal.alpha(root.pal.info, 0.16)
                                    border.width: Tokens.borderWidth
                                    border.color: root.pal.alpha(root.pal.info, 0.6)
                                    opacity: root.countT
                                    Text {
                                        id: modText
                                        anchors.centerIn: parent
                                        text: Karaoke.modLabel(modelData)
                                        color: root.pal.info
                                        font.family: Tokens.fontFamily
                                        font.bold: true
                                        font.letterSpacing: 1
                                        font.pixelSize: Tokens.fontMicro
                                    }
                                }
                            }
                            Rectangle {
                                visible: !!(root.result && root.result.modMult > 1)
                                width: multText.implicitWidth + Tokens.spacingMd * 2
                                height: multText.implicitHeight + Tokens.spacingXs * 2
                                radius: height / 2
                                color: "transparent"
                                border.width: Tokens.borderWidth
                                border.color: root.pal.alpha(root.pal.info, 0.6)
                                opacity: root.countT
                                Text {
                                    id: multText
                                    anchors.centerIn: parent
                                    text: root.result ? "\u00d7" + root.result.modMult.toFixed(2) : ""
                                    color: root.pal.info
                                    font.family: Tokens.fontMono
                                    font.bold: true
                                    font.pixelSize: Tokens.fontMicro
                                }
                            }
                            Rectangle {
                                visible: !!(root.result && root.result.fullCombo)
                                width: fcText.implicitWidth + Tokens.spacingMd * 2
                                height: fcText.implicitHeight + Tokens.spacingXs * 2
                                radius: height / 2
                                color: root.pal.alpha(root.pal.success, 0.18)
                                border.width: Tokens.borderWidth
                                border.color: root.pal.alpha(root.pal.success, 0.7)
                                opacity: root.countT
                                Text {
                                    id: fcText
                                    anchors.centerIn: parent
                                    text: Translation.tr("FULL COMBO")
                                    color: root.pal.success
                                    font.family: Tokens.fontFamily
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.pixelSize: Tokens.fontMicro
                                }
                            }
                        }
                    }
                }

                // ── The rank, and the numbers ─────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXl

                    Item {
                        id: rankBox
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 150

                        // The ring that leaves the rank as it lands.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 112
                            height: 112
                            radius: Math.round(112 * 0.28)
                            color: "transparent"
                            border.width: Tokens.borderChrome * 2
                            border.color: root.ink
                            scale: 0.9 + 1.5 * root.ringT
                            opacity: root.rankIn > 0.5 ? 0.85 * (1 - root.ringT) : 0
                        }

                        // Confetti: a fixed scatter from the particle's index (see the header).
                        Repeater {
                            model: root.confettiCount
                            delegate: Rectangle {
                                required property int index
                                readonly property real r1: ((index * 9301 + 49297) % 233280) / 233280
                                readonly property real r2: ((index * 4271 + 1033) % 9973) / 9973
                                readonly property real ang: r1 * Math.PI * 2
                                readonly property real dist: 56 + r2 * 120
                                readonly property var tones: [root.pal.primary, root.pal.focus, root.pal.info, root.pal.warning, root.pal.success]
                                width: 4 + Math.round(r2 * 5)
                                height: 3 + Math.round(r1 * 5)
                                radius: 1
                                color: tones[index % tones.length]
                                x: rankBox.width / 2 + Math.cos(ang) * dist * root.burst - width / 2
                                y: rankBox.height / 2 + Math.sin(ang) * dist * root.burst + 64 * root.burst * root.burst - height / 2
                                rotation: root.burst * 540 * (r2 * 2 - 1)
                                opacity: root.burst <= 0 ? 0 : Math.max(0, 1 - root.burst * root.burst)
                                visible: opacity > 0.01
                            }
                        }

                        KaraokeRank {
                            id: rankBadge
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: Math.sin(root.shakeT * Math.PI * 7) * (1 - root.shakeT) * 12
                            rank: root.rank
                            size: 112
                            // Lands from large and tilted, overshooting (rankIn runs OutBack).
                            scale: 2.4 - 1.4 * root.rankIn
                            rotation: -14 * (1 - root.rankIn)
                            opacity: Math.min(1, root.rankIn * 4)
                            lively: root.rankIn >= 1
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        columns: 2
                        columnSpacing: Tokens.spacingXl
                        rowSpacing: Tokens.spacingXs

                        // Accuracy, with how it stands against the best you had.
                        ColumnLayout {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: "ACCURACY"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }
                            RowLayout {
                                Layout.fillHeight: false
                                spacing: Tokens.spacingMd
                                Text {
                                    text: root.result ? (root.result.accuracy * root.countT).toFixed(1) + "%" : ""
                                    color: root.pal.fg
                                    font.family: Tokens.fontMono
                                    font.bold: true
                                    font.pixelSize: Math.round(Tokens.fontHeadline * 1.9)
                                    opacity: root.rankIn
                                }
                                // The gap to your best (a first run has none): up in the success colour, down in danger.
                                Row {
                                    visible: !!(root.before && root.result.ranked)
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 4
                                    spacing: 2
                                    opacity: root.countT
                                    MaterialIcon {
                                        name: root.delta >= 0 ? "arrow_upward" : "arrow_downward"
                                        font.pixelSize: Tokens.fontLabel
                                        color: root.delta >= 0 ? root.pal.success : root.pal.danger
                                    }
                                    Text {
                                        text: Math.abs(root.delta).toFixed(1) + "%"
                                        color: root.delta >= 0 ? root.pal.success : root.pal.danger
                                        font.family: Tokens.fontMono
                                        font.bold: true
                                        font.pixelSize: Tokens.fontLabel
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: "SCORE"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }
                            Text {
                                text: root.result ? KJ.formatScore(root.result.score * root.countT) : ""
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontHeadline
                                opacity: root.rankIn
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: "MAX COMBO"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }
                            Text {
                                text: root.result ? Math.round(root.result.maxCombo * root.countT) + "×" : ""
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontHeadline
                                opacity: root.rankIn
                            }
                        }
                        // The words you hit — only when a recogniser was listening to count them.
                        ColumnLayout {
                            visible: !!(root.result && root.result.wordsMode && root.result.wordsTotal > 0)
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: "WORDS"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }
                            Text {
                                text: root.result ? Math.round(root.result.wordsHit * root.countT) + " / " + root.result.wordsTotal : ""
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontHeadline
                                opacity: root.rankIn
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: "LINES"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }
                            Text {
                                text: root.result ? root.result.lines + " / " + root.result.total : ""
                                color: root.pal.fg
                                font.family: Tokens.fontMono
                                font.bold: true
                                font.pixelSize: Tokens.fontHeadline
                                opacity: root.rankIn
                            }
                        }
                    }
                }

                // ── The song, line by line ────────────────────────────────────
                // One column per judged line: its height its points, its colour its judgment. They grow
                // left to right, so the song is read in the order it was sung.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    visible: card.roomForGraph && !!(root.result && root.result.timeline && root.result.timeline.length > 1)
                    opacity: root.cardIn

                    StyledText { text: "LINE BY LINE"; variant: "caption"; emphasis: "dim"; font.letterSpacing: 1 }

                    Item {
                        id: graph
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        readonly property var tl: root.result && root.result.timeline ? root.result.timeline : []
                        readonly property real gap: tl.length > 80 ? 1 : 3
                        readonly property real colW: Math.max(2, (width - (tl.length - 1) * gap) / Math.max(1, tl.length))

                        // The 0.9 line: where a PERFECT starts.
                        Rectangle {
                            width: parent.width
                            height: 1
                            y: parent.height * (1 - 0.9)
                            color: root.pal.alpha(root.pal.fg, 0.1)
                        }
                        Repeater {
                            model: graph.tl
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                // This column's own 0..1, swept in across the whole graph with a soft front.
                                readonly property real p: Math.max(0, Math.min(1, root.graphIn * (graph.tl.length + 6) - index) / 1)
                                x: index * (graph.colW + graph.gap)
                                width: graph.colW
                                height: Math.max(3, Math.round(modelData.points * graph.height)) * Math.min(1, p)
                                y: graph.height - height
                                radius: Math.min(2, graph.colW / 2)
                                color: root.judgmentInk(modelData.judgment)
                                opacity: 0.35 + 0.65 * Math.min(1, p)
                            }
                        }
                    }
                }

                // ── The judgments ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    visible: card.roomForBars

                    Repeater {
                        model: !root.result ? [] : [
                            { label: "PERFECT", n: root.result.perfect, kind: "perfect" },
                            { label: "GREAT",   n: root.result.great,   kind: "great" },
                            { label: "GOOD",    n: root.result.good,    kind: "good" },
                            { label: "MISS",    n: root.result.miss,    kind: "miss" }
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            opacity: root.barsIn

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Text {
                                    text: modelData.label
                                    color: root.judgmentInk(modelData.kind)
                                    font.family: Tokens.fontFamily
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.pixelSize: Tokens.fontMicro
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(modelData.n * root.countT)
                                    color: root.pal.fg
                                    font.family: Tokens.fontMono
                                    font.bold: true
                                    font.pixelSize: Tokens.fontLabel
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                radius: 2
                                color: root.pal.alpha(root.judgmentInk(modelData.kind), 0.16)
                                Rectangle {
                                    width: parent.width * (root.result.lines > 0 ? modelData.n / root.result.lines : 0) * root.barsIn
                                    height: parent.height
                                    radius: 2
                                    color: root.judgmentInk(modelData.kind)
                                }
                            }
                        }
                    }
                }

                // ── What it means, when it is not a ranked run ────────────────
                StyledText {
                    Layout.fillWidth: true
                    visible: !!(root.result && !root.result.ranked)
                    wrapMode: Text.Wrap
                    variant: "caption"
                    color: root.pal.warning
                    text: !root.result ? ""
                        : root.result.why === "late"
                          ? "You joined this song part-way through, so the run was not ranked or saved. Restart it from the beginning to set a score."
                        : root.result.why === "skipped"
                          ? "You skipped around in the song, so the run was not ranked or saved. Sing it through from the start to set a score."
                        : "You sang " + root.result.lines + " of " + root.result.total
                          + " lines. A run needs at least half the song (and three lines) to count, so this one was not saved."
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !!(root.result && root.result.ranked && !root.result.newBest && root.before)
                    variant: "caption"
                    emphasis: "dim"
                    text: root.before ? "Your best is still " + root.before.accuracy.toFixed(1) + "% (" + root.before.rank + ")" : ""
                }

                // ── Where next ────────────────────────────────────────────────
                // The player is held at the end of the song, so the next one is yours to start.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    Item { Layout.fillWidth: true }
                    PanelButton {
                        label: Translation.tr("Close")
                        variant: "ghost"
                        accent: root.accent
                        onActivated: root.closed()
                    }
                    PanelButton {
                        label: Translation.tr("Play again")
                        symbol: "replay"
                        variant: "ghost"
                        accent: root.accent
                        onActivated: Karaoke.replay()
                    }
                    PanelButton {
                        label: Translation.tr("Next song")
                        symbol: "skip_next"
                        variant: "ghost"
                        accent: root.accent
                        visible: Karaoke.canNext
                        onActivated: Karaoke.next()
                    }
                    PanelButton {
                        label: Translation.tr("Scores")
                        symbol: "star"
                        variant: "primary"
                        accent: root.accent
                        visible: !!(root.result && root.result.ranked)
                        onActivated: root.openScores()
                    }
                }
            }
        }
    }
}
