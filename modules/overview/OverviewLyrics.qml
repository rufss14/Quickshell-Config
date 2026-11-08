import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"
import "../../services/lyricsmotion.js" as LyricMotion
import "../../services/romajialign.js" as RomajiAlign
import "../../services/mediasource.js" as MediaSource
import "../../services/clockfmt.js" as ClockFmt
import "../../state"
import "lyrics"

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
    // Reached by the view files in lyrics/.
    property alias cardHover: cardHover
    property alias content: content

    required property var  player
    required property real position

    // Defaults to the overlay's state so the overview passes nothing; the lockscreen
    // passes true. See the wave animator below for why this is not simply `visible`.
    property bool active: UiState.overviewOpen

    // ── Where this card's colours come from ───────────────────────────────────
    // Defaults to the cover, which is what the overlay was designed around and what every
    // caller wanted until the desktop existed. A tile sits ON the wallpaper, where an
    // album's palette competes with the desktop rather than belonging to it — so a widget
    // can point these at the shell's own wallpaper-derived palette and nothing else in
    // this file needs to know which it got.
    //
    // Five colour properties rather than one object: these are animated with Behaviors and
    // bound individually, and a `var` holding all five would invalidate every consumer
    // whenever any one of them changed.
    property color tintBg:      Config.albumCardColors ? AlbumArt.bg      : Colors.of(QsWindow.window).surface
    property color tintFg:      Config.albumCardColors ? AlbumArt.fg      : Colors.of(QsWindow.window).fg
    property color tintFgDim:   Config.albumCardColors ? AlbumArt.fgDim   : Colors.of(QsWindow.window).fgDim
    property color tintFgMuted: Config.albumCardColors ? AlbumArt.fgMuted : Colors.of(QsWindow.window).fgMuted
    property color tintAccent:  Config.albumCardColors ? AlbumArt.accent  : Colors.of(QsWindow.window).primary

    // The frame, in pixels. 0 removes it — over the overlay's scrim an outline is what
    // stops the card dissolving into the blur, but a tile already sits on a wallpaper that
    // gives it an edge, and there the same 2px reads as a box drawn around the lyrics.
    property int frameWidth: 2

    // ── Optional dressing, for hosts that give the card a fixed frame ─────────
    // Both off by default so the overview, lock screen and panel look as they always did;
    // the desktop tile turns them on.
    //
    //   showTrack   what is playing, without a permanent header eating the lyrics' room: a
    //               small card (cover, title, artist) that appears when a song starts and
    //               while the pointer is over the tile, then gets out of the way — plus a
    //               hairline along the bottom edge for how far through the song it is.
    //               Only while lyrics are on screen: the empty states say enough.
    //   edgeFade    lines dissolve into the card at the top and bottom of the viewport,
    //               where they were sliced off by its clip. The fade is the card's own
    //               colour, so over a drifting wash the very edge reads as a soft vignette.
    property bool showTrack: false
    property bool edgeFade: false
    // Right-click on a lyric leaves it out of the karaoke score (Karaoke.toggleSkip); a line left out, or
    // excused as the other voice of a duet, is drawn dimmer. Off for a card that is only a picture of the lyrics.
    property bool skippable: true
    // Draw the built-in "nothing to read" state (the spectrum, the track, the seek bar, a
    // state pill)? A host that has its own, quieter one — the media panel, which already
    // shows the track and the seek bar beside this card — turns it off and draws that over
    // `emptyShown` instead. Off also releases the spectrum, which only that state uses.
    property bool showEmpty: true
    readonly property bool _trackOn: root.showTrack && Lyrics.hasSynced

    // ── The artwork wash ──────────────────────────────────────────────────────
    // On by default: the cover blurred behind the card is the design, not decoration.
    //
    // It has to be switchable because it OVERRULES the palette. Point the colours at the
    // wallpaper and leave this on and almost nothing changes — the album art is still what
    // you see, and the tint only survives in the text and the gradient over it. That is
    // exactly what "the colourscheme option does nothing" was.
    property bool artWash: Config.albumCardColors

    // ── Which background ──────────────────────────────────────────────────────
    // "cover" is the blurred artwork this card was designed around. "flow" is SpicyFlow:
    // the same colours, drifting, with the photograph's composition thrown away — which
    // is what stops a cover with a bright corner putting a bright corner behind the text.
    // "none" leaves the flat fill.
    //
    // `artWash: false` still overrides all of it, because that is what wallpaper colours
    // set — a cover-derived background of any kind defeats a wallpaper palette.
    property string washStyle: "flow"

    elevation: Tokens.elevationPopup
    // Matches OverviewNowPlaying beside it and the overview's other islands.
    cornerRadius: Tokens.radiusXl

    // A clearly visible, album-tinted edge. The default surface outline washes out against
    // arbitrary cover colours, so the card reads as borderless; this is the same 2px accent
    // language the art thumbnail and transport controls INSIDE these cards already use, so
    // the outline belongs to the same family rather than being a bare white line.
    border.width: root.frameWidth
    border.color: root.tintAccent
    Behavior on border.color { ColorAnimation { duration: Motion.spatial } }

    implicitWidth:  320
    implicitHeight: 148

    visible: root.player !== null

    // The card takes the cover's shadow as its fill. Falls back to the shell palette
    // when there's no art (AlbumArt handles that).
    color: root.tintBg
    Behavior on color { ColorAnimation { duration: Motion.spatial } }

    // Rows are absolutely positioned by index, so this and the glyph size move together —
    // raising the type without raising this would overlap the lines into each other.
    readonly property int lineHeight: 40

    // Everything resolves against the CORRECTED clock, never the raw one. `Lyrics.offset`
    // absorbs the slack no amount of matching can remove — player latency, the audio path,
    // and the fact that a lyric provider's timings are keyed to their master rather than
    // the one you happen to be streaming.
    readonly property real clock: root.position + Lyrics.offset

    readonly property int current: Lyrics.hasSynced ? Lyrics.lineAt(root.clock) : -1

    // Only line starts are real — no word or syllable timings. The glyphs light each
    // line whole rather than sweeping interpolated words (LyricGlyphs.wholeLine).
    readonly property bool lineOnly: Lyrics.kind === "line"

    // Why the card is empty, when it is. The rule lives in the service — see
    // Lyrics.blockedReason — because the lockscreen draws this same card and the settings
    // page answers the same question, and three copies of it would drift.
    readonly property string blocked:
        Lyrics.hasSynced || Lyrics.state === "plain" ? "" : Lyrics.blockedReason

    // ── Is there anything worth drawing? ─────────────────────────────────────
    // Synced or plain lyrics, or a load still in flight (kept so the card doesn't
    // blink out for the second it takes each track change to resolve). FALSE for
    // "no lyrics found", an instrumental, an error, or before anything is asked.
    //
    // A host with a fixed frame to fill — the desktop tile, the lock screen —
    // ignores this and shows `blocked` instead. A host that would rather the card
    // just not be there (the overview) binds its own `visible` to this.
    readonly property bool hasContent:
        root.player !== null
        && (Lyrics.hasSynced || Lyrics.state === "plain" || Lyrics.state === "loading")

    // ── Structure ─────────────────────────────────────────────────────────────
    // Computed ONCE per track, not per tick: it walks every line, and the answer only
    // changes when the lyrics do. Binding it to `Lyrics.lines` alone is what keeps it off
    // the position path.
    readonly property var struct: LyricMotion.structure(Lyrics.lines)

    // The measuring instance, used to height every line in the song for the scroll maths.
    // Same settings as the per-row ones, so both agree about where a line breaks.
    OverviewLyricLayout {
        id: measure
        width: root.availWidth
    }

    // The same, at the translation's smaller size. A translated line is prose rather than
    // a lyric — it runs longer than the line it stands for far more often than not — so it
    // WRAPS, and the row has to be told how tall that made it. Eliding instead was cutting
    // the end off the sentence, which is the one thing a translation must not do.
    OverviewLyricLayout {
        id: measureTr
        width: root.availWidth
        font.pixelSize: root.trFontSize
        font.bold: true
    }

    // And for backing vocals. Italic MUST match the rendered one: a single differing font
    // field wraps the text at a different point, so the height reserved is not the height
    // drawn — which is what put translations on top of the lines below them.
    OverviewLyricLayout {
        id: measureBg
        width: root.availWidth
        font.pixelSize: root.bgFontSize
        font.italic: true
    }

    // ── One definition of a line's text ───────────────────────────────────────
    // The layout pass and the row have to be looking at the SAME string, or the heights
    // will not match what is drawn. Both go through here.
    function unitsFor(line) {
        // Called from row bindings, which evaluate while a delegate is being built or torn
        // down — `line` is genuinely undefined for a frame there. Reading `.words` off it
        // throws, the binding fails, `words` resolves to undefined, and the next `.map()`
        // takes the whole row's text with it. That is the lyrics vanishing entirely.
        if (!line) return []

        const src = line.words

        if (src && src.length > 0) return LyricMotion.lineUnits(src)

        const raw = (line.text || "").split(" ").filter(w => w !== "")
        if (raw.length === 0) return []

        let chars = 0
        for (let i = 0; i < raw.length; i++) chars += raw[i].length
        if (chars === 0) return []

        const span = Math.max(0.2, (line.dur > 0 ? line.dur : 4))
        const out = []
        let seen = 0
        for (let i = 0; i < raw.length; i++) {
            out.push({
                text: raw[i] + (i < raw.length - 1 ? " " : ""),
                at:   line.t + (seen / chars) * span,
                d:    (raw[i].length / chars) * span
            })
            seen += raw[i].length
        }
        return out
    }

    // ── One definition of a lead line's height ────────────────────────────────
    // The layout pass and the block MUST agree. They disagreed twice: first when the block
    // used a lineHeight floor the pass did not, and before that when each measured a
    // different string. Both now call this, so a change to the floor cannot land on one
    // side only.
    //
    // The floor is 2, not lineHeight. A large floor is what pushed a translation away from
    // its own line; this exists only so a TextEdit that has not been laid out yet reports
    // something other than a literal zero.
    function leadHeight(contentHeight) {
        return Math.max(2, contentHeight)
    }

    // `i` is the line's index, for the romanization (index-aligned with Lyrics.lines): when
    // there is one, it IS the line's text — see romanUnitsFor.
    function textFor(line, i) {
        const r = root.romanUnitsFor(line, i)
        const u = r.length > 0 ? r : root.unitsFor(line)
        return u.map(x => x.text).join("")
    }

    // ── Backing vocals, in the SAME unit shape the lead uses ──────────────────
    // The source carries `t`; a glyph is animated off `at`. unitsFor() does that
    // translation for the lead, and the background was handed the raw list instead — so
    // every bg unit had `at === undefined`, and the failure was silent and total:
    //
    //     lit     = clock >= undefined            → false, forever
    //     sweep   = (clock - undefined) / d       → NaN, which passes BOTH clamps
    //     litness → NaN → Colors.mix(fg, accent, NaN) → an INVALID colour
    //
    // An invalid colour does not warn. It simply does not paint. So the row rendered
    // correctly while the line was still ahead (sweep short-circuits to 0 before `live`),
    // vanished the instant the line went live, and reappeared once `past` forced sweep to
    // 1 — "they unrender when their time comes, don't animate, then reappear".
    //
    // Fresh objects, never `base` stamped onto the service's own arrays: Lyrics.lines is
    // shared, and the bridge re-applies those same objects on an upgrade.
    function bgUnitsFor(line) {
        const src = line?.bg
        if (!src || src.length === 0) return []

        const out = []
        let base = 0
        for (const u of src) {
            const t = u.text || ""
            out.push({ text: t, at: u.t, d: u.d, base: base })
            base += t.length
        }
        return out
    }

    // What the pass measures and the row lays out — one string, for the same reason
    // textFor() exists. Two spellings of it is the shape that cost six rounds of clipping.
    function bgTextFor(line) {
        return root.bgUnitsFor(line).map(u => u.text).join("")
    }

    // Measured PER CHARACTER, then summed — not advanceWidth() of the whole string.
    //
    // Every glyph is its own StyledText, so the text is never shaped as a run: there is no
    // kerning between characters and no ligatures. advanceWidth("AV") accounts for the
    // kern that pulls those two together, which the card does not have, so the string
    // measurement came out NARROWER than what actually renders and the fit-scale let long
    // lines run off the edge. Summing single characters measures what is really drawn.
    //
    // Cost is a few hundred advanceWidth calls, recomputed when the visible window moves —
    // once per line, not per frame.
    // ── The type size is FIXED ────────────────────────────────────────────────
    // It used to scale each line to fit the card, which is why the size moved: first per
    // line, then per song once the measurement went song-wide. Nothing scales now — a line
    // too wide for the card WRAPS instead, which is the only way to hold one size and
    // still show every word.
    //
    // The cost is that rows are no longer a uniform height, so they can't be placed at
    // `index * lineHeight` any more. The pass below works out where each one actually
    // starts.
    readonly property real availWidth:
        Math.max(1, root.width - 2 * Tokens.spacingMd)

    // ── Where every row starts, and how tall it is ────────────────────────────
    // Background vocals sit on their own quieter row under the lead, so a line carrying
    // them is taller. Smaller type, so a smaller row.
    // ── Backing vocals are much smaller ───────────────────────────────────────
    // They were `fontTitle` against the lead's `fontHeadline` — 15 against 18, which is
    // not a hierarchy, it is a slightly different size. Caption against headline is a real
    // difference: unmistakably a second voice under the line rather than a second line.
    readonly property int bgFontSize: Tokens.fontCaption

    // The breath between a lead and the backing vocal under it — small, they are one
    // phrase. Heights come from the text itself now, not from an allowance.
    readonly property int bgGap: 2

    // ── The translated line ───────────────────────────────────────────────────
    // Sits under its original, smaller and lighter, so the pair reads as one line with a
    // gloss rather than as two competing lyrics. Only present when a translation actually
    // arrived — a row must not reserve height for a line that is not there.
    readonly property int trFontSize: Tokens.fontLabel

    // The breath between a lyric and its translation — small, because they are one thing.
    readonly property int trGap: 2

    // The breath between one lyric row and the next. This is what `lineHeight` used to
    // provide by padding every lead out to a fixed size, which is exactly what pushed
    // translations away from their own line.
    readonly property int rowGap: 14

    readonly property bool showTranslation:
        Config.lyricsTranslate && LyricsTranslate.hasLines

    // ── Translated words, with borrowed timings ───────────────────────────────
    // A translation has no timing of its own — it is one sentence standing for a whole
    // line — so the LINE's span is distributed across its words by length. That is the
    // same interpolation the line-only lyrics path already uses, and it is a guess in
    // exactly the same way: the words light left to right across the right stretch of
    // time, without claiming to know when each one is sung.
    //
    // Words, not syllables. Splitting a translation further would be inventing detail on
    // top of an interpolation, and at this size nobody could see it anyway.
    function translationUnits(i) { return root.spreadUnits(i, root.translationFor(i)) }

    // A sentence with no timing of its own, spread across line `i`'s span by word length.
    // Shared by the translation and the romanization — both are one line standing for a whole
    // lyric.
    function spreadUnits(i, text) {
        if (text === "") return []

        const line = Lyrics.lines[i]
        if (!line) return []

        const raw = text.split(" ").filter(w => w !== "")
        if (raw.length === 0) return []

        let chars = 0
        for (const w of raw) chars += w.length
        if (chars === 0) return []

        const span = Math.max(0.4, LyricMotion.lineEnd(line, Lyrics.lines[i + 1]) - line.t)

        const out = []
        let seen = 0
        let base = 0
        for (let k = 0; k < raw.length; k++) {
            const t = raw[k] + (k < raw.length - 1 ? " " : "")
            out.push({
                text: t,
                at:   line.t + (seen / chars) * span,
                d:    (raw[k].length / chars) * span,
                base: base
            })
            seen += raw[k].length
            base += t.length
        }
        return out
    }

    function translationFor(i) {
        if (!root.showTranslation) return ""
        const t = LyricsTranslate.lines
        if (i < 0 || i >= t.length) return ""

        const tr = t[i] || ""
        if (tr === "") return ""

        // ── Nothing to show for a line already in the target language ─────────
        // The service drops a whole track whose language matches, but a track is not all
        // one language: an English refrain inside a Japanese song comes back identical to
        // its original, and printing that underneath is a duplicate line pretending to be
        // a translation. Compared loosely, because a translator will happily return the
        // same words with different capitalisation or a stray full stop.
        const line = Lyrics.lines[i]
        const orig = line ? (line.text
                    || (line.words ? line.words.map(w => w.text).join("") : "")) : ""

        const norm = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "")
        if (norm(tr) === norm(orig)) return ""

        return tr
    }

    // ── The romanized line REPLACES the lyric ─────────────────────────────────
    // With romanization on, the lead shows "konnichiwa" where "こんにちは" was (LyricsRomanize):
    // same row, same animation, the Latin letters in place of the script. A line with no
    // romanization (an English refrain; one the romanizer left blank) keeps its own text.
    //
    // ── …on the original's SYLLABLES ──────────────────────────────────────────
    // The romanizer answers one string per line, and the voice has timing per syllable, so
    // romajialign.js pairs them: every romaji piece is lit by the syllable it came from, with that
    // syllable's own start and length — "osa" with 抑, "e" with え. It falls back to spreading the
    // words along the original's timeline (retimeWords) for a line it cannot place.
    //
    // One definition, called by the layout pass (textFor) AND by the row: they have to be
    // looking at the same string or the heights will not match what is drawn (the lesson of
    // unitsFor above).
    readonly property bool showRomanization: Config.lyricsRomanize && LyricsRomanize.hasLines

    function romanizationFor(i) {
        if (!root.showRomanization) return ""
        const t = LyricsRomanize.lines
        if (i < 0 || i >= t.length) return ""
        return t[i] || ""
    }

    // The lead's syllables as the row draws them: the provider's own where it has them, the
    // heuristic split otherwise (the row's `units` makes the same choice).
    function baseUnitsFor(line) {
        const w = root.unitsFor(line)
        return Lyrics.kind === "syllable" ? w : LyricMotion.syllabify(w)
    }

    function romanUnitsFor(line, i) {
        if (!line) return []
        const text = root.romanizationFor(i)
        if (text === "") return []
        const orig = root.baseUnitsFor(line)
        if (orig.length === 0) return []
        const r = RomajiAlign.align(text, orig, LyricsRomanize.script)
        return r.length > 0 ? r : LyricMotion.retimeWords(text, orig)
    }

    // ── COMPUTED, never bound ─────────────────────────────────────────────────
    // This was `readonly property var layout: { … }`, and it was a binding loop that made
    // the whole card unusable.
    //
    // The body ASSIGNS `measure.text` and then READS `measure.contentHeight`. Inside a
    // binding those are the same dependency: assigning the text changes the height, the
    // height invalidates the binding, the binding re-assigns the text. Qt caught it —
    // "Binding loop detected for property layout" — and kept re-running it forever, each
    // pass re-laying out every line in the song TWICE, lead and translation.
    //
    // That is what made everything else feel broken. A saturated event loop starves the
    // translate request, the IPC, the process handling and the frame clock alike, so the
    // symptom was never where the fault was.
    //
    // So it is a plain property filled by a function, recomputed when its real inputs
    // change. A measurement that mutates a shared measurer cannot live in a binding.
    property var layout: ({ tops: [], heights: [], total: 0 })

    // ── The dots are a row, and a row that is only there while it is sung ─────
    // A long silence is a row of its own in `Lyrics.lines` (lyricsmotion.js withInterludes), so
    // the view scrolls to the dots, they take the place a line would, and the line follows —
    // rather than one line scrolling to the next across a silence with a widget on top.
    //
    // Not visible in advance: an interlude row has NO height until it is the row being sung, so
    // the lines either side of it sit together while the line before is sung, and the dots open
    // up when their time comes (the next line moving down to make room) and close again when it
    // ends. `dotsOpen` is that opening, 0 → 1, eased; the row's height follows it each frame
    // (relayoutInterludes — arithmetic over the row tops only, no text is measured).
    readonly property int interludeHeight: Tokens.spacingXl * 2
    property int  dotsRow:  -1          // which interlude row is the one open (or closing)
    property real dotsOpen: 0
    property var  interludeIdx: []      // every interlude row's index, filled by rebuildLayout()
    Behavior on dotsOpen {
        NumberAnimation {
            duration: Motion.emphasized
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
        }
    }
    onDotsOpenChanged: root.relayoutInterludes()

    function interludeHeightFor(i) {
        return i === root.dotsRow ? (root.interludeHeight + root.rowGap) * root.dotsOpen : 0
    }

    // The dots open when the row being sung is an interlude, and close when it is not.
    function syncDots() {
        const l = Lyrics.lines[root.current]
        if (l && l.interlude) { root.dotsRow = root.current; root.dotsOpen = 1 }
        else                    root.dotsOpen = 0
    }
    onCurrentChanged: root.syncDots()

    function relayoutInterludes() {
        const idx = root.interludeIdx
        if (idx.length === 0) return
        const heights = root.layout.heights.slice()
        let changed = false
        for (const i of idx) {
            if (i >= heights.length) continue
            const want = root.interludeHeightFor(i)
            if (Math.abs(heights[i] - want) < 0.01) continue
            heights[i] = want
            changed = true
        }
        if (!changed) return
        const tops = []
        let y = 0
        for (let k = 0; k < heights.length; k++) { tops.push(y); y += heights[k] }
        root.layout = { tops: tops, heights: heights, total: y }
    }

    function rebuildLayout() {
        const tops = []
        const heights = []
        const interludes = []
        let y = 0

        for (const l of Lyrics.lines) {
            // An interlude takes only the room its opening has given it so far.
            if (l.interlude) {
                const ih = root.interludeHeightFor(tops.length)
                interludes.push(tops.length)
                tops.push(y)
                heights.push(ih)
                y += ih
                continue
            }

            measure.text = root.textFor(l, tops.length)

            // ── Content height plus ONE explicit gap ──────────────────────────
            // The lead used to be padded out to a fixed lineHeight, which put 16px of
            // nothing between a lyric and its own translation while leaving the row too
            // short for both — so the translation sat far from its line and ran into the
            // next one. Each part is now its true height and `rowGap` is the only spacing,
            // which is what makes a translation PUSH the rest down rather than overlap it.
            let h = measure.text === "" ? root.lineHeight
                                        : root.leadHeight(measure.contentHeight)
            // Gated on the TEXT, not on the unit count, because that is what bgBlock's own
            // `visible` is gated on. An empty TextEdit still reports a full line of
            // contentHeight, so a bg list of blank units would draw a row the pass had
            // reserved nothing for.
            const bgText = root.bgTextFor(l)
            if (bgText !== "") {
                measureBg.text = bgText
                h += root.bgGap + measureBg.contentHeight
            }

            // A translated line makes the row taller, so it has to be counted HERE. Adding
            // it only at render time is how a row ends up overlapping the one below it.
            //
            // Measured rather than assumed a single row tall: translations wrap, and a
            // fixed allowance is exactly what was cutting the long ones off.
            const tr = root.translationFor(tops.length)
            if (tr !== "") {
                measureTr.text = tr
                h += root.trGap + measureTr.contentHeight
            }

            // The rhythm between one lyric and the next. Applied once, at the end, so a
            // row carrying a backing vocal and a translation still has exactly one gap
            // after it rather than three.
            h += root.rowGap

            tops.push(y)
            heights.push(h)
            y += h
        }
        root.interludeIdx = interludes
        root.layout = { tops: tops, heights: heights, total: y }

        // The text changed, so every reported height describes lines that are no longer
        // there. Keeping them would pin the new song's rows to the old one's wrapping.
        root._drawn = ({})
    }

    // The real inputs, named explicitly. A binding would have found these itself — and
    // would also have found `measure.contentHeight`, which is the one that must not be a
    // dependency.
    onAvailWidthChanged: root.rebuildLayout()

    Connections {
        target: Lyrics
        function onLinesChanged() { root.rebuildLayout(); root.syncDots() }
        function onStateChanged() { root.rebuildLayout() }
    }

    // ── Both signals, because they do not arrive together ─────────────────────
    // The service assigns `lines` and then `state`, so onLinesChanged fires while state is
    // still "loading" — at which point hasLines is false, translationFor() returns nothing
    // and the pass reserves NO height for the translations. A moment later state becomes
    // "ready", the rows start drawing them, and they have nowhere to go: they overlap the
    // line below and get clipped.
    //
    // Listening to the state as well means the last of the two always triggers a rebuild,
    // whichever order they land in.
    Connections {
        target: LyricsTranslate
        function onLinesChanged() { root.rebuildLayout() }
        function onStateChanged() { root.rebuildLayout() }
    }

    // Both signals, for the same reason as the translation's: `lines` and `state` do not land
    // together, and the pass must see the last of them.
    Connections {
        target: LyricsRomanize
        function onLinesChanged() { root.rebuildLayout() }
        function onStateChanged() { root.rebuildLayout() }
    }

    Connections {
        target: Config
        function onLyricsRomanizeChanged()      { root.rebuildLayout() }
        function onLyricsTranslateChanged()     { root.rebuildLayout() }
        function onLyricsTranslateLangChanged() { root.rebuildLayout() }
        function onFontFamilyChanged()          { root.rebuildLayout() }
        function onFontScaleChanged()           { root.rebuildLayout() }
    }

    // ── The RENDERED row is the authority ─────────────────────────────────────
    // Seven rounds of "it is still clipping" were all one thing: the pass estimates a row's
    // height with the shared measurers, the row draws with its own, and the two are only
    // ever compared on screen — where four pixels of disagreement looks like a font
    // problem. Each round found a real divergence (a second word-builder, a missing font
    // field, a floor on one side, a fixed allowance) and each fix left the NEXT one
    // waiting, because the design has two sources of truth and only one of them is real.
    //
    // So the estimate is now only used for rows that do not exist yet. The moment a row is
    // built it reports what it actually occupies and the layout adopts that number. A row
    // enters the window three lines before it is sung, so it has corrected itself long
    // before anyone is looking at it.
    //
    // ── Why this cannot loop ──────────────────────────────────────────────────
    // The obvious objection is that heights feed positions feed heights. They do not: a
    // row's blocks are anchored to each other and sized from their own content at
    // `parent.width`, so `drawn` depends on the row's WIDTH and its text — never on
    // `rowHeight(i)` or `rowTop(i)`. Adopting the reported height changes where rows sit
    // and changes nothing about what any of them measured. (`layout` is a plain property
    // for the same family of reasons — see rebuildLayout().)
    property var _drawn: ({})
    property bool _correctionQueued: false

    function reportRow(i, drawn) {
        if (drawn <= 0) return                       // not laid out yet
        if (Lyrics.lines[i]?.interlude) return       // its height is dotsOpen's, not its content's
        if (root._drawn[i] === drawn) return
        root._drawn[i] = drawn

        if (Math.abs(root.rowHeight(i) - root.rowGap - drawn) < 0.5) return
        if (root._correctionQueued) return

        // Coalesced: a track change re-measures every visible row in the same frame, and
        // rebuilding the strip once per row would be eight passes over the whole song.
        root._correctionQueued = true
        Qt.callLater(root.applyCorrections)
    }

    function applyCorrections() {
        root._correctionQueued = false

        const heights = root.layout.heights.slice()
        if (heights.length === 0) return

        let changed = false
        for (const k in root._drawn) {
            const i = Number(k)
            if (!(i >= 0 && i < heights.length)) continue
            if (Lyrics.lines[i]?.interlude) continue
            const h = root._drawn[k] + root.rowGap
            if (Math.abs(heights[i] - h) < 0.5) continue
            heights[i] = h
            changed = true
        }
        if (!changed) return

        const tops = []
        let y = 0
        for (let i = 0; i < heights.length; i++) { tops.push(y); y += heights[i] }
        root.layout = { tops: tops, heights: heights, total: y }
    }

    function rowTop(i) {
        const t = root.layout.tops
        return (i >= 0 && i < t.length) ? t[i] : i * root.lineHeight
    }
    function rowHeight(i) {
        const h = root.layout.heights
        return (i >= 0 && i < h.length) ? h[i] : root.lineHeight
    }

    // ── The wave ──────────────────────────────────────────────────────────────
    // ONE animator for the whole card, not one per letter. Every lit letter reads its
    // offset off this single running phase, so they move as one travelling wave instead of
    // N independent bobs that happen to be near each other. It also means the effect costs
    // one animation regardless of how many letters are on screen.
    property real wavePhase: 0

    NumberAnimation on wavePhase {
        // Gated on someone actually LOOKING at the card, not merely on a player existing.
        // `root.visible` is true whenever something is playing — so gating on that would
        // leave this animator running forever behind a closed overlay, which is precisely
        // the mistake the bar's MediaController had to be fixed for.
        //
        // `active` rather than UiState.overviewOpen directly, for the same reason the
        // media card grew one: the lockscreen draws this card too, and there the overlay
        // is by definition closed — the wave would never run and the lyrics would sit
        // dead on a surface where they are the most alive thing on screen.
        // ── Category 2: ambient, gated by not running (see Motion.qml) ────────
        // 2200ms is a designed tempo, not a transition — scaling it by a motion
        // preference would retune the song's wave rather than speed up a UI. So the
        // duration stays literal and `Config.motionEnabled` is honoured here, which
        // it previously wasn't: with animations off the wave kept travelling.
        running: Config.motionEnabled && root.active && Lyrics.hasSynced
        loops: Animation.Infinite
        from: 0
        to: 2 * Math.PI
        duration: 2200

        // Stopping is not resetting. Every lit letter reads its bob offset off
        // `wavePhase`, so a stopped animator leaves the phase frozen at whatever it
        // held — the letters would sit permanently displaced rather than at rest,
        // which looks like a layout bug rather than like motion being off. Put it
        // back to zero, which is the neutral phase every letter is drawn at.
        onRunningChanged: if (!running) root.wavePhase = 0
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
    //
    // The SOURCE is part of the key: a browser tab can go from a song on YouTube Music to
    // a YouTube video without the player object changing, and `sourceBlocked` has to be
    // re-asked then, not at the next title change.
    readonly property string _track:
        (root.player?.trackTitle  ?? "") + "::" +
        (root.player?.trackArtist ?? "") + "::" +
        (root.player?.trackAlbum  ?? "") + "::" +
        SpotifyBridge.trackUri + "::" +
        MediaSource.idOf(root.player)

    // ── Sources whose metadata a lyrics lookup can't trust ────────────────────
    // YouTube hands MPRIS a VIDEO title with the channel as the artist, so the lookup
    // either misses or matches a different song and scrolls confident wrong words in time
    // with your music. The rule is mediasource.js `lyricsTrusted` — the media panel asks
    // it too and hides its lyrics page outright. Here the card is on a fixed frame (the
    // desktop tile, the lock screen), so it stays and says why instead.
    readonly property bool sourceBlocked:
        root.player !== null && !MediaSource.lyricsTrusted(root.player)

    // ── Prefer Spotify's own metadata over MPRIS's ────────────────────────────
    // Not for the URI alone. MPRIS metadata is whatever the app chose to publish, and the
    // lookup is only as good as the strings it searches on; the bridge reports the fields
    // Spotify itself holds for the track. Same song, cleaner query — and the URI on top of
    // it makes the request's identity exact rather than a tuple two recordings can share.
    //
    // Gated on `desktopEntry`, not on the mediasource.js host table: the bridge is a
    // Spicetify extension living inside the Spotify DESKTOP app, so the browser cases that
    // table exists to disambiguate can't produce a bridge anchor in the first place.
    // mediasource.js records that the real app reports desktopEntry "spotify".
    // `available` covers Spotify having quit without saying so.
    readonly property bool _bridged:
        (root.player?.desktopEntry ?? "") === "spotify" && SpotifyBridge.available

    // ── Nothing to read ───────────────────────────────────────────────────────
    // When there is nothing to read the card shows the player's mark and why (`emptyCard`).
    // The spectrum that used to fill this state — and the cava stream it held for the
    // player's own PipeWire node — went on 2026-10-31 with the rest of that "second phase".
    readonly property bool emptyShown:
        root.player !== null && !Lyrics.hasSynced && Lyrics.state !== "plain" && !root.sourceBlocked

    // For a host that holds its playhead re-read off during a drag (MediaPosition.scrubbing):
    // the card has no seek bar of its own any more, so it never scrubs.
    readonly property bool scrubbing: false

    // The request itself is the service's (Lyrics.loadFor): the karaoke module asks the same way.
    function _reload() {
        if (root.player) Lyrics.loadFor(root.player)
    }

    on_TrackChanged: _reload()
    onPlayerChanged: _reload()
    // Both of the card's start-up jobs, in ONE handler: a signal may be handled only once
    // per object, and a second `Component.onCompleted` is a hard load failure rather than
    // an addition.
    Component.onCompleted: {
        root.rebuildLayout()
        root._reload()
    }

    // ── Ask for a translation once the lyrics themselves have landed ──────────
    // Keyed to `Lyrics.lines` rather than to the track, because the lines are what gets
    // translated and they arrive after the track change — sometimes well after, when the
    // bridge upgrades a fallback answer mid-song. Requesting on the track change alone
    // would translate whichever set happened to be in hand at that instant.
    //
    // The service deduplicates by key, so an unchanged set costs nothing, and a repeat of
    // a track played this week is answered from the script's disk cache.
    function _requestTranslation() {
        if (!Config.lyricsTranslate) { LyricsTranslate.load("", []); return }
        if (!Lyrics.hasSynced)       { LyricsTranslate.load("", []); return }

        const texts = Lyrics.lines.map(l =>
            l.text || (l.words ? l.words.map(w => w.text).join("") : ""))

        // ── A HASH of the lines, not the provider and not the words ───────────
        // Two things were wrong with keying on source/provider plus the opening line.
        //
        // First, the provider CHANGES mid-track: the bridge upgrades a fallback answer
        // seconds after the song starts, so the key changed, the cache missed, and the
        // track was translated a second time — replacing what was already on screen.
        // Identical lines now produce an identical key whoever supplied them.
        //
        // Second, it carried a slice of the lyric itself, which then surfaced in the
        // diagnostics. A key needs to be stable and unique; it does not need to be
        // readable, and the words have no business in a log.
        let h = 0
        for (const line of texts) {
            for (let i = 0; i < line.length; i++)
                h = (Math.imul(31, h) + line.charCodeAt(i)) | 0
        }
        // ── The TARGET LANGUAGE is part of the identity ───────────────────────
        // Without it, changing the language did nothing until the next track: the key was
        // unchanged, the service deduplicated against it and returned immediately, and the
        // previous language stayed on screen. The script's own disk cache always keyed on
        // the language pair, so only this side was wrong — and it failed in the direction
        // that reads as the setting being ignored.
        const key = texts.length + "-" + (h >>> 0).toString(36)
                  + "-" + LyricsTranslate.target

        LyricsTranslate.load(key, texts)
    }

    // The same for the romanization: asked for once the lyrics have landed, keyed on what
    // they say, answered once per track by the service.
    function _requestRomanization() {
        if (!Config.lyricsRomanize || !Lyrics.hasSynced || !LyricsRomanize.romanizable) {
            LyricsRomanize.load("", [])
            return
        }
        const texts = LyricsRomanize.texts
        let h = 0
        for (const line of texts) {
            for (let i = 0; i < line.length; i++)
                h = (Math.imul(31, h) + line.charCodeAt(i)) | 0
        }
        LyricsRomanize.load(texts.length + "-" + (h >>> 0).toString(36), texts)
    }

    // Both signals, for the same reason the layout pass watches both: a request that is
    // dropped because the state had not settled yet is never retried, and nothing else
    // changes afterwards to trigger one. The service deduplicates by key, so the extra
    // call on the second signal costs a string comparison.
    // Deferred rather than called inline: `state` and `lines` are two separate property
    // assignments inside Lyrics._apply(), so a track change fires this TWICE in the same
    // tick — once right after `state` flips (with `lines` still the OLD track's, since
    // that assignment hasn't run yet) and once after `lines` catches up. The first call
    // requests a translation keyed on stale content; usually a harmless no-op, but it can
    // leave LyricsTranslate holding the wrong key for a moment. `Qt.callLater` coalesces
    // both into a single evaluation per settle, run only once every property it reads is
    // final.
    Connections {
        target: Lyrics
        function onLinesChanged() { Qt.callLater(root._requestTranslation); Qt.callLater(root._requestRomanization) }
        function onStateChanged() { Qt.callLater(root._requestTranslation); Qt.callLater(root._requestRomanization) }
    }

    Connections {
        target: Config
        function onLyricsTranslateChanged()     { root._requestTranslation() }
        function onLyricsRomanizeChanged()      { root._requestRomanization() }
        // Changing the language is a new request, not a new track. Nothing else fires
        // here — the lyrics have not moved — so without this the setting only took effect
        // on the next song.
        function onLyricsTranslateLangChanged() { root._requestTranslation() }
    }

    // ── The drifting field ────────────────────────────────────────────────────
    // The alternative background. Gated on `active` as well as on the style: four animated
    // items under a blur pass is real per-frame work, and behind a closed overlay or a
    // covered desktop it must cost nothing.
    SpicyFlow {
        anchors.fill: parent
        anchors.margins: 0
        visible: root.artWash && root.washStyle === "flow"
        running: visible && root.active

        // The cover itself, not colours taken from it. Same URL the "cover" wash uses,
        // so the two styles are two treatments of one picture rather than two sources.
        source: root.player?.trackArtUrl ?? ""
        base:   root.tintBg

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // ══ Cover wash ════════════════════════════════════════════════════════════
    // The blurred cover over the card's fill, so the surface is the album's colour
    // rather than a flat block of it.
    Item {
        anchors.fill: parent
        visible: root.artWash && root.washStyle === "cover"
                 && bgArt.status === Image.Ready

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

            // ── A BLUR source, so it is capped ────────────────────────────
            // 320 to match SpicyFlow's art copies, which is not a coincidence: the
            // "flow" and "cover" washes are two treatments of THE SAME cover, so
            // they should hold it at the same size.
            //
            // Nothing here survives the blur below (blurMax 56 at this card's
            // size), so decoding at native resolution buys no detail — it only
            // holds the full cover in memory, and makes the blur pass chew through
            // a texture that many times larger. `trackArtUrl` is 640px from Spotify
            // but whatever is embedded in a local file otherwise, which is regularly
            // 1500px or more.
            //
            // A literal, not a size binding: bound to width/height this re-decodes
            // on every frame of a card resize.
            sourceSize: Qt.size(320, 320)
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
        id: content
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // ── Synced ────────────────────────────────────────────────────────────
        OverviewLyricsSynced {
            id: viewport
            lyrics: root
        }

        // ── Soft edges ────────────────────────────────────────────────────────
        // Over the viewport, not inside it: the viewport clips rectangularly (for input),
        // and these only change what you SEE of the rows it clips.
        readonly property real _fadeH: root.lineHeight * 0.9
        Rectangle {
            visible: root.edgeFade && Lyrics.hasSynced
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: viewport.top
            height: content._fadeH
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.92) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0) }
            }
        }
        Rectangle {
            visible: root.edgeFade && Lyrics.hasSynced
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: viewport.bottom
            height: content._fadeH
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.92) }
            }
        }

        // ── The track card ────────────────────────────────────────────────────
        // Which song this is, said once and then left alone. It shows for a few seconds
        // when lyrics for a new song land and again whenever the pointer is on the tile;
        // the rest of the time the lyrics have the whole card.
        //
        // `_announce` is armed by a track change and spent by the first lyrics that arrive
        // for it — not by the change itself, because lyrics land a beat after the title
        // does and a card timed from the change would be mostly gone by then. A later
        // upgrade of the same song's lyrics (fallback → bridge) finds it already spent and
        // stays quiet.
        property bool _announce: false
        property bool _pending: false
        Connections {
            target: root
            function on_TrackChanged() { content._pending = true }
        }
        Connections {
            target: Lyrics
            function onLinesChanged() {
                if (!content._pending || !Lyrics.hasSynced) return
                content._pending = false
                content._announce = true
                announceTimer.restart()
            }
        }
        Timer { id: announceTimer; interval: 3800; onTriggered: content._announce = false }

        OverviewLyricsTrackCard {
            id: trackCard
            lyrics: root
        }

        // How far through the song: a hairline, live (it follows the playhead, so it is
        // not eased — an eased bar lags the lyrics it sits under).
        Rectangle {
            readonly property real len: root.player?.length ?? 0
            visible: root._trackOn && len > 0
            z: 3
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: Colors.of(QsWindow.window).alpha(root.tintFg, 0.10)
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, root.position / parent.len))
                color: root.tintAccent
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
                color: root.tintFgMuted
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
        }

        // ── A video, not a song ───────────────────────────────────────────────
        // YouTube has no lyrics to find (see `sourceBlocked`), and an apology is a poor use
        // of the tile — so it becomes what is actually there: the video, as a poster that
        // fills the whole card. The thumbnail runs edge to edge (the card's own rounded
        // mask trims it), the source's mark sits in the corner, the title and channel sit
        // on a scrim along the bottom, and a play / pause control floats in the middle.
        //
        // The mark is the brand glyph in the brand's own red, from the same table the media
        // panel reads (AlbumArt.brandOf) — Material Symbols has no YouTube logo, which is
        // why it is a glyph and not an icon name.
        OverviewLyricsVideoCard {
            id: videoCard
            lyrics: root
        }

        // ── Nothing to read ───────────────────────────────────────────────────
        // The player's mark — Spotify's logo for Spotify, a note for anything else — and one
        // line saying why (2026-10-31, the user: no spectrum, track and seek bar any more,
        // "just make it show spotify's logo and a message like, Instrumental or Unable to
        // fetch Lyrics"). Still looking reads as still looking, so a track change that is
        // about to find its lyrics doesn't announce a failure first.
        OverviewLyricsEmptyCard {
            id: emptyCard
            lyrics: root
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
        spacing: Tokens.spacingXs
        z: 20

        visible: opacity > 0.01
        opacity: (cardHover.hovered && Lyrics.hasSynced) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        PanelButton {
            variant: "ghost"
            implicitWidth:  20
            implicitHeight: 20
            glyph: "󰍴"
            glyphTint: root.tintFgMuted
            accent: root.tintAccent
            onActivated: Lyrics.nudge(-0.1)
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            horizontalAlignment: Text.AlignHCenter
            text: (Lyrics.offset > 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s"
            variant: "caption"
            font.family: Tokens.fontMono
            color: Lyrics.offset === 0 ? root.tintFgDim : root.tintAccent

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
            glyphTint: root.tintFgMuted
            accent: root.tintAccent
            onActivated: Lyrics.nudge(0.1)
        }
    }

    // ── Resync ────────────────────────────────────────────────────────────────
    // Appears once the wheel has taken the lyrics off the playing line.
    PanelButton {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.margins: Tokens.spacingSm
        z: 20
        symbol: "my_location"
        label: Translation.tr("Resync")
        variant: "ghost"
        glyphTint: root.tintFgMuted
        accent: root.tintAccent
        visible: opacity > 0.01
        opacity: (viewport.browsing && Lyrics.hasSynced) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        onActivated: viewport.browsing = false
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
