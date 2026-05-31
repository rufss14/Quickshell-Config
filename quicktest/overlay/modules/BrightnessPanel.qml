import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T

Item {
    id: root

    implicitWidth:  320
    implicitHeight: mainCol.implicitHeight + 28

    // Each entry: { name, label, port, type, bus, brightness, dragging, controllable }
    ListModel { id: monitors }

    // Exposed so OverlayRoot can size the popup window via brightnessContent.monitorCount
    readonly property int monitorCount: monitors.count

    property bool probing: false

    // ── Probe: DDC monitors ───────────────────────────────────────────────────
    Process {
        id: ddcDetect
        command: ["sh", "-c",
            "ddcutil detect 2>/dev/null | awk '" +
            "function emit(    cmd,val) {" +
            "  if (bus == \"\") return;" +
            "  lbl = (mdl != \"\") ? mdl : mfg;" +
            "  if (lbl == \"\") lbl = \"Display\";" +
            "  cmd = \"ddcutil getvcp 10 --bus \" bus \" 2>/dev/null | grep -oP \\\"current value =\\\\s*\\\\K[0-9]+\\\"\";" +
            "  cmd | getline val; close(cmd);" +
            "  if (val != \"\") print \"OK|\" bus \"|\" lbl \"|\" port \"|\" val;" +
            "  else             print \"RO|\" bus \"|\" lbl \"|\" port \"|0\";" +
            "}" +
            "/^Display [0-9]/     { emit(); bus=\"\"; mfg=\"\"; mdl=\"\"; port=\"\" }" +
            "/I2C bus:/           { match($0, /i2c-([0-9]+)/, a); bus = a[1] }" +
            "/Mfg id:/            { sub(/.*Mfg id:[ \\t]*/,\"\"); split($0,w,/[ \\t]+/); mfg = w[1] }" +
            "/Model:/             { sub(/.*Model:[ \\t]*/,\"\"); sub(/[ \\t]*$/,\"\"); mdl = $0 }" +
            "/Display interface:/ { match($0, /(DisplayPort|HDMI|DVI|VGA)/, p); port = p[1] }" +
            "END                  { emit() }'"
        ]
        running: false
        stdout: StdioCollector { id: ddcOut }
        onExited: function() {
            var lines = ddcOut.text.trim().split("\n")
            for (var i = 0; i < lines.length; i++) {
                var parts = lines[i].split("|")
                if (parts.length === 5 && (parts[0] === "OK" || parts[0] === "RO")) {
                    var ok  = parts[0] === "OK"
                    var val = parseInt(parts[4])
                    monitors.append({
                        name:         "i2c-" + parts[1].trim(),
                        label:        parts[2].trim() || ("Display " + (monitors.count + 1)),
                        port:         parts[3].trim(),
                        type:         "ddc",
                        bus:          parts[1].trim(),
                        brightness:   (ok && !isNaN(val)) ? Math.max(0, Math.min(100, val)) : 0,
                        dragging:     false,
                        controllable: ok ? 1 : 0
                    })
                }
            }
            bclList.running = true
        }
    }

    // ── Probe: kernel backlight devices ───────────────────────────────────────
    Process {
        id: bclList
        command: ["sh", "-c",
            "brightnessctl --list 2>/dev/null | grep -E \"^'\" | while IFS= read -r line; do " +
            "  dev=$(echo \"$line\" | grep -oP \"(?<=')[^']+\"); " +
            "  label=$(echo \"$line\" | grep -oP \"\\([^)]+\\)\" | head -1 | tr -d '()'); " +
            "  val=$(brightnessctl --device \"$dev\" g 2>/dev/null); " +
            "  max=$(brightnessctl --device \"$dev\" m 2>/dev/null); " +
            "  [ -n \"$max\" ] && [ \"$max\" -gt 0 ] && echo \"BCL|$dev|${label:-$dev}|$((val * 100 / max))\"; " +
            "done"
        ]
        running: false
        stdout: StdioCollector { id: bclOut }
        onExited: function() {
            var lines = bclOut.text.trim().split("\n")
            for (var i = 0; i < lines.length; i++) {
                var parts = lines[i].split("|")
                if (parts.length === 4 && parts[0] === "BCL") {
                    var val = parseInt(parts[3])
                    monitors.append({
                        name:         parts[1].trim(),
                        label:        parts[2].trim() || parts[1].trim(),
                        port:         "Backlight",
                        type:         "bcl",
                        bus:          "",
                        brightness:   isNaN(val) ? 50 : Math.max(0, Math.min(100, val)),
                        dragging:     false,
                        controllable: 1
                    })
                }
            }
            if (monitors.count === 0) {
                monitors.append({ name: "backlight", label: "Display", port: "Backlight",
                                  type: "bcl", bus: "", brightness: 50,
                                  dragging: false, controllable: 1 })
                bclFallback.running = true
            } else {
                root.probing = false
            }
        }
    }

    Process {
        id: bclFallback
        command: ["sh", "-c", "val=$(brightnessctl g); max=$(brightnessctl m); echo $((val * 100 / max))"]
        running: false
        stdout: StdioCollector { id: bclFallbackOut }
        onExited: function() {
            var v = parseInt(bclFallbackOut.text.trim())
            if (!isNaN(v) && monitors.count > 0)
                monitors.setProperty(0, "brightness", Math.max(0, Math.min(100, v)))
            root.probing = false
        }
    }

    Process { id: setProc; running: false }

    Timer {
        id: applyTimer
        interval: 80; repeat: false
        property int pendingIndex: -1
        property int pendingVal: 0
        onTriggered: { if (pendingIndex >= 0) root._doApply(pendingIndex, pendingVal) }
    }

    function applyBrightness(index, val) {
        val = Math.max(0, Math.min(100, val))
        applyTimer.pendingIndex = index
        applyTimer.pendingVal   = val
        applyTimer.restart()
    }

    function _doApply(index, val) {
        var m = monitors.get(index)
        if (!m.controllable) return
        if (m.type === "ddc")
            setProc.command = ["ddcutil", "setvcp", "10", val.toString(), "--bus", m.bus]
        else
            setProc.command = ["brightnessctl", "--device", m.name, "set", val.toString() + "%"]
        setProc.running = false
        setProc.running = true
    }

    function startProbe() {
        monitors.clear()
        root.probing = true
        ddcDetect.running = false
        ddcDetect.running = true
    }

    Component.onCompleted: startProbe()

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 34
                    height: 34
                    radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.25) }
                        GradientStop { position: 1.0; color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.22) }
                    }
                    border.color: T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰃟"
                        color: T.Theme.fg
                        font.pixelSize: 18
                        font.family: T.Theme.fontFamily
                    }
                }

                ColumnLayout {
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "Brightness"
                            color: T.Theme.fg
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                        Text {
                            text: "Control"
                            color: T.Theme.color9
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: T.Theme.fontFamily
                        }
                    }
                    Text {
                        text: monitors.count + " display" + (monitors.count === 1 ? "" : "s") + " detected"
                        color: T.Theme.fg
                        opacity: 0.5
                        font.pixelSize: 10
                        font.family: T.Theme.fontFamily
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Refresh button
            Rectangle {
                width: 30
                height: 30
                radius: 8
                color: refreshMa.containsMouse
                    ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.20)
                    : T.Theme.pillBg
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: T.Theme.fg
                    font.pixelSize: 14
                    font.family: T.Theme.fontFamily
                }
                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startProbe()
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

        // ── Monitor rows ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: monitors.count > 0

            Repeater {
                model: monitors
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    opacity: model.controllable ? 1.0 : 0.45
                    Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }

                    // Label row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "󰍹"
                            color: T.Theme.color9
                            opacity: 0.70
                            font { family: T.Theme.fontFamily; pixelSize: 11 }
                        }

                        Text {
                            text: model.label || ""
                            color: T.Theme.fg
                            opacity: 0.90
                            font { family: T.Theme.fontFamily; pixelSize: 11; bold: true }
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: model.port || ""
                            color: T.Theme.fg
                            opacity: 0.28
                            font { family: T.Theme.fontFamily; pixelSize: 9 }
                            visible: (model.port || "") !== ""
                        }

                        // Percentage badge
                        Rectangle {
                            implicitWidth: pctLabel.implicitWidth + 10
                            height: 18; radius: 5
                            color: T.Theme.pw(T.Theme.pal?.colors?.color9 || "#7dcfff",
                                model.dragging ? 0.22 : 0.12)
                            border.color: T.Theme.pw(T.Theme.pal?.colors?.color9 || "#7dcfff",
                                model.dragging ? 0.45 : 0.25)
                            border.width: 1
                            Behavior on color        { ColorAnimation { duration: T.Theme.animFast } }
                            Behavior on border.color { ColorAnimation { duration: T.Theme.animFast } }
                            Text {
                                id: pctLabel
                                anchors.centerIn: parent
                                text: model.controllable ? (model.brightness + "%") : "Read-only"
                                color: T.Theme.color9
                                font { family: T.Theme.fontFamily; pixelSize: 9; bold: true }
                            }
                        }
                    }

                    // Slider
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 14
                        visible: model.controllable

                        Rectangle {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 4; radius: 2
                            color: T.Theme.pw(T.Theme.pal?.colors?.color7, 0.14)

                            Rectangle {
                                width: Math.max(track.radius * 2, (model.brightness / 100) * track.width)
                                height: track.height; radius: track.radius
                                color: T.Theme.color9
                                opacity: 0.90
                                Behavior on width { NumberAnimation { duration: model.dragging ? 0 : 50; easing.type: Easing.OutQuad } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            function posToValue(mx) {
                                return Math.round(Math.max(0, Math.min(1, mx / track.width)) * 100)
                            }
                            onPressed: function(e) {
                                monitors.setProperty(index, "dragging", true)
                                monitors.setProperty(index, "brightness", posToValue(e.x))
                            }
                            onReleased: function() {
                                monitors.setProperty(index, "dragging", false)
                                root._doApply(index, model.brightness)
                            }
                            onPositionChanged: function(e) {
                                if (pressed) monitors.setProperty(index, "brightness", posToValue(e.x))
                            }
                            onWheel: function(e) {
                                var d = e.angleDelta.y > 0 ? 5 : -5
                                var v = Math.max(0, Math.min(100, model.brightness + d))
                                monitors.setProperty(index, "brightness", v)
                                root.applyBrightness(index, v)
                            }
                        }
                    }

                    // Divider between monitors (not after last)
                    Rectangle {
                        Layout.fillWidth: true; height: 1
                        color: T.Theme.pw(T.Theme.pal?.colors?.color9 || "#7dcfff", 0.07)
                        visible: index < monitors.count - 1
                    }
                }
            }
        }

        // ── Empty / probing state ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 60
            visible: monitors.count === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.probing ? "󰔟" : "󰍺"
                    color: T.Theme.fg; opacity: 0.30
                    font { family: T.Theme.fontFamily; pixelSize: 22 }
                    RotationAnimation on rotation {
                        loops: Animation.Infinite; from: 0; to: 360; duration: 1000
                        running: root.probing; easing.type: Easing.Linear
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.probing ? "Detecting displays…" : "No displays detected"
                    color: T.Theme.fg; opacity: 0.35
                    font { family: T.Theme.fontFamily; pixelSize: 10 }
                }
            }
        }

    }
}
