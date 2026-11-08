pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../state"
import "../settings"

// ── SettingsPanelHost ─────────────────────────────────────────────────────────
// The docked alternative to SettingsWindow: the same SettingsCard, welded into
// the screen frame's BOTTOM strip the way a bar panel welds into the bar. Active
// only while Config.settingsPanel is on — SettingsWindow self-hides then.
//
//   Config.settingsPanelSide   "left" / "center" / "right"
//
// ── Why it lives in Bar's window ──────────────────────────────────────────────
// `Quicktest.Blobs`' metaball shader fuses shapes by sampling them in ONE Qt
// Quick scene graph; two layer-shell surfaces are composited independently by
// Hyprland. A panel that genuinely MELTS out of the frame therefore has to share
// the frame's scene graph — and the frame's scene graph is Bar's window, where
// BlobBarLayer draws the whole ring. Same move BarPanelDock
// made, for the same reason; see its header.
//
// ── The melt ─────────────────────────────────────────────────────────────────
// A `reveal` clip box pinned at the strip's inner edge grows its height 0 → cardH
// out of the bottom of the screen. BlobBarLayer's `settingsRect` tracks that box
// and smooth-min unions it into the ring, so the card is the frame's bottom strip
// pulled upward — exactly the way a bar panel is the bar pulled down. The real
// SettingsCard is a FIXED-size child anchored to the box's bottom: it never
// resizes, the clip just uncovers it.
//
// Without the plugin the card squares its frame-touching corners and butt-joins
// them (a clean seam, no melt — SettingsCard.welded false).
//
// ── It does not overlap the bar ──────────────────────────────────────────────
// Docked to the bottom, its top edge sits well below the bar strip — the bar
// stays interactive and the Bar page's arrange drag still works.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property int  screenH
    required property bool owns

    readonly property bool shownState:
        UiState.settingsWindowOpen && Config.settingsPanel && host.owns

    readonly property string side: Config.settingsPanelSide
    readonly property int strip: Config.screenFrame ? Config.frameDepth : 0
    readonly property bool blobWeld:
        Morph.available && Config.screenFrame && Config.barAnchored

    // One fixed size, clamped to the screen — not content-driven like a bar panel.
    readonly property int cardW:
        Math.max(880, Math.min(1200, host.width - host.strip * 2 - Tokens.spacingXxl * 2))
    readonly property int cardH:
        Math.max(440, Math.min(600, host.screenH - Config.barExtent - host.strip - Tokens.spacingXxl))

    // Bar.qml grows its window to reach this far down so the card's bottom edge is
    // never clipped by the surface edge. The window is already ~screenH for the
    // the panel docks' reserved room; this is the belt-and-braces term.
    readonly property int bottomReach: host.screenH - host.strip + 2

    // Bar.qml reads these — window input mask, keyboard-focus escalation. The mask
    // tracks `reveal` (not the card): it collapses to zero height when closed, so
    // the reserved band never steals a click from the desktop under it.
    readonly property Item maskItem: reveal
    readonly property bool wantsKeyboardFocus: host.shownState

    // The live box BlobBarLayer's settingsRect tracks, in WINDOW coordinates
    // (host fills the window, so reveal's own x/y already are window space).
    readonly property real blobX: reveal.x
    readonly property real blobY: reveal.y
    readonly property real blobW: reveal.width
    readonly property real blobH: reveal.height

    // The clip is what makes only the grown-out portion of the card show — the
    // card itself is full height and pinned at the strip line. In the no-plugin
    // fallback this also clips the card's own drop shadow at the box edges; that
    // path is already the plain "square the corners, butt-join" look, so a tight
    // shadow is in keeping rather than a regression.
    Item {
        id: reveal
        clip: true
        width: host.cardW
        x: host.side === "left"  ? host.strip
         : host.side === "right" ? host.width - host.strip - host.cardW
         :                         Math.round((host.width - host.cardW) / 2)

        // Bottom pinned at the strip's inner edge; the top rises as height grows.
        readonly property int bottomY: host.screenH - host.strip
        height: host.shownState ? host.cardH : 0
        y: reveal.bottomY - reveal.height
        Behavior on height {
            NumberAnimation {
                duration: Motion.surfaceDuration(host.shownState)
                easing.bezierCurve: Motion.emphasizedDecel
                easing.type: host.shownState ? Easing.BezierSpline : Motion.exitCurve
            }
        }

        Loader {
            id: cardLoader
            width:  host.cardW
            height: host.cardH
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter

            // Built on open, torn down on close — but kept alive through the
            // collapse so the box isn't empty as it shrinks.
            active: host.shownState || reveal.height > 1
            opacity: host.shownState ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            onLoaded: if (item) item.forceActiveFocus()

            sourceComponent: SettingsCard {
                closable: true
                onCloseRequested: UiState.settingsWindowOpen = false

                welded:       host.blobWeld
                squareBottom: !host.blobWeld
                squareLeft:   !host.blobWeld && host.side === "left"
                squareRight:  !host.blobWeld && host.side === "right"

                focus: true
                Keys.onEscapePressed: function(e) {
                    UiState.settingsWindowOpen = false
                    e.accepted = true
                }
            }
        }
    }

    Connections {
        target: UiState
        function onSettingsWindowOpenChanged() {
            if (host.shownState) cardLoader.item?.forceActiveFocus()
        }
    }
}
