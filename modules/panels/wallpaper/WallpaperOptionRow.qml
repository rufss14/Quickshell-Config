import QtQuick
import "../../../components"

// A labelled switch: SettingRow with its Toggle, for the renderer's launch options and the Material
// tab. (Was an inline `OptionRow` with a copy of SettingRow's layout.)
SettingRow {
    id: opt

    property bool checked: false
    signal toggled()

    Toggle {
        checked: opt.checked
        onToggled: opt.toggled()
    }
}
