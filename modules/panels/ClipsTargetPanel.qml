pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ClipsTargetPanel ──────────────────────────────────────────────────────────
// What to capture, beside the clips button: a hold on the button opens it straight
// away (the charge arc, then this), and the Clips panel's "Change" swaps to it.
//
//   Clip from   what the replay buffer records from now on (Clips.retarget) — a
//               monitor, a window's area, a dragged region, or the portal
//   Record      record that, NOW (Clips.recordTarget)
//
// The list is BUILT, not bound: which windows are on screen walks
// Hyprland.monitors, a lazy model a binding over would re-enter (CLAUDE.md). It's
// filled when the panel opens and again whenever Hypr's windows change, with Hypr's
// event tier held for as long as it's up.
//
// Restyled (2026-10-18) to the clips panel's look: a ChipTray header, a SegmentSwitch for what a
// pick does, and the choices as pills under small headings (monitors, windows, the rest), each
// arriving on a spring.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 7
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // "clip" | "record" — what a pick does.
    property string mode: "clip"
    property var choices: []
    function _fill() { root.choices = Clips.targetChoices() }

    Component.onCompleted: { Hypr.acquireEvents(); root._fill() }
    Component.onDestruction: Hypr.releaseEvents()
    Connections {
        target: Hypr
        function onWindowsChanged() { root._fill() }
    }

    function pick(key) {
        if (root.mode === "clip") Clips.retarget(key)
        else Clips.recordTarget(key)
        UiState.closeSidePanel()
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph:     "\u{F04FE}"                                          // 󰓾 target
            title:     Translation.tr("Capture")
            titleTail: "target"
            accent:    root.mode === "record" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
            subtitle:  root.mode === "clip" ? "Clipping records from here on"
                                            : "Starts a recording of it now"

            // Back to the clips panel it came from.
            ChipTray {
                ChipButton {
                    symbol: "arrow_back"
                    tint: root.mode === "record" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
                    onActivated: UiState.openSidePanel("clips", UiState.sidePanelFrom, UiState.sidePanelScreen)
                }
            }
        }

        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            accent: root.mode === "record" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
            model: [{ value: "clip",   label: "Clip from", icon: "replay" },
                    { value: "record", label: "Record",    icon: "fiber_manual_record" }]
            current: root.mode
            onPicked: function (v) { root.mode = v }
        }

        Column {
            Layout.fillWidth: true
            spacing: Tokens.spacingXs

            Repeater {
                model: root.choices
                delegate: Item {
                    id: choice
                    required property var modelData
                    required property int index

                    // The buffer's own target, checked — only while picking for it.
                    readonly property bool current: root.mode === "clip" && choice.modelData.key === Clips.targetKey
                    // A rule between monitors, windows and the rest.
                    readonly property bool newKind: choice.index > 0
                        && root.choices[choice.index - 1].kind !== choice.modelData.kind

                    // A small heading where the kind changes (and above the first).
                    readonly property bool headed: choice.index === 0 || choice.newKind
                    readonly property real headH: choice.headed ? headText.implicitHeight + Tokens.spacingSm * 2 : 0

                    width: parent.width
                    height: choice.headH + rowBox.height
                    enabled: choice.modelData.enabled

                    PopIn { id: rowPop; active: true; index: choice.index; cap: 8; step: Motion.stagger }

                    StyledText {
                        id: headText
                        visible: choice.headed
                        y: Tokens.spacingSm
                        x: Tokens.spacingMd
                        text: choice.modelData.kind === "monitor" ? "Monitors"
                            : choice.modelData.kind === "window"  ? "Windows" : "Other"
                        variant: "micro"
                        emphasis: "dim"
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        id: rowBox
                        y: choice.headH
                        width: parent.width
                        height: Tokens.sideCardUnit * 0.75
                        radius: height / 2
                        color: choice.current ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.2)
                             : rowMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.1)
                             : Colors.of(QsWindow.window).section
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        opacity: (choice.enabled ? 1 : 0.4) * rowPop.opacity
                        scale: rowPop.scale

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingMd
                            MaterialIcon {
                                glyph: choice.current ? "\u{F012C}" : choice.modelData.glyph   // 󰄬 check
                                variant: "label"
                                color: choice.current ? Colors.of(QsWindow.window).focus
                                     : root.mode === "record" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: choice.modelData.label
                                variant: "caption"
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pick(choice.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
