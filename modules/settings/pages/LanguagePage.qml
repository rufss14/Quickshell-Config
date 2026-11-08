pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── LanguagePage — Devices › Language ─────────────────────────────────────────
// The system locale, via localectl.
//
// `localectl set-locale` goes through polkit, so applying one may raise an
// authentication prompt — and may be refused. That's why this page re-reads the
// locale afterwards and shows what the system actually says, not what we asked for.
//
// Rebuilt onto SettingsPage in the overhaul. "What this does" was a card of three
// paragraphs; it's one caption under Current now.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The system's side (localectl) is SystemLocale's; read when the page opens.
    readonly property string current: SystemLocale.current
    readonly property var    locales: SystemLocale.locales
    readonly property string status:  SystemLocale.status
    readonly property bool   failed:  SystemLocale.failed
    Component.onCompleted: SystemLocale.refresh()

    property string search: ""

    // The locale list is a fixed window inside the scrolling page — a ListView reports
    // no implicit height, and ~500 rows unwindowed would make the page itself the scroll.
    readonly property int rowHeight:   34
    readonly property int visibleRows: 8

    readonly property var filtered: {
        const s = root.search.trim().toLowerCase()
        return s === "" ? root.locales
                        : root.locales.filter(l => l.toLowerCase().includes(s)
                                               || root.localeLabel(l).toLowerCase().includes(s))
    }

    // ── "en_US.UTF-8" → "English (United States)" ─────────────────────────────
    // Qt carries the CLDR name table, so the names cost no process and no data file.
    function localeLabel(code) {
        const base = String(code).split(".")[0]
        if (base === "C" || base === "POSIX") return "Plain computer English"
        const loc = Qt.locale(base)
        const lang = loc.nativeLanguageName || ""
        if (lang === "") return ""
        const terr = loc.nativeTerritoryName || ""
        return lang + (terr !== "" ? " (" + terr + ")" : "")
    }

    // ── Hover previews the formats ────────────────────────────────────────────
    // Applying needs authentication and a restart to fully land, so the preview
    // answers the question the click would otherwise be the only way to ask.
    property string hoverLocale: ""
    readonly property string previewCode: root.hoverLocale !== "" ? root.hoverLocale : root.current

    function setLocale(name) { SystemLocale.setLocale(name) }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰗊"
        title:     Translation.tr("Language")
        titleTail: "& region"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.current !== "" ? root.current : "Reading locale…"

        // ══ The shell's own language ═════════════════════════════════════════
        // Not the system locale below: this is the language of the shell's own text
        // (services/Translation). Only what has been wrapped in Translation.tr() is
        // translated, so a language here changes the parts of the shell that have been
        // converted and leaves the rest in English; `python3 scripts/translations.py
        // status` says how far each one goes.
        Section {
            span:     3
            glyph:    "󰗊"
            title:    Translation.tr("Shell language")
            subtitle: Config.uiLanguage === "auto"
                      ? Translation.tr("Follows the system")
                      : Translation.nameOf(Config.uiLanguage)
            help:     Translation.tr("The language of the shell's own text. Only strings that have been prepared for translation change; everything else stays in English. To add a language, copy translations/en_US.json to a new <code>.json and translate the right-hand sides.")
            accent:   Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                PanelButton {
                    capsule: true
                    label: Translation.tr("Automatic")
                    variant: Config.uiLanguage === "auto" ? "primary" : "normal"
                    onActivated: Config.uiLanguage = "auto"
                }
                Repeater {
                    model: Translation.available
                    PanelButton {
                        capsule: true
                        required property string modelData
                        label: Translation.nameOf(modelData)
                        variant: Config.uiLanguage === modelData ? "primary" : "normal"
                        onActivated: Config.uiLanguage = modelData
                    }
                }
            }
        }

        Section {
            span:     1
            glyph:    "󰗡"
            title:    Translation.tr("Current")
            help:     Translation.tr("What the system reports right now. Picking a locale below sets the language, date and number formats programs start with — it needs your password, and running programs keep the old one until they restart.")
            accent:   Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                MaterialIcon {
                    glyph:  "󰗊"
                    color: Colors.of(QsWindow.window).primary
                    variant: "display"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.current !== "" ? root.current : "—"
                        variant: "title"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.localeLabel(root.current) !== ""
                              ? root.localeLabel(root.current) : "System LANG"
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }

            // Only after you've tried to apply something.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.status !== ""
                text:    root.status
                color:   root.failed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                variant: "caption"
                wrapMode: Text.WordWrap
            }

        }

        // ── Format preview ────────────────────────────────────────────────
        // Follows the hovered locale, so the list can be browsed by consequence.
        Section {
            id: previewBox
            span:     1
            glyph:    "󰱆"
            title:    Translation.tr("How it looks")
            subtitle: root.hoverLocale !== "" ? "Previewing " + root.hoverLocale : "Your current formats"
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            readonly property var  loc: Qt.locale(root.previewCode.split(".")[0])
            readonly property date now: new Date()

            FormatRow { label: "Date";        value: previewBox.now.toLocaleDateString(previewBox.loc, Locale.LongFormat) }
            FormatRow { label: "Time";        value: previewBox.now.toLocaleTimeString(previewBox.loc, Locale.ShortFormat) }
            FormatRow { label: "Numbers";     value: Number(1234567.89).toLocaleString(previewBox.loc) }
            FormatRow { label: "Currency";    value: Number(9.99).toLocaleCurrencyString(previewBox.loc) }
            FormatRow { label: "Week starts"; value: previewBox.loc.dayName(previewBox.loc.firstDayOfWeek, Locale.LongFormat) }
        }

        // ══ Available locales ═════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰉹"
            title:    Translation.tr("Available locales")
            subtitle: root.locales.length + " installed"
            accent:   Colors.of(QsWindow.window).primary

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("Search locales")
                onEdited: function (v) { root.search = v }
            }

            ListView {
                Layout.fillWidth: true
                // As tall as what is there (a few locales are usually installed), up to a cap.
                Layout.preferredHeight: root.rowHeight * Math.max(3, Math.min(root.filtered.length, root.visibleRows))
                clip: true
                spacing: Tokens.spacingXs
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: localeRow
                    required property string modelData

                    readonly property bool selected: localeRow.modelData === root.current
                    readonly property string label: root.localeLabel(localeRow.modelData)

                    width:  ListView.view ? ListView.view.width : 0
                    height: root.rowHeight
                    radius: Tokens.radiusSm
                    color: localeRow.selected ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.14)
                         : rowHover.hovered   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                         :                      "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin:  Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        StyledText {
                            text: localeRow.label !== "" ? localeRow.label : localeRow.modelData
                            variant: "body"
                            font.weight: localeRow.selected ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: localeRow.label !== ""
                            text: localeRow.modelData
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                            elide: Text.ElideRight
                        }
                        MaterialIcon {
                            visible: localeRow.selected
                            glyph:    "󰄬"
                            color:   Colors.of(QsWindow.window).primary
                            variant: "body"
                        }
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                        // Cleared only if this row still owns the preview, so
                        // crossing rows doesn't flicker it.
                        onHoveredChanged: {
                            if (hovered) root.hoverLocale = localeRow.modelData
                            else if (root.hoverLocale === localeRow.modelData) root.hoverLocale = ""
                        }
                    }
                    TapHandler {
                        enabled: !localeRow.selected
                        onTapped: root.setLocale(localeRow.modelData)
                    }
                }
            }
        }
    }

    component FormatRow: RowLayout {
        id: fr
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd
        StyledText {
            Layout.preferredWidth: 90
            text: fr.label
            variant: "caption"
            emphasis: "dim"
        }
        StyledText {
            Layout.fillWidth: true
            text: fr.value
            variant: "caption"
            elide: Text.ElideRight
        }
    }
}
