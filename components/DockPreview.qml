pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../config"
import "../services"
import "../state"
import "../services/dock.js" as DockJs

// ── DockPreview ──────────────────────────────────────────────────────────────
// Windows 11's taskbar thumbnails: hover a dock button and, after a dwell, a
// card rises above it with one LIVE tile per window the app has open — its
// title, a close button, and the window itself. Click a tile to go to that
// window; middle-click or × to close it. Move to the next button and the card
// slides over and re-fills, rather than closing and re-opening.
//
// An app that isn't running gets a small label instead (its name, and whether a
// click can start it), which is Windows' tooltip for a pinned app.
//
// ── Separate from the strip on purpose ────────────────────────────────────────
// DockIconStrip decides WHEN (`previewKey`) and WHERE along the dock
// (`previewCenter`); this draws the card. It has to be a sibling of the dock's
// surface, not a child: the persistent dock is uncovered by a clip as it melts
// out of the frame, and a card parented inside that clip would be cut away by
// the very edge it hangs from. The host fills a large item with this one and
// hands over the two coordinates below in that item's space; the card clamps
// itself to this item's bounds.
//
// ── A fading surface keeps its own copy ──────────────────────────────────────
// `key` and `main` are set on the way in and never cleared, so the card still
// shows what it showed for the whole of its fade-out instead of blanking the
// instant the strip lets go (the UpdatesPage/ScreenshotToast rule).
//
// Captures exist only while the card is on screen: the tile model empties once
// it has faded out, and `live` stops the moment it starts closing.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ══ Set by the host ═══════════════════════════════════════════════════════
    property var    strip: null               // the DockIconStrip this previews for
    property string edge:  "bottom"           // the screen edge the dock is on

    // In THIS item's coordinates: the previewed button's centre along the dock,
    // and the dock's inner edge — the side facing into the screen, which the
    // card stands `standOff` away from.
    property real anchorMain: -1
    property real dockInner:  0

    // The dock's own extent along its edge, in this item's coordinates. A MELTED
    // preview stays inside it: it's the dock's material, and a lobe hanging past
    // the dock's end read as the blob escaping its limit. -1 = not given.
    property real spanLo: -1
    property real spanHi: -1

    property var monitor: null                // where a focus lands (Hypr.goToToplevel)

    // The outline — the SAME as the dock it hangs from, so the two read as one
    // family: the frame's line at the frame's width when the dock is welded, the
    // ordinary card outline otherwise (the host decides; these are the latter).
    property color strokeColor: Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)
    property real  strokeWidth: Tokens.borderWidth

    // A tile was clicked through to its window.
    signal activated()

    // ══ Peek ══════════════════════════════════════════════════════════════════
    // Rest on a window (a tile, or a row in the list) and the screen peeks at its
    // workspace with it lit — Windows' Aero Peek (modules/bar/WindowPeek). Off by
    // default: only the Bar's dock turns it on (the overview covers the screen, so
    // its dock has nothing to peek over). Once one peek is showing, moving to the
    // next window switches at once, as the previews themselves do.
    property bool peeks: false
    readonly property int peekDwell: 300          // an interaction timing
    property string _peekWant: ""

    function peekHover(w, on) {
        if (!root.peeks || !w) return
        const a = Hypr.addr(w.address)
        if (on) {
            root._peekWant = a
            if (UiState.dockPeek !== "") UiState.dockPeek = a
            else peekTimer.restart()
        } else if (root._peekWant === a) {
            root._peekWant = ""
            peekTimer.stop()
            UiState.dockPeek = ""
        }
    }
    Timer {
        id: peekTimer
        interval: root.peekDwell
        onTriggered: if (root.open && root._peekWant !== "") UiState.dockPeek = root._peekWant
    }

    // ══ Read by the host ══════════════════════════════════════════════════════
    readonly property bool hovered: cardHover.hovered
    // For a window's input mask: the card's box while it's on screen, nothing
    // otherwise — the card itself keeps its last size through and after the fade,
    // and a mask built from it would eat clicks where it used to be.
    readonly property Item maskItem: maskBox

    // ══ State ═════════════════════════════════════════════════════════════════
    readonly property bool vertical: root.edge === "left" || root.edge === "right"
    readonly property bool open: root.strip !== null && root.strip.previewKey !== ""
    readonly property bool shown: root.fused ? root.grow > 0.01 : card.opacity > 0.01

    // ══ Fused (Config.dockPreviewFuse, welded docks only) ══════════════════════
    // Instead of a floating card that fades in, the preview MELTS out of the dock:
    // its box grows 0 → full from the dock's side, drawn in the frame's own fill,
    // and the host hands that box to BlobBarLayer so the smooth-min welds it to the
    // dock's lobe across the `gap`. The content rides the box's moving edge — the
    // same slide-out the dock itself uses — so nothing is scaled or faded in.
    property bool fused: false
    property matrix4x4 deformMatrix         // the lobe's spring, back from the blob

    property real grow: root.open ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(root.open)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.open ? Easing.BezierSpline : Motion.exitCurve
        }
    }

    // …and how much of its LENGTH along the dock is out, from a bud the icon's
    // width to the whole card. Its own curve, so the melt has a shape: opening, a
    // bud pushes out of the icon and widens as it grows; closing, the card pinches
    // in toward the icon first (fast, `travel`) while the depth is still slow to
    // go (`exitCurve`), so it reads as drawn back INTO the icon rather than wiped
    // flat against the dock.
    property real narrow: root.open ? 1 : 0
    Behavior on narrow {
        NumberAnimation {
            duration: root.open ? Motion.spatial : Motion.exit
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.open ? Easing.BezierSpline : Motion.travel
        }
    }
    readonly property real bud: root.strip ? root.strip.button : 0
    // Both at rest: only then may the glide's own Behaviors take the box over.
    readonly property bool melted: root.grow >= 1 && root.narrow >= 1

    // The box the host gives the blob; zero unless fused and at least partly out.
    readonly property bool _lobe: root.fused && root.grow > 0.01
    readonly property real blobX: root._lobe ? card.x : 0
    readonly property real blobY: root._lobe ? card.y : 0
    readonly property real blobW: root._lobe ? card.width  : 0
    readonly property real blobH: root._lobe ? card.height : 0

    property string key:  ""
    property real   main: 0

    function _sync() {
        if (!root.open) return
        root.key = root.strip.previewKey
        if (root.anchorMain >= 0) root.main = root.anchorMain
    }

    // Arriving, the card lands in place and fades up; only once it's already
    // showing does it GLIDE to the next button.
    property bool _glide: false
    onOpenChanged: {
        if (!root.open && root.peeks) {
            peekTimer.stop()
            root._peekWant = ""
            UiState.dockPeek = ""
        }
        if (root.open) {
            root._sync()
            Qt.callLater(() => root._glide = root.open)
        } else {
            root._glide = false
        }
    }
    onAnchorMainChanged: root._sync()
    // Gliding to another app, the box travels and the new app's content fades up
    // inside it, rather than the old one's snapping to the new one mid-flight.
    onKeyChanged: if (root._glide) swapAnim.restart()
    Connections {
        target: root.strip
        function onPreviewKeyChanged() { root._sync() }
    }

    // The strip's view — a per-monitor dock previews only this screen's windows.
    readonly property var group: root.strip && !root.special ? root.strip.groupFor(root.key) : null
    readonly property bool thumbnails: Config.dockPreviews && root.group !== null
    // Thumbnails off: Windows' fallback — a list of the app's windows by title.
    readonly property bool windowList: !Config.dockPreviews && root.group !== null

    // The dock's own buttons (launcher, Downloads, Trash) borrow the label.
    readonly property bool special: root.key.startsWith("__")
    readonly property var labelFile: root.strip && root.key.startsWith("__file:")
        ? root.strip.fileFor(root.key) : null
    readonly property string labelName:
          root.labelFile             ? root.labelFile.name
        : root.key === "__pin"       ? "Pin to dock"
        : root.key === "__launcher"  ? "Apps"
        : root.key === "__keep"      ? (UiState.dockRevealed ? Translation.tr("Dock kept out") : Translation.tr("Keep dock out"))
        : root.key === "__overview"  ? Translation.tr("Overview")
        : root.key === "__downloads" ? "Downloads"
        : root.key === "__trash"     ? "Trash"
        :                              Taskbar.nameFor(root.key)
    readonly property string labelCaption: {
        if (root.labelFile) return (root.labelFile.dir ? "Folder" : "File") + " · click to open, right-click for more"
        if (root.key === "__pin")       return "Drop files or folders here to keep them on the dock"
        if (root.key === "__launcher")  return "Every app — click, or your launcher keybind"
        if (root.key === "__keep")      return UiState.dockRevealed ? Translation.tr("Click to let it auto-hide again")
                                                                    : Translation.tr("Click to stop it auto-hiding")
        if (root.key === "__overview")  return Translation.tr("Every window and workspace")
        if (root.key === "__downloads") return "Click for your newest files"
        if (root.key === "__trash")     return Places.trashFull
            ? Places.trashCount + (Places.trashCount === 1 ? " item" : " items") + " · drop files here"
            : "Empty · drop files here to throw them away"
        if (root.group) return root.group.count === 1 ? "1 window" : root.group.count + " windows"
        return Taskbar.canPin(root.key) ? "Not running · click to open" : "Can't launch — no desktop entry"
    }

    // The window list's width: a tile's, so switching the setting doesn't
    // change how wide the card is.
    readonly property int listW: root.tileIdeal + Tokens.spacingXxl

    // ══ Geometry ══════════════════════════════════════════════════════════════
    readonly property int gap:     Tokens.spacingMd     // between tiles
    // From the dock's face. Fused, NONE: the card sits flush against the dock, so
    // the blob welds two touching boxes (a clean join, filleted at the corners)
    // instead of bridging a gap with a neck — which read as a bump.
    readonly property int standOff: root.fused ? 0 : Tokens.spacingMd
    readonly property int margin:  Tokens.spacingMd     // from the screen's edge
    readonly property int pad:     Tokens.spacingSm     // card → tiles
    readonly property int tilePad: Tokens.spacingSm     // tile → its contents
    readonly property int headerH: Tokens.iconMd + Tokens.spacingSm

    // Layout sizes rather than spacing, so named here like BarPanelDock's
    // panelWidth: the tile a window gets when there's room, and the smallest one
    // that's still recognisable as a picture of that window.
    readonly property int tileIdeal: 300
    readonly property int tileMin:   168

    // Melted, inside the dock's length (spanLo/spanHi): along a bottom dock that
    // caps the row's width; beside a side dock it caps the card's HEIGHT, which the
    // thumbnail's 16:9 turns into a cap on the tile's width (tileCapByHeight).
    readonly property bool contained: root.fused && root.spanHi > root.spanLo

    // ── Clear of the dock's ENDS ──────────────────────────────────────────────
    // A melted card whose end lands on (or near) the dock's end puts two rounded
    // corners on one line, and the smooth-min blends them into a bump — what an
    // app at either end of the dock used to get. Kept `endInset` inside instead
    // (the blob's reach plus a corner), the dock keeps its own clean rounded end and
    // the card meets its face with an ordinary fillet. Only a card too long for the
    // inset room falls back to the dock's full length.
    readonly property real endInset: Morph.smoothing + Tokens.radiusCard
    readonly property real spanLen: root.contained
        ? Math.max(0, root.spanHi - root.spanLo - root.endInset * 2) : Infinity
    function _alongClamp(v, len) {
        const lo = root.spanLo + root.endInset, hi = root.spanHi - root.endInset
        return len <= hi - lo ? root._clamp(v, lo, hi - len)
                              : root._clamp(v, root.spanLo, root.spanHi - len)
    }
    readonly property bool hasMedia: (Taskbar.players[root.key] ?? null) !== null
    readonly property real mediaH: root.hasMedia ? Tokens.spacingSm + Tokens.iconXl : 0
    readonly property real tileCapByHeight: {
        if (!root.contained || !root.vertical) return Infinity
        const thumbRoom = root.spanLen - root.pad * 2 - root.mediaH
                        - root.tilePad * 2 - root.headerH - Tokens.spacingSm
        return Math.max(Tokens.iconXl * 2, thumbRoom * 16 / 9 + root.tilePad * 2)
    }

    // Room along the row the tiles are laid in (always a row — a side dock's card
    // grows sideways into the screen, which is where the room is).
    readonly property real availW:
          root.edge === "left"  ? root.width - root.dockInner - root.standOff - root.margin
        : root.edge === "right" ? root.dockInner - root.standOff - root.margin
        :                         Math.min(root.width - root.margin * 2, root.spanLen)

    // The height cap wins even below tileMin: a smaller picture beats one that
    // hangs off the end of the dock.
    readonly property int tileW: Math.floor(Math.min(root.tileCapByHeight,
        DockJs.tileSize(root.group ? root.group.count : 0,
                        root.availW - root.pad * 2, root.tileIdeal,
                        root.contained && !root.vertical ? 0 : root.tileMin, root.gap)))
    readonly property int thumbW: root.tileW - root.tilePad * 2
    readonly property int thumbH: Math.round(root.thumbW * 9 / 16)

    // ── A window squeezed by its neighbours ───────────────────────────────────
    // Every tile is the 16:9 box above — except a TILED window that isn't 16:9
    // because others share its workspace (two side by side are each about square).
    // Letterboxed, that one was a sliver in a wide box; it gets a tile of its own
    // shape at the row's height instead. A floating window of an odd shape keeps
    // the box: its shape isn't the layout's doing. The shape comes from the
    // capture once it lands (`_aspects`), Hyprland's geometry before that.
    property var _aspects: ({})
    function setAspect(address, a) {
        if (Math.abs((root._aspects[address] ?? 0) - a) < 0.01) return
        const next = Object.assign({}, root._aspects)
        next[address] = a
        root._aspects = next
    }
    function aspectOf(t) {
        const a = root._aspects[t.address]
        if (a) return a
        const g = Hypr.geometryOf(t)
        return DockJs.thumbAspect(g.width, g.height)
    }
    // How far off its monitor's own shape counts as squeezed (a full-size window
    // on a 16:9 screen is ~1.8; half of it, ~0.9). Against the MONITOR, not a
    // literal 16:9, so a full-size window on an ultrawide isn't "squeezed".
    readonly property real squeezeTolerance: 0.25
    function squeezed(t) {
        if (Hypr.geometryOf(t).floating) return false
        const u = Hypr.usableSize(t.monitor)
        const screen = u.height > 0 ? u.width / u.height : 16 / 9
        return Math.abs(root.aspectOf(t) - screen) > root.squeezeTolerance
    }

    // The card's resting size, which x/y are computed from — NOT its animated
    // size. Positioning off the animated width would move the target every frame
    // of a resize and the position's own Behavior would spend it chasing.
    readonly property real cardW: body.implicitWidth  + root.pad * 2
    readonly property real cardH: body.implicitHeight + root.pad * 2

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    Item {
        id: maskBox
        x: card.x
        y: card.y
        width:  root.shown ? card.width  : 0
        height: root.shown ? card.height : 0
    }

    // ══ The card ══════════════════════════════════════════════════════════════
    Surface {
        id: card

        // Popup elevation for its SHADOW (it floats above the dock), but the
        // standard surface for its fill — the same material as the panels and the
        // dock. Popup elevation alone maps to Colors.surfaceHigh, a lighter tone
        // that made the card read as a different kind of thing.
        elevation:    Tokens.elevationPopup
        color:        root.fused ? Colors.of(QsWindow.window).frameFill : Colors.of(QsWindow.window).surface
        cornerRadius: Tokens.radiusCard
        // No accent outline while open: it made the card's edge a different colour
        // (and weight) from the dock's own. See strokeColor.
        focused:      false
        borderColor:  root.strokeColor
        // Fused: a lobe of the frame — no outline, no shadow (the blob draws the
        // one continuous outline), clipped as it grows.
        borderWidth:  root.fused ? 0 : root.strokeWidth
        castsShadow:  !root.fused
        clip:         root.fused

        // Where the card rests fully out…
        readonly property real restX:
              root.edge === "left"  ? root.dockInner + root.standOff
            : root.edge === "right" ? root.dockInner - root.standOff - root.cardW
            : root.contained ? root._alongClamp(root.main - root.cardW / 2, root.cardW)
            : root._clamp(root.main - root.cardW / 2, root.margin, root.width - root.cardW - root.margin)
        readonly property real restY: root.vertical
            ? (root.contained ? root._alongClamp(root.main - root.cardH / 2, root.cardH)
                              : root._clamp(root.main - root.cardH / 2, root.margin, root.height - root.cardH - root.margin))
            : root.dockInner - root.standOff - root.cardH

        // …and, fused, how much of that has grown out of the dock's side (depth,
        // `grow`) and along it (`narrow`, centred on the icon inside the rest box).
        readonly property real fullAlong: root.vertical ? root.cardH : root.cardW
        readonly property real along: !root.fused ? card.fullAlong
            : Math.min(card.fullAlong, root.bud + (card.fullAlong - root.bud) * root.narrow)
        readonly property real alongPos: {
            const lo = root.vertical ? card.restY : card.restX
            return root._clamp(root.main - card.along / 2, lo, lo + card.fullAlong - card.along)
        }
        width:  !root.fused ? root.cardW : root.vertical ? root.cardW * root.grow : card.along
        height: !root.fused ? root.cardH : root.vertical ? card.along : root.cardH * root.grow
        x: !root.fused ? card.restX
         : root.edge === "right" ? card.restX + root.cardW * (1 - root.grow)
         : root.vertical ? card.restX : card.alongPos
        y: !root.fused ? card.restY
         : root.vertical ? card.alongPos
         : card.restY + root.cardH * (1 - root.grow)

        transform: Matrix4x4 { matrix: root.deformMatrix }

        Behavior on x      { enabled: root._glide && (!root.fused || root.melted); NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
        Behavior on y      { enabled: root._glide && (!root.fused || root.melted); NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
        Behavior on width  { enabled: root._glide && (!root.fused || root.melted); NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
        Behavior on height { enabled: root._glide && (!root.fused || root.melted); NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }

        opacity: root.fused ? 1 : (root.open ? 1 : 0)
        scale:   root.fused || root.open ? 1.0 : 0.94
        // Grows out of the dock, not out of its own middle.
        transformOrigin: root.edge === "left"  ? Item.Left
                       : root.edge === "right" ? Item.Right
                       :                         Item.Bottom
        visible: root.shown
        // Nothing on a card that's leaving may still take a click.
        enabled: root.open

        Behavior on opacity {
            NumberAnimation { duration: Motion.surfaceDuration(root.open)
                              easing.type: Motion.surfaceEasing(root.open) }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.surfaceDuration(root.open)
                              easing.type: Motion.surfaceEasing(root.open) }
        }

        HoverHandler { id: cardHover }

        Item {
            id: body
            // Fused, it stays where the whole card would put it while the box
            // narrows round it (the clip trims it), so nothing slides sideways.
            // (Not once melted: then the box glides between apps and the content
            // rides it — the offset is 0 at that moment, so nothing jumps.)
            x: root.pad + (root.fused && !root.melted && !root.vertical ? card.restX - card.x : 0)
            y: root.pad + (root.fused && !root.melted && root.vertical  ? card.restY - card.y : 0)
            // Fused, only in the last half of the melt: it arrives once there's a
            // card round it, and is gone before the card pinches in on it.
            opacity: (root.fused ? Math.max(0, Math.min(root.grow, root.narrow) * 2 - 1) : 1) * body.swap
            property real swap: 1
            NumberAnimation {
                id: swapAnim
                target: body; property: "swap"; from: 0; to: 1
                duration: Motion.standard; easing.type: Motion.enter
            }
            readonly property real mainW: root.thumbnails ? tiles.implicitWidth
                                        : root.windowList ? list.implicitWidth : label.implicitWidth
            readonly property real mainH: root.thumbnails ? tiles.implicitHeight
                                        : root.windowList ? list.implicitHeight : label.implicitHeight
            implicitWidth:  Math.max(body.mainW, media.visible ? media.minW : 0)
            implicitHeight: body.mainH + (media.visible ? Tokens.spacingSm + media.height : 0)

            Row {
                id: tiles
                visible: root.thumbnails
                spacing: root.gap

                Repeater {
                    // Diffed by identity, so a tile — and its live capture — lives as
                    // long as its window does, across every regroup in between.
                    // Built the moment it opens (so the card's first frame is already
                    // the right size) and empty once it has faded out: no captures
                    // while unseen.
                    model: ScriptModel {
                        values: (root.open || root.shown) && root.thumbnails ? root.group.windows : []
                    }
                    delegate: Tile {}
                }
            }

            // ── Thumbnails off: the windows by title ──────────────────────────
            Column {
                id: list
                visible: root.windowList
                spacing: Tokens.spacingXs

                StyledText {
                    leftPadding: Tokens.spacingSm
                    text: root.labelName
                    variant: "caption"
                    emphasis: "dim"
                }

                Repeater {
                    model: ScriptModel {
                        values: (root.open || root.shown) && root.windowList ? root.group.windows : []
                    }
                    delegate: WindowRow {}
                }
            }

            Column {
                id: label
                visible: !root.thumbnails && !root.windowList
                spacing: Tokens.spacingXs
                leftPadding:   Tokens.spacingSm
                rightPadding:  Tokens.spacingSm
                topPadding:    Tokens.spacingXs
                bottomPadding: Tokens.spacingXs

                StyledText {
                    text: root.labelName
                    variant: "label"
                    font.bold: true
                }
                StyledText {
                    text: root.labelCaption
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            // ── Now playing ───────────────────────────────────────────────────
            // An app with a media player gets Windows' thumbnail toolbar: what's
            // playing, and previous / play-pause / next — without switching to it.
            Item {
                id: media
                readonly property var player: Taskbar.players[root.key] ?? null
                readonly property real minW: Tokens.iconXl * 3 + Tokens.spacingXs * 2 + root.tileMin

                visible: root.hasMedia
                y: body.mainH + Tokens.spacingSm
                width:  body.width
                height: Tokens.iconXl

                MaterialIcon {
                    id: note
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    name: "music_note"
                    color: Colors.of(QsWindow.window).primary
                    font.pixelSize: Tokens.iconMd
                }

                StyledText {
                    anchors.left: note.right
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.right: controls.left
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property string artist: media.player?.trackArtist ?? ""
                    text: (media.player?.trackTitle || media.player?.identity || "")
                        + (artist !== "" ? "  ·  " + artist : "")
                    variant: "caption"
                    emphasis: "muted"
                    elide: Text.ElideRight
                }

                Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacingXs

                    MediaButton {
                        symbol: "skip_previous"
                        available: media.player?.canGoPrevious ?? false
                        onClicked: Taskbar.media(root.key, "previous")
                    }
                    MediaButton {
                        symbol: media.player?.isPlaying ? "pause" : "play_arrow"
                        available: media.player?.canTogglePlaying ?? false
                        onClicked: Taskbar.media(root.key, "toggle")
                    }
                    MediaButton {
                        symbol: "skip_next"
                        available: media.player?.canGoNext ?? false
                        onClicked: Taskbar.media(root.key, "next")
                    }
                }
            }
        }
    }

    // One window, by title — the list mode's row. Click goes there, middle-click
    // or × closes it, the focused one is marked, as the tiles do.
    component WindowRow: Item {
        id: wrow
        required property var modelData
        readonly property bool active: wrow.modelData.activated
        readonly property bool hot: rowMouse.containsMouse || rowClose.containsMouse

        width:  root.listW
        height: Tokens.fieldHeight

        StateLayer {
            id: rowWash
            anchors.fill: parent
            radius: Tokens.radiusSm
            layerColor: Colors.of(QsWindow.window).fg
            hovered: wrow.hot
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width:  Tokens.spacingXs
            height: parent.height - Tokens.spacingMd * 2
            radius: width / 2
            color: Colors.of(QsWindow.window).focus
            visible: wrow.active
        }

        Image {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: Tokens.spacingMd
            anchors.verticalCenter: parent.verticalCenter
            source: Taskbar.iconFor(root.key)
            visible: source.toString() !== ""
            width:  Tokens.iconMd
            height: Tokens.iconMd
            sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
        }

        StyledText {
            anchors.left: rowIcon.right
            anchors.leftMargin: Tokens.spacingSm
            anchors.right: rowX.left
            anchors.rightMargin: Tokens.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            text: wrow.modelData.title !== "" ? wrow.modelData.title : root.labelName
            variant: "label"
            emphasis: wrow.active ? "normal" : "muted"
            elide: Text.ElideRight
        }

        MaterialIcon {
            id: rowX
            anchors.right: parent.right
            anchors.rightMargin: Tokens.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅖"
            variant: "label"
            opacity: wrow.hot ? 1 : 0
            color: rowClose.containsMouse ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: root.peekHover(wrow.modelData, rowMouse.containsMouse)
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: m => rowWash.press(m.x, m.y)
            onReleased: rowWash.release()
            onCanceled: rowWash.release()
            onClicked: function(m) {
                if (m.button === Qt.MiddleButton) { Taskbar.close(wrow.modelData); return }
                if (m.button === Qt.RightButton) {
                    Taskbar.bringHere(wrow.modelData, root.monitor)
                    root.strip?.closePreview()
                    root.activated()
                    return
                }
                Taskbar.focus(wrow.modelData, root.monitor)
                root.strip?.closePreview()
                root.activated()
            }
        }
        MouseArea {
            id: rowClose
            anchors.fill: rowX
            anchors.margins: -Tokens.spacingXs
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Taskbar.close(wrow.modelData)
        }
    }

    component MediaButton: Item {
        id: mb
        property string symbol: ""
        property bool   available: true
        signal clicked()

        width:  Tokens.iconXl
        height: Tokens.iconXl
        opacity: mb.available ? 1 : 0.4

        StateLayer {
            id: mbWash
            anchors.fill: parent
            radius: height / 2
            layerColor: Colors.of(QsWindow.window).fg
            hovered: mbMouse.containsMouse && mb.available
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: mb.symbol
            fill: 1
            color: Colors.of(QsWindow.window).fg
            font.pixelSize: Tokens.iconLg
        }
        MouseArea {
            id: mbMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: mb.available
            cursorShape: Qt.PointingHandCursor
            onPressed: m => mbWash.press(m.x, m.y)
            onReleased: mbWash.release()
            onCanceled: mbWash.release()
            onClicked: mb.clicked()
        }
    }

    // ══ One window ════════════════════════════════════════════════════════════
    component Tile: Item {
        id: tile

        required property var modelData            // a HyprlandToplevel

        readonly property bool active: tile.modelData.activated
        readonly property bool hot:    tileMouse.containsMouse || closeMouse.containsMouse
        // The 16:9 box, or — squeezed by tiled neighbours — its own shape at the
        // row's height (see `squeezed` above).
        readonly property int thumbW: root.squeezed(tile.modelData)
            ? Math.round(root.thumbH * root.aspectOf(tile.modelData)) : root.thumbW

        width:  tile.thumbW + root.tilePad * 2
        height: root.tilePad * 2 + root.headerH + Tokens.spacingSm + root.thumbH

        StateLayer {
            id: wash
            anchors.fill: parent
            radius: Tokens.radiusSm
            layerColor: Colors.of(QsWindow.window).fg
            hovered: tile.hot
        }

        // The window that has focus is outlined, as Windows marks the active one.
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: "transparent"
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).focus
            opacity: tile.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        // ── Header: app icon, title ───────────────────────────────────────────
        Row {
            id: header
            x: root.tilePad
            y: root.tilePad
            width: tile.thumbW - closeBox.width - Tokens.spacingXs
            height: root.headerH
            spacing: Tokens.spacingSm

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: Taskbar.iconFor(root.key)
                visible: source.toString() !== ""
                width:  Tokens.iconMd
                height: Tokens.iconMd
                sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
                smooth: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: header.width - Tokens.iconMd - header.spacing
                text: tile.modelData.title !== "" ? tile.modelData.title
                                                  : Taskbar.nameFor(root.key)
                variant: "caption"
                emphasis: tile.active ? "normal" : "muted"
                elide: Text.ElideRight
            }
        }

        // ── Close ─────────────────────────────────────────────────────────────
        // Only while the tile is hovered, as on Windows — a row of × marks on every
        // tile reads as a warning rather than a picture.
        Rectangle {
            id: closeBox
            anchors.right: parent.right
            anchors.rightMargin: root.tilePad
            y: root.tilePad + (root.headerH - closeBox.height) / 2
            width:  Tokens.iconLg
            height: Tokens.iconLg
            radius: Tokens.radiusXs
            color: closeMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.18) : "transparent"
            opacity: tile.hot ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            Behavior on color   { ColorAnimation  { duration: Motion.respond } }

            MaterialIcon {
                anchors.centerIn: parent
                glyph: "󰅖"
                variant: "label"
                color: closeMouse.containsMouse ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
            }
        }

        // ── The window, live ──────────────────────────────────────────────────
        Item {
            id: shotBox
            x: root.tilePad
            y: root.tilePad + root.headerH + Tokens.spacingSm
            width:  tile.thumbW
            height: root.thumbH

            readonly property var fitted: DockJs.fit(view.sourceSize.width, view.sourceSize.height,
                                                     shotBox.width, shotBox.height)

            // Until the first frame lands: the app's icon, so the tile isn't a hole.
            Image {
                anchors.centerIn: parent
                visible: !view.hasContent && source.toString() !== ""
                source: Taskbar.iconFor(root.key)
                width:  Tokens.iconXl
                height: Tokens.iconXl
                sourceSize: Qt.size(Tokens.iconXl, Tokens.iconXl)
                opacity: 0.5
            }

            Item {
                id: shot
                anchors.centerIn: parent
                // Letterboxed to the window's own shape inside the fixed box, so the
                // card keeps one size while captures arrive (see dock.js fit()).
                width:  view.hasContent ? shotBox.fitted.w : shotBox.width
                height: view.hasContent ? shotBox.fitted.h : shotBox.height
                visible: view.hasContent

                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: shotMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                // Mipmapped from a bigger copy: drawn this small, a plain capture shimmers.
                SharpCapture {
                    id: view
                    anchors.fill: parent
                    captureSource: tile.modelData.wayland
                    live: root.open
                    // The capture knows the window's real shape; the tile follows it.
                    onSourceSizeChanged: if (view.sourceSize.width > 0 && view.sourceSize.height > 0)
                        root.setAspect(tile.modelData.address,
                                       DockJs.thumbAspect(view.sourceSize.width, view.sourceSize.height))
                }
            }

            Item {
                id: shotMask
                anchors.fill: shot
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusXs
                    color: "white"
                }
            }

            // Which workspace it's on — the one thing a thumbnail can't show.
            Badge {
                anchors.right:  shot.right
                anchors.bottom: shot.bottom
                anchors.margins: Tokens.spacingXs
                visible: view.hasContent && (tile.modelData.workspace?.id ?? 0) > 0
                label: "" + (tile.modelData.workspace?.id ?? "")
                tint:   tile.active ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgMuted
                filled: true
            }
        }

        // ── Input ─────────────────────────────────────────────────────────────
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: root.peekHover(tile.modelData, tileMouse.containsMouse)
            cursorShape: Qt.PointingHandCursor
            // Left: go to it. Middle: close it. Right: bring it HERE — to the
            // workspace you're on — and focus it.
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: m => wash.press(m.x, m.y)
            onReleased: wash.release()
            onCanceled: wash.release()
            onClicked: function(m) {
                if (m.button === Qt.MiddleButton) {
                    Taskbar.close(tile.modelData)
                    return
                }
                if (m.button === Qt.RightButton) {
                    Taskbar.bringHere(tile.modelData, root.monitor)
                    root.strip?.closePreview()
                    root.activated()
                    return
                }
                Taskbar.focus(tile.modelData, root.monitor)
                root.strip?.closePreview()
                root.activated()
            }
        }

        // Above the tile's own MouseArea, so × wins the click in its corner.
        MouseArea {
            id: closeMouse
            anchors.fill: closeBox
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Taskbar.close(tile.modelData)
        }
    }
}
