pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/sysstats.js" as Stats

// ── DevicesWidget ─────────────────────────────────────────────────────────────
// The charge of everything with a battery — the iOS "Batteries" widget, in this shell's
// shapes. A view over DeviceBatteries (UPower's peripherals plus OpenRazer, merged and
// sorted lowest first — tested in sysstats.js), with the laptop's own battery in front
// when there is one. No new plumbing: holding the refcount is what turns the Razer poll
// on, and only while the tile is live.
//
// Each device is a wavy ring (Material 3 Expressive's indicator) around its kind's icon:
// the danger tone at 15% and under, the success tone while charging, with a bolt badge.
// Small: four rings, 2×2. Medium: four in a row, named. Large: a tonal row per device.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { DeviceBatteries.acquire(); root._held = true }
        else if (!root.active && root._held) { DeviceBatteries.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) DeviceBatteries.release()

    // The laptop's own battery, first, when this machine has one (a desktop has none).
    readonly property var _dev: UPower.displayDevice
    readonly property var laptop: root._dev && root._dev.isLaptopBattery
        ? { key: "laptop", name: "This laptop", kind: "laptop",
            level: Math.max(0, Math.min(1, root._dev.percentage)),
            charging: root._dev.state === UPowerDeviceState.Charging
                      || root._dev.state === UPowerDeviceState.PendingCharge }
        : null
    readonly property var all: (root.laptop ? [root.laptop] : []).concat(DeviceBatteries.devices)
    readonly property var shown: root.all.slice(0, root.size === "large" ? 7 : 4)

    function iconOf(kind) {
        switch (kind) {
        case "laptop":     return "laptop"
        case "mouse":      return "mouse"
        case "keyboard":   return "keyboard"
        case "headset":
        case "headphones": return "headphones"
        case "speaker":    return "speaker"
        case "gamepad":    return "gamepad"
        case "phone":      return "smartphone"
        case "tablet":     return "tablet"
        case "pen":        return "edit"
        case "watch":      return "watch"
        case "bluetooth":  return "bluetooth"
        default:           return "battery_full"
        }
    }
    function nameOf(d) { return d.name !== "" ? d.name : Stats.kindLabel(d.kind) }
    function toneOf(d) {
        return d.level <= DeviceBatteries.lowThreshold ? Colors.of(QsWindow.window).danger
             : d.charging ? Colors.of(QsWindow.window).success
             : root.accent
    }

    WidgetEmpty {
        visible: root.all.length === 0
        icon: "devices"
        text: Translation.tr("No devices report a battery")
    }

    // ── Small: 2×2 · Medium: a row ────────────────────────────────────────────
    GridLayout {
        anchors.fill: parent
        visible: root.size !== "large" && root.all.length > 0
        columns: root.size === "small" ? 2 : 4
        rowSpacing: Tokens.spacingXs
        columnSpacing: Tokens.spacingSm

        Repeater {
            model: root.size !== "large" ? root.shown : []
            ColumnLayout {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Ring {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: true
                    Layout.preferredWidth: height
                    Layout.maximumWidth: Tokens.iconXl * 2 + Tokens.spacingLg
                    device: cell.modelData
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(cell.modelData.level * 100) + "%"
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: cell.modelData.level <= DeviceBatteries.lowThreshold
                           ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.size === "medium"
                    horizontalAlignment: Text.AlignHCenter
                    text: root.nameOf(cell.modelData)
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }
        }
        // Fewer than four: the rest of the grid stays empty rather than stretching rings.
        Repeater {
            model: root.size !== "large" ? Math.max(0, 4 - root.shown.length) : 0
            Item { Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }

    // ── Large: a row per device ───────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "large" && root.all.length > 0
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "devices"
            shape:  "cookie9"
            title:  Translation.tr("Devices")
            accent: root.accent
            TilePill { text: String(root.all.length) }
        }

        Repeater {
            model: root.size === "large" ? root.shown : []
            TileRow {
                id: devRow
                required property var modelData
                interactive: false

                Ring {
                    Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.topMargin: Tokens.spacingXs
                    Layout.bottomMargin: Tokens.spacingXs
                    device: devRow.modelData
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.nameOf(devRow.modelData)
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fg
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: devRow.modelData.charging ? "Charging" : Stats.kindLabel(devRow.modelData.kind)
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                RollText {
                    text: Math.round(devRow.modelData.level * 100) + "%"
                    family: Tokens.fontMono
                    pixelSize: Tokens.fontTitle
                    weight: Font.Bold
                    color: devRow.modelData.level <= DeviceBatteries.lowThreshold
                           ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                }
            }
        }
        Item { Layout.fillHeight: true }
    }

    // One device: the wavy ring of its charge around its icon, a bolt badge while charging.
    component Ring: Item {
        id: ring
        property var device: null
        readonly property color tone: ring.device ? root.toneOf(ring.device) : root.accent

        RadialGauge {
            anchors.fill: parent
            thickness: Math.max(3, Math.round(ring.width * 0.08))
            wavy: true
            value: ring.device?.level ?? 0
            accent: ring.tone
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: root.iconOf(ring.device?.kind ?? "")
            font.pixelSize: Math.round(ring.width * 0.34)
            color: ring.tone
        }
        Item {
            visible: ring.device?.charging ?? false
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.round(ring.width * 0.36)
            height: width
            MorphShape {
                anchors.fill: parent
                shape: Config.barShape ? "squircle" : "cookie7"
                fillColor: Colors.of(QsWindow.window).success
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: "bolt"
                font.pixelSize: Math.round(parent.width * 0.62)
                color: Colors.of(QsWindow.window).fgOnPrimary
            }
        }
    }
}
