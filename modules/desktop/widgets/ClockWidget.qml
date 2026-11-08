pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ClockWidget ───────────────────────────────────────────────────────────────
// Analog at small, digital at medium — the way the macOS and iOS clock widgets do it,
// and for the reason they do it: a 168px square is the wrong shape for a wide digital
// time. The first version rendered "13:15:09" at 38px into a 140px content box and it
// visibly overflowed the tile. A dial has no such problem — it is square, it fills a
// square, and it reads at a glance.
//
// The tick is gated on `active`, which the layer drives from whether the widget is on
// screen at all. A clock nobody can see must not be waking the process once a second.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    // Set by the host from the widget's stored accent role. Defaults to the palette's
    // primary so a widget rendered outside the layer (a settings preview) still looks
    // right without the caller having to know about accents.
    property color accent: Colors.of(QsWindow.window).primary

    readonly property bool seconds: root.opts.seconds === true
    readonly property bool hour24:  root.opts.hour24 !== false

    // ── Which face ────────────────────────────────────────────────────────────
    // Size picks the DEFAULT — a dial for the square small tile, digits for the wide
    // medium one — and a tap overrides it. Stored per widget, so the choice survives a
    // reload; unset means "whatever suits the size", which is what a freshly placed
    // clock should do rather than committing you to a face you never chose.
    readonly property bool analog:
        root.opts.face === undefined ? root.size === "small"
                                     : root.opts.face === "analog"

    function tileTap() {
        if (root.widgetId < 0) return       // a preview must not write to the store
        DesktopWidgets.setOpt(root.widgetId, "face", root.analog ? "digital" : "analog")
    }

    // The shared wall clock, not a Timer of our own — see services/Clock.qml for why
    // every clock in the shell has to come off one tick. The old local timer also woke
    // at 15s to show a value that changes every 60, which the shared one doesn't need to.
    readonly property date now: Clock.now

    // A face showing seconds needs second resolution; one showing only minutes does not,
    // and the analog face always sweeps seconds. This is now a claim on the shared
    // timer's rate rather than a private interval — the tick moves up for as long as any
    // clock on screen wants it and drops back when the last one goes away.
    //
    // Every face shows the seconds now (2026-10-30, asked for): the analog face as a
    // seconds HAND, the digital faces as a bar that fills across the minute. So a live
    // clock always holds the second tick; one off screen still holds nothing.
    readonly property bool _wantsSeconds: root.active
    property bool _holdingSeconds: false

    function _syncSecondsHold() {
        const want = root._wantsSeconds
        if (want === root._holdingSeconds) return
        root._holdingSeconds = want
        if (want) Clock.acquireSeconds()
        else      Clock.releaseSeconds()
    }

    on_WantsSecondsChanged: root._syncSecondsHold()
    Component.onCompleted: root._syncSecondsHold()
    // Releasing on destruction is what stops a removed widget from pinning the whole
    // shell at one wakeup a second for the rest of the session.
    Component.onDestruction: if (root._holdingSeconds) Clock.releaseSeconds()

    // ══ ANALOG — small ════════════════════════════════════════════════════════
    // (And the small DIGITAL face, which shares the dial's shape: a tap morphs one into the
    // other — the face's outline flows from the hour cookie to a squircle as the hands
    // fade and the digits rise. Material 3 Expressive's shape morph, with a meaning.)
    Item {
        id: dial
        anchors.centerIn: parent
        visible: root.analog || root.size === "small"
        width:  Math.min(parent.width, parent.height)
        height: width

        readonly property real r: width / 2
        readonly property int  h: root.now.getHours()
        readonly property int  m: root.now.getMinutes()
        readonly property int  s: root.now.getSeconds()

        // ── The second hand's angle, kept running ─────────────────────────────
        // `s * 6` wraps from 354 to 0 every minute, and a Behavior on it would spin the
        // hand backwards through the whole dial at that moment. So the hand follows an
        // angle that only ever grows: each tick adds the forward distance to the new
        // second, which also survives the clock jumping (a resume, a DST change) without
        // a lap. Assigned, never bound — a binding would be the wrapping value again.
        property real secAngle: 0
        Component.onCompleted: dial.secAngle = dial.s * 6
        onSChanged: dial.secAngle += ((dial.s * 6 - dial.secAngle % 360) + 360) % 360

        // 1 = the analog face, 0 = the digits; sprung, so the swap is one gesture.
        SpringValue { id: faceMix; target: root.analog ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }

        // Face: Material 3 Expressive's cookie, twelve petals — one per hour, a tip at
        // twelve (shapes.js), so the petals ARE the hour marks and no dots are needed. On
        // `primaryContainer`: the tile's one tonal hero. Not turned as it morphs (`turns`),
        // because its orientation is the time.
        MorphShape {
            anchors.fill: parent
            shape: root.analog ? "cookie12" : "squircle"
            turns: false
            spec: Motion.springSpatialFast
            fillColor: Colors.of(QsWindow.window).primaryContainer
        }

        // ── Hands ─────────────────────────────────────────────────────────────
        // Hours and minutes move CONTINUOUSLY, not in steps: a real hour hand is most
        // of the way to 4 at 3:55, and stepping it leaves the face reading wrong for
        // most of every hour. Material's expressive clock: two thick rounded bars in the
        // container's two inks — the hour in the accent, the minute in the container's own
        // text colour — and no cap: each bar's round end sits ON the pivot (tail = half its
        // width), so they meet at the centre as one joint.
        Item {
            anchors.fill: parent
            opacity: faceMix.value
            scale: 0.85 + 0.15 * faceMix.value
            visible: opacity > 0.01

            Hand { length: dial.r * 0.42; thickness: dial.r * 0.16; tail: thickness / 2
                   colour: Colors.of(QsWindow.window).primary
                   angle: (dial.h % 12) * 30 + dial.m * 0.5 }
            Hand { length: dial.r * 0.64; thickness: dial.r * 0.10; tail: thickness / 2
                   colour: Colors.of(QsWindow.window).fgOnPrimaryContainer
                   angle: dial.m * 6 + dial.s * 0.1 }

            // ── The seconds: a hand ───────────────────────────────────────────
            // A slim bar in the accent from a short tail through the pivot to just inside
            // the petals, over the other two, with a cap on the joint. It TICKS — springs
            // onto each second (the fast spatial spring: a hair past the mark, then back)
            // and rests in between, so the desktop isn't redrawn every frame all day.
            SpringValue { id: secTurn; target: dial.secAngle; spec: Motion.springSpatialFast; epsilon: 0.05 }
            Hand {
                length: dial.r * 0.8
                thickness: Math.max(2, dial.r * 0.045)
                tail: dial.r * 0.18
                colour: Colors.of(QsWindow.window).primary
                angle: secTurn.value
            }
            Rectangle {
                anchors.centerIn: parent
                width: dial.r * 0.13
                height: width
                radius: width / 2
                color: Colors.of(QsWindow.window).primary
                antialiasing: true
            }
        }

        // ── The small digital face ────────────────────────────────────────────
        // Hours over minutes, stacked, in the depth clock's block face (the shell's big
        // clock is one type): the hour heavy, the minute light — the two weights carry the
        // split the analog face gives to two colours.
        Column {
            anchors.centerIn: parent
            spacing: -dial.r * 0.12
            opacity: 1 - faceMix.value
            scale: 0.85 + 0.15 * (1 - faceMix.value)
            visible: root.size === "small" && opacity > 0.01

            RollText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, root.hour24 ? "HH" : "h")
                family: Tokens.fontBlock
                pixelSize: Math.round(dial.r * 0.78)
                weight: Font.ExtraBold
                color: Colors.of(QsWindow.window).fgOnPrimaryContainer
            }
            RollText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, "mm")
                family: Tokens.fontBlock
                pixelSize: Math.round(dial.r * 0.78)
                weight: Font.Medium
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.78)
            }
            SecondsBar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: dial.r * 0.9
                ink: Colors.of(QsWindow.window).fgOnPrimaryContainer
            }
        }
    }

    // ══ DIGITAL — medium ══════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        visible: !root.analog && root.size !== "small"
        spacing: 0

        Item { Layout.fillHeight: true }

        // The digits roll as they change — 13:15 → 13:16 moves one cell and leaves
        // "13:1" standing. Mono so a cell never changes width under its neighbours.
        // RollText has no fit-to-width, so the size is the one that fits the widest
        // string (eight characters with seconds) in a medium tile's content box.
        RollText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now,
                  (root.hour24 ? "HH:mm" : "h:mm") + (root.seconds ? ":ss" : ""))
            family: Tokens.fontMono
            pixelSize: root.seconds ? Tokens.fontNumeralMd : Tokens.fontNumeralLg
            weight: Font.DemiBold
            color: Colors.of(QsWindow.window).fg
        }

        SecondsBar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width * 0.5
            Layout.topMargin: Tokens.spacingXs
            ink: Colors.of(QsWindow.window).primary
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingSm
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                  + (root.hour24 ? "" : "  " + Qt.formatDateTime(root.now, "AP"))
            variant: "caption"
            emphasis: "muted"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }

    // ── The seconds, as a bar ─────────────────────────────────────────────────
    // A track that fills across the minute, one step a second on the fast spatial spring.
    // At the top of the minute it does not sweep back through the whole bar: it empties
    // at once and starts again (a jump, not a spring).
    component SecondsBar: Item {
        id: bar
        property color ink: Colors.of(QsWindow.window).fg
        readonly property int sec: root.now.getSeconds()
        implicitHeight: Tokens.spacingXs + 2
        onSecChanged: {
            if (bar.sec === 0) fill.jump(0)
            fill.target = bar.sec / 59
        }
        Component.onCompleted: { fill.target = bar.sec / 59; fill.jump(bar.sec / 59) }
        SpringValue { id: fill; spec: Motion.springSpatialFast; epsilon: 0.0005 }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.of(QsWindow.window).alpha(bar.ink, 0.22)
        }
        Rectangle {
            width: Math.max(bar.height, bar.width * Math.max(0, Math.min(1, fill.value)))
            height: bar.height
            radius: height / 2
            color: bar.ink
            opacity: fill.value > 0.001 ? 1 : 0
        }
    }

    // A clock hand: a rounded bar pinned at the dial's centre and rotated about it.
    // `tail` is how far it reaches past the pivot — half its width puts its round end
    // centred on the pivot.
    component Hand: Rectangle {
        id: hand
        property real length: 10
        property real thickness: 2
        property real angle: 0
        property real tail: 0
        property color colour: Colors.of(QsWindow.window).fg

        width:  hand.thickness
        height: hand.length + hand.tail
        radius: hand.thickness / 2
        color:  hand.colour
        antialiasing: true

        x: dial.r - hand.thickness / 2
        y: dial.r - hand.length

        transform: Rotation {
            origin.x: hand.thickness / 2
            origin.y: hand.length
            angle: hand.angle
        }
    }
}
