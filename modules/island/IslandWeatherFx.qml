import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services/island.js" as Rules

// ── IslandWeatherFx ───────────────────────────────────────────────────────────
// What the weather looks like, behind a card: rain as slanted streaks falling, snow as flakes drifting down and
// swaying, cloud and fog as soft shapes sliding across, a clear sky as a slow sunburst (a moon's disc at night), and a
// storm as rain with a pale flash now and then. Clipped to the card's rounded corners (ClippingRectangle), drawn in the
// text colour at low alpha so it never fights the content, and only moving while `active` and the shell's ambient motion
// are on (a still frame of it stays when they are not). Nothing is created for a kind it is not showing.
//
// One clock drives the whole sky (`phase`, 0 → 1, looping): every drop, flake and cloud is placed by a function of it
// and its own seed. So the sky costs one animation, it starts scattered (a drop per animation all set off from the top
// at once and drew a row of streaks along the edge), and a still frame is a scattered sky too. Speeds are whole
// multiples of the loop, so it wraps without a jump.
// ─────────────────────────────────────────────────────────────────────────────
ClippingRectangle {
    id: root

    property int  code: 0
    property bool isDay: true
    property bool active: true
    // The tone the sky is drawn in.
    property color tone: Colors.of(QsWindow.window).fg

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property string kind: Rules.weatherKind(root.code, root.isDay)
    readonly property bool moving: root.active && Motion.ambientOn

    color: "transparent"

    property real phase: 0
    NumberAnimation on phase {
        from: 0
        to: 1
        duration: root.kind === "snow" ? 10000 : (root.kind === "cloud" || root.kind === "fog") ? 60000 : 2400
        loops: Animation.Infinite
        running: root.moving && root.kind !== "clear"
    }
    function frac(v) { return v - Math.floor(v) }

    // ── Rain and storm ────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: root.kind === "rain" || root.kind === "storm"
        sourceComponent: Item {
            Repeater {
                model: 22
                delegate: Rectangle {
                    id: drop
                    required property int index
                    // A fixed scatter from the index, so a card draws the same sky every time.
                    readonly property real seed: ((drop.index * 7919) % 101) / 101
                    x: (drop.index / 22) * (root.width + 40) - 20
                    y: root.frac(root.phase * (1 + drop.index % 2) + drop.seed) * (root.height + drop.height) - drop.height
                    width: 1.5
                    height: Tokens.spacingXl * (0.8 + drop.seed)
                    radius: 1
                    rotation: 14
                    color: root.palette.alpha(root.tone, 0.10 + 0.10 * drop.seed)
                }
            }
        }
    }
    // The storm's flash.
    Rectangle {
        anchors.fill: parent
        visible: root.kind === "storm"
        color: root.palette.alpha(root.tone, 0.10)
        opacity: 0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: root.moving && root.kind === "storm"
            PauseAnimation { duration: 3200 }
            NumberAnimation { to: 1; duration: 60 }
            NumberAnimation { to: 0; duration: 140 }
            NumberAnimation { to: 0.7; duration: 50 }
            NumberAnimation { to: 0; duration: 420 }
        }
    }

    // ── Snow ──────────────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: root.kind === "snow"
        sourceComponent: Item {
            Repeater {
                model: 16
                delegate: Rectangle {
                    id: flake
                    required property int index
                    readonly property real seed: ((flake.index * 6151) % 97) / 97
                    x: (flake.index / 16) * root.width + 14 * Math.sin(2 * Math.PI * (root.phase * (2 + flake.index % 3) + flake.seed))
                    y: root.frac(root.phase * (1 + flake.index % 2) + flake.seed) * (root.height + flake.height) - flake.height
                    width: 3 + flake.seed * 3
                    height: width
                    radius: width / 2
                    color: root.palette.alpha(root.tone, 0.18 + 0.2 * flake.seed)
                }
            }
        }
    }

    // ── Cloud and fog ─────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: root.kind === "cloud" || root.kind === "fog"
        sourceComponent: Item {
            Repeater {
                model: 3
                delegate: MorphShape {
                    id: puff
                    required property int index
                    width: root.height * (0.9 + 0.35 * puff.index)
                    height: width * (root.kind === "fog" ? 0.5 : 0.8)
                    x: root.frac(root.phase + puff.index / 3) * (root.width + puff.width) - puff.width
                    y: root.height * (0.05 + 0.28 * puff.index) - height * 0.2
                    shape: puff.index === 1 ? "squircle" : "cookie9"
                    turns: false
                    fillColor: root.palette.alpha(root.tone, 0.05 + 0.02 * puff.index)
                }
            }
        }
    }

    // ── Clear ─────────────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: root.kind === "clear"
        sourceComponent: Item {
            MorphShape {
                id: sun
                width: root.height * 1.5
                height: width
                anchors.right: parent.right
                anchors.rightMargin: -width * 0.28
                anchors.top: parent.top
                anchors.topMargin: -width * 0.32
                shape: root.isDay ? "sunny" : "circle"
                turns: false
                fillColor: root.palette.alpha(root.tone, root.isDay ? 0.07 : 0.05)
                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 70000
                    loops: Animation.Infinite
                    running: root.moving && root.isDay
                }
            }
        }
    }
}
