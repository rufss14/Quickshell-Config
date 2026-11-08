pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── AnnotateWindow ────────────────────────────────────────────────────────────
// Draw on a screenshot, then copy or save it: pen, highlighter, arrow, box, ellipse, text,
// numbered steps and a blur, in the palette's colours, with undo and redo.
//
// ── One canvas at NATURAL size, scaled for display ────────────────────────────
// The canvas is the size of the image, not the size of the window, and the whole thing
// is scaled down to fit the screen by its parent. Two things fall out of that, both
// load-bearing:
//
//   · `Canvas.save()` writes the canvas at ITS size, so the export is full resolution.
//     A canvas sized to the visible area would quietly downscale every edited
//     screenshot to whatever the window happened to be.
//   · The MouseArea lives INSIDE the scaled item, so its coordinates are already in
//     image space. No mapping, no scale factor to get wrong, and it stays correct when
//     the window resizes.
//
// ── Shapes are a LIST, and the canvas is replayed ─────────────────────────────
// Nothing is drawn destructively. Each stroke is appended to `shapes`, and a repaint
// draws the image and then replays them in order. That is what makes undo one `pop()`
// rather than a stack of saved bitmaps, and it is why the pixelate tool composes
// correctly with everything drawn before it.
//
// The cost is a full replay per repaint, so the in-progress stroke goes on a SECOND,
// empty canvas on top — dragging repaints one shape, not the whole history.
//
// ── Redaction is pixelation, not a black box ──────────────────────────────────
// A filled rectangle over a token is the obvious approach and is a real information
// leak in a different way: it is trivially obvious what you covered, and if the image
// is ever re-exported from a source that kept layers, the box may not travel with it.
// Pixelate destroys the pixels in the exported bitmap.
//
// ── Sizes are in IMAGE pixels, scaled by the image ────────────────────────────
// A 4K capture is twice the pixels of a 1080p one, so a 6 px stroke that reads on the second is a
// hairline on the first. `unit` (image width / 1920, at least 1) multiplies every stroke and every
// piece of text, so the same S / M / L looks the same whatever the screen was.
//
// ── Text is typed where you click ─────────────────────────────────────────────
// A TextInput sits INSIDE the scaled item (so it is in image space like everything else) and
// commits to a shape on Enter or a click elsewhere; Esc drops it. While it is up the window's key
// shortcuts stand down, or typing a "p" would pick the pen.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not
    // redeclared (a `required property var screen` shadowed it; see ScreenOwner).

    // The monitor you were on when it opened — see ScreenOwner.
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: UiState.annotatePath !== ""
    }

    readonly property string path: UiState.annotatePath
    readonly property bool shown: win.path !== "" && win.owns

    WlrLayershell.layer:     WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-annotate"
    WlrLayershell.exclusiveZone: -1
    // Exclusive: this is a modal editor with keyboard shortcuts (Escape, Ctrl+Z), opened
    // from a click elsewhere in the shell — OnDemand would not deliver them.
    WlrLayershell.keyboardFocus: win.shown ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    visible: win.shown

    // ── Editor state ──────────────────────────────────────────────────────────
    // The tools, in the dock's order. `key` picks one from the keyboard.
    readonly property var tools: [
        { id: "pen",       symbol: "edit",            key: "P", label: Translation.tr("Pen") },
        { id: "highlight", symbol: "format_paint",    key: "H", label: Translation.tr("Highlight") },
        { id: "arrow",     symbol: "arrow_upward",    key: "A", angle: 45, label: Translation.tr("Arrow") },
        { id: "rect",      symbol: "rectangle",       key: "R", label: Translation.tr("Box") },
        { id: "ellipse",   symbol: "circle",          key: "O", label: Translation.tr("Ellipse") },
        { id: "text",      symbol: "title",           key: "T", label: Translation.tr("Text") },
        { id: "step",      symbol: "numbers",         key: "N", label: Translation.tr("Step") },
        { id: "pixelate",  symbol: "blur_on",         key: "B", label: Translation.tr("Blur") }
    ]
    property string tool: "arrow"

    // Palette roles only — the shell has no hardcoded colours, and an annotation is no exception.
    // Held by INDEX, so a palette change under an open editor recolours the swatches and the ink.
    readonly property var inks: [
        Colors.of(QsWindow.window).danger, Colors.of(QsWindow.window).warning,
        Colors.of(QsWindow.window).success, Colors.of(QsWindow.window).info,
        Colors.of(QsWindow.window).primary, Colors.of(QsWindow.window).fg
    ]
    property int inkIdx: 0
    readonly property color ink: win.inks[win.inkIdx]

    // Small / medium / large, in image pixels at 1920 wide (see `unit`).
    property int sizeIdx: 1
    readonly property real unit: Math.max(1, stage.imgW / 1920)
    readonly property real lineWidth: [3, 6, 10][win.sizeIdx] * win.unit
    // Boxes and ellipses: a wash of the ink inside the outline.
    property bool filled: false

    // [{ tool, color, width, points: [{x,y}, …], … }] — a rect and an arrow keep two
    // points, a pen keeps all of them, a step or a text keeps one.
    property var shapes: []
    // What undo took off, newest last, for redo. Drawing anything new empties it.
    property var undone: []
    property var _live: null

    // Where a text is being typed, in image pixels ({ x, y }), or null.
    property var _typing: null

    readonly property bool dirty: win.shapes.length > 0

    function _push(shape) {
        win.shapes = win.shapes.concat([shape])
        win.undone = []
        base.requestPaint()
    }

    function undo() {
        if (win.shapes.length === 0) return
        win.undone = win.undone.concat([win.shapes[win.shapes.length - 1]])
        win.shapes = win.shapes.slice(0, -1)
        base.requestPaint()
    }

    function redo() {
        if (win.undone.length === 0) return
        win.shapes = win.shapes.concat([win.undone[win.undone.length - 1]])
        win.undone = win.undone.slice(0, -1)
        base.requestPaint()
    }

    function clearAll() {
        if (win.shapes.length === 0) return
        // Kept for redo as a whole: the last thing undone is the FIRST thing drawn, so redo
        // rebuilds it in order.
        win.undone = win.shapes.slice().reverse()
        win.shapes = []
        base.requestPaint()
    }

    function close() {
        win.shapes = []
        win.undone = []
        win._live = null
        win._typing = null
        UiState.closeAnnotate()
    }

    onShownChanged: if (win.shown) {
        win.shapes = []
        win.undone = []
        win._live = null
        win._typing = null
        Qt.callLater(() => base.requestPaint())
    }
    // …and once more a moment after it is on screen, for a canvas that came up after all of the above.
    Timer {
        interval: 80
        running: win.shown
        onTriggered: base.requestPaint()
    }

    // The ink's text colour for a badge on it: whichever of the palette's darkest and lightest
    // reads best against it.
    function _onInk(c) {
        const p = Colors.of(QsWindow.window)
        const light = p.fg.hslLightness > p.shadow.hslLightness ? p.fg : p.shadow
        const dark  = p.fg.hslLightness > p.shadow.hslLightness ? p.shadow : p.fg
        return c.hslLightness > 0.55 ? dark : light
    }

    function _commitText() {
        const t = win._typing
        win._typing = null
        keys.forceActiveFocus()
        if (t === null || textEntry.text.trim() === "") return
        win._push({ tool: "text", color: String(win.ink), width: win.lineWidth,
                    size: win.lineWidth * 5, text: textEntry.text,
                    edge: String(Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.6)),
                    points: [{ x: t.x, y: t.y }] })
    }

    // ── Backdrop ──────────────────────────────────────────────────────────────
    // Dimmed, unlike a passing popup: this one IS modal — you are working on the image
    // and the desktop behind it is not part of the task.
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.82)
        TapHandler { onTapped: win.close() }
    }

    // ── The image, and the canvas over it ─────────────────────────────────────
    Item {
        id: stage
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Tokens.spacingXl * 3
        width:  win.width  - Tokens.spacingXxl * 2
        height: win.height - Tokens.spacingXxl * 2 - 200

        // Natural size of the source, once known. Everything below is in these units.
        readonly property int imgW: probe.implicitWidth  > 0 ? probe.implicitWidth  : 1
        readonly property int imgH: probe.implicitHeight > 0 ? probe.implicitHeight : 1

        // Fit, never enlarge: blowing a small screenshot up to fill the screen makes it
        // blurry and makes the strokes lie about their real size.
        readonly property real fit:
            Math.min(stage.width / stage.imgW, stage.height / stage.imgH, 1)

        // Loaded once, only to learn the natural size and to give the canvas something
        // to draw. Not visible itself — the canvas paints it.
        Image {
            id: probe
            source: win.path !== "" ? "file://" + win.path : ""
            visible: false
            cache: false
            asynchronous: false
            onStatusChanged: if (probe.status === Image.Ready) base.requestPaint()
        }

        Item {
            id: scaled
            anchors.centerIn: parent
            width:  stage.imgW * stage.fit
            height: stage.imgH * stage.fit

            Item {
                width:  stage.imgW
                height: stage.imgH
                scale: stage.fit
                transformOrigin: Item.TopLeft

                Canvas {
                    id: base
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    // The first paint can be asked for before the canvas can take it (no context yet,
                    // or still 1×1 while the stage lays out) and is then dropped, which left the image
                    // blank until a tool's first stroke asked again. Ask whenever any of those change.
                    onAvailableChanged: if (base.available) base.requestPaint()
                    onWidthChanged:  base.requestPaint()
                    onHeightChanged: base.requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (probe.status === Image.Ready)
                            ctx.drawImage(probe, 0, 0, width, height)
                        for (const s of win.shapes) win._draw(ctx, s)
                    }
                }

                // The in-progress stroke only. Cleared and redrawn per mouse move, so a
                // drag never replays the whole history.
                Canvas {
                    id: live
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (win._live) win._draw(ctx, win._live, true)
                    }
                }

                // The text being typed: a real TextInput, in image space like everything else.
                // Enter or a click elsewhere keeps it; Esc drops it.
                TextInput {
                    id: textEntry
                    visible: win._typing !== null
                    x: win._typing ? win._typing.x : 0
                    y: win._typing ? win._typing.y : 0
                    width: Math.max(contentWidth + win.lineWidth * 2, win.lineWidth * 12)
                    font.family: Tokens.fontFamily
                    font.pixelSize: win.lineWidth * 5
                    font.weight: Font.DemiBold
                    color: win.ink
                    selectionColor: Colors.of(QsWindow.window).primary
                    cursorVisible: visible
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                    Keys.onReturnPressed: win._commitText()
                    Keys.onEnterPressed:  win._commitText()
                    Keys.onEscapePressed: { win._typing = null; keys.forceActiveFocus() }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -win.lineWidth
                        z: -1
                        radius: win.lineWidth
                        color: "transparent"
                        border.width: Math.max(1, win.unit)
                        border.color: Colors.of(QsWindow.window).alpha(win.ink, 0.7)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    // Inside the scaled item, so these coordinates are already image
                    // coordinates — see the header.
                    onPressed: function(m) {
                        // A click while a text is open keeps that text, and is nothing more.
                        if (win._typing !== null) { win._commitText(); return }
                        if (win.tool === "text") { win._typing = { x: m.x, y: m.y }; return }
                        if (win.tool === "step") {
                            const n = win.shapes.filter(sh => sh.tool === "step").length + 1
                            win._push({ tool: "step", color: String(win.ink), width: win.lineWidth, n: n,
                                        fg: String(win._onInk(win.ink)), points: [{ x: m.x, y: m.y }] })
                            return
                        }
                        win._live = { tool: win.tool, color: String(win.ink),
                                      width: win.lineWidth, fill: win.filled,
                                      points: [{ x: m.x, y: m.y }, { x: m.x, y: m.y }] }
                        live.requestPaint()
                    }
                    onPositionChanged: function(m) {
                        if (!win._live) return
                        const pts = win._live.points
                        if (win._live.tool === "pen" || win._live.tool === "highlight") pts.push({ x: m.x, y: m.y })
                        else pts[1] = { x: m.x, y: m.y }
                        live.requestPaint()
                    }
                    onReleased: {
                        if (!win._live) return
                        const s = win._live
                        win._live = null
                        live.requestPaint()
                        // A click with no drag is not a shape. Without this, every stray
                        // click leaves an invisible zero-length entry that Undo then has
                        // to be pressed for.
                        const p = s.points
                        const moved = (s.tool === "pen" || s.tool === "highlight")
                            ? p.length > 2
                            : Math.abs(p[1].x - p[0].x) > 2 || Math.abs(p[1].y - p[0].y) > 2
                        if (!moved) return
                        win._push(s)
                    }
                }
            }
        }
    }

    // ── Drawing ───────────────────────────────────────────────────────────────
    // One routine for both canvases. `preview` only affects pixelate, which cannot be
    // sampled from the live (transparent) canvas — it shows its bounds instead.
    function _draw(ctx, s, preview) {
        const p = s.points
        ctx.save()
        ctx.strokeStyle = s.color
        ctx.fillStyle   = s.color
        ctx.lineWidth   = s.width
        ctx.lineCap     = "round"
        ctx.lineJoin    = "round"

        if (s.tool === "rect") {
            if (s.fill) {
                ctx.globalAlpha = 0.28
                ctx.fillRect(p[0].x, p[0].y, p[1].x - p[0].x, p[1].y - p[0].y)
                ctx.globalAlpha = 1
            }
            ctx.beginPath()
            ctx.rect(p[0].x, p[0].y, p[1].x - p[0].x, p[1].y - p[0].y)
            ctx.stroke()
        } else if (s.tool === "ellipse") {
            const cx = (p[0].x + p[1].x) / 2, cy = (p[0].y + p[1].y) / 2
            const rx = Math.max(1, Math.abs(p[1].x - p[0].x) / 2), ry = Math.max(1, Math.abs(p[1].y - p[0].y) / 2)
            // The transform shapes the PATH; it is undone before stroking, so the line keeps its width.
            ctx.beginPath()
            ctx.save()
            ctx.translate(cx, cy)
            ctx.scale(rx, ry)
            ctx.arc(0, 0, 1, 0, Math.PI * 2)
            ctx.restore()
            if (s.fill) {
                ctx.globalAlpha = 0.28
                ctx.fill()
                ctx.globalAlpha = 1
            }
            ctx.stroke()
        } else if (s.tool === "pen") {
            ctx.beginPath()
            ctx.moveTo(p[0].x, p[0].y)
            for (let i = 1; i < p.length; i++) ctx.lineTo(p[i].x, p[i].y)
            ctx.stroke()
        } else if (s.tool === "highlight") {
            // Wide and see-through, so the text under it stays readable.
            ctx.globalAlpha = 0.38
            ctx.lineWidth = s.width * 3.5
            ctx.beginPath()
            ctx.moveTo(p[0].x, p[0].y)
            for (let i = 1; i < p.length; i++) ctx.lineTo(p[i].x, p[i].y)
            ctx.stroke()
        } else if (s.tool === "arrow") {
            win._arrow(ctx, p[0], p[1], s.width)
        } else if (s.tool === "text") {
            ctx.font = "600 " + s.size + "px \"" + Tokens.fontFamily + "\""
            ctx.textBaseline = "top"
            // A thin dark edge, so it reads over a light screenshot and a dark one alike.
            ctx.lineWidth = Math.max(2, s.size / 7)
            ctx.strokeStyle = s.edge
            ctx.strokeText(s.text, p[0].x, p[0].y)
            ctx.fillText(s.text, p[0].x, p[0].y)
        } else if (s.tool === "step") {
            const r = s.width * 2.8
            ctx.beginPath()
            ctx.arc(p[0].x, p[0].y, r, 0, Math.PI * 2)
            ctx.fill()
            ctx.fillStyle = s.fg
            ctx.font = "700 " + Math.round(r * 1.15) + "px \"" + Tokens.fontFamily + "\""
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillText(String(s.n), p[0].x, p[0].y + r * 0.04)
        } else if (s.tool === "pixelate") {
            const x = Math.min(p[0].x, p[1].x), y = Math.min(p[0].y, p[1].y)
            const w = Math.abs(p[1].x - p[0].x), h = Math.abs(p[1].y - p[0].y)
            if (preview) {
                ctx.setLineDash([6, 4])
                ctx.strokeRect(x, y, w, h)
            } else {
                win._pixelate(ctx, Math.round(x), Math.round(y),
                              Math.round(w), Math.round(h))
            }
        }
        ctx.restore()
    }

    function _arrow(ctx, a, b, w) {
        const dx = b.x - a.x, dy = b.y - a.y
        const len = Math.sqrt(dx * dx + dy * dy)
        if (len < 1) return
        // Head scales with the stroke, so a thick arrow doesn't end in a pinprick.
        const head = Math.max(10, w * 3.5)
        const ux = dx / len, uy = dy / len
        // The shaft stops short of the tip, or its square end pokes out through the
        // head's point.
        const sx = b.x - ux * head * 0.9, sy = b.y - uy * head * 0.9

        ctx.beginPath()
        ctx.moveTo(a.x, a.y)
        ctx.lineTo(sx, sy)
        ctx.stroke()

        ctx.beginPath()
        ctx.moveTo(b.x, b.y)
        ctx.lineTo(sx - uy * head * 0.45, sy + ux * head * 0.45)
        ctx.lineTo(sx + uy * head * 0.45, sy - ux * head * 0.45)
        ctx.closePath()
        ctx.fill()
    }

    // Average each block and write it back. Reads from the canvas, so it picks up
    // whatever has already been drawn underneath — including an earlier pixelate.
    function _pixelate(ctx, x, y, w, h, block) {
        if (w < 2 || h < 2) return
        const b = Math.max(4, Math.round(Math.min(w, h) / 12))
        const img = ctx.getImageData(x, y, w, h)
        const d = img.data

        for (let by = 0; by < h; by += b) {
            for (let bx = 0; bx < w; bx += b) {
                const bw = Math.min(b, w - bx), bh = Math.min(b, h - by)
                let r = 0, g = 0, bl = 0, n = 0
                for (let yy = 0; yy < bh; yy++) {
                    for (let xx = 0; xx < bw; xx++) {
                        const i = ((by + yy) * w + (bx + xx)) * 4
                        r += d[i]; g += d[i + 1]; bl += d[i + 2]; n++
                    }
                }
                r = r / n; g = g / n; bl = bl / n
                for (let yy = 0; yy < bh; yy++) {
                    for (let xx = 0; xx < bw; xx++) {
                        const i = ((by + yy) * w + (bx + xx)) * 4
                        d[i] = r; d[i + 1] = g; d[i + 2] = bl
                    }
                }
            }
        }
        ctx.putImageData(img, x, y)
    }

    // ── Export ────────────────────────────────────────────────────────────────
    // Written beside the original with an `-edited` suffix rather than over it: the
    // original is the only copy of what was actually on screen, and an editor that
    // silently overwrites it gives you no way back from a mis-drag.
    function _editedPath() {
        const dot = win.path.lastIndexOf(".")
        return dot > 0 ? win.path.substring(0, dot) + "-edited" + win.path.substring(dot)
                       : win.path + "-edited.png"
    }

    function saveAs(alsoCopy) {
        const out = win._editedPath()
        // Canvas.save() is synchronous and returns whether it wrote.
        if (!base.save(out)) {
            console.warn("Annotate: could not write", out)
            return
        }
        if (alsoCopy) Screenshot.copyToClipboard(out)
        Screenshot.present(out)
        win.close()
    }

    // ── Chrome ────────────────────────────────────────────────────────────────
    // M3E, the snip dock's language: trays of round tiles, the picked tool filled and named with its
    // key, one row for what you draw with and one for what you do with the result.
    SurfaceShadow { surface: dock; opacity: win.shown ? 1 : 0 }
    Surface {
        id: dock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingXl
        elevation: Tokens.elevationCard
        cornerRadius: Tokens.radiusXl
        implicitWidth:  dockCol.implicitWidth  + Tokens.spacingLg * 2
        implicitHeight: dockCol.implicitHeight + Tokens.spacingMd * 2
        // A click on the dock must not reach the backdrop (which closes the editor).
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: dockCol
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            // ── Row 1: tools · undo / redo / clear ────────────────────────────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                Rectangle {
                    implicitWidth: toolRow.implicitWidth + Tokens.spacingXs * 2
                    implicitHeight: toolRow.implicitHeight + Tokens.spacingXs * 2
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    Row {
                        id: toolRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: win.tools
                            SnipAction {
                                id: toolBtn
                                required property var modelData
                                symbol: toolBtn.modelData.symbol
                                label: toolBtn.modelData.label
                                symbolAngle: toolBtn.modelData.angle ?? 0
                                capSymbol: ""
                                capText: toolBtn.modelData.key
                                active: win.tool === toolBtn.modelData.id
                                onActivated: { win._typing = null; win.tool = toolBtn.modelData.id }
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: histRow.implicitWidth + Tokens.spacingXs * 2
                    implicitHeight: histRow.implicitHeight + Tokens.spacingXs * 2
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    Row {
                        id: histRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        SnipAction {
                            symbol: "undo"
                            blocked: win.dirty ? "" : "-"
                            onActivated: win.undo()
                        }
                        SnipAction {
                            symbol: "undo"
                            symbolFlip: true
                            blocked: win.undone.length > 0 ? "" : "-"
                            onActivated: win.redo()
                        }
                        SnipAction {
                            symbol: "delete"
                            blocked: win.dirty ? "" : "-"
                            onActivated: win.clearAll()
                        }
                    }
                }
            }

            // ── Row 2: colour · size · fill ····· copy · save · close ─────────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // Colour: round dots; the picked one wears a ring.
                Rectangle {
                    implicitWidth: inkRow.implicitWidth + Tokens.spacingMd * 2
                    implicitHeight: Tokens.iconXl + Tokens.spacingLg
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    Row {
                        id: inkRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: win.inks
                            Item {
                                id: dot
                                required property color modelData
                                required property int index
                                readonly property bool picked: win.inkIdx === dot.index
                                width: Tokens.iconXl; height: Tokens.iconXl
                                SpringValue {
                                    id: ringGrow
                                    spec: Motion.springSpatialFast
                                    epsilon: 0.0005
                                    target: dot.picked ? 1 : 0
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: Tokens.borderChrome
                                    border.color: dot.modelData
                                    opacity: ringGrow.value
                                    scale: 0.7 + 0.3 * ringGrow.value
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Tokens.iconMd + Tokens.spacingXs * ringGrow.value * -1
                                    height: width
                                    radius: width / 2
                                    color: dot.modelData
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.inkIdx = dot.index
                                }
                            }
                        }
                    }
                }

                // Size: three dots of growing size (keys 1 2 3).
                Rectangle {
                    implicitWidth: sizeRow.implicitWidth + Tokens.spacingXs * 2
                    implicitHeight: Tokens.iconXl + Tokens.spacingLg
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    Row {
                        id: sizeRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: [Tokens.spacingXs * 2 + 1, Tokens.spacingMd, Tokens.spacingLg + Tokens.spacingXs]
                            Rectangle {
                                id: sz
                                required property int modelData
                                required property int index
                                readonly property bool picked: win.sizeIdx === sz.index
                                width: Tokens.iconXl + Tokens.spacingSm; height: Tokens.iconXl + Tokens.spacingSm
                                radius: width / 2
                                color: sz.picked ? Colors.of(QsWindow.window).primaryContainer : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                StateLayer {
                                    anchors.fill: parent
                                    radius: sz.radius
                                    hovered: szMouse.containsMouse
                                    layerColor: Colors.of(QsWindow.window).fg
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: sz.modelData; height: width; radius: width / 2
                                    color: sz.picked ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                     : Colors.of(QsWindow.window).fg
                                }
                                MouseArea {
                                    id: szMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.sizeIdx = sz.index
                                }
                            }
                        }
                    }
                }

                // Fill: boxes and ellipses wash their inside.
                Rectangle {
                    implicitWidth: fillTile.implicitWidth + Tokens.spacingXs * 2
                    implicitHeight: Tokens.iconXl + Tokens.spacingLg
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    opacity: win.tool === "rect" || win.tool === "ellipse" ? 1 : 0.4
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    SnipAction {
                        id: fillTile
                        anchors.centerIn: parent
                        symbol: "opacity"
                        active: win.filled
                        label: Translation.tr("Fill")
                        capSymbol: ""
                        capText: "F"
                        onActivated: win.filled = !win.filled
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredWidth: Tokens.spacingXl }

                PanelButton {
                    variant: "normal"
                    symbol: "content_copy"
                    label: Translation.tr("Copy")
                    onActivated: win.saveAs(true)
                }
                PanelButton {
                    variant: "primary"
                    symbol: "save"
                    label: Translation.tr("Save")
                    onActivated: win.saveAs(false)
                }
                PanelButton {
                    variant: "ghost"
                    symbol: "close"
                    onActivated: win.close()
                }
            }

            // ── What the keys do ──────────────────────────────────────────────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Repeater {
                    model: [
                        { k: "Enter",    t: Translation.tr("Copy") },
                        { k: "Ctrl S",   t: Translation.tr("Save") },
                        { k: "Ctrl Z",   t: Translation.tr("Undo") },
                        { k: "1 2 3",    t: Translation.tr("Size") },
                        { k: "Esc",      t: Translation.tr("Close") }
                    ]
                    RowLayout {
                        id: hintItem
                        required property var modelData
                        required property int index
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        StyledText {
                            visible: hintItem.index > 0
                            text: "·"
                            variant: "caption"
                            emphasis: "dim"
                        }
                        SnipKeyCap { text: hintItem.modelData.k }
                        StyledText { text: hintItem.modelData.t; variant: "caption"; emphasis: "dim" }
                    }
                }
            }
        }
    }

    // Keys attach to an Item, never to a PanelWindow — the removed EmojiPopup
    // learned this the noisy way; see CLAUDE.md's API caution notes.
    // While a text is being typed this stands down: the TextInput owns the keyboard (and Esc / Enter).
    Item {
        id: keys
        anchors.fill: parent
        focus: win.shown
        Keys.onPressed: function(ev) {
            if (win._typing !== null) return
            const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0
            const shift = (ev.modifiers & Qt.ShiftModifier) !== 0
            ev.accepted = true
            if (ev.key === Qt.Key_Escape) { win.close(); return }
            if (ctrl && ev.key === Qt.Key_Z) { if (shift) win.redo(); else win.undo(); return }
            if (ctrl && ev.key === Qt.Key_Y) { win.redo(); return }
            if (ctrl && ev.key === Qt.Key_C) { win.saveAs(true); return }
            if (ctrl && ev.key === Qt.Key_S) { win.saveAs(false); return }
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { win.saveAs(true); return }
            if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_3) { win.sizeIdx = ev.key - Qt.Key_1; return }
            if (!ctrl && ev.text !== "") {
                const k = ev.text.toUpperCase()
                if (k === "F") { win.filled = !win.filled; return }
                for (const t of win.tools) if (t.key === k) { win.tool = t.id; return }
            }
            ev.accepted = false
        }
    }
}
