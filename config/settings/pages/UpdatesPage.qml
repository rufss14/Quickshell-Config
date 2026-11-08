import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../theming" as T

// Updates — a "Windows Update"-style page for Arch. Lists official (checkupdates,
// no root needed) and AUR (yay/paru -Qua) updates, and applies official ones with
// `pkexec pacman -Syu` so privilege escalation goes through polkit — no stored
// password, no insecure sudo. AUR updates build from source, so those are handed
// to the detected helper in a terminal. Failures are reported verbatim.
Item {
    id: root

    property var official: []          // [{ name, from, to }]
    property var aur: []
    property string helper: ""         // "yay" | "paru" | ""
    property string term: "kitty"
    property bool checking: false
    property bool applying: false
    property string log: ""
    property string status: ""

    readonly property int total: official.length + aur.length

    // Detect the AUR helper first; check() needs it, so run the first check only
    // once the helper name is known (otherwise the AUR query is skipped).
    Component.onCompleted: helperProc.running = true

    Process {
        id: helperProc
        command: ["bash", "-c", "command -v yay >/dev/null && echo yay || (command -v paru >/dev/null && echo paru || echo)"]
        stdout: StdioCollector { onStreamFinished: { root.helper = text.trim(); root.check() } }
    }

    function check() {
        root.checking = true; root.status = ""
        offProc.running = false; offProc.running = true
        if (root.helper) { aurProc.command = [root.helper, "-Qua"]; aurProc.running = false; aurProc.running = true }
    }
    function parseUpdates(txt) {
        var out = []
        txt.split("\n").forEach(function(line){
            var p = line.trim().split(/\s+/)
            if (p.length >= 4 && p[2] === "->") out.push({ name: p[0], from: p[1], to: p[3] })
        })
        return out
    }
    Process {
        id: offProc
        command: ["checkupdates"]
        // checkupdates exits 2 when there are no updates — that's not an error.
        stdout: StdioCollector { onStreamFinished: { root.official = root.parseUpdates(text); root.checking = false } }
    }
    Process {
        id: aurProc
        stdout: StdioCollector { onStreamFinished: root.aur = root.parseUpdates(text) }
    }

    // Apply official updates through polkit.
    Process {
        id: applyProc
        command: ["pkexec", "pacman", "-Syu", "--noconfirm"]
        stdout: SplitParser { onRead: function(l){ root.log = (root.log + l + "\n").slice(-6000) } }
        stderr: SplitParser { onRead: function(l){ root.log = (root.log + l + "\n").slice(-6000) } }
        onExited: function(code) {
            root.applying = false
            if (code === 0)        root.status = "✔ Official packages updated."
            else if (code === 126) root.status = "✖ Authentication cancelled or no polkit agent available."
            else                   root.status = "✖ Update failed (exit " + code + "). See log."
            root.check()
        }
    }
    function applyOfficial() {
        if (root.applying) return
        root.applying = true; root.log = ""; root.status = "Requesting authentication…"
        applyProc.running = false; applyProc.running = true
    }

    // Hand the full system+AUR upgrade to the helper in a terminal (it does its
    // own sudo/build). Safe: no password handling here.
    Process { id: termProc }
    function updateAllInTerminal() {
        if (!root.helper) return
        termProc.command = [root.term, "-e", "bash", "-c", root.helper + " -Syu; echo; read -p 'Done. Press Enter to close…'"]
        termProc.running = false; termProc.running = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Updates"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }
            Item { Layout.fillWidth: true }
            Btn { label: "Check"; glyph: 0xF0450; busy: root.checking; onClicked: root.check() }
        }

        // Summary card.
        Rectangle {
            Layout.fillWidth: true
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            implicitHeight: 74
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16; anchors.rightMargin: 16
                spacing: 14
                Text {
                    text: String.fromCodePoint(root.total > 0 ? 0xF06B0 : 0xF0163)   // update / cloud-check
                    color: root.total > 0 ? T.Theme.accent : T.Theme.accentAlt
                    font { family: T.Theme.fontFamily; pixelSize: 34 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: root.checking ? "Checking…"
                            : root.total === 0 ? "Your system is up to date"
                            : root.total + " update" + (root.total === 1 ? "" : "s") + " available"
                        color: T.Theme.ink
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 2; bold: true }
                    }
                    Text {
                        text: root.official.length + " official   ·   " + root.aur.length + " AUR"
                              + (root.helper ? "   ·   helper: " + root.helper : "   ·   no AUR helper")
                        color: T.Theme.inkDim
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
                    }
                }
                Btn { label: "Update official"; glyph: 0xF01DA; accent: true
                      enabled: root.official.length > 0 && !root.applying
                      busy: root.applying
                      onClicked: root.applyOfficial() }
                Btn { label: "Update all…"; glyph: 0xF018D
                      enabled: root.total > 0 && root.helper.length > 0
                      onClicked: root.updateAllInTerminal() }
            }
        }

        Text {
            visible: root.status.length > 0
            Layout.fillWidth: true
            text: root.status
            color: root.status.indexOf("✖") === 0 ? T.Theme.accentAlt : T.Theme.accent
            wrapMode: Text.WordWrap
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
        }

        // Package list (or live log while applying).
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.applying
            clip: true
            spacing: 3
            model: root.official.concat(root.aur)
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool isAur: index >= root.official.length
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: 40
                radius: T.Theme.moduleRadius
                color: T.Theme.surfaceAlt
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 18; radius: T.Theme.radiusSmall
                        color: isAur ? T.Theme.mix(T.Theme.bg, T.Theme.accentAlt, 0.3) : T.Theme.mix(T.Theme.bg, T.Theme.accent, 0.3)
                        Text { anchors.centerIn: parent; text: isAur ? "AUR" : "off"; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 5; bold: true } }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: T.Theme.ink
                        elide: Text.ElideRight
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
                    }
                    Text {
                        text: modelData.from + "  →  " + modelData.to
                        color: T.Theme.inkDim
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
                    }
                }
            }
        }

        // Live log while applying.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.applying || (root.log.length > 0 && root.status.indexOf("✖") === 0)
            radius: T.Theme.moduleRadius
            color: T.Theme.background
            border.width: 1; border.color: T.Theme.border
            Flickable {
                id: logFlick
                anchors.fill: parent; anchors.margins: 10
                contentHeight: logText.implicitHeight
                clip: true
                Text {
                    id: logText
                    width: parent.width
                    text: root.log
                    color: T.Theme.inkDim
                    wrapMode: Text.Wrap
                    font { family: "monospace"; pixelSize: T.Theme.fontSize - 3 }
                    onTextChanged: logFlick.contentY = Math.max(0, logText.implicitHeight - logFlick.height)
                }
            }
        }
    }

    component Btn: Rectangle {
        property string label: ""
        property int glyph: 0
        property bool accent: false
        property bool busy: false
        signal clicked()
        implicitWidth: brow.implicitWidth + 24; implicitHeight: 34
        radius: T.Theme.moduleRadius
        opacity: enabled ? (busy ? 0.6 : 1) : 0.4
        color: bma.containsMouse && enabled ? T.Theme.surfaceHover : (accent ? T.Theme.surfaceActive : T.Theme.surfaceAlt)
        RowLayout {
            id: brow
            anchors.centerIn: parent
            spacing: 7
            Text { visible: glyph > 0; text: glyph > 0 ? String.fromCodePoint(glyph) : ""; color: accent ? T.Theme.accent : T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 1 } }
            Text { text: label; color: accent ? T.Theme.accent : T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; bold: true } }
        }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; enabled: parent.enabled && !parent.busy; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }
}
