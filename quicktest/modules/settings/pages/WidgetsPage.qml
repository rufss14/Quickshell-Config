pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../desktop/widgets"

// ── WidgetsPage ───────────────────────────────────────────────────────────────
// Desktop widgets: what exists, where it lives, and the settings the widgets share.
//
// ── Three columns: Add | Placed | Settings ────────────────────────────────────
// Same geometry as the other pages (~1510 wide — see NetworkPage for the derivation).
// The columns follow the actual sequence of using this: pick a widget, see where it
// went, then tune it. Add and Placed as one list would mean the catalogue scrolling
// away as the desktop fills up.
//
// ── Arranging happens on the DESKTOP, not here ────────────────────────────────
// The obvious design is a little draggable map of the screen in this page. It was
// rejected: a 400px proxy of a 1920px desktop cannot show you whether a widget covers
// the thing you actually keep there, and getting it right on the map still means
// checking the real screen. So "Arrange" closes the overview and puts the real widgets
// on the real desktop, which is also the only place the wallpaper is visible.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Which placed widget the settings column is editing. Held as an ID, not an index
    // or a record — the store replaces every record on each change, so an index would
    // drift as widgets are added and removed and a record would go stale immediately.
    property int selectedId: -1
    readonly property var selected: DesktopWidgets.get(root.selectedId)

    // Where a newly added widget lands. Defaults to the primary screen; multi-monitor
    // users pick, because a widget added to a screen you are not looking at looks
    // exactly like a widget that failed to be added.
    property string targetScreen:
        Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXl

        // ══ ADD ═══════════════════════════════════════════════════════════════
        // The WIDE column, because previews are the thing that needs room. At 330 only
        // two of five fit and the catalogue had to be scrolled to be seen at all —
        // which defeats the point of showing them.
        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            elevation: Tokens.elevationCard

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXl
                spacing: Tokens.spacingMd

                StyledText { text: "Add a widget"; variant: "title"; font.bold: true }
                StyledText {
                    Layout.fillWidth: true
                    text: "Drops onto the desktop, then drag it where you want."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                // Screen picker — only when there is a choice to make.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    visible: Quickshell.screens.length > 1
                    spacing: Tokens.spacingSm

                    StyledText { text: "Screen"; variant: "caption"; emphasis: "muted" }
                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: Quickshell.screens
                        PanelButton {
                            required property var modelData
                            variant: root.targetScreen === modelData.name ? "primary" : "normal"
                            label: modelData.name
                            onActivated: root.targetScreen = modelData.name
                        }
                    }
                }

                Divider { Layout.fillWidth: true }

                // ── The gallery ───────────────────────────────────────────
                // Real widgets at (near) real size, the way the macOS widget picker
                // shows them. A row of glyph + label told you a Calendar existed; it
                // could not tell you what the small one actually looks like, which is
                // the only question you have while choosing.
                // Wrapped in a plain Item, not placed in the ColumnLayout directly:
                // Scrollbar reparents itself to `flickable.parent` and anchors across
                // it, so a Layout parent means anchored and laid out at once — the
                // warning this shell has now paid for four times.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: galleryFlick
                        anchors.fill: parent
                        contentHeight: gallery.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Flow {
                            id: gallery
                            width: parent.width
                            spacing: Tokens.spacingLg

                            // THREE across. At two, seventeen types made 2193px of cards in
                            // an 864px viewport — measured, not estimated — so most of the
                            // catalogue was below the fold with nothing on screen saying so.
                            // Three fits the column's real 726px without shrinking a small
                            // tile below its natural 168px, which is the width that decides
                            // it: at four the previews would be scaled down from life size.
                            //
                            // Cards are a FIXED height so the grid stays aligned — a large
                            // widget previews much taller than a small one, and a ragged
                            // grid reads as broken rather than as varied.
                            readonly property real cardW:
                                Math.floor((gallery.width - Tokens.spacingLg * 2) / 3)

                            Repeater {
                                model: DesktopWidgets.catalogue

                                ColumnLayout {
                                    id: cat
                                    required property var modelData
                                    width: gallery.cardW
                                    spacing: Tokens.spacingSm

                                    readonly property bool placed:
                                        DesktopWidgets.has(cat.modelData.type, root.targetScreen)

                                    Surface {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 160
                                        elevation: Tokens.elevationNested
                                        cornerRadius: Tokens.radiusSm
                                        focused: catMouse.containsMouse && !cat.placed
                                        opacity: cat.placed ? 0.45 : 1

                                        WidgetPreview {
                                            id: preview
                                            anchors.centerIn: parent
                                            type: cat.modelData.type
                                            opts: DesktopWidgets.sampleOpts(cat.modelData.type)
                                            boxWidth: gallery.cardW - Tokens.spacingLg * 2
                                            maxHeight: 128
                                        }

                                        MouseArea {
                                            id: catMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !cat.placed
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const id = DesktopWidgets.add(cat.modelData.type,
                                                                              root.targetScreen)
                                                if (id !== -1) root.selectedId = id
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacingSm

                                        StyledText {
                                            text: cat.modelData.glyph
                                            color: cat.placed ? Colors.success : Colors.focus
                                            variant: "body"
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                text: cat.modelData.label
                                                variant: "body"
                                                font.weight: Font.DemiBold
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: cat.placed ? "Already on this screen"
                                                                 : cat.modelData.detail
                                                variant: "caption"
                                                emphasis: "dim"
                                                elide: Text.ElideRight
                                            }
                                        }
                                        StyledText {
                                            text: cat.placed ? "\u{F012C}" : "\u{F0415}"
                                            variant: "title"
                                            color: cat.placed ? Colors.success
                                                 : catMouse.containsMouse ? Colors.primary
                                                                          : Colors.fgDim
                                        }
                                    }
                                }
                            }
                    }
                    }

                    Scrollbar { flickable: galleryFlick }
                }
            }
        }

        // ══ PLACED ════════════════════════════════════════════════════════════
        Surface {
            Layout.preferredWidth: 340
            Layout.fillWidth: false
            Layout.fillHeight: true
            elevation: Tokens.elevationCard

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXl
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "On your desktop"; variant: "title"; font.bold: true }
                        StyledText {
                            text: DesktopWidgets.widgets.length === 0 ? "Nothing placed yet"
                                : DesktopWidgets.widgets.length === 1 ? "1 widget"
                                : DesktopWidgets.widgets.length + " widgets"
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }

                    PanelButton {
                        variant: "primary"
                        glyph: "󰆾"
                        label: "Arrange on desktop"
                        enabled: DesktopWidgets.widgets.length > 0
                        // Closes the overview on the way out — this page is inside an
                        // overlay covering the desktop being arranged.
                        onActivated: UiState.startArranging()
                    }
                }

                Divider { Layout.fillWidth: true }

                StyledText {
                    Layout.fillWidth: true
                    visible: DesktopWidgets.widgets.length === 0
                    text: "Pick something from the left. Widgets sit behind your windows, "
                        + "so they're visible whenever the desktop is."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: placedCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: placedCol
                        width: parent.width
                        spacing: Tokens.spacingSm

                        Repeater {
                            model: DesktopWidgets.widgets

                            Surface {
                                id: pw
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: pwRow.implicitHeight + Tokens.spacingMd * 2
                                elevation: Tokens.elevationNested
                                cornerRadius: Tokens.radiusSm
                                focused: pwMouse.containsMouse || root.selectedId === pw.modelData.id

                                readonly property var meta: DesktopWidgets.info(pw.modelData.type)

                                MouseArea {
                                    id: pwMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedId = pw.modelData.id
                                }

                                RowLayout {
                                    id: pwRow
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingMd
                                    spacing: Tokens.spacingMd

                                    // A live thumbnail of THIS widget — its size, its
                                    // options, its accent — so the row shows the thing
                                    // you placed rather than a generic type icon.
                                    //
                                    // In a FIXED slot, centred: a medium widget scales
                                    // to ~104 wide and a small one to ~58, so letting
                                    // the preview size the cell made every row a
                                    // different width and pushed the ✕ on the wide ones
                                    // past the card's edge.
                                    Item {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth:  104
                                        Layout.preferredHeight: 58

                                        WidgetPreview {
                                            anchors.centerIn: parent
                                            type:   pw.modelData.type
                                            size:   pw.modelData.size
                                            opts:   pw.modelData.opts
                                            accent: Colors.role(pw.modelData.opts.accent ?? "",
                                                                Colors.primary)
                                            boxWidth: 104
                                            maxHeight: 58
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        // Both lines MUST fillWidth and elide. Without
                                        // it a ColumnLayout's minimum width is its
                                        // widest child's implicit width, so a longer
                                        // detail line ("medium · 200, 16") forced the
                                        // row wider than the card and pushed the ✕ off
                                        // the edge — visible on exactly the rows whose
                                        // coordinates had grown an extra digit.
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: pw.meta ? pw.meta.label : pw.modelData.type
                                            variant: "body"
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: pw.modelData.screen + "  ·  "
                                                  + pw.modelData.size + "  ·  "
                                                  + pw.modelData.x + ", " + pw.modelData.y
                                            variant: "caption"
                                            emphasis: "dim"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    PanelButton {
                                        variant: "ghost"
                                        glyph: "󰅖"
                                        onActivated: {
                                            if (root.selectedId === pw.modelData.id)
                                                root.selectedId = -1
                                            DesktopWidgets.remove(pw.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ══ SETTINGS ══════════════════════════════════════════════════════════
        Surface {
            Layout.preferredWidth: 380
            Layout.fillWidth: false
            Layout.fillHeight: true
            elevation: Tokens.elevationCard

            Flickable {
                id: setFlick
                anchors.fill: parent
                anchors.margins: Tokens.spacingXl
                contentHeight: setCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: setCol
                    width: parent.width
                    spacing: Tokens.spacingMd

                    StyledText { text: "Settings"; variant: "title"; font.bold: true }

                    // ── Global ────────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText { text: "Show widgets"; variant: "body" }
                            StyledText {
                                text: "Hides every widget without removing them"
                                variant: "caption"; emphasis: "dim"
                            }
                        }
                        Toggle {
                            checked: Config.widgetsEnabled
                            onToggled: Config.widgetsEnabled = !Config.widgetsEnabled
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: "Snap grid"; variant: "body" }
                            StyledText {
                                text: Config.widgetGrid + " px"
                                variant: "caption"; emphasis: "muted"
                            }
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            value: Config.widgetGrid
                            maximum: 100
                            // 10px floor: below that it stops being a grid and two
                            // widgets never quite line up.
                            onMoved: function (v) { Config.widgetGrid = Math.max(10, Math.round(v / 5) * 5) }
                        }
                    }

                    // ── Material ──────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText { text: "Liquid glass"; variant: "body" }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Graded fill, a lit rim and a soft sheen. Off is a "
                                    + "plain translucent tile."
                                variant: "caption"
                                emphasis: "dim"
                                wrapMode: Text.WordWrap
                            }
                        }
                        Toggle {
                            checked: Config.widgetGlass
                            onToggled: Config.widgetGlass = !Config.widgetGlass
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: "Tile opacity"; variant: "body" }
                            StyledText {
                                text: Math.round(Config.widgetOpacity * 100) + "%"
                                variant: "caption"; emphasis: "muted"
                            }
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            value: Config.widgetOpacity
                            maximum: 1.0
                            // Floored at 0.2: below that the tile stops reading as a
                            // surface and the text appears to float on the wallpaper.
                            onMoved: function (v) { Config.widgetOpacity = Math.max(0.2, v) }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: "Corner roundness"; variant: "body" }
                            StyledText {
                                text: Config.widgetRoundness + " px"
                                variant: "caption"; emphasis: "muted"
                            }
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            value: Config.widgetRoundness
                            maximum: 44
                            onMoved: function (v) { Config.widgetRoundness = Math.round(v) }
                        }
                    }

                    Divider { Layout.fillWidth: true }

                    // ── Weather ───────────────────────────────────────────────
                    StyledText { text: "Weather"; variant: "body"; font.bold: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: Config.weatherPlace === ""
                              ? "Search for your city. The shell only ever requests a "
                                + "forecast for the coordinate you pick — your location is "
                                + "never looked up from your IP."
                              : "Showing weather for " + Config.weatherPlace
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }

                    Surface {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        elevation: Tokens.elevationNested
                        cornerRadius: Tokens.radiusSm
                        focused: cityField.activeFocus

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingSm

                            StyledText { text: "󰍉"; variant: "caption"; emphasis: "dim" }

                            TextInput {
                                id: cityField
                                Layout.fillWidth: true
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontLabel
                                color: Colors.fg
                                selectionColor: Colors.alpha(Colors.primary, 0.35)
                                selectByMouse: true
                                clip: true

                                // Searched on Enter rather than per keystroke: this is a
                                // network request, and firing one per character would be
                                // both wasteful and rude to a free endpoint.
                                onAccepted: Weather.search(cityField.text)

                                StyledText {
                                    anchors.fill: parent
                                    visible: cityField.text === ""
                                    text: "City name, then Enter"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }

                            StyledText {
                                visible: Weather.searching
                                text: "…"
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: Weather.results

                            Surface {
                                id: res
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: resCol.implicitHeight + Tokens.spacingSm * 2
                                elevation: Tokens.elevationNested
                                cornerRadius: Tokens.radiusXs
                                focused: resMouse.containsMouse

                                MouseArea {
                                    id: resMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Config.weatherLat   = res.modelData.lat
                                        Config.weatherLon   = res.modelData.lon
                                        Config.weatherPlace = res.modelData.name
                                        Weather.results     = []
                                        cityField.text      = ""
                                    }
                                }

                                ColumnLayout {
                                    id: resCol
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingSm
                                    spacing: 0
                                    StyledText { text: res.modelData.name; variant: "caption" }
                                    StyledText {
                                        text: res.modelData.detail
                                        variant: "caption"; emphasis: "dim"
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd
                        StyledText { Layout.fillWidth: true; text: "Use °C"; variant: "body" }
                        Toggle {
                            checked: Config.weatherMetric
                            onToggled: Config.weatherMetric = !Config.weatherMetric
                        }
                    }

                    Divider { Layout.fillWidth: true }

                    // ── Presets ───────────────────────────────────────────────
                    StyledText { text: "Layouts"; variant: "body"; font.bold: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Save the current arrangement, including what's written in "
                            + "your notes, and switch back to it later."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: DesktopWidgets.presetNames

                            Surface {
                                id: pr
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                elevation: Tokens.elevationNested
                                cornerRadius: Tokens.radiusXs
                                focused: prMouse.containsMouse

                                MouseArea {
                                    id: prMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: DesktopWidgets.applyPreset(pr.modelData,
                                                                          root.targetScreen)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingSm
                                    spacing: Tokens.spacingSm

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pr.modelData
                                        variant: "caption"
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: DesktopWidgets.presets[pr.modelData].length + " widgets"
                                        variant: "caption"
                                        emphasis: "dim"
                                    }
                                    // Its own target, so loading and deleting can't be
                                    // confused for one another.
                                    PanelButton {
                                        variant: "ghost"
                                        glyph: "\u{F0156}"
                                        onActivated: DesktopWidgets.deletePreset(pr.modelData)
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        Surface {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            elevation: Tokens.elevationNested
                            cornerRadius: Tokens.radiusSm
                            focused: presetName.activeFocus

                            TextInput {
                                id: presetName
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.spacingMd
                                anchors.rightMargin: Tokens.spacingMd
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontLabel
                                color: Colors.fg
                                selectionColor: Colors.alpha(Colors.primary, 0.35)
                                selectByMouse: true
                                clip: true
                                onAccepted: {
                                    DesktopWidgets.savePreset(presetName.text)
                                    presetName.text = ""
                                }

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: presetName.text === ""
                                    text: "Name this layout"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                        }

                        PanelButton {
                            // Says which it will do before you click, rather than
                            // confirming after — the same call as the colour panel's
                            // save button.
                            variant: "primary"
                            label: DesktopWidgets.presetNames.indexOf(presetName.text.trim()) !== -1
                                   ? "Overwrite" : "Save"
                            enabled: presetName.text.trim() !== ""
                                     && DesktopWidgets.widgets.length > 0
                            onActivated: {
                                DesktopWidgets.savePreset(presetName.text)
                                presetName.text = ""
                            }
                        }
                    }

                    Divider { Layout.fillWidth: true }

                    // ── Selected widget ───────────────────────────────────────
                    StyledText {
                        text: root.selected
                              ? (DesktopWidgets.info(root.selected.type)?.label ?? "Widget")
                              : "No widget selected"
                        variant: "body"
                        font.bold: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.selected
                        text: "Pick one from the middle column to change its size and options."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected
                        spacing: Tokens.spacingSm

                        StyledText { text: "Size"; variant: "caption"; emphasis: "muted" }
                        Item { Layout.fillWidth: true }

                        Repeater {
                            model: root.selected
                                   ? (DesktopWidgets.info(root.selected.type)?.sizes ?? [])
                                   : []
                            PanelButton {
                                required property var modelData
                                variant: (root.selected && root.selected.size === modelData)
                                         ? "primary" : "normal"
                                label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                onActivated: DesktopWidgets.setSize(root.selectedId, modelData)
                            }
                        }
                    }

                    // ── Accent ────────────────────────────────────────────────
                    // Role names, never hex — the same rule the bar's per-module accent
                    // follows. A literal colour pinned here would outlive every future
                    // wallpaper, which is what the palette exists to prevent.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected
                        spacing: Tokens.spacingXs

                        StyledText { text: "Accent"; variant: "caption"; emphasis: "muted" }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            Repeater {
                                model: Config.accentRoles

                                Rectangle {
                                    id: swatch
                                    required property var modelData
                                    readonly property bool chosen:
                                        !!root.selected
                                        && (root.selected.opts.accent ?? "") === swatch.modelData.id
                                    readonly property color shade:
                                        Colors.role(swatch.modelData.id, Colors.fgDim)

                                    width: 26; height: 26
                                    radius: Tokens.radiusFull
                                    color: swatch.modelData.id === "" ? "transparent" : swatch.shade
                                    border.width: swatch.chosen ? 2 : Tokens.borderWidth
                                    border.color: swatch.chosen ? Colors.fg
                                                                : Colors.alpha(Colors.fg, 0.3)

                                    // "Default" has no colour of its own to show, so it
                                    // gets a glyph rather than an empty circle that
                                    // reads as a rendering failure.
                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: swatch.modelData.id === ""
                                        text: "\u{F0156}"
                                        variant: "caption"
                                        color: Colors.fgDim
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DesktopWidgets.setOpt(root.selectedId,
                                                                         "accent",
                                                                         swatch.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Clock-only options. Rendered from the selected widget's type
                    // rather than always present-but-disabled: a permanently greyed
                    // "Show seconds" under a calendar is noise.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "clock"
                        spacing: Tokens.spacingMd
                        StyledText { Layout.fillWidth: true; text: "24-hour clock"; variant: "body" }
                        Toggle {
                            checked: !!root.selected && root.selected.opts.hour24 !== false
                            onToggled: DesktopWidgets.setOpt(root.selectedId, "hour24",
                                                             !(root.selected.opts.hour24 !== false))
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "clock"
                        spacing: Tokens.spacingMd
                        StyledText { Layout.fillWidth: true; text: "Show seconds"; variant: "body" }
                        Toggle {
                            checked: !!root.selected && root.selected.opts.seconds === true
                            onToggled: DesktopWidgets.setOpt(root.selectedId, "seconds",
                                                             !(root.selected.opts.seconds === true))
                        }
                    }

                    // ── Timer ─────────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "timer"
                        spacing: Tokens.spacingMd
                        StyledText { Layout.fillWidth: true; text: "Stopwatch"; variant: "body" }
                        Toggle {
                            checked: !!root.selected && root.selected.opts.stopwatch === true
                            onToggled: DesktopWidgets.setOpt(root.selectedId, "stopwatch",
                                                             !(root.selected.opts.stopwatch === true))
                        }
                    }

                    // ── Photo frame ───────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "photo"
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: "Change every"; variant: "body" }
                            StyledText {
                                text: (root.selected ? (root.selected.opts.seconds ?? 30) : 30) + "s"
                                variant: "caption"
                                emphasis: "muted"
                            }
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            // 10s to 5 minutes. Below ten the cross-fade barely finishes
                            // before the next one starts; above five minutes it stops
                            // being a photo FRAME and becomes a second wallpaper.
                            maximum: 1
                            value: {
                                const s = root.selected ? (root.selected.opts.seconds ?? 30) : 30
                                return Math.max(0, Math.min(1, (s - 10) / 290))
                            }
                            onMoved: function (v) {
                                DesktopWidgets.setOpt(root.selectedId, "seconds",
                                                      Math.round(10 + v * 290))
                            }
                        }
                    }

                    // ── Disk ──────────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "disk"
                        spacing: Tokens.spacingXs

                        StyledText { text: "Mount point"; variant: "caption"; emphasis: "muted" }
                        OptField {
                            Layout.fillWidth: true
                            placeholder: "/"
                            // Read on focus rather than bound: a binding would rewrite
                            // the field from the stored value after every keystroke.
                            seed: root.selected ? (root.selected.opts.mount ?? "/") : "/"
                            onCommitted: function (t) {
                                DesktopWidgets.setOpt(root.selectedId, "mount",
                                                      t.trim() === "" ? "/" : t.trim())
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "A path from the Storage page — \"/\" or \"/home\"."
                            variant: "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ── Countdown ─────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "countdown"
                        spacing: Tokens.spacingXs

                        StyledText { text: "What for"; variant: "caption"; emphasis: "muted" }
                        OptField {
                            Layout.fillWidth: true
                            placeholder: "Holiday"
                            seed: root.selected ? (root.selected.opts.label ?? "") : ""
                            onCommitted: function (t) {
                                DesktopWidgets.setOpt(root.selectedId, "label", t.trim())
                            }
                        }

                        StyledText {
                            Layout.topMargin: Tokens.spacingXs
                            text: "Date"; variant: "caption"; emphasis: "muted"
                        }
                        OptField {
                            id: cdDate
                            Layout.fillWidth: true
                            placeholder: "2026-12-25"
                            seed: root.selected ? (root.selected.opts.date ?? "") : ""
                            // Rejected rather than corrected. There is no sensible guess
                            // at what "25/12" means (day-first or month-first changes the
                            // answer), so the field says what it wants and keeps what you
                            // typed until it matches.
                            readonly property bool valid:
                                cdDate.text === "" || /^\d{4}-\d{2}-\d{2}$/.test(cdDate.text)
                            invalid: !cdDate.valid
                            onCommitted: function (t) {
                                if (/^\d{4}-\d{2}-\d{2}$/.test(t.trim()) || t.trim() === "")
                                    DesktopWidgets.setOpt(root.selectedId, "date", t.trim())
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Year-month-day, like 2026-12-25."
                            variant: "caption"
                            // The hint IS the error message when the field doesn't
                            // match — a second line appearing below would push the
                            // column around every time you mistype a digit.
                            color: cdDate.valid ? Colors.fgDim : Colors.danger
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ── World clock ───────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.type === "worldclock"
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd
                            StyledText { Layout.fillWidth: true; text: "24-hour clock"; variant: "body" }
                            Toggle {
                                checked: !!root.selected && root.selected.opts.hour24 !== false
                                onToggled: DesktopWidgets.setOpt(root.selectedId, "hour24",
                                                                 !(root.selected.opts.hour24 !== false))
                            }
                        }

                        StyledText {
                            Layout.topMargin: Tokens.spacingXs
                            text: "Cities"; variant: "caption"; emphasis: "muted"
                        }

                        Repeater {
                            model: root.selected && root.selected.type === "worldclock"
                                   ? (root.selected.opts.zones ?? []) : []
                            RowLayout {
                                id: zoneEdit
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Tokens.spacingXs

                                OptField {
                                    Layout.fillWidth: true
                                    placeholder: "City"
                                    seed: zoneEdit.modelData.label ?? ""
                                    onCommitted: function (t) {
                                        DesktopWidgets.setZone(root.selectedId, zoneEdit.index,
                                                               "label", t.trim())
                                    }
                                }
                                OptField {
                                    Layout.preferredWidth: 58
                                    placeholder: "+0"
                                    // The offset is stored as a NUMBER of hours, so a
                                    // half-hour zone (India, +5.5) is expressible — which
                                    // it would not be if this were an integer field.
                                    seed: {
                                        const o = zoneEdit.modelData.offset ?? 0
                                        return (o >= 0 ? "+" : "") + o
                                    }
                                    onCommitted: function (t) {
                                        const n = parseFloat(t)
                                        if (!isNaN(n) && n >= -12 && n <= 14)
                                            DesktopWidgets.setZone(root.selectedId, zoneEdit.index,
                                                                   "offset", n)
                                    }
                                }
                                PanelButton {
                                    variant: "ghost"
                                    glyph: "\u{F0156}"
                                    onActivated: DesktopWidgets.removeZone(root.selectedId,
                                                                           zoneEdit.index)
                                }
                            }
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            variant: "ghost"
                            label: "Add city"
                            onActivated: DesktopWidgets.addZone(root.selectedId, "New city", 0)
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Offsets are hours from UTC, so one crossing a daylight-"
                                + "saving change needs editing twice a year."
                            variant: "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // The per-type option blocks made this the tallest column, and a world clock
            // with a dozen cities is genuinely longer than the pane. Anchored across the
            // Surface, which is a plain item — no wrapper needed here, unlike the gallery.
            Scrollbar { flickable: setFlick }
        }
    }

    // ── OptField ──────────────────────────────────────────────────────────────
    // A one-line text box for a widget option. Local to this page rather than promoted
    // to `components/`: it exists because five option blocks needed the same Surface +
    // TextInput pairing, and one page's repetition is not yet shared vocabulary.
    //
    // `seed` is applied on construction and whenever it changes WHILE UNFOCUSED. Binding
    // `text` straight to the stored value is the trap — every keystroke writes, the write
    // comes back, and the field fights the person typing in it.
    component OptField: Surface {
        id: field
        property string placeholder: ""
        property string seed: ""
        property bool invalid: false
        readonly property alias text: input.text
        signal committed(string value)

        // No `Layout.fillWidth` here: the offset box sizes itself with
        // `Layout.preferredWidth`, and a fillWidth baked into the component would
        // override it every time.
        implicitHeight: 30
        elevation: Tokens.elevationNested
        cornerRadius: Tokens.radiusSm
        focused: input.activeFocus
        border.color: field.invalid ? Colors.danger
                    : input.activeFocus ? Colors.outlineFocus
                    : Colors.outlineFor(field.elevation)

        onSeedChanged: if (!input.activeFocus) input.text = field.seed
        Component.onCompleted: input.text = field.seed

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            verticalAlignment: TextInput.AlignVCenter
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLabel
            color: Colors.fg
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectByMouse: true
            clip: true

            // Committed on Enter AND on losing focus. Enter alone loses an edit you
            // finished by clicking elsewhere, which is how most fields are left.
            onAccepted: field.committed(input.text)
            onActiveFocusChanged: if (!input.activeFocus) field.committed(input.text)

            StyledText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text === ""
                text: field.placeholder
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
