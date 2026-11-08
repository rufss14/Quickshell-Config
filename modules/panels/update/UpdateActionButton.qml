import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// A full-width action: the filled pill is THE thing to do, the outlined one is the other option.
// (Was UpdatePanel's inline `ActionButton`; `host` is the UpdatePanel.)
ChipButton {
    required property var host
    property string icon
    property string text
    property var clickHandler: null
    property bool  disabled: false
    property bool  primary: true

    Layout.fillWidth: true
    implicitHeight: host._fieldH
    on: primary
    tint: Colors.of(QsWindow.window).focus
    symbol: icon
    label: text
    enabled: !disabled
    onActivated: if (clickHandler) clickHandler()
}
