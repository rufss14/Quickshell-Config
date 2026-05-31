import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── WifiPanel ─────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: 360

    // ── Height ────────────────────────────────────────────────────────────────
    readonly property int _headerH:  56
    readonly property int _divH:     17           // divider + margins
    readonly property int _statusH:  (errorMsg !== "" || connectingSsid !== "") ? 50 : 0
    readonly property int _passH:    passwordMode ? 182 : 0
    readonly property int _hiddenH:  hiddenMode   ? 182 : 0
    readonly property int _listH:    radioEnabled && networks.length > 0
                                         ? Math.min(networks.length, 5) * 62
                                         : 88
    readonly property int _footerH:  42
    implicitHeight: 20 + _headerH + _divH + _statusH + _passH + _hiddenH + _listH + _footerH

    // ── State ─────────────────────────────────────────────────────────────────
    property var    networks:       []
    property bool   scanning:       false
    property bool   radioEnabled:   true
    property string connectingSsid: ""
    property string errorMsg:       ""
    property string activeIp:       ""

    property string pendingSsid:  ""
    property bool   passwordMode: false
    property bool   hiddenMode:   false
    property bool   showPassword: false
    property string hiddenSsid:   ""
    property bool   ipBlurred:    true

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: scanProc
        command: ["sh", "-c",
            "radio=$(nmcli radio wifi); echo \"RADIO:$radio\"; " +
            "nmcli dev wifi rescan 2>/dev/null & sleep 0.8; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | " +
            "awk -F: '{ k=$2; if (!seen[k] || $3+0 > sig[k]+0) { seen[k]=1; sig[k]=$3; line[k]=$0 } } END { for (k in line) print line[k] }' | " +
            "sort -t: -k3 -rn"
        ]
        running: false
        property var _lines: []

        stdout: SplitParser {
            onRead: function(data) {
                var t = data.trim()
                if (t) scanProc._lines.push(t)
            }
        }
        onRunningChanged: function() {
            if (running) {
                root.scanning = true
                _lines = []
            } else {
                root.scanning = false
                var nets = []
                for (var i = 0; i < _lines.length; i++) {
                    var l = _lines[i]
                    if (l.startsWith("RADIO:")) {
                        root.radioEnabled = l.slice(6).trim() === "enabled"
                        continue
                    }
                    var parts = l.split(":")
                    if (parts.length < 4) continue
                    var active   = parts[0] === "yes"
                    var ssid     = parts.slice(1, parts.length - 2).join(":")
                    var signal   = parseInt(parts[parts.length - 2]) || 0
                    var security = parts[parts.length - 1].trim()
                    if (ssid === "" || ssid === "--") continue
                    nets.push({ ssid: ssid, signal: signal, security: security, active: active, saved: false })
                }
                root.networks = nets
                savedProc._saved = []
                savedProc.running = true
                if (root.radioEnabled) ipProc.running = false; ipProc.running = true
            }
        }
    }

    Process {
        id: savedProc
        command: ["sh", "-c", "nmcli -t -f NAME con show 2>/dev/null"]
        running: false
        property var _saved: []
        stdout: SplitParser {
            onRead: function(data) { savedProc._saved.push(data.trim()) }
        }
        onRunningChanged: function() {
            if (!running) {
                var s = _saved.slice()
                var nets = root.networks.slice()
                for (var i = 0; i < nets.length; i++)
                    nets[i].saved = s.indexOf(nets[i].ssid) >= 0
                root.networks = nets
            }
        }
    }

    Process {
        id: ipProc
        command: ["sh", "-c", "nmcli -t -f IP4.ADDRESS dev show $(nmcli -t -f DEVICE,STATE dev | grep ':connected' | head -1 | cut -d: -f1) 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f1"]
        running: false
        stdout: StdioCollector { id: ipOut }
        onRunningChanged: function() {
            if (!running) root.activeIp = ipOut.text.trim()
        }
    }

    Process {
        id: connectProc
        running: false
        property string _stderr: ""
        property string _stdout: ""
        stdout: SplitParser { onRead: function(data) { var t = data.trim(); if (t) connectProc._stdout += t + "\n" } }
        stderr: SplitParser { onRead: function(data) { var t = data.trim(); if (t) connectProc._stderr += t + "\n" } }
        onRunningChanged: function() {
            if (!running) {
                root.connectingSsid = ""
                var combined = (_stderr + "\n" + _stdout).trim()
                if (combined !== "") {
                    var lines = combined.split("\n")
                    for (var i = 0; i < lines.length; i++) {
                        var l = lines[i].trim()
                        if (l.match(/error|fail/i)) {
                            root.errorMsg = l.replace(/^Error:\s*/i, "")
                            break
                        }
                    }
                }
                _stderr = ""
                _stdout = ""
                refresh()
            }
        }
    }

    Process {
        id: radioProc
        running: false
        onRunningChanged: function() { if (!running) refresh() }
    }

    Process {
        id: disconnectProc
        running: false
        onRunningChanged: function() { if (!running) refresh() }
    }

    Process {
        id: forgetProc
        running: false
        stderr: SplitParser {
            onRead: function(data) {
                var t = data.trim()
                if (t && !t.match(/^Connection .* successfully deleted/i))
                    root.errorMsg = t.replace(/^Error:\s*/i, "")
            }
        }
        onRunningChanged: function() { if (!running) refresh() }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function refresh() {
        if (scanProc.running) return
        scanProc.running = true
    }

    function connectTo(ssid, password) {
        root.connectingSsid = ssid
        root.errorMsg = ""
        root.passwordMode = false
        root.hiddenMode = false
        connectProc._stderr = ""
        connectProc._stdout = ""
        connectProc.command = (password !== undefined && password !== "")
            ? ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "dev", "wifi", "connect", ssid]
        connectProc.running = true
    }

    function doConnect() {
        if (!passwordMode) return
        var pass = passField.text
        passField.text = ""
        passwordMode = false
        connectTo(pendingSsid, pass)
    }

    function doHiddenConnect() {
        if (!hiddenMode) return
        var ssid = hiddenSsidField.text.trim()
        var pass = hiddenPassField.text
        if (ssid === "") return
        hiddenSsidField.text = ""
        hiddenPassField.text = ""
        hiddenMode = false
        connectTo(ssid, pass)
    }

    function forgetNetwork(ssid) {
        forgetProc.command = ["sh", "-c", "nmcli con delete id \"" + ssid + "\" 2>&1; true"]
        forgetProc.running = true
    }

    function signalBars(s) {
        if (s < 20) return 1
        if (s < 45) return 2
        if (s < 65) return 3
        return 4
    }

    function signalColor(s) {
        if (s < 25) return T.Theme.color1
        if (s < 50) return T.Theme.color3
        return T.Theme.color4
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 15000
        repeat: true
        running: root.radioEnabled && !root.passwordMode && !root.hiddenMode
        onTriggered: refresh()
    }

    onPasswordModeChanged: { if (passwordMode) Qt.callLater(() => passField.forceActiveFocus()) }
    onHiddenModeChanged:   { if (hiddenMode)   Qt.callLater(() => hiddenSsidField.forceActiveFocus()) }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Gradient icon pill — matches BrightnessPanel style
            Rectangle {
                width: 36; height: 36
                radius: 10
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.28) }
                    GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.22) }
                }
                border.color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.35)
                border.width: 1
                Behavior on gradient { }

                Text {
                    anchors.centerIn: parent
                    text: root.radioEnabled ? "󰤨" : "󰤭"
                    font.pixelSize: 18
                    font.family: T.Theme.fontFamily
                    color: root.radioEnabled ? T.Theme.color4 : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.45)
                    Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                }
            }

            // Title + subtitle
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true

                RowLayout {
                    spacing: 6
                    Text {
                        text: "Wi-Fi"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: T.Theme.fontFamily
                        color: T.Theme.fg
                    }
                    Text {
                        text: "& Network"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: T.Theme.fontFamily
                        color: T.Theme.color4
                    }
                }

                Text {
                    property var _active: root.networks.filter(n => n.active)
                    text: root.scanning ? "Scanning…"
                        : !root.radioEnabled ? "Radio disabled"
                        : _active.length > 0 ? "Connected to " + _active[0].ssid
                        : root.networks.length + " network" + (root.networks.length !== 1 ? "s" : "") + " found"
                    font.pixelSize: 10
                    font.family: T.Theme.fontFamily
                    color: T.Theme.fg
                    opacity: 0.45
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // IP blur toggle button
            Rectangle {
                width: 30; height: 30; radius: 8
                visible: root.activeIp !== ""
                color: ipToggleMa.containsMouse
                    ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.18)
                    : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: root.ipBlurred ? "󰈉" : "󰈞"
                    font.pixelSize: 13
                    font.family: T.Theme.fontFamily
                    color: root.ipBlurred
                        ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.45)
                        : T.Theme.color9
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                MouseArea {
                    id: ipToggleMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ipBlurred = !root.ipBlurred
                }
            }

            // Scan / refresh button
            Rectangle {
                width: 30; height: 30; radius: 8
                color: scanMa.containsMouse
                    ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.18)
                    : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: "󰑓"
                    font.pixelSize: 14
                    font.family: T.Theme.fontFamily
                    color: T.Theme.pw(T.Theme.pal?.colors?.color4, root.scanning ? 0.35 : 0.85)
                    RotationAnimator on rotation {
                        running: root.scanning
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite
                    }
                }
                MouseArea {
                    id: scanMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.scanning
                    onClicked: refresh()
                }
            }

            // Radio toggle
            Rectangle {
                width: 44; height: 24; radius: 12
                color: root.radioEnabled
                    ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.80)
                    : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.15)
                Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                border.color: root.radioEnabled
                    ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.40)
                    : T.Theme.barBorder
                border.width: 1

                Rectangle {
                    width: 18; height: 18; radius: 9
                    color: "white"
                    opacity: root.radioEnabled ? 1.0 : 0.55
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.radioEnabled ? parent.width - width - 3 : 3
                    Behavior on x       { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        radioProc.command = ["nmcli", "radio", "wifi", root.radioEnabled ? "off" : "on"]
                        radioProc.running = true
                        root.radioEnabled = !root.radioEnabled
                    }
                }
            }
        }

        // ── Divider ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            height: 1
            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.07)
        }

        // ── Status bar (error / connecting) ───────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 40
            radius: 10
            visible: root.errorMsg !== "" || root.connectingSsid !== ""
            color: root.errorMsg !== ""
                ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.10)
                : T.Theme.pw(T.Theme.pal?.colors?.color4, 0.08)
            border.color: root.errorMsg !== ""
                ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.28)
                : T.Theme.barBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: root.errorMsg !== "" ? "󰅙" : "󰤨"
                    font.pixelSize: 13; font.family: T.Theme.fontFamily
                    color: root.errorMsg !== "" ? T.Theme.color1 : T.Theme.color4
                }
                Text {
                    Layout.fillWidth: true
                    text: root.errorMsg !== "" ? root.errorMsg : "Connecting to " + root.connectingSsid + "…"
                    font.pixelSize: 11; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.85
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: 22; height: 22; radius: 6
                    visible: root.errorMsg !== ""
                    color: dismissMa.containsMouse
                        ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.18)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.pixelSize: 11; font.family: T.Theme.fontFamily
                        color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.55)
                    }
                    MouseArea {
                        id: dismissMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.errorMsg = ""
                    }
                }
            }
        }

        // ── Password dialog ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: passLayout.implicitHeight + 24
            radius: 12
            visible: passwordMode
            color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.07)
            border.color: T.Theme.barBorder
            border.width: 1

            ColumnLayout {
                id: passLayout
                anchors.fill: parent; anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text {
                        text: "󰌾"; font.pixelSize: 13; font.family: T.Theme.fontFamily
                        color: T.Theme.color4; opacity: 0.80
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Connect to \"" + pendingSsid + "\""
                        color: T.Theme.fg; font.pixelSize: 12; font.weight: Font.DemiBold
                        font.family: T.Theme.fontFamily; elide: Text.ElideRight
                    }
                }

                // Password input — matches UpdatePanel PasswordInput style
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 8
                    color: passField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.12) : T.Theme.pillBg
                    border.color: passField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.55) : T.Theme.barBorder
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                        spacing: 6
                        Text {
                            text: "󰌋"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                            color: T.Theme.fg; opacity: 0.35
                        }
                        Item {
                            Layout.fillWidth: true; height: 28
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password…"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                                color: T.Theme.fg; opacity: 0.28
                                visible: passField.text === ""
                            }
                            TextInput {
                                id: passField
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: showPassword ? TextInput.Normal : TextInput.Password
                                color: T.Theme.fg
                                font.pixelSize: 12; font.family: T.Theme.fontFamily
                                cursorVisible: activeFocus; selectByMouse: true
                                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                                Keys.onReturnPressed: root.doConnect()
                                Keys.onEscapePressed: { passwordMode = false; passField.text = "" }
                            }
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: eyeMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.10) : "transparent"
                            Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                            Text {
                                anchors.centerIn: parent
                                text: showPassword ? "󰈞" : "󰈉"
                                font.pixelSize: 12; font.family: T.Theme.fontFamily
                                color: showPassword ? T.Theme.color4 : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.45)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: eyeMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: showPassword = !showPassword
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        width: 72; height: 30; radius: 8
                        color: cancelMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.10) : T.Theme.pillBg
                        border.color: T.Theme.barBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Text {
                            anchors.centerIn: parent; text: "Cancel"
                            color: T.Theme.fg; opacity: 0.65
                            font.pixelSize: 11; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                        }
                        MouseArea {
                            id: cancelMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { passwordMode = false; passField.text = "" }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 8
                        color: connectMa.containsMouse
                            ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90)
                            : T.Theme.pw(T.Theme.pal?.colors?.color4, 0.75)
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 5
                            Text { text: "󰌹"; font.pixelSize: 12; font.family: T.Theme.fontFamily; color: "white"; opacity: 0.90 }
                            Text { text: "Connect"; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                        }
                        MouseArea {
                            id: connectMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.doConnect()
                        }
                    }
                }
            }
        }

        // ── Hidden network dialog ─────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: hiddenLayout.implicitHeight + 24
            radius: 12
            visible: hiddenMode
            color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.07)
            border.color: T.Theme.barBorder
            border.width: 1

            ColumnLayout {
                id: hiddenLayout
                anchors.fill: parent; anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text {
                        text: "󰀂"; font.pixelSize: 13; font.family: T.Theme.fontFamily
                        color: T.Theme.color9; opacity: 0.80
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Connect to hidden network"
                        color: T.Theme.fg; font.pixelSize: 12; font.weight: Font.DemiBold
                        font.family: T.Theme.fontFamily
                    }
                }

                // SSID input
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 8
                    color: hiddenSsidField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.12) : T.Theme.pillBg
                    border.color: hiddenSsidField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.55) : T.Theme.barBorder
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                        spacing: 6
                        Text {
                            text: "󰈚"; font.pixelSize: 11; font.family: T.Theme.fontFamily
                            color: T.Theme.fg; opacity: 0.35
                        }
                        Item {
                            Layout.fillWidth: true; height: 28
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Network name (SSID)…"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                                color: T.Theme.fg; opacity: 0.28
                                visible: hiddenSsidField.text === ""
                            }
                            TextInput {
                                id: hiddenSsidField
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: T.Theme.fg
                                font.pixelSize: 12; font.family: T.Theme.fontFamily
                                cursorVisible: activeFocus; selectByMouse: true
                                Keys.onReturnPressed: hiddenPassField.forceActiveFocus()
                                Keys.onEscapePressed: { hiddenMode = false; hiddenSsidField.text = ""; hiddenPassField.text = "" }
                            }
                        }
                    }
                }

                // Password input
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 8
                    color: hiddenPassField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.12) : T.Theme.pillBg
                    border.color: hiddenPassField.activeFocus ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.55) : T.Theme.barBorder
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                        spacing: 6
                        Text {
                            text: "󰌋"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                            color: T.Theme.fg; opacity: 0.35
                        }
                        Item {
                            Layout.fillWidth: true; height: 28
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password (optional)…"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                                color: T.Theme.fg; opacity: 0.28
                                visible: hiddenPassField.text === ""
                            }
                            TextInput {
                                id: hiddenPassField
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: T.Theme.fg
                                font.pixelSize: 12; font.family: T.Theme.fontFamily
                                cursorVisible: activeFocus; selectByMouse: true
                                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                                Keys.onReturnPressed: root.doHiddenConnect()
                                Keys.onEscapePressed: { hiddenMode = false; hiddenSsidField.text = ""; hiddenPassField.text = "" }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        width: 72; height: 30; radius: 8
                        color: hidCancelMa.containsMouse ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.10) : T.Theme.pillBg
                        border.color: T.Theme.barBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        Text {
                            anchors.centerIn: parent; text: "Cancel"
                            color: T.Theme.fg; opacity: 0.65
                            font.pixelSize: 11; font.weight: Font.Medium; font.family: T.Theme.fontFamily
                        }
                        MouseArea {
                            id: hidCancelMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { hiddenMode = false; hiddenSsidField.text = ""; hiddenPassField.text = "" }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 8
                        color: hidConnectMa.containsMouse
                            ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.90)
                            : T.Theme.pw(T.Theme.pal?.colors?.color9, 0.70)
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 5
                            Text { text: "󰀂"; font.pixelSize: 12; font.family: T.Theme.fontFamily; color: "white"; opacity: 0.90 }
                            Text { text: "Connect"; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold; font.family: T.Theme.fontFamily }
                        }
                        MouseArea {
                            id: hidConnectMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.doHiddenConnect()
                        }
                    }
                }
            }
        }

        // ── Network list / empty states ────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: _listH

            // Radio off
            ColumnLayout {
                anchors.centerIn: parent; spacing: 6
                visible: !root.radioEnabled
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰤭"; font.pixelSize: 32; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.22
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Wi-Fi is turned off"
                    font.pixelSize: 12; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.35
                }
            }

            // Scanning / no results
            ColumnLayout {
                anchors.centerIn: parent; spacing: 6
                visible: root.radioEnabled && networks.length === 0
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.scanning ? "󰑓" : "󰤞"
                    font.pixelSize: 28; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.22
                    RotationAnimator on rotation {
                        running: root.scanning
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.scanning ? "Scanning for networks…" : "No networks found"
                    font.pixelSize: 12; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.35
                }
            }

            // Network list
            ListView {
                anchors.fill: parent
                visible: root.radioEnabled && root.networks.length > 0
                model: root.networks
                spacing: 4
                clip: true

                delegate: Rectangle {
                    id: netRow
                    required property var    modelData
                    required property int    index
                    width: ListView.view.width
                    height: 58
                    radius: 11

                    readonly property bool isActive:     modelData.active
                    readonly property bool isConnecting: root.connectingSsid === modelData.ssid
                    readonly property bool isSaved:      modelData.saved
                    readonly property bool showActions:  netMa.hovered && !isConnecting

                    color: isActive
                        ? T.Theme.pw(T.Theme.pal?.colors?.color4, netMa.hovered ? 0.20 : 0.13)
                        : netMa.hovered
                            ? T.Theme.pw(T.Theme.pal?.colors?.color7, 0.08)
                            : T.Theme.pillBg
                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                    // Active indicator strip
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                                  topMargin: 8; bottomMargin: 8; leftMargin: 4 }
                        width: 3; radius: 2
                        visible: isActive
                        color: T.Theme.color4
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: isActive ? 16 : 10; rightMargin: 10 }
                        spacing: 10

                        // Signal bars graphic
                        Item {
                            width: 20; height: 20
                            property int bars: signalBars(modelData.signal)
                            property color barColor: isActive ? T.Theme.color4 : signalColor(modelData.signal)

                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    width: 4; radius: 2
                                    height: 5 + index * 4
                                    anchors.bottom: parent.bottom
                                    x: index * 5
                                    color: (index < parent.bars) ? parent.barColor : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.18)
                                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                }
                            }
                        }

                        // SSID + meta
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3

                            Text {
                                text: modelData.ssid
                                font.pixelSize: 12; font.weight: isActive ? Font.DemiBold : Font.Normal
                                font.family: T.Theme.fontFamily
                                color: T.Theme.fg; elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 4
                                Text {
                                    text: modelData.security !== "" && modelData.security !== "--"
                                        ? "󰌾 " + modelData.security : "󰌿 Open"
                                    font.pixelSize: 9; font.family: T.Theme.fontFamily
                                    color: T.Theme.fg; opacity: 0.38
                                }
                                Text {
                                    text: "·"; font.pixelSize: 9; font.family: T.Theme.fontFamily
                                    color: T.Theme.fg; opacity: 0.22
                                }
                                Text {
                                    text: modelData.signal + "%"
                                    font.pixelSize: 9; font.family: T.Theme.fontFamily
                                    color: T.Theme.fg; opacity: 0.38
                                }
                                // Saved pill
                                Rectangle {
                                    width: savedLbl.implicitWidth + 8; height: 13; radius: 3
                                    visible: isSaved && !isActive
                                    color: T.Theme.pw(T.Theme.pal?.colors?.color2, 0.15)
                                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color2, 0.25)
                                    border.width: 1
                                    Text {
                                        id: savedLbl; anchors.centerIn: parent
                                        text: "saved"; font.pixelSize: 8; font.family: T.Theme.fontFamily
                                        color: T.Theme.pw(T.Theme.pal?.colors?.color2, 0.80)
                                    }
                                }
                                // Active + IP pill
                                Rectangle {
                                    width: activeLbl.implicitWidth + 8; height: 13; radius: 3
                                    visible: isActive
                                    color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.18)
                                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.35)
                                    border.width: 1
                                    Text {
                                        id: activeLbl; anchors.centerIn: parent
                                        text: {
                                            if (root.activeIp === "") return "connected"
                                            if (root.ipBlurred) return root.activeIp.replace(/[0-9]/g, "•")
                                            return root.activeIp
                                        }
                                        font.pixelSize: 8; font.family: T.Theme.fontFamily
                                        color: T.Theme.color4
                                        opacity: root.ipBlurred ? 0.55 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }
                                    }
                                }
                            }
                        }

                        // Right-side action area — fixed width, opacity-only animation
                        Item {
                            // Always reserve space for the widest possible state so
                            // nothing overflows the pill. Disconnect(72)+gap(4)+Forget(52)=128.
                            // When idle just show a 24px chevron centred inside this space.
                            width:  (isActive || isSaved) ? 128 : 24
                            height: 28
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            // Spinner while connecting
                            Text {
                                anchors.centerIn: parent; text: "󰑓"
                                font.pixelSize: 15; font.family: T.Theme.fontFamily
                                color: T.Theme.color4; opacity: 0.80
                                visible: isConnecting
                                RotationAnimator on rotation {
                                    running: isConnecting
                                    from: 0; to: 360; duration: 900
                                    loops: Animation.Infinite
                                }
                            }

                            // Idle indicator: checkmark (active) or chevron (saved/unsaved)
                            Text {
                                anchors.centerIn: parent
                                text: isActive ? "󰄬" : "󰅂"
                                font.pixelSize: isActive ? 14 : 13
                                font.family: T.Theme.fontFamily
                                color: isActive ? T.Theme.color4
                                               : T.Theme.pw(T.Theme.pal?.colors?.color7, 0.30)
                                visible: !isConnecting
                                opacity: showActions ? 0.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            // Hover action buttons — fade in over the chevron
                            Row {
                                id: actionRow
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 4
                                visible: !isConnecting && (isActive || isSaved)
                                opacity: showActions ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                // Disconnect button — only for the active connection
                                Rectangle {
                                    width: 72; height: 26; radius: 7
                                    visible: isActive
                                    color: disconnMa.containsMouse
                                        ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.28)
                                        : T.Theme.pw(T.Theme.pal?.colors?.color1, 0.12)
                                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color1, 0.25)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        font.pixelSize: 9; font.weight: Font.Medium
                                        font.family: T.Theme.fontFamily
                                        color: T.Theme.color1
                                    }
                                    MouseArea {
                                        id: disconnMa; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            disconnectProc.command = ["sh", "-c",
                                                "nmcli -t -f NAME,UUID con show --active 2>/dev/null | " +
                                                "awk -F: -v s=\"" + modelData.ssid + "\" '$1==s{print $2}' | " +
                                                "head -1 | xargs -r nmcli con down"]
                                            disconnectProc.running = true
                                        }
                                    }
                                }

                                // Forget button — for saved (and active) connections
                                Rectangle {
                                    width: 52; height: 26; radius: 7
                                    color: forgetMa.containsMouse
                                        ? T.Theme.pw(T.Theme.pal?.colors?.color3, 0.28)
                                        : T.Theme.pw(T.Theme.pal?.colors?.color3, 0.10)
                                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color3, 0.25)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Forget"
                                        font.pixelSize: 9; font.weight: Font.Medium
                                        font.family: T.Theme.fontFamily
                                        color: T.Theme.color3
                                    }
                                    MouseArea {
                                        id: forgetMa; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.forgetNetwork(modelData.ssid)
                                    }
                                }
                            }
                        }
                    }

                    // HoverHandler tracks hover without stealing clicks from children
                    HoverHandler {
                        id: netMa
                        cursorShape: Qt.PointingHandCursor
                    }

                    // Connect on click — only active over the left/centre of the row,
                    // not over the action buttons on the right
                    MouseArea {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width - ((isActive || isSaved) ? 138 : 0)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (isConnecting || isActive) return
                            root.errorMsg = ""
                            root.hiddenMode = false
                            var needsPass = modelData.security !== "" && modelData.security !== "--" && !modelData.saved
                            if (needsPass) {
                                root.pendingSsid  = modelData.ssid
                                root.passwordMode = true
                            } else {
                                root.connectTo(modelData.ssid, "")
                            }
                        }
                    }
                }
            }
        }

        // ── Footer: hidden network button ─────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 32; radius: 9
            visible: root.radioEnabled && !hiddenMode && !passwordMode
            color: hiddenBtnMa.containsMouse
                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.12)
                : T.Theme.pillBg
            border.color: hiddenBtnMa.containsMouse
                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                : T.Theme.barBorder
            border.width: 1
            Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }

            RowLayout {
                anchors.centerIn: parent; spacing: 6
                Text {
                    text: "󰀂"; font.pixelSize: 12; font.family: T.Theme.fontFamily
                    color: T.Theme.color9; opacity: 0.75
                }
                Text {
                    text: "Connect to hidden network"
                    font.pixelSize: 11; font.family: T.Theme.fontFamily
                    color: T.Theme.fg; opacity: 0.55
                }
            }
            MouseArea {
                id: hiddenBtnMa; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.passwordMode = false
                    root.hiddenMode = true
                }
            }
        }
    }
}
