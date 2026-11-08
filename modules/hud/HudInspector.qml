pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H
import "../../services/inputkeys.js" as IK

// ── HudInspector ──────────────────────────────────────────────────────────────
// The overview island's third face (beside volume/brightness and the window inspector):
// one HUD widget, chosen by its card's tune chip (Hud.inspecting), and WHERE it goes over
// a game.
//
// ── The map ───────────────────────────────────────────────────────────────────
// Your screen, shrunk: the wallpaper, and the real widgets (HudWidget, the same frames
// HudLayer draws) at their saved places — the one being placed at full strength, the
// other pinned ones faint. Press anywhere on it and the widget goes there; drag and it
// follows, snapping onto the screen's centre lines (a guide lights) within 12 px of what
// you see; it commits ONCE on release (`override` meanwhile), so hud.json isn't rewritten
// per frame. The whole rectangle stays on screen (clampCentre). Nine dots on the map put it
// in a corner, an edge's middle or the centre in one click (hud.js ANCHORS).
//
// The input overlay's copy here is drawn idle (`listen: false`) — no key hook.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property string wid
    // The screen being placed on (the overview's own).
    // The input overlay's keyboard options replace the sliders (a page, not more rows: the island keeps its height).
    // Opened by the card's Customise chip, which is how a user gets here for this widget.
    property bool keysPage: root.wid === "input"
    readonly property bool onKeys: root.wid === "input" && root.keysPage
    property real screenW: 1920
    property real screenH: 1080
    // …and its name: a placement makes it the overlay's home ("always" widgets live there).
    property string screenName: ""

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property var meta: H.info(root.wid)
    readonly property var entry: Hud.layout.widgets[root.wid]
    readonly property color accent: root.pal.primary

    readonly property real mapH: Tokens.sideCardUnit * 2.6
    readonly property real mapW: Math.round(root.mapH * root.screenW / Math.max(1, root.screenH))
    readonly property real s: root.mapH / Math.max(1, root.screenH)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // What each widget draws, and the frame being placed (for its size).
    Component { id: cStats;     HudStats {} }
    Component { id: cClips;     HudClips {} }
    Component { id: cVoice;     HudVoice {} }
    Component { id: cInput;     HudInput { listen: false } }
    readonly property var bodies: ({ stats: cStats, clips: cClips, voice: cVoice, input: cInput })
    readonly property Item current: placed.count > 0 ? placed.itemAt(H.ids().indexOf(root.wid)) : null

    property var dragAt: null
    function _at(mx, my) {
        const px = H.SNAP_PX / root.s
        const fx = H.snapCentre(mx / root.screenW, root.screenW, px)
        const fy = H.snapCentre(my / root.screenH, root.screenH, px)
        return H.clampCentre(fx, fy, root.current?.width ?? 0, root.current?.height ?? 0,
                             root.screenW, root.screenH)
    }

    RowLayout {
        id: row
        spacing: Tokens.spacingLg

        // ── The map ───────────────────────────────────────────────────────────
        ClippingRectangle {
            Layout.preferredWidth: root.mapW
            Layout.preferredHeight: root.mapH
            radius: Tokens.radiusCard
            color: root.pal.surfaceContainer
            border.width: Tokens.borderWidth
            border.color: root.pal.outline

            Item {
                id: scr
                width: root.screenW
                height: root.screenH
                scale: root.s
                transformOrigin: Item.TopLeft

                Image {
                    anchors.fill: parent
                    source: Wallpaper.currentPath
                    sourceSize: Qt.size(480, 270)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    color: root.pal.alpha(root.pal.base, 0.3)
                }

                // Centre guides: lit while a drag sits on them.
                Rectangle {
                    x: (scr.width - width) / 2
                    width: Tokens.borderChrome / root.s
                    height: scr.height
                    color: root.accent
                    opacity: root.dragAt !== null && root.dragAt.cx === 0.5 ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
                Rectangle {
                    y: (scr.height - height) / 2
                    width: scr.width
                    height: Tokens.borderChrome / root.s
                    color: root.accent
                    opacity: root.dragAt !== null && root.dragAt.cy === 0.5 ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }

                // The other pinned ones faint; this one at full strength, ringed. (A Repeater,
                // not an inline component: a hot reload can't introduce one — CLAUDE.md.)
                Repeater {
                    id: placed
                    model: H.ids()
                    HudWidget {
                        required property string modelData
                        wid: modelData
                        plain: modelData === "input"
                        resizable: modelData === "input"
                        body: root.bodies[modelData] ?? null
                        preview: modelData === root.wid
                        override: modelData === root.wid ? root.dragAt : null
                        boundsW: scr.width
                        boundsH: scr.height
                        opacity: !shown ? 0 : modelData === root.wid ? 1 : 0.35
                    }
                }

                Rectangle {
                    visible: root.current !== null
                    x: (root.current?.x ?? 0) - Tokens.spacingMd / root.s
                    y: (root.current?.y ?? 0) - Tokens.spacingMd / root.s
                    width: (root.current?.width ?? 0) + 2 * Tokens.spacingMd / root.s
                    height: (root.current?.height ?? 0) + 2 * Tokens.spacingMd / root.s
                    radius: Tokens.radiusCard / root.s
                    color: root.pal.alpha(root.accent, 0.12)
                    border.width: Tokens.borderChrome / root.s
                    border.color: root.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    onPressed: mouse => root.dragAt = root._at(mouse.x, mouse.y)
                    onPositionChanged: mouse => { if (pressed) root.dragAt = root._at(mouse.x, mouse.y) }
                    onReleased: {
                        if (root.dragAt !== null) Hud.move(root.wid, root.dragAt.cx, root.dragAt.cy, root.screenName)
                        root.dragAt = null
                    }
                    onCanceled: root.dragAt = null
                }

                // ── The nine anchors, on the map where they really are ────────
                // Above the drag area: a click on one puts the widget there (hud.js
                // ANCHORS, the whole rectangle kept on screen); lit where it sits now.
                Repeater {
                    model: Object.keys(H.ANCHORS)
                    Rectangle {
                        id: dot
                        required property string modelData
                        readonly property var a: H.ANCHORS[dot.modelData]
                        readonly property bool here: Math.abs(root.entry.cx - dot.a[0]) < 0.08
                                                  && Math.abs(root.entry.cy - dot.a[1]) < 0.1
                        width: (Tokens.spacingMd + Tokens.spacingXs) / root.s
                        height: width
                        radius: width / 2
                        x: dot.a[0] * scr.width - width / 2
                        y: dot.a[1] * scr.height - height / 2
                        visible: root.dragAt === null
                        color: dot.here ? root.accent
                             : dotHover.hovered ? root.pal.alpha(root.pal.fg, 0.7)
                             : root.pal.alpha(root.pal.fg, 0.28)
                        border.width: Tokens.borderWidth / root.s
                        border.color: root.pal.alpha(root.pal.base, 0.6)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: Hud.place(root.wid, dot.modelData, root.current?.width ?? 0,
                                                root.current?.height ?? 0, root.screenW, root.screenH, root.screenName)
                        }
                    }
                }
            }
        }

        // ── What it is, and its options ───────────────────────────────────────
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Tokens.sideCardUnit * 7
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd
                ScallopChip {
                    implicitWidth: 32
                    implicitHeight: 32
                    tint: root.accent
                    hot: root.entry.pinned
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.meta.symbol
                        fill: 1
                        color: root.accent
                        font.pixelSize: Tokens.iconMd
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr(root.meta.label)
                        variant: "body"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: !root.entry.pinned ? Translation.tr("Not on screen yet — pin it")
                            : root.entry.where === "always" ? Translation.tr("Always on screen · drag it on the map")
                            : Translation.tr("Over fullscreen games · drag it on the map")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                // The map, full size: drag it on the real screen (HudArrange).
                ChipButton {
                    symbol: "open_with"
                    solid: true
                    tint: root.accent
                    onActivated: Hud.arrange(true, root.wid)
                }
                ChipButton {
                    symbol: "close"
                    onActivated: Hud.inspect("")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                ChipButton {
                    symbol: "keep"
                    label: root.entry.pinned ? Translation.tr("Pinned") : Translation.tr("Pin it")
                    on: root.entry.pinned
                    tint: root.accent
                    onActivated: Hud.pin(root.wid, !root.entry.pinned)
                }
                ChipButton {
                    visible: root.wid === "input"
                    symbol: "keyboard"
                    label: Translation.tr("Keys")
                    on: root.keysPage
                    tint: root.accent
                    onActivated: root.keysPage = !root.keysPage
                }
                ChipButton {
                    symbol: "ads_click"
                    label: root.entry.clickthrough ? Translation.tr("Click-through") : Translation.tr("Takes clicks")
                    on: !root.entry.clickthrough
                    tint: root.accent
                    onActivated: Hud.passThrough(root.wid, !root.entry.clickthrough)
                }
            }

            // ── Where it shows: over games only, or always (a plain overlay) ───
            SegmentSwitch {
                Layout.fillWidth: true
                visible: !root.onKeys
                accent: root.accent
                model: [{ value: "games", label: Translation.tr("Over games") },
                        { value: "always", label: Translation.tr("Always") }]
                current: root.entry.where
                onPicked: function (value) { Hud.setWhere(root.wid, value) }
            }

            // ── Size and transparency, for the widgets that have them ─────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.entry.opts.opacity !== undefined && !root.onKeys
                spacing: Tokens.spacingMd
                MaterialIcon {
                    name: "opacity"
                    font.pixelSize: Tokens.iconMd
                    color: root.pal.fgMuted
                }
                ValueSlider {
                    Layout.fillWidth: true
                    thickness: 6
                    value: root.entry.opts.opacity ?? 1
                    accent: root.accent
                    onMoved: function (v) { Hud.setOpt(root.wid, "opacity", Math.max(H.OPACITY_MIN, v)) }
                }
                StyledText {
                    Layout.preferredWidth: Tokens.sideCardUnit
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((root.entry.opts.opacity ?? 1) * 100) + "%"
                    variant: "label"
                    font.family: Tokens.fontMono
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.entry.opts.scale !== undefined && !root.onKeys
                spacing: Tokens.spacingMd
                MaterialIcon {
                    name: "open_with"
                    font.pixelSize: Tokens.iconMd
                    color: root.pal.fgMuted
                }
                // SCALE_MIN..SCALE_MAX on the rail.
                ValueSlider {
                    Layout.fillWidth: true
                    thickness: 6
                    value: ((root.entry.opts.scale ?? 1) - H.SCALE_MIN) / (H.SCALE_MAX - H.SCALE_MIN)
                    accent: root.accent
                    onMoved: function (v) { Hud.setOpt(root.wid, "scale", H.SCALE_MIN + v * (H.SCALE_MAX - H.SCALE_MIN)) }
                }
                StyledText {
                    Layout.preferredWidth: Tokens.sideCardUnit
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((root.entry.opts.scale ?? 1) * 100) + "%"
                    variant: "label"
                    font.family: Tokens.fontMono
                }
            }

            // ── The keys page (the input overlay): which keyboard, the mouse, the rates ──
            ColumnLayout {
                id: keysCol
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.onKeys
                spacing: Tokens.spacingSm
                readonly property var layoutNow: IK.layoutOf(root.entry.opts.layout)

                SegmentSwitch {
                    Layout.fillWidth: true
                    accent: root.accent
                    model: IK.LAYOUT_IDS.map(id => ({ value: id, label: IK.layoutOf(id).name }))
                    current: root.entry.opts.layout
                    onPicked: function (value) { Hud.setOpt(root.wid, "layout", value) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    ChipButton {
                        symbol: "mouse"
                        label: Translation.tr("Mouse")
                        on: root.entry.opts.mouse !== false
                        tint: root.accent
                        onActivated: Hud.setOpt(root.wid, "mouse", root.entry.opts.mouse === false)
                    }
                    ChipButton {
                        symbol: "speed"
                        label: Translation.tr("Click and key rates")
                        on: root.entry.opts.stats !== false
                        tint: root.accent
                        onActivated: Hud.setOpt(root.wid, "stats", root.entry.opts.stats === false)
                    }
                    Item { Layout.fillWidth: true }
                    // Size and see-through, one row each is too much here: the page keeps the two as steppers.
                    ChipButton { symbol: "remove"; onActivated: Hud.setOpt(root.wid, "scale", (root.entry.opts.scale ?? 1) - 0.1) }
                    StyledText {
                        text: Math.round((root.entry.opts.scale ?? 1) * 100) + "%"
                        variant: "caption"
                        font.family: Tokens.fontMono
                    }
                    ChipButton { symbol: "add"; onActivated: Hud.setOpt(root.wid, "scale", (root.entry.opts.scale ?? 1) + 0.1) }
                }
                // What the layout puts on the socket. A bigger keyboard names more keys: said plainly, in the danger tone for
                // the ones that cover everything you type.
                StyledText {
                    Layout.fillWidth: true
                    text: keysCol.layoutNow.exposes === "all"
                        ? Translation.tr("Names every key you type, on a socket your other programs can read, while it shows. Don't type passwords with it on.")
                        : keysCol.layoutNow.exposes === "some"
                        ? Translation.tr("Names the keys around WASD as well — not everything you type.")
                        : Translation.tr("Names only the keys games use.")
                    variant: "caption"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: keysCol.layoutNow.exposes === "all" ? Verdict.fail : root.pal.fgDim
                }
            }
        }
    }
}
