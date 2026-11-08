pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── SettingsSearchResults ─────────────────────────────────────────────────────
// What the page area shows while the rail's search field has text.
//
// This was HomePage — a whole landing page holding one field and one list. The field
// lives in the rail now, reachable from every page, and the results take over the
// page area while you type. Clearing the field (or picking a result) puts the page
// back.
//
// ── Grouped, not flat ─────────────────────────────────────────────────────────
// The flat list repeated "Integrations › Discord" on line after line, and its icon
// column had no fixed width, so titles started a pixel or two apart. Results now
// fold by the view they live on (SettingsIndex.group — ranked and tested in
// settingssearch.js): one header per view, its matching settings in a card beneath.
// A view whose NAME matched is a header with no card; clicking a header opens the
// view.
//
// The matched part of each title is drawn in the accent, and the top result — what
// Enter opens — carries a key hint.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string query: ""
    signal picked(string file)

    readonly property var results: root.query.trim() === ""
        ? [] : SettingsIndex.search(root.query, 40)
    readonly property var groups: SettingsIndex.group(root.results)

    // ── Keyboard selection ────────────────────────────────────────────────────
    // An index into `results` — the FLAT ranked list — driven by the card's arrow
    // keys. The display groups those same result objects by view, so a row knows it
    // is selected by identity (`results[selectedIndex] === modelData`) rather than by
    // recomputing where it sits in the grouping.
    property int selectedIndex: -1

    // Keeps the selected row on screen when the arrows walk past the fold.
    function ensure(item) {
        if (!item) return
        const p = item.mapToItem(col, 0, 0)
        const top = p.y
        const bottom = top + item.height
        if (top < flick.contentY)
            flick.contentY = Math.max(0, top - Tokens.spacingMd)
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                      bottom - flick.height + Tokens.spacingMd)
    }

    // What Enter opens: the best result's file.
    readonly property string enterFile: root.results.length > 0 ? root.results[0].file : ""
    readonly property var enterRow: root.results.length > 0 && root.results[0].kind !== "page"
        ? root.results[0] : null

    // Enter takes the SELECTED result, falling back to the best match when the arrows
    // haven't been used yet.
    function pickFirst() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.results.length)
            root.picked(root.results[root.selectedIndex].file)
        else if (root.enterFile !== "")
            root.picked(root.enterFile)
    }

    // Title with the matched part in the accent, as StyledText markup. Every piece
    // is escaped: titles come from page sources and may contain `&` or `<`.
    function _esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function highlighted(text) {
        const m = SettingsIndex.splitMatch(text, root.query)
        if (m.match === "") return root._esc(m.before)
        return root._esc(m.before)
             + "<font color=\"" + Colors.of(QsWindow.window).focus + "\"><b>" + root._esc(m.match) + "</b></font>"
             + root._esc(m.after)
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth:  width
        contentHeight: col.implicitHeight + Tokens.spacingXl
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Tokens.spacingLg

            PanelHeader {
                Layout.fillHeight: false
                glyph:     "󰍉"
                title:     Translation.tr("Search")
                titleTail: "results"
                accent:    Colors.of(QsWindow.window).primary
                subtitle: {
                    // Honest about the degraded state rather than silently finding
                    // less: an absent index still finds every page by name.
                    if (SettingsIndex.indexLoaded && SettingsIndex.indexEntries.length === 0)
                        return "Page names only — run scripts/build-settings-index.py to rebuild the index."
                    if (root.results.length === 0)
                        return "Nothing matches “" + root.query.trim() + "” — try another word."
                    const n = root.results.length
                    const g = root.groups.length
                    return n + (n === 1 ? " match" : " matches")
                         + (g > 1 ? " across " + g + " pages" : "")
                }
            }

            Repeater {
                model: root.groups

                ColumnLayout {
                    id: grp
                    required property var modelData

                    readonly property var view: SettingsIndex.pageFor(grp.modelData.file)

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs

                    // ── Group header: the view ────────────────────────────────
                    Rectangle {
                        id: head
                        readonly property bool isSelected:
                            root.selectedIndex >= 0
                            && root.results[root.selectedIndex]
                            && root.results[root.selectedIndex].kind === "page"
                            && root.results[root.selectedIndex].file === grp.modelData.file

                        Layout.fillWidth: true
                        implicitHeight: headRow.implicitHeight + Tokens.spacingXs * 2
                        radius: Tokens.radiusSm
                        color: head.isSelected   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.18)
                             : headHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                                 : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        onIsSelectedChanged: if (head.isSelected) root.ensure(head)

                        RowLayout {
                            id: headRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin:  Tokens.spacingXs
                            anchors.rightMargin: Tokens.spacingSm
                            spacing: Tokens.spacingSm

                            // Fixed-size tile: every header's text starts at the same x.
                            Rectangle {
                                implicitWidth:  Tokens.iconXl
                                implicitHeight: Tokens.iconXl
                                radius: Tokens.radiusSm
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, grp.modelData.pageHit ? 0.24 : 0.12)

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    glyph: grp.view?.glyph ?? "󰍉"
                                    color: Colors.of(QsWindow.window).focus
                                    variant: "body"
                                }
                            }

                            StyledText {
                                rich: true
                                text: grp.modelData.pageHit ? root.highlighted(grp.modelData.page)
                                                            : root._esc(grp.modelData.page)
                                variant: "body"
                                font.weight: Font.DemiBold
                            }

                            // The rail page, when it isn't the same word (single-view pages).
                            StyledText {
                                Layout.fillWidth: true
                                visible: grp.modelData.group && grp.modelData.group !== grp.modelData.page
                                text: grp.modelData.group ?? ""
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillWidth: true; visible: !(grp.modelData.group && grp.modelData.group !== grp.modelData.page) }

                            EnterHint {
                                visible: head.isSelected
                                    || (root.selectedIndex < 0 && root.enterRow === null
                                        && root.enterFile === grp.modelData.file)
                            }
                            MaterialIcon {
                                visible: headHover.hovered
                                glyph: "󰅂"
                                color: Colors.of(QsWindow.window).fgMuted
                                variant: "body"
                            }
                        }

                        HoverHandler { id: headHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { onTapped: root.picked(grp.modelData.file) }
                    }

                    // ── The matching settings on it ───────────────────────────
                    Surface {
                        Layout.fillWidth: true
                        // Indented under the tile, so the card reads as belonging to it.
                        Layout.leftMargin: Tokens.iconXl + Tokens.spacingXs + Tokens.spacingSm
                        visible: grp.modelData.rows.length > 0
                        elevation: Tokens.elevationNested
                        castsShadow: false
                        implicitHeight: rowsCol.implicitHeight + Tokens.spacingXs * 2

                        ColumnLayout {
                            id: rowsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.spacingXs
                            spacing: 0

                            Repeater {
                                model: grp.modelData.rows

                                Rectangle {
                                    id: hit
                                    required property var modelData
                                    required property int index

                                    // The section is the only location left to say —
                                    // the page is in the header. Skipped when it
                                    // repeats the title (a Section's own entry).
                                    readonly property string where:
                                        hit.modelData.section && hit.modelData.section !== hit.modelData.title
                                            ? hit.modelData.section : ""

                                    readonly property bool isSelected:
                                        root.selectedIndex >= 0
                                        && root.results[root.selectedIndex] === hit.modelData

                                    Layout.fillWidth: true
                                    implicitHeight: hitRow.implicitHeight + Tokens.spacingSm * 2
                                    radius: Tokens.radiusXs
                                    color: hit.isSelected   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.18)
                                         : hitHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                                            : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                    onIsSelectedChanged: if (hit.isSelected) root.ensure(hit)

                                    RowLayout {
                                        id: hitRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin:  Tokens.spacingMd
                                        anchors.rightMargin: Tokens.spacingSm
                                        spacing: Tokens.spacingMd

                                        StyledText {
                                            Layout.fillWidth: true
                                            rich: true
                                            text: root.highlighted(hit.modelData.title)
                                            variant: "body"
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.maximumWidth: hitRow.width * 0.45
                                            visible: hit.where !== ""
                                            text: hit.where
                                            variant: "caption"
                                            emphasis: "dim"
                                            elide: Text.ElideRight
                                        }
                                        EnterHint { visible: hit.isSelected || (root.selectedIndex < 0 && root.enterRow === hit.modelData) }
                                        MaterialIcon {
                                            visible: hitHover.hovered
                                            glyph: "󰅂"
                                            color: Colors.of(QsWindow.window).fgMuted
                                            variant: "body"
                                        }
                                    }

                                    // Hairline between rows, not after the last.
                                    Rectangle {
                                        visible: hit.index < grp.modelData.rows.length - 1
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin:  Tokens.spacingMd
                                        anchors.rightMargin: Tokens.spacingMd
                                        height: 1
                                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).outline, 0.5)
                                    }

                                    HoverHandler { id: hitHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler   { onTapped: root.picked(hit.modelData.file) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Scrollbar { flickable: flick }

    // ── EnterHint — the small key cap on what Enter opens ────────────────────
    component EnterHint: Rectangle {
        implicitWidth:  hintText.implicitWidth + Tokens.spacingSm * 2
        implicitHeight: hintText.implicitHeight + Tokens.spacingXs
        radius: Tokens.radiusXs
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.35)

        StyledText {
            id: hintText
            anchors.centerIn: parent
            text: Translation.tr("Enter")
            variant: "micro"
            color: Colors.of(QsWindow.window).focus
        }
    }
}
