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
// Grouped rows. The shell's language and the locale list are one-of-N rows with a radio mark;
// the format preview is read-only rows. The weather location lives here because it is a place
// setting: the weather widget, the clock panel, night light's sunset schedule and the greeter
// all read it, and the page that sets it should not be one of them.
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
    // Two short segments (°C, °F) of the connected choice.
    readonly property int unitWidth: Tokens.fieldHeight * 4

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

        grouped:   true
        glyph:     "󰗊"
        title:     Translation.tr("Language")
        titleTail: Translation.tr("& region")
        accent:    Colors.of(QsWindow.window).primary
        // Plain words (language and region); the raw value is the detail of the locale group.
        subtitle:  root.current === "" ? Translation.tr("Reading locale…")
                 : root.localeLabel(root.current) !== "" ? root.localeLabel(root.current) : root.current

        // ══ The shell's own language ═════════════════════════════════════════
        // Not the system locale below: this is the language of the shell's own text
        // (services/Translation). Only what has been wrapped in Translation.tr() is
        // translated, so a language here changes the parts of the shell that have been
        // converted and leaves the rest in English; `python3 scripts/translations.py
        // status` says how far each one goes.
        Section {
            grouped:  true
            symbol:   "translate"
            title:    Translation.tr("Shell language")
            subtitle: Config.uiLanguage === "auto"
                      ? Translation.tr("Follows the system")
                      : Translation.nameOf(Config.uiLanguage)
            help:     Translation.tr("The language of the shell's own text. Only strings that have been prepared for translation change; everything else stays in English. To add a language, copy translations/en_US.json to a new <code>.json and translate the right-hand sides.")

            SettingRow {
                rowTap: true
                label:  Translation.tr("Automatic")
                detail: Translation.tr("Follows the system")
                onTapped: Config.uiLanguage = "auto"

                MaterialIcon {
                    name: Config.uiLanguage === "auto" ? "check_circle" : "radio_button_unchecked"
                    fill: Config.uiLanguage === "auto" ? 1 : 0
                    variant: "title"
                    color: Config.uiLanguage === "auto" ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                }
            }
            Repeater {
                model: Translation.available

                SettingRow {
                    id: langRow
                    required property string modelData
                    readonly property bool chosen: Config.uiLanguage === langRow.modelData

                    rowTap: true
                    label:  Translation.nameOf(langRow.modelData)
                    onTapped: Config.uiLanguage = langRow.modelData

                    MaterialIcon {
                        name: langRow.chosen ? "check_circle" : "radio_button_unchecked"
                        fill: langRow.chosen ? 1 : 0
                        variant: "title"
                        color: langRow.chosen ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                    }
                }
            }
        }

        // ══ Available locales ═════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "public"
            title:    Translation.tr("Available locales")
            subtitle: root.locales.length + " installed"

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("Search locales")
                onEdited: function (v) { root.search = v }
            }

            // One segment: the list is a window onto ~500 rows, not 500 segments.
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
                            name: localeRow.selected ? "check_circle" : "radio_button_unchecked"
                            fill: localeRow.selected ? 1 : 0
                            variant: "body"
                            color: localeRow.selected ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
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

        // ══ The locale in use, and what it looks like ═════════════════════════
        // The formats follow the hovered locale in the list, so it can be browsed by consequence.
        Section {
            id: previewBox
            grouped:  true
            symbol:   "language"
            title:    Translation.tr("System locale")
            subtitle: root.hoverLocale !== "" ? Translation.tr("Previewing %1").arg(root.localeLabel(root.hoverLocale) || root.hoverLocale)
                                              : Translation.tr("Your current formats")
            help:     Translation.tr("What the system reports right now. Picking a locale in the list sets the language, date and number formats programs start with. It needs your password, and running programs keep the old one until they restart.")

            readonly property var  loc: Qt.locale(root.previewCode.split(".")[0])
            readonly property date now: new Date()

            SettingRow {
                label:  root.localeLabel(root.current) !== "" ? root.localeLabel(root.current)
                      : root.current !== "" ? root.current : "…"
                detail: root.current !== "" ? Translation.tr("System LANG: %1").arg(root.current) : ""
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

            // The five formats in one compact segment, read-only: a label over its value.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: 2
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingSm

                ColumnLayout {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { text: Translation.tr("Date"); variant: "micro"; emphasis: "dim" }
                    StyledText {
                        Layout.fillWidth: true
                        text: previewBox.now.toLocaleDateString(previewBox.loc, Locale.LongFormat)
                        variant: "body"; elide: Text.ElideRight
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 0
                    StyledText { text: Translation.tr("Time"); variant: "micro"; emphasis: "dim" }
                    StyledText {
                        Layout.fillWidth: true
                        text: previewBox.now.toLocaleTimeString(previewBox.loc, Locale.ShortFormat)
                        variant: "body"; elide: Text.ElideRight
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 0
                    StyledText { text: Translation.tr("Week starts"); variant: "micro"; emphasis: "dim" }
                    StyledText {
                        Layout.fillWidth: true
                        text: previewBox.loc.dayName(previewBox.loc.firstDayOfWeek, Locale.LongFormat)
                        variant: "body"; elide: Text.ElideRight
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 0
                    StyledText { text: Translation.tr("Numbers"); variant: "micro"; emphasis: "dim" }
                    StyledText {
                        Layout.fillWidth: true
                        text: Number(1234567.89).toLocaleString(previewBox.loc)
                        variant: "body"; elide: Text.ElideRight
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 0
                    StyledText { text: Translation.tr("Currency"); variant: "micro"; emphasis: "dim" }
                    StyledText {
                        Layout.fillWidth: true
                        text: Number(9.99).toLocaleCurrencyString(previewBox.loc)
                        variant: "body"; elide: Text.ElideRight
                    }
                }
            }
        }

        // ══ Weather location ══════════════════════════════════════════════════
        // Shell-wide: the weather widget, the clock panel, night light's sunset schedule and the
        // greeter read it, and the calendar's special dates follow its country.
        Section {
            grouped:  true
            symbol:   "partly_cloudy_day"
            title:    Translation.tr("Weather location")
            subtitle: Config.weatherPlace === "" ? "No location set" : Config.weatherPlace
            help:     Translation.tr("Used by the weather widget, the clock panel, night light's sunset schedule and the greeter. Only the place you pick is ever requested; your location is never looked up from your IP.")

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    id: cityField
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: Translation.tr("City name, then Enter")
                    // A network request: on Enter, never per keystroke.
                    onAccepted: function (v) { if (v.trim() !== "") Weather.search(v.trim()) }
                }
                BusyDot {
                    running: Weather.searching
                    visible: Weather.searching
                    tint: Colors.of(QsWindow.window).primary
                }
            }

            // Search results: one tappable row each; picking one sets the place and clears the list.
            Repeater {
                model: Weather.results

                SettingRow {
                    id: res
                    required property var modelData

                    rowTap: true
                    label:  res.modelData.name
                    detail: res.modelData.detail
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

            SettingRow {
                label:  Translation.tr("Temperature unit")
                detail: Config.weatherMetric ? Translation.tr("Celsius") : Translation.tr("Fahrenheit")
                help:   Translation.tr("Celsius or Fahrenheit for every temperature the weather shows.")

                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.unitWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: true,  label: "°C" },
                            { value: false, label: "°F" }]
                    current: Config.weatherMetric
                    onPicked: function (v) { Config.weatherMetric = v }
                }
            }
        }
    }
}
