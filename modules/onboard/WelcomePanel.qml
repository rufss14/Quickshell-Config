import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── WelcomePanel ──────────────────────────────────────────────────────────────
// The first-run window, and the way back to setup later. It is only the frame — modal backdrop, card,
// header, Escape — around SetupWizard: the setup plan, paged (Welcome … Colours, then a Review page with
// the one button). Settings › Setup embeds the same plan as one checklist (SetupFlow).
//
//   shell.qml shows it on a fresh profile, or whenever the core packages aren't in yet
//   (Config.setupSeen || !Setup.coreReady). Dismissing persists setupSeen.
//   Re-open:  qs ipc -c ~/.config/quicktest call welcome toggle
//
// It was a seven-page wizard with a password box in its chrome and a job switch of its own; the pages
// stayed (the layout is liked), the machinery moved — the runner and the job ids into Setup, the
// rows/password/run into shared components. Pages only choose; the last one installs, once.
//
// The card grows and shrinks with the stage (Behavior on height) and caps at the screen; the checklist
// inside scrolls when the card can't fit it. The backdrop swallows clicks but does NOT dismiss: a stray
// click outside shouldn't throw away a half-finished setup. Leaving is Escape or the ✕, and neither works
// while a step is running.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not redeclared (see ScreenOwner).

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-welcome"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.showing ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    // The monitor you were on when it opened — see ScreenOwner.
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: UiState.welcomeOpen
    }
    readonly property bool showing: UiState.welcomeOpen && win.owns

    anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
    color: "transparent"
    visible: UiState.welcomeOpen && win.owns

    function dismiss() {
        if (Setup.planning) return
        Config.setupSeen = true
        UiState.welcomeOpen = false
    }

    // A fresh look every time it opens: re-probe, so the plan is for the machine as it is now.
    // Deferred: on a first run this panel opens FROM Setup's coreProbedChanged (shell.qml
    // _maybeShowFirstRun), and a synchronous recheck() resets _pkgProbed inside that very
    // notification — a binding loop on coreProbed, and the probe restarted at once.
    onShowingChanged: if (win.showing) Qt.callLater(Setup.recheck)

    // ── Backdrop ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.6)
        opacity: win.showing ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.showing)
                easing.type: Motion.surfaceEasing(win.showing)
            }
        }
        MouseArea { anchors.fill: parent }
    }

    SurfaceShadow { surface: card }
    Surface {
        id: card
        anchors.centerIn: parent
        width:  Math.min(640, win.width - Tokens.spacingXxl * 2)
        height: Math.min(win.height - Tokens.spacingXxl * 2,
                         content.implicitHeight + Tokens.spacingXl * 2)
        Behavior on height {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
        }
        elevation: Tokens.elevationCard
        clip: true

        opacity: win.showing ? Tokens.surfaceOpacity : 0.0
        scale:   win.showing ? 1.0 : 0.96
        transformOrigin: Item.Center
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.showing)
                easing.type: Motion.surfaceEasing(win.showing)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.showing)
                easing.type: Motion.surfaceEasing(win.showing)
            }
        }

        Keys.onEscapePressed: win.dismiss()
        focus: win.showing

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingXl
            spacing: Tokens.spacingLg

            PanelHeader {
                Layout.fillHeight: false
                icon:      Icons.logo("quickshell.svg")
                title:     Translation.tr("Quicktest")
                titleTail: Translation.tr("Setup")
                accent:    Colors.of(QsWindow.window).primary
                subtitle:  Config.setupSeen ? "Check what this machine has, and fix what's missing"
                                            : "Welcome — let's get your desktop ready"

                BusyDot {
                    Layout.alignment: Qt.AlignVCenter
                    running: Setup.busy
                    tint: Colors.of(QsWindow.window).primary
                }

                ActionGroup {
                    PanelButton {
                        variant: "ghost"
                        accent:  Colors.of(QsWindow.window).primary
                        symbol:  "close"
                        enabled: !Setup.planning
                        onActivated: win.dismiss()
                    }
                }
            }

            // Built only while the window is up (or fading out): a closed one costs nothing, and the
            // recap doesn't blank mid-fade because the Loader outlives `showing`.
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: false
                active: win.showing || card.opacity > 0.01
                sourceComponent: SetupWizard {
                    onCloseRequested: win.dismiss()
                }
            }
        }
    }
}
