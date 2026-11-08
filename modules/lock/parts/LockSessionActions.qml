pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../overview"
import "../../discord"

// ── LockSessionActions ── part of LockScreen.qml; `lockSurface` is its lock surface (one per screen). ──
ColumnLayout {
    id: lockSessionActions
    required property var lockSurface
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Tokens.spacingXxl
    spacing: Tokens.spacingSm

    visible: Config.lockShowPower

    opacity: lockSurface.revealLate
    transform: Translate { y: (1 - lockSurface.revealLate) * -20 }

    ChipTray {
        Layout.alignment: Qt.AlignRight

        Repeater {
            model: lockSurface.powerActions

            ChipButton {
                required property var modelData

                symbol: modelData.symbol
                on:     lockSurface.armed === modelData.key
                tint:   modelData.tint
                // Arming only. Clicking an armed chip again disarms it — the Confirm
                // button under the tray is the only thing that can fire it, so no
                // amount of clicking in one spot ends the session.
                onActivated: lockSurface.armed = (lockSurface.armed === modelData.key ? "" : modelData.key)
            }
        }
    }

    Surface {
        Layout.alignment: Qt.AlignRight
        visible: lockSurface.armedAction !== null
        implicitWidth:  confirmRow.implicitWidth + Tokens.spacingLg * 2
        implicitHeight: 62
        elevation:    Tokens.elevationCard
        squareMode:   Config.barShape
        cornerRadius: Tokens.radiusCard
        fillOpacity:  Config.surfaceOpacity
        border.color: lockSurface.armedAction ? lockSurface.armedAction.tint
                                          : Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)

        RowLayout {
            id: confirmRow
            anchors.centerIn: parent
            spacing: Tokens.spacingMd

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: lockSurface.armedAction ? lockSurface.armedAction.label : ""
                    variant: "body"
                    font.bold: true
                    color: lockSurface.armedAction ? lockSurface.armedAction.tint : Colors.of(QsWindow.window).fg
                }
                StyledText {
                    text: lockSurface.armedAction ? lockSurface.armedAction.detail : ""
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            PanelButton {
                capsule: true
                variant: "primary"
                accent:  lockSurface.armedAction ? lockSurface.armedAction.tint : Colors.of(QsWindow.window).primary
                label:   "Confirm"
                onActivated: {
                    const a = lockSurface.armedAction
                    lockSurface.armed = ""
                    if (a) lockSurface.fire(a)
                }
            }

            PanelButton {
                capsule: true
                variant: "ghost"
                implicitWidth:  26
                implicitHeight: 26
                symbol: "close"
                onActivated: lockSurface.armed = ""
            }
        }
    }
}
