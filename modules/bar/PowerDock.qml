pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../services/powermenu.js" as PowerJs
import "../../state"

// ── PowerDock ─────────────────────────────────────────────────────────────────
// The power menu: a column of big rounded buttons welded into the screen frame's right
// edge — lock, log out, restart, shut down; four, the important ones — the design
// borrowed from Caelestia's session panel. Lives in the BAR's window, as OsdDock does,
// because the blob only blends pixels inside one Qt Quick scene graph. The code is this
// shell's own; what it offers, in what order, which letter fires which and what each one
// asks is services/powermenu.js.
//
// ── The only look it has ──────────────────────────────────────────────────────
// There used to be a full-screen overlay beside it (2026-10-18: removed). That was also
// what answered while a window was fullscreen on this monitor, where Hyprland hides the bar's
// layer — so now nothing can show the menu there, and a request made then is DROPPED
// (`blocked`) rather than left open and invisible with the keyboard held. Lock still works
// from the sidebar's middle-click and the launcher.
//
// ── Motion: calm ──────────────────────────────────────────────────────────────
// The house personality (Motion.qml): decelerate-only, no overshoot, nothing waiting its turn.
// The column melts out of the frame and its buttons fade up WITH it, together. The pointed-at
// (or keyed-to) button is marked by ONE highlight that travels between buttons rather than two
// buttons cross-fading: its two edges head for the same place at different speeds
// (`Motion.standard` / `Motion.trail`, the workspace pill's indicator), so it stretches across
// the gap and contracts onto the next one. The buttons themselves only dip on a press.
//
// ── It asks twice, and the fill is the countdown ──────────────────────────────
// Everything but lock ARMS on the first press: the warning colour RISES up the button to
// full, then DRAINS over the `disarmMs` the arm lasts, so how long you have is the level on
// screen. The icon swaps to a check (SwapFade) and the caption beside it asks the question and
// lists what the action would cut off (Session.interruptText). Colour alone can't carry that —
// on a wallpaper palette `danger` and `primary` can be one ramp. The second press fires; one is
// armed at a time. Firing holds the chosen button full while the others dim.
//
// ── Keys ──────────────────────────────────────────────────────────────────────
// Each action's letter (L E R P) is a press on it (shown nowhere); ↑/↓ and Tab move the selection, Enter and
// Space press the selected one, Escape disarms and then closes, and a click anywhere outside
// closes (an invisible layer under the card, while it is open). It needs the keyboard, so the
// bar's window goes Exclusive while it is up (`wantsExclusive`) — it is opened from another
// surface, and OnDemand would never deliver the keys.
//
// ── Firing ────────────────────────────────────────────────────────────────────
// The action runs after the column has finished closing (`Motion.exit`), through Session.run:
// the lock screen comes up over a closing menu, and a machine waking from sleep doesn't find
// it still open.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: dock

    required property SideRail rail
    // The bar's own screen.
    required property var forScreen
    // The blob's spring for this lobe; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    // One screen shows it — the monitor you were on when it opened (ScreenOwner).
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: dock.forScreen
        open: UiState.powerMenuOpen
    }

    // Under a fullscreen window the bar's layer is hidden, so there is nowhere to show it.
    readonly property bool hiddenHere: Fullscreen.byMonitor[dock.forScreen?.name ?? ""] === true
    readonly property bool wanted: UiState.powerMenuOpen && dock.owns && !dock.hiddenHere

    // Asked for where it can't be seen: drop the request, or `powerMenuOpen` stays true with
    // nothing on screen (the OSD quiet, and the next toggle "closing" a menu that never showed).
    readonly property bool blocked: UiState.powerMenuOpen && dock.owns && dock.hiddenHere
    onBlockedChanged: if (dock.blocked) UiState.powerMenuOpen = false

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    readonly property bool wantsExclusive: dock.wanted
    readonly property Item maskItem: maskBox
    readonly property bool _lobe: dock.welded && dock.grow > 0.01
    readonly property real blobX: dock._lobe ? card.x : 0
    readonly property real blobY: dock._lobe ? card.y : 0
    readonly property real blobW: dock._lobe ? card.width  : 0
    readonly property real blobH: dock._lobe ? card.height : 0

    // ══ Where ═════════════════════════════════════════════════════════════════
    readonly property bool welded: dock.rail.welded
    // Flush on whatever stands on this edge: the sidebar's face if it is here, else the
    // frame's strip (0 with no frame). Not welded: a gap off it, fading in.
    readonly property real face: dock.rail.edge === "right" && dock.rail.panelFace > 0
                                 ? dock.rail.panelFace : dock.rail.strip
    readonly property real standOff: dock.welded ? 0 : Tokens.spacingXl
    readonly property real lo: Config.barExtent
    readonly property real hi: dock.rail.screenH - dock.rail.strip

    // ══ Sizes ═════════════════════════════════════════════════════════════════
    readonly property int pad: Tokens.spacingXl
    readonly property int gap: Tokens.spacingLg
    readonly property int idealButton: Tokens.spacingXl * 5
    readonly property int disarmMs: 4000

    readonly property int count: PowerJs.ACTIONS.filter(a => PowerJs.available(a, Session.caps)).length
    // The design size, shrunk only as far as a short screen forces.
    readonly property int button: PowerJs.buttonSize(dock.count, dock.hi - dock.lo - Tokens.spacingXl * 2,
                                                     dock.gap, dock.pad, dock.idealButton)
    readonly property real contentW: dock.button + dock.pad * 2
    readonly property real contentH: dock.count * dock.button + Math.max(0, dock.count - 1) * dock.gap + dock.pad * 2

    // The count can change under an open menu (an action that needs a capability the probe
    // hasn't answered yet — none does today, but the table allows it): ease the card to its
    // new height rather than jumping.
    property real alongLen: Math.min(dock.contentH, Math.max(0, dock.hi - dock.lo))
    Behavior on alongLen { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // ── The melt ──────────────────────────────────────────────────────────────
    property real grow: dock.wanted ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(dock.wanted)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: dock.wanted ? Easing.BezierSpline : Motion.exitCurve
        }
    }
    readonly property real acrossNow: dock.contentW * dock.grow

    // ══ State ═════════════════════════════════════════════════════════════════
    // The one armed ("" for none) and the ring (−1 for none).
    property string armedKey: ""
    property int    cursor: -1
    // Whether the pointer put the cursor there: leaving the column clears that one, a key's stays.
    property bool   byMouse: false
    // What the caption beside the ring says, held so it doesn't blank while the column
    // melts shut (the fade rule).
    property int    heldCursor: -1
    onCursorChanged: if (dock.cursor >= 0) dock.heldCursor = dock.cursor

    property string firing: ""

    Timer {
        id: disarm
        interval: dock.disarmMs
        onTriggered: dock.armedKey = ""
    }

    function press(a) {
        if (a.confirm && dock.armedKey !== a.key) {
            dock.armedKey = a.key
            disarm.restart()
            return
        }
        // Fire first: the button reads "armed → not armed" as a disarm unless `firing` is
        // already set, and a disarm would drain the fill the firing one holds full.
        dock.fire(a.key)
        dock.armedKey = ""
    }

    function fire(key) {
        dock.firing = key
        UiState.powerMenuOpen = false
        fireBeat.restart()
    }
    Timer {
        id: fireBeat
        interval: Math.max(1, Motion.exit)
        onTriggered: {
            const k = dock.firing
            dock.firing = ""
            Session.run(k)
        }
    }

    // Each opening starts clean and refreshes what ending the session would cut off (the
    // package-manager lock, for the caption) — a closed menu runs nothing.
    onWantedChanged: {
        if (!dock.wanted) return
        dock.armedKey = ""
        dock.cursor = -1
        Session.probe()
        keys.forceActiveFocus()
    }

    // ══ Dismiss ═══════════════════════════════════════════════════════════════
    // Under everything, covering the window while the menu is up: a click outside the card
    // lands here and closes it. (Costs the click — it does not pass through to what is
    // underneath — which is what makes it a menu and not a tooltip.)
    Item {
        id: dismissLayer
        anchors.fill: parent
        visible: dock.wanted
        TapHandler { onTapped: UiState.powerMenuOpen = false }
    }

    // The mask: the whole window while it is up (for the dismiss layer), the card while
    // it is still melting shut, nothing once it is gone.
    Item {
        id: maskBox
        x: dock.wanted ? 0 : card.x
        y: dock.wanted ? 0 : card.y
        width:  dock.wanted ? dock.width  : (dock.grow > 0.01 ? card.width  : 0)
        height: dock.wanted ? dock.height : (dock.grow > 0.01 ? card.height : 0)
    }

    // ══ Keys ══════════════════════════════════════════════════════════════════
    // On an Item, never the window (PanelWindow isn't one — the keys would silently never
    // arrive). Focus is taken as it opens.
    Item {
        id: keys
        focus: true
        Keys.onPressed: function (e) {
            if (!dock.wanted) return
            if (e.key === Qt.Key_Escape) {
                if (dock.armedKey !== "") dock.armedKey = ""
                else UiState.powerMenuOpen = false
            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab
                       || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier))) {
                dock.byMouse = false
                dock.cursor = PowerJs.step(dock.cursor, -1, Session.caps)
            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) {
                dock.byMouse = false
                dock.cursor = PowerJs.step(dock.cursor, 1, Session.caps)
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                if (dock.cursor >= 0) dock.press(PowerJs.ACTIONS[dock.cursor])
            } else {
                const i = PowerJs.indexForLetter(e.text, Session.caps)
                if (i < 0) return
                dock.byMouse = false
                dock.cursor = i
                dock.press(PowerJs.ACTIONS[i])
            }
            e.accepted = true
        }
    }

    // ══ The card ══════════════════════════════════════════════════════════════
    Card {
        id: card

        x: dock.rail.screenW - dock.face - dock.standOff - dock.acrossNow
        y: dock.lo + (dock.hi - dock.lo - dock.alongLen) / 2
        width:  dock.acrossNow
        height: dock.alongLen

        shown:      dock.wanted
        hoverFocus: false
        elevated:   !dock.welded
        // Welded while the blob draws the cookie field, the blob is the material — fill and cookies.
        blobMaterial: dock.welded && Morph.available && Drift.inBlob
        border.width: dock.welded ? 0 : Tokens.borderWidth
        transformOrigin: Item.Right
        transform: Matrix4x4 { matrix: dock.welded ? dock.deformMatrix : Qt.matrix4x4() }

        // The buttons at their own full size, pinned to the edge, so the melting box
        // uncovers them rather than squeezing them. They fade up together in the melt's
        // last half — no stagger, no pop.
        Item {
            id: content
            x: card.width - dock.contentW
            width:  dock.contentW
            height: dock.contentH
            opacity: Math.max(0, dock.grow * 2 - 1)

            Column {
                id: col
                x: dock.pad
                y: dock.pad
                spacing: dock.gap

                Repeater {
                    id: rep
                    model: PowerJs.ACTIONS

                    delegate: Item {
                        id: btn
                        required property int index
                        required property var modelData

                        readonly property var action: btn.modelData
                        readonly property bool armed: dock.armedKey === btn.action.key
                        readonly property bool ringed: dock.cursor === btn.index
                        readonly property bool hot: mouse.containsMouse || btn.ringed
                        readonly property bool pressed: mouse.pressed
                        readonly property bool fired: dock.firing === btn.action.key
                        // Asking, or already answered: the check and the full fill stay through the firing.
                        readonly property bool asking: btn.armed || btn.fired
                        // Something ELSE was chosen: this one dims out of the way.
                        readonly property bool others: dock.firing !== "" && !btn.fired
                        // The action's warning, in THIS screen's palette.
                        readonly property color warn: btn.action.tone
                            ? Colors.of(QsWindow.window)[btn.action.tone] : Colors.of(QsWindow.window).focus
                        // Hidden in place, never filtered out of the model: a model change
                        // would rebuild every button when the probe answers a moment after
                        // opening.
                        visible: PowerJs.available(btn.action, Session.caps)
                        width:  dock.button
                        height: dock.button

                        // Pressing dips it a hair; pointing at it moves nothing (the face answers).
                        scale: mouse.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }

                        property real aside: btn.others ? 1 : 0
                        Behavior on aside { NumberAnimation { duration: Motion.exit; easing.type: Motion.exitCurve } }
                        opacity: 1 - btn.aside * 0.6

                        // ── The countdown is the fill ─────────────────────────────────────
                        // Up to full as it arms, then down over the arm — `disarmMs` is a literal
                        // duration on purpose: the time IS the information (Motion.qml, kind 2), so
                        // it runs with animations off too. Letting go (disarm, Escape) drains it
                        // out fast; firing holds it full.
                        property real level: 0
                        SequentialAnimation {
                            id: armAnim
                            NumberAnimation { target: btn; property: "level"; to: 1
                                              duration: Motion.standard; easing.type: Motion.travel }
                            NumberAnimation { target: btn; property: "level"; to: 0
                                              duration: dock.disarmMs; easing.type: Easing.Linear }
                        }
                        NumberAnimation { id: letGo; target: btn; property: "level"; to: 0
                                          duration: Motion.exit; easing.type: Motion.exitCurve }
                        NumberAnimation { id: hold;  target: btn; property: "level"; to: 1
                                          duration: Motion.respond; easing.type: Motion.respondCurve }
                        onArmedChanged: {
                            if (btn.armed) { letGo.stop(); armAnim.restart() }
                            else if (!btn.fired) { armAnim.stop(); letGo.restart() }
                        }
                        onFiredChanged: {
                            if (btn.fired) { armAnim.stop(); letGo.stop(); hold.restart() }
                            else if (!btn.armed) { hold.stop(); letGo.restart() }
                        }

                        // ── The icon: a check while asking ────────────────────────────────
                        // `_name` is what is DRAWN, swapped by SwapFade at the bottom of its fade.
                        property string _name: ""
                        SwapFade {
                            target: iconBox
                            key: btn.asking ? "check" : "icon"
                            shownKey: btn._name === "check" ? "check" : "icon"
                            onSwapped: btn._name = btn.asking ? "check" : ""
                        }

                        // The face. A ClippingRectangle, so the fill is cut to the button's rounded
                        // shape. It never reacts to the pointer — the shared highlight does.
                        ClippingRectangle {
                            id: face
                            anchors.fill: parent
                            radius: Tokens.radiusCard
                            color: Colors.of(QsWindow.window).surfaceContainer
                            border.width: Tokens.borderWidth
                            border.color: btn.asking ? Colors.of(QsWindow.window).alpha(btn.warn, 0.7) : "transparent"
                            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                            // The level: the warning colour, with a hairline on its surface so the
                            // draining edge reads.
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.height * btn.level
                                visible: btn.level > 0.001
                                color: Colors.of(QsWindow.window).alpha(btn.warn, 0.34)

                                Rectangle {
                                    anchors.top: parent.top
                                    width: parent.width
                                    height: Tokens.borderWidth
                                    color: Colors.of(QsWindow.window).alpha(btn.warn, 0.7)
                                }
                            }

                            Item {
                                id: iconBox
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    // Asking, the glyph becomes a check: the question is in the
                                    // caption, but the button itself must read as "press again".
                                    name: btn._name
                                    glyph: btn.action.glyph
                                    variant: "title"
                                    sizeScale: 2.0
                                    fill: btn.asking || btn.hot ? 1 : 0
                                    color: btn.asking ? btn.warn
                                         : btn.hot ? Colors.of(QsWindow.window).focus
                                         :           Colors.of(QsWindow.window).fg
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                    Behavior on fill  { NumberAnimation { duration: Motion.respond } }
                                }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: { dock.byMouse = true; dock.cursor = btn.index }
                            onClicked: dock.press(btn.action)
                        }
                    }
                }
            }

            // ── The highlight: ONE, travelling ─────────────────────────────────
            // Over the buttons, on the pointed-at one. Two edges, one target, two speeds
            // (WorkspacesPill's indicator): the leading one arrives in `standard`, the trailing
            // one in `trail`, so it stretches across the gap and contracts onto the next button.
            // Both come from the same expression and `y`/`height` just track them, so a reversal
            // can't cross the edges. It does not slide in from wherever it last was: its edges
            // only animate once it is showing.
            Rectangle {
                id: hl
                readonly property var target: rep.itemAt(dock.cursor)
                readonly property bool armed: dock.armedKey !== "" && dock.cursor >= 0
                                              && PowerJs.ACTIONS[dock.cursor].key === dock.armedKey
                readonly property color tone: dock.cursor >= 0 && PowerJs.ACTIONS[dock.cursor].tone
                    ? Colors.of(QsWindow.window)[PowerJs.ACTIONS[dock.cursor].tone] : Colors.of(QsWindow.window).focus

                // The button's top in this item's coordinates; held where it was while nothing is
                // pointed at, so it fades out in place.
                property real at: 0
                Binding on at {
                    when: hl.target !== null && hl.target !== undefined
                    value: col.y + (hl.target ? hl.target.y : 0)
                    restoreMode: Binding.RestoreNone
                }
                property real leadPos:  hl.at
                property real trailPos: hl.at
                Behavior on leadPos  { enabled: hl.opacity > 0.05; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on trailPos { enabled: hl.opacity > 0.05; NumberAnimation { duration: Motion.trail;    easing.type: Motion.travel } }

                x: col.x
                y: Math.min(hl.leadPos, hl.trailPos)
                width:  dock.button
                height: Math.abs(hl.leadPos - hl.trailPos) + dock.button
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).alpha(hl.armed ? hl.tone : Colors.of(QsWindow.window).focus,
                                                        hl.armed ? 0.10 : 0.20)
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(hl.armed ? hl.tone : Colors.of(QsWindow.window).focus, 0.6)
                Behavior on color        { ColorAnimation { duration: Motion.respond } }
                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                opacity: dock.cursor >= 0 && dock.wanted && hl.target ? 1 : 0
                visible: hl.opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                // Dips with the button under it.
                scale: hl.target && hl.target.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
            }

            // Leaving the column clears a POINTER selection (the tooltip goes with it); the gaps
            // between buttons are inside this item, so crossing one keeps the highlight alive
            // and travelling. A key's selection stays.
            HoverHandler {
                onHoveredChanged: if (!hovered && dock.byMouse) dock.cursor = -1
            }
        }
    }

    // ══ The tooltip ═══════════════════════════════════════════════════════════
    // Beside the selected button, on its LEFT — outside the card, which clips. A panel-style
    // card (radiusCard, the Card's own `surface` fill): the action's name and what it does; armed, the name
    // becomes the question in the warning tone, says to press again, and lists what it would
    // cut off. Display only: it is not in the mask. It eases out from under the column, GLIDES
    // from button to button on the highlight's lead edge (the two travel as one) and swaps its
    // words through a quick fade, so the text never changes under a box that hasn't moved yet.
    // Hidden, it takes the new words at once — there is nothing to fade.
    property int capShown: -1
    onHeldCursorChanged: if (cap.capK < 0.05) dock.capShown = dock.heldCursor

    readonly property var capAction: dock.capShown >= 0 ? PowerJs.ACTIONS[dock.capShown] : null
    readonly property bool capArmed: dock.capAction !== null && dock.armedKey === dock.capAction.key
    readonly property color capTone: dock.capAction && dock.capAction.tone
        ? Colors.of(QsWindow.window)[dock.capAction.tone] : Colors.of(QsWindow.window).focus
    readonly property real capY: {
        const it = rep.itemAt(dock.heldCursor)
        return it ? card.y + col.y + it.y + it.height / 2 : 0
    }

    Rectangle {
        id: cap
        readonly property bool show: dock.wanted && dock.cursor >= 0 && dock.grow > 0.7
        property real capK: cap.show ? 1 : 0
        Behavior on capK { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        visible: cap.capK > 0.01
        opacity: Math.min(1, cap.capK)
        scale:   0.94 + 0.06 * cap.capK
        transformOrigin: Item.Right

        // A floor, so the box doesn't change width on every button — only for a longer line.
        width:  Math.max(capCol.implicitWidth, Tokens.spacingXl * 6) + Tokens.spacingXl * 2
        height: capCol.implicitHeight + Tokens.spacingLg * 2
        Behavior on width  { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        // The slide-in comes from the button's side (it eases out from under the card).
        x: card.x - cap.width - Tokens.spacingLg + (1 - cap.capK) * Tokens.spacingXl
        y: dock.capY - cap.height / 2
        // Glides between buttons — but not on its first appearance, or it would fly in from the top.
        Behavior on y { enabled: cap.capK > 0.9; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        radius: Tokens.radiusCard
        color:  Colors.of(QsWindow.window).surface
        border.width: Tokens.borderWidth
        border.color: dock.capArmed ? Colors.of(QsWindow.window).alpha(dock.capTone, 0.7) : Colors.of(QsWindow.window).outline
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        SwapFade {
            target: capCol
            key: dock.heldCursor
            shownKey: dock.capShown
            onSwapped: dock.capShown = dock.heldCursor
        }

        Column {
            id: capCol
            x: Tokens.spacingXl
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacingXs

            StyledText {
                text: dock.capAction ? (dock.capArmed ? dock.capAction.ask : dock.capAction.label) : ""
                variant: "label"
                font.weight: Font.DemiBold
                color: dock.capArmed ? dock.capTone : Colors.of(QsWindow.window).fg
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            StyledText {
                text: dock.capAction ? dock.capAction.hint : ""
                variant: "caption"
                emphasis: "dim"
            }
            // Only while it asks.
            StyledText {
                visible: dock.capArmed
                text: Translation.tr("Press again to confirm")
                variant: "caption"
                color: dock.capTone
            }
            // What this would cut off — only while it asks, and only for what ends the session.
            StyledText {
                visible: dock.capArmed && dock.capAction.ends === true && Session.interruptText !== ""
                text: Session.interruptText
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
                width: Math.min(implicitWidth, Tokens.spacingXl * 14)
            }
        }
    }
}
