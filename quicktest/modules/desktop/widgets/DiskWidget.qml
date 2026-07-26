pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── DiskWidget ────────────────────────────────────────────────────────────────
// Free space, as a ring.
//
// ── It shows the LAST scan, deliberately ──────────────────────────────────────
// Storage's probe walks directories and takes seconds cold (measured: over two minutes
// on a cold cache, three warm). A desktop tile must not run that on a timer, so this
// acquires the service — which triggers one probe — and then shows what it found. The
// caption says when, so a stale number is never mistaken for a live one.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Storage.acquire(); root._held = true }
        else if (!root.active && root._held) { Storage.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) Storage.release()

    // The root filesystem unless the user named another. Falls back to the first one
    // reported, so a machine with an unusual layout still shows something.
    readonly property var fs: {
        const all = Storage.filesystems ?? []
        if (all.length === 0) return null
        const want = root.opts.mount ?? "/"
        return all.find(f => f.mount === want) ?? all[0]
    }
    readonly property real used:
        root.fs && root.fs.size > 0 ? (root.fs.size - root.fs.avail) / root.fs.size : 0

    StyledText {
        anchors.centerIn: parent
        visible: !root.fs
        text: Storage.probing ? "Checking…" : "No disk data"
        variant: "caption"
        emphasis: "dim"
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!root.fs
        spacing: Tokens.spacingXs

        Item { Layout.fillHeight: true }

        RadialGauge {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth:  root.size === "small" ? 92 : 104
            implicitHeight: implicitWidth
            value: root.used
            accent: root.accent

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    // Free space, not percent used — "how much room have I got" is the
                    // question you look at a disk tile to answer, and a percentage
                    // makes you do arithmetic. Same call as the Storage page's gauges.
                    text: root.fs ? Storage.bytes(root.fs.avail) : ""
                    variant: "title"
                    font.bold: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "free"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.size !== "small"
            text: root.fs ? root.fs.mount + "  ·  " + Storage.bytes(root.fs.size) : ""
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }
}
