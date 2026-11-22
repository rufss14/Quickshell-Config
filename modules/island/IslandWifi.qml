import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../net"

// ── IslandWifi ────────────────────────────────────────────────────────────────
// The network as an island page: on the left the loud card (what you are connected through, its signal,
// the address behind a blur, the radio's switch) over Ethernet when it is there and idle; on the right
// the VPNs and the networks in range (NetworkBrowser: the same list, password and hidden-network
// forms the bar panel has), scrolling inside their card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property bool online: Net.wiredConnected || Net.connected
    readonly property string address: Net.wiredConnected ? Net.wiredAddress : Net.address

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                id: link
                Layout.fillWidth: true
                Layout.fillHeight: true
                hero: true
                order: 0
                clip: true

                MorphShape {
                    width: link.height * 0.8
                    height: width
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -width * 0.25
                    anchors.topMargin: -width * 0.22
                    shape: Net.wiredConnected ? "squircle" : root.online ? "cookie9" : "circle"
                    turns: false
                    fillColor: root.palette.alpha(link.ink, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Network").toUpperCase()
                            variant: "caption"
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                            color: link.inkDim
                        }
                        BusyDot { running: Net.wifiEnabled && Net.scanning; tint: link.ink }
                    }
                    IslandBadge {
                        Layout.topMargin: Tokens.spacingSm
                        size: Tokens.iconXl * 2 + Tokens.spacingSm
                        filled: true
                        shape: Net.wiredConnected ? "squircle" : root.online ? "cookie9" : "circle"
                        symbol: Net.wiredConnected ? "lan" : Net.wifiEnabled ? "wifi" : "wifi_off"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacingSm
                        text: Net.wiredConnected ? Translation.tr("Ethernet")
                            : Net.connected      ? Net.ssid
                            : !Net.hasWifi       ? Translation.tr("No Wi-Fi adapter")
                            : Net.wifiBlocked    ? Translation.tr("Wi-Fi is blocked")
                            : !Net.wifiEnabled   ? Translation.tr("Wi-Fi is off")
                            :                      Translation.tr("Not connected")
                        variant: "headline"
                        font.weight: Font.DemiBold
                        color: link.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Net.wiredConnected ? [Net.wiredStateLabel(), Net.wiredSpeedLabel()].filter(s => s !== "").join("  ·  ")
                            : Net.connected      ? (Net.vpnActive ? Translation.tr("VPN on") : Translation.tr("Connected"))
                            : !Net.hasWifi       ? (Net.hasWired ? Net.wiredStateLabel() : Translation.tr("Nothing to connect with"))
                            : Net.wifiBlocked    ? Translation.tr("A hardware switch or rfkill holds the radio off")
                            : !Net.wifiEnabled   ? Translation.tr("Turn it on to see networks")
                            : Net.networks.length === 1 ? Translation.tr("1 network in range")
                            :                      Translation.tr("%1 networks in range").arg(Net.networks.length)
                        variant: "caption"
                        color: link.inkDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    // The signal, the Dashboard's day bar.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: Net.connected && !Net.wiredConnected
                        spacing: Tokens.spacingSm
                        MaterialIcon { name: "wifi"; fill: 1; font.pixelSize: Tokens.iconMd; color: link.inkDim }
                        Meter {
                            Layout.fillWidth: true
                            value: Math.max(0, Net.strength) / 100 * link.arrive
                            accent: link.ink
                        }
                        StyledText {
                            text: Math.max(0, Net.strength) + "%"
                            variant: "caption"
                            font.features: ({ tnum: 1 })
                            color: link.inkDim
                        }
                    }
                    // The address, blurred until asked for: a screenshot of this page is not an IP leak.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.address !== ""
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: browser.ipBlurred ? "•••  •••  •••" : root.address
                            variant: "caption"
                            font.features: ({ tnum: 1 })
                            color: link.inkDim
                            elide: Text.ElideRight
                        }
                        ChipButton {
                            symbol: browser.ipBlurred ? "visibility_off" : "visibility"
                            Accessible.name: Translation.tr("Show the address")
                            onActivated: browser.ipBlurred = !browser.ipBlurred
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: Net.hasWifi
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Wi-Fi")
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: link.ink
                        }
                        Toggle {
                            accessibleName: Translation.tr("Wi-Fi")
                            checked: Net.wifiEnabled
                            accent: root.palette.primary
                            onToggled: Net.toggleWifi()
                        }
                    }
                }
            }

            IslandTile {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingSm
                visible: Net.hasWired && !Net.wiredConnected
                order: 1
                row: true
                enabled: false
                symbol: "lan"
                label: Translation.tr("Ethernet")
                sub: Net.wiredStateLabel()
            }
        }

        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: true
            order: 1

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                clip: true
                contentHeight: lists.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: lists
                    width: flick.width
                    spacing: Tokens.spacingSm

                    VpnList { Layout.fillWidth: true; Layout.fillHeight: false }
                    NetworkBrowser {
                        id: browser
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: Net.hasWifi
                    }
                    PanelEmpty {
                        visible: !Net.hasWifi
                        quiet: true
                        symbol: "wifi_off"
                        title: Translation.tr("No Wi-Fi adapter")
                        text: Net.hasWired ? Translation.tr("This machine connects by cable") : Translation.tr("Nothing to connect with")
                    }
                }
            }
            Scrollbar { flickable: flick }
        }
    }
}
