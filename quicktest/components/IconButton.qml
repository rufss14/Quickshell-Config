import QtQuick
import QtQuick.Effects
import "../config"

// ── IconButton ────────────────────────────────────────────────────────────────
// The shell's one interactive control. Every bar button, dock button, and panel
// action is this.
//
// It exists to enforce the state ladder, which every button previously
// re-derived for itself — and they disagreed. Some had press states, some
// didn't. The "active" (panel-open) look was `btnActiveBg` in most places, a
// hand-rolled `pw(color1, 0.15)` in UpdateButton, and `pw(color4, 0.20)` in
// WifiButton. The ladder is now one expression:
//
//   idle    → no fill, muted foreground
//   hover   → primary @ 0.18 fill, primary foreground
//   pressed → primary @ 0.35 fill
//   active  → primary @ 0.22 fill, primary foreground   (toggled on)
//
// hover wins over active when both apply, because hover is the more immediate
// feedback — the user is asking "will this respond to me", and the answer has to
// come before "is this already on".
//
// ── container ─────────────────────────────────────────────────────────────────
// ON by default: every control sits in its own inset pill.
//
// The bar used to run two visual languages side by side — flat toggle buttons
// next to pill-wrapped readouts like the clock and the wifi indicator — which is
// precisely what made it read as incoherent. Now the pill is universal, so the
// bar has one rhythm: a group pill, containing inset pills, containing controls.
//
// The state ladder still layers ON TOP of the resting pill, so a fill continues
// to mean "this responded to you" — it's just drawn over a surface rather than
// over nothing. Set `container: false` for a control that must be chromeless.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string glyph: ""

    // ── `icon` is a url, and that changes how you test it for "empty" ─────────
    // `root.icon === ""` compares a url to a STRING and is therefore always false —
    // which would hide the glyph unconditionally and leave the bar blank. The code used
    // `==` to dodge that via coercion, which works but reads like an oversight and
    // invites exactly the "fix" that breaks it.
    //
    // `String(root.icon) === ""` says what it means: resolve the url, then compare
    // strings. Type-safe, and no longer a trap for the next person (or the next linter).
    property url icon: ""
    property string label: ""

    property bool active:     false     // toggled on (e.g. its panel is open)
    property bool squareMode: false     // barShape
    property bool container:   true     // inset pill at rest (see below). Default: yes.
    property bool interactive: true

    // ── Scaled by the bar's settings, not raw tokens ──────────────────────────
    // A `glyph` is a Nerd Font ICON that happens to be a character, so it scales with
    // the icons — not with barFontScale, which is for text you read. `label` is the only
    // real text here (the clock, the layout tag, an SSID), so it's the only thing the
    // font scale touches.
    //
    // Defaults, so a caller that sets its own size still wins. IconButton reads Config
    // directly rather than being told: it already does for barRoundness, and it is a bar
    // component — the settings page's preview is built from these same pills, which is
    // why the preview scales for free.
    property int iconSize:  Math.round(Tokens.iconMd    * Config.barIconScale)
    property int glyphSize: Math.round(Tokens.fontTitle * Config.barIconScale)
    property int labelSize: Math.round(Tokens.fontBody  * Config.barFontScale)

    // ── accent ────────────────────────────────────────────────────────────────
    // The colour this button's state ladder is built from. Defaults to `primary`,
    // which is what the ladder used to name directly — so the default is byte-for-byte
    // the old behaviour, and only a module the user has deliberately recoloured differs.
    //
    // It's a property rather than a Colors lookup because the CALLER knows which module
    // this is; the button doesn't, and shouldn't have to.
    property color accent: Colors.primary

    // Foreground override — for controls that color their icon by state rather
    // than by interaction (the wifi pill tints by signal strength).
    property color iconColor: root.fg

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    // Config.barRoundness, not Tokens.radiusPill: the bar's corner is a user setting
    // now. This is safe to key off Config because IconButton is bar-only — panels use
    // PanelButton and the dock has its own icon. Tokens still supplies the DEFAULT that
    // Config starts from.
    readonly property int  cornerRadius: Tokens.corner(squareMode, Config.barRoundness)

    // Extra content (badges, indicator dots) layers on top of the fill.
    default property alias content: overlay.data

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int delta)          // +1 up, -1 down

    // What the pill actually has to hold. Tokens.pillHeight is the floor rather than the
    // answer: with the icon or font scale turned up, fixing the height at 24 would just
    // clip the thing that grew.
    readonly property int contentExtent: root.label !== "" ? Math.ceil(labelText.implicitHeight)
                                       : root.glyph !== "" ? Math.ceil(glyphText.implicitHeight)
                                       :                     root.iconSize

    implicitHeight: Math.max(Tokens.pillHeight, root.contentExtent + Tokens.spacingXs * 2)
    // Math.ceil, not a raw sum: label width comes from FONT METRICS, which are
    // fractional. A pill landing on x=142.37 puts its 1px border across two device
    // pixels, and antialiasing smears it into a soft ~2px line — the border looks
    // thicker than it is. Snapping the pill to whole pixels keeps it a hairline.
    implicitWidth:  label !== ""
        ? Math.ceil(labelText.implicitWidth) + Tokens.pillPadding * 2
        : Math.max(Tokens.pillIconWidth, root.contentExtent + Tokens.pillPadding * 2)

    readonly property color fg: (root.hovered || root.pressed || root.active)
        ? root.accent
        : Colors.stateIdleFg

    // ── Resting surface ───────────────────────────────────────────────────────
    // `container` is now the DEFAULT: every control in the bar sits in its own
    // inset pill. The bar previously had two languages at once — flat toggle
    // buttons next to pill-wrapped readouts like the clock — which is what made
    // it read as incoherent.
    //
    // Elevation Nested, not Bar. This pill sits INSIDE the group pill, and an
    // outline tuned for sitting on a wallpaper (alpha 0.12) is invisible against
    // another surface's own fill — the nested thing then looks like the parent
    // simply changed size. This is the exact case the Nested elevation exists for,
    // and it's why the old code needed a bespoke `nestedPillBorder` constant.
    Rectangle {
        anchors.fill: parent
        radius:  root.cornerRadius
        visible: root.container
        color:        Colors.surfaceFor(Tokens.elevationNested)
        border.width: Tokens.borderWidth
        border.color: Colors.outlineFor(Tokens.elevationNested)

        Behavior on radius       { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        Behavior on color        { ColorAnimation  { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation  { duration: Motion.respond } }
    }

    // ── State fill ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius

        // The same alphas Colors.state*Bg encodes (0.35 / 0.18 / 0.22), applied to this
        // button's accent rather than to `primary` unconditionally.
        color: !root.interactive ? "transparent"
             : root.pressed      ? Colors.alpha(root.accent, 0.35)
             : root.hovered      ? Colors.alpha(root.accent, 0.18)
             : root.active       ? Colors.alpha(root.accent, 0.22)
             :                     "transparent"

        Behavior on color  { ColorAnimation  { duration: Motion.respond; easing.type: Motion.respondCurve } }
        Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    Text {
        id: glyphText
        visible: root.glyph !== "" && String(root.icon) === ""
        anchors.centerIn: parent
        text:  root.glyph
        color: root.iconColor
        font.family:    Tokens.fontFamily
        font.pixelSize: root.glyphSize
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // Loader-gated rather than an always-present Image with `visible: false`.
    // An Image still *loads* its source when hidden, and an empty url resolves
    // to Quickshell's `qs-blackhole` placeholder, which then fails to open — one
    // "Cannot open: qrc:/qs-blackhole" warning per glyph- or label-only button.
    // Not constructing it at all is both quieter and cheaper.
    Loader {
        active: String(root.icon) !== ""
        anchors.centerIn: parent

        // The asset is TINTED to the same state ladder the glyph icons follow,
        // not drawn as-is: every SVG in assets/icons is baked `fill="#e3e3e3"`,
        // which is fine on a dark pill and *invisible on a light one* — the
        // wallpaper and palette buttons vanished entirely in light mode. With
        // colorization the file's own colour stops mattering, exactly like a
        // font glyph's doesn't.
        sourceComponent: Item {
            width:  root.iconSize
            height: root.iconSize

            Image {
                id: assetImg
                anchors.fill: parent
                source: root.icon
                sourceSize: Qt.size(root.iconSize, root.iconSize)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: false
            }

            MultiEffect {
                anchors.fill: assetImg
                source: assetImg
                colorization: 1.0
                colorizationColor: root.fg

                Behavior on colorizationColor {
                    ColorAnimation { duration: Motion.respond }
                }
            }
        }
    }

    Text {
        id: labelText
        visible: root.label !== "" && root.glyph === "" && String(root.icon) === ""
        anchors.centerIn: parent
        text:  root.label
        color: root.iconColor
        font.family:    Tokens.fontFamily
        font.pixelSize: root.labelSize
        font.bold: true
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    Item {
        id: overlay
        anchors.fill: parent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: function(m) {
            if (m.button === Qt.RightButton)       root.rightClicked()
            else if (m.button === Qt.MiddleButton) root.middleClicked()
            else                                   root.clicked()
        }
        onWheel: function(w) { root.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
