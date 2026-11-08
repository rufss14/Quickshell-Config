pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/claudeusage.js" as Usage

// ── ClaudePanel ───────────────────────────────────────────────────────────────
// Claude Code on this machine (services/ClaudeSessions), beside the sidebar's Claude
// module: the account's rate limit, the sessions running now, and the recent ones you
// can pick up again.
//
// ── The usage card ────────────────────────────────────────────────────────────
// The 5-hour and weekly limits, each a bar, a percentage and when it resets ("in 2h 14m ·
// 13:14"). Claude Code only hands that to a status line, so it needs the same optional
// connection as the hook, and it is as fresh as the last session that reported — the
// card says so once the figures are old. A window that has reset reads empty
// (services/claudeusage.js).
//
// ── Recent ────────────────────────────────────────────────────────────────────
// Ended sessions, any project (the helper's header says how they're found). A click
// RESUMES one in a terminal, in the directory it was started from — "Resume in
// quicktest" — and "New" starts a session in this shell's own directory, which is
// where it is worked on. A running session's click still goes to its terminal.
//
// Running, one row each, the ones that need you first:
//
//   · its title (the session's AI title), project, model and how full its context is;
//   · what it's doing — working (the mark turning, and the tool it's on: "Edit ·
//     Lens.qml"), waiting on your permission ("Wants to use Bash", warning colour,
//     pulsing), waiting for you, or finished (its last reply's first line);
//   · how long it's been like that;
//   · click: its terminal, focused.
//
// Without the connection it still lists them, working or not; a card offers it
// (scripts/install-claude-hooks.py — an async hook and a status line, recording no
// prompts or commands) for the "needs you" half and the usage. Opening the panel marks
// finished turns seen.
//
// Motion: rows arrive and leave like the voice panel's people; a row's state crossfades;
// a working session's mark turns (the panel is only up while you look at it).
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 9
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 6,
        root.maxHeight - root.pad * 2 - head.implicitHeight - offer.implicitHeight
        - usage.implicitHeight - col.spacing * 3))

    // The directory "New" starts in: this shell's own ("quicktest"), by its last segment.
    readonly property string homeProject: Quickshell.shellDir.replace(/\/+$/, "").split("/").pop()

    // Wall-clock minute: what "resets in …" is measured against.
    readonly property real nowMs: Clock.now.getTime()
    readonly property var five: Usage.limit(ClaudeSessions.rate.five_hour, root.nowMs)
    readonly property var week: Usage.limit(ClaudeSessions.rate.seven_day, root.nowMs)
    readonly property string rateAge: Usage.stale(ClaudeSessions.rate.at, root.nowMs)

    // Running, then recent, in one list. A ScriptModel exposes only `modelData`, so there are
    // no roles for a ListView section to group by: the FIRST row of each kind carries its
    // heading (`first`) and draws it. Keyed by what is unique — two live rows can share a
    // session id (a session resumed while the first is still up), so they differ by pid.
    readonly property var rows: {
        const out = []
        ClaudeSessions.sessions.forEach((s, i) => out.push(Object.assign({ kind: "live", key: "p" + s.pid, first: i === 0 }, s)))
        ClaudeSessions.recent.forEach((s, i) => out.push(Object.assign({ kind: "recent", key: "s" + s.sid, first: i === 0 }, s)))
        return out
    }

    Component.onCompleted: ClaudeSessions.markSeen()
    Connections {
        target: ClaudeSessions
        function onFreshChanged() { if (ClaudeSessions.anyFresh) ClaudeSessions.markSeen() }
    }

    ArmLatch {
        id: removeLatch
        onConfirmed: ClaudeSessions.removeHooks()
    }

    function ago(ms) {
        if (!ms) return ""
        const s = Math.max(0, Math.floor((Clock.now.getTime() - ms) / 1000))
        if (s < 60) return "now"
        const m = Math.floor(s / 60)
        if (m < 60) return m + "m"
        const h = Math.floor(m / 60)
        if (h >= 48) return Math.floor(h / 24) + "d"
        return h + "h" + (m % 60 > 0 && h < 10 ? " " + (m % 60) + "m" : "")
    }
    function tokens(n) {
        return n >= 1000000 ? (n / 1000000).toFixed(1) + "M" : n >= 1000 ? Math.round(n / 1000) + "k" : String(n)
    }

    Component {
        id: burstMark
        ClaudeBurst {
            width: Tokens.iconLg
            height: Tokens.iconLg
            playing: true
            tint: Colors.of(QsWindow.window).primary
        }
    }

    // One limit: its name and percentage, the bar, and when it resets.
    component UsageRow: ColumnLayout {
        id: ur
        property string label: ""
        property var info: null            // Usage.limit(): null = not reported yet
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            StyledText {
                text: ur.label
                variant: "label"
                emphasis: "muted"
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: !ur.info ? "—" : ur.info.reset ? "Reset" : ur.info.pct + "%"
                font.bold: true
                font.family: Tokens.fontMono
            }
        }
        Meter {
            Layout.fillWidth: true
            value: ur.info ? ur.info.ratio : 0
            accent: Colors.of(QsWindow.window).primary
            opacity: ur.info ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
            text: !ur.info ? "Not reported yet"
                : ur.info.reset ? "Reset — fresh window"
                : "Resets in " + ur.info.left + "  ·  " + ur.info.when
        }
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            Layout.fillHeight: false
            glyph:     "\u{F06C4}"                                           // 󰛄 asterisk
            // While any session works the chip plays the burst.
            mark:      ClaudeSessions.busyCount > 0 ? burstMark : null
            title:     Translation.tr("Claude")
            titleTail: "sessions"
            accent:    Colors.of(QsWindow.window).primary
            subtitle: {
                if (ClaudeSessions.lastError !== "") return ClaudeSessions.lastError
                const n = ClaudeSessions.sessions.length
                const r = ClaudeSessions.recent.length
                if (n === 0) {
                    if (!ClaudeSessions.ready) return "Looking…"
                    return r > 0 ? "Nothing running · " + r + " to resume" : "Nothing running"
                }
                const bits = []
                if (ClaudeSessions.needsYou.length > 0) bits.push(ClaudeSessions.needsYou.length + " need" + (ClaudeSessions.needsYou.length === 1 ? "s" : "") + " you")
                if (ClaudeSessions.busyCount > 0) bits.push(ClaudeSessions.busyCount + " working")
                const idle = n - ClaudeSessions.busyCount - ClaudeSessions.needsYou.length
                if (idle > 0) bits.push(idle + " waiting")
                return bits.join(" · ")
            }

            ActionGroup {
                PanelButton {
                    variant: "ghost"
                    symbol: "add"
                    label: "New in " + root.homeProject
                    onActivated: ClaudeSessions.newSession()
                }
                PanelButton {
                    visible: ClaudeSessions.hooksInstalled
                    variant: removeLatch.armed ? "primary" : "ghost"
                    accent: Colors.of(QsWindow.window).danger
                    symbol: "link_off"
                    label: removeLatch.armed ? "Disconnect?" : ""
                    onActivated: removeLatch.trigger()
                }
            }
        }

        // ── The hooks, offered ────────────────────────────────────────────────
        Rectangle {
            id: offer
            Layout.fillWidth: true
            visible: ClaudeSessions.ready && !ClaudeSessions.hooksInstalled
            implicitHeight: visible ? offerCol.implicitHeight + Tokens.spacingMd * 2 : 0
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.08)
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.3)
            ColumnLayout {
                id: offerCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Know when Claude needs you, and your usage")
                    font.bold: true
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "muted"
                    text: Translation.tr("Adds a small async hook and a status line to Claude Code's settings ")
                        + "(a backup is kept; a status line you already have keeps working). They "
                        + "record which tool a session is on, its permission prompts and your usage "
                        + "limits — never your prompts or the commands it runs."
                }
                PanelButton {
                    variant: "primary"
                    symbol: "link"
                    label: ClaudeSessions.hooksBusy ? "Connecting…" : "Connect"
                    enabled: !ClaudeSessions.hooksBusy
                    onActivated: ClaudeSessions.installHooks()
                }
            }
        }

        // ── The rate limit ────────────────────────────────────────────────────
        Rectangle {
            id: usage
            Layout.fillWidth: true
            visible: ClaudeSessions.hooksInstalled || ClaudeSessions.rate.at > 0
            implicitHeight: visible ? usageCol.implicitHeight + Tokens.spacingMd * 2 : 0
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.03)
            ColumnLayout {
                id: usageCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    StyledText {
                        text: Translation.tr("Usage limits")
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: root.rateAge !== ""
                        text: "as of " + root.rateAge
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
                // Side by side: stacked, each limit took three lines of a wide card.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingLg
                    UsageRow { Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "5-hour"; info: root.five }
                    UsageRow { Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Weekly";  info: root.week }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: ClaudeSessions.rate.at === 0
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: Translation.tr("Claude reports these after a session's next reply.")
                }
            }
        }

        // ── Nothing at all ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingSm
            Layout.bottomMargin: Tokens.spacingSm
            visible: root.rows.length === 0
            spacing: Tokens.spacingSm
            ClaudeGlyph {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Tokens.fontNumeralMd
                implicitHeight: Tokens.fontNumeralMd
                tint: Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                variant: "caption"
                emphasis: "dim"
                text: Translation.tr("No Claude Code sessions yet. Start one in a terminal and it shows up here.")
                wrapMode: Text.WordWrap
            }
        }

        // ── Running, then recent ──────────────────────────────────────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.listRoom)
            visible: root.rows.length > 0
            clip: true
            interactive: contentHeight > height
            spacing: Tokens.spacingXs
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel {
                values: root.rows
                objectProp: "key"
            }

            populate: Transition {
                id: pop
                SequentialAnimation {
                    PropertyAction { property: "opacity"; value: 0 }
                    PauseAnimation { duration: Math.min(pop.ViewTransition.index * Motion.stagger * 2, Motion.staggerCap) }
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                        NumberAnimation { property: "x"; from: Tokens.spacingLg; to: 0; duration: Motion.emphasized; easing.type: Motion.enter }
                    }
                }
            }
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                    NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
            }
            move: Transition {
                NumberAnimation { property: "y"; duration: Motion.standard; easing.type: Motion.travel }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Motion.standard; easing.type: Motion.travel }
            }

            delegate: Item {
                id: row
                required property var modelData
                readonly property var s: row.modelData
                readonly property bool live: row.s.kind === "live"
                readonly property bool working: row.s.status === "busy" && row.s.attention === ""
                readonly property bool permission: row.s.attention === "permission"
                readonly property bool asking: row.s.attention === "input"
                readonly property color tone: row.permission ? Colors.of(QsWindow.window).warning
                                            : row.asking ? Colors.of(QsWindow.window).focus
                                            : row.working ? Colors.of(QsWindow.window).primary
                                            : Colors.of(QsWindow.window).fgMuted
                readonly property string line2: !row.live
                    ? "Resume in " + row.s.project + (row.s.model !== "" ? "  ·  " + row.s.model : "")
                    : row.permission || row.asking ? (row.s.message || "Waiting for you")
                    : row.working ? (row.s.activity !== "" ? row.s.activity : "Working…")
                    : row.s.last !== "" ? row.s.last
                    : "Waiting for you"

                // The group's heading sits above the first row of the group.
                readonly property real headH: row.s.first ? secLabel.implicitHeight + Tokens.spacingSm : 0

                width: list.width
                height: row.headH + rowLayout.implicitHeight + Tokens.spacingSm * 2

                StyledText {
                    id: secLabel
                    visible: row.s.first
                    x: Tokens.spacingSm
                    text: row.live ? "Running" : "Recent · click to resume"
                    variant: "caption"
                    emphasis: "dim"
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: row.headH
                    radius: Tokens.radiusSm
                    color: rowMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                         : row.permission ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.10)
                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.03)
                    border.width: row.permission ? Tokens.borderWidth : 0
                    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.5)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }

                RowLayout {
                    id: rowLayout
                    x: Tokens.spacingSm
                    y: row.headH + Tokens.spacingSm
                    width: row.width - Tokens.spacingSm * 2
                    spacing: Tokens.spacingMd

                    // State: the mark (turning while it works), in the state's tone.
                    Item {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: Tokens.iconXl
                        implicitHeight: Tokens.iconXl
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Colors.of(QsWindow.window).alpha(row.tone, 0.14)
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                            SequentialAnimation on opacity {
                                running: row.permission && Motion.slow > 0
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.4; duration: Motion.slow * 1.5; easing.type: Motion.ambient }
                                NumberAnimation { to: 1;   duration: Motion.slow * 1.5; easing.type: Motion.ambient }
                            }
                        }
                        // Working: the animated burst. Otherwise the still mark, in the state's tone.
                        ClaudeGlyph {
                            anchors.centerIn: parent
                            width: Tokens.iconLg
                            height: Tokens.iconLg
                            visible: !row.working
                            tint: row.tone
                        }
                        ClaudeBurst {
                            anchors.centerIn: parent
                            width: Tokens.iconLg
                            height: Tokens.iconLg
                            visible: row.working
                            playing: row.working
                            tint: row.tone
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: row.s.title
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.line2
                            variant: "label"
                            color: row.permission || row.asking || row.working ? row.tone : Colors.of(QsWindow.window).fgMuted
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: [row.s.project, row.s.model,
                                   row.s.context > 0 ? root.tokens(row.s.context) + " context" : ""]
                                  .filter(t => t !== "").join("  ·  ")
                            visible: row.live && text !== ""
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        Layout.alignment: Qt.AlignTop
                        spacing: Tokens.spacingXs
                        StyledText {
                            anchors.right: parent.right
                            text: root.ago(row.s.since)
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                        MaterialIcon {
                            anchors.right: parent.right
                            name: row.live ? "chevron_right" : "play_arrow"     // → its terminal / resume
                            variant: "body"
                            color: Colors.of(QsWindow.window).primary
                            opacity: rowMouse.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.topMargin: row.headH
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.live ? ClaudeSessions.focus(row.s.pid) : ClaudeSessions.resume(row.s)
                }
            }
        }
    }
}
