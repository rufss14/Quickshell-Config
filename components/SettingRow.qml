import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── SettingRow ────────────────────────────────────────────────────────────────
// Label + detail on the left, one control on the right. The standard shape for a
// single settings line — a toggle, a button row — across every settings page.
//
// Promoted out of BarPage.qml, which declared it as a local `component` with a
// comment saying exactly this: "exists nowhere else in the shell yet. It moves out
// the moment a second page needs it." That moment already passed — WidgetsPage's
// settings column hand-rolls this same label+control row shape inline instead of
// sharing it — so this is that move, not a new abstraction.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: settingRow

    property string label:  ""
    property string detail: ""
    // The sentence that explains the row — a tip on its label (HelpTip). `detail`
    // is for a short state ("11 apps remembered"), not this.
    property string help:   ""

    // Let the detail run to a second line instead of eliding. Off by default —
    // a column of rows that each silently change height as their detail text
    // changes is a page that jitters, so wrapping is opt-in for the rows whose
    // detail is genuinely a sentence (an explanation of the option you just
    // picked) rather than a few words of metadata.
    property bool wrapDetail: false

    // ── Optional leading icon ─────────────────────────────────────────────────
    // Additive, same shape as PanelButton's symbol/symbolFill: unset (the default)
    // renders nothing, so every existing caller is unaffected. `symbolFill` and
    // `symbolColor` are left to the caller to bind to whatever state the row shows —
    // MaterialIcon's own Behavior on fill animates the on/off transition for free.
    property string symbol:      ""
    property real   symbolFill:  0
    property color  symbolColor: Colors.of(QsWindow.window).fgMuted
    Behavior on symbolColor { ColorAnimation { duration: Motion.fast } }

    default property alias control: controlSlot.data

    // ── Too narrow for side by side: the control goes under the label ─────────
    // A grouped page flows its groups into columns, and a column can be narrower than a label
    // plus a wide control (a connected TabStrip, a pair of time fields). Squeezed side by side the
    // label elides to nothing; stacked, the label keeps its line and the control takes the row's
    // whole width under it (a TabStrip's segments then share the row).
    // "auto" stacks only when the control and `labelRoom` (or the label's own width, if shorter) no
    // longer fit; "never" and "always" fix it. A row that has the room is laid out as it always was.
    property string stack: "auto"
    // What a label is allowed to shrink to before the control moves under it.
    property int labelRoom: 140
    // The control's own width: its children's IMPLICIT widths (a child sized only by an explicit
    // `width` counts that). Not the slot's laid-out width, which grows once the row is stacked.
    readonly property real _controlW: {
        let w = 0
        for (const c of controlSlot.children)
            if (c.visible) w = Math.max(w, c.implicitWidth > 0 ? c.implicitWidth : c.width)
        return w
    }
    readonly property bool _stacked: settingRow.stack === "always"
        || (settingRow.stack === "auto" && splitGrid.width > 0 && settingRow._controlW > 0
            && settingRow._controlW + Math.min(settingRow.labelRoom, textCol.implicitWidth) + settingRow.spacing
               > splitGrid.width)
    // Stacked, a child that has a natural width is widened to the row; back side by side it goes
    // back to that natural width. Only rows that actually stack are touched, so a caller's own
    // width on a row with room is left alone. A child sized only by `width` is never resized.
    function _fitControl() {
        for (const c of controlSlot.children) {
            if (!(c.implicitWidth > 0)) continue
            const cc = c
            cc.width = settingRow._stacked ? Qt.binding(() => controlSlot.width) : Qt.binding(() => cc.implicitWidth)
        }
    }
    on_StackedChanged: settingRow._fitControl()

    // ── The whole row as the hit target (opt-in) ──────────────────────────────
    // `rowTap: true` makes a press anywhere on the row emit `tapped()`; the page says what that means
    // (`onTapped: Config.x = !Config.x`), there is no search for the Toggle. The row's own control still
    // takes a press on itself and only that: the hit area is a MouseArea UNDER the control (it lives in
    // the label column, an earlier sibling of `controlSlot`), so a Toggle's MouseArea accepts the press
    // first and Qt delivers it to no item below. A TapHandler would not do: handlers below an accepting
    // item still get the press, and the row would toggle a second time.
    //
    // A grouped Section draws this row on a tonal segment that runs past it, and sets `segInsetX/Y` to
    // how far, so the whole segment answers; it also draws the hover wash, the press and the focus ring
    // in the segment's own shape from `segHovered` / `segPressed` / `segFocused`. A row that is not on a
    // segment draws its own wash and ring.
    property bool rowTap: false
    signal tapped()
    property real segInsetX: 0
    property real segInsetY: 0
    readonly property bool segPressed: settingRow.rowTap && tapArea.pressed
    readonly property bool segHovered: settingRow.rowTap && tapHover.hovered
    readonly property bool segFocused: settingRow.rowTap && tapArea.activeFocus
    readonly property bool _onSegment: settingRow.segInsetX > 0 || settingRow.segInsetY > 0

    // Dips with its segment, on the same spring, so the two move as one.
    SpringValue { id: rowDip; target: settingRow.segPressed ? 0.98 : 1; spec: Motion.springSpatialFast; epsilon: 0.0005 }
    scale: settingRow.rowTap ? rowDip.value : 1

    // No `property bool enabled` — RowLayout is an Item, which already has one,
    // and redeclaring it would shadow the property QML uses to gate input.
    Layout.fillWidth: true
    // Pinned here, once: a layout nested in a ColumnLayout defaults fillHeight to TRUE
    // and splits the column's surplus height (docs/settings-style.md §7).
    Layout.fillHeight: false
    // A floor, not a height: a row with a two-line detail is still allowed to be
    // taller. It exists because the label and its control were the same weight and
    // the same size with nothing between them, so a column of rows had no rhythm to
    // scan — the eye couldn't find where one row ended. Tall enough that a 32px
    // control sits in it with air on both sides.
    Layout.minimumHeight: 40
    spacing: Tokens.spacingMd

    MaterialIcon {
        visible: settingRow.symbol !== ""
        Layout.alignment: Qt.AlignVCenter
        name:  settingRow.symbol
        fill:  settingRow.symbolFill
        color: settingRow.symbolColor
        variant: "body"
    }

    // Label and control: two columns side by side, one (the control under the label) when stacked.
    GridLayout {
        id: splitGrid
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignVCenter
        columns: settingRow._stacked ? 1 : 2
        columnSpacing: settingRow.spacing
        rowSpacing: Tokens.spacingSm

        ColumnLayout {
            id: textCol
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            HelpTip { id: rowTip; text: settingRow.help }

            // The rowTap hit area. A zero-size host in a spacing-0 column, so it adds no geometry, and it
            // is not laid out at all unless `rowTap` is on (a hidden item is skipped by a Layout). Its
            // children are placed over the whole row (and the segment past it) by arithmetic.
            Item {
                id: hitHost
                visible: settingRow.rowTap
                Layout.preferredWidth: 0
                Layout.preferredHeight: 0
                Layout.fillHeight: false

                readonly property real ox: -(splitGrid.x + textCol.x + hitHost.x) - settingRow.segInsetX
                readonly property real oy: -(splitGrid.y + textCol.y + hitHost.y) - settingRow.segInsetY
                readonly property real ow: settingRow.width  + settingRow.segInsetX * 2
                readonly property real oh: settingRow.height + settingRow.segInsetY * 2

                // Built only for a tappable row off a segment: a hundred plain rows pay nothing for it.
                Loader {
                    x: hitHost.ox; y: hitHost.oy; width: hitHost.ow; height: hitHost.oh
                    active: settingRow.rowTap && !settingRow._onSegment
                    sourceComponent: StateLayer {
                        radius: Tokens.radiusSm
                        hovered: settingRow.segHovered
                    }
                }
                Rectangle {
                    x: hitHost.ox; y: hitHost.oy; width: hitHost.ow; height: hitHost.oh
                    visible: !settingRow._onSegment && settingRow.segFocused
                    radius: Tokens.radiusSm
                    color: "transparent"
                    border.width: Tokens.borderWidth * 2
                    border.color: Colors.of(QsWindow.window).outlineFocus
                }

                MouseArea {
                    id: tapArea
                    x: hitHost.ox; y: hitHost.oy; width: hitHost.ow; height: hitHost.oh
                    enabled: settingRow.rowTap && settingRow.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingRow.tapped()

                    // Passive, so the wash stays lit while the pointer is over the row's own control,
                    // which takes hover from the MouseArea beneath it.
                    HoverHandler { id: tapHover; enabled: tapArea.enabled }

                    // Tab reaches the row; Space or Enter is a tap. A click does not take focus, so the
                    // ring is the keyboard's alone.
                    activeFocusOnTab: settingRow.rowTap
                    Keys.onSpacePressed:  settingRow.tapped()
                    Keys.onReturnPressed: settingRow.tapped()
                    Keys.onEnterPressed:  settingRow.tapped()

                    Accessible.role: Accessible.Button
                    Accessible.name: settingRow.label
                    Accessible.description: settingRow.detail
                    Accessible.onPressAction: settingRow.tapped()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text:    settingRow.label
                    variant: "body"
                    // The label is the row's anchor and the detail is a footnote to it;
                    // at the same weight they read as one run-on line.
                    font.weight: Font.Medium
                    elide:   Text.ElideRight
                }
                MaterialIcon {
                    visible: settingRow.help !== ""
                    name: "info"
                    color: Colors.of(QsWindow.window).fgDim
                    font.pixelSize: Tokens.iconSm
                    opacity: rowTip.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                Item { Layout.fillWidth: true }
            }
            StyledText {
                Layout.fillWidth: true
                visible:  settingRow.detail !== ""
                text:     settingRow.detail
                variant:  "caption"
                emphasis: "dim"
                wrapMode: settingRow.wrapDetail ? Text.WordWrap : Text.NoWrap
                elide:    settingRow.wrapDetail ? Text.ElideNone : Text.ElideRight
            }
        }

        Item {
            id: controlSlot
            Layout.alignment: settingRow._stacked ? (Qt.AlignLeft | Qt.AlignVCenter) : Qt.AlignVCenter
            Layout.fillWidth: settingRow._stacked
            // Stacked, the natural width (not childrenRect, which follows the widened children).
            Layout.preferredWidth:  settingRow._stacked ? settingRow._controlW : childrenRect.width
            Layout.preferredHeight: childrenRect.height
            // A Toggle/slider has no text of its own; a screen reader names it by this row's
            // label, unless the caller already gave it one.
            Component.onCompleted: {
                for (const c of controlSlot.children)
                    if (c.accessibleName !== undefined && c.accessibleName === "")
                        c.accessibleName = Qt.binding(() => settingRow.label)
                if (settingRow._stacked) settingRow._fitControl()
            }
        }
    }
}
