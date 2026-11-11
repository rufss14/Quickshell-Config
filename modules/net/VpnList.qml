import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── VpnList ───────────────────────────────────────────────────────────────────
// One PanelRow per NetworkManager VPN profile (Net.vpns): its name, its state, a switch.
// Absent when there are none, so most people never see it. The profiles themselves are
// made elsewhere (nm-connection-editor, `nmcli connection import`); this only turns them
// on and off. Under them, the last failure (Net.vpnError), dismissable.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    spacing: Tokens.spacingSm
    visible: Net.vpns.length > 0 || Net.vpnError !== ""

    Component.onCompleted: Net.refreshVpns()

    Repeater {
        model: Net.vpns

        delegate: PanelRow {
            id: strip
            required property var modelData

            readonly property bool up:      modelData.state === "activated"
            readonly property bool moving:  Net.vpnBusy === modelData.uuid
                                            || modelData.state === "activating"
                                            || modelData.state === "deactivating"

            symbol: "vpn_key"
            shape: "clover"
            active: strip.up
            title: strip.modelData.name
            subtitle: Net.vpnBusy === strip.modelData.uuid
                        ? (strip.up ? Translation.tr("Disconnecting…") : Translation.tr("Connecting…"))
                    : strip.modelData.state === "activating"   ? Translation.tr("Connecting…")
                    : strip.modelData.state === "deactivating" ? Translation.tr("Disconnecting…")
                    : strip.up ? Translation.tr("Connected") : Translation.tr("Off")

            BusyDot { running: strip.moving; tint: strip.ink }
            Toggle {
                Layout.alignment: Qt.AlignVCenter
                accessibleName: strip.modelData.name
                checked: strip.up
                // One switch at a time: nmcli runs one up/down, and the panel waits for it.
                enabled: Net.vpnBusy === ""
                onToggled: Net.setVpn(strip.modelData.uuid, !strip.up)
            }
        }
    }

    Rectangle {
        id: errorBar
        readonly property var pal: Colors.of(QsWindow.window)
        visible: Net.vpnError !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(Tokens.sideCardUnit, errorText.implicitHeight + Tokens.spacingMd * 2)
        radius: Tokens.radiusCard
        color: errorBar.pal.alpha(errorBar.pal.danger, 0.16)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingMd + 2
            spacing: Tokens.spacingMd

            StyledText {
                id: errorText
                Layout.fillWidth: true
                text: Net.vpnError
                variant: "caption"
                wrapMode: Text.WordWrap
            }
            PanelButton {
                variant: "ghost"
                glyph:   "󰅖"
                glyphTint: errorBar.pal.fgMuted
                implicitHeight: 22
                onActivated: Net.vpnError = ""
            }
        }
    }
}
