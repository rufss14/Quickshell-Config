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
// Bluetooth's power is the one switch ShellActions' table doesn't run (its row opens the
// panel): `switchOn` / `switchFlip` write `Bt.adapter.enabled` directly, as the Bluetooth
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

    function isOn(id) { return ShellActions.switchOn(id) }
    function blocker(id) { return ShellActions.blockerOf(id) }
    function flip(id) { ShellActions.switchFlip(id) }

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
            delegate: ToggleOrb {
                id: orb
                required property string modelData
                readonly property var meta: root.table[orb.modelData]
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: orb.meta.label
                symbolOn: orb.meta.on
                symbolOff: orb.meta.off
                lit: root.isOn(orb.modelData)
                why: root.blocker(orb.modelData)
                named: root.size !== "small"
                accent: root.accent
                onActivated: root.flip(orb.modelData)
            }
        }
    }
}
