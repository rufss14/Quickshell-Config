import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/mediasource.js" as MediaSource

// ── OverviewControls ──────────────────────────────────────────────────────────
// The overview's bottom island at rest: what's playing, beside the system's levels.
//
//   ╭───────────────────────────────────────────────────────────────────────╮
//   │  ✿ cover ✿   Song title                     │  󰕾 ━━━━━━━●──── 64%      │
//   │  (its ring)  Artist                          │  󰃠 ━━━━━━●───── 80%      │
//   │              Album                           │                          │
//   │              ∿∿∿∿∿∿∿●──────  1:28 · 2:24      │  wifi bt dnd 󰖔 mic ⚡    │
//   │              ⤮  ⏮  ⏯  ⏭  ⟳   ▬▬▬▬▬▬ 37%      │                          │
//   ╰───────────────────────────────────────────────────────────────────────╯
//
// Now playing is the Now Playing panel's own player (2026-10-20, the user: "should look more
// like the one from the Now Playing panel"): the cover in a turning cookie with its level ring
// (CookieCover), title / artist / album, the wavy seek (MediaSeek), the cookie transport
// (MediaTransport) and the PLAYER's own volume (Audio.playerLevel, as the panel's) — the same
// components, not look-alikes. No lyrics: the strip has no width for them. A new track swaps
// in through a fade (SwapFade); no player, no block — the island springs to the levels alone.
// Its colours follow Settings › Appearance › "Tint media cards" (Config.albumCardColors),
// like every other media card: off, it wears the shell palette.
//
// Beside it, the system: volume and brightness (the shared ValueSlider; click the volume glyph
// to mute, the wheel steps either), then the quick switches. A display the shell can't drive
// isn't listed. Everything real is Audio / Brightness / the MPRIS player / each switch's own
// service — this shows them and calls them.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation:    Tokens.elevationCard
    cornerRadius: Tokens.radiusXl

    readonly property int pad: Tokens.spacingLg
    // Whether the island is up and showing this — the playhead's per-frame work only then.
    property bool live: true

    implicitWidth:  col.implicitWidth + root.pad * 2
    implicitHeight: col.implicitHeight + root.pad * 2

    MediaPosition { id: media; active: root.live; scrubbing: seek.pressed }
    readonly property var player: media.player
    readonly property string trackKey: root.player ? (root.player.trackTitle ?? "") + "\u0001" + (root.player.trackArtist ?? "") : ""
    // The held copy the row shows (SwapFade swaps it at the fade's midpoint).
    property var shownTrack: ({ key: "", title: "", artist: "", album: "", art: "" })
    function _take() {
        root.shownTrack = { key: root.trackKey, title: root.player?.trackTitle ?? "",
                            artist: root.player?.trackArtist ?? "", album: root.player?.trackAlbum ?? "",
                            art: root.player?.trackArtUrl ?? "" }
    }
    Component.onCompleted: { Brightness.ensureProbed(); root._take(); root._dress() }

    // ── The cover's colour ────────────────────────────────────────────────────
    // With Settings › Appearance › "Tint media cards" on (Config.albumCardColors), the island
    // wears the playing cover's accent (services/AlbumArt — the media cards' palette): the
    // transport, the seek, the ring, and a tint on the island itself (OverviewIsland reads
    // `tone`/`dressed`). Off, the shell palette — the user's call, 2026-10-20.
    // Handed to AlbumArt only while this is on screen; it falls back to the palette
    // whenever the art can't be read.
    readonly property bool dressed: Config.albumCardColors && AlbumArt.ready && root.player !== null && root.shownTrack.art !== ""
    readonly property color tone: root.dressed ? AlbumArt.accent : Colors.of(QsWindow.window).primary
    function _dress() {
        if (!root.live) return
        AlbumArt.sourceId = root.player ? MediaSource.idOf(root.player) : ""
        AlbumArt.source = root.shownTrack.art
    }
    onShownTrackChanged: root._dress()
    onLiveChanged: root._dress()
    // The cover can arrive after the title (MPRIS sends them apart); the same track keeps its row.
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackArtUrlChanged() { if (root.trackKey === root.shownTrack.key) root._take() }
    }


    readonly property int controllableCount: {
        let n = 0
        for (let i = 0; i < Brightness.monitors.count; i++)
            if (Brightness.monitors.get(i).controllable) n++
        return n
    }

    // One control: a glyph that may do something, the fader, the reading.
    component Level: RowLayout {
        id: lv
        property string icon: ""
        property string glyph: ""
        property color tint: Colors.of(QsWindow.window).primary
        property real value: 0
        property real maximum: 1
        property string reading: ""
        property string caption: ""
        property bool iconClickable: false
        // An inline component can't see this file's ids, so its width is its own.
        property int sliderWidth: 200
        signal iconClicked()
        signal moved(real v)
        signal scrolled(int d)

        spacing: Tokens.spacingMd

        Rectangle {
            Layout.preferredWidth: Tokens.iconLg + Tokens.spacingMd
            Layout.preferredHeight: Tokens.iconLg + Tokens.spacingMd
            radius: height / 2
            color: lv.iconClickable && iconMouse.containsMouse ? Colors.of(QsWindow.window).alpha(lv.tint, 0.18) : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            MaterialIcon {
                anchors.centerIn: parent
                name: lv.icon
                glyph: lv.glyph
                color: lv.tint
                font.pixelSize: Tokens.iconLg
            }
            MouseArea {
                id: iconMouse
                anchors.fill: parent
                enabled: lv.iconClickable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lv.iconClicked()
            }
        }
        ValueSlider {
            Layout.preferredWidth: lv.sliderWidth
            thickness: 9
            value: lv.value
            maximum: lv.maximum
            accent: lv.tint
            onMoved: v => lv.moved(v)
            onScrolled: d => lv.scrolled(d)
        }
        Column {
            Layout.preferredWidth: Tokens.spacingXxl * 2
            StyledText {
                text: lv.reading
                font.family: Tokens.fontMono
                font.weight: Font.Bold
                variant: "caption"
            }
            StyledText {
                visible: lv.caption !== ""
                width: parent.width
                text: lv.caption
                variant: "micro"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }
    }

    // This player's own PipeWire stream, for the cover's ring ("" while hidden or streamless).
    readonly property string playerNode: {
        if (!root.live) return ""
        const nodes = Audio.streamsFor(root.player?.desktopEntry ?? "")
        return nodes.length > 0 ? nodes[0].name : ""
    }
    readonly property string volApp: root.player?.desktopEntry ?? ""

    RowLayout {
        id: col
        anchors.centerIn: parent
        spacing: Tokens.spacingLg

        // ── Now playing ───────────────────────────────────────────────────────
        RowLayout {
            id: playing
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            visible: root.player !== null
            spacing: Tokens.spacingLg

            SwapFade {
                target: playing
                key: root.trackKey
                shownKey: root.shownTrack.key
                travel: Tokens.spacingSm
                onSwapped: root._take()
            }

            CookieCover {
                Layout.preferredWidth: Tokens.spacingXl * 7
                Layout.preferredHeight: Tokens.spacingXl * 7
                Layout.alignment: Qt.AlignVCenter
                source: AlbumArt.hiRes(root.shownTrack.art)
                playing: media.playing
                live: root.live
                nodeName: root.playerNode
                accent: root.tone
            }

            ColumnLayout {
                Layout.preferredWidth: Tokens.sideCardUnit * 5.5
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                StyledText {
                    Layout.fillWidth: true
                    text: root.shownTrack.title !== "" ? root.shownTrack.title : (root.player?.identity ?? "")
                    variant: "title"
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.shownTrack.artist
                    variant: "caption"
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.shownTrack.album
                    variant: "caption"
                    color: root.tone
                    elide: Text.ElideRight
                }
                MediaSeek {
                    id: seek
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingXs
                    track: media
                    accent: root.tone
                    live: root.live
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    MediaTransport {
                        size: 0.72
                        player: root.player
                        playing: media.playing
                        accent: root.tone
                    }
                    // The PLAYER's own volume (the panel's rule: Spotify rewrites its stream
                    // on a track change; its own volume lasts). Dimmed when it has none.
                    ThickSlider {
                        id: playerVol
                        Layout.fillWidth: true
                        Layout.minimumWidth: Tokens.spacingXl * 3
                        Layout.alignment: Qt.AlignVCenter
                        enabled: Audio.hasPlayerVolume(root.player, root.volApp)
                        maximum: 100
                        value: Math.min(100, Audio.playerLevel(root.player, root.volApp) * 100)
                        accent: root.tone
                        onMoved: function (v) { Audio.setPlayerLevel(root.player, root.volApp, v / 100, false) }
                    }
                }
            }
        }

        Rectangle {
            visible: playing.visible
            Layout.preferredWidth: Tokens.borderWidth
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacingMd
            Layout.bottomMargin: Tokens.spacingMd
            color: Colors.of(QsWindow.window).outline
        }

        // ── The system: levels, then the quick switches ───────────────────────
        ColumnLayout {
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingSm

            Level {
                visible: Audio.ready
                sliderWidth: Tokens.sideCardUnit * 3
                glyph: Audio.glyph(Audio.volume, Audio.muted)
                tint: Audio.muted ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).primary
                value: Audio.volume
                maximum: 1
                reading: Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
                iconClickable: true
                onIconClicked: Audio.toggleMute()
                onMoved: v => Audio.setVolume(v)
                onScrolled: d => Audio.stepVolume(d)
            }

            Repeater {
                model: Brightness.monitors

                delegate: Level {
                    id: cell
                    required property int index
                    required property var model
                    visible: cell.model.controllable
                    readonly property real min: cell.model.type === "bcl" ? Brightness.laptopMinBrightness : 0
                    function apply(v) { Brightness.requestBrightness(cell.index, Math.max(cell.min, Math.min(100, v))) }
                    sliderWidth: Tokens.sideCardUnit * 3
                    icon: "brightness_6"
                    value: cell.model.brightness
                    maximum: 100
                    reading: Math.round(cell.model.brightness) + "%"
                    caption: root.controllableCount > 1
                        ? (cell.model.type === "bcl" ? "Internal" : (cell.model.port || cell.model.label || "Display"))
                        : ""
                    onMoved: v => cell.apply(v)
                    onScrolled: d => cell.apply(cell.model.brightness + d * 5)
                }
            }

            // ── Quick switches (2026-10-20, the user's pick) ──────────────────
            // One tap each, without leaving the overview: Wi-Fi, Bluetooth, Do Not Disturb,
            // night light, the mic, Game mode. Each is its service's own toggle; one whose
            // service has nothing to switch is dimmed.
            ChipTray {
                Layout.alignment: Qt.AlignHCenter
                ChipButton {
                    symbol: Net.wifiEnabled ? "wifi" : "wifi_off"
                    on: Net.wifiEnabled
                    onActivated: Net.toggleWifi()
                    HoverTip { text: Translation.tr("Wi-Fi") }
                }
                ChipButton {
                    symbol: Bt.powered ? "bluetooth" : "bluetooth_disabled"
                    on: Bt.powered
                    enabled: Bt.available
                    onActivated: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                    HoverTip { text: Translation.tr("Bluetooth") }
                }
                ChipButton {
                    symbol: "notifications_off"
                    on: Notifications.dnd
                    onActivated: Notifications.toggleDnd()
                    HoverTip { text: Translation.tr("Do Not Disturb: no pop-ups or sounds") }
                }
                ChipButton {
                    symbol: "bedtime"
                    on: Config.nightLight
                    enabled: NightLight.blocker() === ""
                    onActivated: NightLight.toggle()
                    HoverTip { text: Translation.tr("Night light: warmer screen colours") }
                }
                ChipButton {
                    symbol: Audio.micMuted ? "mic_off" : "mic"
                    on: Audio.micMuted
                    tint: Colors.of(QsWindow.window).danger
                    enabled: Audio.ready
                    onActivated: Audio.toggleMicMute()
                    HoverTip { text: Translation.tr("Mute the microphone") }
                }
                ChipButton {
                    symbol: "bolt"
                    on: Gamemode.active
                    enabled: Gamemode.toolsAvailable
                    onActivated: Gamemode.toggle()
                    HoverTip { text: Translation.tr("Game mode: more speed for games") }
                }
            }
        }
    }
}
