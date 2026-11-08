import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../services/polkit.js" as P

// ── PolkitPopup ───────────────────────────────────────────────────────────────
// The password dialog for pkexec and friends, drawn by the shell (services/AuthAgent
// owns the protocol). One screen shows it — the monitor you were on when the request
// arrived (ScreenOwner) — over a dimmed backdrop.
//
// ── Modal on purpose ──────────────────────────────────────────────────────────
// Exclusive keyboard focus for as long as a request is open: it is raised by a
// process, not by a click into this surface, so OnDemand would leave the field deaf.
// The backdrop does NOT dismiss on a click — an authentication request is something
// you answer or cancel with Cancel/Escape, and one stray click on the desktop
// shouldn't deny it. It ends when the request does (cancelled by the app, or answered).
//
// ── Its own copy of what it shows ─────────────────────────────────────────────
// `AuthAgent.flow` is null the instant a request ends, so everything on the card is
// read into `held*` while it exists and never cleared: the fade-out is spent showing
// what was asked, not an empty box. That includes `heldSecret` — if the "hide what is
// typed" flag followed the flow to null, a password would be drawn in plain text for
// the length of the fade. The field is also emptied the moment the answer is sent.
//
// ── Where the words come from ─────────────────────────────────────────────────
// Other processes. Everything goes through polkit.js and is rendered as plain text
// (StyledText, never `rich`), and the action id is shown beside the message so two
// requests with a similar message can be told apart.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not redeclared.

    WlrLayershell.layer:         WlrLayer.Overlay
    // Its own namespace: two layer surfaces sharing one fight over keyboard focus.
    WlrLayershell.namespace:     "quickshell-polkit"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.owns && AuthAgent.active
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: AuthAgent.active
    }

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true

    color: "transparent"
    // Mapped while open and while the card is still fading out.
    visible: win.owns && (AuthAgent.active || card.opacity > 0.01)

    // ── What the card shows ───────────────────────────────────────────────────
    property string heldMessage: ""
    property string heldAction:  ""
    property string heldPrompt:  "Password"
    property string heldNote:    ""
    property bool   heldNoteIsError: false
    property bool   heldSecret:  true
    property bool   heldAsking:  false

    function _take() {
        const f = AuthAgent.flow
        if (!f) return
        win.heldSecret = !f.responseVisible
        win.heldMessage = P.message(f.message)
        win.heldAction  = P.actionId(f.actionId)
        win.heldPrompt  = P.prompt(f.inputPrompt, win.heldSecret)
        win.heldNote    = P.message(f.supplementaryMessage)
        win.heldNoteIsError = f.supplementaryIsError
        win.heldAsking  = f.isResponseRequired
    }

    Connections {
        target: AuthAgent
        function onFlowChanged() {
            if (!AuthAgent.flow) return
            field.clear()
            win._take()
            // The target below switches to this flow only now, so a prompt that was
            // already waiting never fires isResponseRequiredChanged for it.
            if (AuthAgent.flow.isResponseRequired) Qt.callLater(function () { field.forceFocus() })
        }
    }

    Connections {
        target: AuthAgent.flow
        function onInputPromptChanged()            { win._take() }
        function onResponseVisibleChanged()        { win._take() }
        function onSupplementaryMessageChanged()   { win._take() }
        function onSupplementaryIsErrorChanged()   { win._take() }
        function onIsResponseRequiredChanged() {
            win._take()
            // The conversation is asking again (first prompt, or after a wrong password):
            // the box is ready, so it takes focus.
            if (AuthAgent.flow && AuthAgent.flow.isResponseRequired) {
                Qt.callLater(function () { field.forceFocus() })
            }
        }
        function onAuthenticationFailed() {
            field.clear()
            shake.restart()
        }
    }

    function _send() {
        if (!win.heldAsking) return
        const answer = field.text
        field.clear()               // gone from the box the moment it's sent
        AuthAgent.submit(answer)
    }

    // ── Backdrop ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.62)
        opacity: AuthAgent.active ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(AuthAgent.active)
                easing.type: Motion.surfaceEasing(AuthAgent.active)
            }
        }
    }

    SurfaceShadow { surface: card }
    Surface {
        id: card
        anchors.centerIn: parent

        width: Math.min(420, win.width - Tokens.spacingXxl * 2)
        implicitHeight: content.implicitHeight + Tokens.spacingXl * 2
        height: implicitHeight

        elevation: Tokens.elevationPopup
        focused: field.editing

        opacity: AuthAgent.active ? Tokens.surfaceOpacity : 0.0
        scale:   AuthAgent.active ? 1.0 : 0.97
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(AuthAgent.active)
                easing.type: Motion.surfaceEasing(AuthAgent.active)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(AuthAgent.active)
                easing.type: Motion.surfaceEasing(AuthAgent.active)
            }
        }

        // A wrong password shakes the card, the way the lock screen's field does.
        transform: Translate { id: shiftT }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shiftT; property: "x"; to: -Tokens.spacingLg; duration: Motion.respond }
            NumberAnimation { target: shiftT; property: "x"; to:  Tokens.spacingLg; duration: Motion.respond }
            NumberAnimation { target: shiftT; property: "x"; to: -Tokens.spacingMd; duration: Motion.respond }
            NumberAnimation { target: shiftT; property: "x"; to:  0;                duration: Motion.respond }
        }

        // Escape cancels. On an Item inside the surface — PanelWindow can't take Keys.
        // It bubbles up from the TextInput, which doesn't consume it.
        Keys.onEscapePressed: AuthAgent.cancel()

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Tokens.spacingXl
            spacing: Tokens.spacingLg

            PanelHeader {
                Layout.fillHeight: false
                symbol:    "security"
                title:     Translation.tr("Authentication")
                titleTail: Translation.tr("required")
                subtitle:  win.heldAction
                accent:    Colors.of(QsWindow.window).primary
            }

            StyledText {
                Layout.fillWidth: true
                visible: win.heldMessage !== ""
                text: win.heldMessage
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            InputField {
                id: field
                Layout.fillWidth: true
                secret: win.heldSecret
                icon: "key"
                placeholder: win.heldPrompt
                enabled: win.heldAsking
                opacity: win.heldAsking ? 1.0 : 0.5
                onAccepted: win._send()
            }

            // The conversation's own words ("Sorry, try again."), or a hint. Space is
            // held either way so the card doesn't jump when an error appears.
            StyledText {
                Layout.fillWidth: true
                text: win.heldNote
                variant: "caption"
                color: win.heldNoteIsError ? Colors.of(QsWindow.window).danger
                                           : Colors.of(QsWindow.window).fgDim
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: win.heldNote !== ""
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                Item { Layout.fillWidth: true }
                PanelButton {
                    label: Translation.tr("Cancel")
                    onActivated: AuthAgent.cancel()
                }
                PanelButton {
                    label: Translation.tr("Authenticate")
                    variant: "primary"
                    enabled: win.heldAsking
                    onActivated: win._send()
                }
            }
        }
    }
}
