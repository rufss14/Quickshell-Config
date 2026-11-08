pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideClipboard ─────────────────────────────────────────────────────────────
// Clipboard history as a sidebar button, its list in a panel beside it
// (ClipboardPanel, in SidePanelDock).
//
//   click     the panel, beside this button (again: shut it)
//   right     Settings › Sidebar
//
// Every copy anywhere answers here: the clipboard glyph turns to a check in the
// accent and pops, then settles back — so the sidebar says "got it" the moment you
// copy, the one live thing a clipboard has to show.
//
// At rest it shows the last copy when that is a picture (a rounded thumbnail) or a
// colour (a swatch of the "#rrggbb" copied), and the glyph otherwise (2026-10-31, the
// user's pick: "richer glances"). Text is never shown at rest.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    // The screen this sidebar is on: its panel opens here.
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "clipboard" && root.ownsPanel

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // ── A copy landed ─────────────────────────────────────────────────────────
    // A new newest entry is a copy (the store dedupes, so re-copying an old one moves
    // it to the top with a fresh `at` — that counts too) — once the history has
    // loaded: the load itself isn't a copy. "New" is by `at`, not just a different
    // hash: removing the top entry also changes which one is newest. How long the check stays is an interaction
    // timing, not a Motion duration: with motion off those are 0, and a check that
    // never shows says nothing.
    readonly property string newest: Clipboard.count > 0 ? Clipboard.entries[0].hash : ""
    readonly property real newestAt: Clipboard.count > 0 ? (Clipboard.entries[0].at ?? 0) : 0
    property string _lastNewest: ""
    property real _lastAt: 0
    property bool _primed: false
    property bool copied: false
    readonly property int copiedMs: 1200
    onNewestChanged: {
        if (root._primed && root.newest !== "" && root.newest !== root._lastNewest
            && root.newestAt >= root._lastAt) {
            root.copied = true
            copiedTimer.restart()
            popAnim.restart()
            if (Config.peekClipboard) peek.fire("clipboard")
        }
        root._lastNewest = root.newest
        root._lastAt = root.newestAt
    }
    Connections {
        target: Clipboard
        function onReadyChanged() { root._primed = Clipboard.ready }
    }
    Component.onCompleted: {
        root._lastNewest = root.newest
        root._lastAt = root.newestAt
        root._primed = Clipboard.ready
    }
    Timer { id: copiedTimer; interval: root.copiedMs; onTriggered: root.copied = false }
    // The copy's preview in a peek beside it (modules/panels/EventPeek).
    SidePeek { id: peek; from: "clipboard"; screen: root.screen }

    property real pop: 1
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: root; property: "pop"; to: 1.25
                          duration: Motion.fast; easing.type: Motion.enter }
        NumberAnimation { target: root; property: "pop"; to: 1
                          duration: Motion.standard; easing.bezierCurve: Motion.spring
                          easing.type: Easing.BezierSpline }
    }

    // ── The last copy, at rest ────────────────────────────────────────────────
    readonly property var latest: Clipboard.count > 0 ? Clipboard.entries[0] : null
    readonly property string latestImage: root.latest && root.latest.kind === "image" && root.latest.file
        ? "file://" + root.latest.file : ""
    readonly property string latestHex: {
        const t = root.latest && root.latest.kind !== "image" ? String(root.latest.preview || "").trim() : ""
        return /^#[0-9a-fA-F]{6}$/.test(t) ? t : ""
    }
    // What stands in for the glyph: never while the check says "got it".
    readonly property bool showThumb: root.latestImage !== "" && !root.copied
    readonly property bool showSwatch: !root.showThumb && root.latestHex !== "" && !root.copied

    SideCell {
        anchors.fill: parent
        glyph:  root.copied ? "\u{F012C}"                                    // 󰄬 check
              : root.showThumb || root.showSwatch ? "" : "\u{F014D}"         // 󰅍 clipboard-text
        tint:   root.copied ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).stateIdleFg
        active: root.open
        glyphScale: root.pop
        // The copy, as a burst behind the check while it shows (LiveShape).
        liveShape:  root.copied ? "burst" : ""
        hoverKind:  "clipboard"

        onClicked:      UiState.toggleSidePanel("clipboard", "clipboard", root.screen)
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }

    // A picture: rounded, at the glyph's size (Avatar's mask, a rounded square here).
    Item {
        id: thumb
        anchors.centerIn: parent
        width:  Config.sidebarGlyphPx
        height: width
        visible: root.showThumb
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image {
                anchors.fill: parent
                source: root.showThumb ? root.latestImage : ""
                sourceSize: Qt.size(thumb.width * 2, thumb.height * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
        Item {
            id: thumbMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            // A stencil: only its alpha counts.
            Rectangle { anchors.fill: parent; radius: Tokens.radiusXs; color: Colors.of(QsWindow.window).fg }
        }
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusXs
            color: "transparent"
            border.width: 1
            border.color: Colors.of(QsWindow.window).outline
        }
    }

    // A colour: its swatch — data, the way SideColour's are, ringed in the pill's outline
    // so one the colour of the pill doesn't vanish into it.
    Rectangle {
        anchors.centerIn: parent
        width:  Math.round(Config.sidebarGlyphPx * 0.8)
        height: width
        radius: width / 2
        visible: root.showSwatch
        color: root.showSwatch ? root.latestHex : "transparent"
        border.width: 1
        border.color: Colors.of(QsWindow.window).outline
    }
}
