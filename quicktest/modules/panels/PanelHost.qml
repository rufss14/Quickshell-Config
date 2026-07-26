import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../components"
import "../../state"

// ── PanelHost ─────────────────────────────────────────────────────────────────
// Owns the three panel containers (left / center / right) on one screen.
// Replaces OverlayRoot.
//
// ── What changed, and why it matters ──────────────────────────────────────────
// OverlayRoot instantiated EVERY panel permanently — six of them, as always-alive
// Rectangles inside always-mapped windows, merely hidden with `opacity: 0`. A
// hidden panel is still a running panel:
//
//   • ClockPanel kept 1s, 500ms and 350ms timers ticking, repainting Canvases
//     nobody could see. (It has since moved to the overview.)
//   • WifiPanel rescanned wifi every 15 seconds while closed.
//   • EqualizerPanel polled `wpctl` every 3 seconds while closed.
//
// Here each container owns ONE Loader. The Loader instantiates only the panel
// the accordion says is active, and destroys it on close — so a closed panel has
// no timers, no processes, and no scene graph, because it does not exist.
//
// The three-step swap (fade out → resize → fade in) that OverlayRoot open-coded
// twice is now the shared Accordion component, and the six hand-copied card
// blocks are one Card.
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: root

    required property var screen

    // ── Geometry ──────────────────────────────────────────────────────────────
    // Config.barThickness, not the token: panels hang off the BAR, so a user who
    // thickens it must not have the bar grow over its own panels.
    readonly property int topMargin:   Config.barThickness + 2
    readonly property int edgeMargin:  Config.barInset + Tokens.spacingMd
    readonly property int bottomSafe:  Tokens.spacingMd

    // Every panel shares one width, so switching between them never shifts the
    // container sideways — only the height changes with content.
    readonly property int panelWidth: 535
    // The widest a left-hand panel may become. The WINDOW is always this wide (it's a
    // fixed surface — see the note below), and the card inside takes whatever the panel
    // actually asks for. A ceiling rather than a free-for-all: a panel that grows without
    // limit stops reading as a popup and starts covering the desktop.
    readonly property int panelWidthMax: 660

    readonly property int screenW: screen?.width  ?? 1920
    readonly property int screenH: screen?.height ?? 1080

    // No panel may crowd the bottom of the screen. This is also the FIXED height
    // of the left/right panel windows — the surface never resizes; the card
    // inside it does. See Card.qml.
    readonly property int maxPanelHeight: screenH - topMargin - bottomSafe

    // Fixed height of the centre (update) window. It must EXCEED the tallest UpdatePanel
    // view (the expanded running view) — the panel is top-anchored inside it and masked to
    // its own rect, so any surplus is transparent click-through, but a window SHORTER than
    // the panel clips the panel's bottom off. That was the "slides down but cuts off": the
    // running view outgrew a 340px window.
    readonly property int centerHeight: 440

    // This screen owns the panels (or no screen does, e.g. an IPC invocation).
    readonly property bool owns: UiState.activeScreen === root.screen

    // ══ LEFT — wallpaper / colorScheme / equalizer ════════════════
    Accordion {
        id: leftAccordion
        requestedKey: root.owns ? UiState.leftPanel : ""
    }

    PanelWindow {
        id: leftWindow
        screen: root.screen

        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-left-panel"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: leftAccordion.anyOpen ? WlrKeyboardFocus.OnDemand
                                                           : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true
        margins.top:  root.topMargin
        margins.left: root.edgeMargin

        // FIXED surface. See Card.qml — animating a PanelWindow's implicitHeight
        // resizes the Wayland surface every frame (new buffer + compositor
        // roundtrip), which stutters however clean the QML is. The window holds
        // still; the card grows inside it, which is pure GPU-side compositing.
        implicitWidth:  root.panelWidthMax
        implicitHeight: root.maxPanelHeight

        color: "transparent"
        // The window is bigger than the card, so input is masked to the card —
        // otherwise this transparent expanse would swallow clicks meant for the
        // desktop below it.
        mask: Region { item: leftCard }

        // Stays mapped while the card fades out, then unmaps.
        visible: leftAccordion.activeKey !== "" || leftCard.opacity > 0.005

        Card {
            id: leftCard
            anchors.top:   parent.top
            anchors.left:  parent.left

            // Width comes from the panel, not from anchoring to the window: the window is a
            // deliberately oversized fixed surface, so anchoring right would stretch every
            // panel to the widest one's size.
            width:  root.widthFor(leftAccordion.activeKey, leftLoader)
            height: root.heightFor(leftAccordion.activeKey, leftLoader)

            Behavior on width {
                NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter }
            }
            Behavior on height {
                NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter }
            }

            shown: leftAccordion.contentVisible
            transformOrigin: Item.TopLeft   // grows out of the button that opened it

            Loader {
                id: leftLoader
                anchors.fill: parent
                // THE line that kills the idle cost: no active key, no panel.
                active: leftAccordion.activeKey !== ""
                sourceComponent: root.componentFor(leftAccordion.activeKey)
            }
        }

        // Escape closes the group. Focus is grabbed whenever the group opens.
        Item {
            id: leftFocus
            focus: true
            Keys.onEscapePressed: UiState.closeLeft()
        }
        Connections {
            target: UiState
            function onLeftPanelChanged() {
                if (UiState.leftPanel !== "") leftFocus.forceActiveFocus()
            }
        }
    }

    // ══ RIGHT — wifi / clock ═══════════════════════════════════════════════════
    Accordion {
        id: rightAccordion
        requestedKey: root.owns ? UiState.rightPanel : ""
    }

    PanelWindow {
        id: rightWindow
        screen: root.screen

        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-right-panel"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: rightAccordion.anyOpen ? WlrKeyboardFocus.OnDemand
                                                            : WlrKeyboardFocus.None

        anchors.top:   true
        anchors.right: true
        margins.top:   root.topMargin
        margins.right: root.edgeMargin

        // Fixed surface; the card animates inside it. Same reason as the left.
        implicitWidth:  root.panelWidth
        implicitHeight: root.maxPanelHeight

        color: "transparent"
        mask: Region { item: rightCard }

        visible: rightAccordion.activeKey !== "" || rightCard.opacity > 0.005

        Card {
            id: rightCard
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right

            height: root.heightFor(rightAccordion.activeKey, rightLoader)
            Behavior on height {
                NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter }
            }

            shown: rightAccordion.contentVisible
            transformOrigin: Item.TopRight

            Loader {
                id: rightLoader
                anchors.fill: parent
                active: rightAccordion.activeKey !== ""
                sourceComponent: root.componentFor(rightAccordion.activeKey)
            }
        }

        Item {
            id: rightFocus
            focus: true
            Keys.onEscapePressed: UiState.closeRight()
        }
        Connections {
            target: UiState
            function onRightPanelChanged() {
                if (UiState.rightPanel !== "") rightFocus.forceActiveFocus()
            }
        }
    }

    // ══ CENTER — system update ═════════════════════════════════════════════════
    // Not an accordion: the center slot only ever hosts one panel, so there is no
    // sibling to sequence against. It sizes itself from its content, which
    // animates its own width/height internally.
    //
    // UpdatePanel is the one panel that OWNS its own visibility (it opens itself
    // on a request and closes itself when the run finishes or is dismissed), and
    // only mirrors that into UiState.updateOpen so the bar pill can react. So the
    // Loader cannot be gated on updateOpen — that would deadlock: the panel can't
    // report itself open until it exists, and it wouldn't exist until it reported
    // itself open. The *request* drives creation instead, and the mirror going
    // false tears it back down.
    property bool updateActive: false

    // `Loader.item` is statically a bare QObject, so `updateLoader.item.startUpdate(…)`
    // is an unchecked call into the dark: nothing verifies the method exists, and a rename
    // would surface as a runtime TypeError in a panel you only open occasionally.
    //
    // Casting it once, here, gives the rest of the file a typed handle — the compiler
    // checks every use, and `?.` makes "not loaded yet" an ordinary state rather than a
    // crash.
    readonly property UpdatePanel updatePanel: updateLoader.item as UpdatePanel

    Connections {
        target: UiState

        function onUpdateRequestIdChanged() {
            if (!root.owns) return
            if (!root.updateActive) root.updateActive = true   // Loader creates it; onLoaded starts the run
            else root.updatePanel?.startUpdate(UiState.pendingUpdateCount)  // already up — restart the run
        }

        function onUpdateOpenChanged() {
            if (!UiState.updateOpen) root.updateActive = false // it closed itself — destroy it
        }
    }

    PanelWindow {
        id: centerWindow
        screen: root.screen

        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-center-panel"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: root.updateActive ? WlrKeyboardFocus.OnDemand
                                                       : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true
        margins.top:  root.topMargin

        // FIXED surface, centred once. UpdatePanel animates its own width and
        // height as it moves between views, and the window used to bind straight
        // to those — so the Wayland surface was being resized on every frame of
        // that animation, AND `margins.left` was recomputed from the animating
        // width, dragging the window sideways as it went. Both are gone: the
        // window is a constant size at a constant position, and the panel grows
        // inside it.
        implicitWidth:  root.panelWidth
        implicitHeight: root.centerHeight
        margins.left:   Math.round((root.screenW - root.panelWidth) / 2)

        color: "transparent"
        mask: Region { item: updateHolder }
        visible: root.owns && root.updateActive

        // Sized to the panel, centred in the (larger) window. No Behavior here —
        // UpdatePanel already eases its own implicitWidth/Height, and animating
        // this too would chase it.
        Item {
            id: updateHolder
            anchors.top:              parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width:  root.updatePanel?.implicitWidth  ?? 0
            height: root.updatePanel?.implicitHeight ?? 0

            Loader {
                id: updateLoader
                anchors.fill: parent
                active: root.owns && root.updateActive
                sourceComponent: updateComponent
                onLoaded: root.updatePanel?.startUpdate(UiState.pendingUpdateCount)
            }
        }
    }

    // ══ Desktop / floating overlays ════════════════════════════════════════════
    // These are not accordion cards — they own their own layer-shell surfaces and
    // are toggled independently. Both already gate their own work on visibility.
    CavaBG            { screen: root.screen }

    // ══ Panel registry ═════════════════════════════════════════════════════════
    // A key → Component map. The Loaders above instantiate exactly one of these
    // at a time; everything else genuinely does not exist.
    function componentFor(key) {
        switch (key) {
            case "wallpaper":   return wallpaperComponent
            case "colorScheme": return colorSchemeComponent
            case "equalizer":   return equalizerComponent
            case "wifi":        return wifiComponent
            default:            return null
        }
    }

    // ── Panels size themselves, within limits ─────────────────────────────────
    // Wallpaper and colorScheme used to be hard-coded to 340 here, which silently CLIPPED
    // them: the wallpaper gallery asked for 420 and the colour editor for 500, and both
    // just lost everything past 340 with no warning anywhere. A panel knows what it needs;
    // this only enforces a ceiling so nothing can run off the screen.
    function heightFor(key, loader) {
        if (key === "") return 0
        // The wallpaper gallery stays at 340 by request — it is a grid of thumbnails and
        // looked right at that size; letting it take its declared 420 made it worse.
        if (key === "wallpaper") return 340
        const h = loader.item?.implicitHeight ?? 0
        return Math.min(h > 0 ? h : 340, root.maxPanelHeight)
    }

    // Width works the same way, floored at the shared panelWidth so the narrow panels stay
    // aligned with each other and only a panel that explicitly asks is ever wider.
    function widthFor(key, loader) {
        if (key === "" || key === "wallpaper") return root.panelWidth
        const w = loader.item?.implicitWidth ?? 0
        return Math.max(root.panelWidth, Math.min(w, root.panelWidthMax))
    }

    Component { id: wallpaperComponent;   WallpaperPanel   {} }
    Component { id: colorSchemeComponent; ColorSchemePanel {} }
    Component { id: equalizerComponent;   EqualizerPanel   {} }
    Component { id: wifiComponent;        WifiPanel        {} }
    Component { id: updateComponent;      UpdatePanel      {} }
}
