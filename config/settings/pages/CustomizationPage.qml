import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theming" as T
import "../../config"
import "../../bar"
import ".."

// Customization (Panels) — configure the bar entirely from the GUI. Every control
// writes straight through the Config store, so the live bar updates instantly and
// the choice persists (Config auto-saves on change). No file editing needed.
Item {
    id: root

    // ── Edge ────────────────────────────────────────────────────────────────────
    readonly property var edges: [
        { id: "top",    label: "Top",    glyph: 0xF10A6 },
        { id: "bottom", label: "Bottom", glyph: 0xF10A4 },
        { id: "left",   label: "Left",   glyph: 0xF10A5 },
        { id: "right",  label: "Right",  glyph: 0xF10A7 },
    ]

    // ── Monitors ────────────────────────────────────────────────────────────────
    readonly property var screens: Quickshell.screens
    function enabledCount() {
        var c = 0
        for (var i = 0; i < screens.length; i++) if (Config.barShowsOn(screens[i].name)) c++
        return c
    }
    function setMonitor(name, on) {
        if (!on && enabledCount() <= 1) return         // never leave zero monitors
        var all = screens.map(function(s){ return s.name })
        var enabled = all.filter(function(n){ return n === name ? on : Config.barShowsOn(n) })
        // All selected → store [] ("all", and future monitors get the bar too).
        Config.barMonitors = (enabled.length === all.length) ? [] : enabled
    }

    // ── Modules ─────────────────────────────────────────────────────────────────
    // Read the three groups DIRECTLY here so bindings track them (a Config.barEnabled()
    // function call would hide the dependency and go stale).
    readonly property var enabledIds: Config.barLeading.concat(Config.barCenter).concat(Config.barTrailing)
    readonly property var disabledModules: BarCatalog.items.filter(function(m){ return enabledIds.indexOf(m.id) === -1 })

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 20

            Text {
                text: "Customization"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }

            // ── Bar position ─────────────────────────────────────────────────────
            SectionLabel { text: "Bar position" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: root.edges
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: Config.barEdge === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: T.Theme.moduleRadius
                        color: sel ? T.Theme.surfaceActive : (ema.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                        border.width: sel ? 1 : 0
                        border.color: T.Theme.accent
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: String.fromCodePoint(modelData.glyph)
                                color: sel ? T.Theme.accent : T.Theme.ink
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 6 }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: sel ? T.Theme.ink : T.Theme.inkDim
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3; bold: sel }
                            }
                        }
                        MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.barEdge = modelData.id }
                    }
                }
            }

            // ── Bar thickness ────────────────────────────────────────────────────
            SectionLabel { text: "Bar thickness" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        { id: "thick", label: "Thick", glyph: 0xF0322, desc: "Full time on one line" },
                        { id: "thin",  label: "Thin",  glyph: 0xF0323, desc: "Slimmer; time stacks" },
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: (Config.barThickness !== "thin" ? "thick" : "thin") === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: T.Theme.moduleRadius
                        color: sel ? T.Theme.surfaceActive : (tma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                        border.width: sel ? 1 : 0
                        border.color: T.Theme.accent
                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                text: String.fromCodePoint(modelData.glyph)
                                color: sel ? T.Theme.accent : T.Theme.ink
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 6 }
                            }
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: modelData.label
                                    color: sel ? T.Theme.ink : T.Theme.inkDim
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: sel }
                                }
                                Text {
                                    text: modelData.desc
                                    color: T.Theme.inkDim
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                                }
                            }
                        }
                        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.barThickness = modelData.id }
                    }
                }
            }

            // ── Screen inset ─────────────────────────────────────────────────────
            SectionLabel { text: "Screen inset" }
            Text {
                Layout.fillWidth: true
                text: "The thin themed frame reserved around the screen edges (the bar's edge "
                    + "stays thick). Set how wide that gutter is, or turn it off."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [ { px: 0, label: "None" }, { px: 5, label: "Thin" }, { px: 10, label: "Medium" }, { px: 16, label: "Thick" } ]
                    delegate: SegBtn {
                        required property var modelData
                        label: modelData.label
                        sel: Config.insetSize === modelData.px
                        onClicked: Config.insetSize = modelData.px
                    }
                }
            }

            // ── Corner roundness ─────────────────────────────────────────────────
            SectionLabel { text: "Corner roundness" }
            Text {
                Layout.fillWidth: true
                text: "Dial the roundness of every surface — the bar, panels, popups, "
                    + "buttons and cards — up or down. Drives the theme's radius tokens globally."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                readonly property real maxRound: 2.0
                Text { text: "Sharp"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 } }
                Rectangle {
                    id: rTrack
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: T.Theme.radiusFull
                    color: T.Theme.surfaceHover
                    readonly property real frac: Math.max(0, Math.min(1, Config.cornerRoundness / parent.maxRound))
                    Rectangle {
                        height: parent.height; radius: T.Theme.radiusFull
                        width: parent.width * parent.frac
                        color: T.Theme.accent
                    }
                    // Handle.
                    Rectangle {
                        width: 18; height: 18; radius: T.Theme.radiusFull
                        y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(parent.width - width, parent.frac * parent.width - width / 2))
                        color: T.Theme.accent
                        border.width: 2; border.color: T.Theme.background
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -10; anchors.bottomMargin: -10
                        cursorShape: Qt.PointingHandCursor
                        function apply(mx) {
                            var f = Math.max(0, Math.min(1, mx / width))
                            Config.cornerRoundness = Math.round(f * parent.parent.maxRound * 20) / 20   // 0.05 steps
                        }
                        onPressed: function(m){ apply(m.x) }
                        onPositionChanged: function(m){ if (pressed) apply(m.x) }
                    }
                }
                Text { text: "Round"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 } }
                Text {
                    Layout.preferredWidth: 44
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(Config.cornerRoundness * 100) + "%"
                    color: T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; bold: true }
                }
            }

            // ── Edge-reveal panels (top info + right quick panel) ────────────────
            // Same shared reveal system (P2/P3); each has its own per-use settings.
            RevealSettings {
                revealId: "topInfo"
                title: "Info panel (top edge)"
                blurb: "On a left/right bar, the calendar / media / performance / weather "
                     + "panel reveals from the top edge when you hover there — no button needed."
            }
            RevealSettings {
                revealId: "rightPanel"
                title: "Notification panel (right edge)"
                blurb: "On a left bar, the notifications + quick-settings panel (Do Not Disturb, "
                     + "mute, mic) reveals from the right edge when you hover there."
            }

            // ── Launcher (Win+R) ─────────────────────────────────────────────────
            SectionLabel { text: "Launcher position" }
            Text {
                Layout.fillWidth: true
                text: "Where the Win+R app launcher appears: slide up from the bottom edge, "
                    + "or rise in at the center of the screen."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [ { id: "bottom", label: "Bottom" }, { id: "middle", label: "Middle" } ]
                    delegate: SegBtn {
                        required property var modelData
                        label: modelData.label
                        sel: Config.launcherPosition === modelData.id
                        onClicked: Config.launcherPosition = modelData.id
                    }
                }
            }
            RevealSettings {
                revealId: "launcher"
                title: "Launcher animation"
                blurb: "The launcher slides in using the shared reveal animation."
                enableLabel: "Animate opening"
            }

            // ── Settings window placement ────────────────────────────────────────
            SectionLabel { text: "Settings window" }
            Text {
                Layout.fillWidth: true
                text: "Where the settings window opens: dead centre of the screen, or anchored to "
                    + "the button or launcher result that opened it."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [ { id: "center", label: "Centre" }, { id: "anchored", label: "Anchored" } ]
                    delegate: SegBtn {
                        required property var modelData
                        label: modelData.label
                        sel: Config.settingsPlacement === modelData.id
                        onClicked: Config.settingsPlacement = modelData.id
                    }
                }
            }

            // ── Monitors ─────────────────────────────────────────────────────────
            SectionLabel { text: "Monitors" }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.screens
                    delegate: Rectangle {
                        id: monRow
                        required property var modelData
                        readonly property bool on: Config.barShowsOn(modelData.name)
                        Layout.fillWidth: true
                        implicitHeight: 50
                        radius: T.Theme.moduleRadius
                        color: T.Theme.surfaceAlt
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 12
                            Text {
                                text: String.fromCodePoint(0xF0379)   // monitor
                                color: monRow.on ? T.Theme.accent : T.Theme.inkDim
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 4 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: monRow.modelData.name
                                    color: T.Theme.ink
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                                }
                                Text {
                                    text: (monRow.modelData.width || "?") + "×" + (monRow.modelData.height || "?")
                                          + (monRow.modelData.model ? "   ·   " + monRow.modelData.model : "")
                                    color: T.Theme.inkDim
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                                }
                            }
                            Toggle { on: monRow.on; onToggled: function(v){ root.setMonitor(monRow.modelData.name, v) } }
                        }
                    }
                }
            }

            // ── Bar items (leading / center / trailing) ──────────────────────────
            SectionLabel { text: "Bar items" }
            Text {
                Layout.fillWidth: true
                text: "Use ↑ ↓ to reorder within a group, and ← → to move an item between "
                    + "leading (start), center, and trailing (end) — so any item can go to either end."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }
            GroupSection { groupKey: "leading";  label: "Leading (start)"; items: Config.barLeading }
            GroupSection { groupKey: "center";   label: "Center";          items: Config.barCenter }
            GroupSection { groupKey: "trailing"; label: "Trailing (end)";  items: Config.barTrailing }

            // ── Available (disabled) modules ─────────────────────────────────────
            SectionLabel { text: "Available modules"; visible: root.disabledModules.length > 0 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.disabledModules
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 50
                        radius: T.Theme.moduleRadius
                        color: T.Theme.surfaceAlt
                        opacity: 0.75
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 10
                            Text {
                                text: String.fromCodePoint(modelData.glyph)
                                color: T.Theme.inkDim
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 3 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: T.Theme.inkDim
                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize }
                            }
                            Toggle { on: false; onToggled: Config.barEnable(modelData.id, "leading") }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        color: T.Theme.accent
        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
    }

    // One edge-reveal's per-use settings: enable toggle + animation style + speed,
    // all writing through Config.setReveal(revealId, …). Reused for every reveal
    // (top info panel, right quick panel, …) so they stay consistent.
    component RevealSettings: ColumnLayout {
        id: rv
        property string revealId: ""
        property string title: ""
        property string blurb: ""
        property string enableLabel: "Reveal on hover"
        readonly property var o: Config.revealFor(revealId)
        Layout.fillWidth: true
        spacing: 12

        SectionLabel { text: rv.title }
        Text {
            Layout.fillWidth: true
            text: rv.blurb
            wrapMode: Text.WordWrap
            color: T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
        }
        // Enabled
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 50
            radius: T.Theme.moduleRadius
            color: T.Theme.surfaceAlt
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: rv.enableLabel
                    color: T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                }
                Toggle { on: rv.o.enabled; onToggled: function(v){ Config.setReveal(rv.revealId, "enabled", v) } }
            }
        }
        // Animation style + speed (dimmed when the reveal is off).
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            opacity: rv.o.enabled ? 1 : 0.4
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "Animation"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; bold: true } }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [ { id: "slide", label: "Slide" }, { id: "instant", label: "Instant" } ]
                        delegate: SegBtn {
                            required property var modelData
                            label: modelData.label
                            sel: rv.o.style === modelData.id
                            onClicked: Config.setReveal(rv.revealId, "style", modelData.id)
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "Speed"; color: T.Theme.inkDim; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; bold: true } }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [ { d: 140, label: "Fast" }, { d: 220, label: "Normal" }, { d: 340, label: "Slow" } ]
                        delegate: SegBtn {
                            required property var modelData
                            label: modelData.label
                            sel: rv.o.duration === modelData.d
                            onClicked: Config.setReveal(rv.revealId, "duration", modelData.d)
                        }
                    }
                }
            }
        }
    }

    // Small segmented-choice button (used by the info-panel animation/speed rows).
    component SegBtn: Rectangle {
        property string label: ""
        property bool sel: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 40
        radius: T.Theme.moduleRadius
        color: sel ? T.Theme.surfaceActive : (sbma.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
        border.width: sel ? 1 : 0
        border.color: T.Theme.accent
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.sel ? T.Theme.ink : T.Theme.inkDim
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: parent.sel }
        }
        MouseArea { id: sbma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // Small icon button (reorder ↑↓ and move-between-groups ←→).
    component MiniBtn: Rectangle {
        property int glyph: 0xF0143
        property bool wide: false
        signal clicked()
        implicitWidth: wide ? 26 : 22; implicitHeight: wide ? 26 : 18
        radius: T.Theme.radiusSmall
        color: mbma.containsMouse && enabled ? T.Theme.surfaceHover : (wide ? T.Theme.surface : "transparent")
        opacity: enabled ? 1 : 0.25
        Text { anchors.centerIn: parent; text: String.fromCodePoint(parent.glyph); color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - (parent.wide ? 1 : 2) } }
        MouseArea { id: mbma; anchors.fill: parent; hoverEnabled: true; enabled: parent.enabled; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // One placement group (leading/center/trailing): a header + its items, each
    // with reorder (↑↓ within the group) and move (←→ to the adjacent group) plus
    // a toggle to remove it from the bar. All actions write through Config, so the
    // live bar updates instantly.
    component GroupSection: ColumnLayout {
        id: grp
        property string groupKey: "leading"
        property string label: ""
        property var    items: []
        readonly property var _order: ["leading", "center", "trailing"]
        readonly property int _gi: _order.indexOf(groupKey)
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: grp.label
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: grp.items.length === 0
                text: "empty"
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3; italic: true }
            }
        }

        Repeater {
            model: grp.items
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property var meta: BarCatalog.meta(modelData)
                Layout.fillWidth: true
                implicitHeight: 50
                radius: T.Theme.moduleRadius
                color: T.Theme.surfaceAlt
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 10
                    spacing: 8
                    ColumnLayout {
                        spacing: 0
                        MiniBtn { glyph: 0xF0143; enabled: index > 0;                onClicked: Config.barMoveWithin(grp.groupKey, index, -1) }
                        MiniBtn { glyph: 0xF0140; enabled: index < grp.items.length - 1; onClicked: Config.barMoveWithin(grp.groupKey, index, 1) }
                    }
                    Text {
                        text: String.fromCodePoint(meta.glyph)
                        color: T.Theme.accent
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 3 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: meta.title
                        color: T.Theme.ink
                        elide: Text.ElideRight
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: true }
                    }
                    MiniBtn { glyph: 0xF004D; wide: true; enabled: grp._gi > 0;                  onClicked: Config.barMoveToGroup(grp.groupKey, index, grp._order[grp._gi - 1]) }  // ← prev group
                    MiniBtn { glyph: 0xF0054; wide: true; enabled: grp._gi < grp._order.length - 1; onClicked: Config.barMoveToGroup(grp.groupKey, index, grp._order[grp._gi + 1]) }  // → next group
                    Toggle { on: true; onToggled: Config.barDisable(modelData) }
                }
            }
        }
    }
}
