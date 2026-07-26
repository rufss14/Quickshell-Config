pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"

// ── LanguagePage ──────────────────────────────────────────────────────────────
// The system locale, via localectl.
//
// `localectl set-locale` goes through polkit, so applying one may raise an
// authentication prompt from the agent — and may simply be refused. That's why this
// page reports a status line instead of assuming the click worked: it re-reads the
// locale afterwards and shows what the system actually says, not what we asked for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string current: ""
    property var    locales: []
    property string status:  ""
    property bool   failed:  false

    property string search: ""

    readonly property var filtered: {
        const s = root.search.trim().toLowerCase()
        return s === "" ? root.locales
                        : root.locales.filter(l => l.toLowerCase().includes(s)
                                               || root.localeLabel(l).toLowerCase().includes(s))
    }

    // ── "en_US.UTF-8" → "English (United States)" ─────────────────────────────
    // Qt carries the whole CLDR name table, so the names cost no process and no data
    // file. An unknown code comes back as the C locale, whose language name is empty —
    // which is also the honest answer for C.UTF-8 itself.
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
    // Pointing at a locale shows what dates and numbers would look like BEFORE
    // applying it — applying needs authentication and restarts to fully land, so the
    // preview answers the question the click would otherwise be the only way to ask.
    property string hoverLocale: ""
    readonly property string previewCode: root.hoverLocale !== "" ? root.hoverLocale
                                                                  : root.current

    // `localectl status` prints a block; LANG= is the line that matters.
    Process {
        id: currentQuery
        running: true
        command: ["bash", "-c",
                  "localectl status 2>/dev/null | sed -n 's/.*LANG=\\([^ ]*\\).*/\\1/p'"]
        stdout: StdioCollector { onStreamFinished: root.current = text.trim() }
    }

    Process {
        id: listQuery
        running: true
        command: ["localectl", "list-locales"]
        stdout: StdioCollector {
            onStreamFinished: root.locales = text.trim() === "" ? [] : text.trim().split("\n")
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }

        onExited: function(code) {
            root.failed = code !== 0
            root.status = code === 0
                ? "Applied. Most apps pick it up on their next start."
                : (setErr.text.trim() || "Could not set the locale.")
            // Re-read rather than trust: polkit may have refused, and the page
            // should show the locale the system HAS, not the one we asked for.
            currentQuery.running = false
            currentQuery.running = true
        }
    }

    function setLocale(name) {
        root.failed = false
        root.status = "Applying " + name + "…"
        setProc.running = false
        setProc.command = ["localectl", "set-locale", "LANG=" + name]
        setProc.running = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     "󰗊"
            title:     "Language"
            titleTail: "& region"
            subtitle:  root.current !== "" ? root.current : "Reading locale…"
        }

        Divider {}

        // ── Two columns ───────────────────────────────────────────────────────
        // The page is ~1500px wide. A single column would put a 34px-tall locale row
        // across the whole card with 1400px of nothing after "en_US.UTF-8" — so the
        // explanation goes beside the list rather than the list going nowhere.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingXl

        ColumnLayout {
            Layout.preferredWidth: 380
            Layout.minimumWidth:   380
            Layout.maximumWidth:   380
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            StyledText { text: "Current"; variant: "label"; emphasis: "muted" }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: currentBox.implicitHeight + Tokens.spacingLg * 2

                RowLayout {
                    id: currentBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingLg

                    StyledText {
                        text:  "󰗊"
                        color: Colors.focus
                        font.family: Tokens.fontFamily
                        font.pixelSize: 34
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
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
                            text: (root.localeLabel(root.current) !== ""
                                   ? root.localeLabel(root.current) + "  ·  " : "")
                                + "System LANG"
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "How it looks"
                variant: "label"
                emphasis: "muted"
            }

            // ── Format preview ────────────────────────────────────────────────
            // What LANG actually changes, shown as the things it changes. Follows the
            // hovered locale so the list can be browsed by consequence, not by code.
            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: previewBox.implicitHeight + Tokens.spacingLg * 2

                ColumnLayout {
                    id: previewBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    readonly property var loc: Qt.locale(root.previewCode.split(".")[0])
                    readonly property date now: new Date()

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: root.hoverLocale !== "" ? "Previewing " + root.hoverLocale
                                                          : "Your current formats"
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }

                    component FormatRow: RowLayout {
                        property string label: ""
                        property string value: ""
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd
                        StyledText {
                            Layout.preferredWidth: 90
                            text: label
                            variant: "caption"
                            emphasis: "dim"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: value
                            variant: "caption"
                            elide: Text.ElideRight
                        }
                    }

                    FormatRow {
                        label: "Date"
                        value: previewBox.now.toLocaleDateString(previewBox.loc, Locale.LongFormat)
                    }
                    FormatRow {
                        label: "Time"
                        value: previewBox.now.toLocaleTimeString(previewBox.loc, Locale.ShortFormat)
                    }
                    FormatRow {
                        label: "Numbers"
                        value: Number(1234567.89).toLocaleString(previewBox.loc)
                    }
                    FormatRow {
                        label: "Currency"
                        value: Number(9.99).toLocaleCurrencyString(previewBox.loc)
                    }
                    FormatRow {
                        label: "Week starts"
                        value: previewBox.loc.dayName(previewBox.loc.firstDayOfWeek, Locale.LongFormat)
                    }
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "What this does"
                variant: "label"
                emphasis: "muted"
            }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: explainBox.implicitHeight + Tokens.spacingLg * 2

                ColumnLayout {
                    id: explainBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    StyledText {
                        Layout.fillWidth: true
                        text: "Sets the system LANG through localectl — the language, date format, and number format that programs start with."
                        variant:  "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Changing it needs authentication, so a password prompt may appear — and it can be refused. Whatever happens, the value above is re-read afterwards, so it always shows what the system actually has rather than what was asked for."
                        variant:  "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Programs already running keep the old locale until they restart."
                        variant:  "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Status only exists after you've tried to apply something, so it takes no
            // room until then. `danger` on failure, `focus` while it's in progress —
            // "working on it" is a state, not an error.
            Surface {
                Layout.fillWidth: true
                visible:   root.status !== ""
                elevation: Tokens.elevationNested
                implicitHeight: statusText.implicitHeight + Tokens.spacingMd * 2

                StyledText {
                    id: statusText
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingMd
                    text:     root.status
                    color:    root.failed ? Colors.danger : Colors.focus
                    variant:  "caption"
                    wrapMode: Text.WordWrap
                }
            }

            Item { Layout.fillHeight: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            StyledText {
                text: "Available locales — " + root.locales.length + " installed"
                variant: "label"
                emphasis: "muted"
            }

        Surface {
            Layout.fillWidth: true
            implicitHeight: 32
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            focused:      searchInput.activeFocus

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingMd
                verticalAlignment: TextInput.AlignVCenter

                color: Colors.fg
                selectionColor:    Colors.alpha(Colors.focus, 0.28)
                selectedTextColor: Colors.fg
                font.family:    Tokens.fontFamily
                font.pixelSize: Tokens.fontBody

                onTextChanged: root.search = text

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible:  searchInput.text === ""
                    text:     "Search locales…"
                    emphasis: "dim"
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.filtered

            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: localeRow
                required property string modelData

                readonly property bool selected: localeRow.modelData === root.current

                width:  ListView.view ? ListView.view.width : 0
                height: 34
                radius: Tokens.radiusSm

                color: localeRow.selected ? Colors.alpha(Colors.focus, 0.14)
                     : rowHover.hovered   ? Colors.alpha(Colors.fg, 0.06)
                     :                      "transparent"
                Behavior on color { ColorAnimation { duration: Motion.respond } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: root.localeLabel(localeRow.modelData) !== ""
                            ? root.localeLabel(localeRow.modelData)
                            : localeRow.modelData
                        variant: "body"
                        font.weight: localeRow.selected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.localeLabel(localeRow.modelData) !== ""
                        text: localeRow.modelData
                        variant: "caption"
                        emphasis: "dim"
                        font.family: Tokens.fontMono
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: localeRow.selected
                        text:    "󰄬"
                        color:   Colors.focus
                        variant: "body"
                    }
                }

                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                    // Feeds the format-preview card on the left; cleared only if this
                    // row still owns the preview, so crossing rows doesn't flicker it.
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
    }
}
