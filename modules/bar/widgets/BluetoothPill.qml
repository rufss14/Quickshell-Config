import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── BluetoothPill ─────────────────────────────────────────────────────────────
// Adapter icon, optionally with what's connected beside it. Left-click opens the
// Bluetooth panel; right-click collapses to icon-only.
//
// ── Everything it shows comes from Bt ─────────────────────────────────────────
// The icon, the connected count and the device name are all derivations on the
// service, so this pill, the panel and the settings page agree by construction
// rather than by three files being edited together. BlueZ pushes over D-Bus, so
// nothing here polls.
//
// ── It does not hide itself; the bar does ─────────────────────────────────────
// Same contract as BatteryPill: "is there an adapter" is a fact about the system,
// so the gate is in Bar.moduleVisible() next to the tray's and the battery's, using
// the same `Bt.available` the settings rail uses to decide whether the Bluetooth
// PAGE exists.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Only ever seen when the
    // radio is ON — off is fgMuted, because a disabled radio is an absence rather
    // than a state worth tinting.
    property color accent: Colors.of(QsWindow.window).primary

    property bool active: false

    // ── collapsed: local by default, persisted on request ─────────────────────
    // Right-click toggles this. Read once at construction rather than bound — see
    // WifiPill for why a live binding would retroactively rewrite a state you had
    // just set by hand.
    property bool collapsed: Config.modulePersist("bluetooth")
        ? Config.moduleRightState("bluetooth")
        : false

    function _toggleCollapsed() {
        const next = !root.collapsed
        if (Config.modulePersist("bluetooth")) Config.setModuleRightState("bluetooth", next)
        // Assigning would destroy the declarative binding above for good, so an
        // opted-in module would stop tracking Config after its first right-click.
        root.collapsed = Qt.binding(() => Config.modulePersist("bluetooth")
            ? Config.moduleRightState("bluetooth")
            : next)
    }

    signal toggled()

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    // What the label says, in priority order: the one connected device by name, or
    // how many if there are several, or the radio's state. A count of one would be
    // strictly less useful than the name — "Connected" tells you nothing you can act
    // on, and the name is the thing you were checking for.
    readonly property string label:
          !Bt.powered              ? "Off"
        : Bt.connectedCount === 0  ? "Bluetooth"
        : Bt.connectedCount === 1  ? (Bt.primary?.name || Bt.primary?.address || "Connected")
        :                            Bt.connectedCount + " devices"

    // Status, not accent, when there's nothing on: the same reasoning as WifiPill's
    // signal ramp. Connected takes the accent because that IS the working state.
    readonly property color stateColor:
          !Bt.powered             ? Colors.of(QsWindow.window).fgMuted
        : Bt.connectedCount > 0   ? root.accent
        :                           Colors.of(QsWindow.window).stateIdleFg

    // ── Battery ring ──────────────────────────────────────────────────────────
    // A thin ring around the icon: the lowest charge among connected devices that
    // report one (Bt.lowestBattery), danger-tinted under the warning threshold. The
    // number is in the panel; the ring is what you notice from across the bar.
    readonly property var ringDev: Config.btPillBattery && Bt.powered ? Bt.lowestBattery : null
    readonly property real ringLevel: root.ringDev ? Bt.batteryLevel(root.ringDev) : 0

    // The group's spacing override (module inspector) — see Config.groupSpacing.
    readonly property int groupSpacing: Config.groupSpacing("bluetooth")

    IconButton {
        id: pill
        container: false
        height: Config.barPillHeight
        width:  root.collapsed ? collapsedW : expandedW

        readonly property int hPad:    root.groupSpacing >= 0
            ? Math.round(root.groupSpacing / 2) : Tokens.pillPadding
        readonly property int gap:     root.groupSpacing >= 0 ? Tokens.spacingXs : Tokens.spacingMd
        readonly property int iconExt: Math.round(Tokens.fontTitle * Config.barIconScale)
        readonly property int labelW:  labelMeasure.implicitWidth
        // The icon's footprint: the icon, or the icon inside its battery ring.
        readonly property int ringPad: Tokens.spacingXs * 2
        readonly property int iconSlot: root.ringDev ? iconExt + ringPad * 2 : iconExt

        readonly property int collapsedW: hPad + iconSlot + hPad
        readonly property int expandedW:  hPad + iconSlot + gap + labelW + hPad

        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        onClicked:      root.toggled()
        onRightClicked: root._toggleCollapsed()

        // The icon is a fixed size regardless of which of the three adapter states is
        // showing, so — unlike the label — there's nothing here to measure. The LABEL is
        // measured live: there is no bounded widest case for a device name, so reserving
        // one is impossible and the pill animates to fit.
        BarLabel { id: labelMeasure; visible: false; text: root.label }

        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     pill.hPad
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap

            // Colour transition is TintedIcon's own — see its Behavior on colorizationColor.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width:  pill.iconSlot
                height: pill.iconSlot

                RadialGauge {
                    anchors.fill: parent
                    visible: root.ringDev !== null
                    thickness: Tokens.spacingXs
                    value:  root.ringLevel
                    accent: root.ringLevel < Config.btBatteryLow / 100 ? Colors.of(QsWindow.window).danger : root.accent
                }
                TintedIcon {
                    anchors.centerIn: parent
                    source: Bt.iconPath
                    size:   pill.iconExt
                    color:  root.stateColor
                }
            }

            // Fades in only AFTER the pill has visibly started widening, so text never
            // appears in a space too small for it. On the way out it goes immediately —
            // the pill can shrink around a gap, but not around visible text.
            BarLabel {
                anchors.verticalCenter: parent.verticalCenter
                text:      root.label
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
