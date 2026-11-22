import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── InspectorActions ──────────────────────────────────────────────────────────
// What you can do to the window(s) the island holds, in one place: the state switches (float, pin and,
// for a single window, fullscreen) in a ChipTray and the close button that asks twice. WindowInspector and
// BulkInspector both wear it, so the two faces are one design; each decides what a click DOES
// (`floatToggled` …) and what is lit. `many` only changes the words of the tips.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property bool floating: false
    property bool pinned: false
    property bool fullscreen: false
    // Fullscreen is for one window; a selection has no such switch.
    property bool showFullscreen: true
    // The close button has been pressed once and is waiting for the second press.
    property bool closeArmed: false
    property bool many: false
    property color accent: Colors.of(QsWindow.window).primary

    signal floatToggled()
    signal pinToggled()
    signal fullscreenToggled()
    signal closeAsked()

    spacing: Tokens.spacingLg

    ChipTray {
        Layout.alignment: Qt.AlignVCenter
        border.width: 0
        color: Colors.of(QsWindow.window).surfaceHigh
        ChipButton {
            symbol: "open_with"
            on: root.floating
            tint: root.accent
            onActivated: root.floatToggled()
            HoverTip {
                text: root.many ? Translation.tr("Float: let them move and resize freely (Ctrl+F)")
                                : Translation.tr("Float: let it move and resize freely (Ctrl+F)")
            }
        }
        ChipButton {
            symbol: "keep"
            on: root.pinned
            tint: root.accent
            onActivated: root.pinToggled()
            HoverTip {
                text: root.many ? Translation.tr("Pin: keep them on screen on every workspace (Ctrl+P)")
                                : Translation.tr("Pin: keep it on screen on every workspace (Ctrl+P)")
            }
        }
        ChipButton {
            visible: root.showFullscreen
            symbol: "fullscreen"
            on: root.fullscreen
            tint: root.accent
            onActivated: root.fullscreenToggled()
            HoverTip { text: Translation.tr("Fullscreen (Ctrl+Enter)") }
        }
    }

    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 44
        implicitHeight: 44
        name: root.closeArmed ? "delete" : "close"
        tint: Colors.of(QsWindow.window).danger
        primary: root.closeArmed
        points: 6
        onActivated: root.closeAsked()
        HoverTip {
            text: root.many ? Translation.tr("Close them all: click twice to confirm (Ctrl+W)")
                            : Translation.tr("Close it: click twice to confirm (Ctrl+W)")
        }
    }
}
