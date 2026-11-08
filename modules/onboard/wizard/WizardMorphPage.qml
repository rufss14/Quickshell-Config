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

// ── WizardMorphPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardMorphPage
    required property var wizard
    property alias p2: p2
    host: wizard
    idx: 2
    ViewEnter { target: p2; active: wizard.on(2); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p2
        anchors.fill: parent
        spacing: Tokens.spacingMd

        readonly property var ids: ["blob"]
        readonly property var t: wizard.topic(p2.ids)

        WizardPageHead {
            icon: "widgets"
            lead: "Morphing"; tail: "system"
            badge: "optional"
            status: p2.t.done ? "Installed — restart the shell to see it" : "The bar and its panels, fused into one shape"
            done: p2.t.done
            shown: wizard.on(2)
        }

        // The top of the frame is the point — the bar and the panel header fusing — so the
        // crop is anchored there, not centred. It drifts slowly (Ken Burns) while it is showing.
        Rectangle {
            id: frame
            Layout.fillWidth: true
            Layout.preferredHeight: 188
            radius: Tokens.radiusPill
            color: "transparent"
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.30)
            PopIn { id: framePop; active: wizard.on(2); index: 1 }
            opacity: framePop.opacity
            scale: framePop.scale

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: Tokens.borderWidth
                radius: parent.radius - Tokens.borderWidth
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

                Image {
                    id: preview
                    anchors.fill: parent
                    source: Icons.preview("MorphPreview.png")
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignTop
                    sourceSize: Qt.size(760, 500)
                    smooth: true
                    asynchronous: true
                    transformOrigin: Item.Top
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: Config.motionEnabled && wizard.on(2)
                        NumberAnimation { from: 1.0; to: 1.05; duration: 9000; easing.type: Motion.ambient }
                        NumberAnimation { from: 1.05; to: 1.0; duration: 9000; easing.type: Motion.ambient }
                    }
                }
                // A veil at the bottom, so the chip on it reads over any screenshot.
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 54
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.78) }
                    }
                }
                WizardChip {
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    anchors.margins: Tokens.spacingMd
                    text: p2.t.done ? "Built and loaded" : "Built once, on this machine"
                    level: p2.t.done ? "ok" : "unknown"
                    shown: wizard.on(2)
                    pops: 3
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: Translation.tr("The bar and its open panels fuse into one shape as they open. A C++ plugin installed system-wide; skipped, panels simply open.")
            variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
        }

        WizardStepGroup { ids: p2.ids; shown: wizard.on(2); base: 4 }

        Item { Layout.fillHeight: true }
    }
}
