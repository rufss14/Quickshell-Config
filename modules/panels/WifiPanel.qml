import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../net"

// ── WifiPanel ─────────────────────────────────────────────────────────────────
// The Wi-Fi module's panel, in the shell's Material 3 Expressive panel shape:
//
//   Header  (Settings › Modules › Wi-Fi hides it) title, what it found, the scan's dot
//   Hero    what the machine is online through right now, the reveal-my-IP eye, the radio's switch
//   Rows    Ethernet (when a cable exists and isn't the subject), a switch per VPN profile
//   List    NetworkBrowser: the networks, the password prompt, the hidden-network form
//
// A view over the Net service (NetworkManager over D-Bus, typed): no subprocess, no parsing, no polling.
// The list is NetworkBrowser because Settings › Network shows the same networks with the same prompt, and
// two copies drift; the scan refcount is keyed to the browser's lifetime.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: Tokens.sideCardUnit * 11

    // The layout reports its own height; the dock's card follows it.
    readonly property int margin: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
    implicitHeight: content.implicitHeight + margin * 2

    // What the machine is online through, for the hero.
    readonly property bool online: Net.wiredConnected || Net.connected
    readonly property string heroTitle: Net.wiredConnected ? Translation.tr("Ethernet")
                                      : Net.connected      ? Net.ssid
                                      : !Net.hasWifi       ? Translation.tr("No Wi-Fi adapter")
                                      : Net.wifiBlocked    ? Translation.tr("Wi-Fi is blocked")
                                      : !Net.wifiEnabled   ? Translation.tr("Wi-Fi is off")
                                      :                      Translation.tr("Not connected")
    readonly property string heroLine: {
        if (Net.wiredConnected) {
            const parts = [Net.wiredStateLabel()]
            if (Net.wiredSpeedLabel() !== "") parts.push(Net.wiredSpeedLabel())
            if (Net.wiredAddress !== "") parts.push(browser.ipBlurred ? "••••••" : Net.wiredAddress)
            return parts.join(" · ")
        }
        if (Net.connected) {
            const parts = [Translation.tr("Signal %1%").arg(Net.strength)]
            if (Net.address !== "") parts.push(browser.ipBlurred ? "••••••" : Net.address)
            if (Net.vpnActive) parts.push(Translation.tr("VPN on"))
            return parts.join(" · ")
        }
        if (!Net.hasWifi)     return Net.hasWired ? Net.wiredStateLabel() : Translation.tr("Nothing to connect with")
        if (Net.wifiBlocked)  return Translation.tr("A hardware switch or rfkill holds the radio off")
        if (!Net.wifiEnabled) return Translation.tr("Turn it on to see networks")
        if (Net.scanning && Net.networks.length === 0) return Translation.tr("Scanning…")
        return Net.networks.length === 1 ? Translation.tr("1 network in range")
                                         : Translation.tr("%1 networks in range").arg(Net.networks.length)
    }

    // Anchored top/left/right, not fill: the Card above this animates its height, and anchoring to fill would
    // re-lay-out this whole column on every frame of that animation.
    ColumnLayout {
        id: content
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingSm

        // ── Header (Settings › Modules › Wi-Fi hides it) ──────────────────────
        PanelHeader {
            Layout.fillHeight: false
            visible: Config.panelHeader("wifi")
            symbol:    "wifi"
            title:     Translation.tr("Wi-Fi")
            titleTail: Translation.tr("& Network")
            accent:    root.accent

            subtitle: Net.wiredConnected ? Translation.tr("Connected via Ethernet")
                    : !Net.wifiEnabled   ? Translation.tr("Radio disabled")
                    : Net.connected      ? Translation.tr("Connected to %1").arg(Net.ssid)
                    : Net.scanning       ? Translation.tr("Scanning…")
                    : Net.networks.length === 1 ? Translation.tr("1 network found")
                    : Translation.tr("%1 networks found").arg(Net.networks.length)

            // Scanning runs continuously while this panel is open, so this is a
            // breathing dot, not a spinner that would never stop.
            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: Net.wifiEnabled && Net.scanning
            }
        }

        // ── Hero: what the machine is online through, and the radio's switch ──
        PanelHero {
            id: hero
            symbol: Net.wiredConnected ? "lan" : "wifi"
            offSymbol: Net.wifiEnabled ? "wifi" : "wifi_off"
            shape: Net.wiredConnected ? "squircle" : "cookie9"
            active: root.online
            turning: false
            accent: root.accent
            title: root.heroTitle
            line: root.heroLine

            // Reveal the local IP. The browser renders it (on the connected row), so the flag lives there.
            PanelButton {
                visible:   Net.address !== "" || Net.wiredAddress !== ""
                variant:   "ghost"
                capsule:   true
                symbol:    browser.ipBlurred ? "visibility_off" : "visibility"
                glyphTint: hero.ink
                onActivated: browser.ipBlurred = !browser.ipBlurred
            }

            Toggle {
                Layout.alignment: Qt.AlignVCenter
                visible: Net.hasWifi
                accessibleName: Translation.tr("Wi-Fi")
                checked: Net.wifiEnabled
                // Just ask NetworkManager: a failed or rfkill-blocked toggle must not leave the switch lying.
                onToggled: Net.toggleWifi()
            }
        }

        // ── Ethernet ──────────────────────────────────────────────────────────
        // A status row: a cable has no list to browse and nothing to join. Only present when a wired device
        // exists and it isn't already the hero's subject.
        PanelRow {
            visible: Net.hasWired && !Net.wiredConnected
            symbol: "lan"
            title: Translation.tr("Ethernet")
            subtitle: Net.wiredStateLabel()
        }

        // ── VPN ───────────────────────────────────────────────────────────────
        // NetworkManager's VPN profiles, a switch each; absent when there are none.
        VpnList { Layout.fillWidth: true; Layout.fillHeight: false }

        NetworkBrowser {
            id: browser
            Layout.fillWidth: true
            // No adapter: the hero has said so, and an empty list under it says it twice.
            visible: Net.hasWifi
            Layout.topMargin: Tokens.spacingXs
        }
    }
}
