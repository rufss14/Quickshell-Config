pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../panels"

// ── SidePanelDock ─────────────────────────────────────────────────────────────
// The sidebar's panel slot: a sidebar button's panel (the stats, the clips) opens
// BESIDE that button, melting sideways out of the sidebar's face — the user's
// pick over the side's bar column, which hangs from the top corner however low on
// the edge the button is. One at a time (UiState.sidePanel), on the screen whose
// sidebar asked.
//
// ── Where ─────────────────────────────────────────────────────────────────────
// Across the edge, flush on the sidebar's face (SideRail.band) — welded, the blob
// welds the two lobes into one; floating, a gap off it. Along the edge, centred on
// the button (UiState.sidePanelFrom's place on the rail), kept on screen, and
// SNAPPED into a corner when it would land within the blob's reach of one: an end
// just short of the bar's underside or the bottom strip is two rounded corners on
// one line, and the smooth-min blends them into a bump (the dock preview's lesson).
//
// ── How it moves ──────────────────────────────────────────────────────────────
// The dock preview's melt, as a panel: `grow` pushes it out of the face, `narrow`
// opens it along the edge from a bud the width of a button, so it reads as coming
// out of THAT button; closing pinches in toward it before the depth goes. Switching
// to another button's panel keeps it out and GLIDES it along the face to the new
// place and size while the content crossfades (Accordion, as the bar's columns).
//
// ── What it hosts ─────────────────────────────────────────────────────────────
// `componentFor` below. Each panel follows the panel recipe and may declare
//   maxHeight     (in)  the room there is, so it can scroll rather than overflow
//   autoCloseMs   (out) close itself after this long unless the pointer is on it
//                       (the clips' "saved" peek)
// Everything behind a Loader: a closed slot has no panel at all.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: dock

    required property SideRail rail
    // This screen's sidebar asked (or nobody said whose: the first screen).
    required property bool owns
    // The blob's spring for this lobe; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    // ══ Which panel ═══════════════════════════════════════════════════════════
    readonly property string requested: dock.owns ? UiState.sidePanel : ""
    readonly property bool wanted: dock.requested !== ""

    Accordion {
        id: accordion
        requestedKey: dock.requested
    }

    function componentFor(key) {
        switch (key) {
        case "stats":       return statsComponent
        case "clips":       return clipsComponent
        case "clipsTarget": return clipsTargetComponent
        case "clipsPeek":   return clipsPeekComponent
        case "peek":        return peekComponent
        case "hover":       return hoverComponent
        case "notifications": return notificationsComponent
        case "clipboard":     return clipboardComponent
        case "timer":         return timerComponent
        case "voice":         return voiceComponent
        case "claude":        return claudeComponent
        case "screentime":    return screenTimeComponent
        case "inactivity":    return inactivityComponent
        case "tasks":         return tasksComponent
        case "brightness":    return brightnessComponent
        case "window":        return windowComponent
        case "layout":        return layoutComponent
        // The bar's panels, for the bar's modules placed here (SideBarModule).
        case "colorScheme":   return colorSchemeComponent
        case "equalizer":     return equalizerComponent
        case "wifi":          return wifiComponent
        case "bluetooth":     return bluetoothComponent
        case "gaming":        return gamingComponent
        case "clock":         return clockComponent
        default:            return null
        }
    }
    Component { id: statsComponent;       StatsPanel {} }
    Component { id: clipsComponent;       ClipsPanel {} }
    Component { id: clipsTargetComponent; ClipsTargetPanel {} }
    Component { id: clipsPeekComponent;   ClipsPeek {} }
    Component { id: peekComponent;        EventPeek {} }
    Component { id: hoverComponent;       HoverCard {} }
    Component { id: notificationsComponent; NotificationsPanel {} }
    Component { id: clipboardComponent;     ClipboardPanel {} }
    Component { id: timerComponent;         TimerPanel {} }
    Component { id: voiceComponent;         VoicePanel {} }
    Component { id: claudeComponent;        ClaudePanel {} }
    Component { id: screenTimeComponent;    ScreenTimePanel {} }
    Component { id: inactivityComponent;    InactivityPanel {} }
    Component { id: tasksComponent;         TasksPanel {} }
    Component { id: brightnessComponent;    BrightnessPanel {} }
    Component { id: windowComponent;        WindowPanel {} }
    Component { id: layoutComponent;        LayoutPanel {} }
    Component { id: colorSchemeComponent;   ColorSchemePanel {} }
    Component { id: equalizerComponent;     EqualizerPanel {} }
    Component { id: wifiComponent;          WifiPanel {} }
    Component { id: bluetoothComponent;     BluetoothPanel {} }
    Component { id: gamingComponent;        GamingPanel {} }
    Component { id: clockComponent;         ClockPanel {} }

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    // Open or still melting shut: the sidebar stays out for it (an auto-hiding
    // bar sliding away would leave the panel hanging off nothing).
    readonly property bool engaged: dock.wanted || dock.grow > 0.01
    readonly property bool wantsKeyboardFocus: accordion.anyOpen
    readonly property Item maskItem: maskBox
    // The lobe, welded only; 0 while shut.
    readonly property bool _lobe: dock.welded && dock.grow > 0.01
    readonly property real blobX: dock._lobe ? card.x : 0
    readonly property real blobY: dock._lobe ? card.y : 0
    readonly property real blobW: dock._lobe ? card.width  : 0
    readonly property real blobH: dock._lobe ? card.height : 0
    // How far the card has faded in, for the cookie field (Bar.qml → Drift.setPanels).
    readonly property real cardOpacity: card.opacity

    // ══ Where ═════════════════════════════════════════════════════════════════
    readonly property string edge: dock.rail.edge
    readonly property bool vertical: dock.rail.vertical
    // Blob, frame and an anchored bar: a lobe of the frame. Otherwise a floating
    // card, a gap off the sidebar, fading in (BarDock's non-welded look).
    readonly property bool welded: dock.rail.welded
    readonly property real face: dock.rail.band
    readonly property real standOff: dock.welded ? 0 : Tokens.spacingMd
    // Kept off the screen's far side and the top bar, as a bar panel is.
    readonly property int margin: Tokens.spacingMd

    // Along the edge, the room it may take: between the bar's underside and the
    // bottom strip on a side, strip to strip along the bottom.
    readonly property real lo: (dock.vertical ? dock.rail.spanStart : dock.rail.strip)
                               + (dock.welded ? 0 : dock.margin)
    readonly property real hi: (dock.vertical ? dock.rail.spanEnd : dock.rail.screenW - dock.rail.strip)
                               - (dock.welded ? 0 : dock.margin)
    readonly property real alongRoom: Math.max(0, dock.hi - dock.lo)
    // Across it: the rest of the screen, less a margin, and on the bottom edge less
    // the top bar.
    readonly property real acrossRoom: Math.max(0, dock.vertical
        ? dock.rail.screenW - dock.face - dock.standOff - dock.margin
        : dock.rail.screenH - dock.face - dock.standOff - Config.barExtent - dock.margin)

    // ── The button it belongs to ──────────────────────────────────────────────
    // Its centre along the edge. A local copy, set while open and never cleared, so
    // a closing panel closes where it opened rather than chasing a button that has
    // already moved or gone (CLAUDE.md's fade rule).
    readonly property real _live: {
        const id = UiState.sidePanelFrom
        const at = dock.rail.at[id]
        const len = dock.rail.allLengths[id] ?? 0
        return at === undefined || len <= 0 ? -1 : at + len / 2
    }
    property real anchorMain: 0
    function _catch() { if (dock.wanted && dock._live >= 0) dock.anchorMain = dock._live }
    on_LiveChanged: dock._catch()
    onWantedChanged: dock._catch()
    Component.onCompleted: dock._catch()
    // The button went away (taken off the sidebar) under its open panel.
    Connections {
        target: Config
        function onSidebarLayoutChanged() {
            if (UiState.sidePanel !== "" && !Config.sidebarPlaced(UiState.sidePanelFrom))
                UiState.closeSidePanel()
        }
    }

    // ── Its size: the active panel's own, within the room ─────────────────────
    readonly property Item panel: loader.item
    readonly property real cardW: dock.panel
        ? Math.min(dock.panel.implicitWidth,  dock.vertical ? dock.acrossRoom : dock.alongRoom) : 0
    readonly property real cardH: dock.panel
        ? Math.min(dock.panel.implicitHeight, dock.vertical ? dock.alongRoom : dock.acrossRoom) : 0
    readonly property real alongLen:  dock.vertical ? dock.cardH : dock.cardW
    readonly property real acrossLen: dock.vertical ? dock.cardW : dock.cardH
    // Held, not bound: the panel unloads as the close finishes, and a box bound to
    // its size would snap to nothing for the last frames of the melt.
    property real heldAlong: 0
    property real heldAcross: 0
    onAlongLenChanged:  if (dock.alongLen  > 0) dock.heldAlong  = dock.alongLen
    onAcrossLenChanged: if (dock.acrossLen > 0) dock.heldAcross = dock.acrossLen

    // ── The melt ──────────────────────────────────────────────────────────────
    property real grow: dock.wanted ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(dock.wanted)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: dock.wanted ? Easing.BezierSpline : Motion.exitCurve
        }
    }
    property real narrow: dock.wanted ? 1 : 0
    Behavior on narrow {
        NumberAnimation {
            duration: dock.wanted ? Motion.spatial : Motion.exit
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: dock.wanted ? Easing.BezierSpline : Motion.travel
        }
    }
    // Both at rest: only then may the glide below take the box over, or it would
    // chase the melt's own animation (Motion.qml's opening rule).
    readonly property bool melted: dock.grow >= 1 && dock.narrow >= 1

    // The glide between two buttons' panels: place and size, on the emphasized curve.
    property real gAnchor: dock.anchorMain
    property real gAlong:  dock.heldAlong
    property real gAcross: dock.heldAcross
    Behavior on gAnchor { enabled: dock.melted; NumberAnimation { duration: Motion.emphasized
                          easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
    Behavior on gAlong  { enabled: dock.melted; NumberAnimation { duration: Motion.emphasized
                          easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
    Behavior on gAcross { enabled: dock.melted; NumberAnimation { duration: Motion.emphasized
                          easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }

    function _clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
    // Where the whole card rests along the edge: centred on the button, on screen,
    // snapped into a corner it would otherwise stop just short of.
    readonly property real restAlong: {
        const len = dock.gAlong
        const top = dock.hi - len
        let at = dock._clamp(dock.gAnchor - len / 2, dock.lo, Math.max(dock.lo, top))
        if (at - dock.lo < dock.rail.apart) at = dock.lo
        if (top - at < dock.rail.apart) at = Math.max(dock.lo, top)
        return at
    }
    // …and, melting, the bud: the button's width out of the button, widening.
    readonly property real budLen: Math.min(dock.gAlong, Config.sidebarCell)
    readonly property real alongNow: dock.budLen + (dock.gAlong - dock.budLen) * dock.narrow
    readonly property real alongPosNow:
        dock._clamp(dock.gAnchor - dock.alongNow / 2, dock.restAlong, dock.restAlong + dock.gAlong - dock.alongNow)
    readonly property real acrossNow: dock.gAcross * dock.grow

    // The mask: the card while it's on screen, nothing otherwise.
    Item {
        id: maskBox
        x: card.x
        y: card.y
        width:  dock.grow > 0.01 ? card.width  : 0
        height: dock.grow > 0.01 ? card.height : 0
    }

    // ══ The card ══════════════════════════════════════════════════════════════
    // BarDock's card, turned on its side: welded, a lobe (no outline, no shadow —
    // the blob draws the one continuous stroke); floating, an ordinary card.
    Card {
        id: card

        readonly property real faceX: dock.edge === "left"  ? dock.face + dock.standOff
                                    : dock.edge === "right" ? dock.rail.screenW - dock.face - dock.standOff
                                    : 0
        readonly property real faceY: dock.rail.screenH - dock.face - dock.standOff

        x: dock.edge === "left"  ? card.faceX
         : dock.edge === "right" ? card.faceX - dock.acrossNow
         :                         dock.alongPosNow
        y: dock.vertical ? dock.alongPosNow : card.faceY - dock.acrossNow
        width:  dock.vertical ? dock.acrossNow : dock.alongNow
        height: dock.vertical ? dock.alongNow : dock.acrossNow

        // Welded, the blob is the material while it melts and the card fades in with
        // its content, as BarDock's does. Floating there's no blob: the card itself
        // is what grows out, so it's up for as long as the panel is wanted.
        shown:      dock.welded ? accordion.contentVisible : dock.wanted
        hoverFocus: !dock.welded
        // The shared cookie field behind the panel (Card.drift), or the blob's material (BarDock's).
        drift:      true
        blobMaterial: dock.welded && Morph.available && Drift.inBlob
        // Welded to the sidebar's face: the edge the sidebar is on is the join. Floating, a gap off
        // it, there is no join and the corners stay round.
        driftJoin:  dock.welded ? dock.edge : ""
        elevated:   !dock.welded
        border.width: dock.welded ? 0 : Tokens.borderWidth
        // Grows out of the face, not out of its own middle, where it isn't welded.
        transformOrigin: dock.edge === "left"  ? Item.Left
                       : dock.edge === "right" ? Item.Right
                       :                         Item.Bottom
        transform: Matrix4x4 { matrix: dock.welded ? dock.deformMatrix : Qt.matrix4x4() }

        HoverHandler { id: cardHover }

        // The panel at its own full size, pinned where the whole card would put
        // it, so the melting box uncovers it rather than squeezing it — while it
        // glides, it rides the box. Shown only in the melt's last half.
        Loader {
            id: loader
            active: accordion.activeKey !== ""
            sourceComponent: dock.componentFor(accordion.activeKey)
            width:  dock.cardW
            height: dock.cardH
            x: dock.edge === "right" ? card.width - dock.cardW
             : !dock.vertical && !dock.melted ? dock.restAlong - dock.alongPosNow
             : 0
            y: dock.edge === "bottom" ? card.height - dock.cardH
             : dock.vertical && !dock.melted ? dock.restAlong - dock.alongPosNow
             : 0
            opacity: Math.max(0, Math.min(dock.grow, dock.narrow) * 2 - 1) * dock.contentFade
            onLoaded: {
                if (loader.item.maxHeight !== undefined)
                    loader.item.maxHeight = Qt.binding(() => dock.vertical ? dock.alongRoom : dock.acrossRoom)
            }
        }
    }

    // The content's own fade, for a swap between two panels (the Accordion's beat:
    // out, the box glides and resizes, in).
    property real contentFade: accordion.contentVisible ? 1 : 0
    Behavior on contentFade {
        NumberAnimation { duration: Motion.surfaceDuration(accordion.contentVisible)
                          easing.type: Motion.surfaceEasing(accordion.contentVisible) }
    }

    // ── Closing itself (the peek) ─────────────────────────────────────────────
    // A panel that asks (autoCloseMs) closes that long after it's up — later if the
    // pointer is resting on it. Only the panel that asked: if something else took
    // the slot meanwhile, it's left alone.
    readonly property int autoCloseMs: (accordion.contentVisible && dock.panel
                                        && dock.panel.autoCloseMs !== undefined) ? dock.panel.autoCloseMs : 0
    onAutoCloseMsChanged: if (dock.autoCloseMs > 0) autoClose.restart(); else autoClose.stop()
    Timer {
        id: autoClose
        interval: Math.max(1, dock.autoCloseMs)
        onTriggered: {
            if (cardHover.hovered) return
            if (UiState.sidePanel === accordion.activeKey) UiState.closeSidePanel()
        }
    }
    Connections {
        target: cardHover
        function onHoveredChanged() {
            if (!cardHover.hovered && dock.autoCloseMs > 0) autoClose.restart()
        }
    }

    // ── Escape closes it ──────────────────────────────────────────────────────
    // On an Item, never the window (BarPanelDock's escFocus).
    EscapeGuard {
        id: escFocus
        wanted: dock.requested !== ""
        // The open panel's own keys (see BarPanelDock): `handleKey(event)`, and `handleEscape()` to use
        // Escape for something smaller than closing.
        onKeyPressed: (event) => {
            const it = loader.item
            if (it && it.handleKey) event.accepted = it.handleKey(event) === true
        }
        onEscaped: {
            const it = loader.item
            if (it && it.handleEscape && it.handleEscape() === true) return
            UiState.closeSidePanel()
        }
    }
    onRequestedChanged: if (dock.requested !== "") escFocus.forceActiveFocus()
}
