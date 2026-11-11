import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── WifiPill ──────────────────────────────────────────────────────────────────
// Signal icon, optionally with the SSID beside it. Left-click opens the wifi
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
    property color accent: Colors.of(QsWindow.window).primary

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
    implicitHeight: Config.barPillHeight

    readonly property string ssidLabel: Net.wiredConnected ? "Ethernet"
        : Net.ssid !== "" ? Net.ssid : "Wi-Fi"

    // Signal strength is a status, not an interaction, so it gets the status
    // ramp rather than an accent: weak is a problem you may need to act on.
    // A cable has no strength to rate — it's either up (accent) or it isn't.
    readonly property color signalColor: {
        if (Net.wiredConnected) return root.accent
        if (!Net.wifiEnabled || !Net.connected) return Colors.of(QsWindow.window).fgMuted
        if (Net.strength < 25) return Colors.of(QsWindow.window).danger
        if (Net.strength < 50) return Colors.of(QsWindow.window).warning
        return root.accent
    }

    // The group's spacing override (module inspector) — see Config.groupSpacing.
    readonly property int groupSpacing: Config.groupSpacing("wifi")

    // One pop when the link comes up or goes down (a cable plugged in, a network
    // joined or lost) — not on every change of strength, which is continuous. Two
    // targets because the wired glyph and the Wi-Fi icon are different items; only one
    // is ever visible, so a pop on the hidden one is invisible.
    Connections {
        target: Net
        function onConnectedChanged()      { wifiPop.fire() }
        function onWiredConnectedChanged() { wiredPop.fire() }
    }
    PulseOnce { id: wifiPop;  target: wifiIcon }
    PulseOnce { id: wiredPop; target: wiredIcon }

    IconButton {
        id: pill
        tipProvider: Config.barTooltips ? function () { return ModuleGlance.tip("wifi") } : null
        container: false
        height: Config.barPillHeight
        width:  root.collapsed ? collapsedW : expandedW

        readonly property int hPad:    root.groupSpacing >= 0
            ? Math.round(root.groupSpacing / 2) : Tokens.pillPadding
        readonly property int gap:     root.groupSpacing >= 0 ? Tokens.spacingXs : Tokens.spacingMd
        readonly property int iconExt: Math.round(Tokens.fontTitle * Config.barIconScale)
        readonly property int labelW:  labelMeasure.implicitWidth

        readonly property int collapsedW: hPad + iconExt + hPad
        readonly property int expandedW:  hPad + iconExt + gap + labelW + hPad

        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        onClicked:      root.toggled()
        onRightClicked: root._toggleCollapsed()

        BarLabel { id: labelMeasure; visible: false; text: root.ssidLabel }

        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.hPad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap

            // Wired stayed the plain Nerd Font glyph — asked back to how it was
            // before this session touched icons at all, rather than any SVG (Fluent
            // OR Material). Wifi's bars/off/warning states are the Material Symbols
            // icon Net.iconPath() resolves to. Both sit in the same slot; only one
            // is ever visible.
            MaterialIcon {
                id: wiredIcon
                anchors.verticalCenter: parent.verticalCenter
                visible:  Net.wiredConnected
                glyph:     Net.glyph()
                variant:  "title"
                sizeScale: Config.barIconScale
                color:    root.signalColor
            }

            TintedIcon {
                id: wifiIcon
                anchors.verticalCenter: parent.verticalCenter
                visible: !Net.wiredConnected
                source:  Net.iconPath()
                size:    pill.iconExt
                color:   root.signalColor
            }

            // The label fades in only AFTER the pill has visibly started
            // widening, so text never appears in a space too small for it. On
            // the way out it goes immediately — the pill can shrink around a
            // gap, but not around visible text.
            BarLabel {
                anchors.verticalCenter: parent.verticalCenter
                text:     root.ssidLabel
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
