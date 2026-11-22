pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ClaudeIslandHero ── part of ClaudePanel.qml (island form); `panel` is the ClaudePanel. ───────────────────────
// The Claude page's loud card on an island, upright in the left column, in place of the panel's header, hero and
// usage card (2026-11-15; the user asked for the header to go):
//
//   top     what the sessions are doing as a shape: Claude's mark on a disc at rest, a cookie that turns while one
//           works (the burst playing on it), a burst in the warning tone while one needs you; the line under it
//   middle  the two usage limits, each a large percentage over a blocky bar and when it resets; before the
//           connection is made, what it adds and Connect instead
//   foot    New in <this shell's project>, and the way to disconnect, which asks on the row (Keep / Disconnect)
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: hero.palette.fgOnPrimaryContainer
    readonly property color inkDim: hero.palette.alpha(hero.palette.fgOnPrimaryContainer, 0.72)
    readonly property bool needs: ClaudeSessions.needsYou.length > 0
    readonly property bool busy: ClaudeSessions.busyCount > 0
    readonly property bool any: ClaudeSessions.sessions.length > 0
    readonly property color tone: hero.needs ? hero.palette.warning : hero.palette.primary
    readonly property bool showUsage: ClaudeSessions.hooksInstalled || ClaudeSessions.rate.at > 0
    property bool confirmOff: false

    radius: Tokens.radiusXl
    color: hero.needs ? hero.palette.mix(hero.palette.primaryContainer, hero.palette.warning, 0.22)
                      : hero.palette.primaryContainer
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm

        // ── What they are doing ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingLg
                implicitHeight: implicitWidth
                Item {
                    anchors.fill: parent
                    RotationAnimator on rotation {
                        running: hero.busy && !hero.needs && Motion.ambientOn
                        from: 0; to: 360
                        duration: Motion.glide * 40
                        loops: Animation.Infinite
                    }
                    MorphShape {
                        anchors.fill: parent
                        shape: hero.needs ? "burst" : hero.busy ? "cookie9" : hero.any ? "squircle" : "circle"
                        spec: Motion.springSpatialFast
                        fillColor: hero.any ? hero.tone : hero.palette.alpha(hero.ink, 0.14)
                        Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                    }
                }
                ClaudeBurst {
                    anchors.centerIn: parent
                    width: Tokens.iconLg
                    height: Tokens.iconLg
                    visible: hero.busy && !hero.needs
                    playing: visible
                    tint: hero.palette.fgOnPrimary
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: hero.needs
                    name: "notifications_active"
                    fill: 1
                    color: hero.palette.fgOnPrimary
                }
                ClaudeGlyph {
                    anchors.centerIn: parent
                    width: Tokens.iconLg
                    height: Tokens.iconLg
                    visible: !hero.busy && !hero.needs
                    tint: hero.any ? hero.palette.fgOnPrimary : hero.ink
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: hero.needs ? Translation.tr("Claude needs you")
                        : hero.busy ? Translation.tr("Claude is working")
                        : hero.any  ? Translation.tr("Waiting for you")
                        :             Translation.tr("Nothing running")
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: hero.panel.summary
                    variant: "caption"
                    color: hero.inkDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        // ── How many, of each ─────────────────────────────────────────────────
        // A shape blooms beside a count while there is one of that kind, and rests as a dot when there is none.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingMd
            spacing: Tokens.spacingSm
            Repeater {
                model: [
                    { t: Translation.tr("Working"),   n: ClaudeSessions.busyCount,        s: "cookie9" },
                    { t: Translation.tr("Needs you"), n: ClaudeSessions.needsYou.length,  s: "clover" },
                    { t: Translation.tr("To resume"), n: ClaudeSessions.recent.length,    s: "sunny" }
                ]
                delegate: RowLayout {
                    id: kind
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: Tokens.spacingXs
                    MorphShape {
                        Layout.preferredWidth: Tokens.iconMd
                        Layout.preferredHeight: Tokens.iconMd
                        shape: kind.modelData.n > 0 ? kind.modelData.s : "circle"
                        spec: Motion.springSpatialFast
                        turns: false
                        fillColor: kind.modelData.n > 0 ? hero.palette.primary : hero.palette.alpha(hero.ink, 0.18)
                        scale: kind.modelData.n > 0 ? 1 : 0.6
                        Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: String(kind.modelData.n)
                            font.pixelSize: Tokens.fontTitle
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            color: kind.modelData.n > 0 ? hero.ink : hero.inkDim
                        }
                        StyledText {
                            text: kind.modelData.t
                            variant: "micro"
                            color: hero.inkDim
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── Usage ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: hero.showUsage
            StyledText {
                text: Translation.tr("Usage limits")
                variant: "label"
                font.weight: Font.DemiBold
                color: hero.ink
            }
            Item { Layout.fillWidth: true }
            StyledText {
                visible: hero.panel.rateAge !== ""
                text: Translation.tr("as of %1").arg(hero.panel.rateAge)
                variant: "micro"
                color: hero.inkDim
            }
        }
        Repeater {
            model: hero.showUsage ? [
                { t: Translation.tr("5-hour"), info: hero.panel.five },
                { t: Translation.tr("Weekly"), info: hero.panel.week }
            ] : []
            delegate: ColumnLayout {
                id: lim
                required property var modelData
                readonly property var info: lim.modelData.info
                readonly property real ratio: lim.info ? lim.info.ratio : 0
                readonly property color fillTone: lim.ratio > 0.9 ? hero.palette.danger
                    : lim.ratio > 0.75 ? hero.palette.warning : hero.palette.primary
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText {
                        text: !lim.info ? "—" : lim.info.reset ? Translation.tr("Fresh") : Translation.tr("%1%").arg(lim.info.pct)
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: hero.ink
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 3
                        spacing: 0
                        StyledText {
                            text: lim.modelData.t
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: !lim.info ? Translation.tr("Not reported yet")
                                : lim.info.reset ? Translation.tr("A new window")
                                : Translation.tr("Resets in %1 · %2").arg(lim.info.left).arg(lim.info.when)
                            variant: "micro"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }
                // The blocky bar of the media page's slider, short.
                Item {
                    id: track
                    Layout.fillWidth: true
                    implicitHeight: Tokens.spacingMd
                    readonly property real r: Math.max(1, Math.round(track.height * 0.3))
                    Rectangle {
                        anchors.fill: parent
                        radius: track.r
                        color: hero.palette.alpha(hero.ink, 0.14)
                    }
                    Rectangle {
                        visible: lim.ratio > 0
                        width: Math.max(track.height, track.width * lim.ratio)
                        height: track.height
                        radius: track.r
                        color: lim.fillTone
                        Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                    }
                }
            }
        }

        // ── Before the connection ─────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !hero.showUsage && ClaudeSessions.ready
            spacing: Tokens.spacingXs
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Know when Claude needs you, and your usage")
                variant: "label"
                font.weight: Font.DemiBold
                color: hero.ink
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("A small hook and a status line in Claude Code's settings, with a backup kept. They record the tool a session is on, its permission prompts and your limits, never your prompts or commands.")
                variant: "micro"
                color: hero.inkDim
                wrapMode: Text.Wrap
            }
            ChipButton {
                Layout.topMargin: Tokens.spacingXs
                solid: true
                symbol: "link"
                label: ClaudeSessions.hooksBusy ? Translation.tr("Connecting…") : Translation.tr("Connect")
                enabled: !ClaudeSessions.hooksBusy
                onActivated: ClaudeSessions.installHooks()
            }
        }

        Item { Layout.fillHeight: true }

        // ── Foot ──────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            ChipButton {
                Layout.fillWidth: true
                visible: !hero.confirmOff
                solid: true
                symbol: "add"
                label: Translation.tr("New in %1").arg(hero.panel.homeProject)
                onActivated: ClaudeSessions.newSession()
            }
            ChipButton {
                visible: ClaudeSessions.hooksInstalled && !hero.confirmOff
                tonal: true
                tint: hero.ink
                symbol: "link_off"
                Accessible.name: Translation.tr("Disconnect from Claude Code")
                onActivated: hero.confirmOff = true
            }
            ChipButton {
                Layout.fillWidth: true
                visible: hero.confirmOff
                tonal: true
                tint: hero.ink
                label: Translation.tr("Keep")
                onActivated: hero.confirmOff = false
            }
            ChipButton {
                Layout.fillWidth: true
                visible: hero.confirmOff
                solid: true
                tint: hero.palette.danger
                symbol: "link_off"
                label: Translation.tr("Disconnect")
                onActivated: { hero.confirmOff = false; ClaudeSessions.removeHooks() }
            }
        }
    }
}
