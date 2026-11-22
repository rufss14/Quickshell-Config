pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../"

// ── TabletProfilesView ────────────────────────────────────────────────────────
// A tablet keeps several sets of settings and one of them is in use: one for drawing across both screens,
// one for pointing at a single monitor, one turned for a left hand. Pressing a row makes it the active one at
// once (and an express key can switch them: Settings › Tablet). New starts from the stock settings; the copy
// tool on a row starts from that row's.
//
// The list is a plate that scrolls, so twelve profiles (the most there are) do not push the page out of its
// island. The rows are TabletProfileRow.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    order: 1

    function _summary(p) {
        return (p.output === "" ? Translation.tr("All screens") : p.output)
            + " · " + Math.round(p.area.w) + " × " + Math.round(p.area.h) + " mm"
            + (p.relative ? " · " + Translation.tr("Relative") : "")
            + (p.rotation !== 0 ? " · " + p.rotation + "°" : "")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            TabletPlateTitle {
                Layout.fillWidth: true
                symbol: "layers"
                shape: "clover"
                title: Translation.tr("Profiles")
                note: Translation.tr("%1 for this tablet").arg(Tablet.profiles.length)
            }
            ChipButton {
                solid: true
                symbol: "add"
                label: Translation.tr("New")
                enabled: Tablet.ready && Tablet.profiles.length < 12
                onActivated: Tablet.addProfile(Translation.tr("Profile"))
                HoverTip { text: Translation.tr("A profile with the stock settings"); alignEnd: true }
            }
        }

        Flickable {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: rows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: rows
                width: list.width
                spacing: Tokens.spacingSm

                Repeater {
                    model: Tablet.profiles
                    delegate: TabletProfileRow {
                        id: row
                        required property var modelData
                        required property int index
                        width: rows.width
                        name: row.modelData.name
                        summary: root._summary(row.modelData)
                        active: Tablet.profile !== null && Tablet.profile.name === row.modelData.name
                        canRemove: Tablet.profiles.length > 1
                        shape: ["cookie9", "clover", "sunny", "squircle", "pentagon", "hexagon"][row.index % 6]
                        onPicked: Tablet.select(row.modelData.name)
                        onCopied: { Tablet.select(row.modelData.name); Tablet.copyProfile() }
                        onRenamed: to => Tablet.renameProfile(row.modelData.name, to)
                        onRemoved: Tablet.removeProfile(row.modelData.name)
                    }
                }
            }
        }
    }
}
