import QtQuick
import Quickshell
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

    tipProvider: Config.barTooltips ? function () { return ModuleGlance.tip("update") } : null

    // NOTE: `accent` is inherited from IconButton (default: Colors.primary) and drives
    // both the state ladder and the glow ring below. Do not redeclare it here — that
    // shadows the property the ladder reads, so the ring would recolour and the fill
    // wouldn't.

    signal requested(int count)

    container:  false
    symbol:     "terminal"
    squareMode: Config.barShape

    // ── `total`, not `count` ──────────────────────────────────────────────────
    // `Updates.count` is OFFICIAL-ONLY by deliberate design (see services/Updates.qml)
    // and this pill was the only thing in the shell treating it as the headline number —
    // the settings page and the desktop tile both already lead with `total`.
    //
    // That mismatch mattered because of what the pill DOES: it opens the panel, whose
    // one button runs a full upgrade of official + AUR + Flatpak. So a machine with
    // nothing but AUR updates showed a dark, badge-less pill that had work waiting, and
    // one with 3 official + 8 AUR opened a panel that installed 11 while the badge said
    // 3. The pill now counts what pressing it actually installs. `count` is untouched
    // and stays official-only for the breakdown consumers.
    //
    // `active` is bound below, which it deliberately was NOT while active meant a flat
    // accent-tinted FILL: the count badge already says "updates pending", and a wash
    // behind a small icon was a second, louder version of the same announcement. Now
    // that active draws an underline instead, it says the one thing the badge
    // cannot — "the panel this pill owns is open" — so the binding is back.

    // ── Always opens, even at zero ────────────────────────────────────────────
    // Do NOT gate this on `Updates.total > 0` with IconButton's `interactive`. That was
    // tried and it is wrong: an up-to-date system is the common case, so the pill spent
    // most of its life with its MouseArea disabled and the panel simply would not open.
    //
    // Opening at zero is useful anyway — the panel also carries the Vencord re-patch
    // button, which has nothing to do with pending packages, and a `pacman -Syu` with
    // nothing to do is fast and harmless. The badge above already communicates
    // "nothing pending"; the button does not also need to refuse.
    onClicked: root.requested(Updates.total)

    // The "its panel is open" underline is IconButton's now, for every button in
    // the shell rather than this one — so this pill just reports the state and the
    // base draws it. See IconButton's active underline.
    active: UiState.updateOpen

    // Count badge — the shared one (CountBadge), which the sidebar's bell wears too.
    // A newer Quicktest release counts as one (services/ShellUpdate) — on an
    // otherwise current system it's the only thing that would light this up.
    CountBadge {
        visible: count > 0
        count:   Updates.total + (ShellUpdate.available ? 1 : 0)
        tint:    Updates.hasError ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).primary

        anchors.top:        parent.top
        anchors.right:      parent.right
        anchors.topMargin:  -3
        anchors.rightMargin: -3
    }

    // Checking pulse. It used to call itself ambient — "atmosphere, not something
    // the user is waiting on" — and take `Motion.slow` accordingly. That had it
    // backwards: this dot is the only thing on the bar saying a check is in
    // progress, so it is precisely something you are waiting on, and `slow` meant
    // it stopped moving entirely when animations were switched off.
    Rectangle {
        visible: Updates.checking
        width:  Math.round(6 * Config.barIconScale)
        height: Math.round(6 * Config.barIconScale)
        radius: width / 2
        color:  Colors.of(QsWindow.window).info

        anchors.bottom:       parent.bottom
        anchors.left:         parent.left
        anchors.bottomMargin: -1
        anchors.leftMargin:   -1

        // Busy indicator: `Motion.pulse` is exempt from the animations toggle, so
        // this keeps breathing while the check is genuinely running. See BusyDot.
        SequentialAnimation on opacity {
            running: Updates.checking
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: Motion.pulse; easing.type: Motion.ambient }
            NumberAnimation { to: 1.00; duration: Motion.pulse; easing.type: Motion.ambient }
        }
    }
}
