pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/updatefmt.js" as UF

// ── UpdateIslandHero ── part of UpdatePanel.qml (island form); `panel` is the UpdatePanel. ─────────────────────
// The update page's loud card on an island, upright in the left column (the other pages' recipe), in place of the
// panel's title row:
//
//   top     what is going on (the panel's own symbol and line: checking, n pending, step 3 of 7, done), re-check
//   middle  how many updates wait, as a big number, and where they come from as three cards (Official, AUR,
//           Flatpak) with their counts; while running, the step and the time instead
//   foot    when it last looked, the log and Cancel while a run is going (Cancel asks on the row), Setup
//
// The panel's views (what is pending, the password, the run and its questions) stand beside it, unchanged.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: hero.palette.fgOnPrimaryContainer
    readonly property color inkDim: hero.palette.alpha(hero.palette.fgOnPrimaryContainer, 0.72)
    readonly property bool running: hero.panel.viewState.view === "running"
    // The three sources, each with its shape and its tone in the share bar (the accent, then two steps quieter).
    readonly property var sources: [
        { t: Translation.tr("Official"), n: Updates.count,        s: "cookie9", tone: hero.palette.primary },
        { t: Translation.tr("AUR"),      n: Updates.aurCount,     s: "clover",  tone: hero.palette.alpha(hero.palette.primary, 0.6) },
        { t: Translation.tr("Flatpak"),  n: Updates.flatpakCount, s: "sunny",   tone: hero.palette.alpha(hero.palette.primary, 0.35) }
    ]
    // The three largest version changes (updatefmt.js bump), major first, then by name.
    readonly property var jumps: Updates.packages
        .map(p => ({ name: p.name, from: p.from, to: p.to, kind: UF.bump(p.from, p.to) }))
        .filter(p => p.kind === "major" || p.kind === "minor" || p.kind === "new")
        .sort((a, b) => UF.bumpRank(a.kind) - UF.bumpRank(b.kind) || a.name.localeCompare(b.name))
        .slice(0, 3)
    property bool confirmCancel: false

    radius: Tokens.radiusXl
    color: hero.palette.primaryContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingMd
                implicitHeight: implicitWidth
                MorphShape {
                    anchors.fill: parent
                    shape: hero.panel.isBusy ? "burst" : Updates.total > 0 ? "cookie9" : "sunny"
                    spec: Motion.springSpatialFast
                    fillColor: hero.palette.primary
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: hero.panel.heroSymbol()
                    fill: 1
                    color: hero.palette.fgOnPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("System update")
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: hero.ink
                }
                StyledText {
                    Layout.fillWidth: true
                    text: hero.panel.heroSubtitle()
                    variant: "caption"
                    color: hero.inkDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            ChipButton {
                visible: !hero.running
                symbol: "refresh"
                tint: hero.ink
                iconAngle: Updates.checking ? hero.panel._checkPhase : 0
                enabled: !Updates.checking
                Accessible.name: Translation.tr("Check again")
                onActivated: Updates.check()
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            text: hero.running ? (hero.panel.getElapsedText() || "0:00") : String(Updates.total)
            font.pixelSize: Tokens.fontDisplay * 2
            font.weight: Font.Bold
            font.features: ({ tnum: 1 })
            color: hero.ink
        }
        StyledText {
            Layout.fillWidth: true
            text: hero.running ? hero.panel.nowDoing()
                : Updates.total === 1 ? Translation.tr("update waiting") : Translation.tr("updates waiting")
            variant: "caption"
            color: hero.inkDim
            elide: Text.ElideRight
        }

        // ── Where they come from ──────────────────────────────────────────────
        // One bar cut by share (rounded pieces with a gap, as M3E's segmented things are), and under it a legend:
        // each source's shape blooms while it has updates and rests as a dot when it has none.
        Item {
            id: share
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingXs
            implicitHeight: Tokens.spacingMd + Tokens.spacingXs
            visible: !hero.running && Updates.total > 0
            readonly property real gap: Tokens.spacingXs
            readonly property var parts: hero.sources.filter(x => x.n > 0)
            readonly property real room: share.width - share.gap * Math.max(0, share.parts.length - 1)
            Row {
                anchors.fill: parent
                spacing: share.gap
                Repeater {
                    model: share.parts
                    delegate: Rectangle {
                        id: piece
                        required property var modelData
                        required property int index
                        // At least a pill's width, so one AUR update among a hundred still shows.
                        width: Math.max(share.height * 1.5, share.room * piece.modelData.n / Math.max(1, Updates.total))
                        height: share.height
                        radius: height / 2
                        color: piece.modelData.tone
                        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !hero.running
            spacing: Tokens.spacingSm
            Repeater {
                model: hero.sources
                delegate: RowLayout {
                    id: src
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: Tokens.spacingXs
                    MorphShape {
                        Layout.preferredWidth: Tokens.iconMd
                        Layout.preferredHeight: Tokens.iconMd
                        shape: src.modelData.n > 0 ? src.modelData.s : "circle"
                        spec: Motion.springSpatialFast
                        turns: false
                        fillColor: src.modelData.n > 0 ? src.modelData.tone : hero.palette.alpha(hero.ink, 0.18)
                        scale: src.modelData.n > 0 ? 1 : 0.6
                        Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: String(src.modelData.n)
                            font.pixelSize: Tokens.fontTitle
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            color: src.modelData.n > 0 ? hero.ink : hero.inkDim
                        }
                        StyledText {
                            text: src.modelData.t
                            variant: "micro"
                            color: hero.inkDim
                        }
                    }
                }
            }
        }

        // ── The biggest jumps ─────────────────────────────────────────────────
        // What is worth knowing before pressing Update: the largest version changes, major ones first.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingSm
            visible: !hero.running && hero.jumps.length > 0
            text: Translation.tr("Biggest jumps")
            variant: "label"
            font.weight: Font.DemiBold
            color: hero.ink
        }
        Repeater {
            model: hero.running ? [] : hero.jumps
            delegate: RowLayout {
                id: jump
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: jump.modelData.name
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: hero.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 to %2").arg(jump.modelData.from || "?").arg(jump.modelData.to || "?")
                        variant: "micro"
                        color: hero.inkDim
                        elide: Text.ElideMiddle
                    }
                }
                Rectangle {
                    implicitWidth: kindText.implicitWidth + Tokens.spacingMd
                    implicitHeight: kindText.implicitHeight + Tokens.spacingXs
                    radius: height / 2
                    color: jump.modelData.kind === "major" ? hero.palette.primary : hero.palette.alpha(hero.ink, 0.12)
                    StyledText {
                        id: kindText
                        anchors.centerIn: parent
                        text: jump.modelData.kind === "major" ? Translation.tr("Major")
                            : jump.modelData.kind === "minor" ? Translation.tr("Minor")
                            : jump.modelData.kind === "new" ? Translation.tr("New")
                            : Translation.tr("Patch")
                        variant: "micro"
                        font.weight: Font.DemiBold
                        color: jump.modelData.kind === "major" ? hero.palette.fgOnPrimary : hero.ink
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            StyledText {
                Layout.fillWidth: true
                visible: !hero.running
                text: Updates.lastCheckedText
                variant: "micro"
                color: hero.inkDim
                elide: Text.ElideRight
            }
            ChipButton {
                visible: hero.running && !hero.confirmCancel
                symbol: "terminal"
                on: hero.panel.expanded
                tonal: true
                tint: hero.ink
                Accessible.name: Translation.tr("The log")
                onActivated: hero.panel.expanded = !hero.panel.expanded
            }
            Item { Layout.fillWidth: true; visible: hero.running }
            ChipButton {
                visible: hero.running && hero.panel.isBusy && !hero.panel.isFinished && !hero.confirmCancel
                symbol: "stop"
                label: Translation.tr("Cancel")
                tonal: true
                tint: hero.ink
                onActivated: hero.confirmCancel = true
            }
            ChipButton {
                visible: hero.confirmCancel
                label: Translation.tr("Keep going")
                tonal: true
                tint: hero.ink
                onActivated: hero.confirmCancel = false
            }
            ChipButton {
                visible: hero.confirmCancel
                symbol: "stop"
                label: Translation.tr("Cancel run")
                solid: true
                tint: hero.palette.danger
                onActivated: { hero.confirmCancel = false; Updates.cancelRun() }
            }
            ChipButton {
                visible: !hero.running
                symbol: "settings"
                tonal: true
                tint: hero.ink
                Accessible.name: Translation.tr("Setup")
                onActivated: { UiState.updateOpen = false; UiState.openSettingsTo("SetupPage.qml") }
            }
        }
    }
}
