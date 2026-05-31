import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../theming" as T
import "." as OM

PanelWindow {
    id: panel

    Component.onCompleted: {
        OM.Panels.updatePanel = panel
        console.log("[UpdatePanel] registered")
    }

    signal updateFinished()

    function startUpdate(count) {
        _resetState()
        state.pkgCount = count ?? 0
        panel.visible = true
        Qt.callLater(() => passField.forceActiveFocus())
    }

    // ── State ─────────────────────────────────────────────────────────────────
    QtObject {
        id: state
        property string view:          "main"

        property bool   running:       false
        property bool   done:          false
        property bool   hadError:      false
        property int    pkgCount:      0
        property real   progress:      0.0
        property string phase:         ""
        property string currentPkg:    ""
        property int    elapsedSecs:   0
        property int    pkgsDone:      0

        property bool   doVencord:      false
        property bool   vencordRunning: false
        property bool   vencordDone:    false
        property bool   vencordError:   false
    }

    ListModel { id: logModel }

    Timer {
        id: elapsedTimer
        interval: 1000; repeat: true
        running: (state.running && !state.done) || (state.vencordRunning && !state.vencordDone)
        onTriggered: state.elapsedSecs++
    }

    // ── Layer shell ───────────────────────────────────────────────────────────
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-update-panel"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    // Sized exactly to the pill so no transparent area eats pointer events.
    // Centred by anchoring top+left+right then using margins.left to offset.
    anchors.top:    true
    anchors.left:   true
    margins.top:    T.Theme.barHeight + T.Theme.barMargin
    // implicitWidth drives the window size; pill fills it.
    implicitWidth:  state.view === "running" ? 440 : 340
    implicitHeight: state.view === "main"    ? 176 : 260

    Behavior on implicitWidth  { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

    // Keep pill centred on screen by computing left margin dynamically.
    // screen.width is available on PanelWindow via the screen property.
    margins.left: screen ? Math.round((screen.width - implicitWidth) / 2) : 0

    visible: false
    color:   "transparent"

    // Focus item — the pattern that actually works for ESC in Quickshell
    Item {
        id: updateFocusItem
        Keys.onEscapePressed: if (!state.running && !state.vencordRunning) _close()
        Connections {
            target: panel
            function onVisibleChanged() {
                if (panel.visible) updateFocusItem.forceActiveFocus()
            }
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 2400; repeat: false
        onTriggered: _close()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _appendLog(line, isError) {
        if (logModel.count > 200) logModel.remove(0)
        logModel.append({ line: line, isError: isError })
    }

    function _resetState() {
        state.view          = "main"
        state.running       = false
        state.done          = false
        state.hadError      = false
        state.pkgCount      = 0
        state.pkgsDone      = 0
        state.progress      = 0.0
        state.phase         = ""
        state.currentPkg    = ""
        state.elapsedSecs   = 0
        state.doVencord     = false
        state.vencordRunning = false
        state.vencordDone   = false
        state.vencordError  = false
        passField.text      = ""
        logModel.clear()
    }

    function _close() {
        panel.visible = false
        passField.text = ""
    }

    function _shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function getStatusText() {
        if (state.hadError || state.vencordError) return "Update failed"
        if (state.vencordRunning && !state.vencordDone) return "Vencord  •  installing…"
        if (state.vencordDone) return "Vencord updated ✓"
        if (state.running && !state.done) {
            if (state.pkgsDone > 0 && state.pkgCount > 0)
                return state.phase + "  •  " + state.pkgsDone + " / " + state.pkgCount
            if (state.pkgCount > 0)
                return state.phase + "  •  " + state.pkgCount + " pkgs"
            return state.phase
        }
        if (state.done) return "System up to date ✓"
        return state.phase
    }

    function getElapsedText() {
        const m = Math.floor(state.elapsedSecs / 60)
        const s = state.elapsedSecs % 60
        return (m > 0 ? m + "m " : "") + s + "s"
    }

    function getStatusDotColor() {
        if (state.hadError || state.vencordError) return T.Theme.color1
        if (state.done && (!state.doVencord || state.vencordDone)) return T.Theme.color2
        return T.Theme.color4
    }

    function isFinished() {
        return state.done && (!state.doVencord || state.vencordDone)
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: pill

        anchors.fill: parent

        radius:       T.Theme.pillRadius + 4
        color:        T.Theme.bg
        border.color: T.Theme.barBorder
        border.width: 1
        clip:         true

        // VIEW: MAIN PROMPT
        ColumnLayout {
            visible: state.view === "main"
            enabled: state.view === "main"
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 10; leftMargin: 12; rightMargin: 12 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text { text: "󰚰"; color: T.Theme.color4; opacity: 0.80; font { family: T.Theme.fontFamily; pixelSize: 14 } }
                Text { text: "System Update"; color: T.Theme.fg; opacity: 0.90; Layout.fillWidth: true; font { family: T.Theme.fontFamily; pixelSize: 12; bold: true } }
                CloseButton { clickHandler: function() { _close() } }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: T.Theme.barBorder }

            PasswordInput {
                id: passField
                iconColor: T.Theme.color4
                onAccepted: _confirmSysUpdate()
            }

            ActionButton {
                icon: "󰣇"
                text: "Update System  (pacman + flatpak)"
                accent: T.Theme.color4
                disabled: passField.text.length === 0
                clickHandler: function() { _confirmSysUpdate() }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Rectangle { Layout.fillWidth: true; height: 1; color: T.Theme.barBorder }
                Text { text: "or"; color: T.Theme.fg; opacity: 0.25; font { family: T.Theme.fontFamily; pixelSize: 9 } }
                Rectangle { Layout.fillWidth: true; height: 1; color: T.Theme.barBorder }
            }

            ActionButton {
                icon: "󰙯"
                text: "Update Vencord  (patch Discord)"
                accent: T.Theme.color9
                disabled: passField.text.length === 0
                clickHandler: function() { _confirmVencord() }
            }

            Item { height: 2 }
        }

        // VIEW: RUNNING / DONE
        ColumnLayout {
            visible: state.view === "running"
            enabled: state.view === "running"
            anchors { top: parent.top; left: parent.left; right: parent.right }
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 10; Layout.topMargin: 0
                implicitHeight: 38; spacing: 8

                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: getStatusDotColor()
                    Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                    SequentialAnimation on opacity {
                        running: (state.running && !state.done) || (state.vencordRunning && !state.vencordDone)
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.20; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: getStatusText()
                    color: (state.hadError || state.vencordError) ? T.Theme.color1
                         : (state.done || state.vencordDone) ? T.Theme.color2
                         : T.Theme.fg
                    opacity: 0.95
                    font { family: T.Theme.fontFamily; pixelSize: 15; bold: true }
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                }

                Rectangle {
                    visible: !isFinished()
                    implicitWidth: elapsedLabel.implicitWidth + 10; height: 18; radius: 5
                    color: T.Theme.pw(T.Theme.pal?.colors?.color9 || "#7dcfff", 0.08)
                    border.color: T.Theme.barBorder
                    border.width: 1
                    Text {
                        id: elapsedLabel
                        anchors.centerIn: parent
                        text: getElapsedText()
                        color: T.Theme.fg; opacity: 0.45
                        font { family: T.Theme.fontFamily; pixelSize: 11 }
                    }
                }

                CloseButton {
                    visible: isFinished() || state.hadError || state.vencordError
                    clickHandler: function() { _close() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 10
                implicitHeight: 22; spacing: 6

                Repeater {
                    model: [
                        { label: "Pacman", col: "color4", active: state.running || state.done },
                        { label: "Flatpak", col: "color4", active: state.phase === "Flatpak" || (state.done && !state.doVencord) },
                        { label: "Vencord", col: "color9", active: state.doVencord }
                    ]
                    delegate: Rectangle {
                        id: badge
                        required property var modelData
                        visible: modelData.active
                        implicitWidth: badgeText.implicitWidth + 12; height: 16; radius: 4
                        property color accentColor: modelData.col === "color4" ? (T.Theme.pal?.colors?.color4 || "#7aa2f7") : (T.Theme.pal?.colors?.color9 || "#7dcfff")
                        color: T.Theme.pw(accentColor, modelData.active ? 0.15 : 0.06)
                        border.color: T.Theme.pw(accentColor, modelData.active ? 0.40 : 0.15)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                        Behavior on border.color { ColorAnimation { duration: T.Theme.animNormal } }
                        Text {
                            id: badgeText; anchors.centerIn: parent
                            text: modelData.label; color: badge.accentColor
                            opacity: modelData.active ? 1.0 : 0.38
                            font { family: T.Theme.fontFamily; pixelSize: 11; bold: true }
                            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal } }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
                Text {
                    visible: !state.done && !state.doVencord
                    text: Math.round(state.progress * 100) + "%"
                    color: T.Theme.color4; opacity: 0.70
                    font { family: T.Theme.fontFamily; pixelSize: 11; bold: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 3
                height: 1; color: T.Theme.barBorder
            }

            Item {
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 5
                implicitHeight: state.currentPkg !== "" && !state.doVencord ? 18 : 0
                visible: implicitHeight > 0; clip: true
                Behavior on implicitHeight { NumberAnimation { duration: T.Theme.animFast } }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Math.min(pkgChip.implicitWidth + 16, parent.width)
                    height: 16; radius: 4
                    color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.10)
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.25); border.width: 1
                    Text {
                        id: pkgChip
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
                        text: "↓  " + state.currentPkg
                        color: T.Theme.color4; opacity: 0.90
                        font { family: T.Theme.fontFamily; pixelSize: 11; bold: true }
                        elide: Text.ElideMiddle
                    }
                }
            }

            Text {
                Layout.leftMargin: 13; Layout.topMargin: 5
                text: "OUTPUT"; color: T.Theme.fg; opacity: 0.22
                font { family: T.Theme.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.2 }
            }

            ListView {
                id: logView
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 6; Layout.bottomMargin: 3
                implicitHeight: 120; clip: true
                model: logModel; spacing: 1
                verticalLayoutDirection: ListView.BottomToTop
                delegate: RowLayout {
                    width: logView.width - 6; spacing: 4
                    Rectangle { visible: model.isError; width: 2; height: 9; radius: 1; color: T.Theme.color1; opacity: 0.80; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        Layout.fillWidth: true; text: model.line
                        color: model.isError ? T.Theme.color1 : T.Theme.fg
                        opacity: model.isError ? 0.88 : 0.72
                        font { family: T.Theme.fontFamily; pixelSize: 11 }
                        wrapMode: Text.NoWrap; elide: Text.ElideRight
                    }
                }
                onCountChanged: Qt.callLater(() => logView.positionViewAtBeginning())
            }

            Rectangle {
                Layout.fillWidth: true; implicitHeight: 3
                color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.10)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * state.progress; radius: 2
                    color: (state.hadError || state.vencordError) ? T.Theme.color1 : T.Theme.color4
                    opacity: isFinished() ? 0.0 : 1.0
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                    Behavior on opacity { NumberAnimation { duration: 1000 } }
                }
            }
        }
    } // end pill

    // ── Reusable Components ───────────────────────────────────────────────────
    component CloseButton: Rectangle {
        property var clickHandler: null
        width: 20; height: 20; radius: 10

        color: closeMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1 || "#f7768e", 0.15) : "transparent"
        border.color: closeMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color1 || "#f7768e", 0.30) : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: "✕"
            color: T.Theme.fg
            opacity: closeMa.containsMouse ? 0.90 : 0.35
            font { family: T.Theme.fontFamily; pixelSize: 9 }
            Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (clickHandler) clickHandler()
        }
    }

    component PasswordInput: Rectangle {
        id: pwdRoot
        property alias text: input.text
        property color iconColor: T.Theme.color4
        signal accepted
        signal escaped

        Layout.fillWidth: true
        height: 24
        radius: 8
        color: input.activeFocus ? T.Theme.pw(iconColor, 0.12) : T.Theme.pillBg
        border.color: input.activeFocus ? T.Theme.pw(iconColor, 0.60) : T.Theme.barBorder
        border.width: 1

        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

        RowLayout {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 9; rightMargin: 9 }
            spacing: 6
            Text { text: "󰌾"; color: pwdRoot.iconColor; opacity: 0.65; font { family: T.Theme.fontFamily; pixelSize: 12 } }
            TextInput {
                id: input
                Layout.fillWidth: true
                echoMode: TextInput.Password
                color: T.Theme.fg
                selectionColor: T.Theme.pw(pwdRoot.iconColor, 0.35)
                font { family: T.Theme.fontFamily; pixelSize: 12; bold: true }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "sudo password…"
                    color: T.Theme.fg
                    opacity: 0.28
                    font: input.font
                    visible: input.text.length === 0
                }
                Keys.onReturnPressed: pwdRoot.accepted()
                Keys.onEnterPressed:  pwdRoot.accepted()
                Keys.onEscapePressed: pwdRoot.escaped()
            }
        }
    }

    component ActionButton: Rectangle {
        property string icon
        property string text
        property color accent
        property var clickHandler: null
        property bool disabled: false

        Layout.fillWidth: true
        height: 28
        radius: 8

        opacity: disabled ? 0.35 : 1.0
        Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }

        color: (!disabled && ma.pressed) ? T.Theme.pw(accent, 0.45)
             : (!disabled && ma.containsMouse) ? T.Theme.pw(accent, 0.28)
             : T.Theme.pw(accent, 0.14)

        border.color: T.Theme.pw(accent, disabled ? 0.15 : 0.35)
        border.width: 1

        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 6
            Text { text: icon; color: accent; font { family: T.Theme.fontFamily; pixelSize: 12 } }
            Text { text: parent.parent.text; color: accent; font { family: T.Theme.fontFamily; pixelSize: 11; bold: true } }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!disabled && clickHandler) clickHandler()
        }
    }


    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: pacmanProcess
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() === "") return
                _appendLog(line, false)
                var m = line.match(/(?:upgrading|installing|reinstalling|removing)\s+(\S+)\s+\((\d+)\/(\d+)\)/i)
                if (m) {
                    state.currentPkg = m[1]
                    state.pkgsDone = parseInt(m[2])
                    if (state.pkgCount === 0) state.pkgCount = parseInt(m[3])
                    state.progress = (parseInt(m[2]) / parseInt(m[3])) * 0.5
                    return
                }
                var d = line.match(/^::\s*(.*)/i)
                if (d) state.currentPkg = d[1]
            }
        }
        stderr: SplitParser { onRead: function(line) { if (line.trim()) _appendLog(line, true) } }
        onExited: function(code) {
            if (code !== 0) state.hadError = true
            state.currentPkg = ""
            state.progress = 0.5
            state.phase = "Flatpak"
            state.pkgsDone = 0
            state.pkgCount = 0
            flatpakProcess.running = true
        }
    }

    Process {
        id: flatpakProcess
        command: ["flatpak", "update", "-y"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() === "") return
                _appendLog(line, false)
                var m = line.match(/^(?:Updating|Installing|Uninstalling)\s+(\S+)/i)
                if (m) state.currentPkg = m[1]
                var p = line.match(/([\d.]+)\s*MB\s*\/\s*([\d.]+)\s*MB/i)
                if (p) state.progress = 0.5 + (parseFloat(p[1]) / parseFloat(p[2])) * 0.5
            }
        }
        stderr: SplitParser { onRead: function(line) { if (line.trim()) _appendLog(line, true) } }
        onExited: function(code) {
            if (code !== 0) state.hadError = true
            state.currentPkg = ""
            state.progress = 1.0
            state.running = false
            state.done = true
            panel.updateFinished()
            notifyProcess.command = state.hadError
                ? ["notify-send", "--app-name=System Update", "--urgency=critical", "--icon=dialog-error", "Update failed", "One or more steps exited with an error."]
                : ["notify-send", "--app-name=System Update", "--urgency=normal", "--icon=system-software-update", "System updated", "Pacman and Flatpak are up to date."]
            notifyProcess.running = false
            notifyProcess.running = true
            if (!state.hadError) autoCloseTimer.start()
        }
    }

    Process {
        id: vencordProcess
        stdout: SplitParser { onRead: function(line) { if (line.trim()) _appendLog(line, false) } }
        stderr: SplitParser { onRead: function(line) { if (line.trim()) _appendLog(line, true) } }
        onExited: function(code) {
            if (code !== 0) state.vencordError = true
            state.vencordRunning = false
            state.vencordDone = true
            state.progress = 1.0
            panel.updateFinished()
            notifyProcess.command = state.vencordError
                ? ["notify-send", "--app-name=Vencord", "--urgency=critical", "--icon=dialog-error", "Vencord update failed", "The installer exited with an error."]
                : ["notify-send", "--app-name=Vencord", "--urgency=normal", "--icon=system-software-update", "Vencord updated", "Discord has been patched successfully."]
            notifyProcess.running = false
            notifyProcess.running = true
            if (!state.vencordError) autoCloseTimer.start()
        }
    }

    Process { id: notifyProcess; running: false }

    // ── Confirmation handlers ─────────────────────────────────────────────────
    function _confirmSysUpdate() {
        if (passField.text.length === 0) return
        var pass = passField.text
        passField.text = ""
        state.view = "running"
        state.running = true
        state.phase = "Pacman"
        pacmanProcess.command = ["bash", "-c", "printf '%s\\n' " + _shellQuote(pass) + " | sudo -S -p '' pacman -Syu --noconfirm"]
        pacmanProcess.running = true
    }

    function _confirmVencord() {
        if (passField.text.length === 0) return
        var pass = passField.text
        passField.text = ""
        state.view = "running"
        state.doVencord = true
        state.vencordRunning = true
        state.phase = "Vencord"
        state.progress = 0.0

        var script = [
            "set -e",
            "CLI=$(mktemp /tmp/vencord-cli.XXXXXX)",
            "curl -sSL https://github.com/Vendicated/VencordInstaller/releases/latest/download/VencordInstallerCli-Linux -o \"$CLI\"",
            "chmod +x \"$CLI\"",
            "printf '%s\\n' " + _shellQuote(pass) + " | sudo -S -p '' \"$CLI\" --install --branch stable",
            "rm -f \"$CLI\""
        ].join("\n")

        vencordProcess.command = ["bash", "-c", script]
        vencordProcess.running = true
    }
}
