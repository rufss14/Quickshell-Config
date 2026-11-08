pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── UpdatesWidget ─────────────────────────────────────────────────────────────
// How many packages are waiting. Click to install them (the update panel) — or, when
// there is nothing to install, to open the Updates page.
//
// It does NOT drive the check on its own cadence: the Flatpak half hits the network and
// is the slowest of the three sources, so it stays on the Updates service's own
// schedule, shared with the bar's pill. This tile reports; it does not poll.
//
// ── What the motion is FOR ────────────────────────────────────────────────────
// The bar pill and the sidebar say "N waiting"; the tile is the one place that can say
// what the update is DOING, so the ring around the glyph is the state: empty while
// updates are pending, full in `success` when there are none, and the run's own
// progress while one is live. Every number comes from `Updates` (the `:: [n/N]` parse
// lives there) — nothing here reads the log.
//
// ── Layout, Material 3 Expressive (2026-10-30) ────────────────────────────────
// The state is ONE hero: the wavy ring (the run's progress, full and green when up to
// date) around a tonal circle with the count INSIDE it in the block face, its caption
// under the number. Beside it: the title and when you last upgraded, then the sources as ONE split
// bar — each source's share of the total, the gaps between them — with a legend of pills
// under it (point at one to peek the first package waiting in it), and the tile's one
// action as a filled pill: "Update now" (or "Show progress" / "Answer" while a run is
// live). Small is the hero alone.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    // Set by WidgetLayer when the tile loads — see its onLoaded. Needed because
    // opening the update panel means naming the screen that asked for it.
    property var screen: null

    readonly property int total: Updates.total

    // Held copy of `caption`, set by the SwapFade on the caption at its midpoint.
    property string shownCaption: ""
    Component.onCompleted: { root.shownCaption = root.caption; root._lastTotal = root.total }

    property real breath: 1
    SequentialAnimation on breath {
        running: Updates.checking && root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: Motion.pulse; easing.type: Motion.ambient }
        NumberAnimation { to: 1.00; duration: Motion.pulse; easing.type: Motion.ambient }
    }

    property int _lastTotal: 0
    onTotalChanged: {
        if (root.total === 0 && root._lastTotal > 0 && root.active) donePop.fire()
        root._lastTotal = root.total
    }

    // A run is live (or stalled on a question only the user can answer).
    readonly property bool running: Updates.runBusy

    // The one line under the figure. A plain string so SwapFade can fade between its
    // values; it is NOT bound to the caption directly (see `shownCaption`).
    readonly property string caption:
        Updates.awaitingInput ? "Waiting on you"
      : root.running          ? (Updates.runInHooks ? "Hooks…" : "Updating…")
      : Updates.checking      ? "Checking…"
      : Updates.hasError      ? "Check failed"
      : root.total === 0      ? "Up to date"
      : root.total === 1      ? "update"
                              : "updates"

    // The figure: how far through the run, else how many are waiting.
    readonly property string figure:
        (root.running && Updates.runPkgCount > 0)
            ? Updates.runPkgsDone + "/" + Updates.runPkgCount
            : String(root.total)

    // ── Tapping the tile ──────────────────────────────────────────────────────
    // The update PANEL — the same thing the bar's pill opens, with the same password
    // field and live progress. Unconditionally, including at zero pending: an
    // up-to-date system is the common case, and a tile whose tap target changes
    // underneath you depending on a number is worse than one that always does the
    // same thing. (The panel also carries the Vencord re-patch button, which has
    // nothing to do with pending packages.)
    function _openUpdates() {
        UiState.activeScreen       = root.screen
        UiState.pendingUpdateCount = root.total
        UiState.updateRequestId++
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._openUpdates()
    }

    // The whole tile's hover, for the action chips. A HoverHandler takes no press, so the
    // tap above still reaches the MouseArea.
    HoverHandler { id: tileHover }

    // ── What the hero wears ───────────────────────────────────────────────────
    readonly property bool upToDate: root.total === 0 && !root.running && !Updates.checking && !Updates.hasError
    readonly property color tone:
        Updates.awaitingInput ? Colors.of(QsWindow.window).warning
      : Updates.hasError && !root.running ? Colors.of(QsWindow.window).danger
      : root.upToDate ? Colors.of(QsWindow.window).success
      : root.accent
    // The palette's accent gets its tonal pair; a state colour gets a container mixed toward it.
    readonly property bool _plain: Qt.colorEqual(root.tone, Colors.of(QsWindow.window).primary)
    readonly property color container: root._plain ? Colors.of(QsWindow.window).primaryContainer
        : Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.tone, 0.26)
    readonly property color ink: root._plain ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.tone
    // A number in the middle when there is one to say; otherwise the state's icon.
    readonly property bool showFigure: root.total > 0 && !Updates.awaitingInput && !(Updates.hasError && !root.running)
    readonly property string heroIcon:
        Updates.awaitingInput ? "help"
      : Updates.hasError      ? "error"
      : Updates.checking      ? "download"
      : "check"

    // ── The sources ───────────────────────────────────────────────────────────
    readonly property var sources: [
        { key: "official", icon: "inventory_2", label: "Official", count: Updates.count,        rows: Updates.official, on: true },
        { key: "aur",      icon: "extension",   label: "AUR",      count: Updates.aurCount,     rows: Updates.aur,      on: Updates.helper !== "" },
        { key: "flatpak",  icon: "apps",        label: "Flatpak",  count: Updates.flatpakCount, rows: Updates.flatpak,  on: Updates.hasFlatpak }
    ].filter(x => x.on)
    // One hue, three strengths: the bar is a split of one total, so its parts are shades
    // of one colour, told apart by the legend under them.
    function shadeOf(i) {
        const c = Colors.of(QsWindow.window)
        return i === 0 ? root.accent : c.mix(root.accent, c.surfaceContainer, i === 1 ? 0.42 : 0.66)
    }
    // The source under the pointer, for the peek ("" = none).
    property string peek: ""
    readonly property var peekRow: {
        const src = root.sources.find(x => x.key === root.peek)
        return src && src.rows.length > 0 ? src.rows[0] : null
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        // ── The hero ──────────────────────────────────────────────────────────
        RadialGauge {
            id: stateRing
            Layout.fillHeight: true
            Layout.preferredWidth: height
            Layout.fillWidth: root.size === "small"
            Layout.alignment: Qt.AlignVCenter
            thickness: Tokens.spacingSm + Tokens.spacingXs
            accent: root.tone
            value: root.running ? Updates.runProgress : root.upToDate ? 1 : 0
            // Material 3 Expressive's wavy indicator: the run's progress waves round.
            wavy: true

            Item {
                id: stateDisc
                anchors.fill: parent

                MorphShape {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingXs
                    spec: Motion.springSpatialFast
                    // Always a circle (the user's call, 2026-10-30): the state is told by the
                    // ring, the colour and what is inside, not by the outline.
                    shape: Config.barShape ? "squircle" : "circle"
                    fillColor: root.container
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -Tokens.spacingXs

                    // The count rolls as packages land or clear; mid-run it is n/N.
                    RollText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.showFigure
                        text: root.figure
                        family: Tokens.fontBlock
                        weight: Font.ExtraBold
                        pixelSize: Math.round(stateRing.width * (root.figure.length > 3 ? 0.17 : 0.26))
                        color: root.ink
                    }
                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.showFigure
                        name: root.heroIcon
                        fill: 1
                        font.pixelSize: Math.round(stateRing.width * 0.24)
                        color: root.ink
                        // Breathes while a check is out, and only then: `breath` is its own
                        // property so stopping the animation leaves opacity at 1, not
                        // wherever the pulse happened to be. A check ends, so this is a
                        // pulse and not a spinner (BusyDot's reasoning).
                        opacity: Updates.checking ? root.breath : 1
                    }
                    // Fades between states. Bound to a held copy, not to `root.caption`, so
                    // the old words are still there while they fade out (SwapFade).
                    StyledText {
                        id: captionText
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: stateRing.width * 0.62
                        text: root.shownCaption
                        variant: "caption"
                        horizontalAlignment: Text.AlignHCenter
                        color: Colors.of(QsWindow.window).alpha(root.ink, 0.78)
                        elide: Text.ElideRight

                        SwapFade {
                            target: captionText
                            key: root.caption
                            shownKey: root.shownCaption
                            onSwapped: root.shownCaption = root.caption
                        }
                    }
                }
            }
        }

        // One pop when the last package clears — a state change worth a single
        // acknowledgement, never a loop (PulseOnce).
        PulseOnce { id: donePop; target: stateDisc; peak: 1.12 }

        // ── Beside it: when, from where, and the action ───────────────────────
        ColumnLayout {
            visible: root.size !== "small"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Updates")
                        variant: "title"
                        font.weight: Font.Bold
                        color: Colors.of(QsWindow.window).fg
                    }
                    // What the run is on while one is live, the package under the pointer
                    // while peeking, otherwise when you last upgraded.
                    StyledText {
                        Layout.fillWidth: true
                        text: root.running ? Updates.runCurrentItem
                            : root.peekRow ? root.peekRow.name + "  " + root.peekRow.from + " → " + root.peekRow.to
                            : Updates.lastUpgradeText
                        variant: "caption"
                        emphasis: root.peekRow && !root.running ? "normal" : "dim"
                        elide: Text.ElideRight
                    }
                }
                TileChip {
                    Layout.alignment: Qt.AlignTop
                    awake: tileHover.hovered
                    accent: root.accent
                    icon: "sync"                       // look again now
                    onActivated: Updates.check()
                }
                // The Arch news page; a dot when there is news since your last upgrade —
                // a headline can hide a manual step.
                TileChip {
                    Layout.alignment: Qt.AlignTop
                    awake: tileHover.hovered || Updates.newsUnread
                    accent: root.accent
                    icon: "newspaper"
                    dot: Updates.newsUnread
                    onActivated: Qt.openUrlExternally(Updates.newsUrl)
                }
            }

            Item { Layout.fillHeight: true }

            // The split: each source's share of what is waiting, the gaps between them.
            // Up to date (or nothing counted yet): one quiet track.
            Item {
                id: split
                Layout.fillWidth: true
                implicitHeight: Tokens.spacingMd
                readonly property var parts: root.sources.filter(x => x.count > 0)
                readonly property real gap: Tokens.spacingXs + 1
                readonly property real room: Math.max(0, split.width - split.gap * Math.max(0, split.parts.length - 1))

                Rectangle {
                    anchors.fill: parent
                    visible: split.parts.length === 0
                    radius: height / 2
                    color: root.upToDate ? Colors.of(QsWindow.window).alpha(root.tone, 0.35)
                                         : Colors.of(QsWindow.window).surfaceHigh
                }
                Row {
                    anchors.fill: parent
                    spacing: split.gap
                    Repeater {
                        model: split.parts
                        Rectangle {
                            id: part
                            required property var modelData
                            required property int index
                            readonly property int at: root.sources.findIndex(x => x.key === part.modelData.key)
                            SpringValue {
                                id: partW
                                spec: Motion.springSpatial
                                epsilon: 0.1
                                target: root.total > 0 ? split.room * part.modelData.count / root.total : 0
                            }
                            width: Math.max(split.height, partW.value)
                            height: split.height
                            radius: height / 2
                            color: root.shadeOf(part.at)
                            opacity: root.peek === "" || root.peek === part.modelData.key ? 1 : 0.4
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }
                    }
                }
            }

            // The legend: a pill per source; pointing at one peeks its first package.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingXs
                Repeater {
                    model: root.sources
                    Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        implicitWidth: chipRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: chipRow.implicitHeight + Tokens.spacingXs * 2
                        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                        color: chipHover.hovered ? Colors.of(QsWindow.window).surfaceHigh : "transparent"
                        opacity: chip.modelData.count > 0 ? 1 : 0.45
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        HoverHandler {
                            id: chipHover
                            onHoveredChanged: root.peek = chipHover.hovered ? chip.modelData.key
                                                        : (root.peek === chip.modelData.key ? "" : root.peek)
                        }
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            Rectangle {
                                implicitWidth: Tokens.spacingSm + Tokens.spacingXs
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: root.shadeOf(chip.index)
                            }
                            StyledText {
                                text: chip.modelData.label
                                variant: "caption"
                                color: Colors.of(QsWindow.window).fgMuted
                            }
                            RollText {
                                text: String(chip.modelData.count)
                                pixelSize: Tokens.fontCaption
                                weight: Font.Bold
                                color: Colors.of(QsWindow.window).fg
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // The one action: a filled pill while there is something to do.
            Rectangle {
                id: action
                readonly property string label:
                    Updates.awaitingInput ? "Answer"
                  : root.running          ? "Show progress"
                  : root.total > 0        ? "Update now"
                  : ""
                visible: action.label !== ""
                Layout.fillHeight: false
                implicitWidth: actionRow.implicitWidth + Tokens.spacingLg * 2
                implicitHeight: actionRow.implicitHeight + Tokens.spacingSm * 2
                radius: height / 2
                color: Updates.awaitingInput ? Colors.of(QsWindow.window).warning : root.accent
                SpringValue {
                    id: actionPress
                    spec: Motion.springSpatialFast
                    epsilon: 0.0005
                    target: actionMouse.pressed ? 0.94 : 1
                }
                scale: actionPress.value

                StateLayer {
                    id: actionFeel
                    anchors.fill: parent
                    radius: action.radius
                    hovered: actionMouse.containsMouse
                    layerColor: Colors.of(QsWindow.window).fgOnPrimary
                }
                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs
                    MaterialIcon {
                        name: Updates.awaitingInput ? "help" : root.running ? "update" : "download"
                        variant: "caption"
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                    StyledText {
                        text: action.label
                        variant: "caption"
                        font.weight: Font.Bold
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                }
                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function (e) { actionFeel.press(e.x, e.y) }
                    onReleased: actionFeel.release()
                    onCanceled: actionFeel.release()
                    onClicked: root._openUpdates()
                }
            }
        }
    }
}
