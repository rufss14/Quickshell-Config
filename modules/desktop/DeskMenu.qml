import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../state"
import "../../services/deskmenu.js" as Menus

// ── DeskMenu ──────────────────────────────────────────────────────────────────
// The desktop menu: right-click the empty desktop (DeskMenuCatcher) and a drop of the bar's own
// material swells out of the pointer into a Windows-style list (DeskMenuBody). Also by key, in the
// middle of the focused screen:
//     qs ipc -c ~/.config/quicktest call deskmenu toggle
//
// One window per screen, mapped only while it is open (and fading). It is full-screen so a click
// anywhere else closes it, and it holds the keyboard exclusively while open, for Escape; the grab
// is dropped the moment it closes. The blob opens with its corner at the pointer, on the other
// side of it where it would run off the screen (services/deskmenu.js `place`). Content sits behind
// a Loader, so a closed menu costs nothing.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    required property var modelData
    screen: win.modelData

    readonly property string screenName: win.modelData?.name ?? ""

    // The screen that was clicked, else (a key) the focused one.
    ScreenOwner {
        id: owner
        screen: win.modelData
        open: UiState.deskMenuOpen
    }
    readonly property bool mine: UiState.deskMenuScreen !== "" ? UiState.deskMenuScreen === win.screenName : owner.owns
    readonly property bool open: UiState.deskMenuOpen && win.mine

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-deskmenu"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: win.open || stage.g > 0.001

    // Switched off in Settings while it is open: it goes.
    Connections {
        target: Config
        function onDeskMenuChanged() { if (!Config.deskMenu) UiState.deskMenuOpen = false }
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: win.open

        readonly property var pal: Colors.of(QsWindow.window)

        // ── The opening ───────────────────────────────────────────────────────
        // A drop of the bar's own material that swells out of the pointer: it starts as a small round
        // blob and fills out to the card. Two critically damped springs in a chain (the box follows a
        // point that travels on the first), so it starts soft and settles without a wobble, as the
        // islands do (IslandDock.followSpec). Its width leads its height, so it stretches out sideways
        // before it drops. Contents come in once the box is a quarter open and leave before it shrinks.
        SpringValue {
            id: reveal
            spec: win.open ? ({ stiffness: 800, damping: 1.0 }) : ({ stiffness: 1300, damping: 1.0 })
            epsilon: 0.0005
            target: win.open ? 1 : 0
        }
        SpringValue {
            id: follow
            spec: win.open ? ({ stiffness: 1800, damping: 1.0 }) : ({ stiffness: 2800, damping: 1.0 })
            epsilon: 0.0005
            target: reveal.value
        }
        SpringValue {
            id: fade
            spec: win.open ? Motion.springEffects : Motion.springEffectsFast
            epsilon: 0.002
            target: win.open && follow.value > 0.25 ? 1 : 0
        }
        readonly property real g: Math.max(0, Math.min(1, follow.value))
        readonly property real seed: Tokens.iconXl + Tokens.spacingLg
        readonly property real fullW: body.implicitWidth
        readonly property real fullH: body.implicitHeight
        readonly property real boxW: stage.seed + (stage.fullW - stage.seed) * Math.min(1, stage.g * 1.35)
        readonly property real boxH: stage.seed + (stage.fullH - stage.seed) * stage.g

        Keys.onEscapePressed: UiState.deskMenuOpen = false

        // A click anywhere else closes it; a right-click moves it to the pointer instead.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) UiState.openDeskMenu(win.screenName, mouse.x, mouse.y)
                else UiState.deskMenuOpen = false
            }
        }

        readonly property real margin: Tokens.spacingLg
        // Where the FULL card sits; the blob grows inside that box from the pointer's corner.
        readonly property var spot: Menus.place(UiState.deskMenuX, UiState.deskMenuY, stage.fullW, stage.fullH,
                                                win.width, win.height, stage.margin)
        readonly property bool byKey: UiState.deskMenuX < 0

        SurfaceShadow { surface: card }
        Surface {
            id: card

            // Grows from its pointer corner, or from its middle when a key opened it.
            x: stage.byKey ? stage.spot.x + (stage.fullW - width) / 2
                           : stage.spot.flipX ? stage.spot.x + stage.fullW - width : stage.spot.x
            y: stage.byKey ? stage.spot.y + (stage.fullH - height) / 2
                           : stage.spot.flipY ? stage.spot.y + stage.fullH - height : stage.spot.y
            width: stage.boxW
            height: stage.boxH

            // The bar's and the frame's own fill, edge and corners.
            elevation: Tokens.elevationPopup
            color: stage.pal.frameFill
            gradient: true
            gradientGround: stage.pal.frameFill
            borderColor: stage.pal.frameLine
            borderWidth: Tokens.borderChrome
            cornerRadius: Math.min(Tokens.radiusCard, Math.min(width, height) / 2)
            opacity: Math.min(1, stage.g * 8)

            // Presses on the card are the card's, not a click-away.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            // Contents are cropped to the box's own corners while it is still growing.
            ClippingRectangle {
                anchors.fill: parent
                radius: card.radius
                color: "transparent"

                Loader {
                    id: body
                    x: stage.spot.flipX && !stage.byKey ? parent.width - width : 0
                    y: stage.spot.flipY && !stage.byKey ? parent.height - height : 0
                    active: win.visible
                    opacity: fade.value
                    sourceComponent: DeskMenuBody {
                        reveal: fade.value
                        onCloseRequested: UiState.deskMenuOpen = false
                    }
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
