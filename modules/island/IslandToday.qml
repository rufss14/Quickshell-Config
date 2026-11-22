import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── IslandToday ───────────────────────────────────────────────────────────────
// The Dashboard, the card's first page, after Caelestia's and in the panels' dialect: three columns of flat cards that
// arrive one after another on springs. Left, the loud one — the time and the weather on the accent container
// (IslandHeroNow) — over the machine's rings (IslandRings). In the middle, who you are (IslandUser) over the month
// (IslandMonth). On the right the player (IslandNow, with the player's own volume) over your switches (IslandSwitches),
// which take only their rows' height. The side columns are one width. The card
// gives the page its size; it fills. Weather, the machine's numbers and the playhead are held only while this shows.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted: { Weather.acquire(); SysInfo.acquire(); Storage.acquire() }
    Component.onDestruction: { Weather.release(); SysInfo.release(); Storage.release() }

    MediaPosition {
        id: track
        active: root.visible
        scrubbing: now.scrubbing
    }
    // The two side columns' width, and the stats card's height. The switches hug their rows, so the player above them
    // gets the rest.
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property int lowH: Tokens.spacingXl * 8

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd
            IslandHeroNow {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 0
            }
            IslandRings {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: root.lowH
                order: 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd
            IslandUser {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingLg
                order: 1
            }
            IslandMonth {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 2
            }
        }

        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd
            IslandNow {
                id: now
                Layout.fillWidth: true
                Layout.fillHeight: true
                media: track
                order: 3
            }
            IslandSwitches {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: implicitHeight
                order: 4
                onSettingsOpened: UiState.closeIsland(UiState.islandOfPage("today"))
            }
        }
    }
}
