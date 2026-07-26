import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theming" as T
import "../../config"

// Appearance — wallpaper + color schemes + fonts. Everything here re-themes the
// whole shell through the theming singleton (which reads Config): choosing a
// wallpaper regenerates the pywal palette; a custom scheme or a font is applied
// live via Config → Theme bindings.
Item {
    id: root

    // ── Wallpaper data ────────────────────────────────────────────────────────
    readonly property string dir: Quickshell.env("HOME") + "/wallpapers/walls"
    property var wallpapers: []
    property string currentName: ""
    property string applying: ""

    Component.onCompleted: { listProc.running = true; curProc.running = true; ed.resetFromTheme() }

    Process {
        id: listProc
        command: ["bash", "-c",
            "find '" + root.dir + "' -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
          + "-o -iname '*.gif' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector { onStreamFinished: root.wallpapers = text.trim().length ? text.trim().split("\n") : [] }
    }
    Process { id: curProc; command: ["cat", Quickshell.env("HOME") + "/.cache/current_wallpaper_name"]
        stdout: StdioCollector { onStreamFinished: root.currentName = text.trim() } }
    Process { id: applyProc; onExited: { root.applying = ""; curProc.running = false; curProc.running = true } }
    function applyWallpaper(path) {
        if (root.applying.length) return
        root.applying = path
        applyProc.command = ["bash", Quickshell.env("HOME") + "/.config/quicktest/scripts/apply-wallpaper.sh", path]
        applyProc.running = true
    }
    function baseName(p) { return p.split("/").pop() }

    // ── Fonts (curated; family strings are the real installed families) ──────────
    readonly property var sansFonts: [
        { n: "Inter", f: "Inter" }, { n: "Roboto", f: "Roboto" }, { n: "Open Sans", f: "Open Sans" },
        { n: "Lato", f: "Lato" }, { n: "Montserrat", f: "Montserrat Thin" }, { n: "Poppins", f: "Poppins" },
        { n: "Nunito", f: "Nunito ExtraLight" }, { n: "Raleway", f: "Raleway Thin" }, { n: "Work Sans", f: "Work Sans" },
        { n: "Ubuntu", f: "Ubuntu" }, { n: "Fira Sans", f: "Fira Sans" }, { n: "Source Sans 3", f: "Source Sans 3 ExtraLight" },
        { n: "Manrope", f: "Manrope ExtraLight" }, { n: "DM Sans", f: "DM Sans 9pt" }, { n: "Rubik", f: "Rubik Light" },
        { n: "Mulish", f: "Mulish ExtraLight" }, { n: "Karla", f: "Karla" }, { n: "Noto Sans", f: "Noto Sans" },
        { n: "PT Sans", f: "PT Sans" }, { n: "Quicksand", f: "Quicksand Light" }
    ]
    readonly property var monoFonts: [
        { n: "JetBrains Mono", f: "JetBrains Mono" }, { n: "Fira Code", f: "Fira Code Light" }, { n: "IBM Plex Mono", f: "IBM Plex Mono" },
        { n: "Roboto Mono", f: "Roboto Mono" }, { n: "Source Code Pro", f: "Source Code Pro ExtraLight" },
        { n: "Space Mono", f: "Space Mono" }, { n: "Ubuntu Mono", f: "Ubuntu Mono" }
    ]

    // color → "#rrggbb"
    function toHex(c) {
        function h(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function validHex(s) { return /^#[0-9a-fA-F]{6}$/.test(s) }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 22

            Text {
                text: "Appearance"
                color: T.Theme.ink
                font { family: T.Theme.headingFamily; pixelSize: T.Theme.fontSize + 10; bold: true }
            }

            // ══ Wallpaper ═════════════════════════════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                SectionLabel { text: "Wallpaper" }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.applying.length > 0
                    text: "Applying & recoloring…"
                    color: T.Theme.accent
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 }
                }
            }
            Text {
                visible: root.wallpapers.length === 0
                text: "No images found in " + root.dir
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; italic: true }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: root.wallpapers
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isCurrent: root.baseName(modelData) === root.currentName
                        width: 156; height: 100
                        radius: T.Theme.moduleRadius
                        color: T.Theme.surfaceAlt
                        clip: true
                        border.width: isCurrent ? 2 : 0
                        border.color: T.Theme.accent
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            source: "file://" + modelData
                            sourceSize.width: 320
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 20; color: T.Theme.background
                            Text {
                                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: (parent.parent.isCurrent ? "● " : "") + root.baseName(modelData)
                                color: parent.parent.isCurrent ? T.Theme.accent : T.Theme.ink
                                elide: Text.ElideRight
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 5 }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent; visible: root.applying === modelData
                            color: T.Theme.background; opacity: 0.75
                            Text { anchors.centerIn: parent; text: "…"; color: T.Theme.accent; font { family: T.Theme.fontFamily; pixelSize: 26; bold: true } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.applyWallpaper(modelData) }
                    }
                }
            }

            // ══ Colors ════════════════════════════════════════════════════════════
            SectionLabel { text: "Color scheme" }
            Text {
                Layout.fillWidth: true
                text: "Use the palette from your wallpaper, or a custom scheme you define below."
                wrapMode: Text.WordWrap; color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            // Source chips: wallpaper + each saved scheme.
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SchemeChip {
                    label: "From wallpaper"
                    active: Config.colorMode !== "custom"
                    onPick: Config.useWallpaperColors()
                }
                Repeater {
                    model: Config.schemeNames()
                    delegate: SchemeChip {
                        required property var modelData
                        label: modelData
                        active: Config.colorMode === "custom" && Config.activeScheme === modelData
                        deletable: true
                        onPick: Config.useScheme(modelData)
                        onRemove: Config.deleteScheme(modelData)
                    }
                }
            }

            // Custom scheme editor.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: edCol.implicitHeight + 28
                radius: T.Theme.radiusMedium
                color: T.Theme.surfaceAlt
                border.width: 1; border.color: T.Theme.border
                ColumnLayout {
                    id: edCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Custom scheme"; Layout.fillWidth: true; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true } }
                        SmallBtn { text: "Use current colors"; onTap: ed.resetFromTheme() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColorField { id: cBg;  label: "Background"; hex: ed.bg;  onEdited: function(v){ ed.bg = v } }
                        ColorField { id: cFg;  label: "Foreground"; hex: ed.fg;  onEdited: function(v){ ed.fg = v } }
                        ColorField { id: cAc;  label: "Accent";     hex: ed.accent;    onEdited: function(v){ ed.accent = v } }
                        ColorField { id: cAc2; label: "Accent 2";   hex: ed.accentAlt; onEdited: function(v){ ed.accentAlt = v } }
                    }
                    // Live preview swatch.
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 40; radius: T.Theme.radiusSmall
                        color: root.validHex(ed.bg) ? ed.bg : T.Theme.background
                        border.width: 1; border.color: T.Theme.border
                        RowLayout {
                            anchors.centerIn: parent; spacing: 14
                            Text { text: "Preview"; color: root.validHex(ed.fg) ? ed.fg : T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true } }
                            Rectangle { width: 20; height: 20; radius: T.Theme.radiusFull; color: root.validHex(ed.accent) ? ed.accent : T.Theme.accent }
                            Rectangle { width: 20; height: 20; radius: T.Theme.radiusFull; color: root.validHex(ed.accentAlt) ? ed.accentAlt : T.Theme.accentAlt }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 38; radius: T.Theme.radiusSmall
                            color: T.Theme.surface; border.width: 1; border.color: nameIn.activeFocus ? T.Theme.accent : T.Theme.border
                            TextInput {
                                id: nameIn
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: T.Theme.ink; selectionColor: T.Theme.accent
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize }
                                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !nameIn.text; text: "Scheme name"; color: T.Theme.inkDim; font: nameIn.font }
                            }
                        }
                        SmallBtn {
                            text: "Save & apply"
                            accent: true
                            enabled: nameIn.text.trim().length > 0 && root.validHex(ed.bg) && root.validHex(ed.fg) && root.validHex(ed.accent) && root.validHex(ed.accentAlt)
                            onTap: {
                                var nm = nameIn.text.trim()
                                // saveScheme also switches to it (one batched write).
                                Config.saveScheme(nm, { bg: ed.bg, fg: ed.fg, accent: ed.accent, accentAlt: ed.accentAlt })
                            }
                        }
                    }
                }
            }

            // ══ Fonts ═════════════════════════════════════════════════════════════
            SectionLabel { text: "Fonts" }
            Text {
                Layout.fillWidth: true
                text: "Pick the interface font. Icons keep rendering via the bundled Nerd Font."
                wrapMode: Text.WordWrap; color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }

            Text { text: "Body font"; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true } }
            FontFlow { pickHeading: false; current: Config.fontBody }

            Text { text: "Heading font"; Layout.topMargin: 4; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true } }
            FontFlow { pickHeading: true; current: Config.fontHeading; followLabel: "Follow body" }

            Item { Layout.preferredHeight: 6 }
        }
    }

    // ── Editor state ──────────────────────────────────────────────────────────
    QtObject {
        id: ed
        property string bg: "#1a1b26"
        property string fg: "#a9b1d6"
        property string accent: "#7aa2f7"
        property string accentAlt: "#f7768e"
        function resetFromTheme() {
            ed.bg = root.toHex(T.Theme.background); ed.fg = root.toHex(T.Theme.ink)
            ed.accent = root.toHex(T.Theme.accent); ed.accentAlt = root.toHex(T.Theme.accentAlt)
        }
    }

    // ── Inline components ───────────────────────────────────────────────────────
    component SectionLabel: Text {
        Layout.fillWidth: true
        color: T.Theme.accent
        font { family: T.Theme.headingFamily; pixelSize: T.Theme.fontSize + 2; bold: true }
    }

    component SmallBtn: Rectangle {
        id: btn
        property string text: ""
        property bool accent: false
        signal tap()
        implicitHeight: 38; implicitWidth: sbLbl.implicitWidth + 30
        radius: T.Theme.radiusSmall
        opacity: btn.enabled ? 1 : 0.4
        color: sbma.containsMouse && btn.enabled ? T.Theme.surfaceHover : (btn.accent ? T.Theme.surfaceActive : T.Theme.surface)
        border.width: 1; border.color: btn.accent ? T.Theme.accent : T.Theme.border
        Text { id: sbLbl; anchors.centerIn: parent; text: btn.text; color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: btn.accent } }
        MouseArea { id: sbma; anchors.fill: parent; hoverEnabled: true; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor; onClicked: btn.tap() }
    }

    // A scheme source chip (wallpaper / a saved scheme), optionally deletable.
    component SchemeChip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        property bool deletable: false
        signal pick()
        signal remove()
        implicitHeight: 40; implicitWidth: chipRow.implicitWidth + 26
        radius: T.Theme.radiusFull
        color: chip.active ? T.Theme.surfaceActive : (chma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
        border.width: chip.active ? 1 : 0; border.color: T.Theme.accent
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        MouseArea { id: chma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.pick() }
        RowLayout {
            id: chipRow
            anchors.centerIn: parent; spacing: 8
            Text { text: chip.label; color: chip.active ? T.Theme.ink : T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: chip.active } }
            Rectangle {
                visible: chip.deletable
                implicitWidth: 20; implicitHeight: 20; radius: T.Theme.radiusFull
                color: delMa.containsMouse ? T.Theme.surfaceHover : "transparent"
                Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0156); color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2 } }
                MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.remove() }
            }
        }
    }

    // A single color slot: swatch + hex TextInput.
    component ColorField: ColumnLayout {
        id: field
        property string label: ""
        property string hex: "#000000"
        signal edited(string v)
        Layout.fillWidth: true
        spacing: 5
        Text { text: field.label; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 } }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: T.Theme.radiusSmall
                color: root.validHex(field.hex) ? field.hex : "#000000"
                border.width: 1; border.color: T.Theme.border
            }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 30; radius: T.Theme.radiusSmall
                color: T.Theme.surface; border.width: 1; border.color: hexIn.activeFocus ? T.Theme.accent : (root.validHex(hexIn.text) ? T.Theme.border : T.Theme.accentAlt)
                TextInput {
                    id: hexIn
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    text: field.hex
                    color: T.Theme.ink; selectionColor: T.Theme.accent
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1 }
                    onTextEdited: field.edited(text.trim())
                    // Re-sync when the value changes externally (e.g. "Use current
                    // colors"), since typing breaks the text binding.
                    Connections { target: field; function onHexChanged() { if (hexIn.text !== field.hex) hexIn.text = field.hex } }
                }
            }
        }
    }

    // A scrollable set of font chips, each rendered in its own typeface. Selects
    // Config.fontBody or Config.fontHeading. `followLabel` (heading only) offers a
    // "follow body" option; the body picker offers "Default".
    component FontFlow: Flow {
        property bool pickHeading: false
        property string current: ""
        property string followLabel: ""
        Layout.fillWidth: true
        spacing: 8
        // The special first option ("" value): Default / Follow body.
        FontChip { display: pickHeading ? (followLabel || "Follow body") : "Default"; family: T.Theme.defaultFont; value: ""
                   selected: current === ""
                   onPick: { if (pickHeading) Config.fontHeading = ""; else Config.fontBody = "" } }
        Repeater {
            model: root.sansFonts.concat(root.monoFonts)
            delegate: FontChip {
                required property var modelData
                display: modelData.n; family: modelData.f; value: modelData.f
                selected: current === modelData.f
                onPick: { if (pickHeading) Config.fontHeading = modelData.f; else Config.fontBody = modelData.f }
            }
        }
    }
    component FontChip: Rectangle {
        id: chip
        property string display: ""
        property string family: ""
        property string value: ""
        property bool selected: false
        signal pick()
        implicitHeight: 40; implicitWidth: fcLbl.implicitWidth + 26
        radius: T.Theme.radiusMedium
        color: chip.selected ? T.Theme.surfaceActive : (fcma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
        border.width: chip.selected ? 1 : 0; border.color: T.Theme.accent
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        Text {
            id: fcLbl; anchors.centerIn: parent
            text: chip.display
            color: chip.selected ? T.Theme.ink : T.Theme.inkDim
            font { family: chip.family; pixelSize: T.Theme.fontSize + 1; bold: chip.selected }
        }
        MouseArea { id: fcma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.pick() }
    }
}
