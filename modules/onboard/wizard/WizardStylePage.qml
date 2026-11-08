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

// ── WizardStylePage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardStylePage
    required property var wizard
    property alias p6: p6
    host: wizard
    idx: 6
    ViewEnter { target: p6; active: wizard.on(6); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p6
        anchors.fill: parent
        spacing: Tokens.spacingSm

        WizardPageHead {
            icon: "auto_awesome"
            lead: "Make it"; tail: "yours"
            badge: "optional"
            status: "Changes apply as you click — look behind this card"
            shown: wizard.on(6)
        }

        WizardPref {
            title: Translation.tr("Light or dark")
            note: "The same wallpaper, the whole shell flips."
            shown: wizard.on(6); pops: 1
            TabStrip {
                anchors.fill: parent
                accent: Colors.of(QsWindow.window).primary
                enabled: Config.wallTheming && !Wallpaper.applying
                model: [
                    { value: "light", label: "Light", icon: "light_mode" },
                    { value: "dark",  label: "Dark",  icon: "dark_mode" }
                ]
                current: Config.themeMode
                onPicked: function (v) { if (Config.themeMode !== v) ColorScheme.switchMode(v) }
            }
        }
        WizardPref {
            title: Translation.tr("Icon shape")
            note: "The holder behind icons — these cookies included."
            shown: wizard.on(6); pops: 2
            controlWidth: 330
            SegmentSwitch {
                anchors.fill: parent
                model: [
                    { value: "default", label: "Default" }, { value: "squircle", label: "Squircle" },
                    { value: "cookie", label: "Cookie" }, { value: "clover", label: "Clover" },
                    { value: "circle", label: "Circle" }
                ]
                current: Config.iconShape
                onPicked: function (v) { Config.iconShape = v }
            }
        }
        WizardPref {
            title: Translation.tr("Corners")
            note: "Rounded, or square everywhere — the bar then runs edge to edge."
            shown: wizard.on(6); pops: 3
            SegmentSwitch {
                anchors.fill: parent
                model: [{ value: false, label: "Rounded" }, { value: true, label: "Square" }]
                current: Config.barShape
                onPicked: function (v) { Config.barShape = v }
            }
        }
        WizardPref {
            title: Translation.tr("Spacing")
            note: "How much room there is between things."
            shown: wizard.on(6); pops: 4
            SegmentSwitch {
                anchors.fill: parent
                model: [{ value: 0.9, label: "Compact" }, { value: 1.0, label: "Comfortable" }, { value: 1.1, label: "Roomy" }]
                current: Config.densityScale
                onPicked: function (v) { Config.densityScale = v }
            }
        }
        WizardPref {
            title: Translation.tr("Floating cookies")
            note: "The scalloped shapes that drift behind open panels."
            shown: wizard.on(6); pops: 5
            controlWidth: 52
            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                accent: Colors.of(QsWindow.window).primary
                checked: Config.panelCookies
                onToggled: Config.panelCookies = !Config.panelCookies
            }
        }
        WizardPref {
            title: Translation.tr("Animations")
            note: "Off, everything arrives at once — easier on a slow machine."
            shown: wizard.on(6); pops: 6
            controlWidth: 52
            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                accent: Colors.of(QsWindow.window).primary
                checked: Config.motionEnabled
                onToggled: Config.motionEnabled = !Config.motionEnabled
            }
        }

        Item { Layout.fillHeight: true }
    }
}
