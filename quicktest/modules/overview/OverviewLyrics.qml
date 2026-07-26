import QtQuick
import QtQuick.Effects
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── OverviewLyrics ────────────────────────────────────────────────────────────
// Time-synced lyrics, left of the media card, dressed in the album cover's colours.
// The live line animates WORD BY WORD as the vocal reaches it.
//
// ── The word timing is REAL, when the provider has it ─────────────────────────
// NetEase's `yrc` gives a start AND a duration for every word, so a held note stays lit
// for exactly as long as it's held. That's `Lyrics.kind === "word"`, and it's what makes
// this feel sung rather than merely highlighted.
//
// LRCLIB only has line-level timing. On that path the words are interpolated across the
// line's span by length — which drifts on a melismatic vowel, and is the honest best you
// can do with line-only data. The card handles both; `Lyrics.kind` says which is in play.
//
// ── It does not own a clock ───────────────────────────────────────────────────
// `position` is handed in from the media card, which already tracks it. A second pair of
// timers following the same number would double the cost of the only continuously-
// ticking thing on the overlay, and the two clocks would drift — so the lyrics and the
// progress bar would disagree about where the song is.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    required property var  player
    required property real position

    elevation: Tokens.elevationPopup

    // A clearly visible, album-tinted edge. The default surface outline washes out against
    // arbitrary cover colours, so the card reads as borderless; this is the same 2px accent
    // language the art thumbnail and transport controls INSIDE these cards already use, so
    // the outline belongs to the same family rather than being a bare white line.
    border.width: 2
    border.color: Colors.alpha(AlbumArt.accent, 0.60)
    Behavior on border.color { ColorAnimation { duration: Motion.spatial } }

    implicitWidth:  320
    implicitHeight: 148

    visible: root.player !== null

    // The card takes the cover's shadow as its fill. Falls back to the shell palette
    // when there's no art (AlbumArt handles that).
    color: AlbumArt.bg
    Behavior on color { ColorAnimation { duration: Motion.spatial } }

    readonly property int lineHeight: 34

    // Everything resolves against the CORRECTED clock, never the raw one. `Lyrics.offset`
    // absorbs the slack no amount of matching can remove — player latency, the audio path,
    // and the fact that a lyric provider's timings are keyed to their master rather than
    // the one you happen to be streaming.
    readonly property real clock: root.position + Lyrics.offset

    readonly property int current: Lyrics.hasSynced ? Lyrics.lineAt(root.clock) : -1

    // ── The wave ──────────────────────────────────────────────────────────────
    // ONE animator for the whole card, not one per letter. Every lit letter reads its
    // offset off this single running phase, so they move as one travelling wave instead of
    // N independent bobs that happen to be near each other. It also means the effect costs
    // one animation regardless of how many letters are on screen.
    property real wavePhase: 0

    NumberAnimation on wavePhase {
        // Gated on the overlay actually being OPEN, not merely on a player existing.
        // `root.visible` is true whenever something is playing — so gating on that would
        // leave this animator running forever behind a closed overlay, which is precisely
        // the mistake the bar's MediaController had to be fixed for.
        running: UiState.overviewOpen && Lyrics.hasSynced
        loops: Animation.Infinite
        from: 0
        to: 2 * Math.PI
        duration: 2200
    }

    // ── Windowed rows ─────────────────────────────────────────────────────────
    // Only the lines you can actually see are built.
    //
    // Rendering per-letter means ~30 items a line, and songs run well past 100 lines — so
    // building them all would be thousands of Text nodes to show the five that fit on the
    // card. The rows are instead positioned ABSOLUTELY by index inside a full-height strip
    // (rather than stacked in a Column), which lets the model be a moving window while the
    // scroll maths stays exactly the same.
    readonly property int windowBefore: 3
    readonly property int windowAfter:  4

    readonly property var visibleRows: {
        const n = Lyrics.lines.length
        if (!Lyrics.hasSynced || n === 0) return []

        const c = Math.max(0, root.current)
        const from = Math.max(0, c - root.windowBefore)
        const to   = Math.min(n - 1, c + root.windowAfter)

        const out = []
        for (let i = from; i <= to; i++) out.push({ i: i, line: Lyrics.lines[i] })
        return out
    }

    // ── Fetch ─────────────────────────────────────────────────────────────────
    // NOT gated on the overlay being open. It used to be, which meant the request didn't
    // even start until you opened the overview — so you sat and watched it load. Now the
    // lyrics for the playing track are already in hand by the time you look.
    //
    // (The position timers in the media card stay gated: those tick 30×/second and must
    // not run for a card nobody is looking at. This is a single request per track.)
    readonly property string _track:
        (root.player?.trackTitle  ?? "") + "::" +
        (root.player?.trackArtist ?? "") + "::" +
        (root.player?.trackAlbum  ?? "")

    function _reload() {
        if (!root.player) return
        Lyrics.load(root.player.trackArtist ?? "",
                    root.player.trackTitle  ?? "",
                    root.player.trackAlbum  ?? "",
                    root.player.length      ?? 0)
    }

    on_TrackChanged: _reload()
    onPlayerChanged: _reload()
    Component.onCompleted: _reload()

    // ══ Cover wash ════════════════════════════════════════════════════════════
    // The blurred cover over the card's fill, so the surface is the album's colour
    // rather than a flat block of it.
    Item {
        anchors.fill: parent
        visible: bgArt.status === Image.Ready

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Image {
            id: bgArt
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: bgArt
            blurEnabled: true
            blur: 1.0
            blurMax: 56
            autoPaddingEnabled: false
            brightness: -0.30
            saturation: 0.30
            opacity: 0.45
        }
    }

    // ══ Content ═══════════════════════════════════════════════════════════════
    // Masked to the card's ROUNDED rect.
    //
    // This is the clipping bug: `clip: true` is rectangular and knows nothing about a
    // radius, so lyrics scrolling past the top and bottom of the card showed through its
    // rounded corners. Exactly the same class of bug as the window previews' square
    // corners poking out of the workspace cells, and it takes the same fix — a mask, not
    // a clip.
    Item {
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // ── Synced ────────────────────────────────────────────────────────────
        Item {
            id: viewport
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            visible: Lyrics.hasSynced

            // The strip is as tall as the whole song; only a window of its rows actually
            // exists (see root.visibleRows). Rows sit at absolute y, so the scroll maths
            // is independent of which rows happen to be built.
            Item {
                id: strip
                width: viewport.width
                height: Lyrics.lines.length * root.lineHeight

                readonly property real centred:
                    viewport.height / 2 - root.lineHeight / 2 - root.current * root.lineHeight
                readonly property real minY:
                    Math.min(0, viewport.height - strip.height)

                // Clamped at both ends, so it can't drift past the first or last lyric and
                // leave the card blank.
                y: root.current < 0
                    ? 0
                    : Math.max(strip.minY, Math.min(0, strip.centred))

                Behavior on y {
                    NumberAnimation {
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                Repeater {
                    model: root.visibleRows

                    Item {
                        id: row
                        required property var modelData

                        readonly property int  index: modelData.i
                        readonly property var  line:  modelData.line

                        readonly property bool isCurrent: index === root.current
                        readonly property bool isPast:    index < root.current
                        readonly property int  distance:  root.current < 0
                            ? index : Math.abs(index - root.current)

                        y: index * root.lineHeight
                        width:  strip.width
                        height: root.lineHeight

                        readonly property string lineText:
                            row.line.text
                            ?? (row.line.words ?? []).map(w => w.text).join("")

                        // A blank line is a real, timed instrumental gap — shown as a rest
                        // rather than as an empty row.
                        readonly property bool isRest: row.lineText.trim() === ""

                        // ── Words, each with the ABSOLUTE second it is sung ───
                        // With word-level timing (NetEase `yrc`) that second is real. With
                        // line-only timing (LRCLIB) the words are spread across the line's
                        // span by length — an interpolation that drifts on a held vowel,
                        // and the honest best available from line-only data.
                        readonly property var words: {
                            const src = row.line.words

                            if (src && src.length > 0)
                                return src.map(w => ({ text: w.text.trim(), at: w.t }))
                                          .filter(w => w.text !== "")

                            const raw = row.lineText.split(" ").filter(w => w !== "")
                            if (raw.length === 0) return []

                            let chars = 0
                            for (let i = 0; i < raw.length; i++) chars += raw[i].length
                            if (chars === 0) return []

                            const next = Lyrics.lines[row.index + 1]
                            const end  = next ? next.t : row.line.t + 4
                            const span = Math.max(0.2, end - row.line.t)

                            const out = []
                            let seen = 0
                            for (let i = 0; i < raw.length; i++) {
                                out.push({ text: raw[i], at: row.line.t + (seen / chars) * span })
                                seen += raw[i].length
                            }
                            return out
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.isRest && row.isCurrent
                            text: "♪"
                            color: AlbumArt.accent
                            variant: "title"
                        }

                        // ── The line ──────────────────────────────────────────
                        // Scaled to fit: a long lyric is wider than the card, and the mask
                        // would simply cut the end off it. Scaling keeps every word on
                        // screen; a long line just renders a little smaller.
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            width:  parent.width
                            height: line.height
                            visible: !row.isRest

                            Row {
                                id: line
                                spacing: 6

                                scale: implicitWidth > 0
                                    ? Math.min(1, parent.width / implicitWidth)
                                    : 1
                                transformOrigin: Item.Left

                                Behavior on scale { NumberAnimation { duration: Motion.standard } }

                                // ── The glow ──────────────────────────────────
                                // A zero-offset coloured shadow IS a glow, and one effect
                                // over the whole line costs far less than one per letter.
                                //
                                // The layer stays ENABLED for every row in the window, and
                                // it is the shadow's OPACITY that's animated. Toggling
                                // `layer.enabled: row.isCurrent` instead — which is what
                                // this did — makes the glow pop in and vanish, because an
                                // item either has a render layer or it doesn't; there is no
                                // half. Eight small layers is a cheap price for a glow that
                                // fades.
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: AlbumArt.accent
                                    shadowBlur: 0.75
                                    shadowHorizontalOffset: 0
                                    shadowVerticalOffset: 0

                                    shadowOpacity: row.isCurrent ? 0.55 : 0.0
                                    Behavior on shadowOpacity {
                                        NumberAnimation {
                                            duration: Motion.emphasized
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Motion.emphasizedDecel
                                        }
                                    }
                                }

                                Repeater {
                                    model: row.words

                                    // One item per WORD, holding one item per LETTER. The
                                    // word owns the timing; the letters own the motion.
                                    Row {
                                        id: word
                                        required property var modelData
                                        required property int index

                                        // Lit once the vocal reaches this word. Past lines
                                        // are wholly lit — they have been sung.
                                        readonly property bool lit:
                                            row.isPast || (row.isCurrent && root.clock >= modelData.at)

                                        // Where this word's letters start in the line, so
                                        // the wave runs continuously ACROSS words rather
                                        // than restarting at each one.
                                        readonly property int letterBase: {
                                            let n = 0
                                            for (let i = 0; i < word.index; i++)
                                                n += row.words[i].text.length
                                            return n
                                        }

                                        Repeater {
                                            model: word.modelData.text.length

                                            StyledText {
                                                id: glyph
                                                required property int index

                                                readonly property int seq: word.letterBase + glyph.index

                                                text: word.modelData.text.charAt(glyph.index)

                                                // ── Every letter is typed the SAME ────
                                                // Size, weight and spacing are constants,
                                                // deliberately.
                                                //
                                                // They used to switch with `isCurrent`
                                                // (headline+bold vs label), and font metrics
                                                // cannot be animated — so a line becoming or
                                                // leaving current SNAPPED, every letter
                                                // changing size at once. Worse, it changed
                                                // the Row's implicitWidth, which jerked the
                                                // fit-to-width scale with it. That snap was
                                                // the "off" transition, and it's why the
                                                // other lines read as a different, plainer
                                                // thing.
                                                //
                                                // Hierarchy now comes only from colour,
                                                // opacity, glow and motion — all of which
                                                // interpolate. Nothing here changes shape.
                                                variant: "title"
                                                font.bold: true
                                                font.letterSpacing: 0.4

                                                color: row.isCurrent && word.lit ? AlbumArt.accent
                                                                                 : AlbumArt.fg

                                                opacity: row.isCurrent
                                                    ? (word.lit ? 1.0 : 0.42)
                                                    : row.distance === 1 ? 0.52
                                                    : row.distance === 2 ? 0.30
                                                    : 0.15

                                                // ── The wave, with an envelope ────────
                                                // `waveAmp` fades the oscillation IN as a
                                                // word is sung and OUT as its line passes.
                                                //
                                                // Without it `y` jumped from wherever the
                                                // sine happened to be straight to 0 the
                                                // moment the line stopped being current — a
                                                // hard snap, mid-swing, on every letter at
                                                // once. That was the broken exit. The
                                                // envelope means the wave always starts and
                                                // ends at rest, however abruptly the state
                                                // changes underneath it.
                                                // NOT `readonly`: a Behavior animates a
                                                // property by WRITING to it, so a readonly
                                                // one can't have any. The binding below is
                                                // still the source of truth; the Behavior
                                                // just eases the trip to each new value.
                                                property real waveAmp:
                                                    (row.isCurrent && word.lit) ? 1 : 0

                                                Behavior on waveAmp {
                                                    NumberAnimation {
                                                        duration: Motion.emphasized
                                                        easing.type: Easing.BezierSpline
                                                        easing.bezierCurve: Motion.emphasizedDecel
                                                    }
                                                }

                                                // Every lit letter reads the SAME running
                                                // phase, shifted by its position in the line,
                                                // so the line ripples as one travelling wave
                                                // rather than as a row of separate bobs.
                                                y: -2.6 * glyph.waveAmp
                                                     * Math.sin(root.wavePhase - glyph.seq * 0.32)

                                                // The pop as the vocal lands on it — driven
                                                // off the same envelope, so it eases away
                                                // with the wave instead of releasing early.
                                                scale: 1.0 + 0.05 * glyph.waveAmp
                                                transformOrigin: Item.Bottom

                                                Behavior on color   { ColorAnimation  { duration: Motion.emphasized } }
                                                Behavior on opacity { NumberAnimation { duration: Motion.emphasized } }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: (root.player?.canSeek ?? false) && !row.isRest
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            // `position` is writable — the same seek the media card uses.
                            // Subtract the offset so we seek the AUDIO to where this lyric
                            // really is, rather than to our corrected view of it.
                            onClicked: if (root.player)
                                root.player.position = Math.max(0, row.line.t - Lyrics.offset)
                        }
                    }
                }
            }
        }

        // ── Plain lyrics — present, but not synced ────────────────────────────
        // No highlight. Faking a sync we don't have would be worse than admitting we
        // don't have one.
        Flickable {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            visible: Lyrics.state === "plain"
            clip: true
            contentHeight: plainText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            StyledText {
                id: plainText
                width: parent.width
                text: Lyrics.plain
                variant: "label"
                color: AlbumArt.fgMuted
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
        }

        // ── Everything else ───────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingSm
            width: parent.width - Tokens.spacingXl * 2

            visible: !Lyrics.hasSynced && Lyrics.state !== "plain"

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lyrics.state === "loading"      ? "󰑮"
                    : Lyrics.state === "instrumental" ? "󰝚"
                    : Lyrics.state === "error"        ? "󰅚"
                    : "󰃨"
                font.pixelSize: 24
                color: Lyrics.state === "error" ? Colors.danger : AlbumArt.fgDim
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lyrics.state === "loading"      ? "Looking for lyrics…"
                    : Lyrics.state === "instrumental" ? "Instrumental"
                    : Lyrics.state === "error"        ? "Couldn't reach a lyrics provider"
                    : Lyrics.state === "idle"         ? "Lyrics off"
                    : "No lyrics for this track"
                variant: "caption"
                color: AlbumArt.fgDim
                wrapMode: Text.WordWrap
            }
        }
    }

    HoverHandler { id: cardHover }

    // ── Sync nudge ────────────────────────────────────────────────────────────
    // Shifts the lyrics against the audio, in 0.1s steps, and remembers it.
    //
    // No amount of matching removes the last of the drift: the player reports position
    // with latency, the audio path adds its own, and the provider's timings belong to
    // their master, not the stream you're hearing. So the last word goes to you.
    //
    // Hidden until you hover the card — it's a fix-it, not furniture.
    Row {
        anchors.bottom: parent.bottom
        anchors.right:  parent.right
        anchors.margins: Tokens.spacingSm
        spacing: 2
        z: 20

        visible: opacity > 0.01
        opacity: (cardHover.hovered && Lyrics.hasSynced) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        PanelButton {
            variant: "ghost"
            implicitWidth:  20
            implicitHeight: 20
            glyph: "󰍴"
            glyphTint: AlbumArt.fgMuted
            accent: AlbumArt.accent
            onActivated: Lyrics.nudge(-0.1)
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            horizontalAlignment: Text.AlignHCenter
            text: (Lyrics.offset > 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s"
            variant: "caption"
            font.family: Tokens.fontMono
            color: Lyrics.offset === 0 ? AlbumArt.fgDim : AlbumArt.accent

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Lyrics.resetOffset()      // click the readout to zero it
            }
        }

        PanelButton {
            variant: "ghost"
            implicitWidth:  20
            implicitHeight: 20
            glyph: "󰐕"
            glyphTint: AlbumArt.fgMuted
            accent: AlbumArt.accent
            onActivated: Lyrics.nudge(0.1)
        }
    }

    // The mask's shape. Never drawn — it exists only to be sampled.
    Item {
        id: cardMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "white"
        }
    }
}
