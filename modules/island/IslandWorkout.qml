pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/workout.js" as W

// ── IslandWorkout ─────────────────────────────────────────────────────────────
// A workout as a checklist, on the bottom-left island (2026-11-16, the user: "start a workout which would
// start a timer … track workouts by date", then "make it like a checking list with beautiful animations").
//
//   left    the loud card. Idle: this week and the streak, one big Start. Running: the clock, a pill for every
//           set that fills as it is ticked off, the rest since the last one, Finish. Under it a rail: Log, History.
//   Log     add an exercise (type it, or tap one you do often: it comes with the numbers you used last) and it
//           stands on the list as a card with its sets to do. Tick a set and its disc blooms into a shape, the
//           row goes round and takes the accent; the pills in the loud card fill. Tweak a set's reps or weight
//           with the buttons that come out under the pointer. A card whose sets are all done folds itself away.
//   History twelve weeks as a heat grid (tap a day), the numbers beside it, and that day's workouts with a
//           Keep / Delete layer.
//
// Only ticked sets are kept when the workout finishes (services/workout.js). The rules are that file (pure,
// `bun scripts/test-workout.js`); services/Workouts holds the state and workouts.json. This shows and calls.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 16 + Tokens.spacingSm
    readonly property string unit: Workouts.unit

    // "log" | "history"
    property string view: "log"

    // The running workout's exercises, never null.
    readonly property var entries: Workouts.active ? Workouts.active.entries : []
    readonly property var tally: Workouts.stats
    readonly property int remaining: root.tally.total - root.tally.sets

    // ── What the next exercise comes with ─────────────────────────────────────
    property string exName: ""
    property string kind: "reps"
    property int reps: 10
    property real weight: 0
    property int secs: 45
    property int setCount: 3
    property bool tuning: false
    readonly property real weightStep: root.unit === "lb" ? 5 : 2.5

    // ── The add field ─────────────────────────────────────────────────────────
    // What is typed is read for numbers ("bench 3x8 60kg"), matched against what you have done and a built-in
    // list, and what is not typed is filled from the last time (services/workout.js quickSpec). `sel` is the
    // highlighted choice: -1 is the text exactly as typed, 0 up the matches. Typing highlights the best match,
    // Up / Down move, Tab takes its name into the field, Enter (or a tap) adds it.
    readonly property var defaults: ({ kind: root.kind, sets: root.setCount, reps: root.reps, weight: root.weight, secs: root.secs })
    readonly property bool typing: root.exName.trim() !== ""
    readonly property var matches: root.typing ? Workouts.suggest(root.exName, 6) : []
    readonly property string typedName: W.parseQuick(root.exName, root.unit).name
    // Is what was typed already the name of the first match: then there is nothing "new" to offer.
    readonly property bool typedIsMatch: root.matches.length > 0 && root.matches[0].name.toLowerCase() === root.typedName.toLowerCase()
    property int sel: 0
    readonly property int selAt: Math.min(root.sel, root.matches.length - 1)
    readonly property string tail: W.parseQuick(root.exName, root.unit).tail
    readonly property var picked: root.selAt >= 0 ? root.matches[root.selAt] : null
    // The exercise Enter would add, or null.
    readonly property var addSpec: {
        if (!root.typing || !Workouts.ready || !Workouts.running) return null
        const text = root.picked ? root.picked.name + (root.tail !== "" ? " " + root.tail : "") : root.exName
        const sp = Workouts.spec(text, root.defaults)
        return sp.name === "" ? null : sp
    }
    readonly property bool canAdd: root.addSpec !== null
    function specText(sp) {
        const one = sp.kind === "time" ? (sp.secs >= 60 ? W.clock(sp.secs * 1000) : sp.secs + " s") : String(sp.reps)
        return sp.sets + " × " + one + (sp.weight > 0 ? " · " + W.weightText(sp.weight) + " " + root.unit : "")
    }
    function addSpecNow(sp) {
        if (!sp || !Workouts.running) return
        Workouts.planSets(sp, sp.sets)
        root.exName = ""
        nameField.clear()
        root.sel = 0
        nameField.forceFocus()
    }
    function addTyped() { root.addSpecNow(root.addSpec) }
    // A chip: that exercise, with what was typed beside its name.
    function addMatch(m) {
        root.addSpecNow(Workouts.spec(m.name + (root.tail !== "" ? " " + root.tail : ""), root.defaults))
    }
    function stepSel(dir) {
        if (root.matches.length === 0) return
        root.sel = Math.max(root.typedIsMatch ? 0 : -1, Math.min(root.matches.length - 1, root.selAt + dir))
    }
    function takeSel() {
        const m = root.picked || root.matches[0]
        if (!m) return
        nameField.setText(m.name + (root.tail !== "" ? " " + root.tail : ""))
    }

    // ── Next up, records ─────────────────────────────────────────────────────
    // The first set still to do, in the order exercises were added.
    readonly property var nextUp: {
        for (const e of root.entries)
            for (let i = 0; i < e.sets.length; i++)
                if (e.sets[i].done === false) return { e: e, i: i }
        return null
    }
    readonly property string nextKey: root.nextUp ? root.nextUp.e.id + ":" + root.nextUp.i : ""
    readonly property int records: {
        let n = 0
        for (const e of root.entries) for (const s of e.sets) if (s.done !== false && Workouts.isRecord(e.kind, e.name, s)) n++
        return n
    }

    // ── History ───────────────────────────────────────────────────────────────
    // Read when the page appears, not every second: the clock ticks while a workout runs.
    property real stamp: Date.now()
    onVisibleChanged: if (root.visible) root.stamp = Date.now()
    property int weeksBack: 0
    property string pickedDay: ""
    // The id of the workout whose delete is waiting for Keep / Delete, 0 for none.
    property int armed: 0
    property bool armDiscard: false

    readonly property var heatGrid: W.heat(Workouts.history, root.stamp, 12, root.weeksBack)
    readonly property var days: W.byDay(Workouts.history)
    readonly property var summary: W.summary(Workouts.history, root.stamp)
    readonly property string latestKey: Workouts.history.length > 0 ? W.dayKey(Workouts.history[0].start) : ""
    readonly property string shownDay: root.pickedDay !== "" ? root.pickedDay : root.latestKey
    readonly property var shownList: root.days[root.shownDay] ?? []

    function dayDate(key) {
        const p = String(key).split("-")
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    }
    function dayTitle(key) {
        if (key === "") return ""
        const today = W.dayKey(root.stamp)
        const y = new Date(root.stamp); y.setDate(y.getDate() - 1)
        if (key === today) return Translation.tr("Today")
        if (key === W.dayKey(y.getTime())) return Translation.tr("Yesterday")
        return Qt.formatDate(root.dayDate(key), "dddd d MMMM")
    }
    function ago(ms) {
        const d = Math.round((W.dayStart(root.stamp) - W.dayStart(ms)) / 86400000)
        return d <= 0 ? Translation.tr("today") : d === 1 ? Translation.tr("yesterday") : Translation.tr("%1 days ago").arg(d)
    }
    // One exercise as a line: "3 × 12 × 20 kg" when every set is alike, else each set in turn.
    function entryLine(e) {
        let same = e.sets.length > 1
        for (let i = 1; i < e.sets.length && same; i++) {
            const a = e.sets[0], b = e.sets[i]
            if (a.reps !== b.reps || a.weight !== b.weight || a.secs !== b.secs) same = false
        }
        return same ? e.sets.length + " × " + W.setText(e.kind, e.sets[0], root.unit)
                    : e.sets.map(s => W.setText(e.kind, s, root.unit)).join(", ")
    }
    function volumeText(v) { return W.weightText(v) + " " + root.unit }
    function setsText(n) { return n === 1 ? Translation.tr("1 set") : Translation.tr("%1 sets").arg(n) }

    // ── Finishing: a recap over the loud card ─────────────────────────────────
    property var recap: null
    function finishNow() {
        const before = Workouts.history.length
        Workouts.finish()
        root.stamp = Date.now()
        root.pickedDay = ""
        root.weeksBack = 0
        root.recap = Workouts.history.length > before ? Workouts.history[0] : null
    }
    function closeRecap(toHistory) {
        root.recap = null
        if (toHistory) root.view = "history"
    }

    function handleEscape() {
        if (root.recap !== null) { root.closeRecap(false); return true }
        if (root.armed !== 0 || root.armDiscard) {
            root.armed = 0
            root.armDiscard = false
            return true
        }
        if (root.view === "history") { root.view = "log"; return true }
        return false
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ The loud card ═════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                id: hero
                Layout.fillWidth: true
                Layout.fillHeight: true
                hero: true
                order: 0
                radius: Tokens.radiusXl

                // ── Not started ───────────────────────────────────────────────
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs
                    visible: !Workouts.running

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        IslandBadge {
                            filled: true
                            size: Tokens.iconXl * 2
                            symbol: "dumbbell"
                            shape: "burst"
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: root.summary.streak > 0
                                ? Translation.tr("%1 day streak").arg(root.summary.streak) : ""
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: hero.inkDim
                        }
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: String(root.summary.week)
                        font.pixelSize: Tokens.fontDisplay * 2
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: hero.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.summary.week === 1 ? Translation.tr("workout this week")
                                                      : Translation.tr("workouts this week")
                        variant: "label"
                        color: hero.inkDim
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Workouts.history.length > 0
                            ? Translation.tr("Last one %1 · %2").arg(root.ago(Workouts.history[0].start))
                                  .arg(W.lasted(W.elapsed(Workouts.history[0], 0)))
                            : Translation.tr("Nothing logged yet")
                        variant: "caption"
                        color: hero.inkDim
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        ChipButton {
                            Layout.fillWidth: true
                            solid: true
                            symbol: "play_arrow"
                            label: Translation.tr("Start workout")
                            enabled: Workouts.ready
                            onActivated: { root.view = "log"; Workouts.start() }
                        }
                        // Do the last one again: its exercises and numbers, every set still to do.
                        ChipButton {
                            visible: Workouts.history.length > 0
                            tonal: true
                            tint: hero.ink
                            symbol: "replay"
                            enabled: Workouts.ready
                            Accessible.name: Translation.tr("Repeat the last workout")
                            onActivated: { root.view = "log"; Workouts.repeatLast() }
                            HoverTip { text: Translation.tr("Repeat the last workout") }
                        }
                    }
                }

                // ── Under way ─────────────────────────────────────────────────
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs
                    visible: Workouts.running

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            Layout.fillWidth: true
                            text: (Workouts.paused ? Translation.tr("Paused") : Translation.tr("Workout")).toUpperCase()
                            variant: "caption"
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                            color: hero.inkDim
                        }
                        LitTool {
                            symbol: Workouts.paused ? "play_arrow" : "pause"
                            lit: Workouts.paused
                            ink: hero.ink
                            tip: Workouts.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                            Accessible.name: tip
                            onActivated: Workouts.togglePause()
                        }
                        LitTool {
                            symbol: "delete"
                            ink: hero.ink
                            tip: Translation.tr("Discard this workout")
                            Accessible.name: tip
                            onActivated: root.armDiscard = true
                        }
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: W.clock(Workouts.elapsedMs)
                        font.pixelSize: Tokens.fontDisplay * 1.7
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: hero.ink
                        opacity: Workouts.paused ? 0.55 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Tokens.fontDisplay
                    }

                    // How many are done: the figure bumps each time one is ticked.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            id: doneFig
                            text: String(root.tally.sets)
                            font.pixelSize: Tokens.fontTitle
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            color: hero.ink
                            transformOrigin: Item.Left
                            scale: figBump.value
                            SpringValue { id: figBump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                            Connections {
                                target: root
                                function onTallyChanged() { if (Config.motionEnabled) { figBump.jump(1.35); figBump.target = 1 } }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.tally.total === 0 ? Translation.tr("Add an exercise to begin")
                                : root.remaining === 0 ? Translation.tr("of %1 sets · all done").arg(root.tally.total)
                                : Translation.tr("of %1 sets").arg(root.tally.total)
                            variant: "label"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }

                    // One pill a set, filling as they are ticked.
                    Row {
                        id: pills
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Tokens.spacingMd
                        visible: root.tally.total > 0
                        spacing: Tokens.spacingXs
                        readonly property int n: Math.min(24, root.tally.total)
                        readonly property real w: pills.n > 0 ? (pills.width - pills.spacing * (pills.n - 1)) / pills.n : 0
                        Repeater {
                            model: pills.n
                            delegate: Rectangle {
                                id: pill
                                required property int index
                                // Past 24 sets the pills stand for equal shares of the whole.
                                readonly property bool lit: root.tally.total <= 24
                                    ? pill.index < root.tally.sets
                                    : (pill.index + 1) / 24 <= root.tally.sets / root.tally.total + 0.0001
                                width: pills.w
                                height: pills.height
                                radius: height / 2
                                color: pill.lit ? hero.palette.primary : hero.palette.alpha(hero.ink, 0.16)
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                // The one just filled swells and settles. Not while the page is being built: a pill
                                // that is lit from the start has nothing to announce.
                                property bool armed: false
                                Component.onCompleted: pill.armed = true
                                SequentialAnimation {
                                    id: swell
                                    NumberAnimation { target: pill; property: "scale"; to: 1.45; duration: Motion.respond; easing.type: Motion.travel }
                                    NumberAnimation { target: pill; property: "scale"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
                                }
                                onLitChanged: if (pill.armed && pill.lit && Config.motionEnabled) swell.restart()
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacingXs
                        visible: root.tally.volume > 0 || root.tally.secs > 0
                        text: [root.tally.volume > 0 ? root.volumeText(root.tally.volume) : "",
                               root.tally.secs > 0 ? W.clock(root.tally.secs * 1000) + " " + Translation.tr("held") : ""]
                              .filter(s => s !== "").join(" · ")
                        variant: "caption"
                        font.features: ({ tnum: 1 })
                        color: hero.inkDim
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.records > 0
                        text: "★ " + (root.records === 1 ? Translation.tr("New record") : Translation.tr("%1 new records").arg(root.records))
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: hero.ink
                    }
                    Item { Layout.fillHeight: true }

                    // ── Next up: the set to do now, with a button to tick it ─────
                    Rectangle {
                        id: nextCard
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: nextRow.implicitHeight + Tokens.spacingMd * 2
                        visible: root.tally.total > 0
                        radius: Tokens.radiusCard
                        color: hero.palette.alpha(hero.ink, 0.10)
                        SpringValue { id: nextBump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                        scale: nextBump.value
                        Connections {
                            target: root
                            function onNextKeyChanged() { if (Config.motionEnabled) { nextBump.jump(0.94); nextBump.target = 1 } }
                        }
                        RowLayout {
                            id: nextRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingMd
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: (root.nextUp ? Translation.tr("Next up") : Translation.tr("Done")).toUpperCase()
                                    variant: "micro"
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                    color: hero.inkDim
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.nextUp ? root.nextUp.e.name : Translation.tr("Every set is done")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    color: hero.ink
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.nextUp !== null
                                    text: root.nextUp ? Translation.tr("Set %1 of %2").arg(root.nextUp.i + 1).arg(root.nextUp.e.sets.length)
                                          + " · " + W.setText(root.nextUp.e.kind, root.nextUp.e.sets[root.nextUp.i], root.unit) : ""
                                    variant: "caption"
                                    font.features: ({ tnum: 1 })
                                    color: hero.inkDim
                                    elide: Text.ElideRight
                                }
                            }
                            ChipButton {
                                visible: root.nextUp !== null
                                solid: true
                                symbol: "check"
                                Accessible.name: Translation.tr("Tick the next set")
                                onActivated: if (root.nextUp) Workouts.toggleSet(root.nextUp.e.id, root.nextUp.i)
                                HoverTip { text: Translation.tr("Tick the next set") }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true; Layout.preferredHeight: Tokens.spacingXs }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        // The rest since the last tick: when to go again.
                        ChipButton {
                            id: restChip
                            visible: Workouts.restMs > 0
                            tonal: true
                            tint: hero.ink
                            symbol: "timer"
                            label: W.clock(Workouts.restMs)
                            Accessible.name: Translation.tr("Rest since the last set")
                            HoverTip { text: Translation.tr("Rest since the last set"); below: false }
                        }
                        Item { Layout.fillWidth: true }
                        ChipButton {
                            solid: true
                            symbol: "check"
                            label: Translation.tr("Finish")
                            onActivated: root.finishNow()
                            HoverTip {
                                text: root.remaining > 0 ? Translation.tr("%1 sets not done are left out").arg(root.remaining)
                                                    : Translation.tr("Save this workout")
                            }
                        }
                    }
                }

                // ── Discard: a layer, not a second press ──────────────────────
                Rectangle {
                    anchors.fill: parent
                    radius: hero.radius
                    color: hero.palette.primaryContainer
                    opacity: root.armDiscard ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
                    MouseArea { anchors.fill: parent; enabled: root.armDiscard }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm
                        Item { Layout.fillHeight: true }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Discard this workout?")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                            wrapMode: Text.WordWrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("What you logged in it is lost.")
                            variant: "caption"
                            color: hero.inkDim
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            ChipButton {
                                tonal: true
                                tint: hero.ink
                                label: Translation.tr("Keep")
                                onActivated: root.armDiscard = false
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                solid: true
                                tint: hero.palette.danger
                                symbol: "delete"
                                label: Translation.tr("Discard")
                                onActivated: { root.armDiscard = false; Workouts.discard() }
                            }
                        }
                    }
                }

                // ── Finished: what you just did, over the loud card ───────────
                Rectangle {
                    id: recapLayer
                    anchors.fill: parent
                    radius: hero.radius
                    color: hero.palette.primaryContainer
                    opacity: root.recap !== null ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    // The card keeps its own copy, so the way out is not spent on an empty card.
                    property var held: null
                    Connections {
                        target: root
                        function onRecapChanged() { if (root.recap !== null) recapLayer.held = root.recap }
                    }
                    readonly property var st: W.stats(recapLayer.held)
                    MouseArea { anchors.fill: parent; enabled: root.recap !== null }
                    Timer { interval: 9000; running: root.recap !== null; onTriggered: root.closeRecap(false) }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingXs

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Tokens.iconXl * 2.4
                            Layout.preferredHeight: Tokens.iconXl * 2.4
                            Layout.topMargin: Tokens.spacingMd
                            MorphShape {
                                anchors.fill: parent
                                shape: root.recap !== null ? "cookie9" : "circle"
                                spec: Motion.springSpatial
                                fillColor: hero.palette.primary
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "check"
                                fill: 1
                                font.pixelSize: Tokens.iconXl * 1.2
                                color: hero.palette.fgOnPrimary
                                scale: root.recap !== null ? 1 : 0.3
                                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingSm
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Workout saved")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: recapLayer.held ? W.lasted(W.elapsed(recapLayer.held, 0)) : ""
                            variant: "label"
                            color: hero.inkDim
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            Repeater {
                                model: [
                                    { n: String(recapLayer.st.sets), t: Translation.tr("sets") },
                                    { n: String(recapLayer.st.exercises), t: Translation.tr("exercises") },
                                    { n: recapLayer.st.volume > 0 ? W.weightText(recapLayer.st.volume) : (recapLayer.st.secs > 0 ? W.clock(recapLayer.st.secs * 1000) : "–"),
                                      t: recapLayer.st.volume > 0 ? root.unit : Translation.tr("held") }
                                ]
                                delegate: ColumnLayout {
                                    id: stat
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    spacing: 0
                                    PopIn { id: statPop; active: root.recap !== null; index: stat.index + 1 }
                                    opacity: statPop.opacity
                                    scale: statPop.scale
                                    StyledText {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: stat.modelData.n
                                        font.pixelSize: Tokens.fontTitle
                                        font.weight: Font.Bold
                                        font.features: ({ tnum: 1 })
                                        color: hero.ink
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: stat.modelData.t
                                        variant: "micro"
                                        color: hero.inkDim
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            ChipButton {
                                tonal: true
                                tint: hero.ink
                                symbol: "history"
                                label: Translation.tr("History")
                                onActivated: root.closeRecap(true)
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                solid: true
                                symbol: "check"
                                label: Translation.tr("Done")
                                onActivated: root.closeRecap(false)
                            }
                        }
                    }
                }
            }

            SourceRail {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 2 * (Tokens.iconXl + Tokens.spacingMd) + Tokens.spacingSm * 2 + Tokens.spacingXs
                current: root.view
                model: [
                    { value: "log", label: Translation.tr("Checklist"), icon: "checklist", shape: "cookie9",
                      figure: Workouts.running ? String(root.tally.sets) + "/" + String(root.tally.total) : "–",
                      big: false, live: Workouts.running },
                    { value: "history", label: Translation.tr("History"), icon: "history", shape: "clover",
                      figure: String(Workouts.history.length) }
                ]
                onPicked: v => root.view = v
            }
        }

        // ══ The page ══════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ─────────────────────── The checklist ───────────────────────────
            ColumnLayout {
                id: pageLog
                anchors.fill: parent
                spacing: Tokens.spacingMd
                opacity: root.view === "log" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transform: Translate { x: (1 - pageLog.opacity) * -16 }

                // Adding: a field, the exercises you do most, and the numbers behind a fold.
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: addCol.implicitHeight + Tokens.spacingLg * 2
                    order: 1
                    radius: Tokens.radiusXl
                    enabled: Workouts.running

                    ColumnLayout {
                        id: addCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm
                        opacity: Workouts.running ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            WorkoutField {
                                id: nameField
                                Layout.fillWidth: true
                                lead: Translation.tr("Add an exercise")
                                hints: [{ key: "pull-ups 4x8" }, { key: "bench 3x10 @ 60" }, { key: "plank 45s" },
                                        { key: "squat 5x5 100kg" }, { key: "dips" }, { key: "wall sit 2 min" }]
                                readyText: root.addSpec ? root.specText(root.addSpec) : ""
                                onEdited: function (v) { root.exName = v; root.sel = 0 }
                                onAccepted: root.addTyped()
                                onStep: function (d) { root.stepSel(d) }
                                onComplete: root.takeSel()
                            }
                            ChipButton {
                                symbol: "tune"
                                on: root.tuning
                                Accessible.name: Translation.tr("Sets, reps and weight for the next exercise")
                                onActivated: root.tuning = !root.tuning
                                HoverTip { text: Translation.tr("Sets, reps and weight for the next exercise") }
                            }
                        }

                        // Idle: what you do most, one tap adds it with last time's numbers. Typing: what matches,
                        // the highlighted one is what Enter adds.
                        Flow {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            visible: root.typing ? (root.matches.length > 0 || root.typedName !== "") : Workouts.recent.length > 0
                            spacing: Tokens.spacingXs
                            // The text as typed, when it is not one of the matches.
                            ChipButton {
                                visible: root.typing && root.typedName !== "" && !root.typedIsMatch
                                symbol: "add"
                                label: root.typedName
                                on: root.selAt < 0
                                onActivated: root.addSpecNow(Workouts.spec(root.exName, root.defaults))
                            }
                            Repeater {
                                model: root.typing ? root.matches : Workouts.recent.slice(0, 6)
                                delegate: ChipButton {
                                    id: sug
                                    required property var modelData
                                    required property int index
                                    tonal: !sug.modelData.known
                                    symbol: sug.modelData.kind === "time" ? "timer" : "add"
                                    label: sug.modelData.name
                                    on: root.typing && sug.index === root.selAt
                                    onActivated: root.typing ? root.addMatch(sug.modelData) : root.addSpecNow(Workouts.spec(sug.modelData.name, root.defaults))
                                }
                            }
                        }

                        // The fold: how the next exercise is set up.
                        Item {
                            id: fold
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: foldHeight.value
                            clip: true
                            SpringValue {
                                id: foldHeight
                                target: root.tuning ? foldRow.implicitHeight + Tokens.spacingXs : 0
                                spec: Motion.springSpatial
                                epsilon: 0.05
                            }
                            opacity: foldHeight.target > 0 ? 1 : (foldHeight.value > 1 ? 1 : 0)

                            RowLayout {
                                id: foldRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: Tokens.spacingXs
                                spacing: Tokens.spacingSm

                                ChipButton {
                                    symbol: "repeat"
                                    label: Translation.tr("Reps")
                                    on: root.kind === "reps"
                                    onActivated: root.kind = "reps"
                                }
                                ChipButton {
                                    symbol: "timer"
                                    label: Translation.tr("Time")
                                    on: root.kind === "time"
                                    onActivated: root.kind = "time"
                                }
                                Item { Layout.fillWidth: true }
                                NumberStepper {
                                    compact: true
                                    numberWidth: Tokens.spacingXl * 2
                                    from: 1; to: 10; step: 1
                                    value: root.setCount
                                    readout: value + " ×"
                                    onCommit: function (v) { root.setCount = v }
                                    Accessible.name: Translation.tr("How many sets")
                                }
                                NumberStepper {
                                    visible: root.kind === "reps"
                                    compact: true
                                    numberWidth: Tokens.spacingXl * 4
                                    from: 1; to: 100; step: 1
                                    value: root.reps
                                    readout: value + " " + Translation.tr("reps")
                                    onCommit: function (v) { root.reps = v }
                                }
                                NumberStepper {
                                    visible: root.kind === "time"
                                    compact: true
                                    numberWidth: Tokens.spacingXl * 4
                                    from: 5; to: 3600; step: 5
                                    value: root.secs
                                    readout: root.secs >= 60 ? W.clock(root.secs * 1000) : root.secs + " s"
                                    onCommit: function (v) { root.secs = v }
                                }
                                NumberStepper {
                                    compact: true
                                    numberWidth: Tokens.spacingXl * 4
                                    from: 0; to: 500; step: root.weightStep
                                    value: root.weight
                                    readout: root.weight <= 0 ? Translation.tr("Body") : W.weightText(root.weight) + " " + root.unit
                                    onCommit: function (v) { root.weight = v }
                                    Accessible.name: Translation.tr("Extra weight, body means none")
                                }
                            }
                        }
                    }
                }

                // The list
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    order: 2
                    radius: Tokens.radiusXl

                    // Not started: a dumbbell and a way in.
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingXl * 2
                        spacing: Tokens.spacingSm
                        visible: !Workouts.running
                        IslandBadge {
                            Layout.alignment: Qt.AlignHCenter
                            size: Tokens.iconXl * 2
                            symbol: "dumbbell"
                            shape: "cookie9"
                            filled: true
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Start a workout")
                            variant: "title"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Add your exercises, tick each set off as you do it. The clock starts with you.")
                            variant: "caption"
                            emphasis: "muted"
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Started, nothing on the list yet.
                    StyledText {
                        anchors.centerIn: parent
                        visible: Workouts.running && root.entries.length === 0
                        text: Translation.tr("Add your first exercise above")
                        variant: "label"
                        emphasis: "muted"
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingSm
                        visible: Workouts.running && root.entries.length > 0

                        Flickable {
                            id: listFlick
                            anchors.fill: parent
                            anchors.rightMargin: Tokens.spacingSm
                            anchors.bottomMargin: restK.value * (restBar.height + Tokens.spacingSm)
                            contentWidth: width
                            contentHeight: listCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: listCol
                                width: listFlick.width
                                spacing: Tokens.spacingSm

                                Repeater {
                                    model: ScriptModel {
                                        objectProp: "id"
                                        // The one you added last is on top: it is the one you are doing.
                                        values: root.entries.slice().reverse()
                                    }
                                    delegate: Rectangle {
                                        id: card
                                        required property var modelData
                                        required property int index
                                        readonly property var e: card.modelData
                                        readonly property int total: card.e.sets.length
                                        readonly property int doneN: card.e.sets.filter(s => s.done !== false).length
                                        readonly property bool complete: card.total > 0 && card.doneN === card.total
                                        // Folded: on its own once every set is done, or by the header.
                                        property bool open: true
                                        property bool decided: false

                                        width: listCol.width
                                        height: head.height + bodyBox.height + Tokens.spacingMd
                                        radius: Tokens.radiusCard
                                        color: root.palette.plate
                                        clip: true

                                        PopIn { id: pop; active: true; index: 0 }
                                        opacity: pop.opacity
                                        scale: pop.scale

                                        Timer {
                                            id: foldAway
                                            interval: 900
                                            onTriggered: if (!card.decided && card.complete) card.open = false
                                        }
                                        onCompleteChanged: {
                                            if (card.complete) foldAway.restart()
                                            else { foldAway.stop(); if (!card.decided) card.open = true }
                                        }

                                        HoverHandler { id: cardHover }

                                        // ── Header ────────────────────────────────────────────
                                        Item {
                                            id: head
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: Tokens.iconXl + Tokens.spacingMd * 2

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { card.decided = true; card.open = !card.open }
                                                Accessible.role: Accessible.Button
                                                Accessible.name: card.open ? Translation.tr("Fold %1").arg(card.e.name) : Translation.tr("Unfold %1").arg(card.e.name)
                                            }
                                            HoverHandler { id: headHover }
                                            StateLayer {
                                                anchors.fill: parent
                                                radius: card.radius
                                                hovered: headHover.hovered
                                                layerColor: root.palette.fg
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Tokens.spacingMd
                                                anchors.rightMargin: Tokens.spacingMd
                                                spacing: Tokens.spacingMd

                                                // Its progress as a badge: a disc with the count, a shape with a tick when done.
                                                Item {
                                                    Layout.preferredWidth: Tokens.iconXl
                                                    Layout.preferredHeight: Tokens.iconXl
                                                    MorphShape {
                                                        anchors.fill: parent
                                                        shape: card.complete ? "cookie9" : "circle"
                                                        spec: Motion.springSpatialFast
                                                        fillColor: card.complete ? root.palette.primary : root.palette.section
                                                    }
                                                    // How far through it is, as a ring that fills as the sets are ticked.
                                                    RadialGauge {
                                                        anchors.fill: parent
                                                        thickness: Tokens.spacingXs + 1
                                                        value: card.total > 0 ? card.doneN / card.total : 0
                                                        accent: root.palette.primary
                                                        glide: true
                                                        opacity: card.complete ? 0 : 1
                                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                    }
                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: card.doneN + "/" + card.total
                                                        font.pixelSize: Tokens.fontMicro
                                                        font.weight: Font.Bold
                                                        font.features: ({ tnum: 1 })
                                                        color: root.palette.fgMuted
                                                        opacity: card.complete ? 0 : 1
                                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                    }
                                                    MaterialIcon {
                                                        anchors.centerIn: parent
                                                        name: "check"
                                                        fill: 1
                                                        font.pixelSize: Tokens.iconMd
                                                        color: root.palette.fgOnPrimary
                                                        opacity: card.complete ? 1 : 0
                                                        scale: card.complete ? 1 : 0.4
                                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                        Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: card.e.name
                                                        variant: "label"
                                                        font.weight: Font.DemiBold
                                                        color: card.complete ? root.palette.fgMuted : root.palette.fg
                                                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: root.entryLine(card.e)
                                                        variant: "micro"
                                                        emphasis: "muted"
                                                        font.features: ({ tnum: 1 })
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                // Under the pointer: another set, or all of it gone.
                                                Row {
                                                    spacing: Tokens.spacingXs
                                                    opacity: cardHover.hovered ? 1 : 0
                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                    CardTool {
                                                        symbol: "add"
                                                        name: Translation.tr("Add a set")
                                                        enabled: cardHover.hovered
                                                        onActivated: { Workouts.addSetLike(card.e.id); card.open = true; card.decided = true }
                                                        HoverTip { text: Translation.tr("Add a set") }
                                                    }
                                                    CardTool {
                                                        symbol: "delete"
                                                        name: Translation.tr("Remove the exercise")
                                                        enabled: cardHover.hovered
                                                        onActivated: Workouts.removeEntry(card.e.id)
                                                        HoverTip { text: Translation.tr("Remove the exercise") }
                                                    }
                                                }
                                                MaterialIcon {
                                                    name: "expand_more"
                                                    font.pixelSize: Tokens.iconLg
                                                    color: root.palette.fgMuted
                                                    rotation: card.open ? 0 : -90
                                                    Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                                                }
                                            }
                                        }

                                        // ── The sets, a checklist ──────────────────────────────
                                        Item {
                                            id: bodyBox
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: head.bottom
                                            height: bodyK.value * setCol.implicitHeight
                                            clip: true
                                            SpringValue {
                                                id: bodyK
                                                target: card.open ? 1 : 0
                                                spec: Motion.springSpatial
                                                epsilon: 0.002
                                            }
                                            opacity: Math.min(1, bodyK.value * 1.6)

                                            Column {
                                                id: setCol
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: Tokens.spacingMd
                                                anchors.rightMargin: Tokens.spacingMd
                                                spacing: Tokens.spacingXs

                                                Repeater {
                                                    model: card.e.sets
                                                    delegate: Rectangle {
                                                        id: row
                                                        required property var modelData
                                                        required property int index
                                                        readonly property bool done: row.modelData.done !== false
                                                        readonly property bool timed: card.e.kind === "time"

                                                        width: setCol.width
                                                        height: Tokens.iconXl + Tokens.spacingXs
                                                        // Done goes round, as a chosen card does everywhere on the island.
                                                        SpringValue { id: roundK; target: row.done ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
                                                        radius: Tokens.radiusSm + Math.max(0, roundK.value) * (height / 2 - Tokens.radiusSm)
                                                        color: row.done ? root.palette.primaryContainer
                                                                        : root.palette.alpha(root.palette.fg, rowHover.hovered ? 0.09 : 0.05)
                                                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                                                        readonly property color ink: row.done ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                                        readonly property color inkDim: row.done ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted

                                                        SpringValue {
                                                            id: leanK
                                                            target: rowTap.pressed ? 0.97 : 1
                                                            spec: Motion.springSpatialFast
                                                            epsilon: 0.001
                                                        }
                                                        scale: leanK.value

                                                        HoverHandler { id: rowHover }
                                                        MouseArea {
                                                            id: rowTap
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: Workouts.toggleSet(card.e.id, row.index)
                                                            Accessible.role: Accessible.CheckBox
                                                            Accessible.name: card.e.name + " " + (row.index + 1)
                                                            Accessible.checkable: true
                                                            Accessible.checked: row.done
                                                            Accessible.onPressAction: Workouts.toggleSet(card.e.id, row.index)
                                                        }

                                                        // The check: a disc that blooms into a shape with a tick, and a ring that leaves it.
                                                        Item {
                                                            id: box
                                                            anchors.left: parent.left
                                                            anchors.leftMargin: Tokens.spacingXs + 1
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.height - Tokens.spacingSm
                                                            height: width

                                                            Rectangle {
                                                                id: ring
                                                                anchors.centerIn: parent
                                                                width: parent.width
                                                                height: width
                                                                radius: width / 2
                                                                color: "transparent"
                                                                border.width: Tokens.borderWidth * 2
                                                                border.color: root.palette.primary
                                                                opacity: 0
                                                                ParallelAnimation {
                                                                    id: burst
                                                                    NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.3; duration: Motion.ripple; easing.type: Motion.travel }
                                                                    NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: Motion.ripple }
                                                                }
                                                            }
                                                            MorphShape {
                                                                anchors.fill: parent
                                                                shape: row.done ? "cookie9" : "circle"
                                                                spec: Motion.springSpatial
                                                                fillColor: row.done ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.14)
                                                            }
                                                            MaterialIcon {
                                                                anchors.centerIn: parent
                                                                name: "check"
                                                                fill: 1
                                                                font.pixelSize: Tokens.iconSm
                                                                color: root.palette.fgOnPrimary
                                                                opacity: row.done ? 1 : 0
                                                                scale: row.done ? 1 : 0.2
                                                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                                            }
                                                        }
                                                        onDoneChanged: if (row.done && Config.motionEnabled) burst.restart()

                                                        Row {
                                                            anchors.left: box.right
                                                            anchors.leftMargin: Tokens.spacingMd
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            spacing: Tokens.spacingSm
                                                            StyledText {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: Translation.tr("Set %1").arg(row.index + 1)
                                                                variant: "caption"
                                                                font.weight: Font.Medium
                                                                color: row.inkDim
                                                            }
                                                            // A record: better than anything you have done of it before. Pops in with the tick.
                                                            Rectangle {
                                                                id: prPill
                                                                readonly property bool shown: row.done && Workouts.isRecord(card.e.kind, card.e.name, row.modelData)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                implicitWidth: prText.implicitWidth + Tokens.spacingMd * 2
                                                                implicitHeight: prText.implicitHeight + Tokens.spacingXs
                                                                radius: height / 2
                                                                color: root.palette.primary
                                                                visible: scale > 0.02
                                                                scale: prPill.shown ? 1 : 0
                                                                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                                                StyledText {
                                                                    id: prText
                                                                    anchors.centerIn: parent
                                                                    text: "★ " + Translation.tr("PR")
                                                                    variant: "micro"
                                                                    font.weight: Font.Bold
                                                                    color: root.palette.fgOnPrimary
                                                                }
                                                            }
                                                        }

                                                        // The numbers, with − and + that come out under the pointer.
                                                        Row {
                                                            anchors.right: parent.right
                                                            anchors.rightMargin: Tokens.spacingMd
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            spacing: Tokens.spacingMd

                                                            Row {
                                                                id: repsTweak
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                spacing: 0
                                                                readonly property real step: row.timed ? 5 : 1
                                                                Item {
                                                                    width: Tokens.iconLg; height: Tokens.iconLg
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    opacity: rowHover.hovered ? 1 : 0
                                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                                    MaterialIcon { anchors.centerIn: parent; name: "remove"; font.pixelSize: Tokens.iconMd; color: row.inkDim }
                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: Workouts.tweakSet(card.e.id, row.index, row.timed
                                                                            ? { secs: row.modelData.secs - repsTweak.step } : { reps: row.modelData.reps - repsTweak.step })
                                                                        Accessible.role: Accessible.Button
                                                                        Accessible.name: Translation.tr("Fewer")
                                                                    }
                                                                }
                                                                StyledText {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: Tokens.spacingXl * 3
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    text: row.timed ? (row.modelData.secs >= 60 ? W.clock(row.modelData.secs * 1000) : row.modelData.secs + " s")
                                                                                    : row.modelData.reps + " " + Translation.tr("reps")
                                                                    variant: "label"
                                                                    font.weight: Font.DemiBold
                                                                    font.features: ({ tnum: 1 })
                                                                    color: row.ink
                                                                }
                                                                Item {
                                                                    width: Tokens.iconLg; height: Tokens.iconLg
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    opacity: rowHover.hovered ? 1 : 0
                                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                                    MaterialIcon { anchors.centerIn: parent; name: "add"; font.pixelSize: Tokens.iconMd; color: row.inkDim }
                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: Workouts.tweakSet(card.e.id, row.index, row.timed
                                                                            ? { secs: row.modelData.secs + repsTweak.step } : { reps: row.modelData.reps + repsTweak.step })
                                                                        Accessible.role: Accessible.Button
                                                                        Accessible.name: Translation.tr("More")
                                                                    }
                                                                }
                                                            }

                                                            Row {
                                                                id: loadTweak
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                spacing: 0
                                                                Item {
                                                                    width: Tokens.iconLg; height: Tokens.iconLg
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    opacity: rowHover.hovered ? 1 : 0
                                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                                    MaterialIcon { anchors.centerIn: parent; name: "remove"; font.pixelSize: Tokens.iconMd; color: row.inkDim }
                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: Workouts.tweakSet(card.e.id, row.index, { weight: row.modelData.weight - root.weightStep })
                                                                        Accessible.role: Accessible.Button
                                                                        Accessible.name: Translation.tr("Lighter")
                                                                    }
                                                                }
                                                                StyledText {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: Tokens.spacingXl * 3.5
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    text: row.modelData.weight <= 0 ? Translation.tr("Body") : W.weightText(row.modelData.weight) + " " + root.unit
                                                                    variant: "label"
                                                                    font.features: ({ tnum: 1 })
                                                                    color: row.inkDim
                                                                }
                                                                Item {
                                                                    width: Tokens.iconLg; height: Tokens.iconLg
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    opacity: rowHover.hovered ? 1 : 0
                                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                                    MaterialIcon { anchors.centerIn: parent; name: "add"; font.pixelSize: Tokens.iconMd; color: row.inkDim }
                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: Workouts.tweakSet(card.e.id, row.index, { weight: row.modelData.weight + root.weightStep })
                                                                        Accessible.role: Accessible.Button
                                                                        Accessible.name: Translation.tr("Heavier")
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
                            }
                        }
                        Scrollbar { flickable: listFlick }
                    }

                    // ── Rest: how long since the last set, filling to the goal ────
                    // It comes up from the foot of the list when a set is ticked and goes when the workout does.
                    SpringValue {
                        id: restK
                        target: Workouts.running && Workouts.restMs > 0 && root.view === "log" ? 1 : 0
                        spec: Motion.springSpatial
                        epsilon: 0.002
                    }
                    Rectangle {
                        id: restBar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Tokens.spacingMd
                        height: Tokens.iconXl + Tokens.spacingMd
                        radius: height / 2
                        color: restGo ? root.palette.primaryContainer : root.palette.plate
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                        readonly property real goalMs: Workouts.restGoal * 1000
                        readonly property bool restGo: Workouts.restMs >= restBar.goalMs
                        opacity: Math.min(1, restK.value * 1.5)
                        visible: restK.value > 0.01
                        transform: Translate { y: (1 - restK.value) * (restBar.height + Tokens.spacingMd) }
                        // It swells once as the goal is reached.
                        property bool armed: false
                        Component.onCompleted: restBar.armed = true
                        SequentialAnimation {
                            id: goalPulse
                            NumberAnimation { target: restBar; property: "scale"; to: 1.04; duration: Motion.respond; easing.type: Motion.travel }
                            NumberAnimation { target: restBar; property: "scale"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
                        }
                        onRestGoChanged: if (restBar.armed && restBar.restGo && Config.motionEnabled) goalPulse.restart()

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingLg
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingMd

                            MaterialIcon {
                                name: "timer"
                                fill: restBar.restGo ? 1 : 0
                                font.pixelSize: Tokens.iconLg
                                color: restBar.restGo ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                            }
                            StyledText {
                                text: restBar.restGo ? Translation.tr("Go") : W.clock(Workouts.restMs)
                                Layout.preferredWidth: Tokens.spacingXl * 3
                                variant: "label"
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                color: restBar.restGo ? root.palette.fgOnPrimaryContainer : root.palette.fg
                            }
                            // The rest so far against the goal, on the media page's squared slider. It only shows:
                            // the goal is set with the buttons beside it.
                            ThickSlider {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                                enabled: false
                                value: Math.min(1, Workouts.restMs / restBar.goalMs)
                                maximum: 1.0
                                accent: root.palette.primary
                                accessibleName: Translation.tr("Rest so far")
                            }
                            // The goal, to change in steps of 15 s.
                            Row {
                                spacing: 0
                                Item {
                                    width: Tokens.iconLg; height: Tokens.iconLg
                                    anchors.verticalCenter: parent.verticalCenter
                                    MaterialIcon { anchors.centerIn: parent; name: "remove"; font.pixelSize: Tokens.iconMd; color: root.palette.fgMuted }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Workouts.setRestGoal(Workouts.restGoal - 15)
                                        Accessible.role: Accessible.Button
                                        Accessible.name: Translation.tr("Shorter rest goal")
                                    }
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Tokens.spacingXl * 3
                                    horizontalAlignment: Text.AlignHCenter
                                    text: W.clock(Workouts.restGoal * 1000)
                                    variant: "caption"
                                    font.features: ({ tnum: 1 })
                                    color: root.palette.fgMuted
                                }
                                Item {
                                    width: Tokens.iconLg; height: Tokens.iconLg
                                    anchors.verticalCenter: parent.verticalCenter
                                    MaterialIcon { anchors.centerIn: parent; name: "add"; font.pixelSize: Tokens.iconMd; color: root.palette.fgMuted }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Workouts.setRestGoal(Workouts.restGoal + 15)
                                        Accessible.role: Accessible.Button
                                        Accessible.name: Translation.tr("Longer rest goal")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ──────────────────────── History ────────────────────────────────
            ColumnLayout {
                id: pageHist
                anchors.fill: parent
                spacing: Tokens.spacingMd
                opacity: root.view === "history" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transform: Translate { x: (1 - pageHist.opacity) * 16 }

                // Twelve weeks of days
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: heatRow.implicitHeight + Tokens.spacingLg * 2
                    order: 1
                    radius: Tokens.radiusXl

                    RowLayout {
                        id: heatRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingLg

                        ColumnLayout {
                            Layout.fillWidth: false
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingXs
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.weeksBack === 0 ? Translation.tr("Last 12 weeks")
                                        : Qt.formatDate(root.dayDate(root.heatGrid[0][0].key), "MMM yyyy") + " – "
                                          + Qt.formatDate(root.dayDate(root.heatGrid[11][6].key), "MMM yyyy")
                                    variant: "caption"
                                    font.weight: Font.DemiBold
                                    emphasis: "muted"
                                    elide: Text.ElideRight
                                }
                                CardTool {
                                    symbol: "chevron_left"
                                    name: Translation.tr("Earlier")
                                    onActivated: root.weeksBack += 12
                                    HoverTip { text: Translation.tr("Earlier") }
                                }
                                CardTool {
                                    symbol: "chevron_right"
                                    name: Translation.tr("Later")
                                    enabled: root.weeksBack > 0
                                    opacity: enabled ? 1 : 0.35
                                    onActivated: root.weeksBack = Math.max(0, root.weeksBack - 12)
                                    HoverTip { text: Translation.tr("Later") }
                                }
                            }

                            // One column a week, Monday at the top. The day under the pointer leans in;
                            // the picked one is a disc.
                            Row {
                                id: grid
                                spacing: Tokens.spacingXs
                                readonly property real cell: Tokens.iconSm + Tokens.spacingXs
                                Repeater {
                                    model: root.heatGrid
                                    delegate: Column {
                                        id: week
                                        required property var modelData
                                        spacing: Tokens.spacingXs
                                        Repeater {
                                            model: week.modelData
                                            delegate: Item {
                                                id: day
                                                required property var modelData
                                                readonly property bool picked: day.modelData.key === root.shownDay
                                                readonly property int n: day.modelData.count
                                                width: grid.cell
                                                height: grid.cell

                                                SpringValue {
                                                    id: lean
                                                    target: tap.pressed ? 0.85 : hover.hovered && !day.modelData.future ? 1.18 : 1
                                                    spec: Motion.springSpatialFast
                                                    epsilon: 0.001
                                                }
                                                Rectangle {
                                                    anchors.fill: parent
                                                    scale: lean.value
                                                    radius: day.picked ? width / 2 : Tokens.radiusXs + 1
                                                    Behavior on radius { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
                                                    color: day.modelData.future ? root.palette.alpha(root.palette.fg, 0.04)
                                                         : day.n === 0 ? root.palette.plate
                                                         : root.palette.alpha(root.palette.primary, day.n >= 3 ? 1 : day.n === 2 ? 0.75 : 0.5)
                                                    border.width: day.picked ? Tokens.borderWidth * 2 : 0
                                                    border.color: root.palette.fg
                                                }
                                                HoverHandler { id: hover; enabled: !day.modelData.future; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    id: tap
                                                    enabled: !day.modelData.future
                                                    onTapped: { root.pickedDay = day.modelData.key; root.armed = 0 }
                                                }
                                                HoverTip {
                                                    text: Qt.formatDate(new Date(day.modelData.ts), "ddd d MMM")
                                                          + (day.n > 0 ? " · " + (day.n === 1 ? Translation.tr("1 workout") : Translation.tr("%1 workouts").arg(day.n)) : "")
                                                }
                                                Accessible.role: Accessible.Button
                                                Accessible.name: Qt.formatDate(new Date(day.modelData.ts), "dddd d MMMM")
                                                Accessible.onPressAction: if (!day.modelData.future) root.pickedDay = day.modelData.key
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // The numbers.
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingSm
                            Repeater {
                                model: [
                                    { n: root.summary.week,   t: Translation.tr("this week") },
                                    { n: root.summary.streak, t: Translation.tr("day streak") },
                                    { n: root.summary.total,  t: Translation.tr("in all") }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: Tokens.spacingSm
                                    StyledText {
                                        text: String(parent.modelData.n)
                                        font.pixelSize: Tokens.fontTitle
                                        font.weight: Font.Bold
                                        font.features: ({ tnum: 1 })
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: parent.modelData.t
                                        variant: "caption"
                                        emphasis: "muted"
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // The picked day
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    order: 2
                    radius: Tokens.radiusXl

                    StyledText {
                        id: dayHead
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingLg
                        text: root.dayTitle(root.shownDay)
                        variant: "label"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingXl * 2
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.shownList.length === 0
                        text: Workouts.history.length === 0 ? Translation.tr("Finished workouts show up here, by day.")
                                                            : Translation.tr("Nothing logged that day.")
                        variant: "label"
                        emphasis: "muted"
                        wrapMode: Text.WordWrap
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: dayHead.bottom
                        anchors.bottom: parent.bottom
                        anchors.margins: Tokens.spacingSm
                        anchors.topMargin: Tokens.spacingXs
                        visible: root.shownList.length > 0

                        Flickable {
                            id: dayFlick
                            anchors.fill: parent
                            anchors.rightMargin: Tokens.spacingSm
                            contentWidth: width
                            contentHeight: dayCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: dayCol
                                width: dayFlick.width
                                spacing: Tokens.spacingXs

                                Repeater {
                                    model: ScriptModel { objectProp: "id"; values: root.shownList }
                                    delegate: Rectangle {
                                        id: wk
                                        required property var modelData
                                        required property int index
                                        readonly property var w: wk.modelData
                                        readonly property var st: W.stats(wk.w)
                                        width: dayCol.width
                                        height: wkCol.implicitHeight + Tokens.spacingMd * 2
                                        radius: Tokens.radiusCard
                                        color: root.palette.plate
                                        clip: true

                                        PopIn { id: wpop; active: true; index: wk.index }
                                        opacity: wpop.opacity
                                        scale: wpop.scale

                                        HoverHandler { id: wkHover }

                                        ColumnLayout {
                                            id: wkCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Tokens.spacingMd
                                            spacing: Tokens.spacingXs

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: false
                                                spacing: Tokens.spacingSm
                                                StyledText {
                                                    text: Qt.formatTime(new Date(wk.w.start), "HH:mm")
                                                    variant: "label"
                                                    font.weight: Font.Bold
                                                    font.features: ({ tnum: 1 })
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: W.lasted(W.elapsed(wk.w, 0)) + " · " + root.setsText(wk.st.sets)
                                                          + (wk.st.volume > 0 ? " · " + root.volumeText(wk.st.volume) : "")
                                                    variant: "caption"
                                                    emphasis: "muted"
                                                    elide: Text.ElideRight
                                                }
                                                CardTool {
                                                    opacity: wkHover.hovered ? 1 : 0
                                                    enabled: wkHover.hovered
                                                    symbol: "delete"
                                                    name: Translation.tr("Delete this workout")
                                                    onActivated: root.armed = wk.w.id
                                                    HoverTip { text: Translation.tr("Delete this workout") }
                                                }
                                            }
                                            Repeater {
                                                model: wk.w.entries
                                                delegate: RowLayout {
                                                    id: ex
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: false
                                                    spacing: Tokens.spacingSm
                                                    StyledText {
                                                        Layout.preferredWidth: Math.round(wkCol.width * 0.38)
                                                        text: ex.modelData.name
                                                        variant: "caption"
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: root.entryLine(ex.modelData)
                                                        variant: "caption"
                                                        emphasis: "muted"
                                                        font.features: ({ tnum: 1 })
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // Delete: Keep or Delete, on a layer over the card.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: wk.radius
                                            color: root.palette.primaryContainer
                                            opacity: root.armed === wk.w.id ? 1 : 0
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
                                            MouseArea { anchors.fill: parent; enabled: root.armed === wk.w.id }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: Tokens.spacingMd
                                                spacing: Tokens.spacingSm
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: Translation.tr("Delete this workout?")
                                                    variant: "label"
                                                    font.weight: Font.DemiBold
                                                    color: root.palette.fgOnPrimaryContainer
                                                    elide: Text.ElideRight
                                                }
                                                ChipButton {
                                                    tonal: true
                                                    tint: root.palette.fgOnPrimaryContainer
                                                    label: Translation.tr("Keep")
                                                    onActivated: root.armed = 0
                                                }
                                                ChipButton {
                                                    solid: true
                                                    tint: root.palette.danger
                                                    symbol: "delete"
                                                    label: Translation.tr("Delete")
                                                    onActivated: { root.armed = 0; Workouts.removeWorkout(wk.w.id) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Scrollbar { flickable: dayFlick }
                    }
                }
            }
        }
    }
}
