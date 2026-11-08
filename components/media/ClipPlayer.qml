import QtQuick
import QtMultimedia

// ── ClipPlayer ────────────────────────────────────────────────────────────────
// The clip editor's video: a MediaPlayer into a VideoOutput, and the handful of
// controls an editor needs — play/pause, seek, frame step, speed, volume, and a
// loop over the span being cut.
//
// ── The one file that may `import QtMultimedia` ───────────────────────────────
// qt6-multimedia is an optional package. A missing QML module makes the importing
// file fail to EXIST — and that cascades to everything that imports IT. So this
// file is never imported and never named as a type: state/Media.qml probes it
// with Qt.createComponent, and the gallery loads it by URL through a Loader only
// once the probe says yes. Without the package the editor still trims, exports and
// saves frames; it just can't play (and says how to fix that). Morph's rule, for
// the same reason (components/blob/MorphProbe.qml).
//
// Times are milliseconds, as MediaPlayer's are.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string source: ""          // an absolute file path
    property bool muted: false
    property real volume: 1
    property real rate: 1
    // Start playing as soon as the media has loaded (the gallery's player, as against its editor).
    property bool autoplay: false
    // Fill the box, cropping (a thumbnail's hover preview), rather than letterbox it.
    property bool crop: false
    // Loop the whole clip, over and over (the hover preview).
    property bool loopAll: false

    // Loop the span being cut: past `loopEnd`, back to `loopStart`.
    property bool loopSpan: false
    property real loopStart: 0
    property real loopEnd: 0

    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property real position: player.position
    readonly property real duration: player.duration
    readonly property bool hasVideo: player.hasVideo
    // Something on screen: the poster under it can go.
    readonly property bool showing: root.hasVideo && (root.playing || root._seeked)
    readonly property string error: player.error === MediaPlayer.NoError ? "" : player.errorString
    readonly property real frameMs: {
        const f = Number(player.metaData.value(MediaMetaData.VideoFrameRate))
        return 1000 / (f > 1 && f < 1000 ? f : 60)
    }
    property bool _seeked: false

    function play() {
        // At (or past) the end, or outside the loop, start from the right place.
        if (root.loopSpan && (player.position < root.loopStart || player.position >= root.loopEnd))
            player.setPosition(root.loopStart)
        else if (player.duration > 0 && player.position >= player.duration - 50)
            player.setPosition(root.loopSpan ? root.loopStart : 0)
        player.play()
    }
    function pause()  { player.pause() }
    function toggle() { if (root.playing) root.pause(); else root.play() }
    function seek(ms) {
        player.setPosition(Math.max(0, Math.min(player.duration, ms)))
        root._seeked = true
    }
    // One frame either way, paused: the way an editor finds the exact cut.
    function step(frames) {
        if (root.playing) player.pause()
        root.seek(player.position + frames * root.frameMs)
    }

    // A path → a file URL. encodeURI leaves # and ? alone, and in a URL they end
    // the path (Clips.copyClip's rule).
    function _url(p) {
        return p === "" ? "" : "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F")
    }

    onSourceChanged: root._seeked = false

    MediaPlayer {
        id: player
        source: root._url(root.source)
        videoOutput: video
        audioOutput: AudioOutput {
            muted: root.muted
            volume: root.volume
        }
        playbackRate: root.rate
        loops: root.loopAll ? MediaPlayer.Infinite : 1
        onPositionChanged: {
            if (root.loopSpan && root.playing && root.loopEnd > root.loopStart
                && player.position >= root.loopEnd)
                player.setPosition(root.loopStart)
        }
        // A frame to look at before anything plays: loaded, seek to the start.
        onMediaStatusChanged: {
            if (player.mediaStatus === MediaPlayer.LoadedMedia && !root._seeked) {
                root.seek(0)
                if (root.autoplay) root.play()
            }
        }
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: root.crop ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit
    }
}
