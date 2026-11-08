import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T

// Keyboard — xkb layout + variant and key-repeat, applied live through Hyprland
// (hyprctl keyword input:*). Changes take effect immediately; note they persist
// only for this session unless also written into the Hyprland config.
Item {
    id: root

    property string layout: ""          // primary layout (first of kb_layout)
    property string variant: ""
    property int repeatRate: 25
    property int repeatDelay: 600
    property var layouts: []
    property var variants: []
    property string search: ""

    readonly property var filteredLayouts: {
        var s = root.search.toLowerCase()
        return s.length ? root.layouts.filter(function(l){ return l.toLowerCase().indexOf(s) !== -1 }) : root.layouts
    }

    Component.onCompleted: { stateProc.running = true; layoutsProc.running = true }

    Process {
        id: stateProc
        command: ["bash", "-c",
            "echo LAYOUT=$(hyprctl getoption input:kb_layout -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"str\"])'); "
          + "echo VARIANT=$(hyprctl getoption input:kb_variant -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"str\"])'); "
          + "echo RATE=$(hyprctl getoption input:repeat_rate -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"int\"])'); "
          + "echo DELAY=$(hyprctl getoption input:repeat_delay -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"int\"])')"]
        stdout: StdioCollector {
            onStreamFinished: {
                text.split("\n").forEach(function(l){
                    if (l.indexOf("LAYOUT=") === 0) root.layout = l.substring(7).split(",")[0].trim()
                    else if (l.indexOf("VARIANT=") === 0) root.variant = l.substring(8).split(",")[0].trim()
                    else if (l.indexOf("RATE=") === 0) root.repeatRate = parseInt(l.substring(5)) || 25
                    else if (l.indexOf("DELAY=") === 0) root.repeatDelay = parseInt(l.substring(6)) || 600
                })
                if (root.layout) { variantsProc.command = ["localectl", "list-x11-keymap-variants", root.layout]; variantsProc.running = true }
            }
        }
    }
    Process {
        id: layoutsProc
        command: ["localectl", "list-x11-keymap-layouts"]
        stdout: StdioCollector { onStreamFinished: root.layouts = text.trim().split("\n") }
    }
    Process {
        id: variantsProc
        stdout: StdioCollector { onStreamFinished: root.variants = text.trim().length ? text.trim().split("\n") : [] }
    }

    Process { id: applyProc }
    function applyLayout(l) {
        root.layout = l; root.variant = ""
        applyProc.command = ["bash", "-c", "hyprctl keyword input:kb_variant ''; hyprctl keyword input:kb_layout '" + l + "'"]
        applyProc.running = false; applyProc.running = true
        variantsProc.command = ["localectl", "list-x11-keymap-variants", l]; variantsProc.running = false; variantsProc.running = true
    }
    function applyVariant(v) {
        root.variant = v
        applyProc.command = ["hyprctl", "keyword", "input:kb_variant", v]
        applyProc.running = false; applyProc.running = true
    }
    function applyRepeat() {
        applyProc.command = ["bash", "-c", "hyprctl keyword input:repeat_rate " + root.repeatRate + "; hyprctl keyword input:repeat_delay " + root.repeatDelay]
        applyProc.running = false; applyProc.running = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Text {
            text: "Keyboard"
            color: T.Theme.ink
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
        }

        // Current + repeat controls.
        Rectangle {
            Layout.fillWidth: true
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            implicitHeight: box.implicitHeight + 24
            ColumnLayout {
                id: box
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: String.fromCodePoint(0xF030C); color: T.Theme.accent; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 4 } }
                    Text {
                        Layout.fillWidth: true
                        text: "Active: " + (root.layout || "?") + (root.variant ? " (" + root.variant + ")" : "")
                        color: T.Theme.ink
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                    }
                }
                Slider { label: "Repeat rate"; from: 10; to: 100; value: root.repeatRate; suffix: "/s"
                         onMoved: function(v){ root.repeatRate = v; root.applyRepeat() } }
                Slider { label: "Repeat delay"; from: 150; to: 1000; value: root.repeatDelay; suffix: "ms"
                         onMoved: function(v){ root.repeatDelay = v; root.applyRepeat() } }
            }
        }

        // Variants for current layout.
        RowLayout {
            Layout.fillWidth: true
            visible: root.variants.length > 0
            spacing: 8
            Text { text: "Variant"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 } }
            ComboChip { label: "default"; sel: root.variant === ""; onClicked: root.applyVariant("") }
            // (first few variants as quick chips; full list is long)
            Repeater {
                model: root.variants.slice(0, 4)
                delegate: ComboChip {
                    required property var modelData
                    label: modelData; sel: root.variant === modelData
                    onClicked: root.applyVariant(modelData)
                }
            }
        }

        // Layout search + list.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            border.width: searchInput.activeFocus ? 1 : 0
            border.color: T.Theme.accent
            TextInput {
                id: searchInput
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: T.Theme.ink; selectionColor: T.Theme.accent
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 }
                onTextChanged: root.search = text
                Text { anchors.fill: parent; anchors.leftMargin: 0; verticalAlignment: Text.AlignVCenter; visible: !searchInput.text; text: "Search layouts…"; color: T.Theme.inkDim; font: searchInput.font }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: root.filteredLayouts
            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: 36
                radius: T.Theme.moduleRadius
                readonly property bool sel: modelData === root.layout
                color: sel ? T.Theme.surfaceActive : (kma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                Text {
                    anchors.fill: parent; anchors.leftMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: sel }
                }
                MouseArea { id: kma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !sel; onClicked: root.applyLayout(modelData) }
            }
        }
    }

    // Chip button.
    component ComboChip: Rectangle {
        property string label: ""
        property bool sel: false
        signal clicked()
        implicitWidth: cl.implicitWidth + 20; implicitHeight: 26
        radius: T.Theme.moduleRadius
        color: sel ? T.Theme.surfaceActive : (cma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
        Text { id: cl; anchors.centerIn: parent; text: parent.label; color: parent.sel ? T.Theme.accent : T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3; bold: parent.sel } }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // Simple labelled slider.
    component Slider: RowLayout {
        property string label: ""
        property real from: 0
        property real to: 100
        property real value: 0
        property string suffix: ""
        signal moved(real v)
        Layout.fillWidth: true
        spacing: 10
        Text { Layout.preferredWidth: 90; text: label; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 } }
        Rectangle {
            id: sbar
            Layout.fillWidth: true
            implicitHeight: 6; radius: T.Theme.radiusFull
            color: T.Theme.surfaceHover
            Rectangle {
                height: parent.height; radius: T.Theme.radiusFull
                width: parent.width * Math.max(0, Math.min(1, (value - from) / (to - from)))
                color: T.Theme.accent
            }
            MouseArea {
                anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
                cursorShape: Qt.PointingHandCursor
                function apply(mx) { moved(Math.round(from + Math.max(0, Math.min(1, mx / width)) * (to - from))) }
                onPressed: function(m){ apply(m.x) }
                onPositionChanged: function(m){ if (pressed) apply(m.x) }
            }
        }
        Text { Layout.preferredWidth: 54; horizontalAlignment: Text.AlignRight; text: Math.round(value) + suffix; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 } }
    }
}
