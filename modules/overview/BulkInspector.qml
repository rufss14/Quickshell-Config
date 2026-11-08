pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── BulkInspector ─────────────────────────────────────────────────────────────
// The overview's bottom island, turned to a SELECTION: the windows Ctrl+clicked in the grid
// (Switcher.marks), or Ctrl+A's — everything the search shows, so `app:kitty` then Ctrl+A is "all
// my terminals". What you can do to all of them at once, in WindowInspector's language:
//
//   (ico)(ico)(ico)  3 windows                ╭ float pin ╮ Clear   1 2 3 4 5   (x)
//                    kitty, Zen · on 1, 2     ╰───────────╯         6 7 8 9 10
//
// Float and pin are one switch for the lot: if every window already has it, they all lose it;
// otherwise the ones without get it (a plain toggle on each would swap the odd ones out). A
// workspace chip sends them all there. Close asks twice. Dragging any ONE of them in the grid, or
// Shift+clicking a cell, moves the lot too (WorkspaceGrid). Every action is ActiveWindow's.
// Keys (Overview.steer): Ctrl+F float, Ctrl+P pin, Ctrl+W close (twice), Ctrl+1…0 send, Esc clears.
//
// Like the inspector it keeps its own copy of the windows (`held`), so the island fades out showing
// what it was showing.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The Switcher records of the marked windows.
    property var wins: []
    property int firstWorkspace: 1
    property color accent: Colors.of(QsWindow.window).primary

    property var held: []
    onWinsChanged: if (root.wins.length > 0) root.held = root.wins
    Component.onCompleted: if (root.wins.length > 0) root.held = root.wins
    readonly property var list: root.held

    // A window's state, read live (Hyprland's lastIpcObject, which notifies on every refresh —
    // only while this is built).
    function _floating(w) { return Hypr.geometryOf(w.toplevel).floating }
    function _pinned(w)   { return w.toplevel?.lastIpcObject?.pinned ?? false }
    readonly property bool allFloating: root.list.length > 0 && root.list.every(w => root._floating(w))
    readonly property bool allPinned:   root.list.length > 0 && root.list.every(w => root._pinned(w))

    // Which workspaces they are on, and which apps: the quiet line under the count.
    readonly property var spaces: {
        const seen = []
        for (const w of root.list) if (seen.indexOf(w.workspaceId) < 0) seen.push(w.workspaceId)
        return seen.sort((a, b) => a - b)
    }
    readonly property var apps: {
        const seen = []
        for (const w of root.list) {
            const n = w.appName || w.appClass
            if (n && seen.indexOf(n) < 0) seen.push(n)
        }
        return seen
    }
    readonly property string summary: {
        const shown = root.apps.slice(0, 2).join(", ") + (root.apps.length > 2 ? " +" + (root.apps.length - 2) : "")
        return shown + "  ·  on " + root.spaces.slice(0, 4).join(", ") + (root.spaces.length > 4 ? " …" : "")
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    function floatAll() {
        const want = !root.allFloating
        for (const w of root.list) if (root._floating(w) !== want) ActiveWindow.toggleFloating(w.address)
    }
    function pinAll() {
        const want = !root.allPinned
        for (const w of root.list) if (root._pinned(w) !== want) ActiveWindow.togglePin(w.address)
    }
    function sendAll(ws) {
        for (const w of root.list) if (w.workspaceId !== ws) ActiveWindow.toWorkspace(w.address, ws)
        root.moved(ws)
    }
    function requestClose() { closeLatch.trigger() }

    // The windows were sent to `ws` from here — the grid rings that cell.
    signal moved(int ws)

    ArmLatch {
        id: closeLatch
        onConfirmed: {
            for (const w of root.list) ActiveWindow.close(w.address)
            Switcher.clearMarks()
        }
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Tokens.spacingLg

        // ── Who is in it: their icons, overlapping ────────────────────────────
        Item {
            id: stack
            readonly property int shown: Math.min(5, root.list.length)
            readonly property int disc: Tokens.iconXl + Tokens.spacingSm
            readonly property int step: Math.round(disc * 0.62)
            Layout.alignment: Qt.AlignVCenter
            SpringValue {
                id: stackW
                target: stack.disc + (stack.shown - 1) * stack.step
                spec: Motion.springSpatial
            }
            Layout.preferredWidth: stackW.value
            Layout.preferredHeight: stack.disc

            Repeater {
                model: stack.shown
                delegate: Rectangle {
                    id: disc
                    required property int index
                    readonly property string path: Icons.pathForAppId(root.list[disc.index]?.appClass ?? "")
                    x: disc.index * stack.step
                    // Earlier ones on top, so the first window reads as the lead.
                    z: stack.shown - disc.index
                    width: stack.disc
                    height: stack.disc
                    radius: width / 2
                    color: Colors.of(QsWindow.window).surfaceHigh
                    border.width: Tokens.borderChrome
                    border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.4)
                    Image {
                        anchors.centerIn: parent
                        visible: disc.path !== ""
                        source: disc.path
                        width: Tokens.iconLg
                        height: Tokens.iconLg
                        sourceSize: Qt.size(Tokens.iconLg, Tokens.iconLg)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: disc.path === ""
                        name: "window"
                        color: root.accent
                        font.pixelSize: Tokens.iconMd
                    }
                }
            }
        }

        // ── What it is ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 220
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            StyledText {
                Layout.fillWidth: true
                text: root.list.length + (root.list.length === 1 ? " window" : " windows")
                variant: "title"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: root.summary
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        // ── What you can do to all of them ────────────────────────────────────
        ChipTray {
            Layout.alignment: Qt.AlignVCenter
            ChipButton {
                symbol: "open_with"
                on: root.allFloating
                tint: root.accent
                onActivated: root.floatAll()
            }
            ChipButton {
                symbol: "keep"
                on: root.allPinned
                tint: root.accent
                onActivated: root.pinAll()
            }
            ChipButton {
                label: Translation.tr("Clear")
                tint: root.accent
                onActivated: Switcher.clearMarks()
            }
        }

        // ── Send them to a workspace ──────────────────────────────────────────
        WorkspaceChips {
            Layout.alignment: Qt.AlignVCenter
            firstWorkspace: root.firstWorkspace
            // Every one of them is already there.
            here: root.spaces.length === 1 ? root.spaces : []
            accent: root.accent
            onPicked: ws => root.sendAll(ws)
        }

        // ── Close them all — twice ────────────────────────────────────────────
        CookieButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 44
            implicitHeight: 44
            name: closeLatch.armed ? "delete" : "close"
            tint: Colors.of(QsWindow.window).danger
            primary: closeLatch.armed
            points: 6
            onActivated: root.requestClose()
        }
    }
}
