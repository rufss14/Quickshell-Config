import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── AppLauncherPanel ──────────────────────────────────────────────────────────
// Search, results, pinned apps.
//
// ── Geometry: three zones, no arithmetic ──────────────────────────────────────
// Three fixed-position zones stacked via anchors (no ColumnLayout, no binding
// arithmetic on heights mid-animation):
//
//   searchBar  — anchors.top,    fixed height
//   pinStrip   — anchors.bottom, fixed height, hidden when collapsed
//   listClip   — between the two
//
// `animH` is the ONE animated value. It sets implicitHeight on root so the parent
// PanelWindow resizes, and listClip derives its height purely from anchor geometry.
// Zero per-frame arithmetic, zero extra layout passes, no jitter. Don't "simplify"
// this into a ColumnLayout — that's what it used to be.
//
// ── Styling ───────────────────────────────────────────────────────────────────
// Every value here now comes from Tokens/Motion/Colors, and every piece of text is a
// StyledText. It used to hand-roll all of it: twelve raw `Text` elements each naming
// the font family and picking a pixel size, radii of 8/9/10, and durations of
// 100/130/140/160/180/200ms — none of which matched each other, let alone the rest of
// the shell.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal closeRequested()

    property string query: ""
    property bool   pinsExpanded: true

    // ── Pins ──────────────────────────────────────────────────────────────────
    // The list and its persistence live in the Pins service — the overview's dock needs
    // the same pins, and a second copy of the store would inevitably drift.
    readonly property var pinnedIds: Pins.ids

    function pinApp(id)   { if (!Pins.isPinned(id)) Pins.toggle(id) }
    function unpinApp(id) { if (Pins.isPinned(id))  Pins.toggle(id) }
    function isPinned(id) { return Pins.isPinned(id) }

    function entryForId(id) {
        const a = DesktopEntries.applications.values
        for (let i = 0; i < a.length; i++) if (a[i].id === id) return a[i]
        return null
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    readonly property var  allEntries:   DesktopEntries.applications.values
    readonly property bool hasResults:   filteredEntries.length > 0
    readonly property bool isExpanded:   hasResults || searchField.text.length > 0
    readonly property bool hasPins:      pinnedIds.length > 0
    readonly property bool showPinStrip: hasPins && pinsExpanded

    // ── Geometry ──────────────────────────────────────────────────────────────
    // Roomier than it was (50/46/62). The launcher is the surface you look at most, and
    // it was the most cramped thing in the shell.
    readonly property int searchBarH: 58
    readonly property int itemH:      54
    readonly property int maxListH:   350
    readonly property int pinStripH:  72

    readonly property int listMargins: Tokens.spacingMd * 2
    readonly property int wantListH:
        isExpanded ? Math.min(filteredEntries.length * itemH, maxListH) + listMargins : 0

    readonly property int wantTotalH:
        searchBarH + wantListH + (showPinStrip ? pinStripH : 0)

    // The tallest the panel can ever be — AppLauncherPopup sizes its PanelWindow from
    // this so the compositor never resizes a surface mid-animation.
    readonly property int maxTotalH: searchBarH + maxListH + pinStripH

    readonly property int animH: wantTotalH
    implicitHeight: animH

    // ── Icons ─────────────────────────────────────────────────────────────────
    // Straight through the Icons service, which already resolves Papirus first and
    // falls back to the theme.
    //
    // This used to build a path by hand:
    //     "file:///usr/share/icons/Papirus-Dark/48x48/apps/" + name + ".svg"
    // …and Papirus-DARK is a near-empty stub — its index.theme inherits breeze-dark, not
    // Papirus, and it ships almost no app icons. So that path 404'd for practically every
    // app, and each one silently limped to the fallback via an Image error handler. The
    // real icons are in plain `Papirus`, which is exactly what Icons.pathForAppId() knows.
    function iconFor(id) { return Icons.pathForAppId(id || "") }

    // ── Search filter + sort ─────────────────────────────────────────────────
    // Pinned apps get +10 on top of the match score so they always float up.
    // Match: 4=exact name, 3=name prefix, 2=name word-boundary, 1=generic name.
    readonly property var filteredEntries: {
        const q = query.trim().toLowerCase()
        if (q === "") return []

        const wordMatch = (s, needle) => {
            const idx = s.indexOf(needle)
            return idx === 0 || (idx > 0 && /[\s\-_.]/.test(s[idx - 1]))
        }

        const scored = []
        for (let i = 0; i < allEntries.length; i++) {
            const e = allEntries[i]
            if (e.noDisplay) continue

            const name    = (e.name        || "").toLowerCase()
            const generic = (e.genericName || "").toLowerCase()

            let score = 0
            if      (name === q)            score = 4
            else if (name.startsWith(q))    score = 3
            else if (wordMatch(name, q))    score = 2
            else if (wordMatch(generic, q)) score = 1
            if (score === 0) continue

            if (root.isPinned(e.id)) score += 10
            scored.push({ e: e, score: score })
        }

        scored.sort((a, b) => b.score - a.score
                           || (a.e.name || "").localeCompare(b.e.name || ""))
        return scored.map(s => s.e)
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        root.closeRequested()
    }

    // ── Called by AppLauncherPopup ────────────────────────────────────────────
    // Part of this panel's contract with its host, not dead code: the popup focuses the
    // field when it opens, and clears it on close so `animH` collapses BEFORE the fade
    // starts — otherwise the card flashes at full height the next time it opens.
    function focusSearch() { searchField.forceActiveFocus() }

    function resetSearch() {
        searchField.text = ""
        root.query = ""
        list.currentIndex = 0
    }

    Keys.onPressed: function(ev) {
        if (ev.key === Qt.Key_Escape) {
            root.closeRequested(); ev.accepted = true
        } else if (ev.key === Qt.Key_Down) {
            if (filteredEntries.length > 0) {
                list.currentIndex = Math.max(0, list.currentIndex); list.forceActiveFocus()
            }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Up) {
            if (list.currentIndex <= 0) searchField.forceActiveFocus()
            else { list.currentIndex--; list.forceActiveFocus() }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            if (filteredEntries.length > 0) launch(filteredEntries[Math.max(0, list.currentIndex)])
            ev.accepted = true
        }
    }

    // ══ SEARCH BAR ════════════════════════════════════════════════════════════
    Item {
        id: searchBar
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height: root.searchBarH

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:   Tokens.spacingLg
            anchors.rightMargin:  Tokens.spacingLg
            anchors.topMargin:    Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            // ── The search pill ───────────────────────────────────────────────
            // An inset pill on the card, exactly as the bar insets its controls into a
            // group: `elevationNested` for the fill and border, `radiusPill` for the
            // corner. That's what the Nested elevation is FOR — a control sitting on
            // another surface needs a stronger border than one sitting on the wallpaper,
            // or the nesting reads as the parent simply changing shape.
            //
            // It lights with `focus` when the field has keyboard focus, which is the same
            // signal every other focusable surface in the shell gives.
            Surface {
                Layout.fillWidth:  true
                Layout.fillHeight: true

                elevation:    Tokens.elevationNested
                cornerRadius: Tokens.radiusPill
                focused:      searchField.activeFocus

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingSm
                    spacing: Tokens.spacingMd

                    StyledText {
                        text: "󰍉"
                        variant: "title"
                        color: searchField.activeFocus ? Colors.focus : Colors.fgDim
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    Item {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        TextInput {
                            id: searchField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter

                            font.family:    Tokens.fontFamily
                            font.pixelSize: Tokens.fontBody

                            color:             Colors.fg
                            selectionColor:    Colors.alpha(Colors.focus, 0.28)
                            selectedTextColor: Colors.fg
                            clip: true

                            onTextChanged: { root.query = text; list.currentIndex = 0 }

                            Keys.onPressed: function(ev) {
                                if (ev.key === Qt.Key_Escape) {
                                    // Escape clears the query first, and only closes the
                                    // launcher once there's nothing left to clear.
                                    if (text.length > 0) { text = ""; ev.accepted = true }
                                    else { root.closeRequested(); ev.accepted = true }
                                } else if (ev.key === Qt.Key_Down && root.filteredEntries.length > 0) {
                                    list.currentIndex = 0; list.forceActiveFocus(); ev.accepted = true
                                } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                                    if (root.filteredEntries.length > 0) root.launch(root.filteredEntries[0])
                                    ev.accepted = true
                                }
                            }

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: searchField.text.length === 0
                                text: "Search anything…"
                                variant: "body"
                                color: Colors.fgDim
                            }
                        }
                    }

                    // Clear. Inside the pill — it acts on the field, so it belongs to it.
                    PanelButton {
                        Layout.alignment: Qt.AlignVCenter
                        variant: "ghost"
                        implicitWidth:  24
                        implicitHeight: 24
                        glyph: "󰅖"
                        opacity: searchField.text.length > 0 ? 1 : 0
                        enabled: searchField.text.length > 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        onActivated: { searchField.text = ""; searchField.forceActiveFocus() }
                    }
                }
            }

            // Pins show/hide. OUTSIDE the pill — it acts on the panel, not on the search
            // field. `primary` when on: it's a toggle you're acting through.
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                variant: root.pinsExpanded ? "primary" : "normal"
                accent:  Colors.focus
                implicitWidth:  34
                implicitHeight: 34
                glyph: root.pinsExpanded ? "󰅃" : "󰅀"
                opacity: root.hasPins ? 1 : 0
                enabled: root.hasPins
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                onActivated: root.pinsExpanded = !root.pinsExpanded
            }
        }

        Divider {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            opacity: root.isExpanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        }
    }

    // ══ PIN STRIP ═════════════════════════════════════════════════════════════
    // `visible` (not just opacity) so it never sits invisibly over the search bar
    // intercepting clicks when collapsed.
    Item {
        id: pinStrip
        anchors.left:  parent.left
        anchors.right: parent.right
        y:       root.wantTotalH - root.pinStripH
        height:  root.pinStripH
        visible: root.showPinStrip
        clip:    true

        Divider {
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
        }

        ListView {
            id: pinListView
            anchors.fill: parent
            anchors.topMargin:    Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingMd
            anchors.leftMargin:   Tokens.spacingLg
            anchors.rightMargin:  Tokens.spacingLg
            orientation: ListView.Horizontal
            spacing: Tokens.spacingMd
            clip: true

            WheelHandler {
                onWheel: function(ev) {
                    pinListView.contentX = Math.max(0,
                        Math.min(pinListView.contentX - ev.angleDelta.y * 0.4,
                                 Math.max(0, pinListView.contentWidth - pinListView.width)))
                }
            }

            model: root.pinnedIds

            delegate: Item {
                id: pin
                required property string modelData

                readonly property var    entry:    root.entryForId(modelData)
                readonly property string iconPath: root.iconFor(modelData)
                readonly property string label:    entry ? (entry.name || modelData) : modelData

                height: pinListView.height
                width:  height

                Rectangle {
                    id: pinBox
                    anchors.centerIn: parent
                    width:  42
                    height: 42
                    radius: Tokens.radiusSm

                    color: pinH.hovered ? Colors.stateHoverBg : Colors.surfaceContainer
                    border.width: Tokens.borderWidth
                    border.color: pinH.hovered ? Colors.outlineFocus : Colors.outline

                    scale: pinH.hovered ? 1.08 : 1.0

                    Behavior on color        { ColorAnimation  { duration: Motion.respond } }
                    Behavior on border.color { ColorAnimation  { duration: Motion.respond } }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.fast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.effects
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        visible: pin.iconPath !== ""
                        source:  pin.iconPath
                        width:  26
                        height: 26
                        sourceSize: Qt.size(52, 52)     // 2× for HiDPI, then downscaled
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        smooth: true
                    }

                    // A letter, not a fallback icon NAME — "application-x-executable" isn't
                    // in this theme, so asking for it just trades one missing icon for
                    // another. A letter always renders.
                    StyledText {
                        anchors.centerIn: parent
                        visible: pin.iconPath === ""
                        text: pin.label.charAt(0).toUpperCase()
                        variant: "title"
                        font.bold: true
                        color: Colors.focus
                    }

                    HoverHandler { id: pinH }
                    TapHandler   { onTapped: root.launch(pin.entry) }
                }

                // Unpin.
                Rectangle {
                    anchors.top:   pinBox.top
                    anchors.right: pinBox.right
                    anchors.margins: -4
                    width:  16
                    height: 16
                    radius: 8
                    color: Colors.danger

                    opacity: pinH.hovered ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                    StyledText {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: Colors.fgOnPrimary
                        font.pixelSize: 9
                    }

                    TapHandler { onTapped: root.unpinApp(pin.modelData) }
                }
            }
        }
    }

    // ══ RESULTS ═══════════════════════════════════════════════════════════════
    // Height emerges from anchor geometry alone — never calculated. That's what keeps
    // this from jittering during the card's resize.
    Item {
        id: listClip
        anchors.top:   searchBar.bottom
        anchors.left:  parent.left
        anchors.right: parent.right
        height: root.wantListH
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.topMargin:    Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingMd
            anchors.leftMargin:   Tokens.spacingMd
            anchors.rightMargin:  Tokens.spacingMd
            clip:  true
            focus: true
            spacing: 2

            highlightFollowsCurrentItem: true
            highlightMoveDuration: Motion.fast
            highlight: Rectangle { color: "transparent" }

            model: root.filteredEntries
            onModelChanged: { positionViewAtBeginning(); currentIndex = 0 }

            Keys.onPressed: function(ev) {
                if (ev.key === Qt.Key_Escape) {
                    root.closeRequested(); ev.accepted = true
                } else if (ev.key === Qt.Key_Up && currentIndex === 0) {
                    searchField.forceActiveFocus(); ev.accepted = true
                } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                    if (currentItem) root.launch(root.filteredEntries[currentIndex])
                    ev.accepted = true
                }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                width:  list.width
                height: root.itemH
                radius: Tokens.radiusSm

                readonly property bool isCurrent: list.currentIndex === index
                readonly property bool isActive:  isCurrent || rowHov.hovered
                readonly property bool pinned:    root.isPinned(modelData.id)
                readonly property string iconPath: root.iconFor(modelData.id)

                // Selection is `focus` — "this is the one you're pointing at" — and that's
                // the shell's rule everywhere else. It used to hash the app's id into one of
                // five palette colours, which meant every row was a different accent for no
                // reason anyone could read, and on a monochrome wallpaper they were five
                // shades of the same grey anyway.
                color: row.isCurrent    ? Colors.alpha(Colors.focus, 0.14)
                     : rowHov.hovered   ? Colors.surfaceContainer
                     : "transparent"

                border.width: row.isCurrent ? Tokens.borderWidth : 0
                border.color: Colors.outlineFocus

                Behavior on color        { ColorAnimation { duration: Motion.respond } }
                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                HoverHandler {
                    id: rowHov
                    onHoveredChanged: if (hovered) list.currentIndex = row.index
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.launch(row.modelData)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: row.pinned ? root.unpinApp(row.modelData.id)
                                         : root.pinApp(row.modelData.id)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingLg

                    Rectangle {
                        Layout.preferredWidth:  38
                        Layout.preferredHeight: 38
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusSm

                        color: row.isActive ? Colors.surfaceHigh : Colors.surfaceContainer
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        Image {
                            anchors.centerIn: parent
                            visible: row.iconPath !== ""
                            source:  row.iconPath
                            width:  26
                            height: 26
                            sourceSize: Qt.size(52, 52)
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                            smooth: true
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: row.iconPath === ""
                            text: (row.modelData.name || row.modelData.id || "?").charAt(0).toUpperCase()
                            variant: "label"
                            font.bold: true
                            color: Colors.focus
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name || row.modelData.id || ""
                            variant: "body"
                            font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                            color: Colors.fg
                            opacity: row.isActive ? 1.0 : 0.82
                            elide: Text.ElideRight
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: row.modelData.genericName || ""
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }

                    // Pinned already, or "right-click to pin" on hover.
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: row.pinned ? "󰐃" : "󰐄"
                        variant: "label"
                        color: row.pinned ? Colors.focus : Colors.fgDim
                        opacity: row.pinned ? 1.0 : (row.isActive ? 0.45 : 0.0)
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }
            }
        }

        // Empty state.
        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingMd
            visible: searchField.text.length > 0 && !root.hasResults

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰍉"
                font.pixelSize: 28
                color: Colors.fgDim
                opacity: 0.5
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No results for “" + searchField.text + "”"
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
