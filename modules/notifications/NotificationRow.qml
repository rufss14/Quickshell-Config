pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../../config"
import "../../components"
import "../../services"
import "../../services/notifyview.js" as View

// ── NotificationRow ───────────────────────────────────────────────────────────
// One notification in the centre (NotificationGroups), as a TILE: the app's icon in a
// cookie, the summary with how long ago, the body, and — while the app still holds it
// live — its action buttons.
//
//   click     the default action while it's live, else focus (or start) the app
//   middle    dismiss
//   hover     copy, snooze (a pick of 15 min / 1 h / 3 h), ✕
//   reply     a field under the message, while the app still holds it AND offers one
//
// While the centre is SELECTING (`selecting`) a click ticks the tile instead, and the hover chips
// stay away — the host acts on the ticked ones together.
//
// ── The cookie is the app ─────────────────────────────────────────────────────
// Its icon sits in a ShapeBox holder (the cookie, unless Config.iconShape picks another —
// the same holder every panel header wears), tinted from the palette by the app's NAME, so
// one app is always the same colour and a stack of them reads as a set rather than a column
// of grey. A critical one wears the danger colour instead, tile and all, so a missed call
// still reads as one in the history. Pointing at a tile winds its cookie. A sender's avatar
// (a stable image: a file, a URL) replaces the icon, in a circle inside the cookie.
//
// ── Tiles that blend ──────────────────────────────────────────────────────────
// The tile is a faint wash of the text colour over whatever it sits on (the overview's card, or
// the panel's own surface), no outline: enough to read as a unit, not a box on a box. The cookie
// carries the colour. The ✕ is a HoverTray chip that springs in from the right while the text gives way
// to it; an action is a pill of its own (ChipTray).
//
// `actionable: false` (the lock screen) keeps the clicks, the action buttons and the
// links shut, so nothing opens an app behind the lock. Dismissing still works.
// Everything real is services/Notifications; this shows a record and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var rec
    property bool actionable: true
    // Arrived since you last opened the centre: a dot on its cookie.
    property bool fresh: false
    // The centre's accent (the dot); the panel passes its own.
    property color accent: Colors.of(QsWindow.window).primary
    // Select mode (the centre's): a click ticks the tile; `selected` is whether it is ticked.
    property bool selecting: false
    property bool selected: false
    signal toggled()

    // Removed by the ✕ or a middle-click (not by activating it) — the list passes it
    // up so the host can offer Undo.
    signal dismissed()

    readonly property bool critical: root.rec.urgency === NotificationUrgency.Critical
    readonly property bool hot: hover.hovered && root.actionable

    // ── The app's tone ────────────────────────────────────────────────────────
    // Chosen by a hash of the name, from the roles a wallpaper palette always has and that
    // mean no verdict (not success / warning / danger).
    readonly property int toneIndex: View.toneIndex(root.rec.appName, 3)
    readonly property color tone: root.critical ? Colors.of(QsWindow.window).danger
        : [Colors.of(QsWindow.window).primary, Colors.of(QsWindow.window).focus,
           Colors.of(QsWindow.window).info][root.toneIndex]

    radius: Tokens.radiusPill
    // Barely there at rest — a faint wash that lets the ground show through — and it comes up
    // under the pointer. No outline: that is what made the first tiles read as boxes.
    color: root.selected ? Colors.of(QsWindow.window).alpha(root.accent, 0.18)
         : root.critical
        ? Colors.of(QsWindow.window).alpha(root.tone, root.hot ? 0.20 : 0.12)
        : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, root.hot ? 0.07 : 0.035)
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    // The live Notification behind the record, or null once the app has let it go.
    // Read straight off the service's side table — never through the model, which is
    // what keeps QObjects out of delegate data (see Notifications' `_liveByKey`).
    readonly property var live: root.actionable ? Notifications.liveFor(root.rec) : null
    readonly property int actionCount: {
        if (!root.live) return 0
        let n = 0
        for (let i = 0; i < root.live.actions.length; i++)
            if (root.live.actions[i].identifier !== "default") n++
        return n
    }

    // The app offers an inline reply (a chat message) and still holds the notification.
    readonly property bool replyable: root.live !== null && root.live.hasInlineReply === true

    readonly property int cookie: Tokens.iconXl + Tokens.spacingMd

    // ── Copy, snooze: the hover chips' state ──────────────────────────────────
    property bool copied: false
    property bool snoozing: false
    Timer { id: copiedReset; interval: 1400; onTriggered: root.copied = false }
    function _copy() {
        Clipboard.copyText(root.rec.summary + (root.rec.body ? "\n" + root.rec.body : ""))
        root.copied = true
        copiedReset.restart()
    }
    function _snooze(minutes) { Notifications.snooze(root.rec, minutes) }

    // At least the cookie's height, so a one-line tile is still a whole tile.
    implicitHeight: Math.max(body.implicitHeight, root.cookie) + Tokens.spacingMd * 2

    // Signal first: the dismiss rebuilds the list's model, and this delegate with it.
    function _dismissNow() {
        const r = root.rec
        root.dismissed()
        Notifications.dismiss(r)
    }
    // It slides off to the right and fades before it goes (the swipe a toast dismisses with).
    function _dismiss() {
        if (leave.running) return
        if (Config.motionEnabled) leave.start(); else root._dismissNow()
    }
    transform: Translate { id: slide }
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.fast }
            NumberAnimation { target: slide; property: "x"; to: Tokens.spacingXxl * 2; duration: Motion.fast; easing.type: Easing.InQuad }
        }
        ScriptAction { script: root._dismissNow() }
    }

    HoverHandler {
        id: hover
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onTapped: function(point, button) {
            // A tap on a chip, or in the reply field, is theirs, not the tile's.
            if (closeTray.hovered || replyHover.hovered) return
            if (root.selecting) root.toggled()
            else if (button === Qt.MiddleButton) root._dismiss()
            else if (root.actionable) Notifications.activate(root.rec)
        }
    }

    RowLayout {
        id: body
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        // ── The tick, while selecting ─────────────────────────────────────────
        // Opens from nothing, so the tile's text isn't shoved about while the mode is off.
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.selecting ? root.cookie * 0.6 : 0
            Layout.preferredHeight: root.cookie
            // Out of the layout once shut, so its spacing goes too.
            visible: Layout.preferredWidth > 0.5
            clip: true
            opacity: root.selecting ? 1 : 0
            Behavior on Layout.preferredWidth { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }

            MaterialIcon {
                anchors.centerIn: parent
                name: root.selected ? "check_circle" : "radio_button_unchecked"
                fill: root.selected ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root.selected ? root.accent : Colors.of(QsWindow.window).fgDim
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        // ── The cookie ────────────────────────────────────────────────────────
        Item {
            id: cookieSlot
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth:  root.cookie
            Layout.preferredHeight: root.cookie

            // Winds a little under the pointer, as a card's heading chip does; the contents
            // counter-rotate so the icon stays upright.
            rotation: root.hot ? -9 : 0
            scale:    root.hot ? 1.08 : 1.0
            Behavior on rotation {
                NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
            }
            Behavior on scale {
                NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
            }

            ShapeBox {
                anchors.fill: parent
                fallback:    "cookie"
                extraPetal:  root.hot ? 0.06 : 0
                fillColor:   Colors.of(QsWindow.window).alpha(root.tone, root.hot ? 0.30 : 0.20)
                strokeColor: Colors.of(QsWindow.window).alpha(root.tone, 0.36)
            }

            Image {
                id: appIco
                anchors.centerIn: parent
                width:  Tokens.iconLg
                height: Tokens.iconLg
                rotation: -cookieSlot.rotation
                source: Notifications.appIconFor(root.rec)
                sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready && !avatar.visible
            }
            MaterialIcon {
                anchors.centerIn: parent
                rotation: -cookieSlot.rotation
                visible: appIco.status !== Image.Ready && !avatar.visible
                name: "notifications"
                fill: 1
                color: root.tone
                font.pixelSize: Tokens.iconLg
            }

            // A sender's avatar or an attachment, cropped to a circle. Records only keep a stable
            // image (a file, a URL); the session-bound kind is gone by now and the cookie keeps
            // the app's icon.
            ClippingRectangle {
                id: avatar
                anchors.centerIn: parent
                width:  root.cookie - Tokens.spacingMd
                height: width
                radius: width / 2
                visible: pic.status === Image.Ready
                color: Colors.of(QsWindow.window).surfaceContainer
                rotation: -cookieSlot.rotation

                Image {
                    id: pic
                    anchors.fill: parent
                    source: root.rec.image || ""
                    sourceSize: Qt.size(root.cookie * 2, root.cookie * 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
            }

            // Arrived since you last looked.
            Rectangle {
                visible: root.fresh
                anchors.right: parent.right
                anchors.top: parent.top
                width:  Tokens.spacingMd
                height: width
                radius: width / 2
                color: root.accent
                rotation: -cookieSlot.rotation
            }
        }

        // ── The message ───────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                // The text gives way to the chips as they spring in — less the time's pill, which
                // goes first (below), so the summary keeps most of its width.
                Layout.rightMargin: Math.max(0, closeTray.width - timePill.implicitWidth) * Math.min(1, closeTray.pop)
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    // An app that sends only a body still gets a headline.
                    text: root.rec.summary || root.rec.appName || "Notification"
                    variant: "body"
                    font.weight: Font.DemiBold
                    color: root.critical ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // How long ago, as a pill. Clock ticks once a minute, on the minute — enough for "5m".
                Rectangle {
                    id: timePill
                    Layout.alignment: Qt.AlignVCenter
                    // One width for "now", "9m" and "29m" alike, so the pills stack in a clean column.
                    implicitWidth:  Math.max(when.implicitWidth + Tokens.spacingMd * 2, Tokens.iconXl * 1.6)
                    implicitHeight: when.implicitHeight + Tokens.spacingXs * 2
                    Layout.preferredWidth: timePill.implicitWidth * (1 - Math.min(1, closeTray.pop))
                    opacity: 1 - Math.min(1, closeTray.pop)
                    clip: true
                    radius: height / 2
                    // No pill behind it: a time is a caption, and a grey capsule on every row was visual noise.
                    color: "transparent"

                    StyledText {
                        id: when
                        anchors.centerIn: parent
                        text: { void Clock.now; return Notifications.ago(root.rec.time) }
                        variant: "caption"
                        emphasis: "muted"
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.rec.body || ""
                variant: "caption"
                emphasis: "muted"
                // Same format the toast renders the body in, so a message reads
                // the same in both places.
                textFormat: Text.MarkdownText
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                onLinkActivated: (url) => { if (root.actionable) Qt.openUrlExternally(url) }
            }

            // ── A reply, while the app still holds it and takes one ───────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: replyField.implicitHeight
                Layout.topMargin: Tokens.spacingXs
                visible: root.replyable && !root.selecting

                HoverHandler { id: replyHover }
                InputField {
                    id: replyField
                    anchors.fill: parent
                    implicitHeight: Tokens.iconXl + Tokens.spacingMd
                    cornerRadius: implicitHeight / 2
                    icon: "reply"
                    placeholder: root.live ? (root.live.inlineReplyPlaceholder || "Reply…") : "Reply…"
                    onAccepted: (value) => Notifications.reply(root.rec, value)
                    onKeyPressed: (event) => {
                        if (event.key !== Qt.Key_Escape || replyField.text === "") return
                        replyField.clear(); replyField.blur(); event.accepted = true
                    }
                }
            }

            // ── Its actions, while the app can still answer them ──────────────
            Flow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin: Tokens.spacingXs
                visible: root.actionCount > 0 && !root.selecting
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.live ? root.live.actions : []

                    ChipTray {
                        id: act
                        required property var modelData
                        // "default" is the tile's own click, not a button.
                        groupShown: act.modelData.identifier !== "default"
                        ChipButton {
                            label: act.modelData.text
                            tint:  root.tone
                            onActivated: {
                                Notifications.invoke(act.modelData)
                                Notifications.dismiss(root.rec)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── The chips, under the pointer ──────────────────────────────────────────
    // Copy, snooze and ✕ — a row of them on every tile at once was a column of chips louder
    // than the messages, so they spring in from the right edge for the hovered tile only (as
    // the Clock panel's reminders do). Snooze turns the tray into its three lengths. Last, so
    // it sits over the body.
    HoverTray {
        id: closeTray
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingMd
        anchors.top: parent.top
        anchors.topMargin: Tokens.spacingXs
        shown: hover.hovered && !root.selecting
        // Pointer gone, the pick goes with it.
        onShownChanged: if (!closeTray.shown) root.snoozing = false

        ChipButton {
            visible: root.actionable && !root.snoozing
            symbol:  root.copied ? "check" : "content_copy"
            tint:    root.accent
            onActivated: root._copy()
        }
        ChipButton {
            visible: root.actionable && !root.snoozing
            symbol:  "snooze"
            tint:    root.accent
            onActivated: root.snoozing = true
        }
        ChipButton { visible: root.snoozing; label: "15 min"; tint: root.accent; onActivated: root._snooze(15) }
        ChipButton { visible: root.snoozing; label: "1 hour"; tint: root.accent; onActivated: root._snooze(60) }
        ChipButton { visible: root.snoozing; label: "3 hours"; tint: root.accent; onActivated: root._snooze(180) }
        ChipButton {
            symbol: "close"
            tint:   Colors.of(QsWindow.window).danger
            onActivated: { if (root.snoozing) root.snoozing = false; else root._dismiss() }
        }
    }
}
