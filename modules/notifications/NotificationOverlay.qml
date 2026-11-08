import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"

// ── NotificationOverlay ───────────────────────────────────────────────────────
// The toasts, stacked top-right on the focused monitor. One of these exists per
// screen; only the focused one draws, so a notification doesn't appear on every
// monitor at once. The window is click-through except where a toast actually is
// (`mask`), so the rest of that corner stays usable.
//
// ── The motion ─────────────────────────────────────────────────────────────────
// Each toast lives in a `cell` wrapper that owns three animations, because a
// Positioner (Column) can animate items ARRIVING and MOVING but not LEAVING:
//
//   enter   slide in from the right + fade, as the newest lands on top.
//   exit    the toast decides it's done (dwell expired, dismissed) → it slides
//           out and fades BEFORE telling the service to drop it, so it animates
//           away instead of blinking out. Only once that finishes does the model
//           lose the item.
//   reflow  `Behavior on y` — when a toast above is added or removed, this one's
//           slot in the Column changes, and it glides to the new position rather
//           than teleporting. A single discrete change, never a chase.
//
// Depth: the newest toast is front-and-centre; the ones behind recede in scale and
// opacity, so a stack reads as a deck rather than a wall. As the front one leaves,
// the next scales up into its place.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // `screen` is PanelWindow's own property, assigned by shell.qml — not
    // redeclared. A `required property var screen` here shadowed it, so the window
    // never learned its output and mapped wherever Hyprland put an unplaced surface
    // (the focused monitor — right by luck, since that's where this shows anyway).

    // Captured imperatively, not bound. This window's `visible` is derived from the
    // name (ownsToasts -> active -> visible), and `screen` re-emits screenChanged when
    // the backing window is created or destroyed — so a binding would close the cycle
    // CavaBG documents at length: visible -> map/unmap -> screenChanged -> visible. A
    // same-value write does not notify, which is what breaks it.
    property string monName: ""
    function _syncMonitor() { root.monName = Hyprland.monitorFor(root.screen)?.name ?? "" }
    onScreenChanged: root._syncMonitor()
    Component.onCompleted: root._syncMonitor()

    // The monitor the deck was delivered to — see Notifications.popupMonitor. It used
    // to follow the focused monitor, so a toast chased the pointer between screens.
    readonly property bool ours: Notifications.popupMonitor === root.monName

    // ── This host only draws while a fullscreen window covers THIS monitor ────
    // The bar is a Top-layer surface and Hyprland renders those below a fullscreen
    // window, so the welded stack inside it vanishes exactly when a game is up.
    // Overlay survives that.
    //
    // `Fullscreen.activeOn` and not a fullscreen check of our own: it is already
    // event-driven (no polling), already per-monitor and per-ACTIVE-WORKSPACE, and
    // already safe to call from a binding. A first attempt at this folded a flag
    // into Hypr.rebuild() instead, which was wrong twice — rebuild only runs while
    // something holds acquire(), and going fullscreen does not change the toplevel
    // list, so it never re-ran; and it counted a fullscreen window on an INACTIVE
    // workspace, which covers nothing.
    // The MAP, not activeOn() — the same choice CavaBG makes, for the same reason.
    readonly property bool ownsToasts:
        root.ours && Fullscreen.byMonitor[root.monName] === true

    // Only while THIS host owns the deck — see the NotificationStack below.
    readonly property bool active: root.ownsToasts && Notifications.popups.length > 0

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-notifications"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None   // toasts never grab the keyboard

    anchors.top:   true
    anchors.right: true
    // Pulled back by the shadow bleed added below, so the stack does not move.
    //
    // The 520-wide window against a 400-wide toast is NOT usable slack here: it is
    // all on the LEFT, for the swipe-to-dismiss overshoot. The toast anchors to the
    // window's right edge, so that edge had no room at all.
    margins.top:   Config.barExtent + Tokens.spacingMd - root.bleedTop
    margins.right: Tokens.spacingMd - root.bleedRight

    // Wider than the widest toast (a preview toast is 400), so the enter overshoot,
    // the deck's depth scale, and the leftward swipe all have room before the window
    // edge clips them.
    // The floating toast is elevationCard (NotificationToast.qml) — same depth as
    // ScreenshotToast, sitting on the bare desktop the same way. Larger than the
    // 8px margin it sits at, so the pull-back clamps to what is actually there.
    // The remainder is clipped at the screen edge, which has nothing to cast onto.
    // Same rule as PanelHost.bleed().
    readonly property int room:       Tokens.shadowRoom(Tokens.elevationCard)
    readonly property int bleedTop:   Math.min(root.room, Config.barExtent + Tokens.spacingMd)
    readonly property int bleedRight: Math.min(root.room, Tokens.spacingMd)

    implicitWidth:  520 + root.bleedRight
    implicitHeight: Math.max(1, stack.implicitHeight + Tokens.spacingSm
                                + root.bleedTop + root.room)

    color: "transparent"
    visible: root.active
    mask: Region { item: stack }

    // The deck itself now lives in NotificationStack, shared with the welded host
    // inside Bar's window. THIS host only draws while something is fullscreen: the
    // bar is a Top-layer surface and Hyprland hides those under a fullscreen window,
    // so the welded stack would simply vanish exactly when a game is up. Overlay
    // survives that, which is why this window still exists.
    NotificationStack {
        id: stack
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.topMargin:   root.bleedTop
        anchors.rightMargin: root.bleedRight
        live: root.ownsToasts
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // Toasts over a fullscreen window take a wallpaper/colour change when the front
    // reaches the top-right corner they sit in. Ignores every zone, so its margins
    // count from the screen's own edges.
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
        windowX: (root.screen ? root.screen.width : root.width) - root.width - root.margins.right
        windowY: root.margins.top
    }
}
