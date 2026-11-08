pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
// The calendar is the overview's own card, instantiated here rather than
// reimplemented — it is a month grid over pure date arithmetic with no session state
// in it at all, which is exactly why it is one of the few things a greeter can borrow.
import "../overview"

// ── GreetScreen ───────────────────────────────────────────────────────────────
// The login screen. Same visual language as the lock — blurred drifting backdrop,
// vignette in the palette's own colour, a blocky clock over one field — because it
// is the same moment from the other side, and a machine that looks like one shell
// after login and something else before it looks like two machines.
//
// ── This is a different PROCESS, not a mode ───────────────────────────────────
// Loaded by greet.qml, which greetd runs as the `greeter` user before any session
// exists. There is no bar, no notification daemon, no Discord, no clipboard and no
// updater — not because they are switched off, but because greet.qml never names
// them and every service in this shell is a lazy singleton. The only ones that
// instantiate are the ones referenced below.
//
// ── What may appear on a screen nobody has authenticated to ───────────────────
// The time, and nothing else that came from your machine's state. The lock screen
// can show a notification COUNT and what is playing, because by then the session is
// yours and merely hidden. Here there is no session to have facts about, and the
// wallpaper and avatar are the only two things exported deliberately — see the
// bundle note in services/Greet.qml.
//
// ── One interactive surface, however many monitors ────────────────────────────
// Every output gets the backdrop and the clock, so a second monitor is not a black
// rectangle that reads as a dead machine. Only the first gets the password box.
//
// That is a real limitation and it is deliberate rather than unfinished: layer-shell
// keyboard focus is per surface, so N boxes means the compositor picks which one
// receives your typing and the other N-1 sit there accepting nothing. Two password
// boxes where only one works is worse than one box in a known place.
// ─────────────────────────────────────────────────────────────────────────────
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: surface

        required property var modelData
        screen: surface.modelData

        // The box goes on the first screen. Not "the primary" — layer-shell has no
        // concept of one, and Hyprland's idea of primary is not exposed to a client
        // that has not connected to its IPC. First is at least stable across a reload.
        readonly property bool interactive:
            Quickshell.screens.length === 0 || surface.modelData === Quickshell.screens[0]

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-greet"

        // ── Exclusive, and only on the surface with the field ─────────────────
        // OnDemand grants focus on a click INTO the surface, which for a login screen
        // means the machine ignores the password you started typing at it. There is
        // nothing to be polite to here — this process IS the session until it is not.
        //
        // The other screens take None rather than Exclusive: two surfaces both
        // claiming exclusive keyboard is exactly the fight described at the top.
        WlrLayershell.keyboardFocus: surface.interactive ? WlrKeyboardFocus.Exclusive
                                                         : WlrKeyboardFocus.None

        // ══ Reveal ════════════════════════════════════════════════════════════
        // The greeter appears on a screen that was black a moment ago, so it fades in
        // rather than cutting. Two derived curves stagger the layers behind the field,
        // same shape as the lock's.
        property real reveal: 0
        readonly property real revealLate:
            Math.max(0, Math.min(1, (surface.reveal - 0.25) / 0.75))

        NumberAnimation on reveal {
            id: revealIn
            to: 1
            duration: Config.motionEnabled ? Motion.slow * 2 : 0
            easing.type: Motion.travel
            running: true
        }

        // ══ Backdrop ══════════════════════════════════════════════════════════
        readonly property string backdrop: Greet.backdrop
        readonly property bool hasBackdrop: surface.backdrop !== ""
        readonly property bool backdropIsGif: surface.backdrop.toLowerCase().endsWith(".gif")

        Rectangle {
            anchors.fill: parent
            color: Colors.of(QsWindow.window).base
        }

        Item {
            anchors.fill: parent
            visible: surface.hasBackdrop
            opacity: surface.reveal

            layer.enabled: surface.hasBackdrop
            // Quarter resolution. The blur is destroying this detail anyway, and
            // blurring a 4K texture every frame to throw it away is the single most
            // expensive thing a login screen could choose to do.
            layer.textureSize: Qt.size(Math.max(320, Math.round(surface.width  / 4)),
                                       Math.max(180, Math.round(surface.height / 4)))
            layer.smooth: true
            // ── Blurred hard, on purpose ──────────────────────────────────────
            // 20 was inherited from the lock screen and is wrong here. The lock sits
            // over YOUR desktop wallpaper as a recognisable backdrop; this sits under a
            // single centred column with nothing else on screen, and any structure left
            // in the picture lands directly behind the one thing you have to read.
            //
            // The Arch wallpaper is the case that proved it: a high-contrast white mark
            // dead centre, which at blurMax 20 survived as a legible logo pointing
            // straight at the password field. 64 turns a wallpaper into a wash of its own
            // colours — which is all this needs it to be, since the palette is already
            // derived from it and carries the identity.
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: surface.reveal
                blurMax: 64
                autoPaddingEnabled: false
                brightness: -0.30
                saturation: -0.20
            }

            // A GIF needs AnimatedImage — a plain Image decodes frame one and stops,
            // which reads as a still that is subtly wrong rather than as an error.
            // The exported backdrop is normally a still, but the export copies
            // whatever the wallpaper actually is, and a scene preview is a GIF.
            Loader {
                id: backdropLoader
                anchors.fill: parent
                sourceComponent: surface.backdropIsGif ? gifBackdrop : stillBackdrop

                // Slow drift, so the screen is never completely static. On a still it
                // is the only motion there is; on a loop it is what stops the loop
                // point being the thing your eye locks onto.
                SequentialAnimation on scale {
                    running: Config.motionEnabled && surface.hasBackdrop
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0;  to: 1.08; duration: 45000; easing.type: Motion.ambient }
                    NumberAnimation { from: 1.08; to: 1.0;  duration: 45000; easing.type: Motion.ambient }
                }
            }

            Component {
                id: stillBackdrop
                Image {
                    source: "file://" + surface.backdrop
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Decoded at the blur's own resolution, not the screen's.
                    sourceSize: Qt.size(Math.round(surface.width / 2),
                                        Math.round(surface.height / 2))
                }
            }

            Component {
                id: gifBackdrop
                AnimatedImage {
                    source: "file://" + surface.backdrop
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    playing: Config.motionEnabled
                    speed: 1.0
                }
            }
        }

        // ── Vignette ──────────────────────────────────────────────────────────
        // In the palette's base colour rather than black, so the greeter is tinted by
        // the same wallpaper-derived scheme as everything after it.
        //
        // ── Why this is not the lock's curve ──────────────────────────────────
        // The lock screen's vignette is heavy at top and bottom and LIGHTEST through the
        // middle band, which is right for it: its content lives in the four corners and
        // the middle is where the wallpaper is allowed to show through.
        //
        // This surface is the exact opposite. Everything you can read or act on is one
        // centred column, so that curve put the busiest part of the picture directly
        // behind the only thing that matters — copied over without re-deriving it, which
        // is how a value that was correct in one place becomes a bug in another.
        //
        // Now it is darkest at the edges AND through the centre band the column occupies
        // (~30–65%), with the lighter ring between them giving the composition somewhere
        // to breathe.
        Rectangle {
            anchors.fill: parent
            opacity: surface.reveal
            gradient: Gradient {
                GradientStop { position: 0.00; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.82) }
                GradientStop { position: 0.16; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.52) }
                GradientStop { position: 0.34; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.66) }
                GradientStop { position: 0.52; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.72) }
                GradientStop { position: 0.68; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.60) }
                GradientStop { position: 0.86; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.56) }
                GradientStop { position: 1.00; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.86) }
            }
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        // ══ The ambient corners ═══════════════════════════════════════════════
        // Only on the screen carrying the field: the others get the backdrop and the
        // clock, and a second monitor repeating your CPU load is noise rather than
        // information.
        //
        // ── What may appear on a screen NOBODY has authenticated to ───────────
        // A stricter line than the lock screen's, because there the session is yours
        // and merely hidden — here nobody has proven anything. Every one of these was
        // checked against "what does this tell a stranger standing at the machine":
        //
        //   · load and memory  — facts about the hardware, not about you
        //   · the date         — a month grid, no events; CalendarCard holds no
        //                        session state, which is why it can be borrowed at all
        //   · uptime and host  — the one thing a LOGIN screen can say that a lock
        //                        screen cannot: whether this machine rebooted without
        //                        you, and how long ago
        //   · weather          — the only one that leaks anything (your rough
        //                        location), and the only one behind a config value
        //                        that has to be exported deliberately to work
        //
        // Nothing here is interactive. The password box and the two power buttons are
        // the entire list of things an unauthenticated person can act on.
        //
        // ── Held live only while the greeter is up ────────────────────────────
        // acquire()/release() is the shell-wide idiom. A greeter is short-lived, so
        // this is mostly a formality — but SysInfo polls on a timer, and a service
        // left running with nothing reading it is exactly the kind of cost that does
        // not show up until it is on a login screen that has to paint fast.
        Component.onCompleted: {
            if (!surface.interactive) return
            // The other half of the timing story. Everything after this is waiting for
            // a human; everything before it is the greeter getting out of bed, and
            // without a mark here a slow startup is indistinguishable from a slow login.
            Greet.mark("surface ready — box is usable")
            SysInfo.acquire()
            Weather.acquire()
        }
        Component.onDestruction: {
            if (!surface.interactive) return
            SysInfo.release()
            Weather.release()
        }

        // ── Top left: weather, then the machine ───────────────────────────────
        ColumnLayout {
            anchors.left: parent.left
            anchors.top:  parent.top
            anchors.margins: Tokens.spacingXxl
            spacing: Tokens.spacingMd

            visible: surface.interactive
            opacity: surface.revealLate
            transform: Translate { x: (1 - surface.revealLate) * -22 }

            GlanceCard {
                // Absent rather than empty when there is no location exported or the
                // fetch has not landed. A greeter has seconds to be useful in, and a
                // card that says "—" for all of them is worse than a card that waited
                // to exist.
                visible: Weather.hasLocation && Weather.ready
                glyph:    Weather.glyph(Weather.code, Weather.isDay)
                headline: Weather.temp(Weather.tempC) + Weather.unit
                detail:   Weather.describe(Weather.code)
                          + (Weather.place !== "" ? "  ·  " + Weather.place : "")
                tint:     Colors.of(QsWindow.window).info
            }

            GlanceCard {
                visible: Greet.hostName !== ""
                glyph:    "󰒋"
                headline: Greet.hostName
                // Derived against the surface's own clock rather than a timer in the
                // service — same rule as Discord's call duration. At Minutes precision
                // this reads "up 4h 12m" and reticks once a minute, which is as often
                // as a number in hours needs to change.
                detail: {
                    const up = Greet.uptimeText(clock.date.getTime())
                    return (up !== "" ? "up " + up : "")
                         + (Greet.kernel !== "" ? "  ·  " + Greet.kernel : "")
                }
                tint: Colors.of(QsWindow.window).primary
            }
        }

        // ── Top right: what the machine is doing ──────────────────────────────
        RowLayout {
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.margins: Tokens.spacingXxl
            spacing: Tokens.spacingMd

            visible: surface.interactive
            opacity: surface.revealLate
            transform: Translate { y: (1 - surface.revealLate) * -18 }

            StatCard {
                label: "CPU"
                tint:  Colors.of(QsWindow.window).primary
                value: SysInfo.cpu
                sampleInterval: SysInfo.interval
                detail: SysInfo.hasCpuTemp
                            ? SysInfo.cpuTemp + "°C  ·  " + SysInfo.cores.length + " threads"
                            : SysInfo.cores.length + " threads"
            }

            StatCard {
                // Absent, not empty, on a machine with no discrete GPU — the row simply
                // closes up. Same rule as the weather card.
                visible: SysInfo.hasGpu
                label: "GPU"
                tint:  Colors.of(QsWindow.window).info
                value: SysInfo.gpu
                sampleInterval: SysInfo.interval
                detail: SysInfo.hasGpuTemp
                            ? SysInfo.gpuTemp + "°C  ·  " + SysInfo.vramUsed.toFixed(1) + " GB"
                            : SysInfo.vramUsed.toFixed(1) + " / " + SysInfo.vramTotal.toFixed(1) + " GB"
            }

            StatCard {
                label: "RAM"
                tint:  Colors.of(QsWindow.window).success
                // memFraction is the RATIO; memUsed is gigabytes. Mixing those up is the
                // one easy mistake in this card.
                value: SysInfo.memFraction
                sampleInterval: SysInfo.interval
                detail: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(1) + " GB"
            }
        }

        // ── Bottom left: the date ─────────────────────────────────────────────
        CalendarCard {
            anchors.left:   parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingXxl

            visible: surface.interactive
            // The card gates its own midnight-rollover timer on this. It defaults to
            // UiState.overviewOpen, which in a greeter is permanently false — so
            // without this the grid would render once and then never notice the date
            // changing under it.
            active: true

            opacity: surface.revealLate
            transform: Translate { x: (1 - surface.revealLate) * -22 }
        }

        // ══ The clock, on every screen ════════════════════════════════════════
        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            // On the interactive screen the clock is the top of the centre column;
            // on the others it is the only thing there, so it sits in the middle.
            anchors.verticalCenter: surface.interactive ? undefined : parent.verticalCenter
            anchors.top: surface.interactive ? parent.top : undefined
            anchors.topMargin: surface.interactive ? Math.round(surface.height * 0.18) : 0

            width: Math.min(surface.width - Tokens.spacingXxl * 2, 460)
            spacing: 0

            opacity: surface.reveal
            transform: Translate { y: (1 - surface.reveal) * -16 }

            // fillWidth + AlignHCenter rather than Layout.alignment, for the reason
            // written out in LockScreen: letter spacing adds an advance after the LAST
            // glyph too, so centring the measured box does not centre what you see.
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.family: Tokens.fontBlock
                font.pixelSize: Tokens.fontHero
                font.weight: Font.ExtraBold
                font.letterSpacing: -2
                color: Colors.of(QsWindow.window).fg
            }

            // The date carried `variant: "label"` — 12px under a 132px clock, which is
            // an eleven-to-one jump with nothing in between. At that ratio it stops
            // reading as the clock's subtitle and starts reading as a stray caption that
            // happened to land there. "title" (15px), letter-spaced and brightened to
            // muted, gives the pair a top and a bottom instead of a headline and a
            // footnote.
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingMd
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                variant: "title"
                emphasis: "muted"
                font.letterSpacing: 1.5
            }
        }

        // ══ The field, on one screen ══════════════════════════════════════════
        ColumnLayout {
            id: centre

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // Clears the clock block above it: ~132px of numerals plus the date and its
            // margin. Re-measured after the date grew from 12px to 15px.
            anchors.topMargin: Math.round(surface.height * 0.18) + 228

            width: Math.min(surface.width - Tokens.spacingXxl * 2, 420)
            spacing: 0

            visible: surface.interactive
            opacity: surface.revealLate
            transform: Translate { y: (1 - surface.revealLate) * 14 }

            // ── Avatar ────────────────────────────────────────────────────────
            // 96 rather than 84, and the ring carries the accent rather than a flat grey
            // outline. Without a photo this circle IS the identity on the screen, and at
            // 84px in `alpha(fg, 0.28)` it read as a disabled placeholder — a grey disc
            // with a grey letter in it, which is what the first screenshot showed.
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth:  96
                implicitHeight: 96

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceHigh, Config.surfaceOpacity)
                    border.width: Math.max(2, Tokens.borderWidth)
                    border.color: field.activeFocus ? Colors.of(QsWindow.window).outlineFocus
                                                    : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.55)
                    Behavior on border.color { ColorAnimation { duration: Motion.standard } }

                    StyledText {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        text: Greet.userName === "" ? "?"
                                                    : Greet.userName.charAt(0).toUpperCase()
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontNumeralMd
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).primary
                    }
                }

                // MASKED, not clipped — `clip` is rectangular and knows nothing about
                // `radius`, so a clipped photo keeps its square corners inside the
                // circle. Same idiom as the lock's avatar.
                Item {
                    anchors.fill: parent
                    anchors.margins: Tokens.borderWidth

                    layer.enabled: true
                    layer.smooth:  true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource:  avatarMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    Image {
                        id: face
                        anchors.fill: parent
                        source: Greet.avatar === "" ? "" : "file://" + Greet.avatar
                        sourceSize: Qt.size(168, 168)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        mipmap: true
                        smooth: true
                        visible: face.status === Image.Ready
                    }
                }

                Item {
                    id: avatarMask
                    anchors.fill: parent
                    anchors.margins: Tokens.borderWidth
                    layer.enabled: true
                    visible: false
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "white"
                    }
                }
            }

            // Your name, at 18px instead of 12. It was `dim`-adjacent and small enough
            // that the screenshot showed it losing to the wallpaper behind it.
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacingLg
                Layout.bottomMargin: Tokens.spacingXl
                text: Greet.userName !== "" ? Greet.userName : "Sign in"
                variant: "headline"
                font.bold: true
                color: Colors.of(QsWindow.window).fg
            }

            // ── The field ─────────────────────────────────────────────────────
            // Wrapped in a plain Item so the shake has something to move it WITHIN —
            // animating a laid-out child's own position fights the layout, which
            // reasserts it on the next pass.
            Item {
                Layout.alignment: Qt.AlignHCenter
                // 340×56 rather than 300×48. This is the only control on the screen and
                // the only thing you touch — at the lock screen's size, floating alone in
                // the middle of a 4K panel with no other furniture around it, it read as
                // small rather than as focused.
                implicitWidth:  340
                implicitHeight: 56

                Surface {
                    id: fieldBox
                    anchors.centerIn: parent
                    width:  340
                    height: 56
                    elevation: Tokens.elevationCard
                    squareMode:   Config.barShape
                    cornerRadius: height / 2
                    focused:      field.activeFocus
                    fillOpacity:  Config.surfaceOpacity

                    border.color: Greet.noticeIsError ? Colors.of(QsWindow.window).danger
                                : field.activeFocus   ? Colors.of(QsWindow.window).outlineFocus
                                :                       Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)
                    Behavior on border.color { ColorAnimation { duration: Motion.standard } }

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin:  Tokens.spacingLg
                        anchors.rightMargin: Tokens.spacingLg

                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment:   TextInput.AlignVCenter

                        // NEVER disabled, for the same reason as the lock's: a field
                        // that stops accepting input while greetd is thinking is
                        // indistinguishable from a login screen that has hung. What is
                        // gated is submission, not typing.
                        enabled: true
                        focus:   true

                        echoMode: Greet.promptSecret ? TextInput.Password : TextInput.Normal
                        passwordCharacter: "•"
                        // The default one-second reveal of the last character is a
                        // shoulder-surfing hole on a screen that is, by definition,
                        // pointed at a room.
                        passwordMaskDelay: 0

                        color: Colors.of(QsWindow.window).fg
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontTitle
                        selectionColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.35)
                        selectedTextColor: Colors.of(QsWindow.window).fg
                        clip: true

                        // No `text:` binding. Typing into a TextInput assigns `text`
                        // imperatively and destroys any declarative binding on it — so a
                        // bound field cannot be cleared after the first keystroke, and a
                        // failed attempt would leave the old password on screen while
                        // the code believed it had wiped it. The field is the source of
                        // truth; clearing means assigning to `field.text`.
                        onAccepted: {
                            const text = field.text
                            if (text === "") return
                            field.text = ""
                            Greet.submit(text)
                        }

                        Component.onCompleted: field.forceActiveFocus()

                        // ── Escape clears, it does not exit ───────────────
                        // There is nowhere to go. The only thing Escape can usefully
                        // mean on a login screen is "forget what I typed" — it must
                        // never mean "close the greeter", because greetd would have
                        // to restart it and on a bad day it would not.
                        //
                        // On the FIELD rather than on a sibling Item, which is the
                        // idiom everywhere else in this shell: `Keys` is an Item
                        // attached property, and the only other way to reach it here
                        // would be a focused Item next to the TextInput — i.e. two
                        // things competing for the focus the password box needs.
                        Keys.onEscapePressed: {
                            field.text = ""
                            surface.armed = ""
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible:  field.text === "" && Greet.phase !== "busy"
                            text:     Greet.promptText
                            variant:  "title"
                            emphasis: "muted"
                        }
                    }
                }

                // Fixed durations, not Motion tokens: this is a physical gesture rather
                // than a transition, and scaling it by a 2× motion preference turns a
                // sharp rejection into a wobble. The preference that DOES apply — motion
                // off — is honoured by not starting it.
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  9; duration: 45 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 65 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  5; duration: 60 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  0; duration: 55 }
                }

                Connections {
                    target: Greet
                    function onRejected() {
                        field.text = ""
                        field.forceActiveFocus()
                        if (Config.motionEnabled) shake.restart()
                    }
                }
            }

            // ── Caps Lock ─────────────────────────────────────────────────────
            // Directly under the field, above the feedback line, because that is where
            // you are already looking and because it has to arrive BEFORE the failure
            // it explains rather than after it.
            //
            // Warning-coloured but not shaped like an error: nothing has gone wrong
            // yet, and that is the entire point of showing it.
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacingMd
                implicitWidth:  capsRow.implicitWidth + Tokens.spacingLg * 2
                implicitHeight: 30

                visible: Greet.capsLock
                opacity: Greet.capsLock ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.corner(Config.barShape, height / 2)
                    color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.16)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.45)
                }

                RowLayout {
                    id: capsRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        glyph: "󰪛"
                        variant: "body"
                        color: Colors.of(QsWindow.window).warning
                    }
                    StyledText {
                        text: "Caps Lock is on"
                        variant: "caption"
                        font.bold: true
                        color: Colors.of(QsWindow.window).warning
                    }
                }
            }

            // ── One line of feedback ──────────────────────────────────────────
            // Fixed height and always present, so nothing under the field you are
            // typing in ever jumps. Carries the spinner too — one place to look for
            // "what is happening", whether that is "checking" or "wrong password".
            Item {
                Layout.fillWidth:  true
                Layout.topMargin:  Tokens.spacingLg
                implicitHeight: 18

                BusyDot {
                    anchors.centerIn: parent
                    running: Greet.phase === "busy" || Greet.phase === "launching"
                    tint:    Colors.of(QsWindow.window).focus
                }

                StyledText {
                    anchors.centerIn: parent
                    width:   parent.width
                    visible: Greet.phase !== "busy" && Greet.phase !== "launching"
                    horizontalAlignment: Text.AlignHCenter
                    text:    Greet.notice
                    variant: "caption"
                    color:   Greet.noticeIsError ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                    elide:   Text.ElideRight
                }
            }

            // From the second failure on. One wrong password is a typo, and saying
            // "1 failed attempt" about it is nagging.
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingXs
                visible: Greet.attempts > 1 && Greet.phase !== "busy"
                horizontalAlignment: Text.AlignHCenter
                text: Greet.attempts + " failed attempts"
                variant: "micro"
                color: Colors.of(QsWindow.window).fgDim
            }

            // ── Designing this without a greetd to talk to ────────────────────
            // Said out loud rather than shown as a broken box. Running greet.qml in
            // your own session is how the layout gets looked at, and a login screen
            // that silently swallows a password is a much worse thing to ship than
            // one that admits it is a mock-up.
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingLg
                visible: Greet.demoMode
                horizontalAlignment: Text.AlignHCenter
                text: "Preview — no greetd on this session, so nothing will be submitted."
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            // Which session Enter will start. Quiet, because it is a fact rather than
            // a control — the choice is made in Settings, on a machine you are already
            // logged into, and exported. There is nothing to pick here.
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingXl
                visible: Greet.session !== null && !Greet.demoMode
                horizontalAlignment: Text.AlignHCenter
                text: Greet.session ? Greet.session.name : ""
                // "micro" is 8px. On a 4K panel at arm's length that is not quiet, it is
                // absent — the screenshot has it as an illegible smudge. Caption keeps it
                // subordinate while leaving it readable, which is the actual intent.
                variant: "caption"
                color: Colors.of(QsWindow.window).fgMuted
            }
        }

        // ══ Restart and shut down ═════════════════════════════════════════════
        // Bottom right, and armed the same way as everywhere else in this shell:
        // picking an action does not fire it, a second and DIFFERENTLY PLACED click
        // does. Colour cannot carry the warning on this palette — `danger` and
        // `primary` can resolve to the same value — so the spelled-out consequence
        // and the moved target are what actually stop a misclick.
        //
        // No "log out": there is no session to leave. That is the whole difference
        // between this rail and the lock's, and it is why they are not one component.
        Process { id: runner }

        property string armed: ""

        readonly property var powerActions: [
            {
                key: "reboot", glyph: "󰜉", label: "Restart",
                detail: "Reboots the machine",
                tint: Colors.of(QsWindow.window).warning, cmd: ["systemctl", "reboot"]
            },
            {
                key: "shutdown", glyph: "󰐥", label: "Shut down",
                detail: "Powers the machine off",
                tint: Colors.of(QsWindow.window).danger, cmd: ["systemctl", "poweroff"]
            }
        ]

        readonly property var armedAction:
            surface.powerActions.find(a => a.key === surface.armed) ?? null

        function fire(action) {
            runner.command = action.cmd
            runner.running = true
        }

        Timer {
            id: disarm
            interval: 4000
            onTriggered: surface.armed = ""
        }
        onArmedChanged: {
            if (surface.armed !== "") disarm.restart()
            else                      disarm.stop()
        }

        RowLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingXxl
            spacing: Tokens.spacingMd

            visible: surface.interactive
            opacity: surface.revealLate
            transform: Translate { x: (1 - surface.revealLate) * 26 }

            // The confirmation comes FIRST in the row so it grows leftward, away from
            // the screen edge the rail is pinned to.
            Surface {
                visible: surface.armedAction !== null
                implicitWidth:  confirmRow.implicitWidth + Tokens.spacingLg * 2
                implicitHeight: 62
                elevation:    Tokens.elevationCard
                squareMode:   Config.barShape
                cornerRadius: Tokens.radiusCard
                fillOpacity:  Config.surfaceOpacity
                border.color: surface.armedAction ? surface.armedAction.tint
                                                  : Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)

                RowLayout {
                    id: confirmRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingMd

                    ColumnLayout {
                        spacing: 0

                        StyledText {
                            text: surface.armedAction ? surface.armedAction.label : ""
                            variant: "body"
                            font.bold: true
                            color: surface.armedAction ? surface.armedAction.tint : Colors.of(QsWindow.window).fg
                        }
                        StyledText {
                            text: surface.armedAction ? surface.armedAction.detail : ""
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }

                    PanelButton {
                        variant: "primary"
                        accent:  surface.armedAction ? surface.armedAction.tint : Colors.of(QsWindow.window).primary
                        label:   "Confirm"
                        onActivated: {
                            const a = surface.armedAction
                            surface.armed = ""
                            if (a) surface.fire(a)
                        }
                    }

                    PanelButton {
                        variant: "ghost"
                        implicitWidth:  26
                        implicitHeight: 26
                        glyph: "󰅖"
                        onActivated: surface.armed = ""
                    }
                }
            }

            // The rail: two glyphs, nothing written down. Deliberately quiet — these
            // are not what the screen is for.
            Surface {
                implicitWidth:  rail.implicitWidth + Tokens.spacingSm * 2
                implicitHeight: 52
                elevation:    Tokens.elevationCard
                squareMode:   Config.barShape
                cornerRadius: Tokens.radiusCard
                fillOpacity:  Config.surfaceOpacity

                RowLayout {
                    id: rail
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: surface.powerActions

                        Item {
                            id: railCell
                            required property var modelData

                            readonly property bool isArmed:
                                surface.armed === railCell.modelData.key

                            implicitWidth:  44
                            implicitHeight: 44

                            Rectangle {
                                anchors.fill: parent
                                radius: Tokens.corner(Config.barShape, width / 2)
                                color: railCell.isArmed   ? Colors.of(QsWindow.window).alpha(railCell.modelData.tint, 0.28)
                                     : railHover.hovered  ? Colors.of(QsWindow.window).surfaceHigh
                                     :                      "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    glyph: railCell.modelData.glyph
                                    font.family: Tokens.fontFamily
                                    variant: "headline"
                                    color: railCell.isArmed  ? railCell.modelData.tint
                                         : railHover.hovered ? Colors.of(QsWindow.window).fg
                                         :                     Colors.of(QsWindow.window).fgMuted
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                }
                            }

                            HoverHandler { id: railHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // Arming only. The Confirm button beside the rail is the
                                // only thing that can fire an action, so no amount of
                                // clicking in one spot turns the machine off.
                                onClicked: surface.armed =
                                    railCell.isArmed ? "" : railCell.modelData.key
                            }
                        }
                    }
                }
            }
        }
    }
}
