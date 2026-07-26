import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── UpdatePill ────────────────────────────────────────────────────────────────
// Pending pacman updates: an icon, a count badge, and a pulse while checking.
//
// Was UpdateButton, which owned the `checkupdates` process and its 10-minute
// timer — so the check ran once per button instance, i.e. twice, times the
// number of monitors. It's now pure presentation over the Updates service, which
// runs exactly one check no matter how many things display the count.
// ─────────────────────────────────────────────────────────────────────────────
IconButton {
    id: root

    // NOTE: `accent` is inherited from IconButton (default: Colors.primary) and drives
    // both the state ladder and the glow ring below. Do not redeclare it here — that
    // shadows the property the ladder reads, so the ring would recolour and the fill
    // wouldn't.

    signal requested(int count)

    icon:       Icons.asset("update")
    squareMode: Config.barShape

    // Having updates pending is a state worth noticing, so the button reads as
    // active even when you aren't pointing at it.
    active: Updates.count > 0

    onClicked: root.requested(Updates.count)

    // ── Glow while the panel is open ──────────────────────────────────────────
    // A breathing accent ring, so it's obvious which pill owns the panel you're looking
    // at. `active` (above) is a static fill for "updates pending"; this is a distinct,
    // moving cue for "its panel is up".
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.width: 2
        border.color: root.accent
        visible: UiState.updateOpen

        SequentialAnimation on opacity {
            running: UiState.updateOpen
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: Motion.slow; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.00; duration: Motion.slow; easing.type: Easing.InOutSine }
        }
    }

    // Count badge. Geometry follows the ICON scale along with the numeral inside it —
    // they have to move together or the digits leave the circle.
    Rectangle {
        visible: Updates.count > 0
        width:   Math.round((Updates.count > 99 ? 18 : (Updates.count > 9 ? 16 : 13))
                            * Config.barIconScale)
        height:  Math.round(13 * Config.barIconScale)
        radius:  Config.barShape ? 2 : height / 2
        color:   Updates.hasError ? Colors.warning : Colors.primary

        anchors.top:        parent.top
        anchors.right:      parent.right
        anchors.topMargin:  -3
        anchors.rightMargin: -3

        Behavior on width  { NumberAnimation { duration: Motion.fast } }
        Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        Behavior on color  { ColorAnimation  { duration: Motion.respond } }

        StyledText {
            anchors.centerIn: parent
            text:      Updates.count > 99 ? "99+" : Updates.count
            color:     Colors.fgOnPrimary
            variant:   "micro"
            sizeScale: Config.barIconScale
            font.bold: true
        }
    }

    // Checking pulse. Ambient, so it uses the slow duration — this is
    // atmosphere, not something the user is waiting on.
    Rectangle {
        visible: Updates.checking
        width:  Math.round(6 * Config.barIconScale)
        height: Math.round(6 * Config.barIconScale)
        radius: width / 2
        color:  Colors.info

        anchors.bottom:       parent.bottom
        anchors.left:         parent.left
        anchors.bottomMargin: -1
        anchors.leftMargin:   -1

        SequentialAnimation on opacity {
            running: Updates.checking
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: Motion.slow; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.00; duration: Motion.slow; easing.type: Easing.InOutSine }
        }
    }
}
