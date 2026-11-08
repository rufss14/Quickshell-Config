import QtQuick
import Quickshell
import "../config"

// ── TimerDial ─────────────────────────────────────────────────────────────────
// The timer panel's face: the time left as a COOKIE (Scallop, the shell's shape) that shrinks as it
// goes, with the digits rolling inside it. Not a progress bar in a costume — everything on it says what
// the clock is doing:
//
//   the cookie     is the time left (`value`, 0..1): full when it starts, a small coin at the end. It
//                  turns slowly while it runs and breathes (a scale, not a re-cut of the petals — that
//                  would rebuild the outline every frame), stops dead when paused, and goes the warning
//                  colour for the last ten seconds, danger when time is up.
//   the rim        a faint scalloped track, and a small star that ORBITS it once a minute (`orbit`, in
//                  turns, unwrapped — it never swings back through the dial at a minute's end).
//   the pulse      a ring that leaves the rim: once a minute, every second in the last ten (`ping()`).
//   the digits     RollText: each digit rolls on its own, so 24:00 → 23:59 moves three of them.
//   the burst      time's up: fourteen small cookies fly out and fade (`burst()`), and the cookie shakes
//                  until it is dismissed.
//   the dial       when `interactive` (a timer that is not running) you TURN it: press the cookie and drag
//                  round — the angle is the length, clockwise from 12 o'clock — with a small bump at each
//                  whole detent. A tap that does not move is `tapped` (start / pause).
//
// It draws and reports; the caller (TimerPanel) owns the numbers. Looping motion (the turn, the breath,
// the orbit) is decoration, so it runs only while `running` and only with animations on.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The digits ("24:59"), a smaller tail ("42" — the stopwatch's hundredths) and a line under them.
    property string text:    ""
    property string fine:    ""
    property string caption: ""

    // The time left, as a fraction of the cookie; and how far round the rim the star is, in turns.
    property real value: 1
    property real orbit: 0

    property color accent: Colors.of(QsWindow.window).primary
    property bool running: false
    property bool paused:  false
    property bool done:    false
    // The last ten seconds: warm, and the digits bump on every second.
    property bool urgent:  false
    property bool interactive: false
    // Whether it is on show. A face that is slid out of sight keeps its numbers but stops its looping motion.
    property bool live: true
    property int  points: 9
    // Detents per full turn when dragging (a timer dial: sixty minutes).
    property int  detents: 60

    signal tapped()
    signal turned(real fraction)

    function ping()  { pingAnim.restart() }
    function burst() { burstAnim.restart() }
    // A small bump (the dial's detent, and the last seconds' tick).
    function bump()  { if (root.animated) kickAnim.restart() }

    implicitWidth:  Tokens.sideCardUnit * 4
    implicitHeight: Tokens.sideCardUnit * 4
    readonly property real size: Math.min(root.width, root.height)
    readonly property bool animated: Config.motionEnabled

    // ── Colours: one `tone`, and every layer is a tint of it ──────────────────
    property color tone: root.done ? Colors.of(QsWindow.window).danger
                       : root.urgent ? Colors.of(QsWindow.window).warning
                       : root.paused ? Colors.of(QsWindow.window).fgDim
                       :               root.accent
    Behavior on tone { ColorAnimation { duration: Motion.standard } }
    function _a(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── The value, eased; the detent bump ─────────────────────────────────────
    // While you are TURNING it the cookie follows a gentler curve than the angle (a five-minute timer on an
    // hour's dial would be a coin); once it runs, it is the plain fraction left — and grows to it.
    property real shown: root.interactive ? Math.sqrt(Math.max(0, root.value)) : root.value
    Behavior on shown {
        enabled: root.animated && !pad.turning
        NumberAnimation { duration: Motion.glide; easing.type: Motion.glideCurve }
    }
    property real kick: 0
    SequentialAnimation {
        id: kickAnim
        NumberAnimation { target: root; property: "kick"; to: 1; duration: Motion.respond; easing.type: Motion.respondCurve }
        NumberAnimation { target: root; property: "kick"; to: 0; duration: Motion.standard; easing.type: Motion.travel }
    }

    // ── The cookie's own motion ───────────────────────────────────────────────
    property real spin: 0
    NumberAnimation on spin {
        from: 0; to: 360
        duration: 48000
        loops: Animation.Infinite
        running: root.running && root.animated && root.live
    }
    property real breath: 0
    SequentialAnimation on breath {
        loops: Animation.Infinite
        running: root.running && root.animated && root.live
        NumberAnimation { to: 1; duration: Motion.pulse * 3; easing.type: Motion.ambient }
        NumberAnimation { to: 0; duration: Motion.pulse * 3; easing.type: Motion.ambient }
    }
    // Time's up: it shakes (a pulse is a channel — it must keep saying "done" with animations off).
    property real shake: 0
    SequentialAnimation on shake {
        loops: Animation.Infinite
        running: root.done && root.live
        alwaysRunToEnd: true
        NumberAnimation { to: 1;  duration: Motion.pulse / 4; easing.type: Motion.ambient }
        NumberAnimation { to: -1; duration: Motion.pulse / 2; easing.type: Motion.ambient }
        NumberAnimation { to: 0;  duration: Motion.pulse / 4; easing.type: Motion.ambient }
        PauseAnimation  { duration: Motion.pulse * 2 }
    }

    // Whether the pointer is on it (the petals lean in), and a press (it dips).
    readonly property bool hot: pad.containsMouse

    // ══ The dial ══════════════════════════════════════════════════════════════
    Item {
        id: dial
        anchors.centerIn: parent
        width: root.size
        height: root.size
        // A press dips it, a detent bumps it, and a hover leans it in: springs, so it settles like the shell's
        // other round things (CookieButton).
        property real lean: pad.pressed ? 0.965 : (root.hot && root.interactive ? 1.025 : 1.0)
        Behavior on lean { SpringAnimation { spring: 6; damping: 0.34; epsilon: 0.002 } }
        scale: dial.lean * (1 + 0.03 * root.kick)
        rotation: root.shake * 5

        // The halo: a larger, fainter cookie turning the other way — only a hint of depth.
        Scallop {
            anchors.centerIn: parent
            width: root.size * 1.0
            height: width
            points: root.points + 3
            petalDepth: 0.05
            fillColor: root._a(root.tone, 0.06)
            rotation: -root.spin * 0.6
            opacity: root.running || root.done ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: Motion.slow } }
        }

        // The rim: where the cookie started, and the star's track.
        Scallop {
            id: rim
            anchors.centerIn: parent
            width: root.size * 0.9
            height: width
            points: root.points
            petalDepth: 0.13 + (root.hot && root.interactive ? 0.03 : 0)
            strokeColor: root._a(root.tone, 0.22)
            strokeWidth: Tokens.borderWidth * 1.5
        }

        // The pulse: a ring that leaves the rim.
        Scallop {
            id: pingRing
            anchors.centerIn: parent
            width: rim.width
            height: width
            points: root.points
            petalDepth: 0.13
            strokeColor: root._a(root.tone, 0.7)
            strokeWidth: Tokens.borderWidth * 2
            property real t: 0
            visible: t > 0 && t < 1
            opacity: 0.7 * (1 - t)
            scale: 1 + 0.32 * t
        }
        NumberAnimation {
            id: pingAnim
            target: pingRing; property: "t"; from: 0.001; to: 1
            duration: Motion.slow * 2; easing.type: Motion.enter
        }

        // The cookie: the time left. Its size is the fraction (never quite nothing, so a last second is still a
        // shape), its turn and its breath are the clock running.
        Item {
            id: body
            anchors.centerIn: parent
            width: root.size * 0.9
            height: width
            scale: (0.2 + 0.8 * Math.max(0, Math.min(1, root.shown))) * (1 + 0.022 * root.breath)
            rotation: root.spin
            Scallop {
                anchors.fill: parent
                points: root.points
                petalDepth: 0.13 + (root.hot && root.interactive ? 0.04 : 0)
                fillColor: root._a(root.tone, root.done ? 0.34 : 0.24)
                strokeColor: root._a(root.tone, 0.85)
                strokeWidth: Tokens.borderWidth * 2
            }
            // A second layer, smaller and brighter: the cookie has a centre.
            Scallop {
                anchors.centerIn: parent
                width: parent.width * 0.74
                height: width
                points: root.points
                petalDepth: 0.1
                fillColor: root._a(root.tone, 0.16)
                rotation: -root.spin * 1.5
            }
        }

        // The star: once round the rim a minute. `orbit` is in unwrapped turns, so it eases forward through the
        // top of the dial instead of sweeping back.
        Item {
            id: star
            anchors.fill: parent
            rotation: root.orbit * 360
            visible: root.running || root.paused
            opacity: root.paused ? 0.5 : 1
            Behavior on rotation { enabled: root.animated; NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            Scallop {
                x: parent.width / 2 - width / 2
                y: parent.height * 0.05 - height / 2
                width: Tokens.spacingLg
                height: width
                points: 5
                petalDepth: 0.2
                fillColor: root.tone
            }
            Rectangle {
                x: parent.width / 2 - width / 2
                y: parent.height * 0.05 - height / 2
                width: Tokens.spacingLg * 2.2
                height: width
                radius: width / 2
                color: root._a(root.tone, 0.16)
            }
        }

        // ── The digits ────────────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingXs / 2

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                // The digits roll; in the last ten seconds each second bumps them.
                RollText {
                    id: digits
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.text
                    family: Tokens.fontMono
                    // "24:59" at a fifth of the cookie; with hours ("1:05:00") or hundredths, smaller.
                    pixelSize: Math.round(root.size * (root.text.length > 5 ? 0.135 : root.fine !== "" ? 0.17 : 0.2))
                    weight: Font.DemiBold
                    color: root.done ? Colors.of(QsWindow.window).danger
                         : root.urgent ? Colors.of(QsWindow.window).warning
                         : root.paused ? Colors.of(QsWindow.window).fgDim
                         :               Colors.of(QsWindow.window).fg
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    scale: 1 + (root.urgent ? 0.07 * root.kick : 0)
                }
                StyledText {
                    visible: root.fine !== ""
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.round(digits.height * 0.16)
                    text: "." + root.fine
                    font.family: Tokens.fontMono
                    font.pixelSize: Math.round(root.size * 0.1)
                    emphasis: "dim"
                }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.caption
                variant: "caption"
                emphasis: "dim"
                opacity: text !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            }
        }

        // ── The burst: time is up ─────────────────────────────────────────────
        Repeater {
            model: 14
            delegate: Scallop {
                id: bit
                required property int index
                // Each flies its own way, a little different in size and reach.
                readonly property real ang: (bit.index * 360 / 14 + (bit.index % 3) * 9) * Math.PI / 180
                readonly property real reach: root.size * (0.5 + 0.2 * ((bit.index * 7) % 5) / 4)
                readonly property real t: root.burstT
                width: root.size * (0.06 + 0.05 * ((bit.index * 3) % 4) / 3) * (1 - 0.45 * bit.t)
                height: width
                points: 5 + bit.index % 4
                petalDepth: 0.22
                x: dial.width / 2 + Math.cos(bit.ang) * (root.size * 0.3 + bit.reach * bit.t) - width / 2
                y: dial.height / 2 + Math.sin(bit.ang) * (root.size * 0.3 + bit.reach * bit.t) - height / 2
                rotation: bit.index * 40 + bit.t * 200
                opacity: bit.t > 0 && bit.t < 1 ? 1 - bit.t : 0
                visible: opacity > 0.01
                fillColor: bit.index % 3 === 0 ? Colors.of(QsWindow.window).danger
                         : bit.index % 3 === 1 ? Colors.of(QsWindow.window).warning
                         :                       Colors.of(QsWindow.window).focus
            }
        }
    }

    property real burstT: 0
    NumberAnimation {
        id: burstAnim
        target: root; property: "burstT"; from: 0.001; to: 1
        duration: Motion.spatialSlow * 2; easing.type: Motion.expressive
    }
    onDoneChanged: if (root.done) root.burst()
    onUrgentChanged: if (root.urgent) root.bump()

    // ── Touch: tap, or turn ───────────────────────────────────────────────────
    MouseArea {
        id: pad
        anchors.centerIn: parent
        width: root.size * 0.92
        height: width
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property bool turning: false
        property real startX: 0
        property real startY: 0
        property real lastF: 0
        property int lastDetent: -1

        // The angle, clockwise from 12 o'clock, as 0..1.
        function frac(mx, my) {
            const dx = mx - pad.width / 2, dy = my - pad.height / 2
            let a = Math.atan2(dx, -dy) / (2 * Math.PI)
            if (a < 0) a += 1
            return a
        }
        onPressed: function (m) {
            pad.startX = m.x; pad.startY = m.y
            pad.turning = false
            pad.lastF = root.value
            pad.lastDetent = Math.round(root.value * root.detents)
        }
        onPositionChanged: function (m) {
            if (!pressed || !root.interactive) return
            if (!pad.turning && Math.hypot(m.x - pad.startX, m.y - pad.startY) > Tokens.spacingMd) pad.turning = true
            if (!pad.turning) return
            let f = pad.frac(m.x, m.y)
            // The dial does not wrap: dragging past 12 o'clock stops at the end it came from.
            if (Math.abs(f - pad.lastF) > 0.5) f = pad.lastF > 0.5 ? 1 : 0
            pad.lastF = f
            const d = Math.round(f * root.detents)
            if (d !== pad.lastDetent) { pad.lastDetent = d; root.bump() }
            root.turned(f)
        }
        onReleased: { if (!pad.turning) root.tapped(); pad.turning = false }
        onCanceled: pad.turning = false
    }
}
