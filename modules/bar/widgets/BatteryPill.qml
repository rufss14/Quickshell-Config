import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"
import "../../../services"

// ── BatteryPill ───────────────────────────────────────────────────────────────
// Charge icon, optionally with the percentage beside it. Left-click opens the
// Battery settings page; right-click collapses to icon-only.
//
// ── Nothing is polled, and nothing is parsed ──────────────────────────────────
// UPower over D-Bus, pushed — `UPower.displayDevice` and its properties notify on
// their own, so the pill costs a binding and no processes. Same reasoning as
// BatteryPage, which is the fuller view this opens.
//
// ── It does not hide itself; the bar does ─────────────────────────────────────
// A desktop has no battery, and this config is published, so somebody WILL have
// this module in a saved layout on a machine that has none. The gate lives in
// Bar.moduleVisible() next to the tray's, because "is there a battery" is a fact
// about the system rather than a preference — the same distinction that keeps
// every other module's visibility out of the widget. See Bar.qml.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Only ever seen at a
    // healthy charge: below 15% the status ramp takes over, on the same reasoning
    // as WifiPill's signal colour — a battery about to die is a problem you may
    // need to act on, not a place to express a theme.
    property color accent: Colors.of(QsWindow.window).primary

    property bool active: false

    // ── collapsed: local by default, persisted on request ─────────────────────
    // Right-click toggles this. Transient unless the module is opted into
    // "remember" (Settings → Bar → this module). Read once at construction rather
    // than bound — see WifiPill for why a live binding here would retroactively
    // rewrite a state you had just set by hand.
    property bool collapsed: Config.modulePersist("battery")
        ? Config.moduleRightState("battery")
        : false

    function _toggleCollapsed() {
        const next = !root.collapsed
        if (Config.modulePersist("battery")) Config.setModuleRightState("battery", next)
        // Assigning would destroy the declarative binding above for good, so an
        // opted-in module would stop tracking Config after its first right-click.
        root.collapsed = Qt.binding(() => Config.modulePersist("battery")
            ? Config.moduleRightState("battery")
            : next)
    }

    signal toggled()

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    readonly property var dev: UPower.displayDevice

    // UPower reports a 0–1 fraction; everything below wants whole percent.
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0

    // `devState`, not `state`: Item already has a `state` (the QML state-machine
    // name) and shadowing it with an int is a trap this codebase has documented
    // twice — see BatteryPage and ValueSlider.
    readonly property int devState: root.dev ? root.dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: root.devState === UPowerDeviceState.Charging
                                  || root.devState === UPowerDeviceState.PendingCharge

    // The thresholds and the charging colour match BatteryPage deliberately. Two
    // surfaces in one shell disagreeing about what "low" looks like is exactly the
    // inconsistency the shared palette exists to prevent.
    readonly property color chargeColor:
          root.charging   ? Colors.of(QsWindow.window).focus
        : root.pct <= 15  ? Colors.of(QsWindow.window).danger
        :                   root.accent

    // Material Symbols' battery run is seven bars (battery_0_bar … battery_6_bar) and
    // battery_full, so the level icon is arithmetic rather than an eight-branch switch —
    // same shape as the Fluent (one per 10%) and Nerd Font runs before it, with the icon
    // NAME instead of a codepoint offset. Charging and critical have their own icons.
    readonly property string iconName: {
        if (root.charging) return "battery_charging_full"
        if (root.pct <= 5) return "battery_alert"
        const bars = Math.min(7, Math.round(root.pct / 100 * 7))
        return bars >= 7 ? "battery_full" : "battery_" + bars + "_bar"
    }

    readonly property string pctLabel: Math.round(root.pct) + "%"

    // One pop when the state changes in a way worth noticing — plugged in / unplugged,
    // dropping to low, reaching full — and NOT on each 10% step the icon goes through,
    // which would be a twitch every few minutes. (The first reading after a reload can
    // flip `charging` once; it lands inside the bar's entrance.)
    readonly property bool low:  !!root.dev && root.pct <= 15
    readonly property bool full: root.devState === UPowerDeviceState.FullyCharged
    onChargingChanged: pop.fire()
    onLowChanged:      if (root.low) pop.fire()
    onFullChanged:     if (root.full) pop.fire()
    PulseOnce { id: pop; target: batteryIcon }

    IconButton {
        id: pill
        container: false
        height: Config.barPillHeight
        width:  root.collapsed ? collapsedW : expandedW

        readonly property int gap:     Tokens.spacingMd
        readonly property int iconExt: Math.round(Tokens.fontTitle * Config.barIconScale)
        readonly property int labelW:  labelMeasure.implicitWidth

        readonly property int collapsedW: Tokens.pillPadding + iconExt + Tokens.pillPadding
        readonly property int expandedW:  Tokens.pillPadding + iconExt + gap + labelW + Tokens.pillPadding

        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        onClicked:      root.toggled()
        onRightClicked: root._toggleCollapsed()

        // Measured off a fixed-width label, not the live one: "100%" is wider than
        // "9%", and measuring the live value would make the pill breathe every time
        // the charge ticked over a percent. The widest case is the honest one to
        // reserve. The icon needs no such measure — every battery icon is the same
        // fixed size regardless of level.
        BarLabel { id: labelMeasure; visible: false; text: "100%" }

        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     Tokens.pillPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap

            // Colour transition is the Behavior on the icon's color.
            MaterialIcon {
                id: batteryIcon
                anchors.verticalCenter: parent.verticalCenter
                name:  root.iconName
                font.pixelSize: pill.iconExt
                color: root.chargeColor
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }

            // The label fades in only AFTER the pill has visibly started widening, so
            // text never appears in a space too small for it. On the way out it goes
            // immediately — the pill can shrink around a gap, but not around visible
            // text. Same sequencing as WifiPill's SSID.
            BarLabel {
                anchors.verticalCenter: parent.verticalCenter
                text:      root.pctLabel
                emphasis:  "normal"
                opacity:   root.collapsed ? 0.0 : 1.0

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
