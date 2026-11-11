import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── KaraokeHud ────────────────────────────────────────────────────────────────
// The game's live readout over the lyrics card, osu!-style, in the corners so the words stay clear:
//
//   top left    the COMBO — per WORD — and, before the first line, GET READY
//   top right   a pill: the rank you are on track for, the accuracy, and — for a moment after each
//               line — its JUDGMENT, which grows out of the pill's left edge and folds back in
//
// Nothing here takes the pointer, and nothing draws over the lyrics themselves. The judgment used to
// float across the middle of the card, on the words being sung; it lives in the pill now, which is
// already where the eye goes to see how you are doing. The listening status is not here: it is the
// panel's subtitle.
//
// ── The motion, and why it is each thing ──────────────────────────────────────
//   combo      every word you sing nudges it (a quick, small bump — words come fast, so it has to be
//              cheap to repeat); every 10 words, and harder at 25, 50 and 100, it PULSES with a ring;
//              when it BREAKS it flashes in the danger colour, shakes and falls away.
//   get ready  a thin bar that drains to the first line, so the time you have is something you see.
//   accuracy   rolls its digits (RollText) rather than swapping them.
//   rank       pops when it changes tier, up or down.
//   judgment   unfolds, holds, folds away.
// The combo number is held in `shown`, copied while it is nonzero and never cleared: a fading
// surface keeps its own copy (CLAUDE.md), or the digits would blank the instant it broke and spend
// the whole fall-out empty.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    readonly property var pal: Colors.of(QsWindow.window)

    // Only while playing the game; the numbers only once a line has been judged.
    readonly property bool playing: Karaoke.active && Karaoke.session.count > 0
    enabled: false
    opacity: Karaoke.active ? 1 : 0
    visible: opacity > 0.005
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    function judgmentInk(j) {
        return j === "perfect" ? root.pal.primary : j === "great" ? root.pal.focus
             : j === "good" ? root.pal.info : root.pal.danger
    }
    function comboInk(n) { return n >= 50 ? root.pal.primary : n >= 20 ? root.pal.focus : root.pal.fg }

    // ══ Combo, top left ═══════════════════════════════════════════════════════
    property int shown: 0                 // the held copy: see the header
    property real bump: 0                 // 0..1, a word
    property real pulse: 0                // 0..1, a milestone
    property real broke: 0                // 0..1, a break
    readonly property bool comboShown: root.shown >= 3

    Item {
        id: comboBox
        y: Tokens.spacingSm
        width: comboRow.implicitWidth
        height: comboRow.implicitHeight
        opacity: root.comboShown ? (1 - root.broke) : 0
        Behavior on opacity { enabled: root.broke === 0; NumberAnimation { duration: Motion.respond } }
        transformOrigin: Item.TopLeft
        scale: 1 + 0.16 * root.bump + 0.42 * root.pulse
        // A break shakes it side to side as it goes.
        x: Tokens.spacingMd - 10 * Math.sin(root.broke * Math.PI * 5) * (1 - root.broke)

        // The ring a milestone throws off.
        Rectangle {
            anchors.centerIn: parent
            width: comboRow.implicitHeight * 1.5
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Tokens.borderChrome
            border.color: root.comboInk(root.shown)
            scale: 0.6 + 1.1 * root.pulse
            opacity: 0.8 * root.pulse * (1 - root.pulse)
            visible: opacity > 0.01
        }

        Row {
            id: comboRow
            spacing: Tokens.spacingXs
            Text {
                text: root.shown
                color: Qt.tint(root.comboInk(root.shown), root.pal.alpha(root.pal.danger, root.broke))
                font.family: Tokens.fontFamily
                font.bold: true
                font.pixelSize: Math.round(Tokens.fontHeadline * 1.5)
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                text: "×"
                color: root.pal.fgMuted
                font.family: Tokens.fontFamily
                font.bold: true
                font.pixelSize: Tokens.fontLabel
            }
        }
    }

    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: root; property: "bump"; to: 1; duration: Motion.track; easing.type: Motion.travel }
        NumberAnimation { target: root; property: "bump"; to: 0; duration: Motion.respond; easing.type: Motion.travel }
    }
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: root; property: "pulse"; from: 0; to: 1; duration: Motion.slow * 1.5; easing.type: Motion.travel }
        ScriptAction { script: root.pulse = 0 }
    }
    SequentialAnimation {
        id: breakAnim
        NumberAnimation { target: root; property: "broke"; from: 0; to: 1; duration: Motion.glide; easing.type: Motion.travel }
        ScriptAction { script: { root.shown = 0; root.broke = 0 } }
    }

    // ══ Get ready, in the same corner ═════════════════════════════════════════
    // Before the first line, while there is grace: how long you have, drained like a fuse.
    Item {
        id: ready
        x: Tokens.spacingMd
        y: Tokens.spacingSm
        width: readyCol.implicitWidth
        height: readyCol.implicitHeight
        readonly property real remaining: Karaoke.getReadyIn
        // What the bar is a fraction of: the countdown's starting length, held so the bar does not
        // jump as it runs down. A NEW countdown starts higher than the last one ended, and resets it.
        property real total: 0
        property real _prev: 0
        onRemainingChanged: {
            if (remaining > _prev + 0.5 || remaining > total) total = remaining
            _prev = remaining
        }
        opacity: remaining > 0.05 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        visible: opacity > 0.01

        Column {
            id: readyCol
            spacing: Tokens.spacingXs
            Text {
                text: Translation.tr("GET READY")
                color: root.pal.primary
                font.family: Tokens.fontFamily
                font.bold: true
                font.letterSpacing: 2
                font.pixelSize: Tokens.fontMicro
            }
            Rectangle {
                width: Tokens.spacingXl * 3
                height: 3
                radius: 2
                color: root.pal.alpha(root.pal.primary, 0.18)
                Rectangle {
                    width: parent.width * (ready.total > 0 ? Math.min(1, ready.remaining / ready.total) : 0)
                    height: parent.height
                    radius: 2
                    color: root.pal.primary
                }
            }
        }
    }

    // ══ Accuracy, rank and judgment: the pill, top right ══════════════════════
    property string judgeKind: "perfect"
    property real judgeShow: 0            // 0..1: how far the judgment has unfolded

    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingMd
        anchors.top: parent.top
        anchors.topMargin: Tokens.spacingSm
        height: Tokens.iconXl + Tokens.spacingMd
        width: pillRow.implicitWidth + Tokens.spacingMd * 2
        radius: height / 2
        color: root.pal.surfaceContainer
        border.width: Tokens.borderWidth
        border.color: root.pal.alpha(root.pal.fg, 0.06)
        opacity: root.playing ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            KaraokeRank {
                id: liveRank
                Layout.alignment: Qt.AlignVCenter
                rank: Karaoke.rank
                size: Tokens.iconXl
                lively: root.playing
                transformOrigin: Item.Center
                property real pop: 0
                scale: 1 + 0.4 * pop
                SequentialAnimation {
                    id: rankPop
                    NumberAnimation { target: liveRank; property: "pop"; to: 1; duration: Motion.respond; easing.type: Motion.travel }
                    NumberAnimation { target: liveRank; property: "pop"; to: 0; duration: Motion.slow; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.45 }
                }
            }
            RollText {
                Layout.alignment: Qt.AlignVCenter
                text: Karaoke.accuracy.toFixed(1) + "%"
                color: root.pal.fg
                family: Tokens.fontMono
                pixelSize: Tokens.fontLabel
                weight: Font.DemiBold
            }
            // The mods this run is being played with (HD, HR, TH).
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: Karaoke.mods.length > 0
                text: Karaoke.modsText(Karaoke.mods)
                color: root.pal.info
                font.family: Tokens.fontFamily
                font.bold: true
                font.letterSpacing: 1
                font.pixelSize: Tokens.fontMicro
            }
            // The judgment: unfolds out of the pill's left side. Zero-width at rest, so the pill is
            // exactly as wide as it always was.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Math.round(judgeText.implicitWidth * root.judgeShow)
                Layout.preferredHeight: judgeText.implicitHeight
                clip: true
                opacity: root.judgeShow
                Text {
                    id: judgeText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.judgeKind.toUpperCase()
                    color: root.judgmentInk(root.judgeKind)
                    font.family: Tokens.fontFamily
                    font.bold: true
                    font.letterSpacing: 1
                    font.pixelSize: Tokens.fontMicro + 1
                }
            }
        }
    }

    // ══ Unranked ══════════════════════════════════════════════════════════════
    // A run that cannot rank (joined mid-song, or skipped about in) says so as it is sung, under the pill.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingMd + Tokens.spacingSm
        y: Tokens.spacingSm + Tokens.iconXl + Tokens.spacingMd + Tokens.spacingXs
        text: Translation.tr("UNRANKED")
        color: root.pal.warning
        font.family: Tokens.fontFamily
        font.bold: true
        font.letterSpacing: 2
        font.pixelSize: Tokens.fontMicro
        opacity: Karaoke.active && !Karaoke.runValid ? 0.9 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
    }

    SequentialAnimation {
        id: judgeAnim
        NumberAnimation { target: root; property: "judgeShow"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot; easing.overshoot: 1.6 }
        PauseAnimation { duration: Motion.slow * 2 }
        NumberAnimation { target: root; property: "judgeShow"; to: 0; duration: Motion.slow; easing.type: Motion.exitCurve }
    }

    // ══ What drives it ════════════════════════════════════════════════════════
    property string _lastRank: ""
    Connections {
        target: Karaoke
        function onWordHit(combo) {
            if (breakAnim.running) { breakAnim.stop(); root.broke = 0 }
            root.shown = combo
            bumpAnim.restart()
            // The round numbers get a ring and a bigger pulse.
            if (combo === 10 || combo === 25 || combo === 50 || (combo >= 100 && combo % 50 === 0)) pulseAnim.restart()
            else if (combo > 0 && combo % 10 === 0) pulseAnim.restart()
        }
        function onComboBroken(was) {
            if (was >= 3) { root.shown = was; breakAnim.restart() }
            else root.shown = 0
        }
        function onLineScored(kind, points, combo) {
            root.judgeKind = kind
            judgeAnim.restart()
        }
        function onActiveChanged() {
            if (Karaoke.active) { root.shown = 0; root.broke = 0; root._lastRank = ""; root.judgeShow = 0 }
        }
    }
    // A change of tier pops the badge, either way.
    readonly property string rankNow: Karaoke.rank
    onRankNowChanged: {
        if (root._lastRank !== "" && root.rankNow !== "" && root.rankNow !== root._lastRank) rankPop.restart()
        root._lastRank = root.rankNow
    }
}
