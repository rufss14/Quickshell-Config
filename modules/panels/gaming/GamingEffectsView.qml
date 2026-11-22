pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/gamemodewatch.js" as Watch

// ── GamingEffectsView ── part of GamingPanel.qml; `panel` is the GamingPanel it belongs to. ──
ColumnLayout {
    id: effectsPage
    required property var panel
    readonly property int idx: 1
    width: panel.pagesBox.width
    x: (effectsPage.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(effectsPage.idx - panel.pg.value) * 1.4)
    visible: effectsPage.opacity > 0.01
    spacing: Tokens.spacingSm

    // Applies at once: the watcher starts or stops with the tile. A game-started mode goes off by
    // itself; a hand-started one never does.
    StyledText {
        Layout.leftMargin: Tokens.spacingXs
        text: Translation.tr("Turns on by itself when")
        variant: "caption"; emphasis: "dim"
    }
    // On an island: option cards (a badge that blooms, the card goes round and takes the accent while on), with
    // no switch pill, so the whole name fits. In the bar's panel: the shape tiles.
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: panel.island
        columns: 2
        columnSpacing: Tokens.spacingSm
        rowSpacing: Tokens.spacingSm
        uniformCellWidths: true

        OptionCard {
            Layout.fillWidth: true
            implicitHeight: Tokens.iconXl + Tokens.spacingLg + Tokens.spacingSm
            shape: "cookie12"
            symbol: "terminal"
            label: Translation.tr("gamemoderun games")
            detail: Gamemode.followAvailable
                    ? (Config.gamemodeAuto ? Translation.tr("Ends when the last one exits") : Translation.tr("Off"))
                    : Gamemode.toolsAvailable ? Translation.tr("Needs gdbus (glib2)") : Translation.tr("Needs gamemode")
            on: Config.gamemodeAuto && Gamemode.followAvailable
            enabled: Gamemode.followAvailable
            onActivated: Config.gamemodeAuto = !Config.gamemodeAuto
        }
        OptionCard {
            Layout.fillWidth: true
            implicitHeight: Tokens.iconXl + Tokens.spacingLg + Tokens.spacingSm
            shape: "burst"
            symbol: "sports_esports"
            label: Translation.tr("Steam games")
            detail: Config.gamemodeSteam ? Translation.tr("Native and Proton") : Translation.tr("Off")
            on: Config.gamemodeSteam
            onActivated: Config.gamemodeSteam = !Config.gamemodeSteam
        }
    }
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !panel.island
        columns: 2
        columnSpacing: Tokens.spacingSm
        rowSpacing: Tokens.spacingSm
        uniformCellWidths: true

        ShapeTile {
            shape: "cookie12"
            symbol: "terminal"
            label: Translation.tr("A gamemoderun game starts")
            subLabel: Gamemode.followAvailable
                      ? (Config.gamemodeAuto ? "Ends when the last one exits" : "Off")
                      : Gamemode.toolsAvailable ? "Needs gdbus (glib2)" : "Needs gamemode"
            active: Config.gamemodeAuto && Gamemode.followAvailable
            available: Gamemode.followAvailable
            help: Translation.tr("Follows games launched through gamemoderun, and ends when the last one exits")
            onToggled: Config.gamemodeAuto = !Config.gamemodeAuto
        }
        ShapeTile {
            shape: "burst"
            symbol: "sports_esports"
            label: Translation.tr("A Steam game opens")
            subLabel: Config.gamemodeSteam ? "Native and Proton, no launch option" : "No launch option needed"
            active: Config.gamemodeSteam
            help: Translation.tr("Follows any window of a Steam game — read from the game's own environment, so native Linux games count too")
            onToggled: Config.gamemodeSteam = !Config.gamemodeSteam
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.leftMargin: Tokens.spacingXs
        Layout.topMargin: Tokens.spacingXs
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("While it's on")
            variant: "caption"; emphasis: "dim"
        }
        StyledText {
            text: panel._effectCount + " of " + panel._effectTotal
            variant: "caption"
            color: panel.accent
        }
    }
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: panel.island
        columns: 2
        columnSpacing: Tokens.spacingSm
        rowSpacing: Tokens.spacingSm
        uniformCellWidths: true

        Repeater {
            model: panel.island ? panel._effects : []
            delegate: OptionCard {
                required property var modelData
                Layout.fillWidth: true
                // Taller on the island, so the eight fill the plate rather than leave room under them.
                implicitHeight: Tokens.iconXl + Tokens.spacingLg + Tokens.spacingSm
                visible: panel._shown(modelData.key)
                shape: modelData.shape
                symbol: modelData.symbol
                label: modelData.label
                detail: panel._sub(modelData)
                on: Config[modelData.key] && panel._blocker(modelData.key) === ""
                enabled: panel._blocker(modelData.key) === ""
                onActivated: Config[modelData.key] = !Config[modelData.key]
            }
        }
    }
    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !panel.island
        columns: 2
        columnSpacing: Tokens.spacingSm
        rowSpacing: Tokens.spacingSm
        uniformCellWidths: true

        Repeater {
            model: panel.island ? [] : panel._effects
            delegate: ShapeTile {
                required property var modelData
                visible: panel._shown(modelData.key)
                shape: modelData.shape
                symbol: modelData.symbol
                label: modelData.label
                subLabel: panel._sub(modelData)
                active: Config[modelData.key] && panel._blocker(modelData.key) === ""
                available: panel._blocker(modelData.key) === ""
                help: modelData.hint
                onToggled: Config[modelData.key] = !Config[modelData.key]
            }
        }
    }
}
