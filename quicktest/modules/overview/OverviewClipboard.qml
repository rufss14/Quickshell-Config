pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── OverviewClipboard ─────────────────────────────────────────────────────────
// Clipboard history on the overview's notifications page, bottom-left — the same card
// language as the notification centre diagonally opposite it: one Surface at card
// elevation, a tinted glyph disc in the header, a hold-to-confirm destructive action,
// and a list that grows with its content instead of filling the corner.
//
// ── Why it mirrors the notification centre so closely ─────────────────────────
// The two answer the same shape of question — "what happened while I wasn't looking,
// and can I act on it" — and they share a screen. Giving them different list idioms
// would make one page look like two.
//
// ── Text and images are one list, not two tabs ────────────────────────────────
// You don't remember what you copied by its type, you remember it by when and roughly
// what it looked like. So they interleave in one chronological list and the row simply
// renders differently: an image gets a thumbnail, text gets its first lines. Splitting
// them would mean checking two places for the thing you copied a minute ago.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard
    implicitWidth:  400
    implicitHeight: layout.implicitHeight + Tokens.spacingXl * 2

    // How tall the scrolling list may get before it scrolls instead of growing. The
    // caller lowers it to fit the corner it's placed in.
    property int maxListHeight: 420

    // Thumbnails are square tiles at the row's height; a wide screenshot is letterboxed
    // into one rather than stretching the row. 44 is the largest that still lets a text
    // row show two lines without the list feeling gappy.
    readonly property int thumbSize: 44

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            Rectangle {
                Layout.preferredWidth:  30
                Layout.preferredHeight: 30
                radius: Tokens.radiusSm
                color: Colors.alpha(Colors.focus, 0.16)

                StyledText {
                    anchors.centerIn: parent
                    text: "󰅍"                  // clipboard with lines — cmap-verified
                    color: Colors.focus
                    variant: "title"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: "Clipboard"
                    variant: "title"
                    font.bold: true
                }
                StyledText {
                    text: Clipboard.count === 0 ? "Nothing copied yet"
                        : Clipboard.count === 1 ? "1 item"
                        : Clipboard.count + " items"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }

        Divider {}

        // ── Wipe toolbar ──────────────────────────────────────────────────────
        // Hold-to-confirm, and the same HoldButton the notification centre uses for
        // Clear all — this deletes the payloads too, not just the list, so it is the
        // more destructive of the two. Only shown when there is something to wipe.
        RowLayout {
            Layout.fillWidth: true
            visible: Clipboard.count > 0
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: root.imageCount > 0
                      ? root.imageCount + (root.imageCount === 1 ? " image" : " images")
                      : "text only"
                variant: "caption"
                emphasis: "dim"
            }

            HoldButton {
                Layout.alignment: Qt.AlignVCenter
                glyph: "󰃢"                     // broom — same as Clear all
                label: "Wipe all"
                busyLabel: "Hold to wipe…"
                onConfirmed: Clipboard.wipe()
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            visible: Clipboard.count === 0
            spacing: Tokens.spacingMd

            StyledText { text: "󰅍"; font.pixelSize: 22; color: Colors.fgDim; opacity: 0.5 }
            StyledText {
                Layout.fillWidth: true
                text: "Copy something and it'll show up here — text or images."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── The list ──────────────────────────────────────────────────────────
        // preferredHeight, not fillHeight, so the card's height follows its content up
        // to maxListHeight and only then scrolls — the same contract as the notification
        // centre, which is what keeps the two corners visually balanced.
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            visible: Clipboard.count > 0
            clip: true
            spacing: Tokens.spacingSm
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            model: Clipboard.entries

            delegate: Surface {
                id: row
                required property var modelData

                width: list.width
                implicitHeight: body.implicitHeight + Tokens.spacingMd * 2
                elevation:    Tokens.elevationNested
                cornerRadius: Tokens.radiusSm
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
                                    root.maxListHeight * 0.62,
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
                    onClicked: Clipboard.copy(row.modelData)
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
                            Layout.preferredWidth:  root.thumbSize
                            Layout.preferredHeight: root.thumbSize
                            Layout.alignment: Qt.AlignVCenter
                            radius: Tokens.radiusXs
                            color: Colors.alpha(Colors.fg, 0.06)
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
                                sourceSize: Qt.size(root.thumbSize * 2, root.thumbSize * 2)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: !thumb.visible
                                // Chain / picture / text-lines. All cmap-verified by
                                // rendering them, not by trusting a codepoint's name.
                                text: row.isLink ? "󰌹" : row.isImage ? "󰋩" : "󰈚"
                                color: row.isLink ? Colors.focus : Colors.fgDim
                                font.pixelSize: 18
                            }

                            // Expand affordance, on the tile it acts on. A scrim behind
                            // it so the chevron stays legible over a bright photo.
                            Rectangle {
                                anchors.fill: parent
                                visible: row.canExpand && (tileMouse.containsMouse || row.expanded)
                                color: Colors.alpha(Colors.base, 0.55)

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "󰅀"
                                    color: Colors.fg
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
                            spacing: 2

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
                                color: row.isLink ? Colors.focus : Colors.fg
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

                            StyledText {
                                Layout.fillWidth: true
                                text: row.copied ? "󰄬  Copied"
                                                 : Clipboard.detail(row.modelData)
                                variant: "caption"
                                color: row.copied ? Colors.success : Colors.fgDim
                                elide: Text.ElideRight
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
                        color: Colors.alpha(Colors.fg, 0.06)

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
    }

    // How many stored entries are images — the header's one piece of texture, and the
    // thing that tells you at a glance whether that screenshot is still in here.
    readonly property int imageCount:
        Clipboard.entries.filter(e => e.kind === "image").length
}
