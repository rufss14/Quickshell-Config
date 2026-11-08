import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── PowerPanel ────────────────────────────────────────────────────────────────
// Top-left of the overview: the session actions, always visible — a compact row
// of four icon buttons rather than a labelled list. The overlay is already a
// deliberate thing you opened, so a screen-filling menu bought nothing.
//
// ── Why every action still needs confirming ───────────────────────────────────
// Clicking an icon ARMS it: the disc fills with its tint and the button expands
// to spell out the consequence with a Confirm button. A second, differently-placed
// click fires it. Colour cannot carry the warning here — on this pywal palette
// `danger` and `primary` are BOTH ramp1, literally the same colour — so the glyph,
// the spelled-out consequence and the two-step are what stop a misclick ending the
// session. Only one action can be armed at a time (`armed` is keyed, same shape as
// LockScreen's), and Escape or clicking the disc again disarms it.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation:    Tokens.elevationCard
    cornerRadius: Tokens.radiusXl

    // The bar's own pills brighten their whole border on hover; a pending
    // Lock/Restart/Shutdown is exactly the moment this card most wants to say
    // "I'm the thing you're looking at".
    focused: panelHover.hovered || root.armed !== ""
    HoverHandler { id: panelHover }

    implicitWidth:  row.implicitWidth  + Tokens.spacingMd * 2
    implicitHeight: row.implicitHeight + Tokens.spacingMd * 2

    property string armed: ""

    // ── Firing an action ──────────────────────────────────────────────────────
    // services/Session does each of these (the sidebar's power module does too);
    // this card only decides when a click means it.
    function fire(action) {
        if (action.key === "lock")          Session.lock()
        else if (action.key === "logout")   Session.logout()
        else if (action.key === "reboot")   Session.reboot()
        else if (action.key === "shutdown") Session.poweroff()
    }

    // Each disc is a scalloped CookieButton (see components/CookieButton.qml).
    // `points`/`tilt` come in mirrored pairs: lock ↔ shut down (5-point, ∓12°),
    // log out ↔ restart (7-point, ∓20°).
    readonly property var actions: [
        {
            key: "lock", glyph: "󰌾", label: "Lock",
            detail: "Lock the screen",
            tint: Colors.of(QsWindow.window).info, points: 5, tilt: -12
        },
        {
            key: "logout", glyph: "󰍃", label: "Log out",
            detail: "End the Hyprland session",
            tint: Colors.of(QsWindow.window).focus, points: 7, tilt: -20
        },
        {
            key: "reboot", glyph: "󰜉", label: "Restart",
            detail: "Reboot the machine",
            tint: Colors.of(QsWindow.window).warning, points: 7, tilt: 20
        },
        {
            key: "shutdown", glyph: "󰐥", label: "Shut down",
            detail: "Power off the machine",
            tint: Colors.of(QsWindow.window).danger, points: 5, tilt: 12
        }
    ]

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingXs

        Repeater {
            model: root.actions

            Rectangle {
                id: btn
                required property var modelData

                readonly property bool isArmed: root.armed === btn.modelData.key
                readonly property int  disc:    40

                height: btn.disc
                // The confirm tail opens on an M3E spring (one 0→1 factor), so the surface, which follows
                // the row's width, needs no animation of its own.
                SpringValue {
                    id: open
                    target: btn.isArmed ? 1 : 0
                    spec: Motion.springSpatial
                    epsilon: 0.002
                }
                width: btn.disc + open.value * (confirmRow.implicitWidth + Tokens.spacingSm * 2)
                radius: Tokens.radiusPill
                color:  btn.isArmed ? Colors.of(QsWindow.window).alpha(btn.modelData.tint, 0.16) : "transparent"
                // No clip — the disc's hover scale/rotation needs to spill past the
                // pill's edge. The confirm tail fades in on its own opacity.
                clip:   false

                Behavior on color { ColorAnimation  { duration: Motion.respond } }

                // ── The disc — a scalloped cookie per action ──────────────────
                // Armed → filled solid with the action's tint; otherwise outlined,
                // tinting on hover. Hover winds the shape. Click arms; click again
                // backs out (the Confirm button in the tail is what fires it).
                CookieButton {
                    id: discRect
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth:  btn.disc
                    implicitHeight: btn.disc

                    glyph:    btn.modelData.glyph
                    // At rest the glyph is plain foreground (the semantic tints are near-grey on this palette and the
                    // tray read as disabled); the tint arrives with the arming, where it carries the warning.
                    tint:     btn.isArmed ? btn.modelData.tint : Colors.of(QsWindow.window).fg
                    primary:  btn.isArmed
                    points:   btn.modelData.points
                    restTilt: btn.modelData.tilt

                    onActivated: root.armed = btn.isArmed ? "" : btn.modelData.key
                    HoverTip { below: true; text: Translation.tr(btn.modelData.label) }
                }

                // ── The confirm tail, only while armed ────────────────────────
                Row {
                    id: confirmRow
                    anchors.left: discRect.right
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    visible: open.value > 0.01
                    opacity: Math.max(0, Math.min(1, open.value))
                    spacing: Tokens.spacingSm

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  btn.modelData.detail + "?"
                        color: btn.modelData.tint
                        variant: "label"
                        font.weight: Font.DemiBold
                    }

                    PanelButton {
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "primary"
                        accent:  btn.modelData.tint
                        label:   Translation.tr("Confirm")
                        onActivated: {
                            // Close first, then act: the overview must not sit under
                            // the lock surface waiting to reappear when you unlock.
                            UiState.overviewOpen = false
                            root.fire(btn.modelData)
                        }
                    }
                }
            }
        }
    }
}
