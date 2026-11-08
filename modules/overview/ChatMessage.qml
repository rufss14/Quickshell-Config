import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── ChatMessage ───────────────────────────────────────────────────────────────
// One turn on the Ask page (FeedAssistant's ListView). Yours: a bubble in the accent, on the right,
// its corner nearest you tucked in. The AI's: the cookie avatar on the left and a quiet bubble
// beside it, its corner nearest the avatar tucked in — then what it did, a card each
// (ChatActionCard), indented under the words.
//
// A reply that has just arrived (`fresh`) types itself out — the words a few at a time, quick for a
// short one and never more than ~1.2 s — and its cards deal in, one after another, once the words are
// out. An older one (rebuilt, scrolled back to) is simply there. Arriving at all is the ListView's
// `add` transition.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property int index
    required property int m
    required property string role
    required property string body
    required property string acts        // the actions, as JSON (a ListModel holds no arrays)
    required property bool fresh
    property color accent: Colors.of(QsWindow.window).primary

    readonly property bool mine: root.role === "user"
    readonly property var actions: { try { return JSON.parse(root.acts) } catch (e) { return [] } }
    readonly property int avatar: 26
    readonly property real maxBubble: root.width * (root.mine ? 0.82 : 0.86) - (root.mine ? 0 : root.avatar + Tokens.spacingSm)

    width: ListView.view ? ListView.view.width : 0
    height: col.implicitHeight
    transformOrigin: root.mine ? Item.BottomRight : Item.BottomLeft

    // ── Typing it out ─────────────────────────────────────────────────────────
    property int shown: root.fresh && !root.mine && Config.motionEnabled ? 0 : root.body.length
    readonly property bool typed: root.shown >= root.body.length
    NumberAnimation on shown {
        running: root.fresh && !root.mine && Config.motionEnabled
        from: 0
        to: root.body.length
        duration: Math.min(1200, root.body.length * 16)
    }

    // ── The avatar ────────────────────────────────────────────────────────────
    ScallopChip {
        visible: !root.mine
        x: 0
        y: 0
        implicitWidth: root.avatar
        implicitHeight: root.avatar
        symbol: "auto_awesome"
        tint: root.accent
        hot: !root.typed
    }

    Column {
        id: col
        x: root.mine ? 0 : root.avatar + Tokens.spacingSm
        width: root.width - x
        spacing: Tokens.spacingXs + 2

        // ── The words ─────────────────────────────────────────────────────────
        Rectangle {
            id: bubble
            readonly property int padH: Tokens.spacingMd
            readonly property int padV: Tokens.spacingSm + 1
            readonly property int r: 16
            visible: root.body !== ""
            x: root.mine ? col.width - bubble.width : 0
            width: Math.min(said.implicitWidth, root.maxBubble - bubble.padH * 2) + bubble.padH * 2
            height: said.height + bubble.padV * 2
            radius: bubble.r
            topLeftRadius: root.mine ? bubble.r : 5
            bottomRightRadius: root.mine ? 5 : bubble.r
            color: root.mine ? root.accent : Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, 0.94)
            border.width: root.mine ? 0 : Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)

            StyledText {
                id: said
                x: bubble.padH
                y: bubble.padV
                width: Math.min(implicitWidth, root.maxBubble - bubble.padH * 2)
                // The whole text sizes the bubble; only the typed part is drawn, so it never resizes
                // as it types.
                text: root.body
                color: "transparent"
                variant: "label"
                wrapMode: Text.Wrap
                lineHeight: 1.1
            }
            StyledText {
                x: said.x
                y: said.y
                width: said.width
                text: root.body.slice(0, root.shown)
                variant: "label"
                wrapMode: Text.Wrap
                lineHeight: 1.1
                color: root.mine ? (root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg)
                                 : Colors.of(QsWindow.window).fg
            }
        }

        // ── What it did ───────────────────────────────────────────────────────
        Repeater {
            model: root.actions
            delegate: ChatActionCard {
                id: card
                required property var modelData
                required property int index
                width: Math.min(col.width, Math.max(root.maxBubble, col.width * 0.9))
                act: card.modelData
                msg: root.m
                slot: card.index
                accent: root.accent

                // Dealt in, one after another, once the words are out.
                readonly property bool deal: root.fresh && Config.motionEnabled
                opacity: card.deal ? 0 : 1
                transform: Translate { id: lift; y: card.deal ? Tokens.spacingMd : 0 }
                SequentialAnimation {
                    running: card.deal && root.typed
                    PauseAnimation { duration: card.index * Motion.stagger * 2 }
                    ParallelAnimation {
                        NumberAnimation { target: card; property: "opacity"; to: 1; duration: Motion.standard }
                        NumberAnimation { target: lift; property: "y"; to: 0; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                    }
                }
            }
        }
    }
}
