pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── DiskWidget ────────────────────────────────────────────────────────────────
// Free space. A ring for one filesystem at small/medium; a stack of bars for
// every mounted filesystem at large.
//
// ── It shows the LAST scan, deliberately ──────────────────────────────────────
// Storage's probe walks directories and takes seconds cold (measured: over two minutes
// on a cold cache, three warm). A desktop tile must not run that on a timer, so this
// acquires the service — which triggers one probe — and then shows what it found. The
// caption says when, so a stale number is never mistaken for a live one.
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// Small/medium: the wavy ring is the fraction used; inside it, a tonal squircle (a
// drive's own shape) holding what is left, because "how much room" is the question.
// It turns the danger tone at 90% full. Medium adds the mount and the totals beside it.
// Large: every filesystem as a tonal row with its bar.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Storage.acquire(); root._held = true }
        else if (!root.active && root._held) { Storage.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) Storage.release()

    // Tap opens the full Storage page — the reclaim tools, the directory scan.
    function tileTap() { UiState.openSettingsTo("StoragePage.qml") }

    readonly property var all: Storage.filesystems ?? []
    readonly property bool multi: root.size === "large"

    // The root filesystem unless the user named another. Falls back to the first one
    // reported, so a machine with an unusual layout still shows something.
    readonly property var fs: {
        if (root.all.length === 0) return null
        const want = root.opts.mount ?? "/"
        return root.all.find(f => f.mount === want) ?? root.all[0]
    }
    readonly property real used:
        root.fs && root.fs.size > 0 ? (root.fs.size - root.fs.avail) / root.fs.size : 0

    readonly property bool full: root.used >= 0.9
    readonly property color tone: root.full ? Colors.of(QsWindow.window).danger : root.accent

    WidgetEmpty {
        visible: !root.fs
        icon: "hard_drive"
        text: Storage.probing ? "Checking disks…" : "No disk data"
    }

    // ── Small / medium: one disk ──────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        visible: !!root.fs && !root.multi
        spacing: Tokens.spacingLg

        RadialGauge {
            Layout.alignment: root.size === "small" ? Qt.AlignCenter : Qt.AlignVCenter
            Layout.fillWidth: root.size === "small"
            implicitWidth:  root.size === "small" ? 120 : 112
            implicitHeight: implicitWidth
            thickness: 10
            wavy: true
            value: root.used
            accent: root.tone

            MorphShape {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXs
                spec: Motion.springSpatialFast
                shape: root.full ? "burst" : "squircle"
                fillColor: root.full
                    ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.tone, 0.26)
                    : Colors.of(QsWindow.window).primaryContainer
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2
                RollText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.fs ? Storage.bytes(root.fs.avail) : ""
                    pixelSize: Tokens.fontTitle
                    weight: Font.Bold
                    color: root.full ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "free"
                    variant: "caption"
                    color: Colors.of(QsWindow.window).alpha(root.full ? Colors.of(QsWindow.window).fg
                                                                     : Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)
                }
            }
        }

        ColumnLayout {
            visible: root.size !== "small"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

            StyledText {
                Layout.fillWidth: true
                text: root.fs ? root.fs.mount : ""
                variant: "title"
                font.weight: Font.Bold
                color: Colors.of(QsWindow.window).fg
                elide: Text.ElideMiddle
            }
            StyledText {
                Layout.fillWidth: true
                text: Math.round(root.used * 100) + "% used"
                variant: "label"
                color: root.full ? root.tone : Colors.of(QsWindow.window).fgMuted
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingSm
                spacing: Tokens.spacingXs
                TilePill { icon: "hard_drive"; text: root.fs ? Storage.bytes(root.fs.size) : "" }
                TilePill {
                    visible: !!root.fs && (root.fs.fstype ?? "") !== ""
                    text: root.fs ? (root.fs.fstype ?? "") : ""
                }
            }
        }
    }

    // ── Large: every disk ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: !!root.fs && root.multi
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "hard_drive"
            shape:  "squircle"
            title:  Translation.tr("Disks")
            accent: root.accent
            MaterialIcon { name: "open_in_new"; variant: "caption"; emphasis: "dim" }
        }

        Repeater {
            model: root.all

            TileRow {
                id: fsRow
                required property var modelData
                readonly property real frac:
                    fsRow.modelData.size > 0
                        ? (fsRow.modelData.size - fsRow.modelData.avail) / fsRow.modelData.size
                        : 0
                // A row is a fact; the whole tile's tap already opens the Storage page.
                interactive: false

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingXs
                    Layout.bottomMargin: Tokens.spacingXs
                    spacing: Tokens.spacingXs
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: fsRow.modelData.mount
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: Colors.of(QsWindow.window).fg
                            elide: Text.ElideMiddle
                        }
                        StyledText {
                            text: Storage.bytes(fsRow.modelData.avail) + " free"
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }
                    Meter {
                        Layout.fillWidth: true
                        value: fsRow.frac
                        accent: fsRow.frac >= 0.9 ? Colors.of(QsWindow.window).danger : root.accent
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
