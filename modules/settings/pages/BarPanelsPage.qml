pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── BarPanelsPage — Bar › Panels ──────────────────────────────────────────────
// The surfaces a bar module opens: which side of the bar each one drops from, and
// how to undo one you have resized.
//
// Split out of BarPage, where it was two cards at the bottom of a long Modules view
// — under a tray, an inspector and a preset list, which is a long way from anything
// about panels.
//
// ── Three arrows, not three words ─────────────────────────────────────────────
// The placement rows used to be three PanelButtons each, labelled "Left / Middle /
// Right" — the same three words eight times down a column, in a control wide enough
// to push the panel's own name into an ellipsis. They are one icon-only segmented
// strip now (←, ●, →), which is the same shape the settings window's own position
// picker uses on Appearance › Type & shape.
//
// Size is NOT set here, deliberately: you drag a panel's outer bottom corner. This is
// where you undo that, which is the one thing the panel's own grip cannot offer once
// the panel is the wrong size to find comfortably.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // How a panel is named in the UI. Config knows panels by key only — it has no
    // business holding display strings — so the label and icon for one live here,
    // where they are drawn. The ORDER is this list's; it is also the placement rows.
    readonly property var placeable: [
        { key: "wallpaper",   label: "Wallpaper",     icon: "wallpaper" },
        { key: "colorScheme", label: "Colour scheme", icon: "palette" },
        { key: "equalizer",   label: "Equalizer",     icon: "volume_up" },
        { key: "media",       label: "Now Playing",   icon: "music_note" },
        { key: "wifi",        label: "Wi-Fi",         icon: "wifi" },
        { key: "bluetooth",   label: "Bluetooth",     icon: "bluetooth" },
        { key: "gaming",      label: "Gaming",        icon: "sports_esports" },
        { key: "clock",       label: "Clock",         icon: "calendar_month" },
        { key: "brightness",  label: "Brightness",    icon: "brightness_6" },
        { key: "window",      label: "Focused window", icon: "desktop_mac" },
        { key: "layout",      label: "Window layout", icon: "vertical_split" }
    ]

    // Covers every key in Config.panelZoomNames — the placement list plus the two
    // centre-slot panels, which have no side to pick but resize like anything else.
    readonly property var extraMeta: ({
        update:   { label: "Updates",  icon: "update" },
        launcher: { label: "Launcher", icon: "apps" }
    })

    // Falls back to the key rather than an empty row: a panel added to panelZoomNames
    // without a line above should look unfinished, not invisible.
    function meta(key) {
        const hit = root.placeable.find(p => p.key === key)
        return hit ?? root.extraMeta[key] ?? { label: key, icon: "square" }
    }

    readonly property var resized: Config.panelZoomNames.filter(n => Config.panelZoomed(n))

    // The three-way control every placement row wears. Icon-only: the label is the
    // panel's name at the start of the row, and "Left / Middle / Right" eight times
    // over is the same three words filling a column.
    readonly property var sideSegments: [
        { value: "left",   label: "", icon: "chevron_left" },
        { value: "center", label: "", icon: "circle" },
        { value: "right",  label: "", icon: "chevron_right" }
    ]

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F0574}"
        title:     Translation.tr("Bar")
        titleTail: "panels"
        accent:    Colors.of(QsWindow.window).primary
        // Where they drop, counted — a reading rather than a description.
        subtitle:  ["left", "center", "right"].map(function (side) {
                       const n = root.placeable.filter(p => Config.panelSide(p.key) === side).length
                       return n + (side === "left" ? " left" : side === "center" ? " centred" : " right")
                   }).join("  ·  ")
                   + (root.resized.length > 0 ? "  ·  " + root.resized.length + " resized" : "")

        // ══ The rows ══════════════════════════════════════════════════════════
        Section {
            span:     2
            glyph:    "\u{F0574}"
            title:    Translation.tr("Panel placement")
            accent:   Colors.of(QsWindow.window).primary
            help:     Translation.tr("Which side of the bar each panel drops from. Each one defaults to the side its own bar module sits on.")

            // Two columns of rows: one long column put each name at the far left and
            // its picker at the far right of the page, with nothing between them.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 640 ? 2 : 1
                columnSpacing: Tokens.spacingXxl
                rowSpacing: Tokens.spacingXs

            Repeater {
                model: root.placeable

                // Not a SettingRow — that component's label is plain text with no room
                // for the icon in front of it, and three placement choices is one more
                // than its single control slot reads well with.
                delegate: Item {
                    id: placeRow
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: 36

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin:  -Tokens.spacingSm
                        anchors.rightMargin: -Tokens.spacingSm
                        radius: Tokens.radiusSm
                        color: rowHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    // Hover only — the row has no click of its own, so a HoverHandler
                    // is enough and it cannot steal the strip's presses. It exists for
                    // the row highlight: a row of controls with no hover state gives
                    // you nothing to aim along.
                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Tokens.spacingMd

                        MaterialIcon {
                            name: placeRow.modelData.icon
                            fill: 0
                            font.pixelSize: Tokens.iconSm
                            color: rowHover.hovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgMuted
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: placeRow.modelData.label
                            variant: "body"
                            elide: Text.ElideRight
                        }
                        TabStrip {
                            Layout.preferredWidth: 126
                            accent:  Colors.of(QsWindow.window).primary
                            model:   root.sideSegments
                            current: Config.panelSide(placeRow.modelData.key)
                            onPicked: function (v) {
                                Config.setPanelSide(placeRow.modelData.key, v)
                            }
                        }
                    }
                }
            }
            }
        }

        // ══ Resized panels ════════════════════════════════════════════════════
        // Lists only what has actually been changed, because Config.panelZoom is a
        // sparse map: a panel at 1.0 is never written, so a row here always has
        // something to reset and "Reset" is never a no-op button.
        // span 1 beside the placement card, not a full-width row of its own: the
        // content is a handful of chips, and a 900px row for a list that is usually
        // one entry is a card of air.
        Section {
            span:     1
            glyph:    "\u{F0A68}"
            title:    Translation.tr("Resized panels")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: root.resized.length === 0 ? "None" : root.resized.length + " resized"
            help:     Translation.tr("Drag a panel's outer bottom corner to resize it. Click one here to put it back to its default size.")

            Flow {
                Layout.fillWidth: true
                visible: root.resized.length > 0
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.resized

                    // A chip per resized panel rather than a full row each: the only
                    // action is "put it back", and eight full-width rows for a list
                    // that is usually one entry is a card of mostly air.
                    delegate: Rectangle {
                        id: zoomChip
                        required property var modelData
                        readonly property real zoom: Config.panelZoomFor(zoomChip.modelData)

                        implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: 32
                        radius: Tokens.radiusPill
                        color: chipHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08) : "transparent"
                        border.width: Tokens.borderWidth
                        border.color: chipHover.hovered
                                      ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.55) : Colors.of(QsWindow.window).outline
                        Behavior on color        { ColorAnimation { duration: Motion.respond } }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Config.resetPanelZoom(zoomChip.modelData) }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm

                            MaterialIcon {
                                name: root.meta(zoomChip.modelData).icon
                                fill: 0
                                font.pixelSize: Tokens.iconSm
                                color: Colors.of(QsWindow.window).fgMuted
                            }
                            StyledText {
                                text: root.meta(zoomChip.modelData).label
                                variant: "caption"
                            }
                            StyledText {
                                text: Math.round(zoomChip.zoom * 100) + "%"
                                variant: "caption"
                                emphasis: "muted"
                            }
                            MaterialIcon {
                                name: "restart_alt"
                                fill: 0
                                font.pixelSize: Tokens.iconSm
                                color: chipHover.hovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }
                        }
                    }
                }
            }

            // One button for all of them, and only once there is more than one to be
            // worth the row. ArmLatch rather than a bare click: it throws away every
            // size at once and there is no undo for it.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.resized.length > 1
                Item { Layout.fillWidth: true }
                PanelButton {
                    capsule: true
                    ArmLatch {
                        id: resetAllZoom
                        onConfirmed: Config.resetPanelZooms()
                    }
                    label:   resetAllZoom.armed ? "Sure?" : "Reset all"
                    variant: resetAllZoom.armed ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).primary
                    onActivated: resetAllZoom.trigger()
                }
            }
        }

        // ── Drifting cookies ──────────────────────────────────────────────────
        // One shared field of soft shapes that every open panel looks onto, so two panels
        // side by side — or one swapping for another — show the same drift. The card's
        // own switch, in its heading, as Desktop visualiser does.
        Section {
            span:     1
            glyph:    "󰺣"
            title:    Translation.tr("Panel backdrop")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: Config.panelCookies ? (Config.motionEnabled ? "Drifting" : "Still — motion is off") : "Off"
            help:     Translation.tr("Soft cookie shapes drifting behind every panel. They hold still when animations are switched off, and cost nothing while no panel is open.")

            actions: Toggle {
                checked: Config.panelCookies
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.panelCookies = !Config.panelCookies
            }
        }

        // ── Cookies on the bar, sidebar and frame ─────────────────────────────
        // The same field, continuing the panels' backdrop onto the rest of the shell's material
        // (FrameDrift). Two ways to have it, so it is a choice and not a fixed behaviour.
        Section {
            span:     1
            glyph:    "󰺣"
            title:    Translation.tr("Cookies on the bar, sidebar & frame")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: !Config.barCookies ? "Off — cookies stay inside the panels"
                    : !Config.motionEnabled ? "Still — motion is off"
                    : Config.barCookiesFrom === "everywhere" ? "Everywhere" : "From panels"
            help:     Config.barCookiesFrom === "everywhere"
                      ? "A field of their own behind the bar, the sidebar and the frame, each shape coming and going on a slow life — and around an open panel, the panel's own, so a cookie crossing into it stays whole. Keeps the bar redrawing. Stands down in Game mode and under a fullscreen window."
                      : "Cookies show here only around an open panel or after drifting out of one — then they keep drifting, across the bar, the sidebar and the frame, until they leave the screen. A cookie crossing between a panel and the bar stays whole. Stands down in Game mode and under a fullscreen window."

            actions: Toggle {
                checked: Config.barCookies
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.barCookies = !Config.barCookies
            }

            TabStrip {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Config.barCookies
                accent:  Colors.of(QsWindow.window).primary
                model:   [
                    { value: "panels",     label: "From panels", icon: "" },
                    { value: "everywhere", label: "Everywhere",  icon: "" }
                ]
                current: Config.barCookiesFrom === "everywhere" ? "everywhere" : "panels"
                onPicked: function (v) { Config.barCookiesFrom = v }
            }
        }
    }
}
