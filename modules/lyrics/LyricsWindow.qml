import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"
import "../overview"
import "../../services"

// ── LyricsWindow ────────────────────────────────────────────────────────────
// The overview's lyrics card, standalone in a resizable window — launched from
// the search bar (scripts/install-lyrics-entry.sh → scripts/lyrics-open.sh),
// the same way Settings is, or by IPC:
//     qs ipc -p ~/.config/quicktest call lyricswindow open
//
// It is the SAME card modules/desktop/widgets/LyricsWidget.qml puts on the
// desktop and the overview puts beside Now Playing — not a second lyrics view
// to keep in sync. MediaPosition supplies the clock exactly like the desktop
// tile does: OverviewLyrics does not own one, and it already prefers Spotify's
// own bridged playhead and syllable timing over MPRIS/NetEase the moment
// Spotify is the active player — nothing here has to know that.
//
// ── Why a FloatingWindow, and why it resets nothing ───────────────────────────
// Same xdg-toplevel reasoning as SettingsWindow: a layer-shell overlay sits
// above the bar and would need its own arrange-mode dance to be resizable at
// all, where a toplevel gets real window resize handles for free. Unlike
// Settings, this one is left at whatever size and position you last put it —
// there's no "always launches the same" case here, and a lyrics window that
// snapped back to 420×280 every time you'd resized it to read comfortably
// would be actively hostile.
FloatingWindow {
    id: win

    title: Translation.tr("Lyrics")

    implicitWidth:  420
    implicitHeight: 280
    minimumSize: Qt.size(280, 160)

    color: "transparent"

    readonly property bool want: UiState.lyricsWindowOpen

    // ── visible is ASSIGNED both ways, never bound ────────────────────────────
    // Same rule as SettingsWindow: a killactive keybind (or just closing the
    // window) assigns `visible = false` directly, which would destroy a binding
    // — after which nothing could reopen it. The state is mirrored by
    // assignment in both directions instead.
    visible: false
    onWantChanged: win.visible = win.want
    onVisibleChanged: if (!win.visible) UiState.lyricsWindowOpen = false

    // Gates the card's per-frame word-highlight animation and MediaPosition's
    // own FrameAnimation — a hidden window has no business interpolating a
    // playhead sixty times a second for nobody to see.
    MediaPosition {
        id: media
        active: win.visible
    }

    // ── Nothing playing ────────────────────────────────────────────────────────
    // OverviewLyrics renders NOTHING when there's no player (`visible: root.player
    // !== null` — right for the overlay, where an empty card would leave a hole in
    // the layout). LyricsWidget.qml needs the same fallback for the same reason:
    // this window has no ambient frame behind it the way a desktop tile does, so
    // without this the idle state is a literal hole in the compositor rather than
    // a card saying so. Same corner radius and elevation as the card itself, so
    // the window's shape doesn't change between the two states.
    Surface {
        anchors.fill: parent
        visible: media.player === null
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusXl

        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Nothing playing")
            variant: "caption"
            emphasis: "dim"
        }
    }

    // Edge to edge, no margin: the card's own rounded corners and elevation
    // shape the window, the same way SettingsCard fills SettingsWindow.
    OverviewLyrics {
        anchors.fill: parent

        player:   media.player
        position: media.pos
        active:   win.visible
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // Same as the settings window's: a toplevel can't know where it sits, and this
    // one keeps wherever you last put it, so the front is timed as if it were
    // centred — close enough for a card, never a pop of new colour ahead of it.
    Infection {
        host: win.contentItem
        screen: win.screen
        hostVisible: win.visible
        windowX: ((win.screen ? win.screen.width  : win.width)  - win.width)  / 2
        windowY: ((win.screen ? win.screen.height : win.height) - win.height) / 2
    }
}
