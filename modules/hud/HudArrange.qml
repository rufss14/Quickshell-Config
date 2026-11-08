pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H

// ── HudArrange ────────────────────────────────────────────────────────────────
// Arranging the HUD on the REAL screen: the overview steps back (Overview.qml hides its
// stage and lightens the dim while `Hud.arranging`), and every widget is drawn here at
// its true place and size — the same HudWidget frames HudLayer draws over a game — to be
// dragged where it goes. The island's map is the small version of this; this is the one
// you can see a game's corner, or your stream's camera, against.
//
//   · Drag a widget: it follows the pointer, snapping onto the centre lines and onto a
//     margin in from each edge (hud.js snapPlace), with the line it snapped to drawn. It
//     commits ONCE on release (`override` meanwhile), with this monitor as the overlay's
//     home (where "always" widgets live).
//   · Each one wears a tag: its name, where it shows (over games / always) and its pin.
//     Unpinned ones are drawn faint — they're placed all the same, for when they're pinned.
//   · Keys: arrows nudge the last-touched widget a pixel (Shift: ten), Tab picks the next,
//     Escape or Enter is done.
//   · It arrives in a cascade: the hint drops in from the top, the widgets spring up at their
//     places one after another (PopIn), and each tag follows its widget a beat later. A
//     spring's every-frame value only ever drives `scale` here — opacity has Behaviors of its
//     own (HudWidget's, the tags'), so it takes a FLIP once the spring is under way.
//
// Built only while arranging (Overview's Loader), so its live bodies sample nothing
// otherwise. The input overlay's copy is drawn idle (`listen: false`) — no key hook.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // This monitor's name — saved as the overlay's home on every placement.
    property string screenName: ""

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property color accent: root.pal.primary
    // How far in from the screen's edges the edge snap sits.
    readonly property int margin: Tokens.spacingXxl

    // The widget the keys act on, and the one under a drag (with where it would land).
    property string current: Hud.arrangeFocus !== "" ? Hud.arrangeFocus : H.ids()[0]
    property string dragging: ""
    property var dragAt: null

    Component { id: cStats; HudStats {} }
    Component { id: cClips; HudClips {} }
    Component { id: cVoice; HudVoice {} }
    Component { id: cInput; HudInput { listen: false } }
    readonly property var bodies: ({ stats: cStats, clips: cClips, voice: cVoice, input: cInput })

    function frameOf(id) { return frames.count > 0 ? frames.itemAt(H.ids().indexOf(id)) : null }

    function nudge(dx, dy) {
        const f = root.frameOf(root.current)
        if (!f) return
        const e = Hud.layout.widgets[root.current]
        const c = H.clampCentre(e.cx + dx / root.width, e.cy + dy / root.height,
                                f.width, f.height, root.width, root.height)
        Hud.move(root.current, c.cx, c.cy, root.screenName)
    }

    // Takes the keyboard from the search field while it's up (Overview gives it back).
    focus: true
    Component.onCompleted: root.forceActiveFocus()
    Keys.onPressed: function (event) {
        const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        const k = event.key
        if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter) Hud.arrange(false)
        else if (k === Qt.Key_Left)  root.nudge(-step, 0)
        else if (k === Qt.Key_Right) root.nudge(step, 0)
        else if (k === Qt.Key_Up)    root.nudge(0, -step)
        else if (k === Qt.Key_Down)  root.nudge(0, step)
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            const ids = H.ids()
            const i = ids.indexOf(root.current)
            root.current = ids[(i + (k === Qt.Key_Tab ? 1 : ids.length - 1)) % ids.length]
        }
        event.accepted = true
    }

    // ── The guides: the lines a drag can snap to, lit while it sits on one ────
    Repeater {
        model: [
            { axis: "x", g: "centre" }, { axis: "x", g: "start" }, { axis: "x", g: "end" },
            { axis: "y", g: "centre" }, { axis: "y", g: "start" }, { axis: "y", g: "end" }
        ]
        Rectangle {
            id: guide
            required property var modelData
            readonly property bool vertical: guide.modelData.axis === "x"
            readonly property real at: {
                const total = guide.vertical ? root.width : root.height
                return guide.modelData.g === "centre" ? total / 2
                     : guide.modelData.g === "start" ? root.margin : total - root.margin
            }
            x: guide.vertical ? Math.round(guide.at - width / 2) : 0
            y: guide.vertical ? 0 : Math.round(guide.at - height / 2)
            width: guide.vertical ? Tokens.borderChrome : root.width
            height: guide.vertical ? root.height : Tokens.borderChrome
            color: root.accent
            opacity: root.dragAt !== null && root.dragAt.guides[guide.modelData.axis] === guide.modelData.g ? 0.85 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }
    }

    // ── The widgets, at their real places ─────────────────────────────────────
    Repeater {
        id: frames
        model: H.ids()

        HudWidget {
            id: fw
            required property string modelData
            required property int index
            readonly property bool touched: root.current === fw.modelData

            wid: fw.modelData
            plain: fw.modelData === "input"
            resizable: fw.modelData === "input"
            body: root.bodies[fw.modelData] ?? null
            preview: true
            override: root.dragging === fw.modelData ? root.dragAt : null
            boundsW: root.width
            boundsH: root.height
            PopIn { id: fwPop; active: true; index: fw.index; delay: Motion.fast }
            opacity: fwPop.arrive > 0.05 ? (fw.entry.pinned ? 1 : 0.45) : 0
            scale: fwPop.scale
            z: root.dragging === fw.modelData ? 2 : fw.touched ? 1 : 0

            // A ring while it's the one the keys move, or under the pointer.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Tokens.spacingSm
                radius: Tokens.radiusCard + Tokens.spacingSm
                color: root.pal.alpha(root.accent, grab.pressed ? 0.10 : 0)
                border.width: Tokens.borderChrome
                border.color: root.accent
                opacity: grab.pressed || grab.containsMouse ? 1 : fw.touched ? 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            MouseArea {
                id: grab
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // Where in the widget it was taken hold of, so it doesn't jump to centre.
                property point hold: Qt.point(0, 0)
                function _land(mouse) {
                    const p = grab.mapToItem(root, mouse.x, mouse.y)
                    return H.snapPlace((p.x - grab.hold.x + fw.width / 2) / root.width,
                                       (p.y - grab.hold.y + fw.height / 2) / root.height,
                                       fw.width, fw.height, root.width, root.height, root.margin)
                }
                onPressed: mouse => {
                    root.current = fw.modelData
                    grab.hold = Qt.point(mouse.x, mouse.y)
                    root.dragging = fw.modelData
                    root.dragAt = grab._land(mouse)
                }
                onPositionChanged: mouse => { if (pressed) root.dragAt = grab._land(mouse) }
                onReleased: {
                    if (root.dragAt !== null) Hud.move(fw.modelData, root.dragAt.cx, root.dragAt.cy, root.screenName)
                    root.dragging = ""
                    root.dragAt = null
                }
                onCanceled: { root.dragging = ""; root.dragAt = null }
            }
        }
    }

    // ── The tags: what each one is, where it shows, its pin ───────────────────
    // Separate from the frames so an unpinned widget's faintness doesn't take its tag with
    // it. Above the widget, or below it when it's against the top of the screen.
    Repeater {
        model: H.ids()

        Surface {
            id: tag
            required property string modelData
            required property int index
            readonly property Item f: frames.count > 0 ? frames.itemAt(tag.index) : null
            readonly property var entry: Hud.layout.widgets[tag.modelData]
            readonly property var meta: H.info(tag.modelData)
            readonly property bool below: tag.f !== null && tag.f.y < tag.height + Tokens.spacingXl

            visible: tag.f !== null
            elevation: Tokens.elevationPopup
            cornerRadius: height / 2
            width: tagRow.implicitWidth + Tokens.spacingSm * 2
            height: tagRow.implicitHeight + Tokens.spacingXs * 2
            x: tag.f ? Math.round(Math.max(Tokens.spacingSm, Math.min(root.width - width - Tokens.spacingSm,
                                     tag.f.x + (tag.f.width - width) / 2))) : 0
            y: tag.f ? Math.round(tag.below ? tag.f.y + tag.f.height + Tokens.spacingMd
                                            : tag.f.y - height - Tokens.spacingMd) : 0
            z: 3
            PopIn { id: tagPop; active: true; index: tag.index; delay: Motion.fast + Motion.standard }
            opacity: tagPop.arrive < 0.05 ? 0 : root.dragging !== "" && root.dragging !== tag.modelData ? 0.35 : 1
            scale: tagPop.scale
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            RowLayout {
                id: tagRow
                anchors.centerIn: parent
                spacing: Tokens.spacingXs

                MaterialIcon {
                    Layout.leftMargin: Tokens.spacingSm
                    name: tag.meta.symbol
                    fill: tag.entry.pinned ? 1 : 0
                    color: root.accent
                    font.pixelSize: Tokens.iconSm
                }
                StyledText {
                    Layout.rightMargin: Tokens.spacingXs
                    text: Translation.tr(tag.meta.label)
                    variant: "label"
                    font.weight: Font.DemiBold
                }
                ChipButton {
                    symbol: tag.entry.where === "always" ? "monitor" : "sports_esports"
                    label: tag.entry.where === "always" ? Translation.tr("Always") : Translation.tr("Over games")
                    tint: root.accent
                    on: tag.entry.where === "always"
                    onActivated: Hud.setWhere(tag.modelData, tag.entry.where === "always" ? "games" : "always")
                }
                ChipButton {
                    symbol: "keep"
                    on: tag.entry.pinned
                    tint: root.accent
                    onActivated: Hud.pin(tag.modelData, !tag.entry.pinned)
                }
            }
        }
    }

    // ── What this is, and the way out ─────────────────────────────────────────
    // Top centre; it drops to the bottom while a drag is up there, so it never sits on the
    // thing you're placing.
    Surface {
        id: hint
        readonly property bool low: root.dragAt !== null && root.dragAt.cy < 0.25
        anchors.horizontalCenter: parent.horizontalCenter
        y: hint.low ? root.height - height - root.margin * 2 : root.margin * 2
        Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        z: 4
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusXl
        // Drops in from above as the view opens.
        PopIn { id: hintPop; active: true }
        scale: hintPop.scale
        itemOpacity: Tokens.surfaceOpacity * hintPop.opacity
        transform: Translate { y: -(1 - hintPop.arrive) * Tokens.spacingXxl }
        width: hintRow.implicitWidth + Tokens.spacingLg * 2
        height: hintRow.implicitHeight + Tokens.spacingMd * 2

        RowLayout {
            id: hintRow
            anchors.centerIn: parent
            spacing: Tokens.spacingLg

            ScallopChip {
                implicitWidth: 36
                implicitHeight: 36
                tint: root.accent
                hot: root.dragging !== ""
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "open_with"
                    color: root.accent
                    font.pixelSize: Tokens.iconMd
                }
            }
            ColumnLayout {
                spacing: 0
                RowLayout {
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText { text: Translation.tr("Arrange your"); variant: "body"; font.weight: Font.DemiBold }
                    StyledText { text: Translation.tr("HUD"); variant: "body"; font.weight: Font.DemiBold; color: root.accent }
                }
                StyledText {
                    text: Translation.tr("Drag to place · snaps to the centre and the edges · arrows nudge, Shift ×10 · Tab next")
                    variant: "caption"
                    emphasis: "dim"
                }
            }
            ChipButton {
                symbol: "check"
                label: Translation.tr("Done")
                solid: true
                tint: root.accent
                onActivated: Hud.arrange(false)
            }
        }
    }
}
