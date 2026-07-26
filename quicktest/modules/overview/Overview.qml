import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../settings"

// ── Overview ──────────────────────────────────────────────────────────────────
// The full-screen overlay. Steam-overlay shaped: a see-through dim over your live
// desktop, with everything you might want floating on top of it.
//
//     ┌──────────────────────────────────────────────────────┐
//     │ [power]          [now playing]              09:41    │
//     │                                       Mon, 13 July   │
//     │          ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐          │
//     │          └────┘ └────┘ └────┘ └────┘ └────┘   drag   │
//     │          ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐  windows │
//     │          └────┘ └────┘ └────┘ └────┘ └────┘          │
//     │                                                      │
//     │ [calendar]      [ dock ]           [timer/stopwatch] │
//     └──────────────────────────────────────────────────────┘
//
// Everything is ON the overlay. There is no panel-over-the-grid mechanism any more:
// the calendar and the timer are cards in the corners, and power is a button, not a
// screen-covering Card. `UiState.overviewPanel` is gone with them.
//
// It also replaces a SEPARATE QUICKSHELL PROCESS. The overview used to be its own
// shell with its own palette, its own widget library, and its own Hyprland data layer
// that spawned four `hyprctl` processes per event. It's now part of this one, on this
// one's tokens.
//
// Nothing here exists while it's closed: the window is unmapped, the Hypr service is
// released (no refreshes), and the live window captures are torn down.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    required property var screen

    readonly property var hyprMonitor: Hypr.monitorFor(root.screen)
    readonly property bool monitorFocused: Hyprland.focusedMonitor?.name === hyprMonitor?.name

    // Only the focused monitor shows the overview — mirroring it onto every screen
    // would mean several grids fighting over one keyboard focus.
    readonly property bool shown: UiState.overviewOpen && root.monitorFocused

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-overview"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive
                                            : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    visible: root.shown || backdrop.opacity > 0.005

    readonly property int edge: Tokens.spacingXxl * 2

    // ── Which page the overview is on ─────────────────────────────────────────
    //     0 = settings   ←  A       1 = main (home)      D  →   2 = notifications
    //
    // Main is the MIDDLE page, not the first, so both side pages are one key away and
    // the geometry matches the keys: settings really is to the left of home. That's why
    // `pageMain` is a named constant rather than a literal 1 — this numbering is
    // load-bearing in about six places and an off-by-one in any of them lands you on
    // the wrong page.
    readonly property int pageSettings: 0
    readonly property int pageMain:     1
    readonly property int pageNotifs:   2

    // Always resets to main when the overview closes, so it reopens where you expect.
    property int page: root.pageMain

    // ── Live-data lifecycle ───────────────────────────────────────────────────
    // Hypr only refreshes window geometry while something holds a reference. Open
    // ⇒ acquire; close ⇒ release, and the shell stops asking Hyprland anything.
    property bool _held: false
    function _sync() {
        if (root.shown === _held) return
        if (root.shown) Hypr.acquire()
        else          { Hypr.release(); root.page = root.pageMain }
        _held = root.shown
    }
    onShownChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: if (_held) Hypr.release()

    // A bar module (Settings, Notifications) asked to open to a specific page.
    // Bumped on every request so it navigates even when the overview is already
    // open — `overviewOpen = true` handles opening it if it wasn't.
    Connections {
        target: UiState
        function onOverviewNavChanged() {
            root.page = UiState.overviewTarget === "notifs"   ? root.pageNotifs
                      : UiState.overviewTarget === "settings" ? root.pageSettings
                      :                                         root.pageMain
        }
    }

    // ── Backdrop ──────────────────────────────────────────────────────────────
    // Deliberately see-through (was 0.82, a near-opaque grey wash that read as no
    // theme at all on a desaturated palette). At ~0.58 the desktop stays visible
    // underneath, which is what makes this read as an *overlay* rather than as a
    // separate screen you switched to.
    //
    // The dim alone is colourless, so the palette is carried by a low-alpha accent
    // gradient over the top of it — present enough to tint the whole surface, far too
    // faint to fight the window previews for attention.
    Rectangle {
        id: backdrop
        anchors.fill: parent

        // Deliberately see-through. The compositor blurs this layer (an `hl.layer_rule`
        // on the `quickshell-overview` namespace), and the blur is what separates the
        // overlay from the desktop — so the dim only has to take the edge off, not do
        // the work. A heavier dim on top of a blur just makes the desktop disappear,
        // and then it isn't an overlay any more, it's a screen.
        color: Colors.alpha(Colors.surface, 0.35)
        opacity: root.shown ? 1.0 : 0.0
        visible: opacity > 0.005

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(root.shown)
                easing.type: Motion.surfaceEasing(root.shown)
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Colors.alpha(Colors.focus,   0.10) }
                GradientStop { position: 0.5; color: Colors.alpha(Colors.surface, 0.00) }
                GradientStop { position: 1.0; color: Colors.alpha(Colors.primary, 0.12) }
            }
        }

        // Swallows clicks on the backdrop WITHOUT dismissing. Click-to-dismiss used to
        // live here and was a hazard on the settings pages: any click that missed a
        // control — a mis-aimed tap at a checkbox, releasing a slider off its track,
        // clicking away from the password field — closed the whole overview and lost
        // what you were doing. Escape still closes it, and that is deliberate rather
        // than accidental.
        //
        // The MouseArea stays so the backdrop keeps absorbing clicks instead of letting
        // them fall through to whatever sits behind.
        MouseArea {
            anchors.fill: parent
        }
    }

    // ── Entrance ──────────────────────────────────────────────────────────────
    // The overlay rises AND settles out of a slight zoom, rather than just fading.
    // Scale is what sells it: a pure fade reads as a picture being turned up, where a
    // surface that resolves out of 96% reads as something arriving in front of you.
    //
    // The scale is anchored to the CENTRE, and it's small — 0.96, not 0.8. A big zoom
    // on a full-screen surface is nausea, not polish, and it drags every one of the
    // grid's live captures through a resample for the duration.
    //
    // Exit is faster than enter and accelerates away (Motion.surfaceDuration/Easing
    // handle both from the one `shown` flag): the user has already decided they're
    // done, and every frame after that is the UI arguing.
    Item {
        id: stage
        anchors.fill: parent

        // ── Keyboard ──────────────────────────────────────────────────────────
        // The handler lives on `stage` — the ANCESTOR of every page — and not on a
        // sibling Item, which is where it used to be and why Escape stopped working the
        // moment you clicked into a text field.
        //
        // Qt Quick delivers a key event to whatever holds active focus and then bubbles it
        // UP THE PARENT CHAIN until something accepts it. A sibling is not on that chain,
        // so once a TextInput (a password box, a search field) took focus, nothing here
        // ever saw another keystroke. As an ancestor it sees everything the focused item
        // declined — which is exactly the right rule:
        //
        //   · Escape isn't consumed by TextInput, so it bubbles and closes the overview.
        //   · "a" and "1" ARE consumed while you're typing, so the page no longer flips
        //     sideways when you type a letter into a field. That was the same bug wearing
        //     the opposite face, and moving the handler fixes both at once.
        focus: root.shown

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                // Escape dismisses anything TRANSIENT first — an open context menu, a
                // primed power action — and otherwise closes the overview outright.
                //
                // It used to step back to the main page first, so closing from settings
                // or notifications took two presses. That treated the pages as a stack
                // when they aren't: A/D move sideways between three peers, and Escape on
                // a peer should mean "I'm done", not "go to the middle one". The
                // transient checks stay, because those genuinely ARE layered on top.
                if (dockMenu.opened)         dockMenu.close()
                else if (power.armed !== "")  power.armed = ""
                else                          UiState.overviewOpen = false
                event.accepted = true
                return
            }

            // A / D step one page left / right, clamped rather than wrapping — a
            // wrap would send you from settings to notifications, which are opposite
            // ends of the overview and nothing like neighbours.
            if (event.key === Qt.Key_D) {
                root.page = Math.min(root.pageNotifs, root.page + 1)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_A) {
                root.page = Math.max(root.pageSettings, root.page - 1)
                event.accepted = true
                return
            }

            // 1-9 / 0 jump straight to a workspace on the current page.
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                Hypr.focusWorkspace(grid.firstWorkspace + (event.key - Qt.Key_1))
                UiState.overviewOpen = false
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_0) {
                Hypr.focusWorkspace(grid.firstWorkspace + 9)
                UiState.overviewOpen = false
                event.accepted = true
            }
        }

        opacity: root.shown ? 1.0 : 0.0
        y:       root.shown ? 0   : 18
        scale:   root.shown ? 1.0 : 0.94
        transformOrigin: Item.Center

        // The overlay ENTERS on the emphasized curve at `spatial` — it's a whole screen
        // of content arriving, and 220ms of OutCubic made it snap into place rather than
        // arrive. It still LEAVES fast (exit stays short and accelerates away): the user
        // has already decided they're done, and every frame after that is the UI arguing.
        Behavior on opacity {
            NumberAnimation {
                duration: root.shown ? Motion.spatial : Motion.exit
                easing.type: root.shown ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.shown ? Motion.spatial : Motion.exit
                easing.type: root.shown ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.shown ? Motion.spatial : Motion.exit
                easing.type: root.shown ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }

        // ══ PAGE 0 — the main overview ═════════════════════════════════════════
        // Everything but the clock and dock lives here. It slides fully off to the left
        // when you move to the notification page.
        //
        // The slide is a Translate driven by a plain `slide` property (Behavior can ease
        // a property; it can't ease a Translate's x directly), so the page glides on the
        // same emphasized curve the overlay enters on.
        Item {
            id: page0
            anchors.fill: parent

            property real slide: (root.pageMain - root.page) * width
            transform: Translate { x: page0.slide }
            Behavior on slide {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasizedDecel
                }
            }

            // ── Power — top left ──────────────────────────────────────────────
            PowerPanel {
                id: power
                anchors.left: parent.left
                anchors.top:  parent.top
                anchors.leftMargin: root.edge
                anchors.topMargin:  root.edge
            }

            // ── Media + brightness — top centre ───────────────────────────────
            // Lyrics · player · brightness sliders, centred as one unit. The media
            // cards collapse to nothing when no player exists; the brightness sliders
            // do NOT (they aren't media), so the row is never empty on a machine with a
            // controllable display.
            Row {
                id: media
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: root.edge
                spacing: Tokens.spacingLg

                OverviewLyrics {
                    id: lyrics
                    // Fed from the media card's clock rather than starting a second one —
                    // two timers following the same number would drift, and the lyrics
                    // and the progress bar would disagree about where the song is.
                    player:   nowPlaying.player
                    position: nowPlaying.pos
                }

                OverviewNowPlaying {
                    id: nowPlaying
                }

                OverviewBrightness {
                    anchors.top: parent.top
                }
            }

            // ── Workspaces — the band between the two rows ────────────────────
            // The grid gets the free band explicitly (measured from the two rows) and
            // shrinks to fit, rather than centring blindly and sliding under the corner
            // cards. `glance`/`dock` are persistent siblings referenced by id — still
            // valid across the page boundary.
            Item {
                id: gridArea

                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.top:    parent.top
                anchors.bottom: parent.bottom

                anchors.leftMargin:  root.edge
                anchors.rightMargin: root.edge

                readonly property real topRow: Math.max(power.implicitHeight,
                                                        media.height,
                                                        glance.height)
                readonly property real bottomRow: Math.max(calendar.implicitHeight,
                                                           dock.implicitHeight,
                                                           timer.implicitHeight)

                anchors.topMargin:    root.edge + topRow    + Tokens.spacingXxl
                anchors.bottomMargin: root.edge + bottomRow + Tokens.spacingXxl

                WorkspaceGrid {
                    id: grid
                    anchors.centerIn: parent
                    monitor: root.hyprMonitor

                    maxWidth:  gridArea.width
                    maxHeight: gridArea.height
                }
            }

            // ── Calendar — bottom left ────────────────────────────────────────
            CalendarCard {
                id: calendar
                anchors.left:   parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin:   root.edge
                anchors.bottomMargin: root.edge
            }

            // ── Timer / stopwatch — bottom right ──────────────────────────────
            TimerCard {
                id: timer
                anchors.right:  parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin:  root.edge
                anchors.bottomMargin: root.edge
            }

            // ── To the notification page ──────────────────────────────────────
            PanelButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: root.edge
                variant: "normal"
                implicitWidth:  40
                implicitHeight: 64
                glyph: "󰅂"
                onActivated: root.page = root.pageNotifs
            }

            // ── Left, to settings ─────────────────────────────────────────────
            PanelButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: root.edge
                variant: "normal"
                implicitWidth:  40
                implicitHeight: 64
                glyph: "󰅁"
                onActivated: root.page = root.pageSettings
            }
        }

        // ══ PAGE 0 — settings ══════════════════════════════════════════════════
        // One screen-width LEFT of main, so A reaches it and the geometry agrees with
        // the key.
        //
        // Nothing else is on this page — no clock, no dock. Those are drawn by the
        // persistent chrome below, which is gated to skip this page: settings is a
        // workspace you're doing something in, not a glance surface, and the card wants
        // every pixel it can get. A dock along the bottom would cost it 90px to show
        // you launchers you didn't come here for.
        Item {
            id: page2
            anchors.fill: parent

            property real slide: (root.pageSettings - root.page) * width
            transform: Translate { x: page2.slide }
            Behavior on slide {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasizedDecel
                }
            }

            // ── Back to main ──────────────────────────────────────────────────
            PanelButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: root.edge
                variant: "normal"
                implicitWidth:  40
                implicitHeight: 64
                glyph: "󰅂"
                onActivated: root.page = root.pageMain
            }

            // ── The card ──────────────────────────────────────────────────────
            // Everything except the chevron's gutter and a margin. It's the only thing
            // here, so it gets the page.
            //
            // Loader-gated on the page being reachable rather than always built: the
            // card's pages shell out (specs.sh, localectl) and the visualizer preview
            // starts cava, all the moment they're constructed — and the overview opens
            // on main. Building it eagerly would run every one of those probes each
            // time you tapped the overview to glance at a workspace.
            //
            // The `slide` half of the test keeps it alive for the whole animation:
            // gating on `page === pageSettings` alone would build it mid-slide (popping
            // in) and destroy it the instant you started sliding away.
            Loader {
                anchors.fill: parent
                anchors.margins: root.edge
                anchors.rightMargin: root.edge + 40 + Tokens.spacingXl

                active: root.page === root.pageSettings || page2.slide > -page2.width
                sourceComponent: SettingsCard {}
            }
        }

        // ══ PAGE 2 — notifications ═════════════════════════════════════════════
        // One screen-width right of main. Empty but for the notification centre and the
        // back chevron — the clock and dock (persistent, below) fill the rest.
        Item {
            id: page1
            anchors.fill: parent

            property real slide: (root.pageNotifs - root.page) * width
            transform: Translate { x: page1.slide }
            Behavior on slide {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasizedDecel
                }
            }

            // ── Back to the main page ─────────────────────────────────────────
            PanelButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: root.edge
                variant: "normal"
                implicitWidth:  40
                implicitHeight: 64
                glyph: "󰅁"
                onActivated: root.page = root.pageMain
            }

            // Right below the clock, growing DOWNWARD as notifications pile up. No
            // bottom anchor, so its height follows its content; `maxListHeight` is the
            // room from under the clock to just above the dock, so a full inbox scrolls
            // inside the card rather than colliding with either.
            //
            // `glance` (the clock) lives on the persistent-chrome layer, not this page,
            // so it can't be an anchor target across the tree — but its height is a
            // plain property read, which is all the top offset needs.
            OverviewNotifications {
                id: notifCentre

                readonly property real topOffset: root.edge + glance.height + Tokens.spacingLg

                anchors.right: parent.right
                anchors.top:   parent.top
                anchors.rightMargin: root.edge
                anchors.topMargin:   notifCentre.topOffset

                maxListHeight: parent.height - notifCentre.topOffset
                    - (root.edge + dock.height + Tokens.spacingLg)   // above the dock
                    - 120                                            // header + chrome
            }

            // ── Clipboard — bottom left ───────────────────────────────────────
            // Diagonally opposite the inbox, in the same card language and under the
            // same grow-with-content contract — but anchored to the BOTTOM, so it
            // grows UPWARD. Two cards hanging from the top would leave the page
            // bottom-heavy with dead space; anchored at opposite corners they frame it.
            //
            // It shares the dock's baseline (both sit `root.edge` off the bottom) so
            // the two read as standing on one line rather than being independently
            // placed. The dock is centred and this is 400 wide at the far left, so
            // they don't compete for the same room.
            //
            // Its CEILING is the back chevron, not the top of the page: the chevron
            // sits at left-of-centre, and a long history growing upward would run
            // straight into it.
            OverviewClipboard {
                id: clipCard

                // Underside of the chevron (vertically centred, 64 tall), plus a gap.
                readonly property real ceiling:
                    parent.height / 2 + 32 + Tokens.spacingLg

                anchors.left:   parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin:   root.edge
                anchors.bottomMargin: root.edge

                maxListHeight: parent.height - root.edge - clipCard.ceiling
                    - 120                                            // header + chrome
            }
        }

        // ══ PERSISTENT CHROME ══════════════════════════════════════════════════
        // Declared last ⇒ painted on top of whichever page is showing.
        //
        // Persistent across main and notifications, but NOT settings — that page is the
        // card and nothing else. Both fade rather than blink out, so stepping left from
        // main is one continuous movement instead of the clock vanishing a frame before
        // the slide begins.
        readonly property bool chromeShown: root.page !== root.pageSettings

        // ── Clock — top right ─────────────────────────────────────────────────
        Column {
            id: glance
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.rightMargin: root.edge
            anchors.topMargin:   root.edge
            spacing: Tokens.spacingXs

            opacity: stage.chromeShown ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }

            // One timer, gated on the overview being open — a clock nobody can see has no
            // business ticking.
            property date now: new Date()
            Timer {
                interval: 1000
                running: root.shown
                repeat: true
                triggeredOnStart: true
                onTriggered: glance.now = new Date()
            }

            StyledText {
                anchors.right: parent.right
                text: Qt.formatDateTime(glance.now, "HH:mm")
                font.family: Tokens.fontMono
                font.pixelSize: 68
                font.weight: Font.Bold
                font.letterSpacing: 2
                color: Colors.fg
            }
            StyledText {
                anchors.right: parent.right
                text: Qt.formatDateTime(glance.now, "dddd, d MMMM")
                variant: "title"
                emphasis: "muted"
            }
        }

        // ── Dock — bottom centre ──────────────────────────────────────────────
        OverviewDock {
            id: dock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.edge

            opacity: stage.chromeShown ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }

            contextMenu: dockMenu
        }
    }

    // ── The dock's context menu ───────────────────────────────────────────────
    // Deliberately a sibling of `stage`, not a child of the dock:
    //
    //   • `stage` has an animated y-offset, so coordinates inside it are not scene
    //     coordinates while the overlay is entering. The menu positions itself from
    //     the scene position of the cursor, so it must live in a container that IS the
    //     scene.
    //   • a menu parented into the dock could only open within the dock's 72px, at the
    //     very bottom of the screen — which is precisely where a menu cannot go.
    //
    // Declared last ⇒ painted last ⇒ above everything, without a z fight.
    ContextMenu {
        id: dockMenu
        anchors.fill: parent
    }
}
