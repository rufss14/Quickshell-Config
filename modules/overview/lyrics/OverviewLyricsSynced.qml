import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/lyricsmotion.js" as LyricMotion
import "../../../services/romajialign.js" as RomajiAlign
import "../../../services/mediasource.js" as MediaSource
import "../../../services/clockfmt.js" as ClockFmt
import "../../../state"
import "../lyrics"
import ".."

// ── OverviewLyricsSynced ── part of OverviewLyrics.qml; `lyrics` is the OverviewLyrics it belongs to. ──
Item {
    id: viewport
    required property var lyrics
    anchors.fill: parent
    anchors.margins: Tokens.spacingMd
    visible: Lyrics.hasSynced
    // Rectangular clip is for INPUT: the card's mask only hides pixels, so rows
    // scrolled above the card kept their seek MouseAreas live over whatever sits
    // above it (the media panel's header buttons).
    clip: true

    // Mouse-wheel browsing. `browsing` swaps the strip from "follow the current
    // line" to `browseY` until Resync (or a new track) clears it.
    property bool browsing: false
    property real browseY: 0
    onVisibleChanged: if (!visible) viewport.browsing = false

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (!viewport.browsing) {
                viewport.browseY = strip.y
                viewport.browsing = true
            }
            const d = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                                               : event.angleDelta.y / 120 * lyrics.lineHeight
            viewport.browseY = Math.max(strip.minY, Math.min(0, viewport.browseY + d))
        }
    }

    Connections {
        target: lyrics
        function on_TrackChanged() { viewport.browsing = false }
    }

    // The strip is as tall as the whole song; only a window of its rows actually
    // exists (see lyrics.visibleRows). Rows sit at absolute y, so the scroll maths
    // is independent of which rows happen to be built.
    Item {
        id: strip
        width: viewport.width
        // Summed, not multiplied: a wrapped line is two rows tall, so the strip is
        // no longer lines × lineHeight.
        height: lyrics.layout.total

        // Centres the current line on its OWN height. Using lineHeight here would
        // hang a wrapped line half a row too high.
        readonly property real centred:
            viewport.height / 2 - lyrics.rowHeight(lyrics.current) / 2
            - lyrics.rowTop(lyrics.current)
        readonly property real minY:
            Math.min(0, viewport.height - strip.height)

        // Clamped at both ends, so it can't drift past the first or last lyric and
        // leave the card blank.
        y: viewport.browsing
            ? viewport.browseY
            : lyrics.current < 0
                ? 0
                : Math.max(strip.minY, Math.min(0, strip.centred))

        // ── The scroll between lines ──────────────────────────────
        // Slower than the shell's usual spatial move, and deliberately so. This is
        // the one transition the eye is already tracking — it follows the words —
        // so a brisk snap reads as a jolt where every other surface in the shell
        // reads as brisk. Rows are also no longer a uniform height, so the distance
        // travelled varies line to line; a longer, softly-decelerating curve keeps
        // a short hop and a tall wrapped line feeling like the same gesture.
        Behavior on y {
            NumberAnimation {
                duration: Motion.spatialSlow
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }

        Repeater {
            model: lyrics.visibleRows

            Item {
                id: row
                required property var modelData

                readonly property int  index: modelData.i
                readonly property var  line:  modelData.line

                // ── Live is a TIME window, not an index ───────────────
                // These were `index === lyrics.current` and `index < lyrics.current`,
                // and lineAt() returns exactly one line — so the moment the next
                // line started, the previous one was declared past and stopped
                // animating mid-word. Lines overlap constantly in real lyrics, and
                // in a duet they overlap by design: two voices singing at once are
                // two lines whose spans cover the same seconds.
                //
                // Asking whether the clock is inside THIS line's own span lets any
                // number of them be live together, and each one finishes its own
                // words rather than being cut off by its successor.
                readonly property real endsAt:
                    LyricMotion.lineEnd(row.line, Lyrics.lines[row.index + 1])

                readonly property bool isLive:
                    lyrics.clock >= row.line.t && lyrics.clock < row.endsAt

                // During an interlude nothing is live, so the last sung line drops
                // to `past` on its own and the dots become the only focused thing
                // on the card — no special case needed for the gap.
                // ── Hidden Lyrics (karaoke mods HD and HD+) ──
                // HD: only the line being sung is shown. HD+: nothing is. The TEXT layers fade (the lead,
                // its translation, its backing line); the row, the layout under them and the karaoke
                // underlines do not — so nothing jumps when a line starts, and under HD+ the words you
                // hit still appear as you sing them. The rule is Karaoke's: it is only ever set during a
                // run begun with the mod.
                // Not `readonly`: an animation writes what it animates (a Behavior on a read-only property
                // is "Invalid property assignment", a hard load failure that takes the whole shell down).
                property real shown: Karaoke.hideMode === "all" ? 0
                    : Karaoke.hideMode === "partial" && !row.isLive ? 0 : 1
                Behavior on shown { NumberAnimation { duration: Motion.standard } }
                // Left out of the score (by right-click, or as a duet's other voice): dimmer.
                property real leftOut: lyrics.skippable && Karaoke.uncounted[row.index] ? 0.4 : 1
                Behavior on leftOut { NumberAnimation { duration: Motion.standard } }

                readonly property bool isCurrent: row.isLive
                readonly property bool isPast:    lyrics.clock >= row.endsAt
                readonly property int  distance:  lyrics.current < 0
                    ? index : Math.abs(index - lyrics.current)

                // Both come from the layout pass. A wrapped line occupies two rows
                // and everything below it shifts down by that much — which is the
                // whole reason `index * lineHeight` had to go.
                y: lyrics.rowTop(row.index)
                width:  strip.width
                height: lyrics.rowHeight(row.index)

                readonly property string lineText:
                    row.line.text
                    ?? (row.line.words ?? []).map(w => w.text).join("")

                // A blank line is a real, timed instrumental gap — shown as a rest
                // rather than as an empty row.
                readonly property bool isRest: row.lineText.trim() === ""

                // A long silence, drawn as three dots (see "The dots are a row").
                readonly property bool isInterlude: row.line.interlude === true

                // ── Words, each with the ABSOLUTE second it is sung ───
                // With word-level timing (NetEase `yrc`) that second is real. With
                // line-only timing (LRCLIB) the words are spread across the line's
                // span by length — an interpolation that drifts on a held vowel,
                // and the honest best available from line-only data.
                // ── The SAME builder the layout pass uses ─────────────
                // This was a second, private copy of unitsFor(). Both produced a
                // word list, both were edited over time, and they drifted: the
                // fallback branch derived its span from the next line's start here
                // and from the line's own duration there.
                //
                // That divergence is the whole clipping bug. The pass measures
                // lyrics.textFor(line) and the row renders row.units — two different
                // strings wrap at two different points, so the height reserved was
                // never the height drawn, and no amount of fixing the heights
                // themselves could close a gap that came from measuring something
                // else. One definition, one answer.
                readonly property var words: lyrics.unitsFor(row.line)

                // ── The units the lead actually draws ─────────────────
                // Deleted by accident when the private word-builder above it was
                // removed, and the loss was silent: `row.units` became undefined,
                // `layoutText` mapped over nothing and resolved to "", so the
                // layout had no text, reported zero height, and drew no glyphs.
                // The translation kept working throughout because it owns a
                // separate `units` — which is exactly why only the original
                // disappeared.
                //
                // `base` is where each unit's letters start within the LINE, so the
                // travelling wave runs continuously across the whole line instead of
                // restarting at every unit, and so positionToRectangle() is asked
                // for the right character.
                // The romanization, when there is one, in place of the lyric — already
                // syllable-sized and on the syllables' own timing (romanUnitsFor).
                readonly property var romanWords: lyrics.romanUnitsFor(row.line, row.index)

                readonly property var units: {
                    const w = row.romanWords.length > 0 ? row.romanWords : (row.words ?? [])
                    const u = row.romanWords.length > 0 || Lyrics.kind === "syllable"
                            ? w
                            : LyricMotion.syllabify(w)

                    let n = 0
                    for (let i = 0; i < u.length; i++) {
                        u[i].base = n
                        n += (u[i].text || "").length
                    }
                    return u
                }

                // Backing vocals, through the same builder the layout pass measures
                // with. `base` is where each unit starts in ITS OWN line — indices
                // here are into the background's text, never the lead's — and `at`
                // is the field the glyphs animate off, which is precisely what the
                // raw list did not carry. See bgUnitsFor().
                readonly property var bgUnits: lyrics.bgUnitsFor(row.line)

                readonly property string bgText:
                    row.bgUnits.map(u => u.text).join("")

                // The exact string Qt is laying out. Built from the units so that a
                // character index into it and a character index into the glyphs are
                // the same number — positionToRectangle() is indexed by character,
                // and a one-character drift would offset every glyph on the line
                // from the position it is being animated at.
                readonly property string layoutText:
                    (row.units ?? []).map(u => u.text).join("")

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isRest && row.isCurrent && !row.isInterlude
                    text: "♪"
                    color: lyrics.tintAccent
                    variant: "title"
                }

                // ── The line ──────────────────────────────────────────
                // Scaled to fit: a long lyric is wider than the card, and the mask
                // would simply cut the end off it. Scaling keeps every word on
                // screen; a long line just renders a little smaller.
                Item {
                    id: leadBlock

                    // Top-anchored rather than centred once a line can carry a
                    // background row beneath it: centring the lead in a row that is
                    // taller than the lead would float it, and the background would
                    // hang off the bottom.
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width:  parent.width
                    // Through the SAME function the layout pass uses, so the height
                    // reserved for this row and the height it draws at cannot
                    // differ. A floor applied on one side only is what put the
                    // translation back under the following lyric.
                    height: lyrics.leadHeight(lineLayout.contentHeight)
                    visible: !row.isRest

                    // ── Qt decides where every glyph goes ─────────────
                    // Invisible, but it is the authority on this line's layout:
                    // where it wraps, how an aligned line is offset, which font
                    // actually supplies each glyph. Nothing in this file measures
                    // text any more.
                    //
                    // Its text is built from the UNITS, not from line.text — the
                    // two can differ by a trailing space, and positionToRectangle()
                    // is indexed by character, so a one-character drift would shift
                    // the whole line's glyphs against their own highlight.
                    OverviewLyricLayout {
                        id: lineLayout
                        width: parent.width
                        text: row.layoutText
                        horizontalAlignment: row.line.aligned === "right"
                            ? TextEdit.AlignRight : TextEdit.AlignLeft
                    }

                    // ── No blur layer ─────────────────────────────
                    // There was a zero-offset coloured shadow here, over the whole
                    // line. It read as haze rather than light: a blur spreads a
                    // letter's own colour outward, so every glyph got softer
                    // instead of brighter at exactly the moment it was meant to be
                    // most legible. The travelling highlight replaced it, and it is
                    // strictly cheaper — no render layers at all now.

                    LyricGlyphs {
                        anchors.fill: parent
                        lay:       lineLayout
                        fg:        lyrics.tintFg
                        accent:    lyrics.tintAccent
                        units:     row.units
                        live:      row.isCurrent
                        past:      row.isPast
                        distance:  row.distance
                        clock:     lyrics.clock
                        wavePhase: lyrics.wavePhase
                        wholeLine: lyrics.lineOnly
                        embolden:  true
                        opacity:   row.shown * row.leftOut   // Hidden Lyrics fades the text, not the marks
                    }

                    // The words you have sung, underlined (karaoke; nothing when it is off) —
                    // on every line you sang, current or past.
                    KaraokeMarks {
                        anchors.fill: parent
                        lay:       lineLayout
                        text:      row.layoutText
                        lineIndex: row.index
                        accent:    lyrics.tintAccent
                    }
                }

                // ── The translation ───────────────────────────────────
                // Under its original, smaller and lighter — the pair reads as one
                // line with a gloss beneath it rather than as two lyrics competing
                // for the same attention.
                Item {
                    id: trBlock
                    opacity: row.shown * row.leftOut

                    anchors.top: bgBlock.visible ? bgBlock.bottom : leadBlock.bottom
                    anchors.topMargin: lyrics.trGap
                    anchors.left: parent.left
                    anchors.right: parent.right

                    // Matches exactly what the layout pass reserved, because both
                    // are the content height of the same component at the same
                    // width. A fixed allowance is what made a wrapped translation
                    // overrun the row it was given.
                    height: trLayout.contentHeight

                    readonly property var units: lyrics.translationUnits(row.index)
                    visible: !row.isRest && trBlock.units.length > 0

                    // Its own layout, at the smaller size — the lead's positions
                    // describe the lead's font, and borrowing them would place
                    // these letters on a grid drawn for type they are not set in.
                    OverviewLyricLayout {
                        id: trLayout
                        width: parent.width
                        font.pixelSize: lyrics.trFontSize
                        text: trBlock.units.map(u => u.text).join("")
                        horizontalAlignment: row.line.aligned === "right"
                            ? TextEdit.AlignRight : TextEdit.AlignLeft
                    }

                    // ── Animated, on borrowed time ────────────────────
                    // The same travelling light the lyric above gets, running on
                    // timings interpolated from that line's span — see
                    // translationUnits(). Words rather than syllables: splitting a
                    // translation finer would be inventing detail on top of an
                    // interpolation, and at this size it would be invisible anyway.
                    //
                    // Fainter and slower deliberately. It is a gloss, and two
                    // equally lively lines would split the eye between them.
                    LyricGlyphs {
                        anchors.fill: parent
                        lay:         trLayout
                        fg:          lyrics.tintFg
                        accent:      lyrics.tintAccent
                        units:       trBlock.units
                        live:        row.isCurrent
                        past:        row.isPast
                        distance:    row.distance
                        clock:       lyrics.clock
                        wavePhase:   lyrics.wavePhase
                        wholeLine:   lyrics.lineOnly
                        motionScale: 0.55
                        dim:         0.72
                    }
                }

                // ── Background vocals ─────────────────────────────────
                // The short echoes and answers sung under the lead. Their own row,
                // smaller and quieter, on the same side as the voice they belong to.
                //
                // Deliberately NOT given the full per-syllable treatment the lead
                // gets. These are secondary by definition — running a travelling
                // light through them would put two competing highlights on screen
                // and pull the eye off the line actually being sung. They fade in
                // over their own span instead, which is the amount of attention
                // they are worth.
                Item {
                    id: bgBlock
                    opacity: row.shown * row.leftOut

                    anchors.top: leadBlock.bottom
                    anchors.topMargin: lyrics.bgGap
                    anchors.left: parent.left
                    anchors.right: parent.right

                    // Its content's height, NOT a fixed allowance. This was the
                    // last block still pinned to a constant (~18px): anything
                    // taller — a wrapped phrase, a larger face — laid its glyphs
                    // out below the block's own bottom edge, where they simply were
                    // not drawn. That is the "background vocals disappear".
                    height: bgLayout.contentHeight

                    // The same test the layout pass makes, so the height reserved and
                    // the height drawn cannot disagree about whether this row exists.
                    visible: !row.isRest && row.bgText !== ""

                    // Its own layout, at the smaller size, because the lead's
                    // positions describe the lead's font. Reusing that one would
                    // place these letters on a grid drawn for type they are not set
                    // in.
                    OverviewLyricLayout {
                        id: bgLayout
                        width: parent.width
                        font.pixelSize: lyrics.bgFontSize
                        font.italic: true
                        text: row.bgText
                        horizontalAlignment: row.line.aligned === "right"
                            ? TextEdit.AlignRight : TextEdit.AlignLeft
                    }

                    // ── Synced and animated, like the lead ────────────
                    // These were one faded StyledText holding the whole phrase,
                    // which meant the backing vocal was neither timed nor moving —
                    // it simply appeared for the length of the line. It carries
                    // per-syllable timings exactly as the lead does, so there was
                    // never a reason to throw them away.
                    //
                    // Quieter and slower on purpose: `dim` and `motionScale` are
                    // what keep it secondary. Two equally lively lines would split
                    // the eye between them, which is the thing a backing vocal must
                    // not do.
                    LyricGlyphs {
                        anchors.fill: parent
                        lay:         bgLayout
                        fg:          lyrics.tintFg
                        accent:      lyrics.tintAccent
                        units:       row.bgUnits
                        live:        row.isCurrent
                        past:        row.isPast
                        distance:    row.distance
                        clock:       lyrics.clock
                        wavePhase:   lyrics.wavePhase
                        // Secondary, but it has to READ as animated. At 0.5 motion
                        // and 0.62 opacity the sweep was technically running and
                        // effectively invisible — the line looked static. The size
                        // difference is what makes it secondary now, so these can
                        // afford to be closer to the lead's.
                        motionScale: 0.75
                        dim:         0.85
                    }
                }

                // ── The interlude: three dots, as if they were syllables ─────────────
                // A silent line: the same travelling head, soft leading edge and glint
                // the glyphs use, each dot standing where a syllable would. The head
                // crosses ALL THREE over the WHOLE gap (interludeAt's progress), so the
                // first lights as the silence begins and the last as it ends — what
                // the dots count is the actual gap, whatever its length. They sit where
                // the words do, in the room the row has opened (`dotsOpen`).
                Row {
                    id: dots
                    visible: row.isInterlude && row.index === lyrics.dotsRow && lyrics.dotsOpen > 0.01
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -lyrics.rowGap / 2
                    spacing: Tokens.spacingSm

                    readonly property var at: row.isInterlude ? LyricMotion.interludeAt(row.line, lyrics.clock)
                                                              : ({ progress: 0, remaining: 0 })

                    // They rise out of nothing as the row opens, and the last second lifts
                    // them a touch more: without it the dots just stop and a line appears,
                    // which gives no sense that the wait was ending.
                    readonly property real imminent: dots.at.remaining > 1.0 ? 0 : (1.0 - dots.at.remaining)
                    opacity: lyrics.dotsOpen
                    scale: (0.6 + 0.4 * lyrics.dotsOpen) * (1.0 + 0.12 * dots.imminent)
                    transformOrigin: Item.Left

                    Repeater {
                        model: row.isInterlude ? 3 : 0

                        Item {
                            id: dot
                            required property int index

                            width:  14
                            height: 14

                            // Where this dot sits along the line, 0 → 1, exactly as a
                            // glyph's `place` does within its unit.
                            readonly property real place: dot.index / 2
                            readonly property real edge: 0.45

                            // The head runs from before the first dot to past the last,
                            // so the first does not start lit and the last still
                            // finishes lit.
                            readonly property real head:
                                -dot.edge + dots.at.progress * (1 + 2 * dot.edge)

                            readonly property real litness: {
                                const t = (dot.head - dot.place) / dot.edge
                                return t < 0 ? 0 : (t > 1 ? 1 : t)
                            }

                            // The bright band riding the head, as on a sung letter.
                            readonly property real glint: {
                                const d = Math.abs(dot.head - dot.place)
                                return d >= 0.4 ? 0 : 1 - d / 0.4
                            }

                            Rectangle {
                                anchors.centerIn: parent

                                // Grows with the light, exactly as a glyph scales.
                                width:  5 + 5 * dot.litness + 3 * dot.glint
                                height: width
                                radius: width / 2

                                // fg → accent as the light arrives, flaring brighter as
                                // the head crosses.
                                color: Colors.of(QsWindow.window).mix(
                                    Colors.of(QsWindow.window).mix(lyrics.tintFg, lyrics.tintAccent, dot.litness),
                                    Qt.lighter(lyrics.tintAccent, 2.3),
                                    Math.min(1, dot.glint * 1.35))

                                opacity: 0.34 + 0.66 * dot.litness

                                // The shared wave, so the dots breathe on the same phase as
                                // every lit letter rather than to their own clock.
                                y: -1.6 * dot.litness
                                   * Math.sin(lyrics.wavePhase - dot.index * 0.7)

                                Behavior on width   { NumberAnimation { duration: Motion.standard } }
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            }
                        }
                    }
                }

                // What this row's three blocks actually occupy, bottom-most first.
                // Compared against what the pass reserved — see reportRow().
                readonly property real drawn:
                    trBlock.visible ? trBlock.y + trBlock.height
                  : bgBlock.visible ? bgBlock.y + bgBlock.height
                  : leadBlock.visible ? leadBlock.y + leadBlock.height
                  : 0

                onDrawnChanged: lyrics.reportRow(row.index, row.drawn)

                // Right-click: leave this line out of the karaoke score, or put it back. Takes only the
                // right button, so the seek below still gets the left.
                MouseArea {
                    anchors.fill: parent
                    enabled: lyrics.skippable && !row.isRest && Karaoke.songId !== ""
                    acceptedButtons: Qt.RightButton
                    onClicked: Karaoke.toggleSkip(row.index)
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: (lyrics.player?.canSeek ?? false) && !row.isRest
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    // `position` is writable — the same seek the media card uses.
                    // Subtract the offset so we seek the AUDIO to where this lyric
                    // really is, rather than to our corrected view of it.
                    onClicked: if (lyrics.player)
                        lyrics.player.position = Math.max(0, row.line.t - Lyrics.offset)
                }
            }
        }
    }
}
