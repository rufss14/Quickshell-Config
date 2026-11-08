pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── EventPeek ─────────────────────────────────────────────────────────────────
// The clips peek for every other module (2026-10-31, the user's pick: "event peeks"):
// something happens to a module, and a card opens beside it for a moment — on the
// focused monitor, into a free slot (components/SidePeek decides), closing itself
// (SidePanelDock's `autoCloseMs`; later while the pointer rests on it). One card, a kind
// per event (UiState.sidePanelArg), each behind its own Config switch:
//
//   timer       a countdown finished, an alarm rings: dismiss / snooze (Config.peekTimer)
//   claude      a session needs you, or finished a turn: go to it (Config.peekClaude)
//   colour      a colour was picked: its swatch and hex, already copied (Config.peekColour)
//   clipboard   a copy landed: its text or its picture (Config.peekClipboard)
//
// The event's own shape leads it (the LiveShape vocabulary: a burst asks for you, a
// cookie says something finished), so the card and the cell it came from read as one.
//
// ── It keeps its own copy ─────────────────────────────────────────────────────
// Taken when it opens and never cleared (CLAUDE.md's fade rule): the alarm dismissed,
// the session answered or the next copy must not rewrite a card on its way out.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    // An interaction timing, not a Motion duration (ClipsPeek's note): something to act on
    // stays longer than something only to see.
    readonly property int autoCloseMs: root.kind === "timer" || root.kind === "claude" ? 6000
                                     : root.kind === "clipboard" ? 2000 : 2600

    readonly property int pad: Tokens.spacingMd
    readonly property int maxW: Tokens.sideCardUnit * 6
    implicitWidth: Math.min(root.maxW, Math.max(Tokens.sideCardUnit * 4, col.implicitWidth + root.pad * 2))
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    property string kind: ""
    property var held: null

    function _pad2(n) { return (n < 10 ? "0" : "") + n }
    function _take(kind) {
        switch (kind) {
        case "timer": {
            const a = Timers.ringing
            return a ? { alarm: true, title: "Alarm", detail: root._pad2(a.h) + ":" + root._pad2(a.m) }
                     : { alarm: false, title: Timers.mode === "focus" ? Timers.pomoLabel + " done" : "Timer done",
                         detail: "" }
        }
        case "claude": {
            const s = ClaudeSessions.needsYou[0] ?? null
            // The session that finished last: `fresh` grows at its end.
            const sid = ClaudeSessions.fresh.length > 0 ? ClaudeSessions.fresh[ClaudeSessions.fresh.length - 1] : ""
            const done = s ? null : (ClaudeSessions.sessions.find(x => x.sid === sid) ?? null)
            const t = s ?? done
            return { needs: !!s, pid: t ? t.pid : 0,
                     title: s ? "Claude needs you" : "Claude finished",
                     detail: t ? (t.title || t.project || "") : "",
                     message: s ? (s.message || "") : "" }
        }
        case "colour":
            return { hex: ColorPicker.lastPicked }
        case "clipboard": {
            const e = Clipboard.count > 0 ? Clipboard.entries[0] : null
            return e ? { image: e.kind === "image", file: e.file || "", preview: e.preview || "",
                         lines: e.lines || 0, w: e.w || 0, h: e.h || 0 } : null
        }
        }
        return null
    }
    Component.onCompleted: {
        root.kind = UiState.sidePanelArg
        root.held = root._take(root.kind)
    }

    // The lead shape and its glyph, per event.
    readonly property string leadShape: root.kind === "timer" ? "burst"
        : root.kind === "claude" ? (root.held && root.held.needs ? "burst" : "cookie9")
        : root.kind === "colour" ? "circle" : "cookie9"
    readonly property color leadTone: root.kind === "timer"
        ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.22)
        : root.kind === "claude" && root.held && root.held.needs
        ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.22)
        // The picked colour itself: data, the way SideColour's swatches are.
        : root.kind === "colour" && root.held && root.held.hex !== "" ? root.held.hex
        : Colors.of(QsWindow.window).primaryContainer
    readonly property color leadInk: root.kind === "timer" ? Colors.of(QsWindow.window).danger
        : root.kind === "claude" && root.held && root.held.needs ? Colors.of(QsWindow.window).warning
        : Colors.of(QsWindow.window).fgOnPrimaryContainer
    readonly property string leadSymbol: root.kind === "timer" ? (root.held && root.held.alarm ? "alarm" : "timer")
        : root.kind === "claude" ? (root.held && root.held.needs ? "notifications_active" : "check")
        : root.kind === "colour" ? "" : "check"

    readonly property string title: !root.held ? ""
        : root.kind === "colour" || root.kind === "clipboard" ? "Copied" : root.held.title
    readonly property string detail: !root.held ? ""
        : root.kind === "colour" ? root.held.hex.toUpperCase()
        : root.kind === "clipboard" ? (root.held.image ? root.held.w + " × " + root.held.h + " image"
                                       : root.held.lines > 1 ? root.held.lines + " lines" : "")
        : root.held.detail

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: root.pad
        width: Math.min(implicitWidth, root.maxW - root.pad * 2)
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                Layout.preferredWidth: Tokens.iconXl
                Layout.preferredHeight: Tokens.iconXl
                MorphShape {
                    anchors.fill: parent
                    shape: root.leadShape
                    fillColor: root.leadTone
                    // A picked colour the card's own colour would vanish: the pill's outline.
                    strokeColor: root.kind === "colour" ? Colors.of(QsWindow.window).outline : "transparent"
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.leadSymbol !== ""
                    name: root.leadSymbol
                    fill: 1
                    font.pixelSize: Math.round(Tokens.iconXl * 0.55)
                    color: root.leadInk
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.bold: true
                    text: root.title
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.detail !== ""
                    elide: Text.ElideRight
                    variant: "caption"
                    emphasis: "dim"
                    text: root.detail
                }
            }
        }

        // Claude's question, when it asked one.
        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: root.maxW - root.pad * 2
            visible: root.kind === "claude" && !!root.held && root.held.message !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            variant: "caption"
            text: root.held && root.held.message ? root.held.message : ""
        }

        // The copy itself: its picture, or its first lines.
        Image {
            Layout.fillWidth: true
            Layout.maximumWidth: root.maxW - root.pad * 2
            Layout.preferredHeight: visible ? Math.round(width * 9 / 16) : 0
            visible: root.kind === "clipboard" && !!root.held && root.held.image && root.held.file !== ""
            source: visible ? "file://" + root.held.file : ""
            sourceSize.width: root.maxW
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: root.maxW - root.pad * 2
            visible: root.kind === "clipboard" && !!root.held && !root.held.image && root.held.preview !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            variant: "caption"
            font.family: Tokens.fontMono
            text: root.kind === "clipboard" && root.held && !root.held.image ? root.held.preview : ""
        }

        // What you'd do next, as the panel's own chips.
        ChipTray {
            visible: root.kind === "timer" || (root.kind === "claude" && !!root.held && root.held.pid > 0)
            ChipButton {
                visible: root.kind === "timer" && !!root.held && root.held.alarm
                symbol: "snooze"
                label: "5 min"
                tint: Colors.of(QsWindow.window).focus
                onActivated: { Timers.snoozeAlarm(5); UiState.closeSidePanel() }
            }
            ChipButton {
                visible: root.kind === "timer"
                symbol: "close"
                label: Translation.tr("Dismiss")
                tint: Colors.of(QsWindow.window).focus
                onActivated: {
                    if (Timers.ringing) Timers.dismissAlarm()
                    else if (Timers.timerDone) Timers.stopTimer()
                    UiState.closeSidePanel()
                }
            }
            ChipButton {
                visible: root.kind === "claude"
                symbol: "open_in_new"
                label: Translation.tr("Go to it")
                tint: Colors.of(QsWindow.window).focus
                onActivated: { ClaudeSessions.focus(root.held.pid); UiState.closeSidePanel() }
            }
        }
    }
}
