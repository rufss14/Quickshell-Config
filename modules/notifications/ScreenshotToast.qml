pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ScreenshotToast ───────────────────────────────────────────────────────────
// The moment after the shutter: here is the picture, here is what you can do with it.
//
// ── Why this is not an ordinary notification ──────────────────────────────────
// It replaces one. Screenshot tools already send "Screenshot saved" through the shell's
// own daemon, and that toast tells you something you knew a quarter of a second ago
// while giving you nothing to act on — so the usual next step is to go and find the
// file. Screenshot.consume() takes that notification over and this stands in for it,
// with the actual image and the four things anyone does next.
//
// It is deliberately a separate surface rather than a notification with actions:
// notification actions belong to the SENDING app (they are invoked back over D-Bus),
// and every one of these is something the shell does itself.
//
// ── Bottom-right, no backdrop ─────────────────────────────────────────────────
// It appears while you are still looking at whatever you screenshotted, so it must not
// cover or dim that.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not
    // redeclared (a `required property var screen` shadowed it; see ScreenOwner).

    WlrLayershell.layer:     WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot"
    // Never takes keyboard focus: it appears unprompted, and a surface that steals the
    // keyboard the instant you press a screenshot key would eat the next thing you type.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    // One screen shows it — the focused one, falling back to the first.
    // The monitor you were on when it opened — see ScreenOwner.
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: Screenshot.pending
    }

    readonly property bool shown: Screenshot.pending && win.owns

    // ── The shown path OUTLIVES the dismiss ───────────────────────────────────
    // Bound straight to Screenshot.latest, the thumbnail blanked the instant the toast
    // was dismissed and then spent the whole fade-out as an empty box — which reads as
    // "the picture sometimes doesn't appear". The card has to keep showing what it was
    // showing until it has finished leaving.
    //
    // Exactly the trap UpdatesPage documents about its log pane: the fade has to outlive
    // the data, so this is a plain property updated on capture, not a binding.
    property string held: ""

    anchors.bottom: true
    anchors.right:  true
    // Pulled back by exactly the bleed the window grew, so the card does not move.
    margins.bottom: Tokens.spacingXl - win.room
    margins.right:  Tokens.spacingXl - win.room

    // ── Bigger than the card, purely so the shadow has somewhere to land ──────
    // Paint stops at a Wayland surface edge. This window used to be exactly 360×132,
    // the card's own size, so the card's shadow was clipped flat on all four sides.
    // The surplus is transparent and excluded from input by the mask below.
    readonly property int room: Tokens.shadowRoom(Tokens.elevationCard)

    implicitWidth:  360 + win.room * 2
    implicitHeight: 132 + win.room * 2

    color: "transparent"
    visible: win.shown || card.opacity > 0.005

    // Not optional, for the same reason as the OSD's: a layer surface with no input
    // region takes the pointer over its whole surface, so the halo this window just
    // grew would start swallowing clicks in the corner of the screen.
    mask: Region { item: card }

    // ── Auto-dismiss ──────────────────────────────────────────────────────────
    // Restarted from captureId rather than from the path: taking a second shot, or
    // writing an edit back over the same file, must re-arm the timer even when the path
    // is unchanged.
    Connections {
        target: Screenshot
        function onCaptureIdChanged() {
            if (Screenshot.latest !== "") win.held = Screenshot.latest
            if (Config.screenshotToastMs > 0) life.restart()
        }
    }

    Timer {
        id: life
        interval: Math.max(1000, Config.screenshotToastMs)
        repeat: false
        onTriggered: Screenshot.dismiss()
    }

    // Hovering holds it: reaching for a button must not be a race against the timer.
    onShownChanged: if (!win.shown) life.stop()

    // The card clips (for the thumbnail), which would clip away the shadow Surface
    // normally draws as its own child — so it is a sibling here. See SurfaceShadow.
    SurfaceShadow { surface: card }

    Surface {
        id: card
        anchors.fill: parent
        anchors.margins: win.room
        elevation: Tokens.elevationCard
        clip: true

        opacity: win.shown ? Tokens.surfaceOpacity : 0.0
        scale:   win.shown ? 1.0 : 0.97
        transformOrigin: Item.BottomRight

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.shown)
                easing.type: Motion.surfaceEasing(win.shown)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.shown)
                easing.type: Motion.surfaceEasing(win.shown)
            }
        }

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (cardHover.hovered) life.stop()
                else if (win.shown && Config.screenshotToastMs > 0) life.restart()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            // ── The shot itself ───────────────────────────────────────────────
            // The whole point: seeing WHICH screenshot this is. A filename would not
            // tell you — they are all timestamps.
            ClippingRectangle {
                Layout.preferredWidth:  148
                Layout.preferredHeight: 108
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

                Image {
                    id: shot
                    anchors.fill: parent
                    // Screenshots are full-resolution; decoding a 4K PNG at full size to
                    // draw it 148px wide is the kind of per-frame waste this shell
                    // avoids. Width only, so the aspect is preserved (see the note on
                    // NotificationToast's preview).
                    sourceSize.width: 320
                    source: win.held !== "" ? "file://" + win.held : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: shot.status !== Image.Ready
                    glyph: "󰋩"
                    variant: "body"
                    color: Colors.of(QsWindow.window).fgDim
                }

                // ── Clicking the picture EDITS it ─────────────────────────
                // This used to call xdg-open, and on this machine the default handler
                // for image/png is firefox.desktop — so a click handed the screenshot to
                // a browser, which either took seconds or opened a background tab. That
                // is indistinguishable from the click doing nothing.
                //
                // The editor is the shell's own surface and opens instantly, and
                // "clicking the picture" is the gesture people try before reading any
                // buttons — so it should be the useful one.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        UiState.openAnnotate(win.held)
                        Screenshot.dismiss()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingXs

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Screenshot")
                    variant: "label"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: win.held.split("/").pop()
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideMiddle
                }

                Item { Layout.fillHeight: true }

                // ── The four things anyone does next ──────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs

                    PanelButton {
                        variant: "primary"
                        glyph: "󰆏"
                        label: Translation.tr("Copy")
                        onActivated: {
                            Screenshot.copyToClipboard(win.held)
                            Screenshot.dismiss()
                        }
                    }

                    PanelButton {
                        variant: "ghost"
                        glyph: "󰏫"
                        label: Translation.tr("Edit")
                        onActivated: {
                            UiState.openAnnotate(win.held)
                            Screenshot.dismiss()
                        }
                    }

                    // To a phone over Bluetooth: stages the file and opens the
                    // Bluetooth panel to pick a device. With bluez-obex missing the
                    // panel's send card says so — the click never fails silently.
                    PanelButton {
                        visible: Bt.available
                        variant: "ghost"
                        glyph: "󰂯"
                        label: Translation.tr("Send")
                        onActivated: {
                            BtBridge.stage(win.held)
                            Screenshot.dismiss()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Trash, not unlink — see Screenshot.remove().
                    PanelButton {
                        variant: "ghost"
                        glyph: "󰩺"
                        onActivated: Screenshot.remove(win.held)
                    }

                    PanelButton {
                        variant: "ghost"
                        glyph: "󰅖"
                        onActivated: Screenshot.dismiss()
                    }
                }
            }
        }
    }
}
