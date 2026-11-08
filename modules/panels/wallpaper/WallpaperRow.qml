import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// One entry in the list view. Shares WallpaperEntry with the grid tile.
Rectangle {
    id: row
    required property var panel
    required property var modelData
    required property int index
    readonly property var entry: row.modelData

    // The keyboard's cursor is on this row (WallpaperPanel.kbIndex).
    readonly property bool kbFocused: panel.kbOn && panel.kbIndex === row.index

    WallpaperEntry { id: st; panel: row.panel; entry: row.entry }

    implicitHeight: 52
    radius: Tokens.radiusCard
    // `surfaceHigh` IS "that surface, hovered" — the role exists for exactly this. The
    // old row doubled surfaceContainer's own alpha to fake the lift, which stopped
    // meaning anything once the surfaces became opaque: `.a` is 1, so `* 2` clamps
    // straight back to 1 and the hover silently became a no-op.
    // The wallpaper on show, and a ticked row, are TONAL (primaryContainer), as the grid's tile frame is.
    color: (st.isCurrent || st.selected) ? Colors.of(QsWindow.window).primaryContainer
         : rowHover.hovered ? Colors.of(QsWindow.window).surfaceHigh : Colors.of(QsWindow.window).surfaceContainer
    border.width: row.kbFocused ? 2 : st.removeLatch.armed ? 1 : 0
    border.color: row.kbFocused ? Colors.of(QsWindow.window).focus
                : st.removeLatch.armed ? Colors.of(QsWindow.window).danger
                : Colors.of(QsWindow.window).outline
    Behavior on color        { ColorAnimation { duration: Motion.respond } }
    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingSm
        spacing: Tokens.spacingMd

        // The action row keeps the thumbnail column so its glyph lines up with
        // every picture below it — a ragged left edge on the first row alone
        // reads as a layout bug.
        ClippingRectangle {
            Layout.preferredWidth:  64
            Layout.fillHeight: true
            radius: Tokens.radiusXs
            color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

            // The action row keeps the thumbnail column so its cookie lines up with every picture below it.
            ScallopChip {
                anchors.centerIn: parent
                visible: st.isAction
                glyph: st.isAction ? row.entry.glyph : ""
                tint:  Colors.of(QsWindow.window).focus
                hot:   rowHover.hovered
            }
            Image {
                anchors.fill: parent
                visible: !st.isAction
                source: panel.bust(st.thumb)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width:  160
                sourceSize.height: 100
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: st.name
                variant: "body"
                font.weight: st.isAction ? Font.DemiBold : Font.Normal
                elide: Text.ElideMiddle
            }
            StyledText {
                Layout.fillWidth: true
                // A list is read rather than pointed at, so this line carries what a
                // scene IS — "video" costs noticeably more GPU than "scene", and that
                // is worth knowing before applying one.
                text: st.removeLatch.armed     ? (st.isScene ? "Press ✕ again to delete and unsubscribe"
                                                   : "Press ✕ again to move it to the trash")
                    : st.isAction  ? row.entry.caption
                                        : st.isCurrent ? "Current wallpaper"
                    : st.isScene && WallpaperEngine.stillSubscribed(st.key) ? "Steam put it back: still subscribed"
                    : st.isScene   ? st.kind
                    : "Click to apply"
                variant: "caption"
                emphasis: "dim"
                color: st.removeLatch.armed ? Colors.of(QsWindow.window).danger
                     : st.isCurrent ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                     : Colors.of(QsWindow.window).fgDim
                elide: Text.ElideRight
            }
        }

        MaterialIcon {
            visible: st.isCurrent
            name: "check"
            fill: 1
            color: panel.accent
            variant: "body"
        }

        // Always present in list view, not only on hover: a list is scanned by reading
        // rather than by pointing, so the action should be visible without hunting for
        // it. Hidden on the active wallpaper, where re-applying is a no-op.
        PanelButton {
            Layout.alignment: Qt.AlignVCenter
            visible: !panel.selecting && (panel.pickingActive ? st.isScene : (!st.applied && !st.isAction))
            variant: "normal"
            label: panel.pickingActive ? "Assign" : (st.busy ? "Applying…" : "Apply")
            enabled: panel.pickingActive ? true : (!panel.applyBusy && panel.blocked === "")
            onActivated: st.doApply()
        }
        PanelButton {
            Layout.alignment: Qt.AlignVCenter
            visible: !panel.selecting && !panel.pickingActive && st.isScene
            variant: "ghost"
            symbol: "equalizer"
            onActivated: panel.openProperties(st.key)
        }
        // The star: a filled gold one when it is a favourite, an outline when it is not.
        PanelButton {
            Layout.alignment: Qt.AlignVCenter
            visible: !panel.selecting && !st.isAction
            variant: "ghost"
            symbol: "star"
            symbolFill: st.isFav ? 1 : 0
            glyphTint: st.isFav ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
            onActivated: st.toggleFav()
        }
        PanelButton {
            Layout.alignment: Qt.AlignVCenter
            visible: !panel.selecting && !st.isAction
            variant: st.removeLatch.armed ? "primary" : "ghost"
            accent: Colors.of(QsWindow.window).danger
            symbol: st.isScene ? "delete_forever" : "delete"
            symbolFill: st.removeLatch.armed ? 1 : 0
            label: st.removeLatch.armed ? "Remove?" : ""
            onActivated: st.doRemove()
        }
        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: panel.selecting && !st.isAction
            name: st.selected ? "check_box" : "check_box_outline_blank"
            fill: st.selected ? 1 : 0
            color: st.selected ? panel.accent : Colors.of(QsWindow.window).fgDim
            variant: "title"
        }
    }

    // Hover as a handler, for the same reason as the tile: the row carries two
    // buttons with their own MouseAreas, and hover must survive crossing them.
    HoverHandler {
        id: rowHover
        onHoveredChanged: if (!hovered) st.removeLatch.disarm()
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: panel.selecting || panel.pickingActive
            ? true
            : (st.isAction || (!panel.applyBusy && panel.blocked === ""))
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) { if (m.button === Qt.RightButton) st.doChoose(); else st.doApply() }
        // z: -1 is load-bearing. This is declared AFTER the RowLayout, so by default it
        // would sit on top and swallow every click meant for the Apply button — the
        // button would still look interactive and never light up. Pushing it behind
        // lets the button take the click when the pointer is on it, and this handles
        // everywhere else in the row.
        z: -1
    }
}
