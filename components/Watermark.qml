import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"

// ── Watermark ─────────────────────────────────────────────────────────────────
// [Quickshell mark] "Quicktest v<Config.version> by rufss", with a shine that travels across the name
// every few seconds. One component, so the desktop, the lock screen and the overview wear
// the same mark; each places it (the overview's middle card and the settings rail, both
// bottom left). There is no switch for it — it is always on where it is mounted.
//
// ── A pill, not bare text ─────────────────────────────────────────────────────
// Bare caption text at 85% over a wallpaper was too easy to lose — it can land on
// anything, in any brightness. The pill is the shell's own surface (the same fill and
// border the bar's pills wear), so the mark reads on a busy picture and sits in the same
// language as everything else.
//
// ── The logo ──────────────────────────────────────────────────────────────────
// Quickshell's own mark (assets/logos, third-party — see its README). Full colour by
// default, the same exception the About page and welcome panel take; with
// Config.colorizeIcons on, the mono cut stencilled in the screen's accent, which is what
// that switch means everywhere else (tray, dock).
//
// ── The shine ─────────────────────────────────────────────────────────────────
// ONE number, `phase`, runs from before the first letter to past the last, and every
// effect below is a function of it — so they cannot drift apart, and there is a single
// animation to start and stop:
//
//   • each letter turns to the accent as the sweep reaches it, rises a little and swells
//     (`lit`), then settles back — a wave through the name, not a colour wipe;
//   • a soft glow of the accent rides behind the name, at the sweep's position;
//   • the pill's border catches the accent while the sweep is on (`glow`, an envelope);
//   • the gear logo makes one full turn over the sweep;
//   • a sparkle pops at the end of the name as the sweep leaves it (`spark`).
//
// That is a few colour mixes and four opacities per frame for under two seconds, then
// nothing for the rest of the cycle — a pause, not a slow tween, so the surface this sits
// on goes idle between sweeps (Motion.settle's reason).
//
// The colours are palette roles (text → the screen's accent), never a fixed gradient. The
// name rests brighter than the words around it, so it reads as the signature.
//
// ── Motion ────────────────────────────────────────────────────────────────────
// Category 2 in Motion's terms — a fixed ambient timing, which scaling would distort
// rather than adjust. Honoured by not STARTING when Config.motionEnabled is off, and the
// phase is put back by hand when it stops (stopping is not resetting): everything is then
// simply at rest.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property var    pal:    Colors.of(QsWindow.window)
    readonly property string author: "rufss"

    property int pixelSize: Tokens.fontTitle
    property int iconSize:  Tokens.iconLg
    // The pill's horizontal padding.
    property int pad:       Tokens.spacingLg
    // Logo only: for a place too narrow for the words (a collapsed settings rail).
    property bool compact: false

    // Whether the sweep runs. A surface that is mapped but hidden (a closed overview, a
    // covered desktop) passes false so it costs nothing.
    property bool active: true

    // Letters of reach either side of the sweep's centre, and where it starts and ends:
    // far enough out that no letter is lit at either end.
    readonly property real _reach: 1.6
    readonly property real _rest:  -root._reach - 0.5
    readonly property real _end:   root.author.length - 1 + root._reach + 0.5

    property real phase: root._rest

    // How far through the sweep, 0..1, and what is derived from it.
    readonly property real sweep: Math.max(0, Math.min(1, (root.phase - root._rest) / (root._end - root._rest)))
    // 0 → 1 → 0 across the whole sweep: the border and the glow's strength.
    readonly property real glow:  Math.sin(Math.PI * root.sweep)
    // A pop over the last third, as the shine leaves the final letter.
    readonly property real spark: root.sweep < 0.62 ? 0 : Math.sin(Math.PI * (root.sweep - 0.62) / 0.38)

    implicitWidth:  row.implicitWidth  + root.pad * 2
    implicitHeight: row.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.corner(Config.barShape, root.height / 2)
    color:  root.pal.alpha(root.pal.surfaceHigh, Config.surfaceOpacity)
    border.width: Tokens.borderWidth
    border.color: root.pal.outline

    // The border catching the light: the accent over the resting outline, only while the
    // sweep is on.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: Tokens.borderWidth
        border.color: root.pal.primary
        opacity: root.glow * 0.8
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        Loader {
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: Config.colorizeIcons ? tinted : plain
            // One full turn per sweep, so it is square again at rest.
            rotation: root.sweep * 360
        }

        StyledText {
            visible: !root.compact
            Layout.alignment: Qt.AlignVCenter
            text: "Quicktest v" + Config.version
            font.pixelSize: root.pixelSize
            font.weight: Font.DemiBold
            color: root.pal.fg
        }
        StyledText {
            visible: !root.compact
            Layout.alignment: Qt.AlignVCenter
            text: "by"
            font.pixelSize: root.pixelSize
            color: root.pal.fgMuted
        }

        Item {
            id: nameBox
            visible: !root.compact
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  letters.implicitWidth
            implicitHeight: letters.implicitHeight

            // The glow behind the name: a soft horizontal band that rides with the sweep.
            // Kept inside the pill's own padding at either end, so it never spills past
            // the border.
            Rectangle {
                readonly property real bandW:   nameBox.width * 0.7
                readonly property real centre:  nameBox.width * (root.phase + 0.5) / root.author.length
                x: Math.max(-Tokens.spacingSm, Math.min(nameBox.width - bandW + Tokens.spacingSm, centre - bandW / 2))
                y: -Tokens.spacingXs
                width:  bandW
                height: nameBox.height + Tokens.spacingXs * 2
                radius: height / 2
                opacity: root.glow
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.pal.alpha(root.pal.primary, 0) }
                    GradientStop { position: 0.5; color: root.pal.alpha(root.pal.primary, 0.38) }
                    GradientStop { position: 1.0; color: root.pal.alpha(root.pal.primary, 0) }
                }
            }

            Row {
                id: letters

                Repeater {
                    model: root.author.length

                    StyledText {
                        id: letter
                        required property int index
                        // 0 at rest, 1 when the sweep's centre is on this letter.
                        readonly property real lit: Math.max(0, 1 - Math.abs(root.phase - letter.index) / root._reach)

                        text: root.author.charAt(letter.index)
                        font.pixelSize: root.pixelSize
                        font.weight: Font.Bold
                        color: root.pal.mix(root.pal.fg, root.pal.primary, Math.min(1, letter.lit * 1.4))
                        // Rises and swells under the sweep. Render transforms, so the row's
                        // own layout never moves.
                        scale: 1 + letter.lit * 0.22
                        transformOrigin: Item.Bottom
                        transform: Translate { y: -letter.lit * Tokens.spacingXs }
                    }
                }
            }

            // The sparkle: pops, turns a quarter, and is gone, at the name's trailing edge.
            MaterialIcon {
                anchors.horizontalCenter: nameBox.right
                anchors.verticalCenter:   nameBox.top
                name: "auto_awesome"
                fill: 1
                color: root.pal.primary
                font.pixelSize: Tokens.iconMd
                opacity: root.spark
                scale:    0.4 + root.spark * 0.8
                rotation: root.spark * 90
            }
        }
    }

    Component {
        id: tinted
        TintedIcon {
            source: Icons.logo("quickshell-mono.svg")
            color:  root.pal.primary
            size:   root.iconSize
        }
    }
    Component {
        id: plain
        Image {
            source: Icons.logo("quickshell.svg")
            sourceSize: Qt.size(root.iconSize, root.iconSize)
            width:  root.iconSize
            height: root.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    SequentialAnimation {
        running: Motion.ambientOn && root.active && root.visible

        // A short first wait, so it is seen soon after appearing; then a long rest between.
        PauseAnimation { duration: 900 }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation {
                target: root; property: "phase"
                from: root._rest; to: root._end
                duration: 1700
                easing.type: Motion.ambient
            }
            PauseAnimation { duration: 3600 }
        }
        onRunningChanged: if (!running) root.phase = root._rest
    }
}
