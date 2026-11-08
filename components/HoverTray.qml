import QtQuick
import Quickshell
import "../config"

// ── HoverTray ─────────────────────────────────────────────────────────────────
// A ChipTray that springs in when `shown` (a row's hover), instead of sitting there: the
// colours panel's preset cards, and now the clock panel's reminders and agenda. Put the
// ChipButtons inside it, as in a ChipTray:
//
//     HoverTray {
//         shown: rowHover.hovered
//         ChipButton { symbol: "snooze"; onActivated: … }
//     }
//
// It leaves from its right edge (`transformOrigin`), a little small and see-through, and
// settles on a spring. `pop` is exposed so the row can slide its own content over by the same
// amount (a Behavior cannot sit on `anchors.*`, so the row binds to a number, as the presets do):
// `width * pop` is how much room the tray has taken.
//
// `hovered` is the tray's OWN hover — a row whose body is tappable asks it so a tap on a chip
// is not also a tap on the row (TapHandlers don't stop one another).
//
// Invisible, and so not hit-testable, at rest. Motion off: Config.motionEnabled turns the
// spring into a cut, as every Behavior here does.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false
    default property alias chips: tray.items

    readonly property alias hovered: hover.hovered
    readonly property real pop: root._pop

    // Implicit as well as actual, so a layout (a card's header row) sizes it too.
    implicitWidth:  tray.implicitWidth
    implicitHeight: tray.implicitHeight
    width:  tray.implicitWidth
    height: tray.implicitHeight
    transformOrigin: Item.Right

    property real _pop: root.shown ? 1 : 0
    Behavior on _pop {
        enabled: Config.motionEnabled
        SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.005 }
    }

    opacity: Math.min(1, root._pop * 1.5)
    scale:   0.7 + 0.3 * root._pop
    visible: root.opacity > 0.01

    HoverHandler {
        id: hover
    }
    ChipTray {
        id: tray
    }
}
