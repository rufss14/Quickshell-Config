pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── NetworkWidget ─────────────────────────────────────────────────────────────
// Live throughput. NetStats already reads the sysfs byte counters at 250ms and is
// refcounted, so this tile is a view over numbers that exist rather than new plumbing.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

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

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: NetStats.iface === "" ? "Network" : NetStats.iface
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            // Names which of the two the numbers are, since they are the same shape.
            StyledText {
                text: root.showTotals ? "session" : "now"
                variant: "caption"
                color: root.accent
            }
        }

        Item { Layout.fillHeight: true }

        Rate {
            glyph: "󰅀"; tint: root.accent
            text: root.showTotals ? NetStats.bytes(NetStats.rxTotal)
                                  : NetStats.rate(NetStats.rxRate)
        }
        Rate {
            glyph: "󰅃"; tint: Colors.fgMuted
            text: root.showTotals ? NetStats.bytes(NetStats.txTotal)
                                  : NetStats.rate(NetStats.txRate)
        }

        Item { Layout.fillHeight: true }

        // The trace is the point at the larger sizes — a number tells you the rate now,
        // the line tells you whether that is a spike or a download.
        Sparkline {
            Layout.fillWidth: true
            Layout.preferredHeight: root.size === "large" ? 60 : 30
            visible: root.size !== "small"
            values: NetStats.rxHistory
            accent: root.accent
            curved: true
        }

        // The other half of the pair, so the large tile still says both at once.
        StyledText {
            Layout.fillWidth: true
            visible: root.size === "large"
            text: root.showTotals
                  ? "Now  ↓ " + NetStats.rate(NetStats.rxRate)
                    + "   ↑ " + NetStats.rate(NetStats.txRate)
                  : "Session  ↓ " + NetStats.bytes(NetStats.rxTotal)
                    + "   ↑ " + NetStats.bytes(NetStats.txTotal)
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }
    }

    component Rate: RowLayout {
        id: rateRow
        property string glyph: ""
        // Formatted by the CALLER: rate and total need different formatters, and a
        // component that picks one is a component that has to know which mode it is in.
        property string text: ""
        property color tint: Colors.fg
        Layout.fillWidth: true
        spacing: Tokens.spacingSm
        StyledText { text: rateRow.glyph; variant: "caption"; color: rateRow.tint }
        StyledText {
            Layout.fillWidth: true
            text: rateRow.text
            font.family: Tokens.fontMono
            font.pixelSize: root.size === "small" ? Tokens.fontLabel : Tokens.fontTitle
            color: Colors.fg
            elide: Text.ElideRight
        }
    }
}
