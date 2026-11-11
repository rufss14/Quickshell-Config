import QtQuick
import Quickshell
import "../config"
import "../state"

// ── TipBubble ─────────────────────────────────────────────────────────────────
// The tooltip of one surface. A control's explanation (its HelpTip) is published through
// UiState.showTip; the bubble that draws it belongs to the SURFACE, above everything in it, because a
// tip drawn beside the control is clipped by whatever scrolls or clips the control. The settings card
// has one, and the bar's window has one for its pills and panels.
//
// It waits a moment before the first tip (sweeping the pointer across a page must not flash one per
// control), then follows from control to control at once, as tooltips do.
//
// `host` is the item the bubble lives in and measures against. Several surfaces read the one UiState,
// so a bubble only follows a control that is inside its own host.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: tip

    required property Item host
    // A part of the host that has a bubble of its own (the docked settings card inside the bar's
    // window): its controls are that bubble's.
    property Item except: null
    // The bar's blob draws its pills' tips (PillTip): a tip from a HelpTip with `pill` is not this bubble's.
    property bool skipPills: false

    readonly property QtObject source: UiState.tipSource
    property bool shown: false
    readonly property int maxWidth: 300

    function _owns(item) {
        for (let it = item; it; it = it.parent) {
            if (tip.except && it === tip.except) return false
            if (it === tip.host) return true
        }
        return false
    }

    function place() {
        const src = UiState.tipSource
        if (!src || !src.parent) return
        const p = src.parent.mapToItem(tip.host, src.point.position.x, src.point.position.y)
        const gap = Tokens.spacingXl
        let x = p.x + Tokens.spacingSm
        let y = p.y + gap
        if (x + tip.width > tip.host.width - Tokens.spacingMd) x = tip.host.width - Tokens.spacingMd - tip.width
        if (y + tip.height > tip.host.height - Tokens.spacingMd) y = p.y - Tokens.spacingSm - tip.height
        tip.x = Math.max(Tokens.spacingMd, x)
        tip.y = Math.max(Tokens.spacingMd, y)
    }

    onSourceChanged: {
        const src = tip.source
        if (!src || !src.parent || !tip._owns(src.parent) || (tip.skipPills && src.pill === true)) {
            tipDelay.stop()
            tip.shown = false
            return
        }
        if (tip.shown) tip.place()
        else tipDelay.restart()
    }

    Timer {
        id: tipDelay
        interval: 550
        onTriggered: {
            tip.place()
            tip.shown = true
        }
    }

    width:  Math.min(tipText.implicitWidth, tip.maxWidth) + Tokens.spacingMd * 2
    height: tipText.implicitHeight + Tokens.spacingSm * 2 + 2
    radius: Tokens.radiusSm
    color:        Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationPopup)

    visible: tip.opacity > 0.01
    opacity: tip.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    // Rises the last few pixels into place, so it reads as arriving, not blinking.
    transform: Translate {
        y: tip.shown ? 0 : 4
        Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    StyledText {
        id: tipText
        anchors.centerIn: parent
        width: Math.min(tipText.implicitWidth, tip.maxWidth)
        // Its own copy: the bubble fades out after the source has gone, and must not blank or
        // show another surface's words on the way.
        property string held: ""
        text: tipText.held
        variant: "caption"
        wrapMode: Text.WordWrap
        Connections {
            target: UiState
            function onTipTextChanged() { if (tip.source && tip.source.parent && tip._owns(tip.source.parent) && !(tip.skipPills && tip.source.pill === true)) tipText.held = UiState.tipText }
            function onTipSourceChanged() { if (tip.source && tip.source.parent && tip._owns(tip.source.parent) && !(tip.skipPills && tip.source.pill === true)) tipText.held = UiState.tipText }
        }
    }
}
