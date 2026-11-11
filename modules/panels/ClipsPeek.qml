pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clockfmt.js" as ClockFmt
import "../../services/clips.js" as ClipsJs
// ── ClipsPeek ─────────────────────────────────────────────────────────────────
// Medal's "clipped!" moment: a save opens this beside the clips button for a
// moment (Config.clipsPeek), on the focused monitor, with the clip's thumbnail and
// what you'd do next — then it closes itself (SidePanelDock's `autoCloseMs`), later
// if the pointer is resting on it. The button only asks when the slot is free: a
// peek never pushes an open panel aside.
//
// It shows a COPY of what was saved, taken when it opened and never cleared
// (CLAUDE.md's fade rule): the next save must not rewrite a card on its way out.
//
// A thin rail under the frame runs down with the time it has left (the dock's own rule: restarted
// when the pointer leaves, held while it rests there). The song that was playing and who was in
// the call, when stamped, are the line under the name.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity
    // How long it stays up. An interaction timing, not a Motion duration: with
    // motion off those are 0, and a peek that closes the frame it opens says nothing.
    readonly property int autoCloseMs: 2600

    readonly property int pad: Tokens.spacingMd
    implicitWidth: Tokens.sideCardUnit * 6
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property var pal: Colors.of(QsWindow.window)
    property var held: null
    Component.onCompleted: { root.held = Clips.lastSaved; railAnim.restart() }

    // The time left, 1 → 0. A countdown is linear.
    property real rail: 1
    NumberAnimation { id: railAnim; target: root; property: "rail"; from: 1; to: 0; duration: root.autoCloseMs; easing.type: Easing.Linear }
    HoverHandler { onHoveredChanged: if (!hovered) railAnim.restart() }
    // The library's entry for it, once indexed (it has the duration and a thumbnail).
    readonly property string context: root.held ? ClipsJs.contextLine(Clips.contextOf(root.held.path)) : ""
    readonly property var entry: root.held ? (Clips.clips.find(c => c.path === root.held.path) ?? null) : null

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingSm

        // The frame is a play button: it plays the clip in THIS shell (the gallery's player).
        ClipThumb {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(width * 9 / 16)
            radius: Tokens.radiusCard
            entry: root.entry
            decodeWidth: 320
            CookieButton {
                anchors.centerIn: parent
                width: Tokens.iconXl * 2.2
                height: width
                name: "play_arrow"
                primary: true
                tint: root.pal.focus
                enabled: root.held !== null
                onActivated: { Clips.playClip(root.held.path); UiState.closeSidePanel() }
            }
            // How long the card has left.
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Tokens.spacingXs
                width: parent.width * root.rail
                color: root.pal.primary
            }
        }

        IconLine {
            glyph: "\u{F012C}"                                              // 󰄬 check
            text: root.held && root.held.type !== "replay" ? "Recording saved" : "Clip saved"
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            variant: "caption"
            emphasis: "dim"
            text: root.entry ? root.entry.name + "  ·  " + ClockFmt.clock(root.entry.duration)
                : root.held ? root.held.path.split("/").pop() : ""
        }
        // What was going on: the song, and who was in the call.
        StyledText {
            Layout.fillWidth: true
            visible: root.context !== ""
            elide: Text.ElideRight
            variant: "micro"
            emphasis: "dim"
            text: root.context
        }

        // What you would do next, as the panel's own chips (ChipTray): copy it, cut it (opens the
        // gallery's editor on it), send it to Discord (shrunk under the upload cap if need be, then copied
        // — a paste attaches the file), keep it (a star), or open the library. The frame plays it.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            ChipTray {
                ChipButton {
                    symbol: "content_copy"
                    tint: root.pal.focus
                    enabled: root.held !== null
                    onActivated: { Clips.copyClip(root.held.path); UiState.closeSidePanel() }
                }
                ChipButton {
                    symbol: "content_cut"
                    tint: root.pal.focus
                    enabled: root.held !== null && (root.entry?.ok ?? false)
                    onActivated: { UiState.closeSidePanel(); Clips.editClip(root.held.path) }
                }
                ChipButton {
                    symbol: "send"
                    label: Translation.tr("Discord")
                    tint: root.pal.focus
                    enabled: root.held !== null && Clips.sharing === ""
                    onActivated: { Clips.sendToDiscord(root.held.path); UiState.closeSidePanel() }
                }
                ChipButton {
                    symbol: "star"
                    on: root.held !== null && Clips.isFavourite(root.held.path)
                    tint: root.pal.focus
                    enabled: root.held !== null
                    onActivated: Clips.toggleFavourite(root.held.path)
                }
            }
            Item { Layout.fillWidth: true }
            ChipTray {
                ChipButton {
                    symbol: "movie"
                    tint: root.pal.focus
                    onActivated: { UiState.closeSidePanel(); Clips.openGallery() }
                }
            }
        }
    }
}
