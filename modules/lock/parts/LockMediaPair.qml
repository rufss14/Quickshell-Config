pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../overview"
import "../../discord"

// ── LockMediaPair ── part of LockScreen.qml; `lockSurface` is its lock surface (one per screen). ──
ColumnLayout {
    id: lockMediaPair
    required property var lockSurface
    property alias nowPlaying: nowPlaying
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Tokens.spacingXxl
    spacing: Tokens.spacingLg

    opacity: lockSurface.revealLast
    transform: Translate { y: (1 - lockSurface.revealLast) * 20 }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacingMd
        visible: lockSurface.mediaShown

        // Lyrics on the left, transport on the right — the same order the
        // overview puts them in, so the pair reads as the thing you already know.
        OverviewLyrics {
            Layout.preferredWidth:  320
            Layout.preferredHeight: 148
            player:   nowPlaying.player
            position: nowPlaying.pos
            // Fed from the media card's clock rather than starting a second one —
            // two timers following the same song drift, and the progress bar and
            // the lyrics would disagree about where it is.
            active:   Config.lockShowMedia && lockSurface.lyricsUseful
            skippable: false      // a locked screen changes nothing
            visible:  lockSurface.lyricsUseful
        }

        OverviewNowPlaying {
            id: nowPlaying
            Layout.preferredWidth:  420
            Layout.preferredHeight: 148
            // Not a bare `true`: `active` drives 32ms interpolation timers, and
            // running those for a card the user has switched off is exactly the
            // waste this property was introduced to prevent.
            active: Config.lockShowMedia
        }
    }


    // ── Footnotes ─────────────────────────────────────────────────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacingLg

        // Only when there is more than one layout, which is exactly when it can
        // be the reason a correct password is rejected — you cannot see what you
        // are typing, so a layout you did not mean to be on is invisible until it
        // has already cost you an attempt. One layout: nothing to warn about.
        RowLayout {
            visible: Keyboard.layouts.length > 1
            spacing: Tokens.spacingSm

            MaterialIcon {
                glyph: "󰌌"
                variant: "label"
                color: Colors.of(QsWindow.window).fgMuted
            }
            StyledText {
                text: Keyboard.layout
                variant: "caption"
                color: Colors.of(QsWindow.window).fgMuted
            }
        }

    }
}
