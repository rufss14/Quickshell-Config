import QtQuick
import "../../config"
import "../bar"

// ── BarPreview ────────────────────────────────────────────────────────────────
// The bar, drawn inside the settings card.
//
// It exists because the real bar is unreachable from here: the overview covers the
// screen and Hyprland blurs everything behind it, so the one surface you're editing is
// the one surface you can't see. Dragging a module and then closing the overview to
// find out what happened isn't editing, it's guessing.
//
// ── It is the bar, not a picture of one ───────────────────────────────────────
// Same BarRegion, same BarGroup, same BarGroupRow, same widgets, reading the same
// Config.layout. So thickness, roundness, inset, square mode, merged mode, the
// dividers and the hover-grow are all genuinely what you'll get — none of it is
// reimplemented here, which is the only way a preview stays honest.
//
// The one difference is scale: it's laid out at the width of the card rather than the
// width of your screen, so the regions sit closer together than they really will. The
// alternative — scaling a 1920px bar down to fit — would render every pill at 0.4×
// with unreadable glyphs, and you'd be judging the layout through a magnifying glass
// backwards.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitHeight: Config.barThickness

    // Inert copies of the bar's widgets. Nothing here is wired to a panel.
    property PreviewModules registry: PreviewModules {}

    // Right-clicking a module here selects it. The page points its inspector at
    // whatever this names, so the preview is a way IN to a module's settings and not
    // just a picture of one.
    signal moduleActivated(string id)

    // The bar's own backdrop is your wallpaper. Here it's the settings card, so the
    // pills would sit on a surface a shade off from what they're built for. A dim plate
    // behind them stands in for "there is a desktop back there" — otherwise elevation
    // Bar's outline (tuned for wallpaper, alpha 0.12) reads as almost nothing.
    Rectangle {
        anchors.fill: parent
        radius: Config.barShape ? 0 : Tokens.radiusSm
        color:  Colors.alpha(Colors.base, 0.55)
        Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    property int inset: Config.barShape ? 0 : Config.barInset
    Behavior on inset { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    BarRegion {
        anchors.top:        parent.top
        anchors.left:       parent.left
        anchors.topMargin:  root.inset
        anchors.leftMargin: root.inset
        outerRoomLeft: root.inset

        BarGroupRow {
            region: "left"
            roomLeft: root.inset
            componentFor: root.registry.componentFor
            slotsClickable: true
            onSlotClicked: id => root.moduleActivated(id)
        }
    }

    BarRegion {
        anchors.top:              parent.top
        anchors.topMargin:        root.inset
        anchors.horizontalCenter: parent.horizontalCenter

        // Centred as a whole, unlike the real bar — which offsets itself so the
        // WORKSPACES group lands on true screen centre. At preview width that
        // correction would shove the region hard against one edge and misrepresent the
        // spacing, so this shows the region's contents honestly and lets the real bar
        // do the arithmetic that only makes sense at 1920px.
        BarGroupRow {
            region: "centre"
            componentFor: root.registry.componentFor
            slotsClickable: true
            onSlotClicked: id => root.moduleActivated(id)
        }
    }

    BarRegion {
        anchors.top:         parent.top
        anchors.right:       parent.right
        anchors.topMargin:   root.inset
        anchors.rightMargin: root.inset
        outerRoomRight: root.inset

        BarGroupRow {
            region: "right"
            roomRight: root.inset
            componentFor: root.registry.componentFor
            slotsClickable: true
            onSlotClicked: id => root.moduleActivated(id)
        }
    }

}
