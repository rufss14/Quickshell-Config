pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ClockWidget ───────────────────────────────────────────────────────────────
// Analog at small, digital at medium — the way the macOS and iOS clock widgets do it,
// and for the reason they do it: a 168px square is the wrong shape for a wide digital
// time. The first version rendered "13:15:09" at 38px into a 140px content box and it
// visibly overflowed the tile. A dial has no such problem — it is square, it fills a
// square, and it reads at a glance.
//
// The tick is gated on `active`, which the layer drives from whether the widget is on
// screen at all. A clock nobody can see must not be waking the process once a second.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    // Set by the host from the widget's stored accent role. Defaults to the palette's
    // primary so a widget rendered outside the layer (a settings preview) still looks
    // right without the caller having to know about accents.
    property color accent: Colors.primary

    readonly property bool seconds: root.opts.seconds === true
    readonly property bool hour24:  root.opts.hour24 !== false

    // ── Which face ────────────────────────────────────────────────────────────
    // Size picks the DEFAULT — a dial for the square small tile, digits for the wide
    // medium one — and a tap overrides it. Stored per widget, so the choice survives a
    // reload; unset means "whatever suits the size", which is what a freshly placed
    // clock should do rather than committing you to a face you never chose.
    readonly property bool analog:
        root.opts.face === undefined ? root.size === "small"
                                     : root.opts.face === "analog"

    function tileTap() {
        if (root.widgetId < 0) return       // a preview must not write to the store
        DesktopWidgets.setOpt(root.widgetId, "face", root.analog ? "digital" : "analog")
    }

    property date now: new Date()

    Timer {
        // A face showing seconds needs a second-accurate tick; one showing only minutes
        // does not, and polling 60× more often than the display can change is exactly
        // the per-frame waste this shell avoids. The analog face always sweeps seconds.
        interval: (root.seconds || root.analog) ? 1000 : 15000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // ══ ANALOG — small ════════════════════════════════════════════════════════
    Item {
        id: dial
        anchors.centerIn: parent
        visible: root.analog
        width:  Math.min(parent.width, parent.height)
        height: width

        readonly property real r: width / 2
        readonly property int  h: root.now.getHours()
        readonly property int  m: root.now.getMinutes()
        readonly property int  s: root.now.getSeconds()

        // Face: barely-there fill and a hairline ring. The hands are the content, and a
        // heavy dial competes with them at this size.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.alpha(Colors.fg, 0.05)
            border.width: 1
            border.color: Colors.alpha(Colors.fg, 0.12)
        }

        // Twelve hour ticks, quarters longer — enough structure to read an angle
        // against, without the clutter of sixty minute ticks at this diameter.
        Repeater {
            model: 12
            Rectangle {
                id: tick
                required property int index
                readonly property bool quarter: tick.index % 3 === 0
                width:  tick.quarter ? 2 : 1
                height: tick.quarter ? 9 : 5
                radius: width / 2
                color: Colors.alpha(Colors.fg, tick.quarter ? 0.55 : 0.28)
                antialiasing: true
                x: dial.r - width / 2
                y: 7
                // Swung about the dial's centre: the tick sits at the top and rotates
                // into place, so the origin is its own centre-x and the distance down
                // to the middle of the face.
                transform: Rotation {
                    origin.x: tick.width / 2
                    origin.y: dial.r - 7
                    angle: tick.index * 30
                }
            }
        }

        // ── Hands ─────────────────────────────────────────────────────────────
        // Hours and minutes move CONTINUOUSLY, not in steps: a real hour hand is most
        // of the way to 4 at 3:55, and stepping it leaves the face reading wrong for
        // most of every hour.
        Hand { length: dial.r * 0.48; thickness: 4;   colour: Colors.fg
               angle: (dial.h % 12) * 30 + dial.m * 0.5 }
        Hand { length: dial.r * 0.70; thickness: 3;   colour: Colors.fg
               angle: dial.m * 6 + dial.s * 0.1 }
        Hand { length: dial.r * 0.76; thickness: 1.5; colour: root.accent
               angle: dial.s * 6; tail: dial.r * 0.16 }

        // Cap, over the hand roots so their square ends never show.
        Rectangle {
            anchors.centerIn: parent
            width: 7; height: 7; radius: 3.5
            color: root.accent
            antialiasing: true
        }
        Rectangle {
            anchors.centerIn: parent
            width: 3; height: 3; radius: 1.5
            color: Colors.surfaceFor(Tokens.elevationCard)
            antialiasing: true
        }
    }

    // ══ DIGITAL — medium ══════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        visible: !root.analog
        spacing: 0

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now,
                  (root.hour24 ? "HH:mm" : "h:mm") + (root.seconds ? ":ss" : ""))
            font.family: Tokens.fontMono
            font.pixelSize: 54
            font.weight: Font.DemiBold
            font.letterSpacing: -2
            color: Colors.fg
            // Shrinks to fit rather than spilling past the tile. With seconds on the
            // string is eight characters, and a fixed size overflowed the widget — this
            // is what makes it impossible for any combination of options to do that.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 20
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                  + (root.hour24 ? "" : "  " + Qt.formatDateTime(root.now, "AP"))
            variant: "caption"
            emphasis: "muted"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }

    // A clock hand: a rounded bar pinned at the dial's centre and rotated about it.
    // `tail` is the counterweight sticking out the far side, which is what makes the
    // second hand read as a second hand rather than as a thin minute hand.
    component Hand: Rectangle {
        id: hand
        property real length: 10
        property real thickness: 2
        property real angle: 0
        property real tail: 0
        property color colour: Colors.fg

        width:  hand.thickness
        height: hand.length + hand.tail
        radius: hand.thickness / 2
        color:  hand.colour
        antialiasing: true

        x: dial.r - hand.thickness / 2
        y: dial.r - hand.length

        transform: Rotation {
            origin.x: hand.thickness / 2
            origin.y: hand.length
            angle: hand.angle
        }
    }
}
