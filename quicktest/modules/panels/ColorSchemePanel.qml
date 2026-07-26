pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/palette.js" as Palette

// ── ColorSchemePanel ──────────────────────────────────────────────────────────
// The palette editor.
//
// ── All logic lives in the ColorScheme service ────────────────────────────────
// This file was 1308 lines and owned everything: six Processes, a bash pipeline built by
// string concatenation, colour maths, and the UI. That pipeline was a SECOND COPY of the
// wallpaper one and had rotted — still `pkill zen`, still `pkill nautilus`, no GTK3, and
// `|| true` on every step so failures were invisible. It now lives in
// `scripts/reload-theme.sh`, shared with the wallpaper gallery, driven by `ColorScheme`.
// Colour maths moved to `services/palette.js`, where it can be tested with node.
//
// ── Anything you set by hand is held ──────────────────────────────────────────
// Simple derives a whole palette from four seeds; Advanced edits individual slots. Both
// write the same overrides file, so both survive wallpaper changes, and "Release all"
// undoes either. Held colours are always visible and always clearable — a colour that
// silently refuses to follow the wallpaper is a haunting.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // PanelHost now honours these (it used to hard-code 340 and silently clip). Wider AND
    // taller than the shared 535: this panel carries a picker, a readout and a preview
    // side by side, and squeezing all three into the narrow width is what made it feel
    // cramped. Kept modest — a popup that fills the screen has stopped being a popup.
    implicitWidth:  640
    implicitHeight: 420

    property string mode: "simple"          // "simple" | "advanced"

    // ── Simple mode: four seeds ───────────────────────────────────────────────
    property string seedBg: Palette.slotValue(Colors.data, "background")
    property string seedFg: Palette.slotValue(Colors.data, "foreground")
    property string seedA:  Palette.slotValue(Colors.data, "color1")
    property string seedB:  Palette.slotValue(Colors.data, "color4")
    property int    seedIndex: 0            // which seed the picker drives

    // Editing any seed means you're no longer using the loaded scheme verbatim.
    onSeedBgChanged: root.dropLoaded()
    onSeedFgChanged: root.dropLoaded()
    onSeedAChanged:  root.dropLoaded()
    onSeedBChanged:  root.dropLoaded()

    readonly property var seeds: [
        { key: "seedBg", label: "Background", value: root.seedBg },
        { key: "seedFg", label: "Text",       value: root.seedFg },
        { key: "seedA",  label: "Accent",     value: root.seedA  },
        { key: "seedB",  label: "Accent 2",   value: root.seedB  }
    ]

    // A scheme loaded from disk previews and applies EXACTLY what was saved. Deriving from
    // its four seeds instead would show — and then apply — a different palette from the one
    // whose name you clicked, because derive() rebuilds the other fourteen slots from
    // scratch. Any seed edit drops back to deriving, since at that point you are building
    // a new scheme rather than using the saved one.
    property var loadedPalette: null

    readonly property var derived: root.loadedPalette
        ?? Palette.derive(root.seedBg, root.seedFg, [root.seedA, root.seedB])

    // What Advanced will actually produce: the live palette with staged edits laid over it.
    readonly property var stagedPalette: {
        const out = ({ special: ({}), colors: ({}) })
        for (const slot of Palette.allSlots()) {
            const v = root.slotColor(slot)
            if (Palette.isSpecial(slot)) out.special[slot] = v
            else                         out.colors[slot]  = v
        }
        out.special["cursor"] = out.special["foreground"]
        return out
    }

    // The palette the Apply button will commit, in either mode. The preview shows this, so
    // what you see is what lands.
    readonly property var pending: root.mode === "simple" ? root.derived : root.stagedPalette

    function dropLoaded() { root.loadedPalette = null }

    // ── Advanced mode: staged per-slot edits ──────────────────────────────────
    // Staged rather than written on every drag: the picker emits continuously, and pinning
    // on each emission would write the overrides file dozens of times per gesture.
    property var    draft: ({})             // { slot: hex } — uncommitted
    property string selectedSlot: "background"

    readonly property int draftCount: Object.keys(root.draft).length

    function slotColor(slot) {
        if (root.draft[slot] !== undefined) return root.draft[slot]
        return Palette.slotValue(Colors.data, slot)
    }

    function stage(slot, hex) {
        const next = Object.assign({}, root.draft)
        next[slot] = hex.toLowerCase()
        root.draft = next                   // reassigned, not mutated — QML only re-evaluates
    }                                       // bindings on a property CHANGE

    function discardDraft() { root.draft = ({}) }

    // ── Applying ──────────────────────────────────────────────────────────────
    function applyCurrent() {
        if (ColorScheme.busy) return
        if (root.mode === "simple") {
            ColorScheme.applyPalette(root.pending, "Colour scheme")
        } else {
            // Pin everything staged as ONE write, then push. Pinning is what makes an edit
            // outlive the next wallpaper — which is the whole point of editing a slot by
            // hand rather than picking a different wallpaper.
            if (root.draftCount > 0) ColorScheme.pinMany(root.draft)
            root.discardDraft()
            ColorScheme.reload("Pinned colours")
        }
    }

    // ── Progress takes over the body ──────────────────────────────────────────
    readonly property bool showProgress: ColorScheme.busy || ColorScheme.runner.failed
    property bool showDetails: false
    onShowProgressChanged: if (!root.showProgress) root.showDetails = false

    Connections {
        target: ColorScheme.runner
        function onFailedChanged() { if (ColorScheme.runner.failed) root.showDetails = true }
    }

    // Loading a saved scheme fills the seeds so it can be adjusted rather than only applied.
    Connections {
        target: ColorScheme
        function onSchemeLoaded(name, p) {
            root.seedBg = Palette.slotValue(p, "background")
            root.seedFg = Palette.slotValue(p, "foreground")
            root.seedA  = Palette.slotValue(p, "color1")
            root.seedB  = Palette.slotValue(p, "color4")
            // AFTER the seeds, because assigning them fires dropLoaded().
            root.loadedPalette = p
            root.mode = "simple"
            schemeName.text = name
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (schemeName.activeFocus) schemeName.focus = false
            if (hexField.activeFocus)   hexField.focus = false
            mouse.accepted = false
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        // ── Header ────────────────────────────────────────────────────────────
        PanelHeader {
            icon:      Icons.asset("Palette")
            title:     "Colours"
            titleTail: root.mode === "simple" ? "Scheme" : "Slots"
            accent:    Colors.primary
            subtitle:  root.mode === "simple"
                     ? "Four colours, whole palette"
                     : root.draftCount > 0
                     ? root.draftCount + " unsaved change" + (root.draftCount !== 1 ? "s" : "")
                     : "Hold individual colours"

            // Releasing lives in the header as a plain button. It was a full-width banner
            // reading "18 colours held through wallpaper changes", which spent a whole row
            // of a 340px panel restating what the button already says.
            PanelButton {
                variant: "ghost"
                glyph:   "󰐃"
                label:   "Release all"
                visible: ColorScheme.overrideCount > 0
                enabled: !ColorScheme.busy
                onActivated: ColorScheme.releaseAll()
            }

            PanelButton {
                variant: "ghost"
                glyph:   "󰑐"
                enabled: !ColorScheme.busy
                onActivated: ColorScheme.regenerate()
            }

            // Segmented mode switch, same shape as the wallpaper gallery's view toggle.
            Rectangle {
                implicitWidth:  150
                implicitHeight: Tokens.pillHeight + Tokens.spacingSm
                radius: Tokens.radiusSm
                color:  Colors.surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: [{ m: "simple", t: "Simple" }, { m: "advanced", t: "Advanced" }]
                        delegate: Rectangle {
                            id: modeBtn
                            required property var modelData
                            Layout.fillWidth:  true
                            Layout.fillHeight: true
                            radius: Tokens.radiusXs
                            readonly property bool on: root.mode === modeBtn.modelData.m
                            color: modeBtn.on ? Colors.alpha(Colors.primary, 0.30) : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            StyledText {
                                anchors.centerIn: parent
                                text: modeBtn.modelData.t
                                variant: "caption"
                                emphasis: modeBtn.on ? "normal" : "dim"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.mode = modeBtn.modelData.m
                            }
                        }
                    }
                }
            }
        }

        // ══ Body ══════════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Editor ────────────────────────────────────────────────────────
            ColumnLayout {
                id: editorCol
                anchors.fill: parent
                spacing: Tokens.spacingSm

                opacity: root.showProgress ? 0.0 : 1.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                // ── Simple: four seeds ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.mode === "simple"
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: root.seeds
                        // Swatch and label on ONE line. As stacked full-width bars these
                        // were the heaviest thing on the panel, which put the most visual
                        // weight on the INPUT rather than on the palette that comes out of
                        // it. Now they read as four small controls.
                        delegate: Rectangle {
                            id: seed
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: Tokens.radiusXs
                            color: root.seedIndex === seed.index
                                 ? Colors.alpha(Colors.primary, 0.16) : "transparent"
                            border.width: 1
                            border.color: root.seedIndex === seed.index
                                        ? Colors.primary : Colors.outline
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin:  Tokens.spacingXs
                                anchors.rightMargin: Tokens.spacingXs
                                spacing: Tokens.spacingXs

                                Rectangle {
                                    Layout.preferredWidth:  14
                                    Layout.preferredHeight: 14
                                    radius: 3
                                    color: seed.modelData.value
                                    border.width: 1
                                    border.color: Colors.alpha(Colors.fg, 0.20)
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: seed.modelData.label
                                    variant: "caption"
                                    emphasis: root.seedIndex === seed.index ? "normal" : "dim"
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.seedIndex = seed.index
                            }
                        }
                    }
                }

                // ── Advanced: every slot ──────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.mode === "advanced"
                    columns: 9
                    columnSpacing: 2
                    rowSpacing: 2

                    Repeater {
                        model: Palette.allSlots()
                        delegate: Rectangle {
                            id: slotSw
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            radius: Tokens.radiusXs
                            color: root.slotColor(slotSw.modelData)
                            border.width: root.selectedSlot === slotSw.modelData ? 2 : 1
                            border.color: root.selectedSlot === slotSw.modelData
                                        ? Colors.primary : Colors.outline

                            readonly property bool pinned: ColorScheme.isOverridden(slotSw.modelData)
                            readonly property bool edited: root.draft[slotSw.modelData] !== undefined

                            // Marker colour is computed from the swatch it sits on — a fixed
                            // one disappears against half of any palette.
                            StyledText {
                                anchors.centerIn: parent
                                visible: slotSw.pinned || slotSw.edited
                                text: slotSw.edited ? "󰏫" : "󰐃"
                                color: Palette.readableOn(slotSw.color.toString())
                                variant: "caption"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedSlot = slotSw.modelData
                            }
                        }
                    }
                }

                // ── Picker beside the preview, not above it ───────────────────
                // The picker is a FIXED square, not fillHeight — stretched to the body it
                // became a floor-to-ceiling gradient column that dominated the panel (the
                // "oddly placed" complaint, seen in screenshots twice). The saved-schemes
                // section below is what absorbs the leftover height instead.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    SpectrumPicker {
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 150
                        value: root.mode === "simple"
                             ? root.seeds[root.seedIndex].value
                             : root.slotColor(root.selectedSlot)
                        onColorPicked: function(hex) {
                            if (root.mode === "simple") {
                                const k = root.seeds[root.seedIndex].key
                                if (k === "seedBg") root.seedBg = hex
                                else if (k === "seedFg") root.seedFg = hex
                                else if (k === "seedA")  root.seedA  = hex
                                else                     root.seedB  = hex
                            } else {
                                root.stage(root.selectedSlot, hex)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        // Centred beside the picker, not stretched across its height. The
                        // stretch is what previously demanded a filler — first a giant Aa
                        // block, before that raw dead space. A compact cluster with even
                        // margins needs neither.
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Tokens.spacingSm

                        // What's being edited, and whether it's held.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText {
                                Layout.fillWidth: true
                                text: root.mode === "simple"
                                    ? root.seeds[root.seedIndex].label
                                    : root.selectedSlot
                                      + (ColorScheme.isOverridden(root.selectedSlot) ? " · held" : "")
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                            PanelButton {
                                visible: root.mode === "advanced"
                                      && ColorScheme.isOverridden(root.selectedSlot)
                                variant: "ghost"
                                label: "Release"
                                enabled: !ColorScheme.busy
                                onActivated: ColorScheme.release(root.selectedSlot)
                            }
                        }

                        Surface {
                            Layout.fillWidth: true
                            elevation: Tokens.elevationNested
                            focused: hexField.activeFocus
                            implicitHeight: Tokens.pillHeight + Tokens.spacingSm

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin:  Tokens.spacingSm
                                anchors.rightMargin: Tokens.spacingSm
                                spacing: Tokens.spacingSm

                                Rectangle {
                                    implicitWidth: Tokens.iconSm
                                    implicitHeight: Tokens.iconSm
                                    radius: 3
                                    color: root.mode === "simple"
                                         ? root.seeds[root.seedIndex].value
                                         : root.slotColor(root.selectedSlot)
                                    border.width: 1
                                    border.color: Colors.outline
                                }

                                TextInput {
                                    id: hexField
                                    Layout.fillWidth: true
                                    color: Colors.fg
                                    font.family: Tokens.fontMono
                                    font.pixelSize: Tokens.fontCaption
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    // Not bound while focused: a binding would rewrite the
                                    // field from the live value after every keystroke.
                                    text: activeFocus ? text
                                        : (root.mode === "simple"
                                           ? root.seeds[root.seedIndex].value
                                           : root.slotColor(root.selectedSlot))

                                    function commit() {
                                        const v = hexField.text.trim().toLowerCase()
                                        if (!/^#[0-9a-f]{6}$/.test(v)) return
                                        if (root.mode === "simple") {
                                            const k = root.seeds[root.seedIndex].key
                                            if (k === "seedBg") root.seedBg = v
                                            else if (k === "seedFg") root.seedFg = v
                                            else if (k === "seedA")  root.seedA  = v
                                            else                     root.seedB  = v
                                        } else root.stage(root.selectedSlot, v)
                                        hexField.focus = false
                                    }
                                    Keys.onReturnPressed: hexField.commit()
                                    Keys.onEnterPressed:  hexField.commit()
                                    Keys.onEscapePressed: hexField.focus = false
                                }
                            }
                        }

                        // ── Preview: exactly what Apply will commit ───────────
                        // Bound to `pending` — the derived palette in Simple, the
                        // live-plus-staged one in Advanced. The pill on the left is
                        // background with foreground text on it — the one pairing a strip
                        // of separate squares can't show. It was briefly a big block filling
                        // the column; the user's verdict was to shrink it back to this.
                        RowLayout {
                            id: strip
                            Layout.fillWidth: true
                            // fillHeight FALSE is load-bearing. A nested Layout defaults it
                            // to TRUE, so preferredHeight was ignored and this row stretched
                            // to fill the whole panel — the swatches became giant vertical
                            // bars covering everything. Same default that eats columns on
                            // the Storage page.
                            Layout.fillHeight: false
                            Layout.preferredHeight: 22
                            spacing: 2

                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 22
                                radius: 3
                                color: Palette.slotValue(root.pending, "background")
                                border.width: 1
                                border.color: Colors.alpha(Colors.fg, 0.15)

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Aa"
                                    color: Palette.slotValue(root.pending, "foreground")
                                    variant: "caption"
                                }
                            }

                            Repeater {
                                model: 15
                                delegate: Rectangle {
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    radius: 2
                                    // From color1: color0 is the background, already shown
                                    // in the pill to the left.
                                    color: Palette.slotValue(root.pending, "color" + (index + 1))
                                }
                            }
                        }

                        // ── Name it, save it ──────────────────────────────────
                        // Lives with the EDITOR, not the library: it saves `pending` — the
                        // palette being built above it — so build → name → save reads top to
                        // bottom. It also fills the height beside the picker, which sat
                        // empty once the preview shrank to one row.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm

                            Surface {
                                Layout.fillWidth: true
                                elevation: Tokens.elevationNested
                                focused: schemeName.activeFocus
                                implicitHeight: Tokens.pillHeight + Tokens.spacingSm

                                TextInput {
                                    id: schemeName
                                    anchors.fill: parent
                                    anchors.leftMargin:  Tokens.spacingSm
                                    anchors.rightMargin: Tokens.spacingSm
                                    color: Colors.fg
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontCaption
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    Keys.onEscapePressed: schemeName.focus = false

                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: schemeName.text.length === 0
                                        text: "Save as…"
                                        variant: "caption"
                                        emphasis: "dim"
                                    }
                                }
                            }

                            PanelButton {
                                variant: "normal"
                                glyph: "󰆓"
                                // Says which way it will go BEFORE the click, rather than
                                // raising a confirm dialog after it.
                                label: ColorScheme.schemeExists(schemeName.text) ? "Overwrite" : "Save"
                                enabled: schemeName.text.trim().length > 0
                                onActivated: {
                                    if (ColorScheme.saveScheme(schemeName.text, root.pending))
                                        schemeName.text = ""
                                }
                            }
                        }
                    }
                }
                // ── Saved schemes, inline ─────────────────────────────────────
                // This was a drawer behind a folder toggle — a leftover from when the panel
                // was clipped to 340px and could not hold editor and library at once. At
                // 640x420 the editor doesn't need the whole body, and the leftover height
                // was exactly the dead space the screenshots showed. The library is the
                // natural tenant: the previews are why the cards exist, and a library you
                // must know to open is one nobody browses. Just a caption — the save
                // controls live with the editor above, since they save what it builds.
                StyledText {
                    text: "Saved schemes"
                    variant: "caption"
                    emphasis: "dim"
                }

                // ── Plain Item around the Flickable ───────────────────────────
                // Scrollbar reparents itself to `flickable.parent` and anchors across it.
                // If that parent is a Layout it gets anchored AND laid out at once, which is
                // the "anchors on an item managed by a layout" warning, every frame. Same
                // trap as StoragePage; the wrapper gives it a plain Item to live in.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: chipPane
                        anchors.fill: parent
                        contentHeight: chipFlow.implicitHeight
                        clip: true

                        Flow {
                            id: chipFlow
                            width: chipPane.width
                            spacing: Tokens.spacingSm

                            Repeater {
                                model: ColorScheme.presets
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData

                                    // A card, not a name-chip. A saved scheme is a set of
                                    // COLOURS, and "Crimson Beauty" tells you nothing about
                                    // whether it's the one you want — which is the whole reason
                                    // the library needed previews. Three across now the section
                                    // spans the full 640 width.
                                    width:  (chipFlow.width - 2 * Tokens.spacingSm) / 3
                                    implicitHeight: 54
                                    radius: Tokens.radiusSm
                                    color: chipHover.containsMouse ? Colors.surfaceHigh
                                                                   : Colors.surfaceContainer
                                    border.width: 1
                                    border.color: chipHover.containsMouse ? Colors.primary
                                                                          : Colors.outline
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.spacingSm
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.spacingSm

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: chip.modelData.name
                                                variant: "caption"
                                                elide: Text.ElideRight
                                            }
                                            // Separate hit target, not a mode: a card that
                                            // sometimes loads and sometimes deletes depending on
                                            // where you clicked is how schemes get lost.
                                            StyledText {
                                                text: "󰅖"
                                                variant: "caption"
                                                color: delHover.containsMouse ? Colors.danger
                                                                              : Colors.fgDim
                                                MouseArea {
                                                    id: delHover
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: ColorScheme.deleteScheme(chip.modelData.name)
                                                }
                                            }
                                        }

                                        // Background + text pill, then the ramp: the same
                                        // shape as the editor's preview, so a scheme looks the
                                        // same here as it will when applied.
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 14
                                            radius: 3
                                            color: Palette.slotValue(chip.modelData.palette, "background")
                                            border.width: 1
                                            border.color: Colors.alpha(Colors.fg, 0.15)

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "Aa"
                                                color: Palette.slotValue(chip.modelData.palette, "foreground")
                                                variant: "caption"
                                            }
                                        }

                                        Row {
                                            id: chipStrip
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 10
                                            spacing: 1

                                            Repeater {
                                                // 1..8 rather than all 16: the bright half is
                                                // the dark half lifted toward white, so showing
                                                // both just makes every scheme look similar at
                                                // this size. color0 is the background, already
                                                // above.
                                                model: 8
                                                delegate: Rectangle {
                                                    required property int index
                                                    width: (chipStrip.width - 7) / 8
                                                    height: chipStrip.height
                                                    radius: 2
                                                    color: Palette.slotValue(chip.modelData.palette,
                                                                             "color" + (index + 1))
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: chipHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        z: -1                       // below the delete target
                                        onClicked: ColorScheme.useScheme(chip.modelData)
                                    }
                                }
                            }

                            StyledText {
                                visible: ColorScheme.presets.length === 0 && !ColorScheme.listing
                                text: "None saved yet"
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                    }
                    Scrollbar { flickable: chipPane }
                }
            }

            // ── Progress ──────────────────────────────────────────────────────
            Flickable {
                id: progressPane
                anchors.fill: parent
                contentHeight: progressCol.implicitHeight
                clip: true
                interactive: root.showProgress

                opacity: root.showProgress ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                ColumnLayout {
                    id: progressCol
                    width: progressPane.width
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Tokens.spacingXs
                        spacing: Tokens.spacingSm

                        BusyDot { running: ColorScheme.busy; tint: Colors.primary }
                        StyledText {
                            Layout.fillWidth: true
                            text: ColorScheme.busy
                                ? (ColorScheme.runner.label || "Applying") + "…"
                                : ColorScheme.runner.failedCount > 0
                                ? ColorScheme.runner.failedCount + " step"
                                  + (ColorScheme.runner.failedCount !== 1 ? "s" : "") + " failed"
                                : "Finished with errors"
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: ColorScheme.busy ? Colors.fg : Colors.warning
                            elide: Text.ElideRight
                        }
                        PanelButton {
                            variant: "ghost"
                            glyph: root.showDetails ? "󰅃" : "󰅀"
                            label: "Details"
                            onActivated: root.showDetails = !root.showDetails
                        }
                        PanelButton {
                            visible: !ColorScheme.busy
                            variant: "ghost"
                            label: "Dismiss"
                            onActivated: ColorScheme.runner.clearResult()
                        }
                    }

                    Repeater {
                        model: root.showDetails ? ColorScheme.runner.steps : []
                        delegate: RowLayout {
                            id: stepRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText {
                                text: stepRow.modelData.status === "ok"   ? "󰄬"
                                    : stepRow.modelData.status === "fail" ? "󰅖"
                                    : stepRow.modelData.status === "skip" ? "󰒲"
                                    : "󰔟"
                                color: stepRow.modelData.status === "ok"   ? Colors.success
                                     : stepRow.modelData.status === "fail" ? Colors.danger
                                     : Colors.fgDim
                                variant: "caption"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: stepRow.modelData.text
                                variant: "caption"
                                emphasis: stepRow.modelData.status === "skip" ? "dim" : "normal"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            Scrollbar { flickable: progressPane }
        }

        // ── Apply ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: !root.showProgress
            spacing: Tokens.spacingMd

            // ── Restart prompt, absorbed ──────────────────────────────────────
            // Was a full-width elevated Surface between body and Apply — a second bar that
            // compressed the card area whenever it appeared and broke the panel's shape. As
            // the left-hand group of the Apply row it costs no height and reads as what it
            // is: a follow-up action, not an alarm.
            RowLayout {
                visible: ColorScheme.runner.needsRestart && !ColorScheme.busy
                spacing: Tokens.spacingSm

                StyledText { text: "󰜉"; color: Colors.info; variant: "caption" }
                StyledText {
                    Layout.maximumWidth: 280
                    text: ColorScheme.runner.restartApps.map(a => a.label).join(", ")
                        + (ColorScheme.runner.restartApps.length === 1 ? " needs" : " need")
                        + " a restart to recolour"
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
                PanelButton {
                    variant: "ghost"
                    glyph: "󰑐"
                    label: "Restart"
                    onActivated: ColorScheme.runner.restartAll()
                }
                PanelButton {
                    variant: "ghost"
                    glyph: "󰅖"
                    onActivated: ColorScheme.runner.dismissRestart()
                }
            }

            PanelButton {
                visible: root.mode === "advanced" && root.draftCount > 0
                variant: "ghost"
                label: "Discard"
                onActivated: root.discardDraft()
            }
            Item { Layout.fillWidth: true }
            PanelButton {
                variant: "primary"
                accent:  Colors.primary
                glyph:   "󰸌"
                // Names the consequence rather than saying "Apply" in both modes: one
                // replaces the palette, the other holds slots against future wallpapers,
                // and those are not the same promise.
                label: root.mode === "simple"
                     ? "Apply scheme"
                     : root.draftCount > 0
                     ? "Hold " + root.draftCount + " colour" + (root.draftCount !== 1 ? "s" : "")
                     : "Re-apply"
                enabled: !ColorScheme.busy
                onActivated: root.applyCurrent()
            }
        }
    }
}
