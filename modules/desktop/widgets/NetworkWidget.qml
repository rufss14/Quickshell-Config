pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── NetworkWidget ─────────────────────────────────────────────────────────────
// Live throughput. NetStats already reads the sysfs byte counters at 250ms and is
// refcounted, so this tile is a view over numbers that exist rather than new plumbing.
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// Two readings, two weights: download is the hero (a tonal container in the accent,
// the bigger figure), upload sits under it on the quiet row. Medium and large draw the
// two histories as stacked traces — down in the accent, up in the muted ink — so the
// shape of the last minute is legible, not just its last value. A tap swaps the rates
// for this session's totals (the pill says which).
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { NetStats.acquire(); root._held = true }
        else if (!root.active && root._held) { NetStats.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) NetStats.release()

    // ── Rate or total ─────────────────────────────────────────────────────────
    // A tap swaps the two big numbers between "how fast right now" and "how much since
    // the link came up". Both come from counters the service already reads, so this
    // costs nothing but a branch — and at small, where the session line has no room,
    // it is the only way to see the totals at all.
    //
    // Transient. Rate is what a network tile is for; totals are something you go and
    // look at.
    property bool showTotals: false
    function tileTap() { root.showTotals = !root.showTotals }

    // The SSID when it's known, else the interface name, else a plain label —
    // "what am I on" reads better than "wlan0".
    readonly property string headerLabel:
        Net.connected && Net.ssid !== "" ? Net.ssid
      : NetStats.iface !== ""             ? NetStats.iface
      :                                    "Network"

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingSm

        WidgetHeader {
            glyph:  Net.glyph()
            shape:  "clover"
            title:  root.headerLabel
            accent: root.accent
            TilePill {
                visible: Net.connected && Net.strength >= 0 && root.size !== "small"
                text: Net.strength + "%"
            }
            TilePill {
                text: root.showTotals ? "Session" : "Now"
                tone: "accent"
                accent: root.accent
            }
        }

        Rate {
            hero: true
            icon: "arrow_downward"
            text: root.showTotals ? NetStats.bytes(NetStats.rxTotal) : NetStats.rate(NetStats.rxRate)
        }
        Rate {
            icon: "arrow_upward"
            text: root.showTotals ? NetStats.bytes(NetStats.txTotal) : NetStats.rate(NetStats.txRate)
        }

        // The last minute, down over up.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.size !== "small"
            Sparkline {
                anchors.fill: parent
                values: NetStats.rxHistory
                accent: root.accent
                curved: true
            }
            Sparkline {
                anchors.fill: parent
                anchors.topMargin: parent.height * 0.45
                values: NetStats.txHistory
                accent: Colors.of(QsWindow.window).fgMuted
                curved: true
            }
        }
        Item { Layout.fillHeight: true; visible: root.size === "small" }
    }

    // One reading on a tonal row: the hero on the accent's container, the other quiet.
    component Rate: Rectangle {
        id: rate
        property bool hero: false
        property string icon: ""
        property string text: ""

        Layout.fillWidth: true
        implicitHeight: rateContent.implicitHeight + Tokens.spacingSm * 2
        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
        color: rate.hero ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).surfaceHigh

        RowLayout {
            id: rateContent
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingSm

            MaterialIcon {
                name: rate.icon
                variant: "caption"
                color: rate.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fgMuted
            }
            StyledText {
                Layout.fillWidth: true
                text: rate.text
                font.family: Tokens.fontMono
                font.weight: rate.hero ? Font.Bold : Font.Medium
                font.pixelSize: rate.hero ? (root.size === "small" ? Tokens.fontTitle : Tokens.fontHeadline)
                                          : Tokens.fontLabel
                color: rate.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fg
                elide: Text.ElideRight
            }
        }
    }
}
