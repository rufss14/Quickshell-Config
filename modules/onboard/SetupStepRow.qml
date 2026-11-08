import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/setupplan.js" as Plan
import "../../state"

// ── SetupStepRow ──────────────────────────────────────────────────────────────
// One step of the setup plan as a card: a cookie plate with the step's icon, what it is, what it costs,
// and a pill that says where it stands — "Included" (filled, it will run), "Skipped", "Installed" (a
// verdict tick), "Unavailable" with the reason. A click anywhere on the card toggles it; a finished step
// toggles only when `allowRedo` (to run it again, "Redo").
//
// The tick is Setup's `selectedIds`, so a page, the Review page and the Settings checklist can never
// disagree about what will run.
//
// ── Two shapes ────────────────────────────────────────────────────────────────
// `tile: false` is a full-width row (plate · text · pill); `tile: true` is a card for a grid of them
// (plate and pill on top, text under). One GridLayout, rows and columns set per mode, so the two cannot
// drift apart.
//
// The card springs in (PopIn, `order` staggers a list) every time it is built or `shown` turns true, and
// leans toward the pointer with the plate winding — ScallopChip's gesture, at card scale.
// `flat` drops the card's own plate and border (a row inside another surface); it still lights up when ticked.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: sr

    property var step: ({})
    property string heading: ""
    property bool allowRedo: false
    property bool flat: false
    property bool tile: false
    // The page it sits on is showing — plays the entrance again each time it turns true.
    property bool shown: true
    property int order: 0

    readonly property bool done: sr.step.state === "done"
    readonly property bool blocked: sr.step.state === "blocked"
    readonly property bool on: Setup.isSelected(sr.step.id)
    readonly property bool canToggle: !sr.blocked && (!sr.done || sr.allowRedo)
    readonly property bool hot: hov.hovered && sr.canToggle
    // The drawer that says what the step will do (setupplan.js touchesFor).
    property bool detailsOpen: false
    readonly property var touches: sr.step.touches ?? []

    readonly property var iconFor: ({
        core: "inventory_2", aurhelper: "terminal", aur: "extension", blob: "widgets", hypr: "tune",
        autostart: "power_settings_new", themes: "palette", colours: "colorize", spotify: "music_note",
        wpe: "wallpaper", argos: "translate", songrec: "mic", awww: "apps"
    })

    spacing: 0

    StyledText {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: sr.heading !== "" && sr.step.group !== "essentials" ? Tokens.spacingSm : 0
        Layout.bottomMargin: Tokens.spacingXs
        visible: sr.heading !== ""
        text: sr.heading.toUpperCase()
        variant: "caption"; emphasis: "dim"; font.letterSpacing: 1
    }

    PopIn { id: pop; active: sr.shown; index: sr.order }

    Rectangle {
        id: card
        Layout.fillWidth: true
        Layout.fillHeight: sr.tile
        implicitHeight: inner.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusPill
        color: sr.on ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.11)
             : sr.flat ? "transparent"
             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, sr.hot ? 0.07 : 0.035)
        border.width: sr.flat && !sr.on ? 0 : Tokens.borderWidth
        border.color: sr.on ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, sr.hot ? 0.55 : 0.34)
                            : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, sr.hot ? 0.16 : 0.08)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        opacity: (sr.blocked ? 0.62 : 1) * pop.opacity
        scale: pop.scale * (sr.hot ? 1.012 : 1)
        Behavior on scale {
            NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
        }

        HoverHandler { id: hov }
        // The drawer is reading matter: a tap below the header ticks nothing.
        TapHandler {
            enabled: sr.canToggle
            onTapped: function (eventPoint) {
                if (eventPoint.position.y <= grid.y + grid.height + Tokens.spacingMd) Setup.toggleStep(sr.step.id)
            }
        }

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: 0

        GridLayout {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: sr.tile
            columns: sr.tile ? 2 : 3
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingSm

            SetupCookie {
                Layout.row: 0; Layout.column: 0
                Layout.alignment: Qt.AlignTop
                size: sr.tile ? 40 : 38
                name: sr.blocked ? "block" : sr.iconFor[sr.step.id] ?? "apps"
                lit: sr.on
                hot: sr.hot
                tint: sr.blocked ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).primary
                badge: sr.done && !sr.on ? "ok" : ""
            }

            ColumnLayout {
                Layout.row: sr.tile ? 1 : 0
                Layout.column: sr.tile ? 0 : 1
                Layout.columnSpan: sr.tile ? 2 : 1
                Layout.fillWidth: true
                Layout.fillHeight: sr.tile
                Layout.alignment: Qt.AlignTop
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: sr.step.title
                    variant: "body"; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: sr.blocked ? sr.step.why : sr.step.detail
                    variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                    maximumLineCount: sr.tile ? 3 : 4
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: sr.step.hint !== "" && !sr.done && !sr.blocked && !sr.tile
                    text: sr.step.hint
                    variant: "caption"; color: Colors.of(QsWindow.window).fgMuted; wrapMode: Text.WordWrap
                }
                // What it costs.
                Row {
                    visible: !sr.done && !sr.blocked
                    spacing: Tokens.spacingMd
                    topPadding: 2
                    Row {
                        spacing: 4
                        MaterialIcon { name: "schedule"; color: Colors.of(QsWindow.window).fgDim; font.pixelSize: Tokens.iconSm - 2; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: Plan.etaText(sr.step.eta).replace("about ", "~"); variant: "caption"; emphasis: "dim"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        visible: sr.step.root
                        spacing: 4
                        MaterialIcon { name: "lock"; color: Colors.of(QsWindow.window).fgDim; font.pixelSize: Tokens.iconSm - 2; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: "password"; variant: "caption"; emphasis: "dim"; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                // "What will this do?" — a MouseArea, so the press stops here and doesn't tick the card.
                Item {
                    visible: sr.touches.length > 0
                    implicitWidth: dRow.implicitWidth
                    implicitHeight: 22
                    Row {
                        id: dRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sr.detailsOpen ? "Hide details" : "What will this do?"
                            variant: "caption"
                            color: dHover.containsMouse ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgMuted
                        }
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "expand_more"
                            color: dHover.containsMouse ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgMuted
                            font.pixelSize: Tokens.iconSm
                            rotation: sr.detailsOpen ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                        }
                    }
                    MouseArea {
                        id: dHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sr.detailsOpen = !sr.detailsOpen
                    }
                }
                Item { Layout.fillHeight: sr.tile }
            }

            // Where it stands.
            Rectangle {
                id: pill
                Layout.row: 0
                Layout.column: sr.tile ? 1 : 2
                // In a tile the plate and the pill are the only things on the top row, so the pill's column
                // is the one that must take the slack — otherwise the text below, which spans both columns,
                // is only as wide as the plate and the pill together and wraps at a third of the card.
                Layout.fillWidth: sr.tile
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                implicitHeight: 26
                implicitWidth: pillRow.implicitWidth + Tokens.spacingMd * 2
                radius: Tokens.corner(Config.barShape, height / 2)
                readonly property bool filled: sr.on
                readonly property color ink: sr.blocked ? Colors.of(QsWindow.window).fgDim
                                           : sr.done && !sr.on ? Verdict.tint(true)
                                           : Colors.of(QsWindow.window).primary
                color: pill.filled ? Colors.of(QsWindow.window).primary : "transparent"
                border.width: pill.filled ? 0 : Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(pill.ink, 0.45)
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: sr.blocked ? "block" : sr.on ? "check" : sr.done ? "check_circle" : "remove"
                        fill: sr.on || sr.done ? 1 : 0
                        color: pill.filled ? Colors.of(QsWindow.window).fgOnPrimary : pill.ink
                        font.pixelSize: Tokens.iconSm - 1
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sr.blocked ? "Unavailable"
                            : sr.on ? (sr.done ? "Redo" : "Included")
                            : sr.done ? "Installed" : "Skipped"
                        variant: "caption"; font.weight: Font.Medium
                        color: pill.filled ? Colors.of(QsWindow.window).fgOnPrimary : pill.ink
                    }
                }
            }
        }

        // ── The drawer: every command, file and root request, in plain words ─────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: sr.detailsOpen ? drawer.implicitHeight + Tokens.spacingSm : 0
            clip: true
            visible: Layout.preferredHeight > 0.5
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }
            Column {
                id: drawer
                y: Tokens.spacingSm
                width: parent.width
                spacing: Tokens.spacingXs
                opacity: sr.detailsOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Repeater {
                    model: sr.touches
                    delegate: Row {
                        id: tr
                        required property var modelData
                        width: drawer.width
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            id: tIcon
                            name: tr.modelData.k === "cmd" ? "terminal" : tr.modelData.k === "file" ? "folder_open"
                                : tr.modelData.k === "net" ? "download" : tr.modelData.k === "root" ? "lock" : "info"
                            color: tr.modelData.k === "root" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                            font.pixelSize: Tokens.iconSm
                        }
                        StyledText {
                            width: tr.width - tIcon.width - tr.spacing
                            text: tr.modelData.t
                            variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                            font.family: tr.modelData.k === "cmd" ? Tokens.fontMono : Tokens.fontFamily
                        }
                    }
                }
            }
        }
        }
    }
}
