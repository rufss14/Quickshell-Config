pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "toggles.js" as Toggles

// ── TogglesWidget ─────────────────────────────────────────────────────────────
// The shell's switches on the desktop: Wi-Fi, Bluetooth, Do not disturb, night light, and
// whatever else `opts.toggles` names. Small shows four as a 2×2, medium four in a row with
// names, large eight.
//
// ── No switch logic lives here ────────────────────────────────────────────────
// State, "why can't it run" and the action itself all come from ShellActions — the same
// table the launcher's toggle rows use — so a toggle here and one there cannot disagree.
// The one exception is Bluetooth's power, which ShellActions doesn't carry (its row opens
// the panel): that is `Bt.adapter.enabled`, written directly exactly as the Bluetooth
// panel and page do (Bt.qml says why there is no wrapper). A missing adapter disables the
// button with its reason, the shell's blocker() contract.
//
// ── Material 3 Expressive toggle buttons ──────────────────────────────────────
// Off: a round tonal button. On: it MORPHS into a filled cookie in the accent, the icon
// flipping to its filled/"on" form — the shape change is the state, which reads from
// across the room in a way a colour change alone doesn't. Pressing squashes it on the fast
// spatial spring; hover swells it a touch.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    // What each id looks like (toggles.js, shared with Settings). State and action are
    // ShellActions' (below).
    readonly property var table: Toggles.TABLE

    readonly property var ids: (root.opts.toggles ?? []).filter(id => root.table[id] !== undefined)
        .slice(0, root.size === "large" ? 8 : 4)

    function isOn(id) {
        if (id === "bluetooth") return Bt.powered
        const s = ShellActions.stateOf(id)
        return s === "On" || s === "Muted" || s === "Light"
    }
    function blocker(id) {
        if (id === "bluetooth") return Bt.available ? "" : "No Bluetooth adapter"
        return ShellActions.blockerOf(id)
    }
    function flip(id) {
        if (root.blocker(id) !== "") return
        if (id === "bluetooth") { if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled }
        else ShellActions.run(id)
    }

    WidgetEmpty {
        visible: root.ids.length === 0
        icon: "dashboard"
        text: Translation.tr("Pick toggles in Settings → Widgets")
    }

    GridLayout {
        anchors.fill: parent
        visible: root.ids.length > 0
        columns: root.size === "small" ? 2 : 4
        rowSpacing: Tokens.spacingSm
        columnSpacing: Tokens.spacingSm

        Repeater {
            model: root.ids
            ToggleButton {
                required property string modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                tid: modelData
            }
        }
    }

    component ToggleButton: Item {
        id: btn
        property string tid: ""
        readonly property var meta: root.table[btn.tid] ?? { label: "", on: "", off: "" }
        readonly property bool lit: root.isOn(btn.tid)
        readonly property string why: root.blocker(btn.tid)
        readonly property bool named: root.size !== "small"

        opacity: btn.why === "" ? 1 : 0.4

        ColumnLayout {
            anchors.fill: parent
            spacing: Tokens.spacingXs

            Item {
                id: face
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property real side: Math.min(width, height, Tokens.iconXl * 2 + Tokens.spacingLg)

                SpringValue {
                    id: squash
                    spec: Motion.springSpatialFast
                    epsilon: 0.0005
                    target: mouse.pressed ? 0.88 : mouse.containsMouse && btn.why === "" ? 1.06 : 1
                }

                MorphShape {
                    anchors.centerIn: parent
                    width: face.side
                    height: face.side
                    scale: squash.value
                    spec: Motion.springSpatialFast
                    shape: Config.barShape ? "squircle" : btn.lit ? "cookie9" : "circle"
                    fillColor: btn.lit ? root.accent : Colors.of(QsWindow.window).surfaceHigh
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    scale: squash.value
                    name: btn.lit ? btn.meta.on : btn.meta.off
                    fill: btn.lit ? 1 : 0
                    font.pixelSize: Math.round(face.side * 0.4)
                    color: btn.lit ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                }
                MouseArea {
                    id: mouse
                    anchors.centerIn: parent
                    width: face.side
                    height: face.side
                    enabled: btn.why === ""
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.flip(btn.tid)
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: btn.named
                horizontalAlignment: Text.AlignHCenter
                text: btn.meta.label
                variant: "caption"
                font.weight: btn.lit ? Font.DemiBold : Font.Normal
                color: btn.lit ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgMuted
                elide: Text.ElideRight
            }
        }
    }
}
