pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/sidemodules.js" as Side

// ── SideVoice ─────────────────────────────────────────────────────────────────
// Your voice, at a glance. In a Discord call (services/Discord): the people in it
// as faces, a ring round whoever is talking, dimmed while they can't hear or be
// heard — past three, the last face is a "+n" — then your mute and deafen. Out of
// a call: your mic, muted or not (services/Audio).
//
// A face (or the "+n") opens the call panel beside it (VoicePanel: everyone, your
// own levels, leave); RIGHT-click a face and it opens on that person — their volume
// and mute, for you. Right-click the mic or deafen: the sidebar's settings.
//
// ── The level ─────────────────────────────────────────────────────────────────
// A bar under the mic says how loud you are — while you're in a call, or while the
// pointer is on it (the "am I coming through?" moments), and never while muted. A
// meter is a real capture stream (PwNodePeakMonitor), so it doesn't run the rest of
// the time; it's a monitor stream, which Audio already leaves out of "who is
// recording you", so it never lights the privacy pill.
//
// The speaking ring is the palette's focus colour, not Discord's green: that green
// is a sanctioned brand constant scoped to the overview's call card, and the list
// of those doesn't grow (CLAUDE.md).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    property var screen: null

    // SideRail.cellsFor asks sidemodules.js the same question.
    readonly property var layout: Side.voiceLayout(Discord.inCall, Discord.users.length)
    readonly property var faces: Discord.inCall ? Discord.users.slice(0, root.layout.faces) : []

    // Muted where it counts: Discord's own mute in a call, the mic's everywhere else.
    readonly property bool micMuted: Discord.inCall ? Discord.mute : (Audio.source?.audio?.muted ?? false)

    readonly property bool hovered: hover.hovered
    HoverHandler { id: hover }

    PwNodePeakMonitor {
        id: peak
        node: Audio.source
        enabled: (Discord.inCall || root.hovered) && !root.micMuted
                 && peak.node !== null && Audio.hasKnownChannels(peak.node)
    }
    readonly property real level: peak.enabled ? Audio.meterLevel(peak.peak) : 0

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(root.layout.cells)
    implicitHeight: root.vertical ? Config.sidebarRun(root.layout.cells) : Config.sidebarCell

    Grid {
        // The stack, the mic and deafen: at most three things side by side along the bottom
        // (a Grid skips what isn't visible). Not `layout.cells`: the stack's are fractional.
        columns: root.vertical ? 1 : 3
        spacing: Config.sidebarCellGap

        // ── The faces: one overlapping stack ─────────────────────────────────
        // Material's avatar group (2026-10-31, the user's pick for a quieter sidebar): the
        // faces smaller and overlapping down the edge, each ringed in the pill's own colour
        // so the overlap reads, the "+n" the last of them — one cell for two, half a cell
        // for each after (sidemodules.js stackCells), where it was a full cell a face. The
        // speaking ring, the dimming and the swell-in on joining stay per face. A click is
        // the call panel; a right-click opens it on the face under the pointer.
        Item {
            id: stack
            visible: root.layout.stack > 0

            readonly property real run: Config.sidebarRun(Side.stackCells(root.layout.stack))
            readonly property int  face: Math.round(Config.sidebarIconPx * 0.75)
            // The pill's colour round each face, separating it from the one it overlaps.
            readonly property int  sep: Tokens.borderChrome
            readonly property real step: Math.round(stack.face * 0.6)
            readonly property real span: stack.face + Math.max(0, root.layout.stack - 1) * stack.step
            readonly property real start: (stack.run - stack.span) / 2

            width:  root.vertical ? Config.sidebarCell : stack.run
            height: root.vertical ? stack.run : Config.sidebarCell

            // Where the i-th thing in the stack is centred, along the edge.
            function centreOf(i) { return stack.start + stack.face / 2 + i * stack.step }
            // Which face a point along the edge falls on (the nearest centre), or -1.
            function faceAt(along) {
                const i = Math.round((along - stack.start - stack.face / 2) / Math.max(1, stack.step))
                return i >= 0 && i < root.faces.length ? i : -1
            }

            CellFeedback {
                id: stackFeedback
                anchors.fill: parent
                hovered: stackMouse.containsMouse
            }

            // A ScriptModel, keyed by person: a join, a leave or a speaking change must not
            // rebuild every face (and replay every entrance).
            Repeater {
                model: ScriptModel {
                    values: root.faces
                    objectProp: "id"
                }

                Item {
                    id: person
                    required property var modelData
                    required property int index

                    readonly property bool speaking: person.modelData.speaking ?? false
                    readonly property bool muted: (person.modelData.selfMute ?? false)
                                               || (person.modelData.serverMute ?? false)
                    readonly property bool deafened: (person.modelData.selfDeaf ?? false) || (person.modelData.serverDeaf ?? false)
                    readonly property int  ring: Tokens.borderChrome
                    readonly property real centre: stack.centreOf(person.index)

                    width:  stack.face + (stack.sep + person.ring) * 2
                    height: width
                    x: root.vertical ? Math.round((stack.width - width) / 2) : Math.round(person.centre - width / 2)
                    y: root.vertical ? Math.round(person.centre - height / 2) : Math.round((stack.height - height) / 2)

                    // Joining: the face swells in on the spring.
                    property real arrive: 0
                    Component.onCompleted: person.arrive = 1
                    Behavior on arrive {
                        NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                    }
                    scale: 0.6 + 0.4 * person.arrive

                    // Dimmed while they can't be heard — by anyone, or by you (muted for you).
                    property real dim: person.muted || person.deafened || (person.modelData.mute ?? false) ? 0.5 : 1
                    Behavior on dim { NumberAnimation { duration: Motion.respond } }
                    opacity: person.arrive * person.dim

                    // Who's talking: a ring round the face, the accent's.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: person.ring
                        border.color: Colors.of(QsWindow.window).focus
                        opacity: person.speaking ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                    // The pill's colour, cut round the face where it overlaps the next.
                    Rectangle {
                        anchors.centerIn: parent
                        width:  stack.face + stack.sep * 2
                        height: width
                        radius: width / 2
                        color: Colors.of(QsWindow.window).surfaceContainer
                    }
                    Avatar {
                        anchors.centerIn: parent
                        width:  stack.face
                        height: stack.face
                        source: person.modelData.avatar ?? ""
                        name:   person.modelData.name ?? ""
                        // Talking leans the face in, a touch.
                        scale: person.speaking ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.respondCurve } }
                    }
                }
            }

            // ── Everyone past the faces: the last of the stack ────────────────
            Item {
                visible: root.layout.more > 0
                readonly property real centre: stack.centreOf(root.layout.faces)
                width:  stack.face + stack.sep * 2
                height: width
                x: root.vertical ? Math.round((stack.width - width) / 2) : Math.round(centre - width / 2)
                y: root.vertical ? Math.round(centre - height / 2) : Math.round((stack.height - height) / 2)

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.of(QsWindow.window).surfaceContainer
                }
                Rectangle {
                    anchors.centerIn: parent
                    width:  stack.face
                    height: width
                    radius: width / 2
                    color: Colors.of(QsWindow.window).surfaceHigh
                }
                StyledText {
                    anchors.centerIn: parent
                    text: "+" + root.layout.more
                    variant: "caption"
                    font.bold: true
                    color: stackMouse.containsMouse ? Config.moduleAccent("voice", Colors.of(QsWindow.window).primary) : Colors.of(QsWindow.window).fgMuted
                }
            }

            // Click: the call panel. Right-click: the panel on the face under the pointer —
            // their volume and mute, for you.
            MouseArea {
                id: stackMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onPressed: function (m) { stackFeedback.press(m.x, m.y) }
                onReleased: stackFeedback.release()
                onCanceled: stackFeedback.release()
                onClicked: function (m) {
                    const i = m.button === Qt.RightButton ? stack.faceAt(root.vertical ? m.y : m.x) : -1
                    UiState.toggleSidePanel("voice", "voice", root.screen,
                        i >= 0 ? (root.faces[i].id ?? "") : "")
                }
            }
        }

        // ── Your mic: Discord's mute in a call, the mic's own out of one ──────
        SideCell {
            id: mic
            hoverKind: "voice"
            glyph: root.micMuted ? "\u{F036D}" : "\u{F036C}"            // 󰍭 mic-off / 󰍬 mic
            tint: root.micMuted ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).stateIdleFg
            onClicked: Discord.inCall ? Discord.toggleMute() : Audio.toggleMicMute()
            onRightClicked: UiState.openSettingsTo("SidebarPage.qml")

            // How loud you are, while it's worth knowing (see the header).
            Meter {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.spacingXs
                width: Config.sidebarGlyphPx
                height: Tokens.spacingXs
                visible: peak.enabled
                value: root.level
                accent: Colors.of(QsWindow.window).primary
                fillDuration: Motion.track
            }
        }

        // ── Deafen, in a call ─────────────────────────────────────────────────
        SideCell {
            visible: Discord.inCall
            glyph: Discord.deaf ? "\u{F07CE}" : "\u{F02CB}"             // 󰟎 headphones-off / 󰋋 headphones
            tint: Discord.deaf ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).stateIdleFg
            onClicked: Discord.toggleDeaf()
            onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
        }
    }
}
