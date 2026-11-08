pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clockfmt.js" as ClockFmt
// ── SideClips ─────────────────────────────────────────────────────────────────
// Clips as a sidebar button: a glance at rest — a camera (`videocam`; it was a record dot),
// with a thin arc round it that fills as the replay buffer does, full and in the accent
// while recording — and the controls in a panel beside it (ClipsPanel, in SidePanelDock). It replaced
// the clips pill's three cells and hover card.
//
//   click     the Clips panel, beside this button (again: shut it)
//   middle    clip it — the buffer's last stretch (Clips.saveClip; with nothing to
//             clip it says why, as Alt+F10 does)
//   HOLD      what to capture: after a dwell a charge sweeps round the ring while it
//             coils and glows; at full charge two ripples and an elastic pop, and the
//             target picker opens beside the button (ClipsTargetPanel)
//   right     Settings › Sidebar › Clips
//
// ── The peek ──────────────────────────────────────────────────────────────────
// A save pulses the ring on every screen, and — on the focused monitor, when the
// slot is free — opens ClipsPeek beside it for a moment (Config.clipsPeek).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null
    property var monitor: null
    // On screen: the sidebar is out and this isn't sunk under a panel.
    property bool shown: true

    readonly property string blocked: Clips.blocker()
    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel !== "" && UiState.sidePanelFrom === "clips" && root.ownsPanel
    readonly property bool focusedHere:
        Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.name === (root.monitor?.name ?? "")

    // Hold-to-pick timings — interaction timings, not Motion durations (a hold with
    // motion off still has to be a hold). The dwell keeps a click from flickering a
    // charge; the whole press, dwell included, is `holdMs`.
    readonly property int holdDwell: 120
    readonly property int holdMs: 520

    // ── A clock only while something is counting and on screen ────────────────
    readonly property bool counting: root.shown && Clips.busy
    property bool _clockHeld: false
    onCountingChanged: {
        if (root.counting === root._clockHeld) return
        if (root.counting) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._clockHeld = root.counting
    }
    Component.onCompleted: if (root.counting) { Clock.acquireSeconds(); root._clockHeld = true }
    Component.onDestruction: if (root._clockHeld) Clock.releaseSeconds()

    readonly property real nowMs: Clock.now.getTime()
    readonly property real bufferFill: !Clips.buffering || Clips.since <= 0 ? 0
        : Math.max(0, Math.min(1, (root.nowMs - Clips.since) / 1000 / Clips.bufferSeconds))
    readonly property real heldSecs: Clips.buffering
        ? Math.min(Clips.bufferSeconds, Math.max(0, (root.nowMs - Clips.since) / 1000)) : 0
    readonly property real recordSecs: Clips.recording && Clips.recordSince > 0
        ? Math.max(0, (root.nowMs - Clips.recordSince) / 1000) : 0

    // ── A save: a pulse everywhere, a peek here ───────────────────────────────
    property real pulse: 0
    Behavior on pulse { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
    Timer { id: pulseTimer; interval: Motion.respond; onTriggered: root.pulse = 0 }
    Connections {
        target: Clips
        function onSaved() {
            root.pulse = 1
            pulseTimer.restart()
            if (Config.clipsPeek && root.focusedHere && root.shown && UiState.sidePanel === "")
                UiState.openSidePanel("clipsPeek", "clips", root.screen)
        }
    }

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // ══ Hold to pick ══════════════════════════════════════════════════════════
    property real charge: 0
    property real pop: 0
    property bool fired: false
    readonly property bool usable: root.blocked === ""
    readonly property color holdTint: Colors.of(QsWindow.window).primary

    function fire() {
        root.fired = true
        drainAnim.restart()
        popAnim.restart()
        ripple.play()
        UiState.openSidePanel("clipsTarget", "clips", root.screen)
    }
    function letGo() {
        dwell.stop()
        chargeAnim.stop()
        if (!root.fired) drainAnim.restart()
    }
    Timer {
        id: dwell
        interval: root.holdDwell
        onTriggered: { drainAnim.stop(); chargeAnim.restart() }
    }
    NumberAnimation {
        id: chargeAnim
        target: root; property: "charge"; to: 1
        duration: root.holdMs - root.holdDwell
        easing.type: Motion.ambient
        onFinished: if (root.charge >= 1 && mouse.pressed) root.fire()
    }
    NumberAnimation {
        id: drainAnim
        target: root; property: "charge"; to: 0
        duration: Motion.standard
        easing.type: Motion.travel
    }
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: root; property: "pop"; to: 1
                          duration: Motion.respond; easing.type: Motion.respondCurve }
        NumberAnimation { target: root; property: "pop"; to: 0
                          duration: Motion.slow; easing.type: Easing.OutElastic
                          easing.amplitude: 1.2; easing.period: 0.45 }
    }

    // The cell, less a hair: the arc's outer edge stands where an app icon's artwork
    // would end. (It was icon + spacingMd, sized for the old roomy cell; in the
    // tightened one that's wider than the cell.)
    readonly property real ringSize: Config.sidebarCell - Tokens.spacingXs * 2
    // The glyph is every other cell's size (Config.sidebarGlyphPx), the arc a hairline
    // round it (2026-10-17: a ring with a half-size glyph in it was a different
    // language from the rest of the edge).
    readonly property int innerGlyphPx: Config.sidebarGlyphPx

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: mouse.containsMouse && root.charge < 0.01
        active: root.open
    }

    // ── The glow it charges up ────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        visible: root.charge > 0.01
        width: root.ringSize
        height: width
        radius: width / 2
        color: Colors.of(QsWindow.window).alpha(root.holdTint, 0.28 * root.charge)
        scale: 0.7 + 0.55 * root.charge
    }

    // ── The ripples it fires ──────────────────────────────────────────────────
    Item {
        id: ripple
        anchors.centerIn: parent
        width: root.ringSize
        height: width
        function play() { for (let i = 0; i < waves.count; i++) waves.itemAt(i).play() }
        Repeater {
            id: waves
            model: 2
            delegate: Rectangle {
                id: wave
                required property int index
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(Tokens.borderWidth, Tokens.spacingXs - wave.index)
                border.color: root.holdTint
                opacity: 0
                function play() { waveAnim.restart() }
                SequentialAnimation {
                    id: waveAnim
                    PauseAnimation { duration: wave.index * Motion.respond }
                    ParallelAnimation {
                        NumberAnimation { target: wave; property: "scale"; from: 1; to: 1.35
                                          duration: Motion.slow; easing.type: Motion.travel }
                        NumberAnimation { target: wave; property: "opacity"; from: 0.9; to: 0
                                          duration: Motion.slow; easing.type: Motion.respondCurve }
                    }
                }
            }
        }
    }

    // ── The ring around its glyph ─────────────────────────────────────────────
    RadialGauge {
        id: gauge
        anchors.centerIn: parent
        width:  root.ringSize
        height: gauge.width
        thickness: Tokens.spacingXs
        // Material 3 Expressive's wavy indicator, as the desktop tiles wear it.
        wavy: true
        accent: Colors.of(QsWindow.window).primary
        value: Clips.recording ? 1 : root.bufferFill
        sampleInterval: 1000
        glide: true
        // Clipping off is an empty ring at full strength, as idle as any other cell
        // (dimmed, it read as broken beside them); only "unavailable" dims.
        opacity: !root.usable ? 0.4 : 1

        // The charge coils it, the fire springs it back past its size, a save pulses it.
        scale: (1 - 0.14 * root.charge) * (1 + 0.22 * root.pop) * (1 + 0.25 * root.pulse)

        // Hovering while it counts swaps the glyph for the time. (The time AT REST was
        // tried, 2026-10-02, beside a tower of numbered rings; both read as "weird"
        // next to the top bar.)
        readonly property bool number: Clips.busy && mouse.containsMouse && root.charge < 0.01

        // The camera, where the record dot was (2026-10-31, the user's ask; the dot was their
        // 2026-10-17 one, and the catalogue already showed this symbol). The dot's states carry
        // over: filled while the buffer is running or recording, an outline when clipping is
        // off. It breathes while recording — Motion.pulse, not `slow`: it's a channel
        // ("recording"), and it has to keep saying so with animations off (Motion.qml) — and
        // sits at half a pulse dimmer while paused.
        MaterialIcon {
            id: dot
            anchors.centerIn: parent
            name: "videocam"
            readonly property bool solid: Clips.recording || Clips.clipping
            fill:   dot.solid ? 1 : 0
            weight: Config.sidebarGlyphWeight
            font.pixelSize: root.innerGlyphPx
            color: Clips.recording || mouse.containsMouse || root.open
                ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).stateIdleFg
            opacity: gauge.number ? 0 : Math.max(0, 1 - root.charge * 2.5) * (Clips.paused ? 0.5 : 1)
            Behavior on opacity { enabled: root.charge < 0.01; NumberAnimation { duration: Motion.respond } }
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            SequentialAnimation on scale {
                running: Clips.recording && !Clips.paused
                loops: Animation.Infinite
                NumberAnimation { to: 0.75; duration: Motion.pulse; easing.type: Motion.ambient }
                NumberAnimation { to: 1.0; duration: Motion.pulse; easing.type: Motion.ambient }
            }
        }
        // What a hold is aiming for: a crosshair, turning in as it charges.
        MaterialIcon {
            anchors.centerIn: parent
            glyph: "\u{F01A4}"                                               // 󰆤 crosshairs
            font.pixelSize: root.innerGlyphPx
            color: root.holdTint
            opacity: Math.max(0, Math.min(1, (root.charge - 0.25) * 2))
            rotation: -90 * (1 - root.charge)
            scale: 0.6 + 0.4 * root.charge
        }
        StyledText {
            anchors.fill: parent
            anchors.margins: gauge.thickness + Tokens.spacingXs
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: ClockFmt.clock(Clips.recording ? root.recordSecs : root.heldSecs)
            font.bold: true
            font.pixelSize: Math.round(height * 0.55)
            fontSizeMode: Text.Fit
            minimumPixelSize: Tokens.fontMicro
            opacity: gauge.number ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }
    }

    // ── The charge: an arc round the ring, un-eased ───────────────────────────
    // Its own Shape, not a RadialGauge: the gauge eases its sweep, and a hold must
    // track the finger.
    Shape {
        id: chargeArc
        anchors.centerIn: parent
        visible: root.charge > 0.01
        readonly property real size: root.ringSize + Tokens.spacingSm * 2
        readonly property real stroke: Math.max(Tokens.spacingXs, Math.round(gauge.thickness * 1.2))
        width: chargeArc.size
        height: chargeArc.size
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).alpha(root.holdTint, 0.18)
            strokeWidth: chargeArc.stroke
            fillColor: "transparent"
            PathAngleArc {
                centerX: chargeArc.size / 2; centerY: chargeArc.size / 2
                radiusX: (chargeArc.size - chargeArc.stroke) / 2
                radiusY: (chargeArc.size - chargeArc.stroke) / 2
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: root.holdTint
            strokeWidth: chargeArc.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: chargeArc.size / 2; centerY: chargeArc.size / 2
                radiusX: (chargeArc.size - chargeArc.stroke) / 2
                radiusY: (chargeArc.size - chargeArc.stroke) / 2
                startAngle: -90
                sweepAngle: 360 * root.charge
            }
        }
    }

    // Not mid-hold: a hold opens the target picker in the same slot.
    SideHover {
        hovered: mouse.containsMouse && !mouse.pressed && root.charge < 0.01
        from:    "clips"
        arg:     "clips"
        screen:  root.screen
        enabled: !root.open
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) {
            feedback.press(m.x, m.y)
            root.fired = false
            if (m.button === Qt.LeftButton && root.usable) dwell.restart()
        }
        onReleased: { feedback.release(); root.letGo() }
        onCanceled: { feedback.release(); root.letGo() }
        onClicked: function (m) {
            // A completed hold already did its thing.
            if (root.fired) { root.fired = false; return }
            if (m.button === Qt.RightButton)       UiState.openSettingsTo("ClipsPage.qml")
            else if (m.button === Qt.MiddleButton) Clips.saveClip(0)
            else                                   UiState.toggleSidePanel("clips", "clips", root.screen)
        }
    }
}
