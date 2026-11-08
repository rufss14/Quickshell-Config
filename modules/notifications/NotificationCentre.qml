pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/notifyview.js" as View

// ── NotificationCentre ────────────────────────────────────────────────────────
// The notification history as a panel body: a header (Do Not Disturb, Clear all), a tools row
// (search, the layout, select), the per-app summary strip, the Undo bar, the empty state, and the
// list — NotificationGroups. It is the ONE body the bar's / sidebar's NotificationsPanel and the
// overview's notification card both host, so the two can't drift: they used to be two copies of
// the seen-marking, the undo pile, the empty state and the header, with different wording.
//
//   compact: false   a PanelHeader (the panel recipe), the full empty state, on the panel's own
//                    surface
//   compact: true    the overview's card, 6.5 units wide, with NO ground of its own — it sits on the
//                    grid's card and blends (a tinted pill behind it read as a box on a box) — and
//                    a header in the HUD cards' shape (a cookie chip, a title over a subtitle, the
//                    ChipTray), which a 36px icon square and a two-word title would not fit
//
// Wears the Media and Clock panels' language: the header's actions are a ChipTray (off is an
// icon on the pill, on a filled disc), the list is tiles with cookie app icons
// (NotificationRow), and the groups arrive as a PopIn cascade a beat after the host opens.
//
// ── What it can do ────────────────────────────────────────────────────────────
//   Search       words, any order, over app / summary / body (notifyview.js `filter`); shown once
//                there are a few notifications to look through
//   Strip        a chip per app with its count; tap one to see only that app
//   View         by app (the default) or by day — "Last hour / Earlier today / Yesterday / Earlier"
//   Select       tick tiles, then dismiss or snooze them together
//   Do Not Disturb for a while (30 min, 1 hour, until tomorrow morning), beside its plain switch
//   On a tile    copy, snooze, reply (NotificationRow); on an app, mute (NotificationGroups)
//
// Opening counts everything as seen (Notifications.markSeen) — which is what clears the
// bell's dot, including what arrives while you're looking. What was new when it opened keeps a
// dot in the list, so "seen" doesn't erase "what's new".
//
// Clearing is instant, with an Undo (UndoBar) instead of a click-twice: history is plain data,
// so it can simply be put back. Successive clears pile into one Undo.
//
// Everything real is services/Notifications and notifyview.js; this shows it and calls it. The
// only state here is what's SELECTED or typed: the query, the app filter, the view, the ticks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool compact: false
    // The room the host has, header and list together (the panel's slot); the list scrolls past
    // it. Ignored when `fill`.
    property real maxHeight: Infinity
    // The list takes all the height it is given (the overview's card), instead of hugging its
    // content up to a ceiling (the panel).
    property bool fill: false

    readonly property color accent: Config.moduleAccent("notifications", Colors.of(QsWindow.window).primary)

    implicitHeight: col.implicitHeight

    // ── What is looked at ─────────────────────────────────────────────────────
    property string query: ""
    property string app: ""             // the strip's pick; "" = every app
    property string view: "app"         // "app" | "day"
    property bool   dndMenu: false      // the "quiet for…" row
    property bool   searchOpen: false   // the search field's row (a chip in the toolbar opens it)
    property bool   moreMenu: false     // the layout / select row (⋯)
    property bool   selecting: false
    property var    selected: ({})      // record key → true. Assigned, never mutated.

    // The text filter first (the strip's counts follow it), then the strip's app.
    readonly property var matching: View.filter(Notifications.records, root.query, "")
    readonly property var apps:     View.appCounts(root.matching)
    readonly property var shown:    root.app === "" ? root.matching : View.filter(root.matching, "", root.app)

    // By-day sections are relative to "now", which only needs refreshing now and then: a
    // minute-by-minute rebuild would put the list back at the top while you scroll it.
    property real _dayNow: Date.now()
    Timer {
        running: root.view === "day"
        interval: 600000
        repeat: true
        onTriggered: root._dayNow = Date.now()
    }
    readonly property var groups: root.view === "day" ? View.byDay(root.shown, root._dayNow)
                                                      : View.byApp(root.shown)

    // A filter whose app has gone (cleared, or the search no longer reaches it) lets go.
    onAppsChanged: if (root.app !== "" && !root.apps.some(a => a.app === root.app)) root.app = ""

    // ── Selecting ─────────────────────────────────────────────────────────────
    readonly property var selectedRecs: root.shown.filter(r => root.selected[r.key] === true)
    readonly property bool allSelected: root.shown.length > 0 && root.selectedRecs.length === root.shown.length
    function toggle(rec) {
        const n = Object.assign({}, root.selected)
        if (n[rec.key]) delete n[rec.key]; else n[rec.key] = true
        root.selected = n
    }
    function selectAll() {
        const n = ({})
        if (!root.allSelected) for (const r of root.shown) n[r.key] = true
        root.selected = n
    }
    function endSelect() { root.selecting = false; root.selected = ({}) }

    // ── New since you last looked ─────────────────────────────────────────────
    // Captured BEFORE markSeen moves it, and never again while open.
    property real since: 0
    readonly property int newCount: {
        let n = 0
        for (const r of Notifications.records) if (r.time > root.since) n++
        return n
    }
    // The list's cards arrive after creation, not during it (PopIn plays when `active` TURNS true).
    property bool opened: false
    Component.onCompleted: {
        root.since = Notifications.seenAt
        Notifications.markSeen()
        Qt.callLater(function () { root.opened = true })
    }
    Connections {
        target: Notifications
        function onUnseenChanged() { Notifications.markSeen() }
    }

    // The one line under the title.
    readonly property string snoozedText: Notifications.snoozed.length > 0
        ? "  ·  " + Notifications.snoozed.length + " snoozed" : ""
    readonly property string subtitle: Notifications.statusLine
        + (root.newCount > 0 && Notifications.count > 0 ? "  ·  " + root.newCount + " new" : "")
        + root.snoozedText
    // "6 · 3 apps · 2 new": a bare number said nothing, and the full status line is too long for the
    // overview card beside its three chips.
    readonly property string subtitleCompact: Notifications.dnd || Notifications.count === 0
        ? Notifications.statusLine + root.snoozedText
        : Notifications.count + (Notifications.historyGroups.length > 1 ? "  ·  " + Notifications.historyGroups.length + " apps" : "")
          + (root.newCount > 0 ? "  ·  " + root.newCount + " new" : "") + root.snoozedText

    // ── Undo ──────────────────────────────────────────────────────────────────
    // Everything cleared while the bar is up comes back together.
    property var _undoRecs: []
    function offerUndo(recs) {
        if (!recs || recs.length === 0) return
        const all = undo.shown ? root._undoRecs.concat(recs) : recs
        root._undoRecs = all
        undo.show(all.length === 1 ? "Cleared 1 notification" : "Cleared " + all.length + " notifications",
                  () => Notifications.restore(all))
    }

    // ── The list's ceiling ────────────────────────────────────────────────────
    // What's left under everything else that is showing, never more than ten card units.
    readonly property int _rows: 1 + (dndRow.visible ? 1 : 0) + (tools.visible ? 1 : 0)
        + (searchRow.visible ? 1 : 0) + (moreRow.visible ? 1 : 0)
        + (strip.visible ? 1 : 0) + (undo.shown ? 1 : 0) + (selBar.visible ? 1 : 0)
    readonly property real _chrome: (root.compact ? slim.implicitHeight : head.implicitHeight)
        + (dndRow.visible ? dndRow.implicitHeight : 0) + (tools.visible ? tools.implicitHeight : 0)
        + (searchRow.visible ? searchRow.implicitHeight : 0) + (moreRow.visible ? moreRow.implicitHeight : 0)
        + (strip.visible ? strip.implicitHeight : 0) + (undo.shown ? undo.implicitHeight : 0)
        + (selBar.visible ? selBar.implicitHeight : 0) + col.spacing * root._rows
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2,
        Math.min(Tokens.sideCardUnit * 10, root.maxHeight - root._chrome))

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: root.fill ? parent.bottom : undefined
        spacing: Tokens.spacingMd

        // ── Header, full: the panel recipe ────────────────────────────────────
        PanelHeader {
            id: head
            Layout.fillHeight: false
            visible: !root.compact
            symbol:    Notifications.quiet ? "notifications_off" : "notifications"
            title:     Translation.tr("Notification")
            titleTail: "centre"
            accent:    root.accent
            subtitle:  root.subtitle

        }

        // ── Header, compact: the HUD cards' shape ─────────────────────────────
        RowLayout {
            id: slim
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.compact
            spacing: Tokens.spacingMd

            ScallopChip {
                Layout.alignment: Qt.AlignVCenter
                glyph: Notifications.quiet ? "\u{F009B}" : "\u{F009A}"   // 󰂛 bell-off / 󰂚 bell
                tint:  root.accent
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    text: Translation.tr("Notifications")
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitleCompact
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }
        }

        // ── Do Not Disturb, for how long ──────────────────────────────────────
        // New notifications still arrive and wait here; they just do not pop up or make a sound.
        RowLayout {
            id: dndRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.dndMenu
            opacity: 0
            spacing: Tokens.spacingMd
            ViewEnter { target: dndRow; active: root.dndMenu; rise: Tokens.spacingSm }

            StyledText {
                text: Translation.tr("Quiet for")
                variant: "caption"
                emphasis: "dim"
            }
            ChipTray {
                ChipButton { label: "30 min"; tint: root.accent; onActivated: { Notifications.dndFor(30); root.dndMenu = false } }
                ChipButton { label: "1 hour"; tint: root.accent; onActivated: { Notifications.dndFor(60); root.dndMenu = false } }
                ChipButton { label: "Till morning"; tint: root.accent; onActivated: { Notifications.dndUntilMorning(); root.dndMenu = false } }
                ChipButton {
                    visible: !Notifications.dnd
                    label: Translation.tr("Until I stop it")
                    tint: root.accent
                    onActivated: { Notifications.toggleDnd(); root.dndMenu = false }
                }
                ChipButton {
                    visible: Notifications.dnd
                    symbol: "notifications"
                    label: Translation.tr("Turn off")
                    on: true
                    tint: root.accent
                    onActivated: { Notifications.toggleDnd(); root.dndMenu = false }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ── The toolbar: what you do most, in words ───────────────────────────
        // Quiet (Do Not Disturb, and for how long) and Clear all are labelled — they were a bell, a stopwatch and a
        // bin, which a first-time user had to hover to read. Search and the layout / select options open their own rows
        // from the two icons on the right, so the card is a title, two buttons and the list until you ask for more.
        RowLayout {
            id: tools
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Notifications.count > 0 || Notifications.dnd
            spacing: Tokens.spacingMd

            ChipTray {
                ChipButton {
                    symbol: "notifications_off"
                    label:  Notifications.dnd ? "Quiet · on" : "Quiet"
                    on:     Notifications.dnd
                    tint:   root.accent
                    onActivated: root.dndMenu = !root.dndMenu
                }
                ChipButton {
                    visible: Notifications.count > 0
                    symbol:  "delete"
                    label:   Translation.tr("Clear all")
                    tint:    Colors.of(QsWindow.window).danger
                    onActivated: root.offerUndo(Notifications.clearHistory())
                }
            }
            Item { Layout.fillWidth: true }
            ChipTray {
                visible: Notifications.count > 0
                ChipButton {
                    symbol: "search"
                    on:     root.searchOpen || root.query !== ""
                    tint:   root.accent
                    onActivated: {
                        if (root.searchOpen || root.query !== "") { searchField.clear(); root.query = ""; root.searchOpen = false }
                        else { root.searchOpen = true; Qt.callLater(() => searchField.forceFocus()) }
                    }
                }
                ChipButton {
                    symbol: "more_horiz"
                    on:     root.moreMenu || root.view === "day" || root.selecting
                    tint:   root.accent
                    onActivated: root.moreMenu = !root.moreMenu
                }
            }
        }

        // ── Search: opened from the toolbar ───────────────────────────────────
        RowLayout {
            id: searchRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Notifications.count > 0 && (root.searchOpen || root.query !== "")
            opacity: 0
            ViewEnter { target: searchRow; active: searchRow.visible; rise: Tokens.spacingSm }
            InputField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: Tokens.iconXl + Tokens.spacingMd
                cornerRadius: implicitHeight / 2
                icon: "search"
                placeholder: Translation.tr("Search notifications…")
                onEdited: (value) => root.query = value
                onKeyPressed: (event) => {
                    if (event.key !== Qt.Key_Escape) return
                    searchField.clear(); root.query = ""; root.searchOpen = false; searchField.blur(); event.accepted = true
                }
            }
        }

        // ── How to look at them: by app or by time, or select ─────────────────
        RowLayout {
            id: moreRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Notifications.count > 0 && root.moreMenu
            opacity: 0
            spacing: Tokens.spacingMd
            ViewEnter { target: moreRow; active: moreRow.visible; rise: Tokens.spacingSm }
            ChipTray {
                ChipButton {
                    symbol: "apps"
                    label:  Translation.tr("By app")
                    on:     root.view === "app"
                    tint:   root.accent
                    onActivated: root.view = "app"
                }
                ChipButton {
                    symbol: "today"
                    label:  Translation.tr("By time")
                    on:     root.view === "day"
                    tint:   root.accent
                    onActivated: root.view = "day"
                }
                ChipButton {
                    symbol: "checklist"
                    label:  Translation.tr("Select")
                    on:     root.selecting
                    tint:   root.accent
                    onActivated: { if (root.selecting) root.endSelect(); else root.selecting = true }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ── The apps, at a glance — and the filter ────────────────────────────
        NotificationStrip {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: false
            apps: root.apps
            current: root.app
            accent: root.accent
            onPicked: (app) => root.app = app
        }

        UndoBar { id: undo }

        // ── Nothing here ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingXl
            Layout.bottomMargin: Tokens.spacingXl
            visible: Notifications.count === 0
            spacing: Tokens.spacingMd

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 72
                implicitHeight: 72
                MorphShape {
                    anchors.fill: parent
                    shape: Notifications.quiet ? "squircle" : "cookie9"
                    fillColor: Colors.of(QsWindow.window).primaryContainer
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: Notifications.quiet ? "notifications_off" : "check"
                    fill: 1
                    color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                    font.pixelSize: Tokens.iconXl
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Notifications.dnd ? "Quiet for now" : "All caught up"
                variant: "title"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Notifications.dnd
                    ? "New notifications wait here without a sound."
                    : Notifications.quietHeldExternally
                    ? "Quiet while " + Notifications.quietHolds.join(", ") + " is on. New notifications wait here."
                    : "New notifications land here, grouped by app."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── A search that found nothing ───────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingLg
            Layout.bottomMargin: Tokens.spacingLg
            visible: Notifications.count > 0 && root.shown.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: "Nothing matches “" + root.query + "”"
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        NotificationGroups {
            Layout.fillWidth: true
            Layout.fillHeight: root.fill
            Layout.preferredHeight: root.fill ? -1 : Math.min(contentHeight, root.listRoom)
            visible: root.shown.length > 0
            model: root.groups
            muteable: root.view === "app"
            collapseAt: root.view === "day" ? 5 : 2
            accent: root.accent
            newSince: root.since
            selecting: root.selecting
            selected: root.selected
            cascade: true
            opened: root.opened
            onToggled: (rec) => root.toggle(rec)
            onCleared: (recs) => root.offerUndo(recs)
        }

        // ── Selecting: what to do with the ticked ─────────────────────────────
        RowLayout {
            id: selBar
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.selecting
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                text: root.selectedRecs.length > 0 ? root.selectedRecs.length + " selected" : "Tap to select"
                variant: "label"
                emphasis: root.selectedRecs.length > 0 ? "normal" : "dim"
            }
            ChipTray {
                ChipButton {
                    label: root.allSelected ? "None" : "All"
                    tint:  root.accent
                    onActivated: root.selectAll()
                }
                ChipButton {
                    symbol:  "snooze"
                    label:   "1 hour"
                    tint:    root.accent
                    enabled: root.selectedRecs.length > 0
                    onActivated: {
                        for (const r of root.selectedRecs) Notifications.snooze(r, 60)
                        root.endSelect()
                    }
                }
                ChipButton {
                    symbol:  "delete"
                    tint:    Colors.of(QsWindow.window).danger
                    enabled: root.selectedRecs.length > 0
                    onActivated: {
                        root.offerUndo(Notifications.clearRecs(root.selectedRecs))
                        root.endSelect()
                    }
                }
            }
        }
    }
}
