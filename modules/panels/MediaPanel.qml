pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/mediasource.js" as MediaSource
import "../../services/volumeprofiles.js" as ProfileData
import "../overview"

// ── MediaPanel ────────────────────────────────────────────────────────────────
// The visualizer pill's panel: what's playing, its lyrics, and the translation
// settings that go with them. Opened by VisualizerPill's left-click — the pill's
// right-click still toggles the desktop cava background directly, unchanged.
//
// Same recipe as WallpaperPanel/ColorSchemePanel: PanelHeader up top, a
// Player | Settings strip underneath (copied from ColorSchemePanel's Editor |
// Presets | Album switch — same shape, two tabs instead), content-hugging (no
// fixed pin; this isn't a thumbnail grid).
//
// Player and Lyrics used to be separate tabs. They're one page now — a synced
// lyrics card is the reason this panel exists at all, and hiding it a tab away
// left "Player" showing a thumbnail, three lines of text and a transport row
// with a slab of empty space under it. Transport stays compact up top; the
// lyrics card fills whatever room that leaves.
//
// ── Reused rather than rebuilt ────────────────────────────────────────────────
// The Lyrics page is `OverviewLyrics` itself, not a second lyrics renderer —
// word-by-word timing via `positionToRectangle` is exactly the kind of thing
// CLAUDE.md's Lyrics section says not to re-derive, and `modules/lyrics/
// LyricsWindow.qml` already proves the component works standalone, outside the
// overview. `MediaPosition` (the same "which player, where in the track" clock
// OverviewLyrics/LyricsWidget/LyricsWindow all share) drives both pages, rather
// than a fourth reimplementation of that sticky-player pick — this shell already
// has three (MediaController, MediaPosition, OverviewNowPlaying's own copy).
//
// It does NOT filter Discord out of the player pick the way MediaController
// does — MediaPosition doesn't either, and neither does OverviewNowPlaying. That
// matches this panel's company (the overview's now-playing surfaces) rather than
// the bar pill's.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Wider than the shared 535 floor every other panel is happy with, and
    // deliberately landscape rather than tall: the transport column and the
    // lyrics beside it both want width, not height, and BarPanelDock's
    // widthFor()/panelWidthMax (660) let a panel ask for exactly that.
    implicitWidth:  660
    implicitHeight: mainCol.implicitHeight + Tokens.spacingMd * 2

    property string view: "player"   // "player" | "scores" | "settings"

    // The volume bar is folded into the four named levels (VolumeProfiles).
    property bool profilesOpen: false

    // The bar's range is 0–100% until Boost unlocks it to the ceiling (130%): a left click on
    // Boost only unlocks, a right click unlocks and sets it. It also reads as unlocked whenever
    // the level IS past 100% (a boost set elsewhere, or still on after a reload), or the bar
    // would show a level its range can't reach.
    property bool boostUnlocked: false

    // Is the panel on screen? BarPanelDock keeps this one mounted while closed (so
    // the lyrics card never rebuilds), which makes this the gate for every piece of
    // per-frame work below — a hidden Item still runs its timers.
    property bool shown: true
    readonly property bool playerLive: root.shown && root.view === "player"

    // ── YouTube gets its own panel, not the music one with the lyrics blank ────
    // Lyrics are keyed on artist + title, and YouTube hands MPRIS the VIDEO title with the
    // channel as the artist — so the lookup misses, or matches a different song and scrolls
    // confident wrong words (mediasource.js `lyricsTrusted`, which owns the rule). So there
    // is no lyrics card at all for such a source: not an empty one, not a "no lyrics" state.
    // What's left is a video: a 16:9 thumbnail instead of a square cover, the brand's red
    // instead of the visualizer's accent, and a source chip.
    //
    // `media.player`'s metadata resolves the xesam:url host, so this is browser-agnostic —
    // YouTube in Zen and in a PWA both land here. YouTube Music is NOT: its metadata is a
    // real track, so it keeps the lyrics.
    readonly property bool showLyrics: MediaSource.lyricsTrusted(media.player)
    readonly property var  brand:      root.showLyrics ? null : AlbumArt.brandOf(MediaSource.idOf(media.player))

    // ── The video itself, when a window is showing it ─────────────────────────
    // The browser window whose title is this track's (or its Picture-in-Picture window —
    // see mediasource.js videoWindow), captured live in place of the thumbnail. Null when
    // the video is in a background tab, which no window shows; the thumbnail stays then.
    // Gated on the panel being open on the player page: the lookup reads every window's
    // title, and those change constantly.
    readonly property var videoTop: (root.showLyrics || !root.playerLive) ? null
        : MediaSource.videoWindow(Hyprland.toplevels.values,
                                  media.player?.trackTitle, media.player?.desktopEntry)

    // ── Does this player say where in the track it is? ────────────────────────
    // A browser often doesn't: Zen reports no length and a Position stuck at 0, so
    // MediaPosition's 1s fallback length drew a full bar and a made-up clock. Better to
    // draw no time than a wrong one. Spotify's bridge supplies its own, so it counts.
    readonly property bool hasTiming: media.bridged
        || ((media.player?.lengthSupported ?? false) && (media.player?.length ?? 0) > 0)

    // ── This player's own PipeWire node ───────────────────────────────────────
    // What the cover's ring listens to, so it answers THIS player and not whatever else
    // shares the speakers (OverviewLyrics derives its own the same way). "" when the
    // panel isn't showing the player, so nothing is looked up for a closed panel, and when
    // the player has no stream yet — the ring then rests as dots.
    readonly property string playerNodeName: {
        if (!root.playerLive) return ""
        const appId = media.player?.desktopEntry ?? ""
        if (!appId) return ""
        const nodes = Audio.streamsFor(appId)
        return nodes.length > 0 ? nodes[0].name : ""
    }

    // Matches the pill's own accent choice (Settings → Bar → Visualizer), so the
    // panel it opens doesn't disagree with the button that opened it — unless the
    // source has a brand to wear.
    readonly property color accent: root.brand
        ? root.brand.accent
        : Config.moduleAccent("visualizer", Colors.of(QsWindow.window).primary)

    // ── Translation-backend rows for the settings tab ─────────────────────────
    // One line of "what this backend is" per id. The display NAME comes from
    // LyricsTranslate.backendNames (one source, shared with the "translated by…"
    // readout); the list itself — order, which are on — lives in Config and is
    // edited through LyricsTranslate's helpers.
    readonly property var backendMeta: ({
        "argos":    "argostranslate — the text never leaves this machine",
        "deepl":    "documented API, uses the key on the full settings page",
        "google":   "public endpoint, no key — every line is sent out",
        "mymemory": "public API, no key — smaller free quota",
    })

    // What produced the translation currently on screen — shown under the toggle
    // so "which backend answered" is visible, not just configurable. Also covers
    // the in-between states so the line does not simply vanish while it works.
    readonly property string translationStatus: {
        if (!Config.lyricsTranslate) return ""
        const T = LyricsTranslate
        if (T.blocker() !== "")       return ""       // the warning line says it instead
        if (T.skipped)               return "This track is already in " + T.target
        if (T.state === "probing" || T.state === "loading") return "Translating…"
        if (T.state === "error")     return "Translation failed — " + T.lastError
        if (T.state === "ready" && T.backendUsed !== "")
            return "Translated by " + T.backendUsed
                 + (T.lastCached ? " · from cache" : "")
                 + (T.sourceLang ? " · " + T.sourceLang + " → " + T.target : "")
        return ""
    }

    // Enabled backends first, in priority order, then the disabled ones. Recomputes
    // whenever the Config list changes.
    readonly property var backendRows: {
        const all    = LyricsTranslate.allBackends
        const chosen = (Config.lyricsTranslateBackends || []).filter(b => all.indexOf(b) >= 0)
        const rest   = all.filter(b => chosen.indexOf(b) < 0)
        return chosen.concat(rest).map(id => {
            const ci = chosen.indexOf(id)
            return { id: id, enabled: ci >= 0,
                     first: ci === 0, last: ci === chosen.length - 1 }
        })
    }

    // The transport row's non-active CookieButtons' fill — same mix
    // OverviewNowPlaying's own `tintChip` uses (there, blended from the
    // per-track album tint; here, from this panel's one fixed accent, since
    // there's no per-track palette to blend from).
    readonly property color _chipTint: Colors.of(QsWindow.window).mix(root.accent, Colors.of(QsWindow.window).fg, 0.5)

    // Gated to the page that actually shows live playback state — the settings
    // page needs none of it. Fetching lyrics for the current track does NOT
    // depend on this: OverviewLyrics watches `player` itself and requests on
    // track change regardless of `active` (see its own header comment), so
    // lyrics are already warm by the time the panel opens on this page.
    MediaPosition {
        id: media
        active: root.playerLive
        // Stubborn while the seek bar is being dragged — see MediaPosition's own
        // header. `seekWave` is declared further down; QML ids resolve across the
        // whole file regardless of order.
        scrubbing: seekWave.pressed
    }


    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        // ══ Header ════════════════════════════════════════════════════════════
        PanelHeader {
            // U+F0388 — the exact Nerd Font codepoint services/icons.js maps the
            // "music_note" Material Symbol back to, so this chip matches every
            // other music_note glyph in the shell instead of a second guess at
            // "a note character".
            glyph:     root.showLyrics ? "\u{F0388}" : MediaSource.sourceGlyph(media.player)
            title:     Translation.tr("Now")
            titleTail: Translation.tr("Playing")
            accent:    root.accent
            subtitle: SongRec.listening ? (SongRec.usingMic ? Translation.tr("Listening to the microphone…")
                                                                 : Translation.tr("Listening to the desktop…"))
                : SongRec.phase === "found" ? Translation.tr("Found: %1").arg(SongRec.track.title + (SongRec.track.artist !== "" ? " — " + SongRec.track.artist : ""))
                : SongRec.phase === "missed" ? Translation.tr("Couldn't recognise it")
                // Karaoke's state, where SongRec's is: "Listening", "Singing · 82% ×3", or — for a few
                // seconds after a click that couldn't start it — why.
                : Karaoke.headline !== "" ? Karaoke.headline
                // A romanization that could not be made says so where it is seen: the toggle
                // alone looked like it did nothing.
                : (Config.lyricsRomanize && LyricsRomanize.romanizable && LyricsRomanize.failed)
                ? "Romanization: " + LyricsRomanize.status
                : root.view === "settings"
                ? "Lyrics lookup and translation"
                : root.view === "scores"
                ? "Your karaoke scores"
                : !media.player
                    ? "Nothing playing"
                    : (media.player.trackArtist ? media.player.trackArtist + " — " : "")
                      + (media.player.trackTitle || "Unknown")

            // The mods, in a pill of their own to the LEFT of the one with the karaoke button, and only
            // while Sing along is on: HD (a click cycles Hidden Lyrics through HD, HD+ and off), HR and TH.
            // They are read when a run BEGINS, so a change made during one shows in the warning colour:
            // it lands on the next run. (They can be set with Sing along off in the Settings tab.)
            ChipTray {
                groupShown: Karaoke.active && root.showLyrics
                ChipButton {
                    label:       Karaoke.hiddenLevel === 2 ? "HD+" : "HD"
                    labelWeight: Font.Bold
                    on:          Karaoke.hiddenLevel > 0
                    tint:        Karaoke.modsPending ? Colors.of(QsWindow.window).warning : root.accent
                    onActivated: Karaoke.cycleHidden()
                }
                ChipButton {
                    label:       "HR"
                    labelWeight: Font.Bold
                    on:          Config.karaokeModHardRock
                    tint:        Karaoke.modsPending ? Colors.of(QsWindow.window).warning : root.accent
                    onActivated: Config.karaokeModHardRock = !Config.karaokeModHardRock
                }
                ChipButton {
                    label:       "TH"
                    labelWeight: Font.Bold
                    on:          Config.karaokeModTimeHell
                    tint:        Karaoke.modsPending ? Colors.of(QsWindow.window).warning : root.accent
                    onActivated: Config.karaokeModTimeHell = !Config.karaokeModTimeHell
                }
            }

            // A pill of round chips (ChipTray): off is an icon on the tray, on is a filled
            // disc with the icon filled in. This panel's own look — every other panel's header
            // still wears ActionGroup.
            ChipTray {
                // Lives here rather than on the player page itself — Lyrics no
                // longer has a tab of its own to carry it, and a header action
                // reaches it from Settings too, where the language/fallback
                // controls for exactly this toggle live.
                ChipButton {
                    visible:     root.showLyrics   // nothing to translate without lyrics
                    symbol:      "translate"
                    on:          Config.lyricsTranslate
                    tint:        root.accent
                    onActivated: Config.lyricsTranslate = !Config.lyricsTranslate
                }
                // Sing along: the lyrics light up as you sing them (services/Karaoke). Only with
                // lyrics to sing. Never disabled — a click that can't start it says why in the
                // header's subtitle (headphones, pw-record), where it is seen.
                ChipButton {
                    visible:     root.showLyrics
                    symbol:      "mic"
                    on:          Karaoke.active
                    tint:        root.accent
                    onActivated: Karaoke.toggle()
                }
                // "What is this song?" — listens to the desktop audio (services/SongRec). The
                // microphone button that sat after it was removed (never used); SongRec's own
                // mic path is still there. Disabled with the reason in the tooltip-less header:
                // the subtitle says why when it's pressed, and Settings › Setup lists the package.
                ChipButton {
                    symbol:      "music_note"
                    on:          SongRec.listening && !SongRec.usingMic
                    tint:        root.accent
                    enabled:     SongRec.blocker(false) === "" || (SongRec.listening && !SongRec.usingMic)
                    onActivated: SongRec.toggle(false)
                }
                // Latin letters under a song in another script. Only on a song that HAS
                // something to romanize (LyricsRomanize.romanizable: the lyrics' own writing
                // system) — a song in English has nothing to show, and a switch for it is noise.
                ChipButton {
                    visible:     root.showLyrics && LyricsRomanize.romanizable
                    symbol:      "record_voice_over"
                    on:          Config.lyricsRomanize
                    // Warning while it is on and could not be made (see the subtitle).
                    tint:        Config.lyricsRomanize && LyricsRomanize.failed
                                 ? Colors.of(QsWindow.window).warning : root.accent
                    onActivated: Config.lyricsRomanize = !Config.lyricsRomanize
                }
                // The desktop visualiser. Its disc is palette colour 12 (pywal's bright blue),
                // not the panel's accent — it is the one chip that is not about THIS player, and
                // wearing a colour of its own says so.
                ChipButton {
                    symbol:      "equalizer"
                    on:          Config.cavaBg
                    // The CIRCLE is colour 12, always; the icon stays the contrast colour on it
                    // and says on/off by its fill.
                    solid:       true
                    tint:        Colors.of(QsWindow.window).ansi(12)
                    onActivated: Config.cavaBg = !Config.cavaBg
                }
            }
        }

        // ══ Player | Settings ═════════════════════════════════════════════════
        // A full pill with a filled accent indicator that slides on a spring (SegmentSwitch),
        // in place of the flat 5% strip this panel borrowed from ColorSchemePanel.
        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            model: [
                { value: "player",   label: "Player",   icon: "music_note" },
                { value: "scores",   label: "Scores",   icon: "star"       },
                { value: "settings", label: "Settings", icon: "settings"   }
            ]
            current: root.view
            accent:  root.accent
            onPicked: function (v) { root.view = v }
        }

        // ══ PLAYER ════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.view === "player"
            spacing: Tokens.spacingLg

            PanelEmpty {
                visible: !media.player
                quiet: true
                symbol: "music_note"
                title: Translation.tr("Nothing playing")
                text: Translation.tr("Start something in a player and its controls and lyrics show up here.")
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !!media.player
                spacing: Tokens.spacingLg

                // ── Art · track & transport · lyrics ────────────────────────────
                // Three columns, the shape asked for directly: a circular cover on
                // the left, title/artist/album with the seek bar, transport and
                // volume stacked under it in the middle, lyrics as a sidebar on
                // the right — rather than the stacked, single-column pages every
                // earlier pass at this panel used.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingLg

                    // ── Cover ────────────────────────────────────────────────────
                    // The exact shape OverviewNowPlaying's own cover uses — same
                    // radius, same tinted fill instead of a plain grey, same mask
                    // (not clip — `clip: true` on a Rectangle ignores `radius`),
                    // same quiet playing-pulse instead of a static ring. Two
                    // surfaces drawing "the album art" should draw it identically.
                    // ── Music: a cookie ──────────────────────────────────────────
                    // The picture through a turning Scallop, with a ring of level bars
                    // round it (CookieCover). Its slot is 176 square: a 136 cover inside
                    // a ring 20 deep. The panel is 660 wide (BarPanelDock's cap) to make
                    // the room, and the row is at least as tall as the lyrics card beside it.
                    CookieCover {
                        visible: root.showLyrics
                        Layout.preferredWidth:  Tokens.spacingXl * 11
                        Layout.preferredHeight: Tokens.spacingXl * 11
                        Layout.alignment: Qt.AlignVCenter
                        source:   AlbumArt.hiRes(media.player?.trackArtUrl ?? "")
                        playing:  media.playing
                        // Not for a video: the cookie is hidden then, and a hidden ring
                        // must not hold the spectrum process open.
                        live:     root.playerLive && root.showLyrics
                        nodeName: root.playerNodeName
                        accent:   root.accent
                    }

                    // ── Video: the thumbnail, as it was ───────────────────────────
                    Rectangle {
                        id: artFrame
                        visible: !root.showLyrics
                        // A video's thumbnail is 16:9; cropping it square throws away
                        // a third of the picture. Without the lyrics column there is
                        // the room for a real one — the panel's hero, not a cover.
                        Layout.preferredWidth:  256
                        Layout.preferredHeight: 144
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusSm
                        color:  Colors.of(QsWindow.window).alpha(root.accent, 0.18)

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: artMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                            Image {
                                anchors.fill: parent
                                source: AlbumArt.hiRes(media.player?.trackArtUrl ?? "")
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready && !liveVideo.hasContent
                                sourceSize: Qt.size(artFrame.width * 2, artFrame.height * 2)
                                mipmap: true
                            }
                            // The live window, fitted inside the frame (a capture paints a raw
                            // texture and stretches to whatever size it is given).
                            ScreencopyView {
                                id: liveVideo
                                anchors.centerIn: parent
                                captureSource: root.videoTop ? root.videoTop.wayland : null
                                live: root.playerLive
                                visible: hasContent
                                readonly property real fit: sourceSize.width > 0
                                    ? Math.min(artFrame.width / sourceSize.width, artFrame.height / sourceSize.height) : 0
                                width:  sourceSize.width  * fit
                                height: sourceSize.height * fit
                            }
                            // YouTube's own progress line along the thumbnail's bottom
                            // edge (inside the mask, so it follows the rounded corners).
                            // Display only — seeking stays on the bar beside it.
                            Rectangle {
                                visible: !root.showLyrics && root.hasTiming
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                height: Tokens.spacingXs
                                width:  parent.width * Math.min(1, media.pos / Math.max(1, media.length))
                                color:  root.accent
                            }
                        }
                        Item {
                            id: artMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: artFrame.radius; color: "white" }
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: (media.player?.trackArtUrl ?? "") === ""
                            name: "music_note"
                            fill: 0
                            font.pixelSize: Tokens.iconXl
                            color: root.accent
                        }

                        // Same ambient "this is live" cue OverviewNowPlaying's
                        // cover uses, rather than a border that sits there
                        // whether or not anything is actually playing.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: root.accent
                            opacity: 0

                            SequentialAnimation on opacity {
                                running: media.playing && root.shown
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.55; duration: Motion.slow; easing.type: Motion.ambient }
                                NumberAnimation { to: 0.00; duration: Motion.slow; easing.type: Motion.ambient }
                            }
                        }
                    }

                    // ── Track, seek, transport, volume ──────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        Badge {
                            visible: !root.showLyrics
                            label:   MediaSource.resolve(media.player).name
                            tint:    root.accent
                            filled:  true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingXs
                            StyledText {
                                Layout.fillWidth: true
                                text: media.player?.trackTitle || "Unknown"
                                variant: "title"
                                font.weight: Font.Bold
                                // A video title is a sentence, not a track name — let it
                                // take two lines before it gives up.
                                wrapMode: root.showLyrics ? Text.NoWrap : Text.Wrap
                                maximumLineCount: root.showLyrics ? 1 : 2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: (media.player?.trackArtist ?? "") !== ""
                                text: media.player?.trackArtist || ""
                                variant: "caption"
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: (media.player?.trackAlbum ?? "") !== ""
                                text: media.player?.trackAlbum || ""
                                variant: "caption"
                                // The accent, as the third line of Caelestia's details is
                                // — title, who, then WHICH record in the colour of the cover.
                                color: root.accent
                                elide: Text.ElideRight
                            }
                        }

                        // ── Seek ───────────────────────────────────────────────
                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingSm
                            visible: !root.hasTiming
                            text: Translation.tr("This player doesn't report playback time")
                            variant: "caption"
                            emphasis: "dim"
                        }

                        // The shared seek (components/MediaSeek — the island draws the same).
                        MediaSeek {
                            id: seekWave
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingSm
                            visible: root.hasTiming
                            track: media
                            accent: root.accent
                            live: root.playerLive && root.hasTiming
                        }

                        // ── Transport ──────────────────────────────────────────
                        // The shared CookieButton (scalloped shape, winds on
                        // hover/press) rather than PanelButton — the exact
                        // control OverviewNowPlaying's transport row uses, same
                        // point counts, tilts, sizes and glyphs, so the two
                        // "now playing" surfaces in this shell share one
                        // transport language instead of two.
                        MediaTransport {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Tokens.spacingXs
                            player: media.player
                            playing: media.playing
                            accent: root.accent
                            chipTint: root._chipTint
                        }

                        // ── Volume ─────────────────────────────────────────────
                        // The PLAYER's own volume (Audio.playerLevel: MPRIS `Volume`, the slider
                        // inside Spotify), not its PipeWire stream and not the system output.
                        // Spotify rewrites its stream on a track change, so a level set there
                        // did not last the song; its own volume does. A player with no volume of
                        // its own falls back to its stream (Audio.hasPlayerVolume).
                        //
                        // The speaker used to MUTE. It folds the bar away now (`profilesOpen`)
                        // and four named levels take its place — soft, medium, max, and boost,
                        // the one that also lifts the general volume past 100%
                        // (services/volumeprofiles.js). Muting is one drag to zero here, or the
                        // mixer's own button.
                        RowLayout {
                            id: volRow
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingSm
                            spacing: Tokens.spacingSm

                            readonly property string appId: media.player?.desktopEntry ?? ""
                            readonly property bool has: Audio.hasPlayerVolume(media.player, volRow.appId)
                            readonly property real level: Audio.playerLevel(media.player, volRow.appId)

                            // A real speaker, by level (Material's four: off, mute, down, up), filled, in
                            // the panel's own button — folds the bar into the profiles and back. Dimmed
                            // while the player has no volume to set.
                            PanelButton {
                                Layout.alignment: Qt.AlignVCenter
                                enabled:    volRow.has
                                symbol:     volRow.level <= 0 ? "volume_off"
                                          : volRow.level < 0.35 ? "volume_mute"
                                          : volRow.level < 0.70 ? "volume_down"
                                          :                       "volume_up"
                                symbolFill: 1
                                variant:    root.profilesOpen ? "normal" : "ghost"
                                accent:     root.accent
                                onActivated: root.profilesOpen = !root.profilesOpen
                            }

                            // The two faces of the row share one slot and cross-fade, so folding
                            // the bar reads as the row changing shape rather than two rows swapping.
                            Item {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: profiles.implicitHeight

                                // The thick one (ThickSlider — Caelestia's audio-settings slider): a
                                // volume is a level you set once and want to SEE, not a track you
                                // scrub, so it wants mass rather than a wave.
                                ThickSlider {
                                    id: volBar
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    readonly property bool unlocked: root.boostUnlocked || volRow.level > 1.001
                                    enabled:      volRow.has
                                    // Unlocked: out to the ceiling, a tick at 100% and the warning
                                    // colour beyond it — the bar changes shape and tone, so a boost
                                    // is not mistaken for a level.
                                    maximum:      volBar.unlocked ? Math.round(Audio.boostCeiling * 100) : 100
                                    value:        Math.min(volBar.maximum, volRow.level * 100)
                                    notchAt:      volBar.unlocked ? 100 : -1
                                    notchColor:   Colors.of(QsWindow.window).warning
                                    accent:       root.accent
                                    opacity: root.profilesOpen ? 0 : 1
                                    visible: opacity > 0.005
                                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                    onMoved: function(v) { Audio.setPlayerLevel(media.player, volRow.appId, v / 100, volBar.unlocked) }
                                }

                                VolumeProfiles {
                                    id: profiles
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    enabled:  volRow.has
                                    profiles: ProfileData.PROFILES
                                    current:  Audio.volumeProfileOf(media.player, volRow.appId)
                                    accent:   root.accent
                                    opacity: root.profilesOpen ? 1 : 0
                                    visible: opacity > 0.005
                                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                    // Boost is a different gesture from the others, which just apply:
                                    //   left   unlocks the bar to 130% and shows it, changing nothing
                                    //   right  unlocks it AND sets the boost (player full, stream 130%)
                                    // Any other profile locks it again.
                                    onPicked: function(i) {
                                        if (ProfileData.PROFILES[i].boost) {
                                            root.boostUnlocked = true
                                            root.profilesOpen = false
                                            return
                                        }
                                        root.boostUnlocked = false
                                        Audio.applyProfile(media.player, volRow.appId, i)
                                    }
                                    onAlternated: function(i) {
                                        if (!ProfileData.PROFILES[i].boost) {
                                            root.boostUnlocked = false
                                            Audio.applyProfile(media.player, volRow.appId, i)
                                            return
                                        }
                                        Audio.applyProfile(media.player, volRow.appId, i)
                                        root.boostUnlocked = true
                                        root.profilesOpen = false
                                    }
                                }
                            }

                            StyledText {
                                Layout.preferredWidth: 34
                                visible: !root.profilesOpen
                                text: volRow.has ? Math.round(volRow.level * 100) + "%" : "—"
                                variant: "caption"
                                emphasis: "dim"
                                font.family: Tokens.fontMono
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // ── Lyrics sidebar ───────────────────────────────────────────
                    // Fixed width rather than sharing the row equally with the
                    // track/transport column — a secondary sidebar, not an equal
                    // partner, matching the proportions asked for. Fills whatever
                    // height that column ends up needing. Widened as the
                    // track/transport column shrank, so lyrics pick up the room a
                    // smaller cover and smaller type gave back.
                    // A Loader, so a source with no lyrics doesn't just hide the card —
                    // it never builds one, and never fires a lookup it would get wrong.
                    // Now a card of its own (PanelLyrics: a header with the sync mode, the
                    // lyrics, a footer with the source and the timing offset) rather than
                    // bare text on the panel. At least 224 tall so the lyrics get a few
                    // lines once the header and footer have taken theirs; the row grows to
                    // that if the track column is shorter.
                    Loader {
                        // `visible`, not just `active`: an inactive Loader still holds its
                        // preferred width, which left a dead gap beside the video.
                        visible: root.showLyrics
                        Layout.preferredWidth:  240
                        Layout.preferredHeight: 0   // follow the transport column; the card's own implicitHeight must not size the row
                        Layout.minimumHeight:   Tokens.spacingXl * 14
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        active: root.showLyrics

                        sourceComponent: PanelLyrics {
                            player:   media.player
                            position: media.pos
                            active:   root.playerLive
                            accent:   root.accent
                        }
                    }
                }
            }
        }

        // ══ SCORES ════════════════════════════════════════════════════════════
        // Built when the tab is opened and gone when it is left, so the list slides in afresh
        // each visit (KaraokeScoresView). A Loader's size follows its item, so the panel hugs it.
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: false
            active: root.view === "scores"
            visible: active
            sourceComponent: KaraokeScoresView { accent: root.accent }
        }

        // ══ SETTINGS ══════════════════════════════════════════════════════════
        // Same shape as GamingPanel's switches: a dim group caption, then SettingRows
        // (symbol, label, one-line detail, a Toggle). Translation's options exist only
        // while translation is on, and the backend order — the one fiddly control — is
        // a Disclosure, so the tab opens as three rows rather than a wall.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.view === "settings"
            spacing: Tokens.spacingXs

            StyledText {
                text: Translation.tr("Lyrics")
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                label:  Translation.tr("Look up lyrics online")
                detail: Translation.tr("When Spotify has none, or doesn't answer in time")
                Layout.minimumHeight: 36
                symbol:      "lyrics"
                symbolFill:  Config.lyricsFallback ? 1 : 0
                symbolColor: Config.lyricsFallback ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsFallback
                    onToggled: Config.lyricsFallback = !Config.lyricsFallback
                }
            }

            // ── Romanization: only on a song that has something to romanize ───────
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                visible: LyricsRomanize.romanizable
                text: Translation.tr("Romanization")
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                visible: LyricsRomanize.romanizable
                label:  Translation.tr("Romanize lyrics")
                detail: LyricsRomanize.status !== "" ? LyricsRomanize.status
                                                     : "Latin letters in place of a song's own script"
                Layout.minimumHeight: 36
                symbol:      "record_voice_over"
                symbolFill:  Config.lyricsRomanize ? 1 : 0
                symbolColor: Config.lyricsRomanize ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsRomanize
                    onToggled: Config.lyricsRomanize = !Config.lyricsRomanize
                }
            }
            SettingRow {
                visible: LyricsRomanize.romanizable && Config.lyricsRomanize
                label:  Translation.tr("Allow Google")
                detail: Config.lyricsRomanizeOnline ? "Each line is sent to Google, the best at kanji"
                                                    : "Kept on this machine — needs a local library"
                Layout.minimumHeight: 36
                symbol:      "language"
                symbolFill:  Config.lyricsRomanizeOnline ? 1 : 0
                symbolColor: Config.lyricsRomanizeOnline ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsRomanizeOnline
                    onToggled: Config.lyricsRomanizeOnline = !Config.lyricsRomanizeOnline
                }
            }

            SettingRow {
                visible: LyricsRomanize.romanizable && Config.lyricsRomanize
                label:  Translation.tr("Cache romanizations")
                detail: Translation.tr("Keep a song's Google romanization a month, an on-device one a day")
                Layout.minimumHeight: 36
                symbol:      "cached"
                symbolFill:  Config.lyricsRomanizeCache ? 1 : 0
                symbolColor: Config.lyricsRomanizeCache ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsRomanizeCache
                    onToggled: Config.lyricsRomanizeCache = !Config.lyricsRomanizeCache
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: Translation.tr("Translation")
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                label:  Translation.tr("Translate lyrics")
                // What answered, when something did; the plain description otherwise.
                detail: root.translationStatus !== "" ? root.translationStatus : "A line under each lyric"
                Layout.minimumHeight: 36
                symbol:      "translate"
                symbolFill:  Config.lyricsTranslate ? 1 : 0
                symbolColor: Config.lyricsTranslate ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsTranslate
                    onToggled: Config.lyricsTranslate = !Config.lyricsTranslate
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Config.lyricsTranslate && LyricsTranslate.blocker() !== ""
                text: LyricsTranslate.blocker()
                    + (LyricsTranslate.installHint ? "  (" + LyricsTranslate.installHint + ")" : "")
                variant:  "caption"
                color:    Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            SettingRow {
                visible: Config.lyricsTranslate
                label:  Translation.tr("Language")
                detail: Translation.tr("Two-letter code, e.g. en, es, ja")
                Layout.minimumHeight: 36
                symbol:      "language"
                symbolColor: Colors.of(QsWindow.window).fgMuted
                InputField {
                    width: 72
                    placeholder: "en"
                    seed: Config.lyricsTranslateLang
                    onCommitted: function(v) {
                        const t = v.trim().toLowerCase()
                        Config.lyricsTranslateLang = t !== "" ? t : "en"
                    }
                }
            }
            SettingRow {
                visible: Config.lyricsTranslate
                label:  Translation.tr("Cache translations")
                detail: Translation.tr("Keep a translated track for a week")
                Layout.minimumHeight: 36
                symbol:      "cached"
                symbolFill:  Config.lyricsTranslateCache ? 1 : 0
                symbolColor: Config.lyricsTranslateCache ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.lyricsTranslateCache
                    onToggled: Config.lyricsTranslateCache = !Config.lyricsTranslateCache
                }
            }

            // ── Translators, in priority order ───────────────────────────────
            // Tried top to bottom, first that answers wins. A backend switched off is
            // never contacted — the way to keep every line on DeepL is to turn the
            // others off. Closed by default and built on first open (Disclosure).
            Disclosure {
                Layout.fillWidth: true
                visible: Config.lyricsTranslate
                label: Translation.tr("Translators")
                contentComponent: Component {
                    ColumnLayout {
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: root.backendRows

                            delegate: SettingRow {
                                id: bRow
                                required property var modelData

                                label: (LyricsTranslate.backendNames[bRow.modelData.id] || bRow.modelData.id)
                                       + (LyricsTranslate.backend === bRow.modelData.id ? "  · in use" : "")
                                detail: root.backendMeta[bRow.modelData.id] || ""
                                Layout.minimumHeight: 36
                                opacity: bRow.modelData.enabled ? 1 : 0.5

                                Row {
                                    spacing: Tokens.spacingXs
                                    PanelButton {
                                        symbol:  "keyboard_arrow_up"
                                        variant: "ghost"
                                        accent:  root.accent
                                        implicitWidth: 30
                                        enabled: bRow.modelData.enabled && !bRow.modelData.first
                                        opacity: enabled ? 1 : 0.25
                                        onActivated: LyricsTranslate.moveBackend(bRow.modelData.id, -1)
                                    }
                                    PanelButton {
                                        symbol:  "keyboard_arrow_down"
                                        variant: "ghost"
                                        accent:  root.accent
                                        implicitWidth: 30
                                        enabled: bRow.modelData.enabled && !bRow.modelData.last
                                        opacity: enabled ? 1 : 0.25
                                        onActivated: LyricsTranslate.moveBackend(bRow.modelData.id, 1)
                                    }
                                    Toggle {
                                        accent:  root.accent
                                        checked: bRow.modelData.enabled
                                        onToggled: LyricsTranslate.setBackendEnabled(
                                            bRow.modelData.id, !bRow.modelData.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Karaoke ──────────────────────────────────────────────────────────
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: Translation.tr("Karaoke")
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                label:  Translation.tr("Sing along")
                detail: Karaoke.active ? Karaoke.status
                      : Karaoke.blocked !== "" ? Karaoke.blocked
                      : "The lyrics light up as you sing them"
                Layout.minimumHeight: 36
                symbol:      "mic"
                symbolFill:  Karaoke.active ? 1 : 0
                symbolColor: Karaoke.active ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Karaoke.active
                    onToggled: Karaoke.toggle()
                }
            }
            SettingRow {
                label:  Translation.tr("Match the words")
                detail: !Config.karaokeWords ? "Timing only — whether you sing, not what"
                      : Karaoke.wordsActive ? "The words you sing are underlined"
                      : Karaoke.modeNote !== "" ? Karaoke.modeNote
                      : "Underlines the words you sing — needs a speech model"
                Layout.minimumHeight: 36
                symbol:      "lyrics"
                symbolFill:  Config.karaokeWords ? 1 : 0
                symbolColor: Config.karaokeWords ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.karaokeWords
                    onToggled: Config.karaokeWords = !Config.karaokeWords
                }
            }
            SettingRow {
                label:  Translation.tr("Song language")
                detail: Config.karaokeLanguage !== "" ? "Pinned to " + Karaoke.languageName
                      : Karaoke.detectedLanguage !== ""
                        ? "Detected: " + Karaoke.languageName + (Karaoke.languageSure ? "" : " (not sure)")
                      : "Detected from each song's lyrics"
                Layout.minimumHeight: 36
                symbol:      "language"
                symbolFill:  Config.karaokeLanguage !== "" ? 1 : 0
                symbolColor: Config.karaokeLanguage !== "" ? root.accent : Colors.of(QsWindow.window).fgMuted
                PanelButton {
                    label:   Karaoke.languageLabel(Config.karaokeLanguage)
                    variant: "ghost"
                    accent:  root.accent
                    onActivated: Karaoke.cycleLanguage()
                }
            }
            // The song's language has no speech model on this machine: offered here, before Sing along is
            // on, rather than a command to find. One click runs scripts/karaoke-model.sh (30–50 MB, no root).
            SettingRow {
                visible: Karaoke.modelMissing || Karaoke.installing || Karaoke.installNote !== ""
                label:  Translation.tr("Speech model")
                detail: Karaoke.installing ? "Downloading the " + Karaoke.languageName + " model\u2026"
                      : Karaoke.installNote !== "" ? Karaoke.installNote
                      : Karaoke.canInstall ? "No " + Karaoke.languageName + " model yet \u2014 one download, 30\u201350 MB"
                      : "None found in the folder set in Config"
                Layout.minimumHeight: 36
                symbol:      "download"
                symbolFill:  0
                symbolColor: Karaoke.installNote !== "" ? Colors.of(QsWindow.window).warning : root.accent
                PanelButton {
                    label:   Karaoke.installing ? "Downloading\u2026" : Karaoke.installNote !== "" ? "Retry" : "Download"
                    variant: "ghost"
                    accent:  root.accent
                    enabled: Karaoke.canInstall && !Karaoke.installing
                    onActivated: Karaoke.installModel()
                }
            }
            // Lines that are not meant to be sung (an ad-lib, a spoken part): right-click one on the lyrics and it
            // is dimmed and left out of the score, this song only. Said here because nothing on the card says so.
            SettingRow {
                label:  Translation.tr("Lines left out")
                detail: Karaoke.skippedCount > 0
                        ? Karaoke.skippedCount + (Karaoke.skippedCount === 1 ? " line" : " lines") + " in this song \u2014 right-click one on the lyrics to put it back"
                        : "Right-click a lyric that isn't meant to be sung to leave it out of the score"
                Layout.minimumHeight: 36
                symbol:      "visibility_off"
                symbolFill:  Karaoke.skippedCount > 0 ? 1 : 0
                symbolColor: Karaoke.skippedCount > 0 ? root.accent : Colors.of(QsWindow.window).fgMuted
                PanelButton {
                    visible: Karaoke.skippedCount > 0
                    label:   Translation.tr("Put all back")
                    variant: "ghost"
                    accent:  root.accent
                    onActivated: Karaoke.clearSkips()
                }
            }
            SettingRow {
                label:  Translation.tr("I'm on headphones")
                detail: Config.karaokeSkipHeadphoneCheck ? "Not checked — the mic may hear the song"
                                                         : "Karaoke needs them; skip the check if yours report wrong"
                Layout.minimumHeight: 36
                symbol:      "headphones"
                symbolFill:  Config.karaokeSkipHeadphoneCheck ? 1 : 0
                symbolColor: Config.karaokeSkipHeadphoneCheck ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.karaokeSkipHeadphoneCheck
                    onToggled: Config.karaokeSkipHeadphoneCheck = !Config.karaokeSkipHeadphoneCheck
                }
            }

            // ── Mods ─────────────────────────────────────────────────────────────
            // osu!-style: each makes a run harder in one way and its score worth more. Read when a run
            // BEGINS and fixed for it (a mod changed mid-song would change the rules under a score).
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Mods" + (Karaoke.modsWantedMult > 1 ? "  ·  ×" + Karaoke.modsWantedMult.toFixed(2) : "")
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                label:  Karaoke.hiddenLevel === 2 ? "HD+  Hidden Lyrics+" : "HD  Hidden Lyrics"
                detail: Karaoke.hiddenLevel === 0
                        ? "Off. HD shows only the line being sung (\u00d7" + Karaoke.modTable.HD.mult.toFixed(2)
                          + "); HD+ hides everything (\u00d7" + Karaoke.modTable.HDP.mult.toFixed(2) + ")"
                      : Karaoke.hiddenLevel === 1
                        ? Karaoke.modTable.HD.note + "  \u00b7  \u00d7" + Karaoke.modTable.HD.mult.toFixed(2)
                        : Karaoke.modTable.HDP.note + "  \u00b7  \u00d7" + Karaoke.modTable.HDP.mult.toFixed(2)
                Layout.minimumHeight: 36
                symbol:      "visibility_off"
                symbolFill:  Karaoke.hiddenLevel > 0 ? 1 : 0
                symbolColor: Karaoke.hiddenLevel > 0 ? root.accent : Colors.of(QsWindow.window).fgMuted
                PanelButton {
                    label:   Karaoke.hiddenLevel === 0 ? "Off" : Karaoke.hiddenLevel === 1 ? "HD" : "HD+"
                    variant: "ghost"
                    accent:  root.accent
                    onActivated: Karaoke.cycleHidden()
                }
            }
            SettingRow {
                label:  Translation.tr("HR  Hard Rock")
                detail: Karaoke.modTable.HR.note + "  ·  ×" + Karaoke.modTable.HR.mult.toFixed(2)
                Layout.minimumHeight: 36
                symbol:      "bolt"
                symbolFill:  Config.karaokeModHardRock ? 1 : 0
                symbolColor: Config.karaokeModHardRock ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.karaokeModHardRock
                    onToggled: Config.karaokeModHardRock = !Config.karaokeModHardRock
                }
            }
            SettingRow {
                label:  Translation.tr("TH  Time-Hell")
                detail: Karaoke.modTable.TH.note + "  ·  ×" + Karaoke.modTable.TH.mult.toFixed(2)
                Layout.minimumHeight: 36
                symbol:      "history"
                symbolFill:  Config.karaokeModTimeHell ? 1 : 0
                symbolColor: Config.karaokeModTimeHell ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.karaokeModTimeHell
                    onToggled: Config.karaokeModTimeHell = !Config.karaokeModTimeHell
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: Karaoke.modsPending
                wrapMode: Text.Wrap
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                text: Translation.tr("This run keeps the mods it started with. The change applies from the next run.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: Config.karaokeModHardRock && !Config.karaokeWords
                wrapMode: Text.Wrap
                variant: "caption"
                emphasis: "dim"
                text: Translation.tr("Hard Rock is about the words; with 'Match the words' off it changes nothing and earns nothing.")
            }

            SettingRow {
                label:  Translation.tr("Hold the song at its end")
                detail: Config.karaokeStayAtEnd ? "Pauses at the end, so the next song never starts under your results"
                                                : "The player moves on to the next song by itself"
                Layout.minimumHeight: 36
                symbol:      "pause_circle"
                symbolFill:  Config.karaokeStayAtEnd ? 1 : 0
                symbolColor: Config.karaokeStayAtEnd ? root.accent : Colors.of(QsWindow.window).fgMuted
                Toggle {
                    accent:  root.accent
                    checked: Config.karaokeStayAtEnd
                    onToggled: Config.karaokeStayAtEnd = !Config.karaokeStayAtEnd
                }
            }

            Divider { Layout.topMargin: Tokens.spacingXs }

            // Where the lyrics on screen came from, and the way to the rest.
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (Lyrics.viaBridge)
                            return "Spotify bridge — " + Lyrics.provider
                                + (Lyrics.community ? ", community" : "") + ", per-syllable"
                        if (Lyrics.state === "loading") return "Looking up lyrics…"
                        if (!Lyrics.hasSynced && Lyrics.blockedReason !== "")
                            return Lyrics.blockedReason === "connecting"
                                ? "Waiting on the Spotify bridge to connect…"
                                : Lyrics.blockedReason === "waiting"
                                ? "Waiting on Spotify…"
                                : "The Spotify bridge has nothing for this track."
                        return "Fallback lookup" + (Lyrics.source ? " — " + Lyrics.source : "")
                    }
                    variant:  "caption"
                    emphasis: "dim"
                    elide:    Text.ElideRight
                }

                PanelButton {
                    label:       Translation.tr("More")
                    symbol:      "open_in_new"
                    variant:     "ghost"
                    accent:      root.accent
                    onActivated: UiState.openSettingsTo("MiscPage.qml")
                }
            }
        }
    }

    // ══ Joined mid-song, and the countdown ═══════════════════════════════════
    // Switching Karaoke on part-way through a song says the run won't be ranked and offers a restart
    // from the beginning with a 3-2-1 (KaraokeJoin). Built only while the panel is on screen, so the
    // countdown's first beat is not spent on a hidden panel: switch it on with the panel shut and the
    // warning is waiting when you open it.
    Loader {
        anchors.fill: parent
        z: 60
        active: (Karaoke.joinNotice || Karaoke.countdown > 0 || Karaoke.countdownGo) && root.shown
        sourceComponent: KaraokeJoin { accent: root.accent }
    }

    // ══ The results screen ═══════════════════════════════════════════════════
    // Over the whole panel, when a song has just played out (Karaoke.result). Built only while the
    // panel is on screen, so its entrance plays when it can be SEEN: finish a song with the panel
    // shut and the result is waiting, animating in, when you open it.
    Loader {
        anchors.fill: parent
        z: 50
        active: Karaoke.result !== null && root.shown
        sourceComponent: KaraokeResults {
            result: Karaoke.result
            accent: root.accent
            onClosed: Karaoke.dismissResult()
            onOpenScores: { Karaoke.dismissResult(); root.view = "scores" }
        }
    }
}
