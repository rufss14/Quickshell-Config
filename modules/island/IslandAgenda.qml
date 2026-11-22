pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules
import "../../services/quickadd.js" as Quick

// ── IslandAgenda ──────────────────────────────────────────────────────────────
// Your day ahead on an island (2026-11-15, one of the user's new pages; the middle island, beside Clock):
//
//   left    the loud card: what is next (the event, when, how soon), the next holiday, and the world clocks you
//           keep (Settings › Clock), each with its time and how far it is from here
//   right   one line to add anything by typing it the way you would say it ("call mum at 6", "dentist fri 3pm",
//           "gym every monday 7am"): it says what it understood as you type, Reminder or Event, Enter adds it
//           (services/quickadd.js, the clock panel's parser); then today and tomorrow from your calendars, and
//           the open reminders (tick, snooze 10 minutes and remove under the pointer)
//
// Everything real is services/Calendar (held while this shows), Reminders and WorldClock.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    Component.onCompleted: { Calendar.acquire(); WorldClock.acquire() }
    Component.onDestruction: { Calendar.release(); WorldClock.release() }

    readonly property date now: Clock.now
    function dayOcc(offset) {
        const d = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate() + offset)
        return Rules.agenda(Calendar.eventsOn(d.getFullYear(), d.getMonth(), d.getDate()), offset === 0 ? root.now.getTime() : 0, 12)
    }
    readonly property var today: root.dayOcc(0)
    readonly property var tomorrow: root.dayOcc(1)
    readonly property var next: root.today.find(e => !e.allDay) ?? root.today[0] ?? null
    function hm(ms) { return Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat)) }
    function soon(ms) {
        const m = Math.round((ms - root.now.getTime()) / 60000)
        if (m <= 0) return Translation.tr("now")
        if (m < 60) return Translation.tr("in %1 min").arg(m)
        return Translation.tr("in %1 h %2 min").arg(Math.floor(m / 60)).arg(m % 60)
    }

    // ── Typing it in ──────────────────────────────────────────────────────────
    property string text: ""
    property string kind: "reminder"
    property string error: ""
    readonly property var quick: Quick.parse(root.text, Date.now())
    readonly property bool parsed: root.text.trim() !== "" && root.quick.start !== null
    readonly property string as_: root.quick.repeat !== "" ? "event" : root.kind
    function submit() {
        const t = root.text.trim()
        if (t === "") return
        let err = ""
        if (!root.parsed) err = Reminders.add(t, "")
        else if (!root.quick.ok) err = Translation.tr("Add a title")
        else {
            const q = root.quick
            const d = new Date(q.start)
            const dayMs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
            const p = n => (n < 10 ? "0" : "") + n
            const hmOf = ms => { const x = new Date(ms); return p(x.getHours()) + ":" + p(x.getMinutes()) }
            if (root.as_ === "event")
                err = Calendar.saveLocal({ uid: "", summary: q.summary, location: "", day: dayMs, allDay: q.allDay,
                                           startTime: q.allDay ? "" : hmOf(q.start), endTime: q.allDay ? "" : hmOf(q.end),
                                           repeat: q.repeat })
            // A reminder with a day and no hour goes off at nine.
            else err = Reminders.addDue(q.summary, q.allDay ? dayMs + 9 * 3600000 : q.start)
        }
        root.error = err || ""
        if (root.error === "") { root.text = ""; field.clear() }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Next, loud ════════════════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: "event"
                        shape: root.next && root.next.live ? "burst" : root.next ? "cookie9" : "circle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Next up")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.now, "dddd d MMMM")
                            variant: "caption"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.next ? (root.next.summary || Translation.tr("Event")) : Translation.tr("Nothing more today")
                    font.pixelSize: Tokens.fontDisplay
                    font.weight: Font.Bold
                    color: hero.ink
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.next !== null
                    text: !root.next ? "" : root.next.allDay ? Translation.tr("All day")
                        : root.next.live ? Translation.tr("Now, until %1").arg(root.hm(root.next.end))
                        : Translation.tr("%1, %2").arg(root.hm(root.next.start)).arg(root.soon(root.next.start))
                    variant: "label"
                    color: hero.inkDim
                }
                StyledText {
                    Layout.fillWidth: true
                    readonly property var sp: Calendar.nextSpecial
                    visible: !!sp && !!sp.entries && sp.entries.length > 0
                    text: visible ? Translation.tr("%1 · %2").arg(sp.entries[0].name ?? "").arg(Qt.formatDate(new Date(sp.day), "d MMM")) : ""
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                // The world clocks you keep.
                Repeater {
                    model: WorldClock.zones.slice(0, 3)
                    delegate: RowLayout {
                        id: zone
                        required property string modelData
                        readonly property var r: WorldClock.reading(zone.modelData, 0)
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm
                        MaterialIcon { name: "public"; color: hero.ink }
                        StyledText {
                            Layout.fillWidth: true
                            text: zone.modelData.split("/").pop().replace(/_/g, " ")
                            variant: "caption"
                            color: hero.ink
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: zone.r.known ? (zone.r.h < 10 ? "0" : "") + zone.r.h + ":" + (zone.r.m < 10 ? "0" : "") + zone.r.m : ""
                            variant: "label"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: hero.ink
                        }
                        StyledText {
                            text: zone.r.known ? zone.r.diff : ""
                            variant: "micro"
                            color: hero.inkDim
                        }
                    }
                }
            }
        }

        // ══ Right ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── Type it in ─────────────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: addCol.implicitHeight + Tokens.spacingMd * 2
                order: 1

                ColumnLayout {
                    id: addCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        InputField {
                            id: field
                            Layout.fillWidth: true
                            icon: "add"
                            placeholder: Translation.tr("Call mum at 6, dentist fri 3pm, gym every monday 7am")
                            onEdited: function (v) { root.text = v; root.error = "" }
                            onAccepted: function () { root.submit() }
                        }
                        ChipButton {
                            label: Translation.tr("Reminder")
                            on: root.as_ === "reminder"
                            enabled: root.quick.repeat === ""
                            onActivated: root.kind = "reminder"
                        }
                        ChipButton {
                            label: Translation.tr("Event")
                            on: root.as_ === "event"
                            onActivated: root.kind = "event"
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.error !== "" ? root.error
                            : root.parsed ? Translation.tr("%1: %2").arg(root.as_ === "event" ? Translation.tr("Event") : Translation.tr("Reminder")).arg(Quick.describe(root.quick, Date.now()))
                            : root.text.trim() !== "" ? Translation.tr("A reminder with no time. Enter adds it.")
                            : Translation.tr("Say when in the line and it understands")
                        variant: "caption"
                        color: root.error !== "" ? root.palette.danger : root.palette.fgMuted
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                // ── Today and tomorrow ─────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 2

                    // A clear calendar says so, and where calendars come from.
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingXl * 2
                        visible: root.today.length === 0 && root.tomorrow.length === 0
                        spacing: Tokens.spacingSm
                        MorphShape {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Tokens.iconXl * 1.5
                            height: width
                            shape: "sunny"
                            turns: false
                            fillColor: root.palette.plate
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "event"
                                color: root.palette.fgMuted
                            }
                        }
                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Today and tomorrow are clear")
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Type an event above, or add a calendar in Settings › Clock.")
                            variant: "caption"
                            emphasis: "muted"
                            wrapMode: Text.Wrap
                        }
                    }
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        visible: root.today.length > 0 || root.tomorrow.length > 0
                        contentHeight: daysCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: daysCol
                            width: parent.width
                            spacing: Tokens.spacingXs
                            Repeater {
                                model: [{ t: Translation.tr("Today"), list: root.today }, { t: Translation.tr("Tomorrow"), list: root.tomorrow }]
                                delegate: ColumnLayout {
                                    id: day
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacingXs
                                    StyledText {
                                        text: day.modelData.t
                                        variant: "label"
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        visible: day.modelData.list.length === 0
                                        text: Translation.tr("Nothing planned")
                                        variant: "caption"
                                        emphasis: "muted"
                                    }
                                    Repeater {
                                        model: day.modelData.list
                                        delegate: Rectangle {
                                            id: ev
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: evRow.implicitHeight + Tokens.spacingSm * 2
                                            radius: Tokens.radiusSm
                                            color: ev.modelData.live ? root.palette.primaryContainer : root.palette.plate
                                            RowLayout {
                                                id: evRow
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.margins: Tokens.spacingSm
                                                spacing: Tokens.spacingSm
                                                StyledText {
                                                    Layout.preferredWidth: Tokens.spacingXl * 3
                                                    text: ev.modelData.allDay ? Translation.tr("All day") : root.hm(ev.modelData.start)
                                                    variant: "caption"
                                                    font.weight: Font.DemiBold
                                                    font.features: ({ tnum: 1 })
                                                    color: ev.modelData.live ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: ev.modelData.summary || Translation.tr("Event")
                                                    variant: "caption"
                                                    color: ev.modelData.live ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Reminders ──────────────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 3

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            StyledText {
                                text: Translation.tr("Reminders")
                                variant: "label"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Reminders.overdueCount > 0 ? Translation.tr("%1 overdue").arg(Reminders.overdueCount) : ""
                                variant: "caption"
                                color: root.palette.danger
                            }
                        }
                        Item {
                            visible: Reminders.openCount === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - Tokens.spacingXl
                                spacing: Tokens.spacingSm
                                MorphShape {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Tokens.iconXl * 1.5
                                    height: width
                                    shape: "cookie9"
                                    turns: false
                                    fillColor: root.palette.plate
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: "notifications_active"
                                        color: root.palette.fgMuted
                                    }
                                }
                                StyledText {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("Nothing to remember")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("Type it above with a time and it reminds you then.")
                                    variant: "caption"
                                    emphasis: "muted"
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Reminders.openCount > 0
                            clip: true
                            spacing: Tokens.spacingXs
                            boundsBehavior: Flickable.StopAtBounds
                            model: Reminders.sorted.filter(r => !r.done)
                            delegate: Rectangle {
                                id: rem
                                required property var modelData
                                readonly property bool overdue: rem.modelData.due > 0 && rem.modelData.due <= root.now.getTime()
                                width: ListView.view.width
                                height: remRow.implicitHeight + Tokens.spacingSm * 2
                                radius: Tokens.radiusSm
                                color: root.palette.plate
                                HoverHandler { id: remHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Reminders.toggle(rem.modelData.id)
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: rem.modelData.text
                                }
                                RowLayout {
                                    id: remRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.spacingSm
                                    spacing: Tokens.spacingSm
                                    MaterialIcon {
                                        name: "radio_button_unchecked"
                                        color: rem.overdue ? root.palette.danger : root.palette.fgMuted
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rem.modelData.text
                                            variant: "caption"
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: rem.modelData.due > 0
                                            text: Reminders.dueLabel(rem.modelData)
                                            variant: "micro"
                                            color: rem.overdue ? root.palette.danger : root.palette.fgMuted
                                        }
                                    }
                                    CardTool {
                                        visible: remHover.hovered
                                        symbol: "snooze"
                                        name: Translation.tr("Snooze 10 minutes")
                                        onActivated: Reminders.snooze(rem.modelData.id, 10)
                                    }
                                    CardTool {
                                        visible: remHover.hovered
                                        symbol: "close"
                                        name: Translation.tr("Remove")
                                        onActivated: Reminders.remove(rem.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
