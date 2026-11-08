pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../desktop/widgets"
import "../../desktop/widgets/toggles.js" as Toggles
import ".."
import "widgets"

// ── WidgetsPage — Desktop › Widgets ───────────────────────────────────────────
// Your desktop widgets, and how they all look — one page, one file, three jobs picking
// a widget to place/edit, the shell-wide look, and everything that feeds a widget's
// content (weather, calendars, presets). It used to be two views (a big map that
// swallowed the page, and a Style tab a click away from the thing it changed), then one
// view with all five jobs stacked in a bento grid — correct dialect, but a scroll of
// unrelated cards. A header `TabStrip` (Desktop · Style · Content, `root.viewMode`)
// swaps the body between them instead, the same header-takes-over-the-body idea as the
// catalogue below, so it stays one file without pushing the Desktop page's view count up.
//
// ── Desktop: the map is small, and sits beside the widget's own settings ──────
// "Your desktop" is a card: the screen, small, with every widget where it really is
// (DesktopMap — drag one to move it, click one to pick it) and, beside it, the picked
// widget's settings in place — its size, its type's options, move / remove. Nothing picked:
// the widgets on this screen as chips, to pick from.
//
// Adding is a MODE within Desktop: "Add widget" swaps the card for the catalogue; you pick
// one, and land back with it selected. With nothing placed yet the catalogue is simply what
// is shown, and the mode switch is moot (there's nothing to view in Style/Content either
// until something's placed — they stay reachable, they're just empty).
//
// ── Style: what every widget shares ────────────────────────────────────────────
// The tile look (and its four switches), opacity, roundness, parallax, snap grid. Per-widget
// opacity / roundness / glass / accent overrides were removed — every tile follows this.
// `DesktopWidgets.setOpt(id, "opacity"|…)` still works (presets round-trip it), there is
// just no per-widget control.
//
// ── Content: what feeds a widget, plus Presets ─────────────────────────────────
// Weather (shell-wide — Night light's "follow the sun" and the calendar's holidays read it
// too) and subscribed calendars feed the clock/calendar widgets. Presets is two related but
// separate ideas that the old UI both called "layout": a saved whole-desktop snapshot you
// load back later, and a wallpaper's own live widgets. See that Section's own comment.
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

    // Opens on the bare desktop: the canvas is the content, and a card over it on
    // arrival would hide what you came to look at.

    // ── Which job this page is doing ─────────────────────────────────────────
    // The view did five things stacked in one bento grid (place/edit a widget, the
    // shell-wide Look, Weather, Calendars, Presets/Per-wallpaper) — a header mode
    // switch, same idea as the catalogue takeover below, keeps it one file/one view
    // while only showing one job at a time.
    property string viewMode: "desktop"   // "desktop" | "style" | "content"

    // ── Adding ────────────────────────────────────────────────────────────────
    // A request plus a derived state, not one assignable bool: with nothing placed
    // the gallery IS the page, and an assignment would break that binding.
    property bool _addRequested: false
    readonly property bool adding: root.viewMode === "desktop"
                                    && (root._addRequested || DesktopWidgets.shown.length === 0)

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

        bento:     true
        glyph:     "󰕮"
        title:     Translation.tr("Desktop")
        titleTail: root.adding ? "gallery"
                   : root.viewMode === "style"   ? "style"
                   : root.viewMode === "content" ? "content"
                   :                               "widgets"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.adding
                   ? "Pick a widget — it drops onto the wallpaper"
                   : root.viewMode === "style"
                   ? "How every widget looks"
                   : root.viewMode === "content"
                   ? "Weather, calendars and saved presets"
                   : (Config.widgetsEnabled
                      ? DesktopWidgets.shown.length + " on your desktop"
                      : "Hidden — still placed")

        // Removing a widget throws away its size, position and options — all of which are in
        // the record, so it can be put back exactly.
        banner: UndoBar { id: undoBar }

        actions: [
            TabStrip {
                implicitWidth: 240
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "desktop", label: "Desktop", icon: "dashboard" },
                    { value: "style",   label: "Style",   icon: "palette"   },
                    { value: "content", label: "Content", icon: "tune"      }
                ]
                current: root.viewMode
                onPicked: function (v) { root.viewMode = v }
            },
            ChipTray {
                visible: root.viewMode === "desktop"
                ChipButton {
                    visible: DesktopWidgets.shown.length > 0
                    symbol:  root.adding ? "close" : "add"
                    label:   root.adding ? "Done" : "Add widget"
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
            },
            Toggle {
                accent: Colors.of(QsWindow.window).primary
                checked: Config.widgetsEnabled
                onToggled: Config.widgetsEnabled = !Config.widgetsEnabled
            }
        ]

        // ══ The catalogue (adding) ════════════════════════════════════════════
        WidgetsCatalogueSection {
            id: widgetsCatalogueSection
            page: root
        }

        // ══ Your desktop ══════════════════════════════════════════════════════
        WidgetsDesktopSection {
            id: hero
            page: root
        }

        Section {
            span:    root.viewMode === "style" ? 3 : 1
            visible: root.viewMode === "style"
            glyph:  "󰆾"
            title:  Translation.tr("Look")
            subtitle: Translation.tr("Every widget")
            accent: Colors.of(QsWindow.window).primary

            actions: ChipTray {
                ChipButton {
                    symbol: "restart_alt"
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: Config.resetWidgetsAppearance()
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                ToggleChip {
                    symbol: "blur_on"
                    label:  Translation.tr("Liquid glass")
                    hint:   Translation.tr("A graded fill, a lit rim and a sheen, instead of a plain translucent tile.")
                    active: Config.widgetGlass
                    onToggled: Config.widgetGlass = !Config.widgetGlass
                }
                // Was on Bar › Style, where its Config name (barHoverGrow) put it; the
                // only thing that reads it is WidgetFrame, so it lives with the widgets.
                ToggleChip {
                    symbol: "mouse"
                    label:  Translation.tr("Grow on hover")
                    hint:   Translation.tr("A widget swells a little under the pointer.")
                    active: Config.barHoverGrow
                    onToggled: Config.barHoverGrow = !Config.barHoverGrow
                }
                // Hover over one of the previews above to see it.
                ToggleChip {
                    symbol: "open_with"
                    label:  Translation.tr("Parallax")
                    hint:   Translation.tr("A widget leans under the pointer and its contents shift the other way. Strength is under Tile.")
                    active: Config.widgetParallax
                    onToggled: Config.widgetParallax = !Config.widgetParallax
                }
                ToggleChip {
                    symbol: "animation"
                    label:  Translation.tr("Entrance")
                    hint:   Translation.tr("Widgets pop in one after another when the desktop loads or one is added.")
                    active: Config.widgetEntrance
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
                label: Translation.tr("Parallax")
                help:  Translation.tr("How far a widget leans and its contents shift under the pointer. Off in the chips above.")
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

        // ══ Weather ═══════════════════════════════════════════════════════════
        Section {
            span:     1
            visible:  root.viewMode === "content"
            glyph:    "󰖕"
            title:    Translation.tr("Weather")
            subtitle: Config.weatherPlace === "" ? "No location set" : Config.weatherPlace
            help:     Translation.tr("Only the place you pick is ever requested — your location is never looked up from your IP. Night light and the calendar use it too.")
            accent:   Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    cornerRadius: implicitHeight / 2
                    id: cityField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("City name, then Enter")
                    // A network request — on Enter, never per keystroke.
                    onAccepted: function (v) { if (v.trim() !== "") Weather.search(v.trim()) }
                }
                BusyDot {
                    running: Weather.searching
                    visible: Weather.searching
                    tint: Colors.of(QsWindow.window).primary
                }
            }

            Repeater {
                model: Weather.results

                Rectangle {
                    id: res
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: resCol.implicitHeight + Tokens.spacingSm * 2
                    radius: Tokens.radiusSm
                    color: resHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    ColumnLayout {
                        id: resCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.spacingSm
                        anchors.rightMargin: Tokens.spacingSm
                        spacing: 0
                        StyledText { text: res.modelData.name; variant: "caption" }
                        StyledText { text: res.modelData.detail; variant: "caption"; emphasis: "dim" }
                    }

                    HoverHandler { id: resHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Config.weatherLat     = res.modelData.lat
                            Config.weatherLon     = res.modelData.lon
                            Config.weatherPlace   = res.modelData.name
                            // The calendar's special dates follow this.
                            Config.weatherCountry = res.modelData.countryCode
                            Weather.results = []
                            cityField.clear()
                        }
                    }
                }
            }

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: true,  label: "°C" },
                        { value: false, label: "°F" }]
                current: Config.weatherMetric
                onPicked: function (v) { Config.weatherMetric = v }
            }
        }

        // ══ Calendars ═════════════════════════════════════════════════════════
        // Subscribed calendars for the clock panel: any .ics address, read-only, each in a colour
        // of its own (a palette role). The fetching, the queue and the checks are Calendar's; this
        // lists them and takes a new one.
        Section {
            id: calSection
            span:     1
            visible:  root.viewMode === "content"
            glyph:    "󰃭"
            title:    Translation.tr("Calendars")
            subtitle: Calendar.feeds.length === 0 ? "Just your own" : Calendar.feeds.length + " subscribed"
            help:     Translation.tr("Paste a calendar's .ics address — Google: your calendar's settings › Secret address in iCal format — and its events show in the clock panel, read-only, in a colour of their own. The address stays on this machine.")
            accent:   Colors.of(QsWindow.window).primary

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
                            text: feed.st.state === "loading" ? "Fetching…"
                                : feed.st.state === "error"   ? "Couldn't reach it"
                                : feed.st.state === "ok"      ? feed.st.count + (feed.st.count === 1 ? " event" : " events")
                                :                               "Not fetched yet"
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

        // ══ Presets ═══════════════════════════════════════════════════════════
        // Two related but separate ideas, and the old copy called both of them
        // "layout" — the thing people couldn't tell apart. A PRESET is a named
        // snapshot you load back onto any screen, once, like Bar's own presets.
        // A wallpaper's OWN WIDGETS is live and automatic: whenever a screen shows
        // that wallpaper, its tiles replace the normal ones — no "load" step, and
        // it can start from a preset without becoming one. One card says both, in
        // that order, because starting a wallpaper's own widgets from a preset is
        // the common path (the chip row below "Start from a preset").
        WidgetsPresetsSection {
            id: presetSection
            page: root
        }
    }

    // ── Wheel = turn the gallery page ───────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: root.adding && root.galPageCount > 1

        property real acc: 0
        onWheel: function (ev) {
            acc += ev.angleDelta.y
            if (acc <= -120) { widgetsCatalogueSection.galPager.incrementCurrentIndex(); acc = 0 }
            else if (acc >= 120) { widgetsCatalogueSection.galPager.decrementCurrentIndex(); acc = 0 }
            ev.accepted = true
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

    // ── GalleryCard — one catalogue tile: live preview + name + placed state ────
    // One of each type per screen (DesktopWidgets.add hands back the existing one), so
    // the state is binary. Clicking places it if needed, selects it, and leaves the
    // gallery.
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
