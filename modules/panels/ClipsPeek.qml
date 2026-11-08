pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clockfmt.js" as ClockFmt
// ── ClipsPeek ─────────────────────────────────────────────────────────────────
// Medal's "clipped!" moment: a save opens this beside the clips button for a
// moment (Config.clipsPeek), on the focused monitor, with the clip's thumbnail and
// what you'd do next — then it closes itself (SidePanelDock's `autoCloseMs`), later
// if the pointer is resting on it. The button only asks when the slot is free: a
// peek never pushes an open panel aside.
//
// It shows a COPY of what was saved, taken when it opened and never cleared
// (CLAUDE.md's fade rule): the next save must not rewrite a card on its way out.
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

    property var held: null
    Component.onCompleted: root.held = Clips.lastSaved
    // The library's entry for it, once indexed (it has the duration and a thumbnail).
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
                tint: Colors.of(QsWindow.window).focus
                enabled: root.held !== null
                onActivated: { Clips.playClip(root.held.path); UiState.closeSidePanel() }
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

        // What you would do next, as the panel's own chips (ChipTray): copy it, cut it (opens the
        // gallery's editor on it), send it to Discord (copies it and brings Discord forward — a paste
        // attaches the file), play it, or open the library.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            ChipTray {
                ChipButton {
                    symbol: "content_copy"
                    tint: Colors.of(QsWindow.window).focus
                    enabled: root.held !== null
                    onActivated: { Clips.copyClip(root.held.path); UiState.closeSidePanel() }
                }
                ChipButton {
                    symbol: "content_cut"
                    tint: Colors.of(QsWindow.window).focus
                    enabled: root.held !== null && (root.entry?.ok ?? false)
                    onActivated: { UiState.closeSidePanel(); Clips.editClip(root.held.path) }
                }
                ChipButton {
                    symbol: "send"
                    label: Translation.tr("Discord")
                    tint: Colors.of(QsWindow.window).focus
                    enabled: root.held !== null
                    onActivated: { Clips.sendToDiscord(root.held.path); UiState.closeSidePanel() }
                }
                ChipButton {
                    symbol: "play_arrow"
                    tint: Colors.of(QsWindow.window).focus
                    enabled: root.held !== null
                    onActivated: { Clips.playClip(root.held.path); UiState.closeSidePanel() }
                }
            }
            Item { Layout.fillWidth: true }
            ChipTray {
                ChipButton {
                    symbol: "movie"
                    tint: Colors.of(QsWindow.window).focus
                    onActivated: { UiState.closeSidePanel(); Clips.openGallery() }
                }
            }
        }
    }
}
