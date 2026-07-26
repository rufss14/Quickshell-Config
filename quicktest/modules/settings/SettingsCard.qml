pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../../config"
import "../../components"
import "../../services"

// ── SettingsCard ──────────────────────────────────────────────────────────────
// Settings, as a card on the overview's second page rather than a window of its own.
//
// The shell already has a full-screen surface that dims the desktop, traps the
// keyboard, and closes on Escape — the overview. A settings PanelWindow would have
// been a second one of those, with its own scrim, its own key grab and its own
// drag-to-move handle, all racing the overview's. So this is just a card: it inherits
// the overview's focus, its Escape, and its motion.
//
// ── Rail, not tabs ────────────────────────────────────────────────────────────
// A vertical rail because the page list only grows — tabs would need a scroll or a
// row of ever-shrinking labels the first time a sixth page shows up. The rail also
// keeps the page title in the same place on every page, which is what makes flipping
// between them read as one surface changing rather than four cards swapping.
//
// The rail is a RECESSED SURFACE, not items floating against a hairline. It's the
// one piece of chrome that persists across every page, so it needs to read as part
// of the card's structure rather than as the first row of content. That's what the
// elevation ladder is for: the card sits at Card, the rail one step up at Nested, and
// the selected item one step above that again — so "where am I" is answered by depth
// before colour has to say anything.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard

    // Fallbacks only. The overview anchors this to fill the left and middle of the
    // page, and a Loader with a size resizes what it loads — so in practice these
    // never apply. They exist so the card is still sane if something instantiates it
    // without giving it a size.
    implicitWidth:  980
    implicitHeight: 640

    // ── The FILE is the state; the index is derived ───────────────────────────
    // This used to be the other way round — `current` was the property, restored by a
    // binding — and it was broken, in a way worth recording because it looked fine:
    //
    //   1. The card is built. Config hasn't finished loading, so settingsPage is still
    //      the default and `current` resolves to 0.
    //   2. NetworkManager comes up, `hasWifi` flips, and the old
    //      `onHasWifiChanged: root.current = …` ASSIGNED to current — destroying the
    //      binding.
    //   3. Config then loads with the remembered page, and nothing is listening any more.
    //
    // So the page was always remembered and never restored. Deriving the index instead
    // means a renumber re-resolves for free (the binding reads `pages`), and there is
    // nothing to assign, so nothing to break. The hardware handlers are gone with it.
    //
    // Not in UiState: that holds session state and is deliberately not persisted, and
    // "the page I was last on" is a preference that should survive a restart.
    property string currentFile: Config.settingsPage
    readonly property int current: root._indexOfPage(root.currentFile)

    // Only ever the user's own choice reaches Config — never a fallback we resolved to
    // because the remembered page hadn't appeared yet. That distinction is what stops a
    // transient state from erasing the memory.
    onCurrentFileChanged: Config.settingsPage = root.currentFile

    function showPage(index) {
        const p = root.pages[index]
        if (p) root.currentFile = p.file
    }

    function _indexOfPage(file) {
        // `pages` is declared below this binding and is undefined on the first pass, so
        // this must cope with being asked before there is anything to search. Reading
        // root.pages here still registers the dependency, so the binding re-runs and
        // lands on the right page once the list exists.
        const list = root.pages
        if (!list) return 0
        for (let i = 0; i < list.length; i++)
            if (list[i].file === file) return i
        return 0        // remembered page no longer exists (hardware went away)
    }

    // ── Battery only exists if there is one ───────────────────────────────────
    // This is a desktop, so today the page is simply absent rather than showing a
    // column of em-dashes and a charge readout stuck at 0%. It appears on its own on
    // a laptop — `displayDevice` is a live binding, so plugging the config into one
    // is all it takes.
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false

    // Same rule as the battery, for the same reason: a machine with no Wi-Fi device
    // gets no Wi-Fi page, rather than one explaining that it has no Wi-Fi. `hasWifi`
    // is a live binding on the device list, so a USB adapter appearing adds the page.
    readonly property bool hasWifi: Net.hasWifi
    // Gated like Wi-Fi: a desktop with no adapter gets no Bluetooth page. `values` is
    // live, so plugging a dongle in makes the page appear without a restart.
    readonly property bool hasBluetooth: Bluetooth.adapters.values.length > 0

    // `section` groups the rail: contiguous entries sharing one get a single header.
    readonly property var pages: [
        { file: "BarPage.qml",      label: "Bar",      glyph: "󰍜", detail: "Modules, size, shape", section: "Shell" },
        { file: "WallpaperPage.qml", label: "Wallpaper", glyph: "󰸉", detail: "Images and scenes", section: "Shell" },
        { file: "WidgetsPage.qml",  label: "Widgets",  glyph: "󰕮", detail: "Desktop clock, weather, notes", section: "Shell" },
        { file: "KeyboardPage.qml", label: "Keyboard", glyph: "󰌌", detail: "Layout and repeat",    section: "Devices" }
    ].concat(root.hasWifi
        ? [{ file: "NetworkPage.qml", label: "Wi-Fi", glyph: "󰤨", detail: "Networks and status", section: "Devices" }]
        : []
    ).concat(root.hasBluetooth
        ? [{ file: "BluetoothPage.qml", label: "Bluetooth", glyph: "󰂯", detail: "Devices and pairing", section: "Devices" }]
        : []
    ).concat(root.hasBattery
        ? [{ file: "BatteryPage.qml", label: "Battery", glyph: "󰁽", detail: "Health and profile", section: "Devices" }]
        : []
    ).concat([
        // Unconditional, unlike Wi-Fi and Battery: those pages are gated because the
        // hardware may genuinely be absent, whereas a machine with no working PipeWire
        // still wants to be told so — and the page says exactly that rather than
        // presenting dead controls.
        { file: "SoundPage.qml",    label: "Sound",    glyph: "󰕾", detail: "Output, input, apps",   section: "Devices" },
        { file: "HyprlandPage.qml", label: "Hyprland", glyph: "", detail: "Keybinds and tuning",   section: "System" },
        { file: "UpdatesPage.qml",  label: "Updates",  glyph: "󰚰", detail: "Packages and upgrades", section: "System" },
        { file: "StoragePage.qml",  label: "Storage",  glyph: "󰋊", detail: "Disks and cleanup",     section: "System" },
        { file: "LanguagePage.qml", label: "Language", glyph: "󰗊", detail: "Locale",                section: "System" },
        { file: "AboutPage.qml",    label: "About",    glyph: "󰋼", detail: "This machine",          section: "System" }
    ])

    // ── Renumbering handles itself now ────────────────────────────────────────
    // A battery arriving mid-session, or NetworkManager coming up late, inserts a page
    // and shifts everything below it. That used to need explicit handlers to re-snap
    // `current`.
    //
    // No onHasBattery/onHasWifi handlers any more. They existed to re-snap `current`
    // when the rail renumbered, and that is now automatic: `current` is derived from
    // `currentFile` AND `pages`, so a page appearing or vanishing re-resolves the index
    // on its own. Assigning here was what broke the restore — see the note above.

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingXl

        // ══ Rail ══════════════════════════════════════════════════════════════
        // ── Pinned, not merely preferred. This is load-bearing. ───────────────
        // The rail was a bare ColumnLayout with `Layout.preferredWidth: 190`, and it
        // rendered hundreds of pixels wide with the page squeezed out of existence
        // beside it. Preferred is only a REQUEST: a layout derives its
        // Layout.minimumWidth from its children, and RowLayout honours minimums over
        // preferences. The header inside had a title that didn't elide, so it set a
        // minimum wider than 190 and the rail grew to swallow the card.
        //
        // Two things stop that recurring. The rail is a Surface (a Rectangle) with
        // its content ANCHORED inside rather than laid out, which breaks the
        // implicit-size chain — children can no longer report a size upward at all.
        // And min == max == preferred says the width is a decision, not a hint, so a
        // future long label elides instead of resizing the card.
        Surface {
            id: rail

            // Collapsed, the rail is icons only — enough to navigate by, and it hands
            // ~150px back to the page. Animated, because a rail that teleports between
            // two widths reads as the card being rebuilt rather than folded.
            readonly property int fullWidth:      210
            readonly property int collapsedWidth: 62
            readonly property bool collapsed: Config.railCollapsed

            property int railWidth: rail.collapsed ? rail.collapsedWidth : rail.fullWidth
            Behavior on railWidth {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }

            Layout.preferredWidth: rail.railWidth
            Layout.minimumWidth:   rail.railWidth
            Layout.maximumWidth:   rail.railWidth
            Layout.fillHeight: true

            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusPill

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingXs

                // ── Wordmark ──────────────────────────────────────────────────
                // Not a PanelHeader: every page already has one, and two headers
                // stacked eight pixels apart is how you get a card that looks like
                // two cards. This just says which surface you're on.
                //
                // The gear doubles as the collapse control. A separate button would be
                // one more thing in a rail whose whole job is to be small, and the
                // wordmark is dead weight otherwise.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins:   Tokens.spacingSm
                    Layout.bottomMargin: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        // Fills and centres when collapsed — the same treatment the nav
                        // glyphs get. This replaces a fixed 4px nudge, which left the
                        // gear visibly off-centre: a ~20px glyph in a 46px row needs
                        // ~13px, and a hardcoded margin is wrong the moment any size
                        // token moves.
                        Layout.fillWidth: rail.collapsed
                        horizontalAlignment: Text.AlignHCenter
                        text:  "󰒓"
                        color: Colors.focus
                        variant: "headline"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !rail.collapsed
                        // Fades rather than vanishing on the frame the width starts
                        // moving — otherwise the label disappears before the rail has
                        // narrowed and the fold looks like a glitch.
                        opacity: rail.collapsed ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        text: "Settings"
                        variant: "headline"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    HoverHandler { id: wordmarkHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: Config.toggleRail() }
                }

                Repeater {
                    model: root.pages

                    ColumnLayout {
                        id: navBlock
                        required property int index
                        required property var modelData

                        // First entry of a new section carries the section's header.
                        readonly property bool sectionStart: navBlock.index === 0
                            || root.pages[navBlock.index - 1].section !== navBlock.modelData.section

                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs

                        // ── Section header ────────────────────────────────────
                        // Expanded: a small label. Collapsed: there's no room for a
                        // word, so it becomes a short centred divider — the grouping
                        // survives the fold instead of silently vanishing.
                        StyledText {
                            visible: navBlock.sectionStart && !rail.collapsed
                            Layout.leftMargin: Tokens.spacingSm
                            Layout.topMargin:  navBlock.index === 0 ? 0 : Tokens.spacingMd
                            text: navBlock.modelData.section
                            variant: "label"
                            emphasis: "muted"
                        }
                        Rectangle {
                            visible: navBlock.sectionStart && rail.collapsed && navBlock.index !== 0
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin:    Tokens.spacingSm
                            Layout.bottomMargin: Tokens.spacingSm
                            implicitWidth: 20
                            implicitHeight: 1
                            color: Colors.outline
                        }

                    Rectangle {
                        id: navItem

                        readonly property bool isCurrent: root.current === navBlock.index

                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: Tokens.radiusSm

                        // The launcher's selected-row treatment, for the same reason: a
                        // selection is `focus` ("this is what you're looking at"), never
                        // `primary` — a filled primary would read as a button waiting to
                        // be pressed, and the rail item you're already on isn't one.
                        color: navItem.isCurrent  ? Colors.alpha(Colors.focus, 0.14)
                             : navHover.hovered   ? Colors.alpha(Colors.fg, 0.06)
                             :                      "transparent"

                        border.width: Tokens.borderWidth
                        border.color: navItem.isCurrent
                            ? Colors.alpha(Colors.focus, 0.32)
                            : "transparent"

                        Behavior on color        { ColorAnimation { duration: Motion.respond } }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        // ── Selection marker ──────────────────────────────────
                        // A short accent bar on the leading edge. The fill alone is
                        // very quiet on a monochrome pywal palette — `focus` at 14%
                        // over an already-lifted surface is a few points of
                        // luminance, and on a grey scheme that can vanish entirely.
                        // The bar is what makes the current page unmistakable
                        // regardless of what the wallpaper hands us.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width:  3
                            height: navItem.isCurrent ? parent.height - Tokens.spacingLg * 2 : 0
                            radius: 2
                            color:  Colors.focus

                            Behavior on height {
                                NumberAnimation {
                                    duration: Motion.standard
                                    easing.type: Motion.travel
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin:  rail.collapsed ? 0 : Tokens.spacingLg
                            anchors.rightMargin: rail.collapsed ? 0 : Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            StyledText {
                                // Centres in the collapsed rail; sits left when the
                                // label is beside it.
                                Layout.fillWidth: rail.collapsed
                                horizontalAlignment: Text.AlignHCenter
                                text:  navBlock.modelData.glyph
                                color: navItem.isCurrent ? Colors.focus : Colors.fgDim
                                variant: "title"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !rail.collapsed
                                opacity: rail.collapsed ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: navBlock.modelData.label
                                    variant: "body"
                                    font.weight: navItem.isCurrent ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text:     navBlock.modelData.detail
                                    variant:  "caption"
                                    emphasis: "dim"
                                    elide:    Text.ElideRight
                                }
                            }
                        }

                        // ── Tooltip ───────────────────────────────────────────
                        // The collapsed rail is glyphs alone, and a glyph is a guess.
                        // Drawn outside the item (x = width + gap) and z-lifted so it
                        // isn't clipped by the nav item it belongs to.
                        Rectangle {
                            visible: rail.collapsed && navHover.hovered
                            x: parent.width + Tokens.spacingMd
                            anchors.verticalCenter: parent.verticalCenter
                            z: 50
                            width:  tipText.implicitWidth + Tokens.spacingMd * 2
                            height: tipText.implicitHeight + Tokens.spacingSm * 2
                            radius: Tokens.radiusSm
                            color:        Colors.surfaceFor(Tokens.elevationPopup)
                            border.width: Tokens.borderWidth
                            border.color: Colors.outlineFor(Tokens.elevationPopup)

                            StyledText {
                                id: tipText
                                anchors.centerIn: parent
                                text:    navBlock.modelData.label
                                variant: "caption"
                            }
                        }

                        HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { onTapped: root.showPage(navBlock.index) }
                    }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ══ Page ══════════════════════════════════════════════════════════════
        // Loader, not a stack of always-built pages: BatteryPage polls UPower and
        // AboutPage shells out to specs.sh. Building all five up front would run
        // every page's process the first time the overview opens, whether or not
        // you ever look at them.
        //
        // The pages are only unloaded when the CARD is (the overview closing takes
        // the whole thing with it), so flipping back to a page you've already
        // visited does re-run its probe — which is correct: battery and locale can
        // both have changed since.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: pageLoader
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingSm
                source: root.pages[root.current] ? "pages/" + root.pages[root.current].file : ""

                // A cross-fade, not a slide: the rail is what tells you where you are,
                // so the page has no direction to travel in. Fading keeps the eye on
                // the rail rather than sending it chasing a card across the surface.
                opacity: pageLoader.status === Loader.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }
    }
}
