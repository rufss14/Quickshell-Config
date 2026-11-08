pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../services/lens.js" as L

// ── LensOverlay ───────────────────────────────────────────────────────────────
// What services/Lens read, over the screen it read it from. The region you dragged
// stays FROZEN (the capture, drawn exactly where it was) with the rest of the screen
// dimmed; each line of text gets a box — hover it, click it to copy that line. A
// toolbar beside the region: copy all, translate (and back), search, close.
//
// Translated, every box is painted over with its line's translation at the line's own
// place and height, wiping in left to right one line after another — the Lens look.
//
// While it reads (or translates) a band of the accent sweeps down the region: a busy
// indicator, so it isn't switched off with animations (Motion's category 3).
//
// Keys: Escape closes, Ctrl+C copies all, T translates / flips back. Needs EXCLUSIVE
// keyboard focus (CheatsheetPopup's reason); a click outside the region closes too.
//
// It fades out holding its own copy of what it showed (the fade rule): Lens clears
// its state on close, and bound straight to it the frozen picture would vanish first.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own, assigned by shell.qml — never redeclared.

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-lens"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.owns && Lens.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"

    // This screen, if the region is on it (slurp names the output; "<unknown>" falls
    // back to where its corner is).
    readonly property bool owns: {
        const r = Lens.region
        if (!r || !win.screen) return false
        if (r.output === win.screen.name) return true
        const known = Quickshell.screens.some(s => s.name === r.output)
        return !known && r.x >= win.screen.x && r.x < win.screen.x + win.screen.width
                      && r.y >= win.screen.y && r.y < win.screen.y + win.screen.height
    }
    readonly property bool shown: win.owns && Lens.open
    // 0 → 1 as it opens; the window stays mapped (and its content loaded) for the fade.
    property real amount: win.shown ? 1 : 0
    Behavior on amount {
        NumberAnimation { duration: Motion.surfaceDuration(win.shown); easing.type: Motion.surfaceEasing(win.shown) }
    }
    visible: win.owns && (Lens.open || win.amount > 0.01)

    // ── A copy of what's shown, kept through the fade ─────────────────────────
    property var    region: ({ x: 0, y: 0, w: 0, h: 0 })
    property string image: ""
    property int    imageW: 0
    property int    imageH: 0
    property var    lines: []
    property var    translated: []
    property bool   showTranslation: false
    Binding on region          { when: win.shown && Lens.region !== null; value: Lens.region ? L.local(Lens.region, win.screen.x, win.screen.y) : win.region; restoreMode: Binding.RestoreNone }
    Binding on image           { when: win.shown; value: Lens.image;           restoreMode: Binding.RestoreNone }
    Binding on imageW          { when: win.shown; value: Lens.imageW;          restoreMode: Binding.RestoreNone }
    Binding on imageH          { when: win.shown; value: Lens.imageH;          restoreMode: Binding.RestoreNone }
    Binding on lines           { when: win.shown; value: Lens.lines;           restoreMode: Binding.RestoreNone }
    Binding on translated      { when: win.shown; value: Lens.translated;      restoreMode: Binding.RestoreNone }
    Binding on showTranslation { when: win.shown; value: Lens.showTranslation; restoreMode: Binding.RestoreNone }

    readonly property bool translating: Lens.phase === "translating"
    readonly property bool reading: Lens.phase === "reading"

    // The line just copied (-2 = all), for the toolbar's word and the box's flash.
    property int copied: -1
    Timer { id: copiedBeat; interval: 1400; onTriggered: win.copied = -1 }
    function noteCopied(i) { win.copied = i; copiedBeat.restart() }

    // A closed lens costs nothing: the content exists only while the window is up.
    Loader {
        anchors.fill: parent
        active: win.visible
        sourceComponent: stageComponent
    }

    Component {
        id: stageComponent

        Item {
            id: stage
            anchors.fill: parent
            opacity: win.amount

            focus: true
            Connections {
                target: win
                function onShownChanged() { if (win.shown) stage.forceActiveFocus() }
            }
            Component.onCompleted: if (win.shown) stage.forceActiveFocus()
            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Escape) Lens.close()
                else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) { Lens.copyAll(); win.noteCopied(-2) }
                else if (e.key === Qt.Key_T) {
                    if (Lens.translated.length > 0) Lens.showTranslation = !Lens.showTranslation
                    else Lens.translate()
                } else return
                e.accepted = true
            }

            // ── The dim, with a click-away ────────────────────────────────────────
            Rectangle {
                anchors.fill: parent
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.55)
                TapHandler { onTapped: Lens.close() }
            }

            // ── The frozen region ─────────────────────────────────────────────────
            Item {
                id: frame
                x: win.region.x
                y: win.region.y
                width: win.region.w
                height: win.region.h

                // Clicks inside the region don't count as "away".
                MouseArea { anchors.fill: parent }

                Image {
                    anchors.fill: parent
                    source: win.image !== "" ? "file://" + win.image : ""
                    cache: false
                    asynchronous: false
                    smooth: true
                    fillMode: Image.Stretch
                }

                // The outline: drawn in from a little way out as it opens.
                Rectangle {
                    property real spread: win.shown ? 0 : Tokens.spacingLg
                    Behavior on spread { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }
                    anchors.fill: parent
                    anchors.margins: -Tokens.borderChrome - spread
                    radius: Tokens.radiusSm
                    color: "transparent"
                    border.width: Tokens.borderChrome
                    border.color: Colors.of(QsWindow.window).primary
                }

                // Reading: a band of the accent sweeping down (a busy indicator).
                Item {
                    anchors.fill: parent
                    clip: true
                    visible: win.reading || win.translating
                    Rectangle {
                        id: band
                        width: parent.width
                        height: Math.max(Tokens.spacingXl, parent.height / 4)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.85; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.35) }
                            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).primary }
                        }
                        NumberAnimation on y {
                            running: win.reading || win.translating
                            loops: Animation.Infinite
                            from: -band.height
                            to: frame.height
                            duration: 1100
                            easing.type: Motion.ambient
                        }
                    }
                }
            }

            // ── The lines ─────────────────────────────────────────────────────────
            Repeater {
                model: win.lines

                Item {
                    id: box
                    required property var modelData
                    required property int index
                    readonly property var at: L.place(box.modelData, win.region, win.imageW, win.imageH)
                    readonly property real pad: 2
                    readonly property bool hot: boxMouse.containsMouse
                    readonly property string translation: win.translated[box.index] ?? ""

                    x: box.at.x - box.pad
                    y: box.at.y - box.pad
                    width: box.at.w + box.pad * 2
                    height: box.at.h + box.pad * 2

                    // In one after another.
                    property real arrive: 0
                    Component.onCompleted: box.arrive = 1
                    Behavior on arrive {
                        SequentialAnimation {
                            PauseAnimation { duration: Math.min(box.index * Motion.stagger, Motion.staggerCap) }
                            NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                        }
                    }
                    opacity: Math.min(1, box.arrive)
                    scale: 0.92 + 0.08 * box.arrive

                    // Original: a highlight to point at.
                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusXs
                        color: win.copied === box.index ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).success, 0.35)
                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, box.hot ? 0.28 : 0.12)
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, box.hot ? 0.9 : 0.45)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }
                    }

                    // Translated: painted over, wiping in left to right, line after line.
                    Item {
                        id: wipe
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        clip: true
                        readonly property bool on: win.showTranslation && box.translation !== ""
                        property real reveal: wipe.on ? 1 : 0
                        Behavior on reveal {
                            SequentialAnimation {
                                PauseAnimation { duration: wipe.on ? Math.min(box.index * Motion.stagger * 2, Motion.staggerCap * 2) : 0 }
                                NumberAnimation { duration: wipe.on ? Motion.emphasized : Motion.exit
                                                  easing.type: wipe.on ? Motion.enter : Motion.exitCurve }
                            }
                        }
                        width: box.width * wipe.reveal
                        visible: wipe.reveal > 0.001

                        Rectangle {
                            width: box.width
                            height: box.height
                            radius: Tokens.radiusXs
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard), 0.97)
                            border.width: Tokens.borderWidth
                            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, box.hot ? 0.9 : 0.3)

                            StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: box.pad + 1
                                anchors.rightMargin: box.pad + 1
                                verticalAlignment: Text.AlignVCenter
                                text: box.translation
                                color: win.copied === box.index ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fg
                                font.pixelSize: Math.max(Tokens.fontMicro, Math.round(box.at.h * 0.8))
                                fontSizeMode: Text.Fit
                                minimumPixelSize: Tokens.fontMicro
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: boxMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Lens.copyLine(box.index); win.noteCopied(box.index) }
                    }
                }
            }

            // ── The toolbar ───────────────────────────────────────────────────────
            Surface {
                id: bar
                elevation: Tokens.elevationCard
                cornerRadius: Tokens.radiusCard
                implicitWidth: barCol.implicitWidth + Tokens.spacingMd * 2
                implicitHeight: barCol.implicitHeight + Tokens.spacingSm * 2
                width: implicitWidth
                height: implicitHeight
                readonly property var at: L.toolbar(win.region, bar.width, bar.height, win.width, win.height,
                                                    Tokens.spacingMd, Tokens.spacingMd)
                x: bar.at.x
                y: bar.at.y + (win.shown ? 0 : Tokens.spacingLg)
                Behavior on y { NumberAnimation { duration: Motion.surfaceDuration(win.shown); easing.type: Motion.surfaceEasing(win.shown) } }

                MouseArea { anchors.fill: parent }

                Column {
                    id: barCol
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Tokens.spacingXs
                        PanelButton {
                            enabled: win.lines.length > 0
                            variant: "ghost"
                            symbol: win.copied === -2 ? "check" : "content_copy"
                            label: win.copied === -2 ? "Copied" : "Copy"
                            onActivated: { Lens.copyAll(); win.noteCopied(-2) }
                        }
                        PanelButton {
                            enabled: win.lines.length > 0 && !win.translating
                            variant: win.showTranslation ? "primary" : "ghost"
                            symbol: "translate"
                            label: win.translating ? "Translating…"
                                 : win.showTranslation ? "Original"
                                 : "Translate → " + Lens.target.toUpperCase()
                            onActivated: {
                                if (Lens.translated.length > 0) Lens.showTranslation = !Lens.showTranslation
                                else Lens.translate()
                            }
                        }
                        PanelButton {
                            enabled: win.lines.length > 0
                            variant: "ghost"
                            symbol: "search"
                            onActivated: { Lens.search(); Lens.close() }
                        }
                        PanelButton {
                            variant: "ghost"
                            symbol: "close"
                            onActivated: Lens.close()
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property string status:
                            Lens.error !== "" ? Lens.error + (Lens.install !== "" ? " — pacman -S " + Lens.install : "")
                            : win.reading ? "Reading…"
                            : win.translating ? "Translating " + win.lines.length + " lines…"
                            : win.showTranslation && Lens.via !== "" ? "Translated via " + Lens.via + " · click a line to copy it"
                            : win.lines.length + (win.lines.length === 1 ? " line" : " lines") + " · click one to copy it · T translates"
                        text: status
                        variant: "caption"
                        color: Lens.error !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                    }
                }
            }
        }
    }
}
