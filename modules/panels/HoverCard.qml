import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── HoverCard ─────────────────────────────────────────────────────────────────
// The popup a sidebar cell shows while the pointer rests on it (components/SideHover
// opens it as the side panel "hover"; UiState.sidePanelArg says what about). It is
// information, not a control — the pointer is on the CELL, so nothing here takes a
// click; the cell's own click still opens its real panel.
//
// One card, a kind per module (`kind`). The window's: the app and its title, its
// state, and what a click does. Every other module's (2026-10-31, the user's pick: "hover
// label chips"): a chip of its name and what it's doing — "Timer · 04:12 left", "Claude ·
// 1 session needs you" — sized to its text (`chipFor`).
//
// ── It keeps its own copy ─────────────────────────────────────────────────────
// A surface that fades out must keep its own copy of what it shows (CLAUDE.md): the
// window you left would blank the card on its way out. `kind` and `held` update
// while there is something to show and are never cleared.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingMd
    implicitWidth: root.kind === "window" ? Tokens.sideCardUnit * 5
        : Math.min(Tokens.sideCardUnit * 5,
                   Math.max(Tokens.sideCardUnit * 2, (body.item ? body.item.implicitWidth : 0) + root.pad * 2))
    implicitHeight: Math.min(root.maxHeight, (body.item ? body.item.implicitHeight : 0) + root.pad * 2)

    readonly property string liveKind: UiState.sidePanelArg
    property string kind: ""
    onLiveKindChanged: if (root.liveKind !== "") root.kind = root.liveKind

    // ── The focused window (kind "window") ────────────────────────────────────
    readonly property var screenOf: UiState.sidePanelScreen ?? Quickshell.screens[0]
    readonly property var liveWin: ActiveWindow.byMonitor[root.screenOf ? root.screenOf.name : ""] ?? null
    property var held: null
    onLiveWinChanged: if (root.liveWin) root.held = root.liveWin
    Component.onCompleted: {
        root.kind = root.liveKind
        if (root.liveWin) root.held = root.liveWin
    }

    Loader {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        sourceComponent: root.kind === "window" ? windowCard : root.kind !== "" ? chipCard : null
    }

    // ── Every other module (a chip) ───────────────────────────────────────────
    // Its catalogue name, and a line of what it is doing (services/ModuleGlance, the bar pills'
    // tooltips' wording too). Live while shown; a module with nothing to say gets its name alone.
    function chipFor(kind) {
        return { title: ModuleGlance.label(kind), value: ModuleGlance.value(kind) }
    }
    readonly property var chip: root.kind !== "" && root.kind !== "window" ? root.chipFor(root.kind) : null

    Component {
        id: chipCard
        Column {
            spacing: 0
            StyledText {
                width: Math.min(implicitWidth, Tokens.sideCardUnit * 5 - root.pad * 2)
                elide: Text.ElideRight
                font.bold: true
                text: root.chip ? root.chip.title : ""
            }
            StyledText {
                width: Math.min(implicitWidth, Tokens.sideCardUnit * 5 - root.pad * 2)
                visible: !!(root.chip && root.chip.value !== "")
                elide: Text.ElideRight
                variant: "caption"
                emphasis: "dim"
                text: root.chip ? root.chip.value : ""
            }
        }
    }

    Component {
        id: windowCard
        ColumnLayout {
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Image {
                    visible: !!(root.held && root.held.icon)
                    source: root.held && root.held.icon ? root.held.icon : ""
                    Layout.preferredWidth: Tokens.iconLg
                    Layout.preferredHeight: Tokens.iconLg
                    sourceSize: Qt.size(Tokens.iconLg, Tokens.iconLg)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }
                MaterialIcon {
                    visible: !(root.held && root.held.icon)
                    name: root.held ? "window" : "desktop_mac"
                    font.pixelSize: Tokens.iconLg
                    color: Colors.of(QsWindow.window).focus
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.bold: true
                        text: root.held ? (root.held.name || root.held.appId) : "Desktop"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !!(root.held && root.held.appId && root.held.appId !== root.held.name)
                        elide: Text.ElideRight
                        variant: "caption"
                        emphasis: "dim"
                        text: root.held ? root.held.appId : ""
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!(root.held && root.held.title)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                variant: "caption"
                text: root.held ? root.held.title : ""
            }

            Flow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd
                visible: !!root.held

                Repeater {
                    model: !root.held ? [] : [
                        { symbol: "workspaces",  label: "Workspace " + root.held.workspace, on: root.held.workspace > 0 },
                        { symbol: "open_with",   label: root.held.floating ? "Floating" : "Tiled", on: true },
                        { symbol: "fullscreen",  label: "Fullscreen", on: root.held.fullscreen },
                        { symbol: "push_pin",    label: "Pinned", on: root.held.pinned }
                    ].filter(f => f.on)

                    Row {
                        required property var modelData
                        spacing: Tokens.spacingXs
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: parent.modelData.symbol
                            variant: "label"
                            color: Colors.of(QsWindow.window).focus
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.label
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                variant: "caption"
                emphasis: "dim"
                text: Translation.tr("Click for window actions")
            }
        }
    }
}
