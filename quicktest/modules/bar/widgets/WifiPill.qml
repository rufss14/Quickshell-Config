import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── WifiPill ──────────────────────────────────────────────────────────────────
// Signal glyph, optionally with the SSID beside it. Left-click opens the wifi
// panel; right-click collapses to icon-only.
//
// Was WifiButton, which ran a `sh -c "nmcli radio wifi; nmcli dev wifi list |
// grep | head"` pipeline every 8 seconds — twice, since the bar built both
// layouts. State could be 8s stale, so the indicator would sit on a dead network
// for seconds after a disconnect.
//
// Now it reads Network (NetworkManager over D-Bus, pushed). Note it does NOT
// scan: the *connected* network is known without scanning, which is all an
// indicator ever needed. Scanning only happens while the panel is open.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.focus

    property bool active:    false
    // ── collapsed: local by default, persisted on request ────────────────
    // Right-click toggles this. Transient unless the module is opted into
    // "remember" (Settings → Bar → this module), in which case Config holds it and
    // it survives a reload.
    //
    // `_persist` is read once at construction rather than bound, on purpose. If it
    // were a live binding, turning "remember" on in settings would yank the value
    // out from under a state you'd just set by hand — the setting is about what
    // happens NEXT, not a retroactive rewrite of what's on screen.
    property bool collapsed: Config.modulePersist("wifi")
        ? Config.moduleRightState("wifi")
        : false

    function _toggleCollapsed() {
        const next = !root.collapsed
        if (Config.modulePersist("wifi")) Config.setModuleRightState("wifi", next)
        // Assigning here would destroy the declarative binding above for good, so an
        // opted-in module would stop tracking Config after its first right-click.
        // Re-establishing it keeps Config the source of truth.
        root.collapsed = Qt.binding(() => Config.modulePersist("wifi")
            ? Config.moduleRightState("wifi")
            : next)
    }

    signal toggled()

    implicitWidth:  pill.width
    implicitHeight: Tokens.pillHeight

    readonly property string ssidLabel: Net.ssid !== "" ? Net.ssid : "Wi-Fi"

    // Signal strength is a status, not an interaction, so it gets the status
    // ramp rather than an accent: weak is a problem you may need to act on.
    readonly property color signalColor: {
        if (!Net.wifiEnabled || !Net.connected) return Colors.fgMuted
        if (Net.strength < 25) return Colors.danger
        if (Net.strength < 50) return Colors.warning
        return root.accent
    }

    IconButton {
        id: pill
        height: Tokens.pillHeight
        width:  root.collapsed ? collapsedW : expandedW

        readonly property int gap:    Tokens.spacingMd
        readonly property int glyphW: glyphMeasure.implicitWidth
        readonly property int labelW: labelMeasure.implicitWidth

        readonly property int collapsedW: Tokens.pillPadding + glyphW + Tokens.pillPadding
        readonly property int expandedW:  Tokens.pillPadding + glyphW + gap + labelW + Tokens.pillPadding

        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        onClicked:      root.toggled()
        onRightClicked: root._toggleCollapsed()

        StyledText { id: glyphMeasure; visible: false; text: "󰤨"; variant: "title"; sizeScale: Config.barIconScale }
        StyledText { id: labelMeasure; visible: false; text: root.ssidLabel; variant: "caption"; sizeScale: Config.barFontScale }

        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     Tokens.pillPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:    Net.glyph()
                variant: "title"
                sizeScale: Config.barIconScale
                color:   root.signalColor
            }

            // The label fades in only AFTER the pill has visibly started
            // widening, so text never appears in a space too small for it. On
            // the way out it goes immediately — the pill can shrink around a
            // gap, but not around visible text.
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:     root.ssidLabel
                variant:  "caption"
                sizeScale: Config.barFontScale
                emphasis: "normal"
                opacity:  root.collapsed ? 0.0 : 1.0

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: root.collapsed ? 0 : 85 }
                        NumberAnimation { duration: Motion.fast; easing.type: Motion.enter }
                    }
                }
            }
        }
    }
}
