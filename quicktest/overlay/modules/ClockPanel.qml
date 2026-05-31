import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theming" as T

Item {
    id: root

    implicitWidth:  340
    implicitHeight: col.implicitHeight + col.anchors.topMargin + col.anchors.bottomMargin

    property var now:      new Date()
    property int todayD:   now.getDate()
    property int todayM:   now.getMonth()
    property int todayY:   now.getFullYear()
    property int calMonth: todayM
    property int calYear:  todayY

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            root.now    = new Date()
            root.todayD = root.now.getDate()
            root.todayM = root.now.getMonth()
            root.todayY = root.now.getFullYear()
        }
    }

    readonly property var monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]
    readonly property var dayNames: ["Mo","Tu","We","Th","Fr","Sa","Su"]
    readonly property var fullDayNames: [
        "Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"
    ]

    function fullDateString() {
        var d = root.now
        return fullDayNames[d.getDay()] + ", " + d.getDate() +
               " " + monthNames[d.getMonth()] + " " + d.getFullYear()
    }

    function daysInMonth(y, m)     { return new Date(y, m + 1, 0).getDate() }
    function firstDayOfMonth(y, m) { return (new Date(y, m, 1).getDay() + 6) % 7 }
    function buildCalendar(y, m) {
        var cells = [], offset = firstDayOfMonth(y, m)
        for (var i = 0; i < offset; i++) cells.push(0)
        var days = daysInMonth(y, m)
        for (var d = 1; d <= days; d++) cells.push(d)
        while (cells.length % 7 !== 0) cells.push(0)
        return cells
    }

    property var calCells: buildCalendar(calYear, calMonth)
    property int selectedDay: 0
    property bool calCollapsed: false
    property var calNotes: ({})
    property int notesVersion: 0
    property bool _notesLoaded: false

    // Persistent notes — survives reboots and quickshell refreshes.
    PersistentProperties {
        id: notesPersist
        reloadableId: "clockPanelNotes"
        property var savedNotes: ({})
        onLoaded: {
            root.calNotes = Object.assign({}, notesPersist.savedNotes)
            root._notesLoaded = true
            root.notesVersion++
        }
    }

    onCalNotesChanged: {
        if (!_notesLoaded) return
        notesPersist.savedNotes = Object.assign({}, calNotes)
    }

    function saveNotes() {
        if (!_notesLoaded) return
        notesPersist.savedNotes = Object.assign({}, root.calNotes)
    }

    // Improved note saving reliability
    onNotesVersionChanged: saveNotes()
    Component.onDestruction: saveNotes()

    Component.onCompleted: detectCountry()

    property int selectedNoteIndex: -1  // which note is being edited/removed

    // Returns the notes array for the selected day (user notes only, not holidays)
    readonly property var selectedNotes: {
        if (selectedDay === 0) return []
        var key = calYear + "-" + (calMonth+1) + "-" + selectedDay
        var v = calNotes[key]
        if (!v) return []
        if (Array.isArray(v)) return v
        return [v]  // migrate legacy string
    }

    readonly property string selectedEventText: {
        if (selectedDay === 0) return ""
        var key = calYear + "-" + (calMonth+1) + "-" + selectedDay
        var notes = calNotes[key]
        var holiday = holidays[key]
        var parts = []
        if (holiday) parts.push(holiday)
        if (notes) {
            var arr = Array.isArray(notes) ? notes : [notes]
            for (var i = 0; i < arr.length; i++) parts.push(arr[i])
        }
        return parts.join(" · ")
    }

    onCalMonthChanged: calCells = buildCalendar(calYear, calMonth)
    onCalYearChanged: {
        calCells = buildCalendar(calYear, calMonth)
        if (countryCode !== "") fetchHolidays(calYear)
    }

    // Holidays
    property string countryCode: ""
    property var    holidays: ({})

    function fetchHolidays(year) {
        if (countryCode === "") return
        var url = "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + countryCode
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            try {
                var list = JSON.parse(xhr.responseText)
                var h = Object.assign({}, holidays)
                for (var i = 0; i < list.length; i++) {
                    var entry = list[i]
                    var parts = entry.date.split("-")
                    var ky = parseInt(parts[0])
                    var km = parseInt(parts[1])
                    var kd = parseInt(parts[2])
                    h[ky + "-" + km + "-" + kd] = entry.localName || entry.name
                }
                holidays = h
            } catch(e) {}
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function detectCountry() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            try {
                var r = JSON.parse(xhr.responseText)
                if (r.countryCode) {
                    countryCode = r.countryCode
                    fetchHolidays(todayY)
                    fetchHolidays(todayY + 1)
                    if (calYear !== todayY && calYear !== todayY + 1)
                        fetchHolidays(calYear)
                }
            } catch(e) {}
        }
        xhr.open("GET", "http://ip-api.com/json/?fields=countryCode")
        xhr.send()
    }

    // Timer
    property double timerTarget: 0
    property bool timerRunning: false
    property bool timerFinished: false
    property int  timerRemain:  0
    property int timerH: 0
    property int timerM: 0
    property int timerS: 0

    function timerRemainStr() {
        var s = timerRemain
        var h = Math.floor(s / 3600); s -= h * 3600
        var m = Math.floor(s / 60);   s -= m * 60
        return (h > 0 ? (h < 10 ? "0"+h : h) + ":" : "")
             + (m < 10 ? "0"+m : m) + ":"
             + (s < 10 ? "0"+s : s)
    }

    function startTimer() {
        var totalS = (timerH || 0)*3600 + (timerM || 0)*60 + (timerS || 0)
        if (totalS <= 0) return
        timerTarget  = Date.now() + totalS * 1000
        timerRemain  = totalS
        timerRunning = true
    }

    function stopTimer() {
        timerRunning  = false
        timerTarget   = 0
        timerRemain   = 0
        timerFinished = false
        _flashCount   = 0
        flashTimer.stop()
        countdownTick.stop()
    }

    Timer {
        id: countdownTick
        interval: 1000; repeat: true; running: root.timerRunning
        onTriggered: {
            var rem = Math.round((root.timerTarget - Date.now()) / 1000)
            if (rem <= 0) {
                root.timerRemain  = 0
                root.timerRunning = false
                root.timerTarget  = 0
                root.timerFinished = true
                flashTimer.start()
            } else {
                root.timerRemain = rem
            }
        }
    }

    property int _flashCount: 0
    Timer {
        id: flashTimer
        interval: 350; repeat: true
        onTriggered: root._flashCount++
    }

    ColumnLayout {
        id: col
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: 12; leftMargin: 14; rightMargin: 14; bottomMargin: 12
        }
        spacing: 6   // tighter spacing so mini clock sits closer

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 34; height: 34; radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25) }
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.22) }
                    }
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.30)
                    border.width: 1

                    Canvas {
                        id: smallClock
                        anchors.centerIn: parent
                        width: 20; height: 20
                        Timer { interval: 1000; running: true; repeat: true; onTriggered: smallClock.requestPaint() }
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var cx = width/2, cy = height/2, r = width/2 - 1
                            var n = new Date()
                            var hrs = n.getHours() % 12, mins = n.getMinutes(), secs = n.getSeconds()
                            var hA = ((hrs + mins/60)/12)*Math.PI*2 - Math.PI/2
                            var mA = (mins/60)*Math.PI*2 - Math.PI/2
                            var sA = (secs/60)*Math.PI*2 - Math.PI/2
                            var accent = T.Theme.color1, fg = T.Theme.fg
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2)
                            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.8)
                            ctx.lineWidth = 1.5; ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(cx, cy)
                            ctx.lineTo(cx + Math.cos(hA)*r*0.45, cy + Math.sin(hA)*r*0.45)
                            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 1.0); ctx.lineWidth = 2; ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(cx, cy)
                            ctx.lineTo(cx + Math.cos(mA)*r*0.7, cy + Math.sin(mA)*r*0.7)
                            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 1.0); ctx.lineWidth = 1.5; ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(cx, cy)
                            ctx.lineTo(cx + Math.cos(sA)*r*0.75, cy + Math.sin(sA)*r*0.75)
                            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.9); ctx.lineWidth = 1; ctx.stroke()
                            ctx.beginPath(); ctx.arc(cx, cy, 2, 0, Math.PI*2)
                            ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 1.0); ctx.fill()
                        }
                    }
                }

                ColumnLayout {
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "Clock"
                            color: T.Theme.fg
                            font.pixelSize: 15; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily
                        }
                        Text {
                            text: "& Calendar"
                            color: T.Theme.color1
                            font.pixelSize: 15; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily
                        }
                    }
                    Text {
                        text: root.fullDateString()
                        color: T.Theme.fg; opacity: 0.35
                        font.pixelSize: 10; font.family: T.Theme.fontFamily
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 30; height: 30; radius: 8
                color: collapseMA.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.20) : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: root.calCollapsed ? "▾" : "▴"
                    color: T.Theme.fg; opacity: 0.7; font.pixelSize: 11; font.family: T.Theme.fontFamily
                    Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                }
                MouseArea {
                    id: collapseMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.calCollapsed = !root.calCollapsed
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
        }

        // Big 7-segment clock (unchanged)
        Canvas {
            id: clockCanvas
            Layout.fillWidth: true
            Layout.preferredHeight: 90

            property string displayTime: Qt.formatDateTime(root.now, "HHmm")
            property bool   blinkOn:    true

            Timer { interval: 500; running: true; repeat: true; onTriggered: {
                clockCanvas.displayTime = Qt.formatDateTime(root.now, "HHmm")
                clockCanvas.blinkOn     = !clockCanvas.blinkOn
                clockCanvas.requestPaint()
            }}
            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var accent = T.Theme.color1
                var clr    = Qt.rgba(accent.r, accent.g, accent.b, 1.0)

                var dw  = 52; var dh = 86; var th = 14; var gap = 8; var cw = 20
                var totalW = dw*4 + cw + gap*4
                var ox = Math.floor((width - totalW) / 2)
                var oy = Math.floor((height - dh) / 2)

                var bars = [
                    [1,1,1,0,1,1,1], [0,0,1,0,0,1,0], [1,0,1,1,1,0,1],
                    [1,0,1,1,0,1,1], [0,1,1,1,0,1,0], [1,1,0,1,0,1,1],
                    [1,1,0,1,1,1,1], [1,0,1,0,0,1,0], [1,1,1,1,1,1,1],
                    [1,1,1,1,0,1,1]
                ]

                function drawDigit(x, y, d) {
                    var b = bars[d]
                    var rx = x + dw - th
                    var midY = y + Math.floor((dh - th) / 2)
                    ctx.fillStyle = clr

                    if (b[0]) ctx.fillRect(x, y, dw, th)
                    if (b[3]) ctx.fillRect(x, midY, dw, th)
                    if (b[6]) ctx.fillRect(x, y + dh - th, dw, th)

                    if (d === 1) {
                        var cx1 = x + Math.floor((dw - th) / 2)
                        ctx.fillRect(cx1, y, th, dh)
                        return
                    }

                    if (b[1]) { var tlY = b[0] ? y + th : y; var tlH = (b[3] ? midY : (b[6] ? y + dh - th : y + dh)) - tlY; ctx.fillRect(x, tlY, th, tlH) }
                    if (b[4]) { var blY = b[3] ? midY + th : y; var blH = (b[6] ? y + dh - th : y + dh) - blY; ctx.fillRect(x, blY, th, blH) }
                    if (b[2]) { var trY = b[0] ? y + th : y; var trH = (b[3] ? midY : (b[6] ? y + dh - th : y + dh)) - trY; ctx.fillRect(rx, trY, th, trH) }
                    if (b[5]) { var brY = b[3] ? midY + th : y; var brH = (b[6] ? y + dh - th : y + dh) - brY; ctx.fillRect(rx, brY, th, brH) }
                }

                function drawColon(x, y) {
                    var sz = th
                    var dx = x + Math.floor((cw - sz) / 2)
                    ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, blinkOn ? 1.0 : 0.2)
                    ctx.fillRect(dx, y + Math.floor(dh * 0.25), sz, sz)
                    ctx.fillRect(dx, y + Math.floor(dh * 0.60), sz, sz)
                }

                var t = displayTime
                var x = ox, y = oy
                drawDigit(x, y, parseInt(t[0])); x += dw + gap
                drawDigit(x, y, parseInt(t[1])); x += dw + gap
                drawColon(x, y); x += cw + gap
                drawDigit(x, y, parseInt(t[2])); x += dw + gap
                drawDigit(x, y, parseInt(t[3]))
            }
        }

        // Simple seconds text — same accent color as the big clock
        Text {
            Layout.fillWidth: true
            text: Qt.formatDateTime(root.now, "HH:mm:ss")
            horizontalAlignment: Text.AlignHCenter
            color: T.Theme.color1
            font.pixelSize: 14
            font.weight: Font.Bold
            font.family: T.Theme.fontFamily
            opacity: 0.85
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07) }

        // Calendar — collapsible
        Item {
            id: calWrapper
            Layout.fillWidth: true
            implicitHeight: root.calCollapsed ? 0 : calInner.implicitHeight
            clip: true

            // Smoother collapse: longer duration + premium easing + fade
            // This keeps the mini clock / header completely stable during animation
            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 340
                    easing.type: Easing.OutQuart
                }
            }
            opacity: root.calCollapsed ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: calInner
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Rectangle { width: 24; height: 24; radius: 6; color: prevMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Text { anchors.centerIn: parent; text: "‹"; color: T.Theme.fg; opacity: 0.7; font.pixelSize: 15 }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.calMonth === 0 ? (root.calMonth = 11, root.calYear--) : root.calMonth-- }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.monthNames[root.calMonth] + " " + root.calYear
                        color: T.Theme.fg; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.calMonth = root.todayM; root.calYear = root.todayY } }
                    }
                    Rectangle { width: 24; height: 24; radius: 6; color: nextMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Text { anchors.centerIn: parent; text: "›"; color: T.Theme.fg; opacity: 0.7; font.pixelSize: 15 }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.calMonth === 11 ? (root.calMonth = 0, root.calYear++) : root.calMonth++ }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ColumnLayout { spacing: 2
                        Row {
                            Repeater {
                                model: root.dayNames
                                delegate: Text {
                                    width: 38
                                    text: modelData
                                    color: (index >= 5) ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.6) : T.Theme.fg
                                    opacity: 0.45; font.pixelSize: 10; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        Grid {
                            columns: 7; columnSpacing: 0; rowSpacing: 2

                            Repeater {
                                model: root.calCells
                                delegate: Item {
                                    width: 38; height: 30

                                    readonly property bool isEmpty: modelData === 0
                                    readonly property bool isToday: !isEmpty && modelData === root.todayD && root.calMonth === root.todayM && root.calYear === root.todayY
                                    readonly property bool isWeekend: (index % 7 >= 5)
                                    readonly property bool isSelected: !isEmpty && modelData === root.selectedDay
                                    readonly property string _key: root.calYear + "-" + (root.calMonth+1) + "-" + modelData
                                    readonly property bool hasNote: !isEmpty && root.notesVersion >= 0 && root.calNotes[_key] !== undefined && (Array.isArray(root.calNotes[_key]) ? root.calNotes[_key].length > 0 : true)
                                    readonly property bool isHoliday: !isEmpty && root.holidays[_key] !== undefined

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 30; height: 26; radius: 5
                                        visible: !isEmpty && !isToday && (hasNote || isHoliday)
                                        color: (hasNote && isHoliday) ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.28)
                                            : hasNote ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.22)
                                            : T.Theme.pw(T.Theme.pal?.colors?.color3, 0.18)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent; width: 26; height: 26; radius: 13
                                        visible: isToday
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.9) }
                                            GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.8) }
                                        }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent; width: 26; height: 26; radius: 13
                                        visible: !isEmpty && !isToday && (dayMa.containsMouse || isSelected)
                                        color: isSelected ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.18) : T.Theme.pw(T.Theme.pal?.colors?.color1, 0.10)
                                        border.color: isSelected ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.55) : "transparent"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                        Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                                    }

                                    Rectangle { visible: hasNote && !isToday; width: 4; height: 4; radius: 2; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 1.0)
                                        anchors { bottom: parent.bottom; horizontalCenter: isHoliday ? undefined : parent.horizontalCenter; right: isHoliday ? parent.horizontalCenter : undefined; rightMargin: isHoliday ? 1 : 0; bottomMargin: 2 }
                                    }
                                    Rectangle { visible: isHoliday && !isToday; width: 4; height: 4; radius: 2; color: T.Theme.pw(T.Theme.pal?.colors?.color3, 0.80)
                                        anchors { bottom: parent.bottom; horizontalCenter: hasNote ? undefined : parent.horizontalCenter; left: hasNote ? parent.horizontalCenter : undefined; leftMargin: hasNote ? 1 : 0; bottomMargin: 2 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !isEmpty
                                        text: modelData
                                        color: isToday ? T.Theme.bg : isWeekend ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.85) : T.Theme.fg
                                        opacity: isToday ? 1.0 : (isWeekend ? 0.75 : 0.9)
                                        font.pixelSize: 12
                                        font.weight: (isToday || hasNote || isHoliday) ? Font.Bold : Font.Medium
                                        font.family: T.Theme.fontFamily
                                    }

                                    MouseArea {
                                        id: dayMa; anchors.fill: parent; hoverEnabled: !isEmpty
                                        cursorShape: isEmpty ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onClicked: if (!isEmpty) root.selectedDay = (root.selectedDay === modelData ? 0 : modelData)
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 5
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 6

                        Rectangle {
                            width: 26; height: 26; radius: 7
                            color: addBtnMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.28) : root.selectedDay > 0 ? T.Theme.pillBg : "transparent"
                            opacity: root.selectedDay > 0 ? 1.0 : 0.25
                            Behavior on color   { ColorAnimation { duration: T.Theme.animFast } }
                            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                            Text { anchors.centerIn: parent; text: "+"; color: T.Theme.fg; font.pixelSize: 15; font.family: T.Theme.fontFamily; font.weight: Font.Light }
                            MouseArea { id: addBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.selectedDay > 0; onClicked: calActionPopup.open("add") }
                        }
                    }
                }

                // Notes + holiday display — one row per item
                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.selectedDay > 0 ? notesCol.implicitHeight + 2 : 0
                    visible: root.selectedDay > 0
                    clip: true
                    opacity: (root.selectedNotes.length > 0 || root.holidays[root.calYear + "-" + (root.calMonth+1) + "-" + root.selectedDay] !== undefined) ? 1.0 : 0.0
                    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity        { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: notesCol
                        anchors { left: parent.left; right: parent.right }
                        spacing: 3

                        // Holiday row (read-only)
                        Rectangle {
                            property string holidayText: root.holidays[root.calYear + "-" + (root.calMonth+1) + "-" + root.selectedDay] || ""
                            visible: holidayText !== ""
                            Layout.fillWidth: true
                            implicitHeight: holidayRow.implicitHeight + 10
                            radius: 7
                            color: T.Theme.pw(T.Theme.pal?.colors?.color3, 0.08)
                            border.width: 1; border.color: T.Theme.pw(T.Theme.pal?.colors?.color3, 0.22)

                            RowLayout {
                                id: holidayRow
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                                spacing: 6
                                Text { text: "✦"; color: T.Theme.pw(T.Theme.pal?.colors?.color3, 0.80); font.pixelSize: 9; font.family: T.Theme.fontFamily }
                                Text { Layout.fillWidth: true; text: parent.parent.holidayText; color: T.Theme.fg; font.pixelSize: 11; font.family: T.Theme.fontFamily; elide: Text.ElideRight }
                            }
                        }

                        // User notes — one row each with edit + delete
                        Repeater {
                            model: root.notesVersion >= 0 ? root.selectedNotes : []
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: noteRowL.implicitHeight + 10
                                radius: 7
                                color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.08)
                                border.width: 1; border.color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.22)

                                RowLayout {
                                    id: noteRowL
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 4 }
                                    spacing: 4

                                    Text { text: "✎"; color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.60); font.pixelSize: 9; font.family: T.Theme.fontFamily }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData
                                        color: T.Theme.fg; font.pixelSize: 11; font.family: T.Theme.fontFamily
                                        elide: Text.ElideRight
                                    }

                                    // Edit button
                                    Rectangle {
                                        width: 20; height: 20; radius: 5
                                        color: editNoteMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.28) : "transparent"
                                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                        Text { anchors.centerIn: parent; text: "✎"; color: T.Theme.fg; opacity: 0.55; font.pixelSize: 9 }
                                        MouseArea { id: editNoteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calActionPopup.open("edit", index) }
                                    }

                                    // Delete button
                                    Rectangle {
                                        width: 20; height: 20; radius: 5
                                        color: delNoteMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.22) : "transparent"
                                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                        Text { anchors.centerIn: parent; text: "✕"; color: T.Theme.color1; opacity: 0.70; font.pixelSize: 8 }
                                        MouseArea { id: delNoteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calActionPopup.open("remove", index) }
                                    }
                                }
                            }
                        }
                    }
                }

                // Calendar action popup
                Item {
                    id: calActionPopup
                    property string mode: ""
                    property bool active: false
                    property bool _fullyHidden: true

                    readonly property real contentH: popupInner.implicitHeight + 16

                    function open(m, noteIdx) {
                        if (root.selectedDay === 0) return
                        mode = m
                        root.selectedNoteIndex = (noteIdx !== undefined) ? noteIdx : -1
                        _fullyHidden = false
                        active = true
                        if (m === "edit" && noteIdx !== undefined) {
                            noteInput.text = root.selectedNotes[noteIdx] || ""
                        } else {
                            noteInput.text = ""
                        }
                        focusDelay.restart()
                    }
                    function close() { active = false; mode = ""; hideDelay.restart() }
                    function confirm() {
                        var key = root.calYear + "-" + (root.calMonth+1) + "-" + root.selectedDay
                        var notes = Object.assign({}, root.calNotes)
                        var arr = notes[key] ? (Array.isArray(notes[key]) ? notes[key].slice() : [notes[key]]) : []
                        if (mode === "remove") {
                            arr.splice(root.selectedNoteIndex, 1)
                            if (arr.length === 0) delete notes[key]
                            else notes[key] = arr
                        } else if (mode === "edit" && root.selectedNoteIndex >= 0) {
                            if (noteInput.text.trim() !== "") {
                                arr[root.selectedNoteIndex] = noteInput.text.trim()
                                notes[key] = arr
                            }
                        } else if (mode === "add" && noteInput.text.trim() !== "") {
                            arr.push(noteInput.text.trim())
                            notes[key] = arr
                        }
                        root.calNotes = notes
                        root.notesVersion++
                        root.saveNotes()
                        close()
                    }

                    Timer { id: focusDelay; interval: 100; onTriggered: {
                        if (calActionPopup.mode === "add" || calActionPopup.mode === "edit") {
                            popupFocusScope.forceActiveFocus()
                            noteInput.forceActiveFocus()
                            noteInput.cursorPosition = noteInput.text.length
                        }
                    }}
                    Timer { id: hideDelay; interval: 200; onTriggered: calActionPopup._fullyHidden = true }

                    Layout.fillWidth: true
                    implicitHeight: _fullyHidden ? 0 : contentH
                    clip: true
                    Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    Item {
                        id: popupInner
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 8 }
                        implicitHeight: popupCol.implicitHeight + 20

                        opacity: calActionPopup.active ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            color: T.Theme.pw(T.Theme.pal?.colors?.color0, 0.92)
                            border.color: T.Theme.pw(calActionPopup.mode === "remove" ? T.Theme.pal?.colors?.color1 : T.Theme.pal?.colors?.color1, calActionPopup.mode === "remove" ? 0.45 : 0.20)
                            border.width: 1
                        }

                        FocusScope {
                            id: popupFocusScope
                            anchors.fill: parent

                            ColumnLayout {
                                id: popupCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: {
                                            var day = root.monthNames[root.calMonth] + " " + root.selectedDay
                                            if (calActionPopup.mode === "add") return "Add note — " + day
                                            if (calActionPopup.mode === "edit") return "Edit note — " + day
                                            if (calActionPopup.mode === "remove") return "Delete note — " + day
                                            return ""
                                        }
                                        color: T.Theme.fg; font.pixelSize: 11; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily; Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        width: 18; height: 18; radius: 5
                                        color: xMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.15) : "transparent"
                                        Text { anchors.centerIn: parent; text: "✕"; color: T.Theme.fg; opacity: 0.45; font.pixelSize: 9 }
                                        MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; onClicked: calActionPopup.close() }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; height: 32; radius: 7
                                    visible: calActionPopup.mode === "add" || calActionPopup.mode === "edit"
                                    color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
                                    border.color: noteInput.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.55) : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.18)
                                    border.width: 1

                                    TextInput {
                                        id: noteInput
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: T.Theme.fg; font.pixelSize: 12; font.family: T.Theme.fontFamily
                                        selectByMouse: true
                                        clip: true
                                        Keys.onReturnPressed: calActionPopup.confirm()
                                        Keys.onEscapePressed: calActionPopup.close()
                                    }
                                    Text {
                                        anchors { fill: parent; leftMargin: 10 }
                                        verticalAlignment: Text.AlignVCenter
                                        text: "What's happening?"
                                        color: T.Theme.fg; opacity: 0.25; font.pixelSize: 12; font.family: T.Theme.fontFamily
                                        visible: noteInput.text.length === 0 && !noteInput.activeFocus
                                    }
                                }

                                Text {
                                    visible: calActionPopup.mode === "remove"
                                    text: "This will permanently delete this note."
                                    color: T.Theme.fg; opacity: 0.55; font.pixelSize: 11; font.family: T.Theme.fontFamily
                                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        width: 56; height: 26; radius: 7
                                        color: cancelBtnMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.18) : T.Theme.pillBg
                                        Text { anchors.centerIn: parent; text: "Cancel"; color: T.Theme.fg; opacity: 0.55; font.pixelSize: 11; font.family: T.Theme.fontFamily }
                                        MouseArea { id: cancelBtnMa; anchors.fill: parent; hoverEnabled: true; onClicked: calActionPopup.close() }
                                    }

                                    Rectangle {
                                        width: calActionPopup.mode === "remove" ? 64 : 52; height: 26; radius: 7
                                        color: confirmBtnMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.40) : T.Theme.pw(T.Theme.pal?.colors?.color1, 0.22)
                                        Text {
                                            anchors.centerIn: parent
                                            text: calActionPopup.mode === "remove" ? "Remove" : "Save"
                                            color: T.Theme.fg
                                            font.pixelSize: 11; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                                        }
                                        MouseArea { id: confirmBtnMa; anchors.fill: parent; hoverEnabled: true; onClicked: calActionPopup.confirm() }
                                    }
                                }
                            }
                        }
                    }
                }
            }  // closes ColumnLayout { id: calInner }
        }  // end calWrapper

        Rectangle { Layout.fillWidth: true; height: 1; color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07) }

        // Timer (pill style)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Timer"; color: T.Theme.fg; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                Text { text: "Countdown"; color: T.Theme.color1; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 64
                radius: 16
                color: T.Theme.pillBg
                visible: !root.timerRunning && !root.timerFinished

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    component SpinField: Rectangle {
                        property int value: 0
                        property int maxVal: 59
                        width: 48; height: 48; radius: 12; color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: value < 10 ? "0" + value : value
                            color: T.Theme.fg
                            font.pixelSize: 22; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: value = (value + 1) % (maxVal + 1)
                            onWheel: value = (value + (wheel.angleDelta.y > 0 ? 1 : -1) + maxVal + 1) % (maxVal + 1)
                        }
                    }

                    SpinField { id: hField; maxVal: 23; onValueChanged: root.timerH = value }
                    Text { text: ":"; color: T.Theme.fg; opacity: 0.4; font.pixelSize: 24; font.weight: Font.Bold }
                    SpinField { id: mField; maxVal: 59; onValueChanged: root.timerM = value }
                    Text { text: ":"; color: T.Theme.fg; opacity: 0.4; font.pixelSize: 24; font.weight: Font.Bold }
                    SpinField { id: sField; maxVal: 59; onValueChanged: root.timerS = value }

                    Rectangle {
                        width: 48; height: 48; radius: 12
                        color: startMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.3) : T.Theme.pw(T.Theme.pal?.colors?.color1, 0.2)
                        Text { anchors.centerIn: parent; text: "▶"; color: T.Theme.color1; font.pixelSize: 18 }
                        MouseArea { id: startMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.startTimer() }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: root.timerRunning || root.timerFinished

                Text {
                    Layout.fillWidth: true
                    text: root.timerFinished ? "00:00:00" : root.timerRemainStr()
                    color: root.timerFinished ? T.Theme.pal?.colors?.color1 ?? T.Theme.color1 : T.Theme.color1
                    opacity: root.timerFinished ? (root._flashCount % 2 === 0 ? 1.0 : 0.0) : 1.0
                    font.pixelSize: 42; font.weight: Font.Bold; font.family: T.Theme.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    width: 48; height: 48; radius: 12
                    color: stopMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.3) : T.Theme.pw(T.Theme.pal?.colors?.color1, 0.2)
                    Text { anchors.centerIn: parent; text: "■"; color: T.Theme.color1; font.pixelSize: 18 }
                    MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.stopTimer() }
                }
            }
        }
    }
}