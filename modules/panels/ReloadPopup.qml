import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"

// ── ReloadPopup ───────────────────────────────────────────────────────────────
// A card under the bar when a configuration reload FAILS (and, if you ask for it, when one
// succeeds), in place of Quickshell's own: what went wrong in one line, the full text below
// it, a Copy button, and a line along the bottom edge running down to when it goes away.
// Click it to dismiss; rest the pointer on it to keep it. services/ReloadWatch hears the
// reloads (and stops Quickshell's own card); this draws them.
//
// ── Built like a notification ─────────────────────────────────────────────────
// The same card, corner and elevation as NotificationToast, and it starts where BarToastHost's
// deck does (Config.belowBar) so it never covers the bar — an earlier version sat 24px down
// and clipped it.
//
// ── Pass/fail colours are Verdict's ───────────────────────────────────────────
// "It worked" and "it broke" must not depend on what the wallpaper's palette landed on
// (config/Verdict.qml says why), so the icon, its holder and the countdown use Verdict.tint(),
// which also carries the Config.colorizeIcons opt-out.
//
// ── Keeps its own copy ────────────────────────────────────────────────────────
// What the card shows is copied when an event arrives and never cleared, so the fade-out
// isn't spent on an empty card. One screen shows it (ScreenOwner). Its own namespace; no
// keyboard focus — the shell is in the middle of being edited and must never steal the
// editor's keys.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-reload"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top:   true
    anchors.left:  true
    anchors.right: true
    implicitHeight: Config.belowBar + card.height + Tokens.spacingXxl
    color: "transparent"

    // Only the card takes the mouse; the rest of the strip is the desktop's.
    mask: Region { item: card }

    // ── What it shows ─────────────────────────────────────────────────────────
    property bool   open: false
    property bool   heldFailed: false
    property string heldText: ""
    // How long a card stays: a success is a blink, a failure is for reading.
    readonly property int stayMs: win.heldFailed ? 14000 : 1800

    // The root cause in one line: Quickshell's error is a chain ("caused by …" per level), and
    // the last link is the one that names the file and what is wrong with it.
    readonly property var lines: win.heldText.split("\n").map(s => s.trim()).filter(s => s !== "")
    readonly property string cause: win.lines.length === 0 ? ""
        : win.lines[win.lines.length - 1].replace(/^caused by\s*/, "").replace(/^@/, "")

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: win.open
    }

    visible: win.owns && (win.open || card.opacity > 0.01)

    Connections {
        target: ReloadWatch
        function onSerialChanged() {
            if (!ReloadWatch.wanted) return
            win.heldFailed = ReloadWatch.failed
            win.heldText = ReloadWatch.error
            win.open = true
            stay.restart()
        }
    }

    // The time left, 1 → 0. Paused while the pointer is on the card, so an error can be read
    // to the end. Interaction timing, not a Motion duration: with motion off those are 0 and
    // the card would vanish the instant it appeared.
    property real remaining: 1
    NumberAnimation {
        id: stay
        target: win
        property: "remaining"
        from: 1
        to: 0
        duration: win.stayMs
        paused: hover.hovered
        onFinished: win.open = false
    }

    SurfaceShadow { surface: card }
    Surface {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.open ? Config.belowBar + Tokens.spacingMd : Config.belowBar - card.height
        Behavior on y {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.open)
                easing.type: Motion.surfaceEasing(win.open)
            }
        }

        elevation: Tokens.elevationCard
        cornerRadius: Tokens.radiusCard
        focused: hover.hovered
        clip: true
        width: Math.min(460, win.width - Tokens.spacingXxl * 2)
        height: col.implicitHeight + Tokens.spacingLg * 2
        opacity: win.open ? Tokens.surfaceOpacity : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.open)
                easing.type: Motion.surfaceEasing(win.open)
            }
        }

        HoverHandler { id: hover }
        TapHandler { onTapped: win.open = false }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // The icon in the shell's holder, tinted pass/fail.
                ShapeBox {
                    implicitWidth: 36
                    implicitHeight: 36
                    fallback: "rounded"
                    fillColor:   Colors.of(QsWindow.window).alpha(Verdict.tint(!win.heldFailed), 0.20)
                    strokeColor: Colors.of(QsWindow.window).alpha(Verdict.tint(!win.heldFailed), 0.32)
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: win.heldFailed ? "error" : "check_circle"
                        fill: 1
                        variant: "headline"
                        color: Verdict.tint(!win.heldFailed)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    RowLayout {
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm + 2
                        StyledText {
                            text: win.heldFailed ? Translation.tr("Reload") : Translation.tr("Shell")
                            variant: "title"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: win.heldFailed ? Translation.tr("failed") : Translation.tr("reloaded")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: Verdict.tint(!win.heldFailed)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: win.heldFailed && win.cause !== ""
                        text: win.cause
                        variant: "caption"
                        emphasis: "muted"
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: !win.heldFailed
                        text: Translation.tr("The new configuration is running")
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                ActionGroup {
                    groupShown: win.heldFailed && win.heldText !== ""
                    PanelButton {
                        symbol: "content_copy"
                        variant: "ghost"
                        onActivated: Clipboard.copyText(win.heldText)
                    }
                }
            }

            // The whole error, as Quickshell wrote it — in a well of its own, so it reads as
            // output and not as more of the card's prose.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: win.heldFailed && win.lines.length > 1
                implicitHeight: detail.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

                StyledText {
                    id: detail
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    text: win.lines.join("\n")
                    variant: "caption"
                    emphasis: "muted"
                    font.family: Tokens.fontMono
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 8
                    elide: Text.ElideRight
                }
            }
        }

        // The time left, as a line along the bottom edge.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: Tokens.spacingXs
            width: parent.width * win.remaining
            color: Verdict.tint(!win.heldFailed)
            opacity: 0.8
        }
    }
}
