//@ pragma UseQApplication
import Quickshell
import "statusbar"
import "overlay"
import "overlay/modules"

ShellRoot {
    UpdatePanel { id: updatePanel }

    Variants {
        model: Quickshell.screens
        delegate: StatusBarRoot {
            required property var modelData
            screen:      modelData
            updatePanel: updatePanel
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: OverlayRoot {
            required property var modelData
            screen: modelData
        }
    }
}
