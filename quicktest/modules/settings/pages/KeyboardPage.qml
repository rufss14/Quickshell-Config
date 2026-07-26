pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services"

// ── KeyboardPage ──────────────────────────────────────────────────────────────
// The configured xkb layouts and key repeat, applied live through Hyprland.
//
// ── Layouts are a list, not a choice ──────────────────────────────────────────
// kb_layout reads "us,pt" on this machine, and the bar's keyboard pill cycles
// between them. The obvious settings page is a long list of every layout localectl
// knows, where clicking one makes it THE layout — which would quietly delete
// Portuguese the first time you clicked "us" to confirm what you already had.
//
// So the page has two halves: what you have configured (removable, reorderable by
// removing and re-adding), and the catalogue you add from. The pill's cycling
// keeps working because the list stays a list.
//
// All the state lives in the Keyboard service. This page is a view — it has to be,
// because SettingsCard's Loader tears it down whenever you look at another page.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string search: ""

    // The catalogue is page-local: nothing else in the shell wants a list of every
    // xkb layout in existence, and it's ~250 entries that would otherwise sit in a
    // singleton for the life of the process.
    //
    // Read from base.lst rather than `localectl list-x11-keymap-layouts`: same
    // authority (localectl reads this file), but localectl prints only the CODES, and
    // a list of "af / al / am" is only usable by someone who already knows the answer.
    // The lst carries the names beside them.
    property var catalogue: []              // [{ code, name }], sorted by name
    property var nameOf: ({})               // code → name, for the chips

    readonly property var filtered: {
        const s = root.search.trim().toLowerCase()
        const pool = root.catalogue.filter(l => Keyboard.layouts.indexOf(l.code) === -1)
        return s === "" ? pool
             : pool.filter(l => l.code.toLowerCase().includes(s)
                             || l.name.toLowerCase().includes(s))
    }

    Process {
        id: catalogueQuery
        running: true
        command: ["sed", "-n", "/^! layout$/,/^! variant$/p",
                  "/usr/share/X11/xkb/rules/base.lst"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [], names = ({})
                for (const line of text.split("\n")) {
                    if (line.startsWith("!") || line.trim() === "") continue
                    const t = line.trim()
                    const sp = t.search(/\s/)
                    if (sp <= 0) continue
                    const code = t.slice(0, sp), name = t.slice(sp).trim()
                    rows.push({ code: code, name: name })
                    names[code] = name
                }
                // By NAME, not code: you look for "Portuguese", not for "pt".
                rows.sort((a, b) => a.name.localeCompare(b.name))
                root.catalogue = rows
                root.nameOf = names
            }
        }
    }

    // ── The physical keyboard, from Hyprland ──────────────────────────────────
    // `hyprctl -j devices` lists every input device that carries a keymap — dongles,
    // headset buttons, the power button — so the card shows the one marked `main` and
    // just counts the rest. Listing eight pseudo-keyboards answers nothing.
    property var mainKeyboard: null
    property int inputDeviceCount: 0

    Process {
        id: devicesQuery
        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || []
                    root.inputDeviceCount = kbs.length
                    root.mainKeyboard = kbs.find(k => k.main) ?? kbs[0] ?? null
                } catch (e) {
                    root.mainKeyboard = null
                }
            }
        }
    }

    // "razer-razer-huntsman-mini" → "Razer Huntsman Mini". Consecutive duplicate words
    // collapsed because vendor prefixes double up in evdev names.
    function prettyName(n) {
        const out = []
        for (const w of String(n).split(/[-_]+/).filter(w => w !== ""))
            if (out.length === 0 || out[out.length - 1].toLowerCase() !== w.toLowerCase())
                out.push(w[0].toUpperCase() + w.slice(1))
        return out.join(" ")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     "󰌌"
            title:     "Keyboard"
            titleTail: Keyboard.layout
            subtitle:  "Layouts and key repeat — this session only"
        }

        Divider {}

        // ── Two columns ───────────────────────────────────────────────────────
        // Controls and explanation on the left, the ~250-entry layout catalogue on the
        // right. Stacked, the catalogue would push the repeat sliders off the top of a
        // page that's wide enough to hold both side by side twice over.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingXl

        ColumnLayout {
            Layout.preferredWidth: 420
            Layout.minimumWidth:   420
            Layout.maximumWidth:   420
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

        StyledText { text: "Key repeat"; variant: "label"; emphasis: "muted" }

        // ══ Repeat ════════════════════════════════════════════════════════════
        Surface {
            Layout.fillWidth: true
            elevation: Tokens.elevationNested
            implicitHeight: repeatBox.implicitHeight + Tokens.spacingLg * 2

            ColumnLayout {
                id: repeatBox
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                RepeatSlider {
                    label:  "Repeat rate"
                    suffix: "/s"
                    from:   10
                    to:     100
                    value:  Keyboard.repeatRate
                    onCommit: function(v) { Keyboard.setRepeat(v, Keyboard.repeatDelay) }
                }
                RepeatSlider {
                    label:  "Repeat delay"
                    suffix: "ms"
                    from:   150
                    to:     1000
                    value:  Keyboard.repeatDelay
                    onCommit: function(v) { Keyboard.setRepeat(Keyboard.repeatRate, v) }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: "Rate is how many characters a second a held key produces; delay is how long you hold it before that starts."
            variant:  "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }

        // ── Feel it, don't imagine it ─────────────────────────────────────────
        // The sliders describe the repeat in numbers; this box is the actual thing.
        // Hold a key and what comes out IS the rate and delay set above — no preview
        // code, just a text field, because typing is the real test.
        Surface {
            Layout.fillWidth: true
            implicitHeight: 32
            elevation: Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            focused: tryInput.activeFocus

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingSm

                TextInput {
                    id: tryInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.fg
                    selectionColor: Colors.alpha(Colors.focus, 0.28)
                    selectedTextColor: Colors.fg
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontBody
                    Keys.onEscapePressed: tryInput.focus = false

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tryInput.text === ""
                        text: "Hold a key here to feel the repeat…"
                        emphasis: "dim"
                    }
                }

                StyledText {
                    visible: tryInput.text !== ""
                    text: "󰅖"
                    variant: "caption"
                    color: clearHover.hovered ? Colors.danger : Colors.fgDim
                    HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: tryInput.text = "" }
                }
            }
        }

        // ══ Configured ════════════════════════════════════════════════════════
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            text: "Your layouts"
            variant: "label"
            emphasis: "muted"
        }

        StyledText {
            Layout.fillWidth: true
            text: "The bar's keyboard pill cycles these in order. Drag order isn't editable here — remove one and add it back to move it to the end."
            variant:  "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            Repeater {
                model: Keyboard.layouts

                Rectangle {
                    id: chip
                    required property string modelData

                    // The last layout can't be removed — a keyboard with no layout
                    // is not a state Hyprland will accept, and the service refuses
                    // it anyway. Better to grey the X than to have it do nothing.
                    readonly property bool removable: Keyboard.layouts.length > 1

                    implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
                    implicitHeight: 30
                    radius: Tokens.radiusSm

                    color:        Colors.alpha(Colors.focus, 0.16)
                    border.width: Tokens.borderWidth
                    border.color: Colors.alpha(Colors.focus, 0.40)

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingSm

                        StyledText {
                            text:  chip.modelData
                            color: Colors.focus
                            variant: "body"
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            visible: (root.nameOf[chip.modelData] || "") !== ""
                            text: root.nameOf[chip.modelData] || ""
                            variant: "caption"
                            emphasis: "dim"
                        }

                        StyledText {
                            visible: chip.removable
                            text:    "󰅖"
                            color:   removeHover.hovered ? Colors.danger : Colors.fgDim
                            variant: "caption"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { onTapped: Keyboard.removeLayout(chip.modelData) }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacingSm
            Layout.fillWidth: true
            text: "These are applied with hyprctl, which lasts for this Hyprland session only — they aren't written to hyprland.conf, so a restart brings back whatever your config says."
            variant:  "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }

        // ══ Hardware ══════════════════════════════════════════════════════════
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            visible: root.mainKeyboard !== null
            text: "Hardware"
            variant: "label"
            emphasis: "muted"
        }

        Surface {
            Layout.fillWidth: true
            visible: root.mainKeyboard !== null
            elevation: Tokens.elevationNested
            implicitHeight: kbBox.implicitHeight + Tokens.spacingLg * 2

            RowLayout {
                id: kbBox
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                StyledText { text: "󰌌"; variant: "body"; color: Colors.focus }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.mainKeyboard ? root.prettyName(root.mainKeyboard.name) : ""
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mainKeyboard
                            ? "Typing in " + (root.mainKeyboard.active_keymap || "?")
                              + (root.inputDeviceCount > 1
                                 ? "  ·  " + (root.inputDeviceCount - 1)
                                   + " other input devices follow the same layouts"
                                 : "")
                            : ""
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
        }

        // ══ Catalogue ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

        StyledText {
            text: "Add a layout — " + root.catalogue.length + " available"
            variant: "label"
            emphasis: "muted"
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: 32
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            focused:      searchInput.activeFocus

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingMd
                verticalAlignment: TextInput.AlignVCenter

                color: Colors.fg
                selectionColor: Colors.alpha(Colors.focus, 0.28)
                selectedTextColor: Colors.fg
                font.family:    Tokens.fontFamily
                font.pixelSize: Tokens.fontBody

                onTextChanged: root.search = text

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible:  searchInput.text === ""
                    text:     "Add a layout…"
                    emphasis: "dim"
                }
            }
        }

        // Two columns: ~250 entries in one column is a scroll marathon, and the rows
        // are short enough that half the width was empty anyway.
        GridView {
            id: catView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: Math.floor(catView.width / 2)
            cellHeight: 34
            model: root.filtered
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: layoutCell
                required property var modelData
                width:  catView.cellWidth
                height: catView.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin:  Tokens.spacingSm
                    anchors.bottomMargin: 2
                    radius: Tokens.radiusSm

                    color: rowHover.hovered ? Colors.alpha(Colors.fg, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin:  Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        StyledText {
                            Layout.fillWidth: true
                            text:    layoutCell.modelData.name
                            variant: "body"
                            elide:   Text.ElideRight
                        }
                        StyledText {
                            text:     layoutCell.modelData.code
                            variant:  "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                        StyledText {
                            visible: rowHover.hovered
                            text:    "󰐕"
                            color:   Colors.focus
                            variant: "body"
                        }
                    }

                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: Keyboard.addLayout(layoutCell.modelData.code) }
                }
            }
        }
        }
        }
    }

    // ── RepeatSlider ──────────────────────────────────────────────────────────
    // Same shape as BarPage's SliderRow. Deliberately NOT shared yet: two pages is
    // where you notice a pattern, three is where you extract it — and the third
    // will tell you which of these two shapes was the accident.
    component RepeatSlider: RowLayout {
        id: repeatSlider

        property string label:  ""
        property string suffix: ""
        property int from:  0
        property int to:    100
        property int value: 0

        signal commit(int v)

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        StyledText {
            Layout.preferredWidth: 100
            text:     repeatSlider.label
            variant:  "caption"
            emphasis: "dim"
        }

        ValueSlider {
            Layout.fillWidth: true
            maximum: 1.0
            value: (repeatSlider.value - repeatSlider.from)
                 / (repeatSlider.to - repeatSlider.from)

            onMoved: function(v) {
                repeatSlider.commit(Math.round(
                    repeatSlider.from + v * (repeatSlider.to - repeatSlider.from)))
            }
            onScrolled: function(d) {
                repeatSlider.commit(Math.max(repeatSlider.from,
                    Math.min(repeatSlider.to, repeatSlider.value + d)))
            }
        }

        StyledText {
            Layout.preferredWidth: 46
            horizontalAlignment: Text.AlignRight
            text:     repeatSlider.value + repeatSlider.suffix
            variant:  "caption"
            emphasis: "dim"
        }
    }
}
