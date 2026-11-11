pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import ".."

// ── HyprlandPage — Window manager › Keybinds ──────────────────────────────────
// Keybinds read from and written to the user's native-Lua Hyprland config
// (~/.config/hypr) through the HyprConfig service. Everything here is a VIEW over
// HyprConfig — the service owns the parsed config, the write queue, the backups and
// the undo stack.
//
// ── Why the window manager is two views now ───────────────────────────────────
// It was keybinds on the left and a fixed 372px column of sliders on the right, each
// scrolling on its own — the sliders column alone was over a window tall. The
// tunables are HyprTuningPage now, and the keybinds get the whole width: groups are
// dealt into two columns balanced by row count, so a long bind list reads across the
// page instead of down it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted: HyprConfig.acquire()
    Component.onDestruction: HyprConfig.release()

    // ── Keybind view state (page-local; the edits themselves go to the service) ──
    property string search: ""
    property int    editingLine: -1
    property string editCombo: ""
    property string editOrigCombo: ""
    property string editAction: ""
    property string editOrigAction: ""
    property bool   editExec: true

    property bool   adding: false
    property string addCombo: ""
    property string addValue: ""
    property bool   addLua: false

    function startEdit(b) {
        root.adding = false
        root.editingLine   = b.line
        root.editOrigCombo = b.combo
        root.editCombo     = b.combo
        root.editExec      = (b.action.type === "exec")
        root.editAction    = root.editExec
            ? b.action.args
            : ("hl.dsp." + b.action.name + "(" + (b.action.args || "") + ")")
        root.editOrigAction = root.editAction
    }
    function saveEdit(line) {
        const combo = root.editCombo.trim()
        if (combo !== "" && combo !== root.editOrigCombo)
            HyprConfig.rebind(line, combo)
        const act = root.editAction.trim()
        if (act !== "" && act !== root.editOrigAction)
            HyprConfig.setAction(line, root.editExec ? "exec" : "raw", act)
        root.editingLine = -1
    }
    function startAdd() {
        root.editingLine = -1
        root.adding = true
        root.addCombo = ""; root.addValue = ""; root.addLua = false
    }
    function saveAdd() {
        const c = root.addCombo.trim(), v = root.addValue.trim()
        if (c === "" || v === "") return
        HyprConfig.addBind(c, root.addLua ? "raw" : "exec", v)
        root.adding = false
    }

    // The chosen category ("" = every section), a chip above the list. 48 binds in one wall
    // was the clutter: you almost always want one KIND (the focus keys, the launchers).
    property string category: ""

    // The sections that exist, with how many binds each holds — the chips' model.
    readonly property var categories: {
        const out = [], idx = ({})
        for (const b of HyprConfig.binds) {
            const k = b.section || "Other"
            if (idx[k] === undefined) { idx[k] = out.length; out.push({ section: k, n: 0 }) }
            out[idx[k]].n++
        }
        return out
    }

    // Binds grouped by their source section, filtered by the search box and the category.
    readonly property var groups: {
        const s = root.search.trim().toLowerCase()
        const out = [], byName = ({})
        for (const b of HyprConfig.binds) {
            if (root.category !== "" && (b.section || "Other") !== root.category) continue
            if (s !== "" &&
                !((b.combo || "").toLowerCase().includes(s)
                  || (b.action.text || "").toLowerCase().includes(s)
                  || (b.section || "").toLowerCase().includes(s)))
                continue
            const key = b.section || "Other"
            let g = byName[key]
            if (!g) { g = { section: key, binds: [] }; byName[key] = g; out.push(g) }
            g.binds.push(b)
        }
        return out
    }

    // ── Groups dealt into two columns ─────────────────────────────────────────
    // Greedy by ROW COUNT (binds + the group's heading), into whichever column is
    // shorter so far. No measuring and no reparenting — the counts are known before
    // anything is drawn, and rows are one fixed height, so the count IS the height
    // (bar an open inline editor, which only ever makes one column briefly taller).
    readonly property var groupColumns: {
        const cols = [[], []], load = [0, 0]
        for (const g of root.groups) {
            const i = load[0] <= load[1] ? 0 : 1
            cols[i].push(g)
            load[i] += g.binds.length + 1.5
        }
        return cols
    }

    readonly property int rowHeight: Tokens.pillHeight + Tokens.spacingMd

    // ── What a row SAYS its action is ─────────────────────────────────────────
    // Presentation only — the edit field still shows the real command. A call into
    // this shell reads as "Shell: launcher toggle" instead of a qs ipc line with the
    // config's full path in it, and any other path loses the home directory.
    readonly property string home: Quickshell.env("HOME") || ""
    function prettyAction(text) {
        let t = String(text || "")
        const m = t.match(/^Run: (?:qs|quickshell) ipc (?:-[cp] \S+ )?call (.+)$/)
        if (m) return "Shell: " + m[1]
        if (root.home !== "") t = t.split(root.home).join("~")
        return t
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        PanelHeader {
            // The same header every Settings page wears (SettingsPage): a morphing badge, a headline.
            morph:     "squircle"
            chipSize:  Tokens.iconXl + Tokens.spacingLg
            titleVariant: "headline"
            subtitleVariant: "label"
            Layout.fillHeight: false
            glyph:     "󰌋"
            title:     Translation.tr("Key")
            titleTail: "binds"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  !HyprConfig.loaded
                       ? "Reading ~/.config/hypr…"
                       : HyprConfig.binds.length + " binds  ·  saved to your Hyprland config, live on reload"

            ChipTray {
                ChipButton {
                    symbol:  root.adding ? "close" : "add"
                    label:   root.adding ? "Cancel" : "Add bind"
                    on:      !root.adding
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: HyprConfig.loaded
                    onActivated: root.adding ? root.adding = false : root.startAdd()
                }
            }
        }


        HyprApplyBar {}

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: HyprConfig.loaded
            spacing: Tokens.spacingMd

            InputField {
                implicitHeight: Tokens.iconXl + Tokens.spacingMd
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("Search keybinds")
                // Types a few things it can find, like the settings search does.
                hintLead: "Search keybinds"
                hints: [{ key: "SUPER + Q" }, { key: "screenshot" }, { key: "workspace" },
                        { key: "launcher" }, { key: "fullscreen" }]
                onEdited: function (t) { root.search = t }
            }
        }

        // ── Categories ────────────────────────────────────────────────────────
        ChipRow {
            Layout.fillHeight: false
            visible: HyprConfig.loaded && root.categories.length > 1
            accent: Colors.of(QsWindow.window).primary
            model: [{ value: "", label: "All  " + HyprConfig.binds.length }].concat(
                root.categories.map(c => ({ value: c.section, label: c.section + "  " + c.n })))
            current: root.category
            onPicked: function (v) { root.category = v }
        }

        // ── Add form ──────────────────────────────────────────────────────────
        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.adding
            onVisibleChanged: if (visible) { addComboField.clear(); addValueField.clear() }
            implicitHeight: addRow.implicitHeight + Tokens.spacingMd * 2
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            castsShadow:  false

            RowLayout {
                id: addRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd

                InputField {
                    cornerRadius: implicitHeight / 2
                    id: addComboField
                    Layout.preferredWidth: 180
                    placeholder: "SUPER + B"; mono: true
                    onEdited: function (t) { root.addCombo = t }
                }
                InputField {
                    cornerRadius: implicitHeight / 2
                    id: addValueField
                    Layout.fillWidth: true
                    placeholder: root.addLua ? "hl.dsp.focus({ direction = \"left\" })" : "command to run"
                    mono: root.addLua
                    onEdited: function (t) { root.addValue = t }
                    onAccepted: root.saveAdd()
                }
                StyledText { text: "Lua"; variant: "caption"; emphasis: "muted" }
                Toggle { accent: Colors.of(QsWindow.window).primary; checked: root.addLua; onToggled: root.addLua = !root.addLua }
                PanelButton {
                    capsule: true
                    variant: "primary"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "check"
                    label: Translation.tr("Add")
                    enabled: root.addCombo.trim() !== "" && root.addValue.trim() !== ""
                    onActivated: root.saveAdd()
                }
            }
        }

        // ── The bind list: two balanced columns, one scroll ───────────────────
        // A list, so it scrolls — but the page around it doesn't.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: HyprConfig.loaded

            Flickable {
                id: bindFlick
                anchors.fill: parent
                contentHeight: bindRow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: bindRow
                    width: bindFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                    spacing: Tokens.spacingXl

                    Repeater {
                        model: root.groupColumns

                        ColumnLayout {
                            id: bindCol
                            required property var modelData
                            Layout.preferredWidth: 1          // even split, see NetworkPage history
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignTop
                            spacing: Tokens.spacingLg

                            Repeater {
                                model: bindCol.modelData

                                ColumnLayout {
                                    id: grp
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: Tokens.spacingXs

                                    StyledText {
                                        visible: root.category === ""
                                        Layout.topMargin: Tokens.spacingXs
                                        text: grp.modelData.section + "  ·  " + grp.modelData.binds.length
                                        variant: "caption"
                                        emphasis: "dim"
                                        font.weight: Font.DemiBold
                                    }

                                    Repeater {
                                        model: grp.modelData.binds

                                        ColumnLayout {
                                            id: bindItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            spacing: 0

                                            readonly property bool editing:
                                                root.editingLine === bindItem.modelData.line
                                                && bindItem.modelData.editable

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: root.rowHeight
                                                radius: Tokens.radiusSm
                                                color: rowHover.hovered || bindItem.editing
                                                       ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05) : "transparent"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin:  Tokens.spacingSm
                                                    anchors.rightMargin: Tokens.spacingXs
                                                    spacing: Tokens.spacingMd

                                                    // ── The keys, as keys ─────────────────────────────────
                                                    // One cap per key with a lip underneath, so a combo reads as
                                                    // the chord you press and not as a string. Modifiers sit
                                                    // quieter than the key they go with.
                                                    Row {
                                                        Layout.preferredWidth: 168
                                                        Layout.alignment: Qt.AlignVCenter
                                                        spacing: Tokens.spacingXs

                                                        Repeater {
                                                            model: String(bindItem.modelData.combo).split("+")
                                                                       .map(k => k.trim()).filter(k => k !== "")

                                                            Item {
                                                                id: cap
                                                                required property string modelData
                                                                required property int index
                                                                readonly property bool last:
                                                                    cap.index === String(bindItem.modelData.combo).split("+").length - 1
                                                                width:  Math.max(capText.implicitWidth + Tokens.spacingMd * 2, Tokens.pillHeight)
                                                                height: Tokens.pillHeight

                                                                Rectangle {          // the lip
                                                                    anchors.fill: parent
                                                                    radius: Tokens.radiusSm - 2
                                                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.16)
                                                                }
                                                                Rectangle {          // the face
                                                                    width: parent.width
                                                                    height: parent.height - 3
                                                                    radius: Tokens.radiusSm - 2
                                                                    color: cap.last
                                                                        ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.30)
                                                                        : Colors.of(QsWindow.window).surfaceHigh
                                                                    StyledText {
                                                                        id: capText
                                                                        anchors.centerIn: parent
                                                                        text: cap.modelData
                                                                        variant: "caption"
                                                                        font.family: Tokens.fontMono
                                                                        font.weight: cap.last ? Font.DemiBold : Font.Medium
                                                                        color: cap.last ? Colors.of(QsWindow.window).fg
                                                                                        : Colors.of(QsWindow.window).fgMuted
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: root.prettyAction(bindItem.modelData.action.text)
                                                             + (bindItem.modelData.desc ? "  ·  " + bindItem.modelData.desc : "")
                                                        variant: "label"
                                                        elide: Text.ElideRight
                                                    }
                                                    // Read-only marker — the action text says
                                                    // why (a loop range, or a custom function).
                                                    MaterialIcon {
                                                        visible: !bindItem.modelData.editable
                                                        glyph: "󰌾"
                                                        variant: "label"
                                                        emphasis: "dim"
                                                    }
                                                    IconButton {
                                                        visible: bindItem.modelData.editable && (rowHover.hovered || bindItem.editing)
                                                        glyph: "󰏫"; container: false
                                                        onClicked: root.startEdit(bindItem.modelData)
                                                    }
                                                    IconButton {
                                                        visible: bindItem.modelData.editable && rowHover.hovered
                                                        glyph: "󰆴"; container: false
                                                        iconColor: Colors.of(QsWindow.window).danger
                                                        onClicked: HyprConfig.removeBind(bindItem.modelData.line)
                                                    }
                                                }
                                                HoverHandler { id: rowHover }
                                            }

                                            // Inline editor. Fields are SEEDED when it opens
                                            // rather than bound — a live binding breaks on the
                                            // first keystroke and shows stale text on reopen.
                                            Surface {
                                                Layout.fillWidth: true
                                                visible: bindItem.editing
                                                onVisibleChanged: if (visible) {
                                                    comboField.setText(root.editCombo)
                                                    actionField.setText(root.editAction)
                                                }
                                                implicitHeight: editCol.implicitHeight + Tokens.spacingMd * 2
                                                elevation:    Tokens.elevationNested
                                                cornerRadius: Tokens.radiusSm
                                                castsShadow:  false

                                                ColumnLayout {
                                                    id: editCol
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.margins: Tokens.spacingMd
                                                    spacing: Tokens.spacingSm

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Tokens.spacingMd
                                                        StyledText { text: "Keys"; Layout.preferredWidth: 40; variant: "caption"; emphasis: "muted" }
                                                        InputField {
                                                            cornerRadius: implicitHeight / 2
                                                            id: comboField
                                                            Layout.fillWidth: true; mono: true
                                                            onEdited: function (t) { root.editCombo = t }
                                                        }
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Tokens.spacingMd
                                                        StyledText {
                                                            text: root.editExec ? "Run" : "Lua"
                                                            Layout.preferredWidth: 40; variant: "caption"; emphasis: "muted"
                                                        }
                                                        InputField {
                                                            cornerRadius: implicitHeight / 2
                                                            id: actionField
                                                            Layout.fillWidth: true
                                                            mono: !root.editExec
                                                            onEdited: function (t) { root.editAction = t }
                                                            onAccepted: root.saveEdit(bindItem.modelData.line)
                                                        }
                                                        PanelButton {
                                                            capsule: true
                                                            variant: "ghost"
                                                            symbol: "close"
                                                            onActivated: root.editingLine = -1
                                                        }
                                                        PanelButton {
                                                            capsule: true
                                                            variant: "primary"
                                                            accent: Colors.of(QsWindow.window).primary
                                                            symbol: "check"
                                                            onActivated: root.saveEdit(bindItem.modelData.line)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Scrollbar { flickable: bindFlick }

            StyledText {
                anchors.centerIn: parent
                visible: root.groups.length === 0
                text: root.search.trim() !== "" ? "No keybinds match “" + root.search.trim() + "”."
                                                : "No keybinds found in your config."
                variant: "body"
                emphasis: "dim"
            }
        }
    }
}
