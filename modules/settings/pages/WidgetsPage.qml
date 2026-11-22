pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../desktop/widgets"
import ".."
import "widgets"

// ── WidgetsPage — Desktop › Widgets ───────────────────────────────────────────
// Your desktop widgets, and how they all look: grouped rows in two columns under the map, no modes.
// Every job is a group, in the order you reach for them.
//
// ── The map is the page ───────────────────────────────────────────────────────
// The loud card is the screen with every widget where it really is (DesktopMap: drag one to
// move it, click one to pick it), the map on the left and the page's master switch beside it. Under it: "On this screen" (which widgets, the picked one's size,
// move / remove), then the picked widget's own options (WidgetsOptionsSection, and the photo frame's
// two groups). With nothing placed those groups stay away and the gallery is the page.
//
// ── Adding ────────────────────────────────────────────────────────────────────
// "Add widget" in the header opens the gallery group at the top of the scroll; you pick one and land
// back with it selected. A request plus a derived state, not one assignable bool: with nothing placed
// the gallery IS the page, and an assignment would break that binding.
//
// ── Style, calendars, presets ─────────────────────────────────────────────────
// Style is what every widget shares: the tile look (and its four switches), opacity, roundness,
// parallax, snap grid. Per-widget opacity / roundness / glass / accent overrides were removed: every
// tile follows this. `DesktopWidgets.setOpt(id, "opacity"|…)` still works (presets round-trip it),
// there is just no per-widget control. Calendars feed the clock panel. Presets is two related but
// separate ideas the old UI both called "layout" (see WidgetsPresetsSection). The weather place is set
// in System › Language & region; a link row here opens it.
//
// ── Arranging happens on the DESKTOP, not here ────────────────────────────────
// A 400px map of a 1920px desktop can't show whether a widget covers the thing you keep
// behind it. "Arrange" puts the real widgets on the real wallpaper.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in widgets/.
    property alias photoPicker: photoPicker
    property alias undoBar: undoBar

    // The placed widget being edited, held as an ID — the store replaces every record
    // on each change, so an index or a record would go stale immediately.
    property int selectedId: -1
    readonly property var selected: DesktopWidgets.get(root.selectedId)

    // Adding: a request plus a derived state (see the header).
    property bool _addRequested: false
    readonly property bool adding: root._addRequested || DesktopWidgets.shown.length === 0

    // Where a newly placed widget lands. A widget on a screen you're not looking at
    // looks exactly like one that failed to place, so multi-monitor users pick.
    property string targetScreen:
        Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""

    // Which screen the desktop map shows: the selected widget's, until you pick one.
    property string mapScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    onSelectedIdChanged: if (root.selected) root.mapScreen = root.selected.screen

    // Which screen a saved layout is applied to (the map's screen, until picked).
    property string layoutScreen:
        Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""

    property string gallerySearch: ""
    readonly property var filteredCatalogue: {
        const q = root.gallerySearch.trim().toLowerCase()
        if (q === "") return DesktopWidgets.catalogue
        return DesktopWidgets.catalogue.filter(c =>
            c.label.toLowerCase().indexOf(q) !== -1
            || c.detail.toLowerCase().indexOf(q) !== -1
            || c.category.toLowerCase().indexOf(q) !== -1)
    }
    readonly property int galPageSize:  6
    readonly property int galPageCount: Math.max(1, Math.ceil(root.filteredCatalogue.length / root.galPageSize))
    onGallerySearchChanged: widgetsCatalogueSection.galPager.currentIndex = 0

    // ── Moving a placed widget to another screen ─────────────────────────────
    // One menu for the whole page, not a ContextMenu built per row.
    property int _screenMenuTarget: -1
    function openScreenMenu(anchorItem, widgetId, currentScreen) {
        root._screenMenuTarget = widgetId
        screenMenu.items = Quickshell.screens
            .filter(s => s.name !== currentScreen)
            .map(s => ({ key: s.name, label: s.name }))
        const p = anchorItem.mapToItem(root, 0, anchorItem.height)
        screenMenu.openAt(p.x, p.y)
    }


    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰕮"
        title:     Translation.tr("Desktop")
        titleTail: root.adding ? "gallery" : "widgets"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.adding
                   ? Translation.tr("Pick a widget, it drops onto the wallpaper")
                   : (Config.widgetsEnabled
                      ? Translation.tr("%1 on your desktop").arg(DesktopWidgets.shown.length)
                      : Translation.tr("Hidden, still placed"))

        // Removing a widget throws away its size, position and options — all of which are in
        // the record, so it can be put back exactly.
        banner: UndoBar { id: undoBar }

        actions: [
            ChipTray {
                ChipButton {
                    visible: DesktopWidgets.shown.length > 0
                    symbol:  root.adding ? "close" : "add"
                    label:   root.adding ? Translation.tr("Done") : Translation.tr("Add widget")
                    on:      !root.adding
                    tint:    Colors.of(QsWindow.window).primary
                    onActivated: root._addRequested = !root._addRequested
                }
                ChipButton {
                    symbol:  "open_with"
                    label:   Translation.tr("Arrange")
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: DesktopWidgets.shown.length > 0
                    onActivated: UiState.startArranging()
                }
            }
        ]

        // ══ The gallery (adding) ══════════════════════════════════════════════
        WidgetsCatalogueSection {
            id: widgetsCatalogueSection
            page: root
        }

        // ══ Your desktop: the map, the live subject ═══════════════════════════
        WidgetsDesktopSection { page: root }

        // ══ Which widget, and what you do to it ═══════════════════════════════
        WidgetsPickedSection { page: root }

        // ══ The picked widget's own options ═══════════════════════════════════
        WidgetsOptionsSection { page: root }
        WidgetsPhotoSection { page: root }
        WidgetsPhotoLookSection { page: root }

        // ══ Style: what every widget shares ═══════════════════════════════════
        Section {
            grouped:  true
            symbol:   "palette"
            title:    Translation.tr("Style")
            subtitle: Translation.tr("Every widget")

            actions: ChipTray {
                ChipButton {
                    symbol: "restart_alt"
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: Config.resetWidgetsAppearance()
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Liquid glass")
                detail: Config.widgetGlass ? Translation.tr("Graded fill, lit rim and a sheen")
                                           : Translation.tr("Plain translucent tile")
                help:   Translation.tr("A graded fill, a lit rim and a sheen, instead of a plain translucent tile.")
                onTapped: Config.widgetGlass = !Config.widgetGlass

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.widgetGlass
                    onToggled: Config.widgetGlass = !Config.widgetGlass
                }
            }
            // The only thing that reads this one is WidgetFrame, so it lives with the widgets
            // (its Config name, barHoverGrow, is from when it sat on Bar › Style).
            SettingRow {
                rowTap: true
                label:  Translation.tr("Grow on hover")
                detail: Config.barHoverGrow ? Translation.tr("Swells a little under the pointer")
                                            : Translation.tr("Stays put")
                help:   Translation.tr("A widget swells a little under the pointer.")
                onTapped: Config.barHoverGrow = !Config.barHoverGrow

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.barHoverGrow
                    onToggled: Config.barHoverGrow = !Config.barHoverGrow
                }
            }
            // "Parallax tilt" here and "Parallax strength" below, so the two controls are not both just "Parallax".
            SettingRow {
                rowTap: true
                label:  Translation.tr("Parallax tilt")
                detail: Config.widgetParallax ? Translation.tr("Leans under the pointer") : Translation.tr("Stays flat")
                help:   Translation.tr("A widget leans under the pointer and its contents shift the other way. Hover a widget on the map to see it. How far is Parallax strength, below.")
                onTapped: Config.widgetParallax = !Config.widgetParallax

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.widgetParallax
                    onToggled: Config.widgetParallax = !Config.widgetParallax
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Entrance")
                detail: Config.widgetEntrance ? Translation.tr("Pop in one after another")
                                              : Translation.tr("Appear at once")
                help:   Translation.tr("Widgets pop in one after another when the desktop loads or one is added.")
                onTapped: Config.widgetEntrance = !Config.widgetEntrance

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.widgetEntrance
                    onToggled: Config.widgetEntrance = !Config.widgetEntrance
                }
            }

            Fader {
                label: Translation.tr("Opacity")
                accent: Colors.of(QsWindow.window).primary
                from: 0.2; to: 1.0; step: 0.01
                value: Config.widgetOpacity
                readout: Math.round(Config.widgetOpacity * 100) + "%"
                onCommit: function (v) { Config.widgetOpacity = Math.max(0.2, v) }
            }
            Fader {
                label: Translation.tr("Roundness")
                accent: Colors.of(QsWindow.window).primary
                from: 0; to: 44
                value: Config.widgetRoundness
                readout: Config.widgetRoundness + " px"
                onCommit: function (v) { Config.widgetRoundness = Math.round(v) }
            }
            Fader {
                label: Translation.tr("Parallax strength")
                help:  Translation.tr("How far a widget leans and its contents shift under the pointer. Needs Parallax tilt on.")
                accent: Colors.of(QsWindow.window).primary
                enabled: Config.widgetParallax
                opacity: Config.widgetParallax ? 1 : 0.4
                from: 0.25; to: 2.0; step: 0.05
                value: Config.widgetParallaxStrength
                readout: Math.round(Config.widgetParallaxStrength * 100) + "%"
                onCommit: function (v) { Config.widgetParallaxStrength = Math.max(0.25, Math.round(v * 20) / 20) }
            }
            Fader {
                label: Translation.tr("Snap grid")
                help:  Translation.tr("Widgets you drag snap to this grid.")
                accent: Colors.of(QsWindow.window).primary
                from: 10; to: 100; step: 5
                value: Config.widgetGrid
                readout: Config.widgetGrid + " px"
                onCommit: function (v) { Config.widgetGrid = Math.max(10, Math.round(v / 5) * 5) }
            }
        }

        // ══ Weather: set in System › Language & region ═══════════════════════
        // Night light's "follow the sun" and the calendar's holidays read the same place, so it is set once,
        // there. This row is the way to it.
        Section {
            grouped:  true
            symbol:   "wb_sunny"
            title:    Translation.tr("Weather")
            subtitle: Config.weatherPlace === "" ? Translation.tr("No location set") : Config.weatherPlace

            SettingRow {
                rowTap: true
                label:  Translation.tr("Weather location")
                detail: Config.weatherPlace !== "" ? Config.weatherPlace : Translation.tr("Not set")
                help:   Translation.tr("Only the place you pick is ever requested. Your location is never looked up from your IP. Night light and the calendar use it too.")
                onTapped: UiState.openSettingsTo("LanguagePage.qml")

                MaterialIcon {
                    name: "chevron_right"
                    color: Colors.of(QsWindow.window).fgDim
                }
            }
        }

        // ══ Layout presets ════════════════════════════════════════════════════
        WidgetsPresetsSection {
            id: presetSection
            page: root
        }

        // ══ Calendars ═════════════════════════════════════════════════════════
        // Subscribed calendars for the clock panel: any .ics address, read-only, each in a colour
        // of its own (a palette role). The fetching, the queue and the checks are Calendar's; this
        // lists them and takes a new one.
        Section {
            id: calSection
            grouped:  true
            symbol:   "calendar_month"
            title:    Translation.tr("Calendars")
            subtitle: Calendar.feeds.length === 0 ? Translation.tr("Just your own")
                                                  : Translation.tr("%1 subscribed").arg(Calendar.feeds.length)
            help:     Translation.tr("Paste a calendar's .ics address (Google: your calendar's settings › Secret address in iCal format) and its events show in the clock panel, read-only, in a colour of their own. The address stays on this machine.")

            // Nothing is fetched unless something holds the service; this page does while it is open,
            // so a feed you just added shows its state (and any error) here.
            Component.onCompleted:   Calendar.acquire()
            Component.onDestruction: Calendar.release()

            property string feedError: ""

            Repeater {
                model: Calendar.feeds

                delegate: RowLayout {
                    id: feed
                    required property var modelData
                    readonly property var st: Calendar.stateOf(feed.modelData.id)
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    // The colour: click for the next one.
                    Rectangle {
                        Layout.preferredWidth:  Tokens.iconMd
                        Layout.preferredHeight: Tokens.iconMd
                        radius: width / 2
                        color: Colors.of(QsWindow.window).role(feed.modelData.color, Colors.of(QsWindow.window).primary)
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const roles = Calendar.feedRoles
                                Calendar.setFeedColor(feed.modelData.id, roles[(roles.indexOf(feed.modelData.color) + 1) % roles.length])
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: feed.modelData.name; variant: "label"; elide: Text.ElideRight }
                        StyledText {
                            Layout.fillWidth: true
                            variant: "caption"
                            elide: Text.ElideRight
                            text: feed.st.state === "loading" ? Translation.tr("Fetching…")
                                : feed.st.state === "error"   ? Translation.tr("Couldn't reach it")
                                : feed.st.state === "ok"      ? (feed.st.count === 1 ? Translation.tr("1 event")
                                                                                     : Translation.tr("%1 events").arg(feed.st.count))
                                :                               Translation.tr("Not fetched yet")
                            color: feed.st.state === "error" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                        }
                    }
                    PanelButton {
                        capsule: true
                        variant: "ghost"
                        symbol:  "close"
                        accent:  Colors.of(QsWindow.window).danger
                        onActivated: Calendar.removeFeed(feed.modelData.id)
                    }
                }
            }

            // Adding one: a name, the address, and the button that takes both.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    cornerRadius: implicitHeight / 2
                    id: feedName
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Name (optional)")
                }
                InputField {
                    cornerRadius: implicitHeight / 2
                    id: feedUrl
                    Layout.fillWidth: true
                    placeholder: "https://… .ics"
                    invalid: calSection.feedError !== ""
                    onEdited: calSection.feedError = ""
                    onAccepted: addFeed.activated()
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: calSection.feedError
                        variant: "caption"
                        color: Colors.of(QsWindow.window).danger
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillWidth: true; visible: calSection.feedError === "" }
                    PanelButton {
                        capsule: true
                        id: addFeed
                        variant: "primary"
                        accent:  Colors.of(QsWindow.window).primary
                        symbol:  "add"
                        label:   Translation.tr("Add")
                        enabled: feedUrl.text.trim() !== ""
                        onActivated: {
                            calSection.feedError = Calendar.addFeed(feedName.text, feedUrl.text)
                            if (calSection.feedError === "") { feedName.clear(); feedUrl.clear() }
                        }
                    }
                }
            }
        }
    }

    // ── Screen picker menu ─────────────────────────────────────────────────
    ContextMenu {
        id: screenMenu
        anchors.fill: parent

        onTriggered: function (key) {
            if (root._screenMenuTarget !== -1) {
                const scr = Quickshell.screens.find(s => s.name === key)
                DesktopWidgets.setScreen(root._screenMenuTarget, key,
                    scr ? scr.width : 1920, scr ? scr.height : 1080)
            }
            root._screenMenuTarget = -1
        }
    }

    // The photo frame's picture/folder browser, over the whole page. Stores the choice
    // `~`-relative (DesktopWidgets.contractPath): presets are saved into the published repo.
    ImagePicker {
        id: photoPicker
        anchors.fill: parent
        onPicked: function (path) {
            DesktopWidgets.setOpt(root.selectedId, "image", DesktopWidgets.contractPath(path))
        }
        onPickedFolder: function (path) {
            DesktopWidgets.setOpt(root.selectedId, "folder", DesktopWidgets.contractPath(path))
        }
    }
}
