import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── HotCorner ─────────────────────────────────────────────────────────────────
// Rest the pointer in the chosen screen corner (Config.hotCorner, Config.hotCornerEdge) and a
// panel slides out of it (HotCornerPanel); leave it and the panel goes. Also summoned by key:
//     qs ipc -c ~/.config/quicktest call hotcorner toggle
//
// Two windows per screen:
//   - the trigger: a few pixels in the corner, mapped only while the corner is on. It takes
//     the pointer there and nothing else of the screen.
//   - the panel: mapped only while open (and while it fades), content behind a Loader so a
//     closed one costs nothing.
//
// The pointer is not in the corner while the panel is open (the panel's window is over it), so
// "the pointer is here" is the trigger's hover OR the panel window's hover; the window includes
// the gap round the card, so crossing the gap does not close it. Nothing opens while a
// fullscreen window is on that screen: a corner touched in a game is not a request.
//
// Opened by key there is no pointer in the corner yet, so closing waits until it has been
// there once (or `grace` has passed).
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: scope

    required property var modelData

    readonly property string screenName: scope.modelData?.name ?? ""
    readonly property bool atTop:  Config.hotCornerEdge.startsWith("top")
    readonly property bool atLeft: Config.hotCornerEdge.endsWith("Left")

    // The screen it opens on: the one whose corner was touched, else (a key) the focused one.
    ScreenOwner {
        id: owner
        screen: scope.modelData
        open: UiState.hotCornerOpen
    }
    readonly property bool mine: UiState.hotCornerScreen !== "" ? UiState.hotCornerScreen === scope.screenName : owner.owns
    readonly property bool open: UiState.hotCornerOpen && scope.mine

    // The pointer has been in the corner or the panel since it opened.
    property bool armed: false
    // Closed by an action with the pointer still in the corner: it must leave before the corner opens again.
    property bool held: false

    readonly property bool inside: panelHover.hovered || trigHover.hovered
    onInsideChanged: if (scope.inside && scope.open) scope.armed = true
    onOpenChanged: {
        if (scope.open) {
            scope.armed = !UiState.hotCornerByKey
            if (!scope.armed) grace.restart()
        } else {
            grace.stop()
        }
    }

    function close(byAction) {
        UiState.hotCornerPinned = false
        UiState.hotCornerOpen = false
        if (byAction === true) { scope.held = true; heldClear.restart() }
    }

    Timer { id: grace; interval: 3000; onTriggered: scope.armed = true }
    Timer {
        id: leave
        interval: Config.hotCornerLinger
        running: scope.open && scope.armed && !scope.inside && !UiState.hotCornerPinned
        onTriggered: scope.close(false)
    }
    // A corner that is still held a moment after closing, with the pointer gone from it, is free.
    Timer { id: heldClear; interval: 900; onTriggered: if (!trigHover.hovered) scope.held = false }

    // ── The trigger ───────────────────────────────────────────────────────────
    PanelWindow {
        id: trigger
        screen: scope.modelData

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-hotcorner-trigger"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusiveZone: -1

        anchors.top: scope.atTop
        anchors.bottom: !scope.atTop
        anchors.left: scope.atLeft
        anchors.right: !scope.atLeft
        implicitWidth: Tokens.spacingSm
        implicitHeight: Tokens.spacingSm
        color: "transparent"
        // Unmapped under a fullscreen window: an Overlay surface sits above a game and
        // steals the corner pixels from it (the cursor can't reach the game's corner).
        visible: Config.hotCorner && !Fullscreen.activeOn(scope.screenName)

        Item {
            anchors.fill: parent
            HoverHandler { id: trigHover }
        }

        Timer {
            interval: Config.hotCornerDelay
            running: trigHover.hovered && !scope.held && !UiState.hotCornerOpen && !Fullscreen.activeOn(scope.screenName)
            onTriggered: {
                UiState.hotCornerScreen = scope.screenName
                UiState.hotCornerByKey = false
                UiState.hotCornerOpen = true
            }
        }
        Connections {
            target: trigHover
            function onHoveredChanged() { if (!trigHover.hovered) scope.held = false }
        }
    }

    // ── The panel ─────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        screen: scope.modelData

        // The room a shadow needs, all round the card; it is also the gap to the screen's edge.
        readonly property int gap: Math.max(Tokens.spacingLg, Tokens.shadowRoom(Tokens.elevationPopup))

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-hotcorner"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusiveZone: -1

        anchors.top: scope.atTop
        anchors.bottom: !scope.atTop
        anchors.left: scope.atLeft
        anchors.right: !scope.atLeft
        // Under the bar, not over it.
        margins.top: scope.atTop ? Config.barExtent : 0

        implicitWidth: card.width + win.gap * 2
        implicitHeight: card.height + win.gap * 2
        color: "transparent"
        visible: scope.open || stage.t > 0.001

        Item {
            id: stage
            anchors.fill: parent

            // 0 closed, 1 open: the panel's size, slide and fade ride this one number.
            property real t: scope.open ? 1 : 0
            Behavior on t {
                NumberAnimation {
                    duration: Motion.surfaceDuration(scope.open)
                    easing.type: Motion.surfaceEasing(scope.open)
                }
            }

            HoverHandler { id: panelHover }

            Surface {
                id: card
                anchors.top: scope.atTop ? parent.top : undefined
                anchors.bottom: scope.atTop ? undefined : parent.bottom
                anchors.left: scope.atLeft ? parent.left : undefined
                anchors.right: scope.atLeft ? undefined : parent.right
                anchors.margins: win.gap

                width: Math.round(body.implicitWidth * Config.hotCornerScale)
                height: Math.round(body.implicitHeight * Config.hotCornerScale)
                // Not clipping: Surface draws its own shadow, which a clip would cut off, and the panel's
                // parts stay inside it as they arrive.
                elevation: Tokens.elevationPopup

                opacity: stage.t * Tokens.surfaceOpacity
                scale: 0.94 + 0.06 * stage.t
                transformOrigin: scope.atTop
                    ? (scope.atLeft ? Item.TopLeft : Item.TopRight)
                    : (scope.atLeft ? Item.BottomLeft : Item.BottomRight)
                transform: Translate {
                    x: (scope.atLeft ? -1 : 1) * (1 - stage.t) * Tokens.spacingXxl
                    y: (scope.atTop ? -1 : 1) * (1 - stage.t) * Tokens.spacingXxl
                }

                // The panel is built at its own size and scaled whole (text, icons, spacing together), from
                // the card's top-left; the card above is sized to the scaled result.
                Loader {
                    id: body
                    width: body.implicitWidth
                    height: body.implicitHeight
                    scale: Config.hotCornerScale
                    transformOrigin: Item.TopLeft
                    active: win.visible
                    sourceComponent: HotCornerPanel {
                        reveal: stage.t
                        onCloseRequested: scope.close(true)
                    }
                }
            }
        }

        // The wave: a shell window that's up during a theme change takes it on the front.
        Infection {
            host: win.contentItem
            screen: win.screen
            hostVisible: win.visible
        }
    }
}
