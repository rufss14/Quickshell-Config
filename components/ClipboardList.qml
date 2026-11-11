pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Widgets
import "../config"
import "../services"

// ── ClipboardList ─────────────────────────────────────────────────────────────
// Clipboard history as one chronological list: click a row to put it back, the tile
// expands an image, links open on their own button, ✕ removes one. Lifted out of
// OverviewClipboard so the overview card and the sidebar's clipboard panel
// (ClipboardSidePanel) draw the same rows — two copies would drift.
//
// Text and images interleave rather than splitting into tabs: you remember what you
// copied by when and roughly what it looked like, not by its type. All the real work
// is services/Clipboard; this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
ListView {
    id: list

    // How tall the list may get before it scrolls instead of growing — the caller
    // binds its height to min(contentHeight, this). The image preview caps on it too.
    property int maxListHeight: 420
    // Thumbnails are square tiles at the row's height; a wide screenshot is letterboxed
    // into one rather than stretching the row. 44 is the largest that still lets a text
    // row show two lines without the list feeling gappy.
    property int thumbSize: 44

    // A row was clicked and put back on the clipboard — the sidebar's panel steps
    // aside after it so you can paste.
    signal picked(var entry)

    clip: true
    spacing: Tokens.spacingSm
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 400

    // What to show of the history: words (any order, over the text, or a link's address) and a kind
    // ("" all, "text", "image", "link"). Both empty = everything, the history itself.
    property string query: ""
    property string kind: ""
    readonly property var shown: {
        const words = list.query.toLowerCase().split(/\s+/).filter(w => w !== "")
        if (words.length === 0 && list.kind === "") return Clipboard.entries
        return Clipboard.entries.filter(e => {
            const link = Clipboard.isLink(e)
            if (list.kind === "image" && e.kind !== "image") return false
            if (list.kind === "link" && !link) return false
            if (list.kind === "text" && (e.kind !== "text" || link)) return false
            if (words.length === 0) return true
            // A picture has no words to match.
            if (e.kind === "image") return false
            const hay = (e.preview || "").toLowerCase()
            return words.every(w => hay.indexOf(w) !== -1)
        })
    }

    model: list.shown

    delegate: Surface {
        id: row
        required property var modelData

        width: list.width
        implicitHeight: body.implicitHeight + Tokens.spacingMd * 2
        elevation:    Tokens.elevationNested
        cornerRadius: Tokens.radiusCard
        focused:      rowMouse.containsMouse || row.expanded

        readonly property bool isImage: row.modelData.kind === "image"
        readonly property bool isLink:  Clipboard.isLink(row.modelData)
        readonly property bool copied:  Clipboard.justCopied === row.modelData.hash

        // ── The expanded preview ──────────────────────────────────────
        // Only images expand. A link's preview would have to be FETCHED, which
        // means the shell making an outbound request to a site off your
        // clipboard — a different kind of feature, and not one to switch on
        // without asking. Text needs no preview: the row already shows it.
        readonly property bool canExpand: row.isImage && row.modelData.w > 0
        property bool expanded: false

        // Animated 0..1 driving the reveal, so opening glides. Same idiom as the
        // notification centre's pile, deliberately — one page, one motion.
        property real expand: row.expanded ? 1 : 0
        Behavior on expand {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
        }

        // Height the picture wants at this width, from the dimensions the STORE
        // recorded. Known before the image loads, so opening a preview doesn't
        // jolt the list while it decodes — which is the whole reason the store
        // reads image headers at capture time.
        readonly property real previewH: {
            if (!row.canExpand) return 0
            const w = list.width - Tokens.spacingMd * 2
            // Capped against the LIST's height as well as an absolute ceiling: a
            // preview that fills the whole visible list turns a history you were
            // scanning into a single picture, and the card is only ~330px tall in
            // the corner it actually lives in.
            return Math.min(220,
                            list.maxListHeight * 0.62,
                            w * row.modelData.h / row.modelData.w)
        }

        // Clicking the row puts it back on the clipboard. That's the whole point
        // of the panel, so it's the largest possible target rather than a button
        // you have to find — the thumbnail, Open and ✕ are carved out of it.
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Clipboard.copy(row.modelData)
                list.picked(row.modelData)
            }
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: 0

            RowLayout {
                id: rowContent
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                // ── Thumbnail / type tile ─────────────────────────────
                Rectangle {
                    id: tile
                    Layout.preferredWidth:  list.thumbSize
                    Layout.preferredHeight: list.thumbSize
                    Layout.alignment: Qt.AlignVCenter
                    radius: Tokens.radiusXs
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                    clip: true

                    // The payload is already a file on disk — no decode step, no
                    // subprocess. `sourceSize` caps the decode at tile size, so a
                    // 4K screenshot doesn't cost 30MB of pixmap to draw at 44px.
                    //
                    // Note it CANNOT tell you the picture's real size: read back,
                    // `sourceSize` returns the cap you set, not the source's
                    // dimensions (measured — an 88px-capped 1920x1080 reports
                    // 88x88). That is why `w`/`h` come from the store instead.
                    Image {
                        id: thumb
                        anchors.fill: parent
                        visible: row.isImage && status === Image.Ready
                        source: row.isImage ? "file://" + row.modelData.file : ""
                        sourceSize: Qt.size(list.thumbSize * 2, list.thumbSize * 2)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !thumb.visible
                        // Chain / picture / text-lines. All cmap-verified by
                        // rendering them, not by trusting a codepoint's name.
                        glyph: row.isLink ? "󰌹" : row.isImage ? "󰋩" : "󰈚"
                        color: row.isLink ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgDim
                        variant: "headline"
                    }

                    // Expand affordance, on the tile it acts on. A scrim behind
                    // it so the chevron stays legible over a bright photo.
                    Rectangle {
                        anchors.fill: parent
                        visible: row.canExpand && (tileMouse.containsMouse || row.expanded)
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.55)

                        MaterialIcon {
                            anchors.centerIn: parent
                            glyph: "󰅀"
                            color: Colors.of(QsWindow.window).fg
                            variant: "body"
                            rotation: row.expanded ? -180 : 0
                            Behavior on rotation {
                                NumberAnimation {
                                    duration: Motion.standard
                                    easing.type: Motion.travel
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: row.canExpand
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.expanded = !row.expanded
                    }
                }

                // ── Body ──────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs

                    // A link leads with its HOST. "where does this go" is the
                    // question you have about a URL you copied twenty minutes
                    // ago; the path almost never is, so it goes underneath.
                    StyledText {
                        Layout.fillWidth: true
                        text: row.isLink  ? Clipboard.linkHost(row.modelData)
                            : row.isImage ? (row.modelData.w > 0
                                             ? row.modelData.w + "×" + row.modelData.h
                                             : "Image")
                            : Clipboard.label(row.modelData)
                        variant: "body"
                        // Mono for text: most of what lands in a clipboard during
                        // this kind of work is code or a path, and a proportional
                        // face makes those harder to scan. A hostname is a name,
                        // so it reads better in the UI face.
                        font.family: (row.isImage || row.isLink) ? Tokens.fontFamily
                                                                 : Tokens.fontMono
                        font.weight: row.isLink ? Font.DemiBold : Font.Normal
                        color: row.isLink ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fg
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // Second line: a link's path, or the second line of a
                    // multi-line copy so a snippet is recognisable by more than
                    // its first word. Hidden when empty — a blank line would make
                    // every short entry taller than it needs to be.
                    StyledText {
                        Layout.fillWidth: true
                        visible: !row.isImage && text !== ""
                        text: row.isLink ? Clipboard.linkPath(row.modelData)
                                         : row.secondLine
                        variant: "caption"
                        emphasis: "dim"
                        font.family: Tokens.fontMono
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            visible: row.copied
                            name: "check"
                            variant: "caption"
                            color: Colors.of(QsWindow.window).success
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.copied ? "Copied" : Clipboard.detail(row.modelData)
                            variant: "caption"
                            color: row.copied ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgDim
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── Open a link ───────────────────────────────────────
                // Only for links, and separate from the row's copy action: a
                // clipboard panel's default verb is "put it back", and launching
                // a browser on a stray click would be a nasty surprise.
                PanelButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.isLink
                    variant: "ghost"
                    glyph: "󰏌"                  // arrow out of a box — open
                    onActivated: Clipboard.openLink(row.modelData)
                }

                // ── Remove just this entry ────────────────────────────
                // Its own target, outside the row's click area, so deleting
                // can't also copy the thing you were deleting.
                PanelButton {
                    Layout.alignment: Qt.AlignVCenter
                    variant: "ghost"
                    glyph: "󰅖"
                    onActivated: Clipboard.remove(row.modelData)
                }
            }

            // ── The preview ───────────────────────────────────────────
            // Inline rather than a floating popup: the card already lives in a
            // screen corner, and a popup would need its own window and its own
            // placement rules to avoid opening off-screen. Expanding in place
            // also matches the notification pile on the same page.
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingMd * row.expand
                Layout.preferredHeight: row.previewH * row.expand
                visible: row.expand > 0.005
                radius: Tokens.radiusXs
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

                // Loaded ONLY while open, and dropped again on collapse — a list
                // that decoded every stored screenshot at full size to render
                // 44px tiles is exactly the always-mounted cost this shell avoids.
                // Re-opening reads from the local file, so it costs nothing real.
                Image {
                    anchors.fill: parent
                    source: row.expanded ? "file://" + row.modelData.file : ""
                    sourceSize: Qt.size(720, 720)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
            }
        }

        // Computed here rather than in the binding above so the `visible` test
        // and the text read the same value instead of splitting the string twice.
        readonly property string secondLine: {
            if (row.isImage || row.isLink) return ""
            const raw = row.modelData.preview || ""
            const lines = raw.split("\n").filter(l => l.trim() !== "")
            return lines.length > 1 ? lines[1].trim() : ""
        }
    }
}
