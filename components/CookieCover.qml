pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../config"
import "../services"
import "../services/cookie.js" as Cookie

// ── CookieCover ───────────────────────────────────────────────────────────────
// An album cover in a cookie: the picture shows through a Scallop silhouette that turns
// slowly while the track plays, with a ring of level bars standing off its edge. The
// media panel's hero. The look is borrowed from Caelestia's media tab; the code is this
// shell's own (Scallop for the shape, Cava for the spectrum, services/cookie.js for the
// ring's geometry).
//
// ── The picture does not turn, the cookie does ────────────────────────────────
// The silhouette rotates INSIDE a layer used as the picture's mask, so the art stays
// upright and the petals sweep across it. (Rotating the mask source item itself would
// do nothing: a layer renders its item without its own transform — the rotation has to
// be on a CHILD.)
//
// ── The ring breathes with the petals ─────────────────────────────────────────
// Each bar starts a gap outside the cookie's edge AT ITS OWN ANGLE, and the cookie turns
// underneath it, so the inner end of every bar slides in and out as petals pass while
// the bars themselves stand still. The silhouette's radius at an angle is Scallop's own
// formula, in cookie.js, where a test keeps the two in step.
//
// ── What it costs, and when ───────────────────────────────────────────────────
// Nothing while `live` is false (the panel closed, another page showing): the turn is
// paused and the spectrum released. Paused while the track is, too — the ring settles to
// dots and the cookie stops where it is. The spectrum is the shared `Cava` service's, held
// by refcount against the player's OWN node (the same way OverviewLyrics and the bar's
// visualiser do), so this starts no process of its own and ignores a call in the background.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property url    source: ""
    property bool   playing: false
    // On screen and awake: gates every piece of per-frame work.
    property bool   live: true
    // The player's own PipeWire node, so the ring answers THIS player and not whatever
    // else shares the speakers. "" = no ring movement (dots).
    property string nodeName: ""
    property color  accent: Colors.of(QsWindow.window).primary

    property int  points:     9
    property real petalDepth: 0.1

    // ── The ring ──────────────────────────────────────────────────────────────
    readonly property int  barCount: Math.max(8, Cava.barCount)
    readonly property real gap:   Tokens.spacingSm       // edge → shortest bar
    readonly property real reach: Tokens.spacingXl       // longest bar
    readonly property real thick: Tokens.spacingXs * 1.5

    // What is left for the cover once the ring has its room all the way round.
    readonly property real coverSize: Math.max(0, Math.min(root.width, root.height) - 2 * (root.gap + root.reach))
    // Scallop insets itself by 1.5 so a stroke isn't clipped; the ring must measure from
    // the same radius.
    readonly property real rMax: root.coverSize / 2 - 1.5

    // Degrees, counter-clockwise (the direction it is designed in), one turn in 23.5s.
    // Paused rather than stopped, so it resumes from where it was instead of jumping back.
    property real turn: 0
    NumberAnimation on turn {
        from: 360
        to: 0
        duration: 23500
        loops: Animation.Infinite
        running: true
        paused: !(root.live && root.playing)
    }

    // ── The spectrum ──────────────────────────────────────────────────────────
    readonly property bool wantsCava: root.live && root.playing && root.nodeName !== ""
                                      && !Gamemode.hidesVisualizer
    property bool _cavaHeld: false

    function _syncCava() {
        if (root.wantsCava) {
            if (!root._cavaHeld) { Cava.acquireSource(root.nodeName); root._cavaHeld = true }
            else                 Cava.sourceName = root.nodeName
        } else if (root._cavaHeld) {
            Cava.releaseSource()
            root._cavaHeld = false
        }
    }
    onWantsCavaChanged: root._syncCava()
    onNodeNameChanged:  root._syncCava()
    // A destroyed panel must not pin cava on.
    Component.onDestruction: if (root._cavaHeld) Cava.releaseSource()

    // 0..1 per bar, shaped to be looked at; empty (so: dots) when not held.
    readonly property var levels: root._cavaHeld
        ? Cava.resample(Cava.shape(Cava.sourceBars || [], 1.25), root.barCount) : []

    // ── The cookie ────────────────────────────────────────────────────────────
    Item {
        id: cover
        width:  root.coverSize
        height: root.coverSize
        anchors.centerIn: parent

        // The silhouette as a mask. A layer, hidden: it is only ever read by the effect.
        Item {
            id: silhouette
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Scallop {
                anchors.fill: parent
                points: root.points
                petalDepth: root.petalDepth
                fillColor: "white"
                rotation: root.turn
            }
        }

        // The ground, seen where there is no picture (none yet, or still loading).
        Scallop {
            anchors.fill: parent
            points: root.points
            petalDepth: root.petalDepth
            fillColor: Colors.of(QsWindow.window).alpha(root.accent, 0.18)
            rotation: root.turn
        }

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: silhouette
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image {
                anchors.fill: parent
                source: root.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                mipmap: true
                // 2× what is drawn: art off a player is whatever it shipped, often huge.
                sourceSize: Qt.size(root.coverSize * 2, root.coverSize * 2)
                // Fades in once decoded, so a track change is a dissolve rather than a
                // blank flash.
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.slow } }
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: root.source.toString() === ""
            name: "music_note"
            fill: 0
            font.pixelSize: Tokens.iconXl
            color: root.accent
        }
    }

    // ── The ring ──────────────────────────────────────────────────────────────
    // Each bar is a zero-size Item at the centre, turned to its angle, with the dash laid
    // along its +x axis: moving the dash outward is just `x`, and its length is `width`.
    Repeater {
        model: root.barCount
        delegate: Item {
            id: bar
            required property int index

            readonly property real theta: Cookie.barAngle(bar.index, root.barCount)

            x: root.width / 2
            y: root.height / 2
            rotation: bar.theta * 180 / Math.PI

            Rectangle {
                x: Cookie.edgeDist(bar.theta, root.turn * Math.PI / 180,
                                   root.rMax, root.petalDepth, root.points) + root.gap
                y: -height / 2
                width:  Cookie.barLength(root.levels[bar.index], root.thick, root.reach)
                height: root.thick
                radius: height / 2
                color: root.accent
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
        }
    }
}
