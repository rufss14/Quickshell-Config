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
// away (the charge arc, then this), and the Clips panel's edit chip swaps to it.
//
//   Clip from   what the replay buffer records from now on (Clips.retarget) — a
//               monitor, a window's area, a dragged region, or the portal
//   Record      record that, NOW (Clips.recordTarget)
//
// Keys: Up / Down move, Enter picks, Tab flips between Clip from and Record.
//
// The list is BUILT, not bound: which windows are on screen walks Hyprland.monitors, a lazy
// model a binding over would re-enter. It is filled when the panel opens and again whenever
// Hypr's windows change, with Hypr's event tier held for as long as it's up — and replaced only
// when what it lists is different, so a window opening elsewhere does not rebuild the rows.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property int pad: Tokens.spacingXl
    implicitWidth: Tokens.sideCardUnit * 7
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // "clip" | "record" — what a pick does.
    property string mode: "clip"
    readonly property color accent: root.mode === "record" ? root.pal.danger : root.pal.primary
    property var choices: []
    property string _sig: ""
    // The row the keyboard is on; -1 until a key moves it.
    property int cursor: -1
    function _fill() {
        const next = Clips.targetChoices()
        const sig = JSON.stringify(next)
        if (sig === root._sig) return
        root._sig = sig
        root.choices = next
        root.cursor = Math.min(root.cursor, next.length - 1)
    }

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

    // The dock hands over a key nothing in the panel took.
    function handleKey(event) {
        const n = root.choices.length
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.mode = root.mode === "clip" ? "record" : "clip"
            return true
        }
        if (n === 0) return false
        // Skip a row that can't be picked (a region with no slurp).
        const step = d => {
            let i = root.cursor
            for (let k = 0; k < n; k++) {
                i = (i + d + n) % n
                if (root.choices[i].enabled) return i
            }
            return root.cursor
        }
        if (event.key === Qt.Key_Down) { root.cursor = step(1); return true }
        if (event.key === Qt.Key_Up)   { root.cursor = step(-1); return true }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.cursor >= 0) {
            root.pick(root.choices[root.cursor].key)
            return true
        }
        return false
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
            titleTail: Translation.tr("target")
            accent:    root.accent
            subtitle:  root.mode === "clip" ? Translation.tr("Clipping records from here on")
                                            : Translation.tr("Starts a recording of it now")

            // Back to the clips panel it came from.
            ChipTray {
                ChipButton {
                    symbol: "arrow_back"
                    tint: root.mode === "record" ? root.pal.danger : root.pal.focus
                    onActivated: UiState.openSidePanel("clips", UiState.sidePanelFrom, UiState.sidePanelScreen)
                }
            }
        }

        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            accent: root.accent
            model: [{ value: "clip",   label: Translation.tr("Clip from"), icon: "replay" },
                    { value: "record", label: Translation.tr("Record"),    icon: "fiber_manual_record" }]
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
                    readonly property bool onCursor: root.cursor === choice.index
                    // A small heading where the kind changes (and above the first).
                    readonly property bool headed: choice.index === 0
                        || root.choices[choice.index - 1].kind !== choice.modelData.kind
                    readonly property real headH: choice.headed ? headText.implicitHeight + Tokens.spacingSm * 2 : 0
                    readonly property string iconSource: choice.modelData.icon ?? ""

                    width: parent.width
                    height: choice.headH + rowBox.height
                    enabled: choice.modelData.enabled

                    PopIn { id: rowPop; active: true; index: choice.index; cap: 8; step: Motion.stagger }

                    StyledText {
                        id: headText
                        visible: choice.headed
                        y: Tokens.spacingSm
                        x: Tokens.spacingMd
                        text: choice.modelData.kind === "monitor" ? Translation.tr("Monitors")
                            : choice.modelData.kind === "window"  ? Translation.tr("Windows") : Translation.tr("Other")
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
                        color: choice.current ? root.pal.alpha(root.pal.focus, 0.2)
                             : rowMouse.containsMouse || choice.onCursor ? root.pal.stateHoverBg
                             : root.pal.section
                        border.width: choice.onCursor ? Tokens.borderWidth : 0
                        border.color: root.pal.focus
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        opacity: (choice.enabled ? 1 : 0.4) * rowPop.opacity
                        scale: rowPop.scale

                        Accessible.role: Accessible.Button
                        Accessible.name: choice.modelData.label
                        Accessible.checked: choice.current
                        Accessible.onPressAction: root.pick(choice.modelData.key)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingMd
                            // The window's own icon (read synchronously: the icon provider must not load async);
                            // everything else, and a window with none, is a glyph.
                            Item {
                                implicitWidth: Tokens.iconLg
                                implicitHeight: Tokens.iconLg
                                Image {
                                    anchors.fill: parent
                                    visible: choice.iconSource !== "" && !choice.current
                                    source: choice.iconSource
                                    sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: choice.iconSource === "" || choice.current
                                    glyph: choice.current ? "\u{F012C}" : choice.modelData.glyph   // 󰄬 check
                                    variant: "label"
                                    color: choice.current ? root.pal.focus
                                         : root.mode === "record" ? root.pal.danger : root.pal.fgMuted
                                }
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
