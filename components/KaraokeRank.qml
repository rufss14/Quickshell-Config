import QtQuick
import Quickshell
import "../config"

// ── KaraokeRank ───────────────────────────────────────────────────────────────
// A rank (SS+, SS, S, A, B, C, F) as a badge: the letter on a rounded plate in its tier's colour, the
// way a rhythm game stamps a result. One shape, used by the live HUD, the results screen and the
// scores list, so a rank looks like the same thing everywhere.
//
// Every colour is a palette role (never a hex): SS wears the accent, S the focus colour, A success,
// B info, C warning, F danger. On a monochrome palette they all read as greys and the LETTER carries
// the rank — which is why it is the letter that is big.
//
// SS and SS+ are alive: their halo breathes — SS+ with a second one half a beat behind the first, and in a
// brighter tone (the accent mixed toward the text colour), because a flawless 100% should not look like SS
// with a plus. That is a loop, so it only runs while the badge is on screen (`lively` and visible), never
// for one in a list that has scrolled away.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string rank: ""
    property int size: 40
    // May the halo of an SS breathe? The list turns it off for rows that are not on screen.
    property bool lively: true

    readonly property var pal: Colors.of(QsWindow.window)

    function inkFor(r) {
        switch (r) {
        case "SS+": return root.pal.mix(root.pal.primary, root.pal.fg, 0.4)
        case "SS": return root.pal.primary
        case "S":  return root.pal.focus
        case "A":  return root.pal.success
        case "B":  return root.pal.info
        case "C":  return root.pal.warning
        case "F":  return root.pal.danger
        default:   return root.pal.fgMuted
        }
    }
    readonly property color ink: root.inkFor(root.rank)

    implicitWidth:  root.size
    implicitHeight: root.size
    visible: root.rank !== ""

    // The halos. Only SS and SS+ breathe; for the rest they are absent, not just still. SS+ has two, the
    // second a half-cycle behind.
    readonly property bool halos: root.rank === "SS" || root.rank === "SS+"
    Rectangle {
        id: halo2
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: Math.round(root.size * 0.28)
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: root.ink
        visible: root.rank === "SS+"
        opacity: 0
        scale: 1

        SequentialAnimation {
            running: halo2.visible && root.lively && root.visible
            loops: Animation.Infinite
            PauseAnimation { duration: Motion.glide }
            ParallelAnimation {
                NumberAnimation { target: halo2; property: "scale"; from: 1; to: 1.55; duration: Motion.glide * 2; easing.type: Motion.travel }
                NumberAnimation { target: halo2; property: "opacity"; from: 0.6; to: 0; duration: Motion.glide * 2; easing.type: Motion.travel }
            }
        }
    }
    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: Math.round(root.size * 0.28)
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: root.ink
        visible: root.halos
        opacity: 0
        scale: 1

        SequentialAnimation {
            running: halo.visible && root.lively && root.visible
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: halo; property: "scale"; from: 1; to: 1.4; duration: Motion.glide * 2; easing.type: Motion.travel }
                NumberAnimation { target: halo; property: "opacity"; from: 0.7; to: 0; duration: Motion.glide * 2; easing.type: Motion.travel }
            }
            PauseAnimation { duration: Motion.glide }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.round(root.size * 0.28)
        color: Colors.of(QsWindow.window).alpha(root.ink, 0.16)
        border.width: Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).alpha(root.ink, 0.75)
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    Text {
        anchors.centerIn: parent
        // A hair up: a capital sits low in its line box.
        anchors.verticalCenterOffset: -Math.round(root.size * 0.02)
        text: root.rank
        color: root.ink
        font.family: Tokens.fontFamily
        font.bold: true
        // Two letters need to be smaller than one to sit in the same plate.
        font.pixelSize: Math.round(root.size * (root.rank.length > 2 ? 0.34 : root.rank.length > 1 ? 0.44 : 0.58))
        font.letterSpacing: root.rank.length > 1 ? -Math.round(root.size * 0.02) : 0
    }
}
