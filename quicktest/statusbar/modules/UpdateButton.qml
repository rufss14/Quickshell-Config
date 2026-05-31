import QtQuick
import Quickshell.Io
import "../../theming" as T
import "../../overlay/modules" as OV

// ── UpdateButton ──────────────────────────────────────────────────────────────
// Cleaned & lightweight version
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape:    false
    property var  updatePanel: OV.Panels.updatePanel

    readonly property var _panel: updatePanel ?? OV.Panels.updatePanel ?? null

    QtObject {
        id: updateInfo
        property int  count:    0
        property bool checking: false
        property bool hasError: false
    }

    Process {
        id: checkProcess
        property int _lines: 0

        command: ["checkupdates"]

        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim().length > 0) {
                    checkProcess._lines++
                }
            }
        }

        onExited: function(code) {
            if (checkProcess._lines > 0) {
                updateInfo.count    = checkProcess._lines
                updateInfo.hasError = false
            } else if (code !== 1) {
                updateInfo.count    = 0
                updateInfo.hasError = false
            } else {
                updateInfo.hasError = true
            }

            checkProcess._lines = 0
            updateInfo.checking = false
        }
    }

    function _startCheck() {
        if (checkProcess.running) return
        checkProcess._lines = 0
        updateInfo.checking = true
        checkProcess.running = true
    }

    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._startCheck()
    }

    Timer {
        id: recheckTimer
        interval: 90000
        repeat: false
        onTriggered: root._startCheck()
    }

    Connections {
        target: root._panel
        ignoreUnknownSignals: true
        function onUpdateFinished() {
            recheckTimer.start()
        }
    }

    implicitWidth:  updateInfo.count > 0 ? 44 : 40
    implicitHeight: T.Theme.pillHeight
    radius: T.Theme.radius(barShape)
    color:  btn.containsMouse
        ? T.Theme.hoverFull
        : (updateInfo.count > 0 ? T.Theme.pw(T.Theme.pal?.colors?.color1, 0.15) : T.Theme.pillBg)

    Behavior on implicitWidth { NumberAnimation { duration: T.Theme.animFast } }
    Behavior on color         { ColorAnimation  { duration: T.Theme.animFast } }
    Behavior on radius        { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    Image {
        anchors.centerIn: parent
        source: "../../theming/icons/update.svg"
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
        opacity: updateInfo.checking ? 0.4 : 1.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Rectangle {
        visible: updateInfo.count > 0
        width:   updateInfo.count > 99 ? 18 : (updateInfo.count > 9 ? 16 : 13)
        height:  13
        radius:  barShape ? 2 : 6
        color:   updateInfo.hasError ? T.Theme.color3 : T.Theme.color1
        anchors { top: parent.top; right: parent.right; topMargin: -3; rightMargin: -3 }

        Behavior on width  { NumberAnimation { duration: T.Theme.animFast } }
        Behavior on radius { NumberAnimation { duration: T.Theme.animSlow } }
        Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text:  updateInfo.count > 99 ? "99+" : updateInfo.count
            color: T.Theme.bg
            font { family: T.Theme.fontFamily; pixelSize: 8; weight: Font.Bold }
        }
    }

    Rectangle {
        visible: updateInfo.checking
        width: 6; height: 6; radius: 3
        color: T.Theme.color9
        anchors { bottom: parent.bottom; left: parent.left; bottomMargin: -1; leftMargin: -1 }

        SequentialAnimation on opacity {
            running: updateInfo.checking
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: 500 }
            NumberAnimation { to: 1.00; duration: 500 }
        }
    }

    MouseArea {
        id: btn
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root._panel) root._panel.startUpdate(updateInfo.count)
        }
    }
}