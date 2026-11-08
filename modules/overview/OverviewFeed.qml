import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── OverviewFeed ──────────────────────────────────────────────────────────────
// The overview's LEFT face (2026-10-24): the notification centre's mirror, left of the busy
// workspaces when there's room (WorkspaceGrid `notesOn`), with pages side by side that you swipe
// through — one page fills the face, the next waits beside it:
//
//     0  What's changed   FeedChanges    the version you're on; patch notes, later
//     1  Ask              FeedAssistant  a chat that changes the shell (Assistant)
//     2  News             FeedNews       near you or the world (News)
//
// ── The swipe (horizontal since 2026-10-24, the user) ─────────────────────────
//   · press and drag ANYWHERE on a page, left or right: the page follows the pointer; let go past a
//     fifth of the face (or with a flick) and it turns. A rubber band past the first and last.
//     Up or down instead, and the page's list follows the pointer and coasts on when let go — the
//     first few px decide which (`_axis`), so a swipe never scrolls and a scroll never swipes;
//   · a sideways wheel (a touchpad's two-finger swipe, a tilt wheel) turns too, one page per push
//     with a beat of cool-down so a coast doesn't skip two. The vertical wheel only scrolls;
//   · the wheel scrolls the list SMOOTHLY, a notch at a time (`scroll`, ~2.5 lines a notch — the
//     user found the plain one too slow); a touchpad scrolls 1:1;
//   · the rail under the pages (SlidingTabs): one stop per page, the one you're on wears its name,
//     and a lit pill slides between the stops with the swipe; click to go.
// The pages' own lists are NOT mouse-draggable (`interactive: false`) — their own drag would grab
// the press before a sideways one could — so the handlers OVER the pages (`swipeLayer`) do both the
// swipe and the scroll, driving the page's Flickable (each page exposes `flick`). The drag never takes a press from an
// item (no CanTakeOverFromItems), so selecting text in a field still works.
//
// Pages are built while in view or passing through, so a page you aren't on costs nothing;
// what must survive (the chat, the stories) lives in the services. The page you were on is
// Config.overviewFeedPage.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var pages: [
        { symbol: "update",       label: Translation.tr("What's new"), badge: Changelog.unseen > 0 },
        { symbol: "auto_awesome", label: Translation.tr("Ask") },
        { symbol: "newspaper",    label: Translation.tr("News") }
    ]
    readonly property int count: root.pages.length

    property int index: Math.max(0, Math.min(root.count - 1, Config.overviewFeedPage))
    // Where the pages are, in pages: `pos` follows `index` on a spring; `pull` is the pointer's
    // (or the wheel's) share on top of it.
    property real pos: root.index
    property real pull: 0
    property bool dragging: false
    readonly property real at: root.pos + root.pull

    Behavior on pos {
        enabled: !root.dragging
        NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
    }
    Behavior on pull {
        enabled: !root.dragging
        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    function go(i) {
        const n = Math.max(0, Math.min(root.count - 1, i))
        root.cool.restart()
        root.pos = n
        if (n === root.index) return
        root.index = n
        Config.overviewFeedPage = n
    }

    // ── The wheel ─────────────────────────────────────────────────────────────
    readonly property real turnAt: 150          // px of sideways push that turns the page
    property real _over: 0
    property Timer cool: Timer { interval: 420 }
    property Timer settle: Timer { interval: 260; onTriggered: { root._over = 0; root.pull = 0 } }

    // Up/down: the page's own list. `smooth` (a wheel notch) glides there, and notches in a row add up
    // onto where the glide is going, not where it has got to.
    function _flick() {
        const page = pagesRepeater.itemAt(root.index)
        return page && page.item ? page.item.flick : null
    }
    function _clampY(f, y) {
        return Math.max(f.originY, Math.min(f.originY + Math.max(0, f.contentHeight - f.height), y))
    }
    property real _scrollTo: 0
    NumberAnimation {
        id: glide
        property: "contentY"
        duration: Motion.standard
        easing.type: Motion.travel
    }
    function scroll(dy, smooth) {
        const f = root._flick()
        if (!f || f.contentHeight <= f.height + 1) return
        const from = glide.running && glide.target === f ? root._scrollTo : f.contentY
        const to = root._clampY(f, from + dy)
        glide.stop()
        if (!smooth || !Config.motionEnabled) { f.contentY = to; return }
        root._scrollTo = to
        glide.target = f
        glide.from = f.contentY
        glide.to = to
        glide.duration = Motion.standard
        glide.easing.type = Motion.travel
        glide.start()
    }
    // A let-go drag coasts on, slowing — the pointer's speed carried a little way.
    function coast(v) {
        const f = root._flick()
        if (!f || Math.abs(v) < 80) return
        const to = root._clampY(f, f.contentY - v * 0.35)
        glide.stop()
        root._scrollTo = to
        glide.target = f
        glide.from = f.contentY
        glide.to = to
        glide.duration = Motion.emphasized * 2
        glide.easing.type = Easing.OutQuart
        glide.start()
    }
    // Sideways: push toward the next page; past `turnAt`, it turns.
    function push(dx) {
        if (root.cool.running) return
        if ((dx < 0 && root.index === 0) || (dx > 0 && root.index === root.count - 1))
            root._over = Math.max(-root.turnAt * 0.5, Math.min(root.turnAt * 0.5, root._over + dx * 0.4))
        else root._over += dx
        root.pull = root._over / root.turnAt * 0.14
        root.settle.restart()
        if (Math.abs(root._over) >= root.turnAt) {
            const dir = root._over > 0 ? 1 : -1
            root._over = 0
            root.pull = 0
            root.go(root.index + dir)
        }
    }

    // ── The rail: a stop per page, under the pages (SlidingTabs) ──────────────
    // Its pill follows `at`, so it slides between two stops mid-swipe as the pages do.
    SlidingTabs {
        id: rail
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: implicitWidth
        height: implicitHeight
        model: root.pages
        position: root.at
        accent: root.accent
        onPicked: index => root.go(index)
    }

    // ── The pages ─────────────────────────────────────────────────────────────
    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: rail.top
        anchors.bottomMargin: Tokens.spacingMd
        clip: true
        readonly property real step: viewport.width + Tokens.spacingXl

        Repeater {
            id: pagesRepeater
            model: root.count
            delegate: Loader {
                id: page
                required property int index
                readonly property real d: page.index - root.at
                width: viewport.width
                height: viewport.height
                x: page.d * viewport.step
                // The one leaving steps back a little as the next slides in beside it.
                opacity: 1 - Math.min(1, Math.abs(page.d)) * 0.55
                scale: 1 - Math.min(1, Math.abs(page.d)) * 0.06
                visible: Math.abs(page.d) < 1
                active: root.shown && (Math.abs(page.d) < 1 || page.index === root.index)
                sourceComponent: page.index === 0 ? changesPage : page.index === 1 ? askPage : newsPage
                Binding { when: page.item !== null; target: page.item; property: "current"; value: root.shown && page.index === root.index }
                Binding { when: page.item !== null; target: page.item; property: "accent"; value: root.accent }
            }
        }

        // The swipe and the drag-scroll — on the viewport ITSELF, not the layer over the pages: a
        // DragHandler on an item stacked over a text field kept the field from taking focus on a click
        // (the Ask page's box could not be typed in; reproduced offscreen with qmltestrunner,
        // 2026-10-24). On the parent, a press reaches the field first and a drag still comes here.
        DragHandler {
            id: swipe
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything
            cursorShape: Qt.ClosedHandCursor
            // "x" swipes the pages, "y" scrolls the page; decided by the first few px.
            property string axis: ""
            property real y0: 0
            onActiveChanged: {
                if (swipe.active) { swipe.axis = ""; glide.stop(); return }
                if (swipe.axis === "y") { root.coast(swipe.centroid.velocity.y); swipe.axis = ""; return }
                if (swipe.axis !== "x") return
                swipe.axis = ""
                const p = root.pull
                // Hand the pull to `pos` while the animations are off, then let them run.
                root.pos = root.pos + p
                root.pull = 0
                root.dragging = false
                const v = swipe.centroid.velocity.x
                if (p > 0.2 || v < -600) root.go(root.index + 1)
                else if (p < -0.2 || v > 600) root.go(root.index - 1)
                else root.go(root.index)
            }
            onTranslationChanged: {
                if (!swipe.active) return
                const t = swipe.translation
                if (swipe.axis === "") {
                    if (Math.abs(t.x) < 6 && Math.abs(t.y) < 6) return
                    swipe.axis = Math.abs(t.x) > Math.abs(t.y) ? "x" : "y"
                    if (swipe.axis === "x") root.dragging = true
                    else { const f = root._flick(); swipe.y0 = f ? f.contentY + t.y : 0 }
                }
                if (swipe.axis === "y") {
                    const f = root._flick()
                    if (f && f.contentHeight > f.height + 1) f.contentY = root._clampY(f, swipe.y0 - t.y)
                    return
                }
                let p = -t.x / viewport.step
                // A rubber band past the first and the last.
                if ((p < 0 && root.index === 0) || (p > 0 && root.index === root.count - 1)) p *= 0.25
                root.pull = Math.max(-1, Math.min(1, p))
            }
        }

        Component { id: changesPage; FeedChanges {} }
        Component { id: askPage; FeedAssistant {} }
        Component { id: newsPage; FeedNews {} }

        // Over the pages: the wheel only (see the header) — it never touches a press.
        Item {
            id: swipeLayer
            anchors.fill: parent
            z: 5
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function (event) {
                    // A touchpad's pixels are 1:1; a notch is ~150 px, glided.
                    const px = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
                    const dx = px ? -event.pixelDelta.x : -event.angleDelta.x / 120 * 150
                    const dy = px ? -event.pixelDelta.y * 1.2 : -event.angleDelta.y / 120 * 150
                    if (Math.abs(dx) > Math.abs(dy)) root.push(dx)
                    else root.scroll(dy, !px)
                }
            }
        }
    }
    // A page that runs past the rail dissolves into the card instead of ending in a hard cut mid-line
    // (2026-11-03 review). A gradient in the card's own colour OVER the viewport, as OverviewLyrics does its soft
    // edges — a MultiEffect alpha mask on the viewport's layer drew nothing here. Bottom only: the top holds the
    // page's header. It takes no input (a Rectangle has none), so scrolling and swiping reach the pages below it.
    Rectangle {
        z: 2
        anchors.left: viewport.left
        anchors.right: viewport.right
        anchors.bottom: viewport.bottom
        height: Tokens.spacingXl * 1.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard), 0) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard), 0.96) }
        }
    }
}
