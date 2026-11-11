pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── AppearancePage — Appearance › Theme ───────────────────────────────────────
// Where the shell's colours come from: the wallpaper, the album cover, the accent.
// The file keeps its old name so a remembered page and the default landing resolve;
// the rail calls it Theme.
//
// ── A bento, not two columns of rows ──────────────────────────────────────────
// This page is eight booleans, one picker and a palette. As stacked cards that was a
// wall of label-detail-switch lines, all the same shape, none of which told you its
// state without reading to the far right edge.
//
// Now: the palette itself spans the grid, and every boolean is a TILE you tap, which
// lights up when it is on. State is the fill and the chip, readable across the whole
// page at a glance — the switch's position was never legible at that distance.
//
// ── One home for the palette ──────────────────────────────────────────────────
// "Theme from wallpaper", light/dark and "follow the album cover" were spread over
// two pages and a panel. They are all here. The colour EDITOR (seeds, slots, presets)
// stays the bar's Colours panel: that is a live tool, this is where the rules are set.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Which swatch the pointer is on, or -1 — the hero's caption reads it.
    property int hoverSwatch: -1

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰸌"
        title:     Translation.tr("Colour")
        titleTail: "theme"
        accent:    Colors.of(QsWindow.window).primary
        subtitle: AlbumScheme.active || AlbumScheme.reason === "held"
            ? AlbumScheme.reasonText
            : Config.wallTheming
            ? "The palette follows the wallpaper"
            : "The palette is frozen — a new wallpaper won't recolour the shell"

        // ══ The palette itself ════════════════════════════════════════════════
        // Full width, first: the page is about colour, so it opens with the colour.
        Section {
            span:     3
            glyph:    "󰸉"
            title:    Translation.tr("Your palette")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: root.hoverSwatch >= 0
                ? "color" + root.hoverSwatch + "   " + String(Colors.of(QsWindow.window).ansi(root.hoverSwatch)).toUpperCase()
                : Config.wallTheming ? "From the current wallpaper" : "Frozen"
            help:     Translation.tr("Sixteen slots. Everything in the shell is drawn from these — point at one to read its value.")

            // Light/Dark rides in the heading: it is the one control that changes
            // every swatch under it.
            actions: TabStrip {
                implicitWidth: 168
                accent: Colors.of(QsWindow.window).primary
                enabled: Config.wallTheming && !Wallpaper.applying
                model: [
                    { value: "light", label: "Light", icon: "light_mode" },
                    { value: "dark",  label: "Dark",  icon: "dark_mode" }
                ]
                current: Config.themeMode
                onPicked: function (v) {
                    if (Config.themeMode === v) return
                    ColorScheme.switchMode(v)
                }
            }

            // The ramp. Equal-width bars: the palette is a continuum of sixteen
            // slots, and bars sit together as one object where tiles would read as
            // sixteen buttons. Hovering one lifts it and names it in the subtitle.
            //
            // ── The row's own height is FIXED ─────────────────────────────────
            // It used to be `Layout.preferredHeight: hot ? 52 : 40` on the swatch
            // itself — a Layout property, so growing one swatch grew the RowLayout,
            // which grew the Section card, which reflowed every card below it in
            // the bento grid. Sixteen swatches meant sixteen chances to jitter the
            // whole page on a stray mouse movement.
            //
            // The row now reserves the TALL height (52) permanently, and each
            // swatch is a plain Item inside a fixed-size cell: the cell's size never
            // changes, only the Rectangle anchored to its bottom does. Growth reads
            // as the bar rising off the baseline, and nothing outside this row ever
            // learns it happened.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                Repeater {
                    model: 16

                    Item {
                        id: cell
                        required property int index
                        readonly property bool hot: root.hoverSwatch === cell.index

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.left:   parent.left
                            anchors.right:  parent.right
                            anchors.bottom: parent.bottom
                            height: cell.hot ? 52 : 40
                            radius: Tokens.radiusSm
                            color: Colors.of(QsWindow.window).ansi(cell.index)

                            // Eased, so a new wallpaper washes across the ramp.
                            Behavior on color { ColorAnimation { duration: Motion.emphasized } }
                            Behavior on height {
                                NumberAnimation {
                                    duration: Motion.standard
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring
                                }
                            }
                        }

                        // On the fixed-size cell, not the growing Rectangle: a
                        // hover target that changes size while you're hovering it
                        // is the other half of this bug — the swatch could shrink
                        // out from under the pointer, end the hover, shrink back,
                        // and re-enter it, oscillating. The cell is the whole
                        // reserved footprint, so the hit area never moves.
                        HoverHandler {
                            id: cellHover
                            onHoveredChanged: {
                                if (cellHover.hovered) root.hoverSwatch = cell.index
                                else if (root.hoverSwatch === cell.index) root.hoverSwatch = -1
                            }
                        }
                    }
                }
            }

            // Held colours win over the wallpaper, silently — said where the switch
            // they override lives.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Config.wallTheming && ColorScheme.overrideCount > 0
                text: ColorScheme.overrideCount
                    + (ColorScheme.overrideCount === 1 ? " colour is" : " colours are")
                    + " held by a saved scheme — release them from the bar's Colours panel."
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }
        }

        // ══ Where the colours come from ═══════════════════════════════════════
        QuickToggleTile {
            roomy: true
            symbol: "wallpaper"
            label:  Translation.tr("Theme from wallpaper")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallTheming
            subLabel: Config.wallTheming
                ? "Every new wallpaper repaints the shell"
                : "The palette stays exactly as it is"
            onToggled: Config.wallTheming = !Config.wallTheming
        }

        QuickToggleTile {
            roomy: true
            symbol: "music_note"
            label:  Translation.tr("Follow the album cover")
            accent: Colors.of(QsWindow.window).primary
            active: Config.albumScheme
            // The service's own account of what it is doing, so the tile and the
            // header cannot describe one state two ways.
            subLabel: Config.albumScheme ? AlbumScheme.reasonText
                                         : "The cover is ignored"
            onToggled: Config.albumScheme = !Config.albumScheme
        }

        QuickToggleTile {
            roomy: true
            symbol: "palette"
            label:  Translation.tr("Recolour every app")
            accent: Colors.of(QsWindow.window).primary
            active: Config.albumSchemeSystem
            // Off is not "nothing happens" — it is "the shell only", which is a
            // different promise and the one people want by default.
            available: Config.albumScheme
            subLabel: Config.albumSchemeSystem
                ? "Terminal, GTK/Qt apps and Discord repaint each track"
                : "Bar, panels and overview only — held in memory"
            onToggled: Config.albumSchemeSystem = !Config.albumSchemeSystem
        }

        QuickToggleTile {
            roomy: true
            symbol: "lock"
            label:  Translation.tr("Lock while playing")
            accent: Colors.of(QsWindow.window).primary
            active: Config.albumSchemeLock
            available: Config.albumScheme
            subLabel: "Album colours hold until playback stops"
            help:     Translation.tr("While music plays, a new wallpaper or scheme doesn't overwrite the cover's colours.")
            onToggled: Config.albumSchemeLock = !Config.albumSchemeLock
        }

        QuickToggleTile {
            roomy: true
            symbol: "queue_music"
            label:  Translation.tr("Tint media cards")
            accent: Colors.of(QsWindow.window).primary
            active: Config.albumCardColors
            // Deliberately NOT gated on albumScheme: this one works on its own, which
            // is why it is its own tile rather than a row nested under that switch.
            subLabel: Config.albumCardColors ? "Now playing and lyrics wear the cover"
                                             : "Media cards use the shell palette"
            help:     Translation.tr("Works on its own: the media cards take the cover's colours even when the shell doesn't follow the album.")
            onToggled: Config.albumCardColors = !Config.albumCardColors
        }

        QuickToggleTile {
            roomy: true
            symbol: "format_paint"
            label:  Translation.tr("Colorize icons")
            accent: Colors.of(QsWindow.window).primary
            active: Config.colorizeIcons
            subLabel: Config.colorizeIcons
                ? "Tray and lyrics-badge icons wear the accent"
                : "Each icon keeps its own colours"
            onToggled: Config.colorizeIcons = !Config.colorizeIcons
        }

        // ══ Accent ════════════════════════════════════════════════════════════
        Section {
            span:     2
            glyph:    "󰌁"
            title:    Translation.tr("Accent")
            subtitle: (Config.accentRoles.find(function (r) { return r.id === Config.accentRole }) || { label: Translation.tr("Default") }).label || "Default"
            help:     Translation.tr("The fallback colour, for widgets that ask for one. Picked by role, so it follows the next wallpaper.")
            accent:   Colors.of(QsWindow.window).info

            // Palette ROLES, never hex — so the choice survives the next wallpaper.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: Config.accentRoles

                    Rectangle {
                        id: role
                        required property var modelData
                        readonly property bool isCurrent: Config.accentRole === role.modelData.id
                        readonly property bool isDefault: role.modelData.id === ""

                        implicitWidth:  role.isDefault ? defaultLabel.implicitWidth + Tokens.spacingMd * 2
                                                       : 34
                        implicitHeight: 34
                        radius: Tokens.radiusSm

                        color: role.isDefault ? "transparent"
                                              : Colors.of(QsWindow.window).role(role.modelData.id, Colors.of(QsWindow.window).primary)
                        border.width: role.isCurrent ? 2 : Tokens.borderWidth
                        border.color: role.isCurrent   ? Colors.of(QsWindow.window).fg
                                    : roleHover.hovered ? Colors.of(QsWindow.window).outlineFocus
                                                        : Colors.of(QsWindow.window).outline

                        // Picking one pops it, the same acknowledgement a chip makes.
                        scale: roleHover.hovered && !role.isCurrent ? 1.08 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.respond
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.spring
                            }
                        }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        StyledText {
                            id: defaultLabel
                            anchors.centerIn: parent
                            visible: role.isDefault
                            text:    Translation.tr("Default")
                            variant: "caption"
                            emphasis: role.isCurrent ? "normal" : "dim"
                        }

                        HoverHandler { id: roleHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { onTapped: Config.accentRole = role.modelData.id }
                    }
                }
            }
        }

        // ══ Looks ═════════════════════════════════════════════════════════════
        // How the shell looks, as one small .json file (services/Look.qml, look.js). Import never
        // applies on its own: it lists what the file would change and waits for Apply, and a look
        // rewrites the bar, the sidebar and the colours, so there is an Undo for as long as it is
        // the last thing done. Motion settings are never in a file and never changed by one.
        Section {
            span:     3
            symbol:   "style"
            title:    Translation.tr("Looks")
            subtitle: Look.status !== "" && !Look.statusBad ? Look.status
                                                            : Translation.tr("Share how your shell looks as one small file")
            help:     Translation.tr("A look is the bar, the sidebar, the style settings and your current colours in one .json file. No wallpaper, no paths, nothing personal, and never your motion settings. Import shows what it would change first, and you can undo it.")
            accent:   Colors.of(QsWindow.window).primary

            actions: ChipTray {
                ChipButton {
                    symbol:  "ios_share"
                    label:   Translation.tr("Export")
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: Look.blocker() === "" && !Look.busy
                    onActivated: Look.exportLook(lookName.text)
                }
                ChipButton {
                    symbol:  "download"
                    label:   Translation.tr("Import")
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: Look.blocker() === "" && !Look.busy
                    onActivated: Look.importLook()
                }
                ChipButton {
                    visible: Look.canUndo
                    symbol:  "undo"
                    label:   Translation.tr("Undo")
                    tint:    Colors.of(QsWindow.window).primary
                    onActivated: Look.undo()
                }
            }

            InputField {
                id: lookName
                Layout.fillWidth: true
                cornerRadius: implicitHeight / 2
                placeholder: Translation.tr("Name this look (used by Export)")
            }

            // A missing file dialog disables both buttons; this is the reason.
            StyledText {
                Layout.fillWidth: true
                visible: Look.blocker() !== "" || Look.statusBad
                text:    Look.blocker() !== "" ? Look.blocker() : Look.status
                variant: "caption"
                wrapMode: Text.WordWrap
                color:   Colors.of(QsWindow.window).danger
            }

            // What an imported file would change, until you say yes.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Look.pending !== null
                spacing: Tokens.spacingSm

                StyledText {
                    text: Look.pending ? "Apply “" + Look.pending.name + "”?" : ""
                    variant: "label"
                }
                Repeater {
                    model: Look.pendingLines
                    StyledText {
                        required property string modelData
                        Layout.fillWidth: true
                        text: "·  " + modelData
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }
                StyledText {
                    visible: Look.pendingSkipped > 0
                    Layout.fillWidth: true
                    text: Look.pendingSkipped + (Look.pendingSkipped === 1 ? " value in the file isn't valid and will be skipped"
                                                                           : " values in the file aren't valid and will be skipped")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    ChipButton {
                        symbol: "check"
                        label:  Translation.tr("Apply")
                        solid:  true
                        tint:   Colors.of(QsWindow.window).primary
                        onActivated: Look.applyPending()
                    }
                    ChipButton {
                        symbol: "close"
                        label:  Translation.tr("Cancel")
                        tint:   Colors.of(QsWindow.window).primary
                        onActivated: Look.discard()
                    }
                }
            }
        }
    }
}
