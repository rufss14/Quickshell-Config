pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../services/snip.js" as P

// ── SnipOverlay ───────────────────────────────────────────────────────────────
// One screen's side of the snip tool (services/Snip): the frozen picture, a dim over
// everything but the selection, and — once something is selected — a toolbar beside it.
//
//   drag            select a box          click   select the window under the pointer
//   handles / inside  resize / move it    F       the whole screen
//   toolbar button  do that action         Enter   do the highlighted one
//   Esc / right-click   clear the selection, then leave
//
// That is the whole interface: there is no mode to pick and nothing to switch on first.
//
// ── Every screen shows its still, one takes the keys ──────────────────────────
// So the selection can start on any monitor. Keyboard focus is Exclusive on ONE of them
// (ScreenOwner — the screen you were on when it opened), and each window has a namespace
// of its own: two layer surfaces sharing one fight over the keyboard.
//
// ── The dim never reaches the screenshot ──────────────────────────────────────
// grim captures the screen BEFORE any overlay exists, and every action crops from that file —
// never from what is on screen — so the scrim, the outline, the handles and the toolbar can
// look however they like. The scrim is a fade of the shell's constant black (Colors.shadow),
// strong enough to read over dark windows, with the selection cut out of it.
//
// ── The loupe is a GPU copy, not a second Image ───────────────────────────────
// The first loupe was an Image with `sourceClipRect` on the same file. Qt re-reads and
// re-clips the WHOLE file on the CPU whenever that rectangle changes, and it pinned the main
// thread at 100% (measured: the shell went from ~35% to ~103% of a core, a few frames a
// second — "extremely low frame" on open). A ShaderEffectSource of the already-uploaded still
// costs the GPU a sampling pass and nothing else. It also shows only while you are dragging —
// that is when pixel accuracy matters; a loupe following the pointer all the time is just in
// the way.
//
// ── The picture is a file, named per snip ─────────────────────────────────────
// Snip names it with a session id, so Image's URL-keyed cache can never show an earlier
// snip's screen.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-snip-" + P.safeName(win.screen?.name)
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.owns && Snip.open ? WlrKeyboardFocus.Exclusive
                                                       : WlrKeyboardFocus.None

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true
    color: "transparent"

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: Snip.open
    }

    // Mapped only once the still has loaded, so the freeze never shows half a frame.
    visible: Snip.open && still.status === Image.Ready

    // Image pixels per logical pixel on this output.
    readonly property real pxScale: still.sourceSize.width > 0 && win.width > 0
                                    ? still.sourceSize.width / win.width : 1

    // The screen the pointer is on shows the hint and the toolbar.
    readonly property bool active: Snip.activeScreen === (win.screen?.name ?? "")
    readonly property int  handleSize: Tokens.spacingLg

    // ── Windows under the pointer ─────────────────────────────────────────────
    readonly property var hyprMon: Hyprland.monitorFor(win.screen)
    readonly property int ws: hyprMon?.activeWorkspace?.id ?? -1
    readonly property var winRects: {
        if (!Snip.open) return []
        const out = []
        const wins = Hypr.windows
        for (let i = 0; i < wins.length; i++) {
            if (wins[i].workspaceId !== win.ws) continue
            out.push({ x: wins[i].at[0] - win.screen.x, y: wins[i].at[1] - win.screen.y,
                       w: wins[i].size[0], h: wins[i].size[1], label: wins[i].appClass || wins[i].title || "" })
        }
        return out
    }

    // ── The pointer and the gesture in progress ───────────────────────────────
    property point pointer: Qt.point(-1, -1)
    property bool  pointerIn: false
    // "" · "create" · "move" · a handle name ("nw", "e", …)
    property string gesture: ""
    property point  from: Qt.point(0, 0)
    property var    origRect: null

    readonly property var sel: Snip.selScreen === (win.screen?.name ?? "") ? Snip.selRect : null
    readonly property var hovered: (win.sel === null && Snip.selRect === null && win.pointerIn && win.gesture === "")
                                   ? P.windowAt(win.winRects, win.pointer.x, win.pointer.y) : null
    readonly property bool selIsWindow: win.sel === null && win.hovered !== null
    readonly property var  shown: win.sel !== null ? win.sel : win.hovered

    // What the pointer would grab right now, for the cursor.
    readonly property string overHit: (win.sel !== null && win.pointerIn)
                                      ? P.hitHandle(win.sel, win.pointer.x, win.pointer.y, win.handleSize) : ""
    readonly property var cursors: ({
        sizeFDiag: Qt.SizeFDiagCursor, sizeBDiag: Qt.SizeBDiagCursor, sizeVer: Qt.SizeVerCursor,
        sizeHor: Qt.SizeHorCursor, sizeAll: Qt.SizeAllCursor, cross: Qt.CrossCursor
    })

    // The size chip's menu (a ratio to lock, an exact size to type).
    property bool menuOpen: false
    onMenuOpenChanged: if (!win.menuOpen) keys.forceActiveFocus()
    onSelChanged: if (win.sel === null) win.menuOpen = false

    function _reset() {
        win.gesture = ""
        win.origRect = null
        win.menuOpen = false
    }
    Connections {
        target: Snip
        function onOpenChanged() { if (!Snip.open) win._reset() }
    }

    // The screen the snip opened on is the active one before the pointer has moved, so the
    // hint shows at once and `select`/F have a screen to work on.
    onVisibleChanged: if (win.visible && win.active) Snip.pointerOn(win.screen, win.pxScale)
    onPxScaleChanged: if (win.visible && win.active) Snip.pointerOn(win.screen, win.pxScale)

    function _select(rect) {
        const r = P.clampRect(rect, win.width, win.height)
        if (r !== null) Snip.setSelection(win.screen, r, win.pxScale)
    }

    // ── The still ─────────────────────────────────────────────────────────────
    Image {
        id: still
        anchors.fill: parent
        source: Snip.open ? "file://" + Snip.imageFor(win.screen.name) : ""
        asynchronous: true
        fillMode: Image.Stretch
        smooth: false
    }

    // ── Things that arrive ────────────────────────────────────────────────────
    // Every piece of chrome eases in on one of these (0 → 1), so nothing just appears.
    // `scrim` fades the dim up as the freeze lands; `selAppear` brings the outline and handles
    // in with the spring the dock uses, when a selection starts; `chrome` does the same for the
    // toolbar once it is settled (never while a drag or resize is in progress).
    property real scrim: win.visible ? 1 : 0
    Behavior on scrim { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }
    property real selAppear: win.sel !== null ? 1 : 0
    Behavior on selAppear {
        NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring; easing.type: Easing.BezierSpline }
    }
    property real chrome: win.sel !== null && win.gesture === "" ? 1 : 0
    Behavior on chrome {
        NumberAnimation { duration: Motion.emphasized; easing.bezierCurve: Motion.spring; easing.type: Easing.BezierSpline }
    }
    property real hintAppear: win.active && Snip.selRect === null && win.gesture === "" ? 1 : 0
    Behavior on hintAppear {
        NumberAnimation { duration: Motion.emphasized; easing.bezierCurve: Motion.spring; easing.type: Easing.BezierSpline }
    }

    // ── The dim, with the selection left bright ───────────────────────────────
    readonly property color dimColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.58)
    Rectangle { anchors.fill: parent; color: win.dimColor; visible: win.shown === null; opacity: win.scrim }
    Item {
        anchors.fill: parent
        opacity: win.scrim
        visible: win.shown !== null
        readonly property real sx: win.shown ? win.shown.x : 0
        readonly property real sy: win.shown ? win.shown.y : 0
        readonly property real sw: win.shown ? win.shown.w : 0
        readonly property real sh: win.shown ? win.shown.h : 0
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.sy; color: win.dimColor }
        Rectangle { x: 0; y: parent.sy + parent.sh; width: parent.width
                    height: parent.height - parent.sy - parent.sh; color: win.dimColor }
        Rectangle { x: 0; y: parent.sy; width: parent.sx; height: parent.sh; color: win.dimColor }
        Rectangle { x: parent.sx + parent.sw; y: parent.sy
                    width: parent.width - parent.sx - parent.sw; height: parent.sh; color: win.dimColor }
    }

    // ── Crosshair lines, while nothing is selected ────────────────────────────
    readonly property color guideColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.35)
    readonly property bool guides: win.pointerIn && win.sel === null && win.hovered === null
    Rectangle { visible: win.guides; x: 0; y: win.pointer.y; width: parent.width; height: Tokens.borderWidth; color: win.guideColor }
    Rectangle { visible: win.guides; x: win.pointer.x; y: 0; width: Tokens.borderWidth; height: parent.height; color: win.guideColor }

    // ── The outline (a window's gets the card corner and its name) ────────────
    Rectangle {
        visible: win.shown !== null
        opacity: win.scrim
        x: win.shown ? win.shown.x : 0
        y: win.shown ? win.shown.y : 0
        width: win.shown ? win.shown.w : 0
        height: win.shown ? win.shown.h : 0
        color: "transparent"
        radius: win.selIsWindow ? Tokens.radiusCard : 0
        border.width: win.selIsWindow ? Tokens.borderChrome * 2 : Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).focus
        Behavior on x      { enabled: win.selIsWindow; NumberAnimation { duration: Motion.respond } }
        Behavior on y      { enabled: win.selIsWindow; NumberAnimation { duration: Motion.respond } }
        Behavior on width  { enabled: win.selIsWindow; NumberAnimation { duration: Motion.respond } }
        Behavior on height { enabled: win.selIsWindow; NumberAnimation { duration: Motion.respond } }
    }
    Rectangle {
        visible: win.selIsWindow && win.hovered.label !== ""
        x: win.hovered ? win.hovered.x + Tokens.spacingMd : 0
        y: win.hovered ? win.hovered.y + Tokens.spacingMd : 0
        width: windowLabel.implicitWidth + Tokens.spacingMd * 2
        height: windowLabel.implicitHeight + Tokens.spacingXs * 2
        radius: height / 2
        color: Colors.of(QsWindow.window).focus
        StyledText {
            id: windowLabel
            anchors.centerIn: parent
            text: win.hovered ? win.hovered.label : ""
            variant: "caption"
            color: Colors.of(QsWindow.window).fgOnPrimary
        }
    }

    // ── Handles ───────────────────────────────────────────────────────────────
    Repeater {
        model: win.sel !== null ? P.HANDLES : []
        Rectangle {
            required property string modelData
            readonly property var at: win.sel ? P.handlePoints(win.sel)[modelData] : ({ x: 0, y: 0 })
            // A handle on a tiny box would hide the box: edges drop out below 40px.
            visible: win.sel !== null && (modelData.length === 2
                     || (modelData === "n" || modelData === "s" ? win.sel.w > 40 : win.sel.h > 40))
            x: at.x - width / 2
            y: at.y - height / 2
            // Corners are round knobs; an edge is a short pill lying along it (M3E's drag
            // handle), so which handle does what reads before you touch it.
            readonly property bool edgeH: modelData === "n" || modelData === "s"
            readonly property bool edgeV: modelData === "e" || modelData === "w"
            width:  edgeH ? win.handleSize * 2 : win.handleSize - Tokens.spacingXs
            height: edgeV ? win.handleSize * 2 : win.handleSize - Tokens.spacingXs
            scale: win.selAppear
            opacity: win.selAppear
            radius: Math.min(width, height) / 2
            color: Colors.of(QsWindow.window).primary
            border.width: Tokens.borderChrome
            border.color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard)
        }
    }

    // ── The toolbar sits below the selection, or above when there's no room ───
    readonly property real tbGap: Tokens.spacingMd
    readonly property bool toolbarBelow: win.sel !== null
        && win.sel.y + win.sel.h + win.tbGap + toolbar.height + Tokens.spacingXl <= win.height

    // ── The loupe: the pixels under the pointer, while you drag ───────────────
    // See the header for why this is a ShaderEffectSource. 15 px across at 8×, with the middle
    // one boxed. At a fractional output scale it samples the still's logical pixels (a touch
    // soft) — the crop itself always comes from the real file.
    readonly property int loupeSize: 120
    readonly property int loupePx: 15
    Surface {
        id: loupe
        visible: win.pointerIn && win.gesture !== "" && win.gesture !== "move"
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusCard
        clip: true
        width: win.loupeSize + Tokens.spacingXs * 2
        height: win.loupeSize + Tokens.spacingXs * 2
        x: win.pointer.x + Tokens.spacingXxl + width > win.width ? win.pointer.x - Tokens.spacingXxl - width
                                                                    : win.pointer.x + Tokens.spacingXxl
        y: win.pointer.y + Tokens.spacingXxl + height > win.height ? win.pointer.y - Tokens.spacingXxl - height
                                                                    : win.pointer.y + Tokens.spacingXxl

        ShaderEffectSource {
            x: Tokens.spacingXs
            y: Tokens.spacingXs
            width: win.loupeSize
            height: win.loupeSize
            sourceItem: still
            sourceRect: Qt.rect(Math.max(0, Math.min(win.width - win.loupePx, Math.round(win.pointer.x) - Math.floor(win.loupePx / 2))),
                                Math.max(0, Math.min(win.height - win.loupePx, Math.round(win.pointer.y) - Math.floor(win.loupePx / 2))),
                                win.loupePx, win.loupePx)
            smooth: false
            // Only built while the loupe is up (the Surface's `visible`); the still never
            // changes, so a live source costs a re-grab of 15×15 px when the pointer moves.
            live: true
        }
        Rectangle {
            anchors.centerIn: parent
            width: win.loupeSize / win.loupePx
            height: width
            color: "transparent"
            border.width: Tokens.borderChrome
            border.color: Colors.of(QsWindow.window).focus
        }
    }

    // ── Input ─────────────────────────────────────────────────────────────────
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: win.gesture !== "" && win.gesture !== "create"
                     ? win.cursors[P.cursorFor(win.gesture)]
                     : win.cursors[P.cursorFor(win.overHit)]

        onContainsMouseChanged: {
            win.pointerIn = mouse.containsMouse
            if (mouse.containsMouse) Snip.pointerOn(win.screen, win.pxScale)
        }

        onPositionChanged: function (m) {
            win.pointer = Qt.point(m.x, m.y)
            if (win.gesture === "") return
            if (win.gesture === "create") {
                if (P.movedEnough(win.from, win.pointer))
                    win._select(Snip.ratio > 0 ? P.ratioFromAnchor(win.from, win.pointer, Snip.ratio, win.width, win.height)
                                               : P.rectFromPoints(win.from, win.pointer))
                return
            }
            // Moving or resizing the selection that is already up.
            const dx = m.x - win.from.x, dy = m.y - win.from.y
            win._select(win.gesture === "move" ? P.moveRect(win.origRect, dx, dy, win.width, win.height)
                      : Snip.ratio > 0 ? P.resizeRatio(win.origRect, win.gesture, dx, dy, Snip.ratio, win.width, win.height)
                                       : P.resizeRect(win.origRect, win.gesture, dx, dy, win.width, win.height))
        }

        onPressed: function (m) {
            win.pointer = Qt.point(m.x, m.y)
            Snip.pointerOn(win.screen, win.pxScale)
            // A click anywhere else closes the size menu and does nothing more.
            if (win.menuOpen) { win.menuOpen = false; return }
            if (m.button === Qt.RightButton) {
                if (Snip.selRect !== null) Snip.clearSelection(); else Snip.close()
                return
            }
            win.from = Qt.point(m.x, m.y)
            if (win.sel !== null) {
                const hit = P.hitHandle(win.sel, m.x, m.y, win.handleSize)
                if (hit !== "") {
                    win.gesture = hit
                    win.origRect = win.sel
                    return
                }
            }
            win.gesture = "create"
        }

        onReleased: function (m) {
            if (m.button !== Qt.LeftButton) return
            win.pointer = Qt.point(m.x, m.y)
            const g = win.gesture
            win.gesture = ""
            if (g !== "create") return                       // adjusted, or nothing: stays as it is
            if (P.movedEnough(win.from, win.pointer)) return  // a drag: the selection is already up
            // A click: the window under the pointer, or nothing (which clears).
            const w = P.windowAt(win.winRects, m.x, m.y)
            if (w !== null) win._select(w)
            else Snip.clearSelection()
        }
    }

    // ── Keys (on an Item: a PanelWindow can't take Keys) ──────────────────────
    Item {
        id: keys
        anchors.fill: parent
        focus: Snip.open && win.owns
        Keys.onPressed: function (event) {
            // The size menu's fields are typing: only Esc (close the menu) is ours.
            if (win.menuOpen) {
                if (event.key === Qt.Key_Escape) { win.menuOpen = false; event.accepted = true }
                return
            }
            const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
            switch (event.key) {
            case Qt.Key_Escape:
                if (Snip.selRect !== null) Snip.clearSelection(); else Snip.close()
                event.accepted = true; return
            case Qt.Key_Return: case Qt.Key_Enter:
                if (Snip.selRect !== null) Snip.commitSelection()
                event.accepted = true; return
            case Qt.Key_Left:  Snip.nudge(-step, 0); event.accepted = true; return
            case Qt.Key_Right: Snip.nudge(step, 0);  event.accepted = true; return
            case Qt.Key_Up:    Snip.nudge(0, -step); event.accepted = true; return
            case Qt.Key_Down:  Snip.nudge(0, step);  event.accepted = true; return
            case Qt.Key_F:     Snip.selectWhole();   event.accepted = true; return
            }
            // C / S / E / T / L / R pick that action too (not advertised: the buttons are the
            // interface, these are for people who already know).
            const k = event.text.toUpperCase()
            if (k === "") return
            for (const a of Snip.actions) {
                if (a.key === k) { Snip.pickAction(a.id); event.accepted = true; return }
            }
        }
    }

    // ══ The size, in the picture's own pixels — and the way to change it ══════
    // Drawn ABOVE the pointer's MouseArea (it is clickable now). Opposite side to the toolbar.
    // With a selection up it opens the menu: lock an aspect ratio (the box is cut to it, and every
    // drag and handle after keeps it) or type an exact size. A hovered window has no menu to open.
    readonly property bool chipLive: win.sel !== null
    SurfaceShadow { surface: sizeChip; opacity: sizeChip.opacity; visible: sizeChip.visible }
    Rectangle {
        id: sizeChip
        visible: win.shown !== null && win.shown.w > 48
        x: win.shown ? Math.max(Tokens.spacingMd, Math.min(win.width - width - Tokens.spacingMd, win.shown.x)) : 0
        y: {
            if (!win.shown) return 0
            const above = win.shown.y - height - Tokens.spacingSm
            const below = win.shown.y + win.shown.h + Tokens.spacingSm
            // With a toolbar below, the size goes above (and the other way round).
            return (win.sel === null || win.toolbarBelow)
                   ? (above >= Tokens.spacingMd ? above : win.shown.y + Tokens.spacingSm)
                   : below
        }
        implicitWidth: chipRow.implicitWidth + Tokens.spacingMd * 2
        implicitHeight: Tokens.iconLg + Tokens.spacingSm
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        opacity: win.scrim
        color: win.menuOpen ? Colors.of(QsWindow.window).primaryContainer
                            : Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        StateLayer {
            id: chipFeel
            anchors.fill: parent
            radius: sizeChip.radius
            hovered: chipMouse.containsMouse && win.chipLive
            layerColor: Colors.of(QsWindow.window).fg
        }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Tokens.spacingSm
            readonly property color fg: win.menuOpen ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                     : Colors.of(QsWindow.window).fg
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Snip.ratio > 0 ? "lock" : "crop"
                font.pixelSize: Tokens.iconMd
                color: Snip.ratio > 0 ? Colors.of(QsWindow.window).primary : chipRow.fg
            }
            StyledText {
                id: sizeText
                anchors.verticalCenter: parent.verticalCenter
                text: win.shown ? Math.round(win.shown.w * win.pxScale) + " × " + Math.round(win.shown.h * win.pxScale) : ""
                variant: "caption"
                font.family: Tokens.fontMono
                color: chipRow.fg
            }
            StyledText {
                visible: Snip.ratio > 0
                anchors.verticalCenter: parent.verticalCenter
                text: P.ratioLabel(Snip.ratio)
                variant: "caption"
                font.weight: Font.DemiBold
                color: Colors.of(QsWindow.window).primary
            }
            MaterialIcon {
                visible: win.chipLive
                anchors.verticalCenter: parent.verticalCenter
                name: win.menuOpen ? "expand_less" : "expand_more"
                font.pixelSize: Tokens.iconMd
                color: chipRow.fg
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: win.chipLive
            cursorShape: Qt.PointingHandCursor
            onPressed: function (e) { chipFeel.press(e.x, e.y) }
            onReleased: chipFeel.release()
            onCanceled: chipFeel.release()
            onClicked: win.menuOpen = !win.menuOpen
        }
    }

    // ── The menu ──────────────────────────────────────────────────────────────
    readonly property var ratios: [
        { value: 0,       label: Translation.tr("Free") },
        { value: 1,       label: "1:1" },
        { value: 4 / 3,   label: "4:3" },
        { value: 3 / 2,   label: "3:2" },
        { value: 16 / 9,  label: "16:9" },
        { value: 9 / 16,  label: "9:16" }
    ]
    function _applyTyped() {
        if (win.sel === null) return
        const w = parseInt(typedW.text), h = parseInt(typedH.text)
        Snip.setSize(w > 0 ? w : Math.round(win.sel.w * win.pxScale), h > 0 ? h : Math.round(win.sel.h * win.pxScale))
    }
    SurfaceShadow { surface: sizeMenu; opacity: sizeMenu.opacity; visible: sizeMenu.visible }
    Surface {
        id: sizeMenu
        elevation: Tokens.elevationCard
        cornerRadius: Tokens.radiusXl
        implicitWidth: menuCol.implicitWidth + Tokens.spacingLg * 2
        implicitHeight: menuCol.implicitHeight + Tokens.spacingLg * 2
        width: implicitWidth
        height: implicitHeight
        // Opens on the chip's far side from the selection, or the near one when there is no room.
        x: Math.max(Tokens.spacingMd, Math.min(win.width - width - Tokens.spacingMd, sizeChip.x))
        y: {
            const chipAbove = win.shown !== null && sizeChip.y < win.shown.y
            const out = chipAbove ? sizeChip.y - height - Tokens.spacingSm : sizeChip.y + sizeChip.height + Tokens.spacingSm
            return out >= Tokens.spacingMd && out + height <= win.height - Tokens.spacingMd ? out
                 : (chipAbove ? sizeChip.y + sizeChip.height + Tokens.spacingSm : sizeChip.y - height - Tokens.spacingSm)
        }
        property real appear: win.menuOpen ? 1 : 0
        Behavior on appear { NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring; easing.type: Easing.BezierSpline } }
        visible: appear > 0.01
        opacity: Math.min(1, appear * 1.6) * Tokens.surfaceOpacity
        scale: 0.94 + 0.06 * appear
        transformOrigin: Item.Top

        // A click inside must not reach the pointer layer below (it would close the menu).
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: menuCol
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            StyledText { text: Translation.tr("Aspect ratio"); variant: "caption"; emphasis: "dim" }
            ChipRow {
                Layout.fillHeight: false
                Layout.preferredWidth: Tokens.fieldHeight * 8
                model: win.ratios
                current: Snip.ratio
                onPicked: function (v) { Snip.setRatio(v) }
            }

            StyledText {
                Layout.topMargin: Tokens.spacingXs
                text: Translation.tr("Exact size (pixels)")
                variant: "caption"
                emphasis: "dim"
            }
            RowLayout {
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                InputField {
                    id: typedW
                    Layout.preferredWidth: Tokens.fieldHeight * 3
                    mono: true
                    seed: win.shown ? String(Math.round(win.shown.w * win.pxScale)) : ""
                    onAccepted: win._applyTyped()
                }
                StyledText { text: "×"; emphasis: "dim" }
                InputField {
                    id: typedH
                    Layout.preferredWidth: Tokens.fieldHeight * 3
                    mono: true
                    seed: win.shown ? String(Math.round(win.shown.h * win.pxScale)) : ""
                    onAccepted: win._applyTyped()
                }
                SnipKeyCap { symbol: "keyboard_return" }
            }
        }
    }

    // ══ Before anything is selected: one line saying what to do ═══════════════
    // The shell's own card (elevationCard — the fill NotificationToast, ScreenshotToast and the
    // bar wear, not the lifted Popup grey), as a full pill, rising in on the dock's spring.
    SurfaceShadow { surface: hint; opacity: win.hintAppear }
    Surface {
        id: hint
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingXxl
        anchors.horizontalCenter: parent.horizontalCenter
        elevation: Tokens.elevationCard
        cornerRadius: height / 2
        implicitWidth: hintRow.implicitWidth + Tokens.spacingXl * 2
        implicitHeight: hintRow.implicitHeight + Tokens.spacingMd * 2
        width: implicitWidth
        height: implicitHeight
        opacity: win.hintAppear * Tokens.surfaceOpacity
        visible: win.hintAppear > 0.01
        transform: Translate { y: (1 - win.hintAppear) * Tokens.spacingXl }
        // Four things you can do, each with the key or gesture that does it.
        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: Tokens.spacingXl
            Repeater {
                model: [
                    { symbol: "drag_pan",  key: "", label: Translation.tr("Select an area") },
                    { symbol: "ads_click", key: "", label: Translation.tr("Click a window") },
                    { symbol: "",          key: "F",   label: Translation.tr("Whole screen") },
                    { symbol: "",          key: "Esc", label: Translation.tr("Cancel") }
                ]
                Row {
                    id: hintItem
                    required property var modelData
                    spacing: Tokens.spacingSm
                    SnipKeyCap {
                        anchors.verticalCenter: parent.verticalCenter
                        symbol: hintItem.modelData.symbol
                        text: hintItem.modelData.key
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: hintItem.modelData.label
                        variant: "label"
                    }
                }
            }
        }
    }

    // ══ After: the toolbar, right by the selection ════════════════════════════
    // One button per thing you can do with it, each named. The highlighted one is what Enter
    // does; clicking another does it and becomes the new highlighted one. It grows out of the
    // selection's edge (the side it sits on) with a small overshoot, and its buttons arrive one
    // after another.
    SurfaceShadow { surface: toolbar; opacity: win.chrome }
    Surface {
        id: toolbar
        elevation: Tokens.elevationCard
        cornerRadius: Tokens.radiusXl
        implicitWidth: tbCol.implicitWidth + Tokens.spacingLg * 2
        implicitHeight: tbCol.implicitHeight + Tokens.spacingMd * 2
        width: implicitWidth
        height: implicitHeight

        opacity: Math.min(1, win.chrome * 1.6) * Tokens.surfaceOpacity
        visible: win.chrome > 0.01
        scale: 0.9 + 0.1 * win.chrome
        transformOrigin: win.toolbarBelow ? Item.Top : Item.Bottom
        transform: Translate { y: (win.toolbarBelow ? -1 : 1) * (1 - win.chrome) * Tokens.spacingLg }

        x: win.sel ? Math.max(Tokens.spacingMd, Math.min(win.width - width - Tokens.spacingMd,
                                                          win.sel.x + win.sel.w / 2 - width / 2)) : 0
        y: {
            if (!win.sel) return 0
            if (win.toolbarBelow) return win.sel.y + win.sel.h + win.tbGap
            const above = win.sel.y - height - win.tbGap
            // No room either side (a near-fullscreen selection): inside, at the bottom.
            return above >= Tokens.spacingMd ? above : win.sel.y + win.sel.h - height - win.tbGap
        }

        // A click on the toolbar's own background must not start a new selection.
        MouseArea { anchors.fill: parent }

        // The action under the pointer, for the line below ("" = none).
        property string hoverId: ""

        ColumnLayout {
            id: tbCol
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // Two trays: what you keep (copy, save, edit, pin, live) and what you do with what is in it
                // (read it, translate it, record it). Inside a tray the tiles sit flush.
                Repeater {
                    model: [["copy", "save", "edit", "pin", "livepin"], ["text", "translate", "record"]]
                    Rectangle {
                        id: tray
                        required property var modelData
                        required property int index
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: trayRow.implicitWidth + Tokens.spacingXs * 2
                        implicitHeight: trayRow.implicitHeight + Tokens.spacingXs * 2
                        radius: height / 2
                        color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)

                        Row {
                            id: trayRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            Repeater {
                                model: tray.modelData
                                SnipAction {
                                    id: act
                                    required property string modelData
                                    required property int index
                                    readonly property var spec: Snip.actionById(act.modelData)
                                    // Staggered arrival, in toolbar order.
                                    readonly property int order: Snip.actions.findIndex(a => a.id === act.modelData)
                                    symbol: act.spec.symbol
                                    label: act.spec.label
                                    key: act.spec.key
                                    active: Snip.action === act.modelData
                                    blocked: Snip.blocker(act.modelData)
                                    reveal: Math.max(0, Math.min(1, win.chrome * (Snip.actions.length + 1) - act.order * 0.7))
                                    onActivated: Snip.pickAction(act.modelData)
                                    onHoveredChanged: {
                                        if (act.hovered) toolbar.hoverId = act.modelData
                                        else if (toolbar.hoverId === act.modelData) toolbar.hoverId = ""
                                    }
                                }
                            }
                        }
                    }
                }

                SnipAction {
                    Layout.alignment: Qt.AlignVCenter
                    symbol: "close"
                    reveal: Math.max(0, Math.min(1, win.chrome * (Snip.actions.length + 1) - Snip.actions.length * 0.7))
                    onActivated: Snip.close()
                }
            }

            // Why a button is dead, or what Enter does (what the pointer is over, when it is
            // over a button), each with its key.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                opacity: win.chrome
                readonly property string why: Snip.actions
                    .filter(a => Snip.blocker(a.id) !== "")
                    .map(a => a.label + ": " + Snip.blocker(a.id)).join("   ·   ")
                readonly property var shown: Snip.actionById(toolbar.hoverId !== "" ? toolbar.hoverId : Snip.action)

                SnipKeyCap {
                    visible: parent.why === ""
                    text: toolbar.hoverId !== "" ? parent.shown.key : ""
                    symbol: toolbar.hoverId !== "" ? "" : "keyboard_return"
                }
                StyledText {
                    text: parent.why !== "" ? parent.why : parent.shown.what
                    variant: "caption"
                    emphasis: "dim"
                }
                StyledText {
                    visible: parent.why === ""
                    text: "·"
                    variant: "caption"
                    emphasis: "dim"
                }
                SnipKeyCap { visible: parent.why === ""; text: "Esc" }
                StyledText {
                    visible: parent.why === ""
                    text: Translation.tr("Cancel")
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
    }
}
