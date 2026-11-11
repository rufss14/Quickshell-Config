import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"
import "../wizard"

// ── WizardColoursPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardColoursPage
    required property var wizard
    property alias p5: p5
    host: wizard
    idx: 5
    ViewEnter { target: p5; active: wizard.on(5); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p5
        anchors.fill: parent
        spacing: Tokens.spacingMd

        readonly property var ids: ["themes", "colours", "discordtheme", "spotifytheme"]
        readonly property var t: wizard.topic(p5.ids)

        WizardPageHead {
            icon: "palette"
            lead: "Your"; tail: "colours"
            badge: "optional"
            status: p5.t.done ? "Apps are themed" : "Pywal, GTK, Qt and Hyprland stay in sync automatically"
            done: p5.t.done
            shown: wizard.on(5)
        }

        // The palette the shell is wearing right now — read from it, not drawn.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: palCol.implicitHeight + Tokens.spacingLg * 2
            radius: Tokens.radiusPill
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.035)
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

            ColumnLayout {
                id: palCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Translation.tr("Every colour change in this shell — a new wallpaper, a saved scheme — repaints your terminal, Hyprland and every app set up here, on its own.")
                    variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacingMd
                    Repeater {
                        model: [
                            Colors.of(QsWindow.window).primary, Colors.of(QsWindow.window).focus,
                            Colors.of(QsWindow.window).info, Colors.of(QsWindow.window).success,
                            Colors.of(QsWindow.window).warning, Colors.of(QsWindow.window).danger,
                            Colors.of(QsWindow.window).surfaceHigh
                        ]
                        delegate: Item {
                            id: sw
                            required property color modelData
                            required property int index
                            width: 40; height: 40
                            PopIn { id: swPop; active: wizard.on(5); index: sw.index + 1 }
                            opacity: swPop.opacity
                            scale: swPop.scale * (swHover.hovered ? 1.14 : 1)
                            Behavior on scale {
                                NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                            }
                            rotation: swHover.hovered ? -12 : 0
                            Behavior on rotation {
                                NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                            }
                            HoverHandler { id: swHover }
                            ShapeBox {
                                anchors.fill: parent
                                fallback: "cookie"
                                fillColor: sw.modelData
                                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                            }
                        }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Wallpaper.currentPath !== "" ? "Extracted from your wallpaper" : "No wallpaper yet — this is the built-in monochrome"
                    variant: "caption"; emphasis: "dim"
                }
            }
        }

        WizardStepGroup { ids: p5.ids; shown: wizard.on(5); base: 3 }

        // Per app: what is there to theme, read-only (GTK, Qt and Steam are the "Theme your apps" step above; Discord and Spotify are steps of their own).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: appFlow.implicitHeight
            Flow {
                id: appFlow
                width: parent.width
                spacing: Tokens.spacingSm
                Repeater {
                    model: [
                        { id: "gtk",     title: "GTK apps" },
                        { id: "qt",      title: "Qt apps" },
                        { id: "discord", title: "Discord" },
                        { id: "spotify", title: "Spotify" },
                        { id: "steam",   title: "Steam" }
                    ]
                    delegate: WizardChip {
                        id: appChip
                        required property var modelData
                        required property int index
                        readonly property var st: Setup.theme(modelData.id)
                        text: modelData.title
                        level: st.state === "ready" ? "ok" : st.state === "absent" ? "unknown" : "warn"
                        shown: wizard.on(5)
                        pops: index + 6
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Open the full colour editor")
            variant: "caption"
            color: colorLinkHover.hovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
            HoverHandler { id: colorLinkHover }
            TapHandler {
                onTapped: {
                    wizard.closeRequested()
                    UiState.togglePanel("colorScheme")
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
