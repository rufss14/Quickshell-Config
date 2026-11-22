pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"

// ── ReloadCard ────────────────────────────────────────────────────────────────
// The card a configuration reload leaves on screen: what went wrong in one line, the whole
// chain below it, a Copy chip, and a capsule along the foot that runs down to when the card
// goes away. It holds its own state (an event arrives from services/ReloadWatch, the card
// opens, a countdown closes it) and says nothing about WHERE it stands: a host places it.
//
// ── Two hosts, one card ───────────────────────────────────────────────────────
//   • modules/bar/BarReloadHost, inside Bar's own window, where the blob draws the card (`welded`):
//     it comes out from under the bar and goes back into it. Quicktest.Blobs can only fuse shapes
//     that share one scene graph, which is why the card cannot be its own window and weld.
//   • modules/panels/ReloadPopup, a window of its own: what still draws over a FULLSCREEN window
//     (the bar is a Top layer surface, hidden under one), and where the plugin is not built.
// Exactly one is `live` at a time (the same rule BarToastHost / NotificationOverlay keep), so an
// event opens one card.
//
// ── Pass / fail colours are Verdict's ─────────────────────────────────────────
// "It worked" and "it broke" must not depend on what the wallpaper's palette landed on
// (config/Verdict.qml says why), so the badge and the countdown use Verdict.tint().
//
// ── Keeps its own copy ────────────────────────────────────────────────────────
// What it shows is copied when an event arrives and never cleared, so the way out is not spent
// on an empty card. One screen shows it (ScreenOwner: the monitor you were on when it opened).
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    // The screen this instance stands on, and whether it may open for an event.
    property var  screen: null
    property bool live: false
    // The blob draws this card: no stroke, no shadow, and no fill while it paints the cookies.
    property bool welded: false
    // The widest the card gets; the host knows how much room it has.
    property real maxWidth: 460

    // ── What it shows ─────────────────────────────────────────────────────────
    property bool   open: false
    property bool   heldFailed: false
    property string heldText: ""
    // How long a card stays: a success is a blink, a failure is for reading.
    readonly property int stayMs: root.heldFailed ? 14000 : 1800

    // The root cause in one line: Quickshell's error is a chain ("caused by …" per level), and
    // the last link is the one that names the file and what is wrong with it.
    readonly property var lines: root.heldText.split("\n").map(s => s.trim()).filter(s => s !== "")
    readonly property string cause: root.lines.length === 0 ? ""
        : root.lines[root.lines.length - 1].replace(/^caused by\s*/, "").replace(/^@/, "")

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: root.screen
        open: root.open
    }

    // 0 away, 1 in place. The host moves the card by it.
    property real reveal: root.open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: Motion.surfaceDuration(root.open)
            easing.type: Motion.surfaceEasing(root.open)
        }
    }

    // Standing at all: open, or still on its way out.
    readonly property bool shown: root.owns && (root.open || root.reveal > 0.01)

    readonly property color tint: Verdict.tint(!root.heldFailed)
    readonly property var palette: Colors.of(QsWindow.window)

    Connections {
        target: ReloadWatch
        function onSerialChanged() {
            if (!root.live || !ReloadWatch.wanted) return
            root.heldFailed = ReloadWatch.failed
            root.heldText = ReloadWatch.error
            root.open = true
            stay.restart()
        }
    }

    // The time left, 1 → 0. Paused while the pointer is on the card, so an error can be read
    // to the end. Interaction timing, not a Motion duration: with motion off those are 0 and
    // the card would vanish the instant it appeared.
    property real remaining: 1
    NumberAnimation {
        id: stay
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: root.stayMs
        paused: hover.hovered
        onFinished: root.open = false
    }

    function dismiss() { root.open = false }

    // A line of the chain as styled text: "caused by" dim, the file in bold, where in it in the tint.
    function _esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function rich(line) {
        const dim = String(root.palette.fgDim)
        const hot = String(root.palette.fg)
        let t = root._esc(line)
        t = t.replace(/^caused by\s*/, '<font color="' + dim + '">caused by </font>')
        t = t.replace(/@([^\s\[]+)\[(\d+:\d+)\]/g,
                      '<b><font color="' + hot + '">$1</font></b><font color="' + String(root.tint) + '">:$2</font>')
        return t
    }

    // ── The face ──────────────────────────────────────────────────────────────
    elevation: Tokens.elevationCard
    cornerRadius: Tokens.radiusCard
    focused: hover.hovered
    clip: true
    width: Math.min(460, root.maxWidth)
    height: col.implicitHeight + Tokens.spacingLg * 2
    borderWidth: root.welded ? 0 : Tokens.borderWidth
    // Welded while the blob draws the cookie field, the blob paints this fill (the same
    // Colors.surface) with the cookies in it; painted again it would hide them.
    fillOpacity: root.welded && Drift.inBlob ? 0 : 1
    // A lobe of the bar casts no shadow onto the bar it is made of.
    castsShadow: !root.welded

    HoverHandler { id: hover }
    TapHandler { onTapped: if (!copyChip._hot) root.dismiss() }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            // The verdict, as a badge: a disc that blooms into a shape as the card arrives.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                MorphShape {
                    anchors.fill: parent
                    shape: root.open ? (root.heldFailed ? "clover" : "cookie9") : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: root.tint
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.heldFailed ? "error" : "check_circle"
                    fill: 1
                    variant: "headline"
                    color: root.palette.shadow
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
                        text: root.heldFailed ? Translation.tr("Reload") : Translation.tr("Shell")
                        variant: "title"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: root.heldFailed ? Translation.tr("failed") : Translation.tr("reloaded")
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: root.tint
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.heldFailed && root.cause !== ""
                    text: root.cause
                    variant: "caption"
                    emphasis: "muted"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                StyledText {
                    visible: !root.heldFailed
                    text: Translation.tr("The new configuration is running")
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            ChipButton {
                id: copyChip
                Layout.alignment: Qt.AlignVCenter
                visible: root.heldFailed && root.heldText !== ""
                tonal: true
                symbol: root.copied ? "check" : "content_copy"
                label: root.copied ? Translation.tr("Copied") : Translation.tr("Copy")
                onActivated: {
                    Clipboard.copyText(root.heldText)
                    root.copied = true
                    copiedReset.restart()
                }
            }
        }

        // The whole chain as Quickshell wrote it, in a well one tone up from the card so it reads as
        // output and not as more of the card's prose. No outline: the tone is the edge.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.heldFailed && root.lines.length > 1
            implicitHeight: detail.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusSm
            color: root.palette.plate

            StyledText {
                id: detail
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                rich: true
                text: root.lines.map(l => root.rich(l)).join("<br>")
                variant: "caption"
                emphasis: "muted"
                font.family: Tokens.fontMono
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 8
                elide: Text.ElideRight
            }
        }

        // The time left, a capsule on a track.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.spacingXs
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.palette.alpha(root.palette.fg, 0.08)
            }
            Rectangle {
                height: parent.height
                width: Math.max(height, parent.width * root.remaining)
                radius: height / 2
                color: root.tint
                opacity: 0.85
            }
        }
    }

    // Copy says it was heard for a moment.
    property bool copied: false
    Timer { id: copiedReset; interval: 1400; onTriggered: root.copied = false }
}
