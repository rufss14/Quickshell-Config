import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../net"

// ── WifiPanel ─────────────────────────────────────────────────────────────────
// The bar's Wi-Fi popup: a header, and a NetworkBrowser under it.
//
// ── What this used to be ──────────────────────────────────────────────────────
// Seven `nmcli` subprocesses and a 15-second rescan Timer that ran whether or not
// the panel was open. The scan pipeline was:
//
//   radio=$(nmcli radio wifi); echo "RADIO:$radio";
//   nmcli dev wifi rescan & sleep 0.8;
//   nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list |
//     awk -F: '{ … dedupe by strongest … }' | sort -t: -k3 -rn
//
// …with the SSID recovered by `parts.slice(1, length-2).join(":")` because an
// SSID may itself contain a colon, and errors detected by running a regex —
// `/error|fail/i` — over nmcli's *human-readable stderr*, in whatever language
// the user's locale happens to be.
//
// It is now a view over the Net service (NetworkManager, over D-Bus, typed).
// No subprocesses, no parsing, no locale dependency, and no polling: NM pushes.
//
// ── Why the list isn't in this file any more ──────────────────────────────────
// The settings page shows the same networks, with the same password prompt and the
// same connect/forget behaviour, and two copies of that would drift apart one fix at
// a time. All of it moved to NetworkBrowser, including the scan refcount — the
// refcount was only ever keyed to this panel's lifetime because the list could only
// appear here. It's keyed to the browser's lifetime now, which is the same rule
// stated where it can't be forgotten.
//
// What's left is what a POPUP specifically wants: the radio toggle, the scan
// indicator, and the reveal-my-IP eye — the ambient facts you glance at on the way
// to joining something.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: 535

    // ── Height ────────────────────────────────────────────────────────────────
    // The layout reports its own height. This used to be a hand-summed pile of
    // magic numbers (_headerH + _divH + _statusH + _passH + _hiddenH + _listH +
    // _footerH) that had to be kept in sync with the real layout by hand — and
    // silently drifted whenever anything inside changed size.
    readonly property int margin: Tokens.spacingLg + 2
    implicitHeight: content.implicitHeight + margin * 2

    // ══════════════════════════════════════════════════════════════════════════
    // Anchored top/left/right — NOT fill. The Card above this animates its height,
    // and anchoring to fill would re-lay-out this whole column on every frame of
    // that animation, reflowing every child as it went. Top-anchored content keeps
    // its natural size; the Card grows around it and clips.
    ColumnLayout {
        id: content
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingMd + 2

        // ── Header ────────────────────────────────────────────────────────────
        PanelHeader {
            glyph:     Net.glyph()          // real signal strength, same glyph as the bar pill
            title:     "Wi-Fi"
            titleTail: "& Network"
            accent:    Colors.focus

            subtitle: !Net.wifiEnabled ? "Radio disabled"
                    : Net.connected    ? "Connected to " + Net.ssid
                    : Net.scanning     ? "Scanning…"
                    : Net.networks.length + " network"
                      + (Net.networks.length !== 1 ? "s" : "") + " found"

            // Reveal the local IP. The browser renders it (on the connected row), so
            // the flag lives there — this is only the switch.
            PanelButton {
                visible:   Net.address !== ""
                variant:   "ghost"
                glyph:     browser.ipBlurred ? "󰈉" : "󰈈"   // eye-off / eye
                glyphTint: browser.ipBlurred ? Colors.fgDim : Colors.info
                onActivated: browser.ipBlurred = !browser.ipBlurred
            }

            // Scanning runs continuously while this panel is open, so this is a
            // breathing dot, not a spinner that would never stop.
            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: Net.wifiEnabled && Net.scanning
            }

            Toggle {
                Layout.alignment: Qt.AlignVCenter
                checked: Net.wifiEnabled
                // Just ask NetworkManager. The old code optimistically flipped its own
                // local flag alongside the nmcli call, so a failed or rfkill-blocked
                // toggle left the UI lying about the radio.
                onToggled: Net.toggleWifi()
            }
        }

        Divider { Layout.topMargin: 2; Layout.bottomMargin: Tokens.spacingSm }

        NetworkBrowser {
            id: browser
            Layout.fillWidth: true
        }
    }
}
