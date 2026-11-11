pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs
import "../../services/workspaces.js" as Wsp
import ".."
import "."

// DockAppButton — DockIconStrip's inline `AppButton`, moved into its own file (2026-11-08).
Item {
    id: btn
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip

    required property string modelData
    required property int    index

    readonly property string key: btn.modelData
    readonly property var    group: strip.groups[btn.key] ?? null

    readonly property bool running:   btn.group !== null
    readonly property bool focused:   btn.group ? btn.group.focused : false
    readonly property bool urgent:    (btn.group ? btn.group.urgent : false)
                                      || (btn.reported !== null && btn.reported.urgent)
    readonly property bool launching: Taskbar.launching[btn.key] !== undefined
    // A pin whose app has no desktop entry any more: it can be unpinned, not
    // started. Drawn faded so it doesn't pose as a working button.
    readonly property bool launchable: btn.running || Taskbar.canPin(btn.key)

    readonly property bool dragging: strip.dragKey === btn.key
    readonly property bool hot: mouse.containsMouse && strip.dragKey === ""

    readonly property string iconPath: Taskbar.iconFor(btn.key)

    // Sound it's making (null = none), unseen notifications, a media player.
    readonly property var sound: Taskbar.audio[btn.key] ?? null
    // What the app reports about itself (LauncherEntry), if anything.
    readonly property var reported: Taskbar.reported[btn.key] ?? null
    // The app's own count wins when it shows one — it knows what's unread better
    // than notification history does (and it's shown even while focused, as
    // Windows does). Otherwise, notifications since you last looked.
    readonly property bool ownCount: btn.reported !== null && btn.reported.countVisible
                                     && btn.reported.count > 0
    readonly property int badge: btn.ownCount ? btn.reported.count : (Taskbar.badges[btn.key] ?? 0)

    width:  strip.button
    height: strip.button
    z: btn.dragging ? 10 : 0

    // ── Where it sits ─────────────────────────────────────────────────────
    readonly property real restPos: strip.slotPos(btn.index)
    readonly property real pos: btn.dragging
        ? strip.dragPos
        // The app being dragged in from the launcher, already on the dock:
        // shown faint in the gap it would land in.
        : (strip.insertAt >= 0 && strip.insertKey === btn.key)
        ? strip.lead + strip.insertAt * strip.slot
        : btn.restPos + strip.slot * (strip.insertAt >= 0
              ? DockJs.shift(btn.index, strip.insertFrom >= 0 ? strip.insertFrom : strip.count, strip.insertAt)
              : DockJs.shift(btn.index, strip.dragFrom, strip.dragTo))

    x: strip.vertical ? 0 : btn.pos
    y: strip.vertical ? btn.pos : 0

    // Not while it's in the hand: easing a position the pointer is holding
    // reads as lag. Snappier while a drag is reflowing the neighbours than when
    // an app opens or closes, where it's the same curve as the strip's length.
    Behavior on x {
        enabled: !btn.dragging
        NumberAnimation {
            duration: strip.dragKey !== "" ? Motion.standard : Motion.emphasized
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: Easing.BezierSpline
        }
    }
    Behavior on y {
        enabled: !btn.dragging
        NumberAnimation {
            duration: strip.dragKey !== "" ? Motion.standard : Motion.emphasized
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: Easing.BezierSpline
        }
    }

    // ── Arriving ──────────────────────────────────────────────────────────
    // A new button swells in from 60% with the spring's overshoot, while the
    // strip opens its slot on the emphasized curve above.
    property real born: 0
    // Set when the swell has finished. The spring overshoots past 1, so
    // `born >= 1` would switch the scale Behavior on mid-flight and leave it
    // chasing the rest of the swell a frame behind.
    property bool settled: false
    // Built with the strip: one after another (strip._fresh). Frozen at
    // creation — `_fresh` flips a frame later, long before the pause is up.
    property int bornDelay: strip._fresh ? strip.entranceDelay(btn.index) : 0
    Component.onCompleted: btn.bornDelay = btn.bornDelay
    SequentialAnimation on born {
        onFinished: btn.settled = true
        PauseAnimation { duration: btn.bornDelay }
        NumberAnimation {
            from: 0; to: 1
            duration: Motion.emphasized
            easing.bezierCurve: Motion.spring
            easing.type: Easing.BezierSpline
        }
    }

    // ── Rising with the dock ──────────────────────────────────────────────
    // Each time the dock comes out, the icons rise out of the edge in turn,
    // riding the reveal and landing a beat apart. Going in they sink with the
    // surface, all at once — nothing to stagger on the way out.
    property real rise: 0
    Connections {
        target: strip
        function onShownChanged() {
            if (strip.shown && Motion.emphasized > 0) riseAnim.restart()
        }
    }
    SequentialAnimation {
        id: riseAnim
        PropertyAction  { target: btn; property: "rise"; value: Tokens.spacingMd }
        PauseAnimation  { duration: strip.entranceDelay(btn.index) }
        NumberAnimation { target: btn; property: "rise"; to: 0
                          duration: Motion.emphasized
                          easing.bezierCurve: Motion.spring; easing.type: Easing.BezierSpline }
    }

    // A button can die under the pointer (its app closed) without its
    // MouseArea ever reporting the pointer left. And it leaves a copy of
    // itself to sink out where it stood (strip._leave says when).
    Component.onDestruction: {
        strip._hover(btn.key, false)
        strip._leave(btn.key, btn.iconPath, btn.x, btn.y)
    }

    // ── The launch bounce ─────────────────────────────────────────────────
    // One hop away from the edge when a click starts an app, the way Windows
    // acknowledges a launch before the window exists.
    property real hop: 0
    function bounce() { hopAnim.restart() }

    // ── Asking for attention ──────────────────────────────────────────────
    // On top of the warning pulse: a few hops, the way a macOS icon bounces for
    // attention and a Windows button flashes. Three, then it settles into the
    // pulse — a dock that bounces forever is a dock you learn to ignore.
    readonly property int attentionHops: 3
    property int hopsLeft: 0
    onUrgentChanged: btn.hopsLeft = btn.urgent ? btn.attentionHops : 0
    Timer {
        running: btn.hopsLeft > 0
        interval: Motion.slow * 3
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            btn.bounce()
            btn.hopsLeft--
        }
    }
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: btn; property: "hop"; to: Tokens.spacingSm
                          duration: Motion.fast; easing.type: Motion.enter }
        NumberAnimation { target: btn; property: "hop"; to: 0
                          duration: Motion.fast; easing.type: Motion.exitCurve }
        NumberAnimation { target: btn; property: "hop"; to: Tokens.spacingXs
                          duration: Motion.fast; easing.type: Motion.enter }
        NumberAnimation { target: btn; property: "hop"; to: 0
                          duration: Motion.fast; easing.type: Motion.exitCurve }
    }

    // ── Layers, back to front ─────────────────────────────────────────────
    DockWash { strip: btn.strip;
        id: wash
        hovered: btn.hot || strip.kbIndex === btn.index
    }

    DockFocusRing { strip: btn.strip; visible: strip.kbIndex === btn.index || btn.fileTarget }

    // A file being dragged over this app, and the app can open it.
    readonly property bool fileTarget: strip.fileDropIndex === btn.index
                                       && Taskbar.acceptsFiles(btn.key)

    // The focused app keeps a quiet fill, Windows' "this one is in front" —
    // in the overview's dock. The sidebar's says it with the glider alone (the
    // user's call: no box behind the focused app).
    Rectangle {
        anchors.fill: parent
        radius: strip.cellRadius
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
        visible: !strip.flat
        opacity: btn.focused && !btn.dragging ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    // Wants attention: Windows' flashing taskbar button, as a slow pulse in the
    // warning colour until the app is focused (Hyprland clears urgency then).
    Rectangle {
        id: urgentFill
        anchors.fill: parent
        radius: strip.cellRadius
        color: Colors.of(QsWindow.window).warning
        visible: btn.urgent
        opacity: 0.12
        SequentialAnimation on opacity {
            // Never with motion off: Motion.slow is 0 then, and an infinite loop
            // of zero-length steps spins the CPU.
            running: btn.urgent && Motion.slow > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.32; duration: Motion.slow; easing.type: Motion.respondCurve }
            NumberAnimation { to: 0.12; duration: Motion.slow; easing.type: Motion.respondCurve }
        }
    }

    Item {
        id: face
        anchors.fill: parent
        opacity: btn.born * (btn.launchable ? 1 : 0.4)
                 * ((btn.dragging && strip.dragOff) || strip.insertKey === btn.key ? 0.35 : 1)
        // Magnifying, the swell follows the pointer directly — no Behavior on a
        // value the hand is driving (easing it reads as lag).
        readonly property real magnified: strip.magnifying
            ? strip.magnifyAt(btn.restPos + strip.button / 2)
            : 1.0
        transformOrigin: strip.magnifying ? strip.magnifyOrigin : Item.Center
        scale: (0.6 + 0.4 * btn.born)
             * (mouse.pressed && !btn.dragging ? strip.pressScale
                : strip.magnifying ? face.magnified
                : btn.hot || btn.dragging ? strip.hoverScale : 1.0)
        Behavior on scale {
            enabled: btn.settled && !strip.magnifying
            NumberAnimation { duration: Motion.respond; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }

        // Lifts away from the screen edge on hover, and hops on launch; sits
        // down into it while rising with the dock.
        property real lift: btn.hot ? strip.hoverLift : 0
        Behavior on lift { NumberAnimation { duration: Motion.respond; easing.type: Motion.enter } }
        readonly property real away: face.lift + btn.hop - btn.rise

        transform: [
            // The sidebar's lift: the icon rises on the plate's hover spring, as every other
            // cell's glyph does (CellFeedback.lift; 1 off the bar's ladder).
            Scale {
                origin.x: face.width / 2
                origin.y: face.height / 2
                xScale: strip.barFeedback ? wash.lift : 1
                yScale: strip.barFeedback ? wash.lift : 1
            },
            Translate {
                x: strip.edge === "left" ? face.away : strip.edge === "right" ? -face.away : 0
                y: strip.vertical ? 0 : strip.edge === "top" ? face.away : -face.away
            }
        ]

        Image {
            id: img
            anchors.centerIn: parent
            visible: btn.iconPath !== ""
            source: btn.iconPath
            width:  strip.iconPx
            height: strip.iconPx
            // Rasterised at the hovered size, so the hover scale-up stays crisp —
            // the tint's layer too (`tinted`), or it would draw at the resting size.
            sourceSize: Qt.size(strip.iconRaster, strip.iconRaster)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            layer.enabled: strip.tinted
            layer.textureSize: Qt.size(strip.iconRaster, strip.iconRaster)
            layer.smooth: true
            layer.effect: MonoIconEffect {}
        }

        // Unseen notifications from this app (Notifications.unseenFor — since the
        // notification panel was last opened; 2026-10-31, the user's pick: "richer
        // glances"), on the icon's corner, so it lifts with it. Matched by the app's
        // desktop id or its name, so an app naming itself unlike its window class has none.
        CountBadge {
            anchors.top: img.top
            anchors.right: img.right
            anchors.topMargin: -Tokens.spacingXs
            anchors.rightMargin: -Tokens.spacingXs
            count: Notifications.unseenFor(btn.key, Taskbar.nameFor(btn.key))
            visible: count > 0
        }

        // A glyph, not a fallback icon NAME — the theme has no generic
        // executable icon, so asking for one only trades one miss for another.
        MaterialIcon {
            anchors.centerIn: parent
            visible: btn.iconPath === ""
            glyph: "󰬉"
            color: Colors.of(QsWindow.window).fgMuted
            font.pixelSize: strip.iconPx
        }
    }

    // ── Running indicator ─────────────────────────────────────────────────
    // Windows 11's pill on the button's OUTWARD side: a short muted one for
    // running, a long accent one for focused, warning-coloured for attention.
    // Pulses while a launch is still waiting for its first window.
    Rectangle {
        id: pip
        // Focused, the glider is drawn on it (strip.gliding) — this stays the
        // short running pip underneath until the glider can't be.
        readonly property bool showsFocus: btn.focused && !strip.gliding
        readonly property real thick: strip.indicatorThick
        // Running: a short pill (on the sidebar the same short line, not a dot — see
        // "One calm mark"). Making sound on the sidebar: that line, stretched toward the
        // focused length by how loud the app is (the level bars' job elsewhere).
        readonly property bool sounding: strip.barFeedback && btn.sound !== null
        readonly property real len:
              pip.showsFocus || btn.urgent    ? strip.focusMarkLen
            : pip.sounding                    ? Tokens.spacingMd + (strip.focusMarkLen - Tokens.spacingMd) * bars.loud
            : btn.running || btn.launching    ? Tokens.spacingMd
            :                                   0

        width:  strip.vertical ? pip.thick : pip.len
        height: strip.vertical ? pip.len   : pip.thick
        radius: pip.thick / 2
        x: strip.vertical ? strip.indicatorAt(pip.width) : (btn.width - pip.width) / 2
        y: strip.vertical ? (btn.height - pip.height) / 2 : strip.indicatorAt(pip.height)

        color: btn.urgent       ? Colors.of(QsWindow.window).warning
             : pip.showsFocus   ? Colors.of(QsWindow.window).focus
             :                    Colors.of(QsWindow.window).fgMuted
        visible: (pip.len > 0 || pip.width > 0.5 || pip.height > 0.5)
                 && (btn.sound === null || strip.barFeedback) && !strip.ii
        opacity: btn.dragging ? 0 : (btn.launching && !btn.running ? pip.pulse : 1)

        property real pulse: 1
        SequentialAnimation on pulse {
            running: btn.launching && !btn.running && Motion.slow > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: Motion.slow; easing.type: Motion.respondCurve }
            NumberAnimation { to: 1.0;  duration: Motion.slow; easing.type: Motion.respondCurve }
        }

        Behavior on width  { NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring
                                               easing.type: Easing.BezierSpline } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring
                                               easing.type: Easing.BezierSpline } }
        Behavior on color  { ColorAnimation  { duration: Motion.respond } }
    }

    // ── ii: one dot per window ────────────────────────────────────────────
    // Up to three, side by side where the pip would be: wide pills for one to three
    // windows, small circles past that ("a lot"). The focused app's are the accent,
    // the rest a quiet foreground; attention is the warning colour, and an app still
    // waiting for its first window shows one dot that breathes like the pip does.
    // Hidden while the app is making sound (the level bars take that place).
    Item {
        id: dots
        readonly property int  windows: btn.group ? btn.group.count : 0
        readonly property int  n: btn.running ? Math.min(dots.windows, 3) : (btn.launching ? 1 : 0)
        readonly property bool many: dots.windows > 3
        readonly property real along: dots.many ? strip.indicatorThick : Tokens.spacingMd + Tokens.spacingXs
        readonly property real across: strip.indicatorThick
        readonly property real run: dots.n * dots.along + Math.max(0, dots.n - 1) * Tokens.spacingXs

        visible: strip.ii && dots.n > 0 && btn.sound === null && !btn.dragging
        opacity: btn.launching && !btn.running ? pip.pulse : 1
        width:  strip.vertical ? dots.across : dots.run
        height: strip.vertical ? dots.run : dots.across
        x: strip.vertical ? strip.indicatorAt(dots.width) : (btn.width - dots.width) / 2
        y: strip.vertical ? (btn.height - dots.height) / 2 : strip.indicatorAt(dots.height)

        Repeater {
            model: dots.n
            Rectangle {
                required property int index
                readonly property real off: index * (dots.along + Tokens.spacingXs)
                width:  strip.vertical ? dots.across : dots.along
                height: strip.vertical ? dots.along : dots.across
                x: strip.vertical ? 0 : off
                y: strip.vertical ? off : 0
                radius: dots.across / 2
                color: btn.urgent  ? Colors.of(QsWindow.window).warning
                     : btn.focused ? Colors.of(QsWindow.window).focus
                     :               Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.4)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
        }
    }

    // ── Unseen notifications ──────────────────────────────────────────────
    // Windows' badge: how many arrived since you last had this app in front of
    // you. Hidden while it IS in front of you — you're looking at them.
    // Pops in on the spring and bumps when the count moves; shrinks away
    // with the last count it had (a local copy — see `held`), not a blank.
    Badge {
        id: badge
        readonly property bool shown: btn.badge > 0 && (btn.ownCount || !btn.focused) && !btn.dragging
        property string held: ""
        readonly property string count: DockJs.badgeText(btn.badge)
        onCountChanged: if (btn.badge > 0) {
            const bump = badge.held !== "" && badge.held !== badge.count
            badge.held = badge.count
            if (bump && badge.shown) bumpAnim.restart()
        }
        Component.onCompleted: if (btn.badge > 0) badge.held = badge.count

        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.spacingXs
        label:  badge.held
        tint:   Colors.of(QsWindow.window).primary
        filled: true

        transformOrigin: Item.Center
        scale: badge.shown ? 1 : 0
        visible: badge.scale > 0.01
        Behavior on scale {
            NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
        property real bump: 1
        transform: Scale {
            origin.x: badge.width / 2
            origin.y: badge.height / 2
            xScale: badge.bump
            yScale: badge.bump
        }
        SequentialAnimation {
            id: bumpAnim
            NumberAnimation { target: badge; property: "bump"; to: 1.25
                              duration: Motion.fast; easing.type: Motion.enter }
            NumberAnimation { target: badge; property: "bump"; to: 1
                              duration: Motion.standard; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
    }

    // ── Scrolling over it ─────────────────────────────────────────────────
    // An app making sound: its volume, 5% a notch on multiples of 5 — the bar's
    // media pill, exactly (Taskbar.stepVolume). Otherwise: its windows.
    // Deltas are summed to a full notch first, so a touchpad's stream of tiny
    // deltas steps once per swipe-notch instead of once per event.
    property real wheelAcc: 0
    WheelHandler {
        enabled: !strip.editMode
        acceptedModifiers: Qt.NoModifier
        onWheel: function(event) {
            btn.wheelAcc += event.angleDelta.y
            if (Math.abs(btn.wheelAcc) < 120) return
            const up = btn.wheelAcc > 0
            btn.wheelAcc = 0
            if (btn.sound) {
                // Same feedback as the media pill: the system OSD, with this
                // app's own icon and its new level.
                const r = Taskbar.stepVolume(btn.key, up)
                if (r) Osd.show("volume", r.level, r.muted || r.level <= 0,
                                Audio.glyph(r.level, r.muted),
                                r.muted ? "Muted" : Math.round(r.level * 100) + "%",
                                btn.iconPath)
            } else if (btn.running) {
                strip.closePreview()
                Taskbar.cycleWindows(btn.key, up ? -1 : 1, strip.monitor, strip.groups)
            }
        }
    }

    // ── Progress the app reports (a download, a render) ──────────────────
    // Across the button's outward side, just inside the running indicator —
    // Windows' progress-on-the-taskbar-button, as the house Meter.
    Meter {
        visible: btn.reported !== null && btn.reported.progressVisible && !btn.dragging
        value:   btn.reported ? btn.reported.progress : 0
        accent:  Colors.of(QsWindow.window).primary
        width:   btn.width - Tokens.spacingMd * 2
        height:  Tokens.spacingSm
        x: Tokens.spacingMd
        y: btn.height - height - Tokens.spacingXs * 2 - Tokens.spacingXs
    }

    // ── Making sound ──────────────────────────────────────────────────────
    // The running indicator becomes three small level bars while the app has
    // a playback stream — same place, same colour logic, so it reads as the
    // indicator saying more rather than a second badge on the icon. Muted,
    // they lie flat and dim. Mute/unmute is in the jump list; scroll for
    // volume.
    Item {
        id: bars
        readonly property bool live:  btn.sound !== null && !btn.sound.muted
        readonly property int  thick: strip.indicatorThick
        readonly property int  tall:  Tokens.spacingSm * 2          // longest bar
        readonly property int  n:     3
        // Not on the sidebar: its running line stretches with the loudness instead
        // ("One calm mark"), reading `loud` from here — so the meter runs for it too.
        visible: btn.sound !== null && !btn.dragging && !strip.barFeedback
        readonly property bool measuring: bars.visible || (strip.barFeedback && btn.sound !== null && !btn.dragging)

        // Along the dock's edge, on the pip's side of the button.
        width:  strip.vertical ? bars.tall : bars.n * bars.thick + (bars.n - 1) * bars.thick
        height: strip.vertical ? bars.n * bars.thick + (bars.n - 1) * bars.thick : bars.tall
        x: strip.vertical ? strip.indicatorAt(bars.width) : (btn.width - bars.width) / 2
        y: strip.vertical ? (btn.height - bars.height) / 2 : strip.indicatorAt(bars.height)

        // The app's real loudness — the mixer's own chain (PwNodePeakMonitor →
        // Audio.meterLevel), metering only while these bars are on screen. A
        // stream whose channels PipeWire can't name can't be metered (the mixer
        // skips it for the same reason, see Audio.hasKnownChannels); those fall
        // back to the gentle breathing below.
        PwNodePeakMonitor {
            id: peakMon
            node: btn.sound ? btn.sound.streams[0] : null
            enabled: bars.measuring && bars.live && peakMon.node !== null
                     && Audio.hasKnownChannels(peakMon.node)
        }
        readonly property bool metered: peakMon.enabled
        readonly property real loud: bars.metered ? Audio.meterLevel(peakMon.peak) : 0

        Repeater {
            model: bars.n
            delegate: Rectangle {
                id: bar
                required property int index
                // Metered: the loudness, each bar weighted differently so the
                // three read as a little spectrum rather than one bar three times.
                readonly property real weight: [0.75, 1.0, 0.85][bar.index]
                // Not readonly: a Behavior writes the value it animates, and QML
                // refuses that on a readonly property — a load failure of the file.
                property real metered: Math.max(0.15, Math.min(1, bars.loud * bar.weight * 1.2))
                Behavior on metered { NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve } }

                // Unmetered: each bar breathes on its own period, so the three
                // never lock into one pulse. Flat (a dot) while muted.
                property real breath: 0.35
                readonly property real level: bars.metered ? bar.metered : bar.breath
                SequentialAnimation on breath {
                    running: bars.live && !bars.metered && Motion.slow > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.0;  duration: Motion.slow + bar.index * Motion.fast
                                      easing.type: Motion.respondCurve }
                    NumberAnimation { to: 0.3;  duration: Motion.slow + (2 - bar.index) * Motion.fast
                                      easing.type: Motion.respondCurve }
                }
                readonly property real len: bars.live ? Math.max(bars.thick, bars.tall * bar.level) : bars.thick

                radius: bars.thick / 2
                color: !bars.live  ? Colors.of(QsWindow.window).fgDim
                     : btn.focused ? Colors.of(QsWindow.window).focus
                     :               Colors.of(QsWindow.window).fgMuted
                width:  strip.vertical ? bar.len : bars.thick
                height: strip.vertical ? bars.thick : bar.len
                // Grow away from the edge the pip sits on.
                x: strip.vertical ? (strip.indicatorLow ? 0 : bars.width - bar.len)
                                 : bar.index * bars.thick * 2
                y: strip.vertical ? bar.index * bars.thick * 2
                                 : (strip.indicatorLow ? 0 : bars.height - bar.len)
            }
        }
    }

    // ── Input ─────────────────────────────────────────────────────────────
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: btn.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        // The grab must survive the pointer leaving the button mid-drag.
        preventStealing: true

        // In `track` coordinates — a fixed frame. The button's own coordinates
        // move with the drag, so a delta measured in them fights itself.
        property real pressMain: 0
        property real pressCross: 0
        property bool moved: false

        onContainsMouseChanged: strip._hover(btn.key, mouse.containsMouse)

        onPressed: function(m) {
            wash.press(m.x, m.y)
            const p = mouse.mapToItem(strip.trackItem, m.x, m.y)
            mouse.pressMain  = strip.vertical ? p.y : p.x
            mouse.pressCross = strip.vertical ? p.x : p.y
            mouse.moved = false
        }

        onPositionChanged: function(m) {
            if (!mouse.pressed || !(m.buttons & Qt.LeftButton)) return
            const p = mouse.mapToItem(strip.trackItem, m.x, m.y)
            const main  = strip.vertical ? p.y : p.x
            const cross = strip.vertical ? p.x : p.y
            if (!mouse.moved) {
                // Either axis: pulling an icon straight up off the dock is a drag too.
                const slop = Qt.styleHints.startDragDistance
                if (Math.abs(main - mouse.pressMain) < slop
                    && Math.abs(cross - mouse.pressCross) < slop) return
                mouse.moved = true
                strip._beginDrag(btn.key, btn.index, btn.restPos)
            }
            strip._dragTo(btn.restPos + (main - mouse.pressMain))
            // How far INTO the screen the pointer is past the strip's inner edge.
            const inward = strip.edge === "left"  ? p.x - strip.button
                         : strip.edge === "right" ? -p.x
                         : strip.edge === "top"   ? p.y - strip.button
                         :                         -p.y
            strip.dragOff = btn.index < strip.pinCount && inward > strip.button
            strip.dragScene = mouse.mapToItem(null, m.x, m.y)
        }

        onReleased: function(m) {
            wash.release()
            if (mouse.moved) {
                mouse.moved = false
                strip._endDrag(true)
                return
            }
            // Let go somewhere else: not a click.
            if (!mouse.containsMouse) return

            if (m.button === Qt.RightButton) {
                const s = mouse.mapToItem(null, m.x, m.y)
                strip._openMenu(btn.key, s.x, s.y)
            } else if (m.button === Qt.MiddleButton) {
                strip._closeRecent(btn.key)
            } else if (m.modifiers & Qt.ShiftModifier) {
                strip._newWindow(btn.key, btn)
            } else {
                strip._activate(btn.key, btn)
            }
        }

        // The grab can be taken away without a release.
        onCanceled: {
            wash.release()
            if (mouse.moved) strip._endDrag(false)
            mouse.moved = false
        }
    }

}
