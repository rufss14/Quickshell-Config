import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/lyricsmotion.js" as LyricMotion

// ── LyricGlyphs ───────────────────────────────────────────────────────────────
// One line's worth of animated letters, placed at the coordinates a LyricLayout reports.
//
// Extracted because the card draws TWO of these per line: the lead vocal, and the quieter
// backing line beneath it. They differ only in size, colour and how much they move — all
// of which are properties here — so a second copy would have been the same eighty lines
// with three numbers changed, and the two would have drifted the first time either was
// touched.
//
// ── It does not lay anything out ──────────────────────────────────────────────
// `lay` already holds the answer. Every glyph reads positionToRectangle() for its own
// character index and puts itself there, so wrapping, mixed scripts, font fallback and a
// right-aligned duet line are all inherited rather than recomputed. Nothing in this file
// measures text; that was the mistake this design replaced.
//
// The font comes from `lay` for the same reason: glyphs drawn in a face the layout did
// not use would sit at coordinates describing a layout that is not on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: glyphs

    // The laid-out line these letters belong to. Supplies both the positions and the font.
    required property var lay

    // [{ text, at, d, base }] — syllables, with `base` the character offset of each within
    // the line. `base` is what keeps the travelling wave continuous across the whole line
    // instead of restarting at every unit.
    required property var units

    // Is the vocal inside this line right now, and has it finished?
    required property bool live
    required property bool past

    // The card's corrected playhead, and the one shared wave animator every letter reads
    // its phase from. Passed in rather than reached for through `lay` — a layout element
    // has no business carrying the clock, and hanging unrelated state off it is how two
    // things that must agree end up disagreeing.
    required property real clock
    required property real wavePhase

    // How far from the line being sung, for the resting opacity of everything else.
    property int distance: 0

    property color fg:     AlbumArt.fg
    property color accent: AlbumArt.accent

    // Backing vocals move less and sit quieter — they are secondary by definition, and two
    // equally lively lines would split the eye between them.
    property real motionScale: 1.0
    property real dim: 1.0

    // Light the whole line the moment it starts, with no sweep. For line-only timing,
    // where every unit's `at` is an interpolation: a sweep there claims to know when
    // each word is sung and visibly runs ahead of or behind the vocal. The line's own
    // start IS real, so that is the only moment this draws.
    property bool wholeLine: false

    // ── Heavier letters, for a face with no heavier weight ────────────────────
    // The lyrics face may stop at Bold (the default family does: Regular and Bold only), so
    // asking for ExtraBold changes nothing. Every letter is drawn a second time half a pixel
    // across instead, which thickens each stroke by about that much — a little, which is the
    // point. Two draws at the same opacity would stack (a line at 30% would read as 51%), so
    // each is drawn at the opacity that makes the PAIR come to the intended one:
    // 1 − √(1 − α). Off for the backing line and the translation, which are small and
    // quiet and would only clot.
    property bool embolden: false
    readonly property real emboldenOffset: 0.5

    // The share of the light that reaches a letter ahead of and behind the head of the sweep
    // — its brightest stretch. Wider and brighter than it was, so the pass of the vocal
    // reads as a flash and not as a tint.
    readonly property real glintWidth: 0.38
    readonly property real glintLift:  2.3

    // Resting opacity for a line that is not the one being sung.
    function _restOpacity() {
        return glyphs.distance === 1 ? 0.52
             : glyphs.distance === 2 ? 0.30
             : 0.15
    }

    Repeater {
        model: glyphs.units

        // One item per SYLLABLE, holding one per LETTER. A plain Item, deliberately NOT a
        // positioner: each glyph places itself where Qt said, so anything laying them out
        // here would be fighting the engine.
        Item {
            id: word

            required property var modelData
            anchors.fill: parent

            // Lit once the vocal reaches this unit. A finished line is wholly lit — it has
            // been sung.
            readonly property bool lit:
                glyphs.past || (glyphs.live && (glyphs.wholeLine || glyphs.clock >= modelData.at))

            // ── Sweep position ────────────────────────────────────────────────
            // How far the vocal is THROUGH this syllable, 0 → 1. The travelling light
            // rides this: each glyph lights as the value passes its own place in the unit,
            // so the highlight crosses the text rather than switching it on at once.
            //
            // Before the unit it is 0, after it 1 — a finished line is uniformly lit with
            // no residual gradient left behind.
            // ── The clamp must survive NaN, and that is not paranoia ──────────
            // `p < 0 ? 0 : (p > 1 ? 1 : p)` passes NaN through UNCHANGED — both
            // comparisons are false. NaN then reaches litness, reaches
            // Colors.mix(fg, accent, NaN), and produces an INVALID colour, which Qt
            // paints as nothing and says nothing about. That is how a bg unit missing
            // its `at` field made the whole backing row disappear for exactly the
            // seconds it was being sung.
            //
            // Ordering the test the other way round means anything non-finite lands on
            // 0: the line renders unlit and static, which is wrong but VISIBLE, and a
            // visible wrong thing can be reported. It is not a substitute for the units
            // carrying `at` — see bgUnitsFor() — it is a floor under how badly that can
            // fail.
            readonly property real sweep: {
                if (glyphs.past) return 1
                if (!glyphs.live) return 0
                if (glyphs.wholeLine) return 1    // eased in by accentFade, not swept
                const d = modelData.d > 0 ? modelData.d : 0.18
                const p = (glyphs.clock - modelData.at) / d
                return p > 0 ? (p > 1 ? 1 : p) : 0
            }

            // Derived from the syllable's OWN duration, so a held vowel swells and a
            // clipped consonant snaps.
            readonly property var motion:
                LyricMotion.wordMotion(modelData.d,
                                       Config.lyricsMotion * glyphs.motionScale)

            readonly property int letterBase: word.modelData.base ?? 0

            Repeater {
                model: word.modelData.text.length

                StyledText {
                    id: glyph
                    required property int index

                    readonly property int seq: word.letterBase + glyph.index

                    text: word.modelData.text.charAt(glyph.index)

                    // ── Placed where Qt put it ────────────────────────────────
                    // The one expression that replaced all the measuring, wrapping and
                    // alignment this card used to do itself.
                    //
                    // Re-read when the text or the column width changes — those move the
                    // layout, and neither is visible to the function call on its own.
                    // ── Guarded, and that guard is load-bearing ───────────────
                    // The glyphs and the layout do not change in the same instant. When a
                    // line's text is replaced — a track change, a translation arriving —
                    // these items still hold indices from the OLD text for a frame while
                    // the TextEdit already holds the new one.
                    //
                    // Asking for an out-of-range position is not fatal, which is why it
                    // went unnoticed: Qt just logs "QTextCursor::setPosition: Position N
                    // out of range". But it logs it PER GLYPH, PER FRAME — roughly eight
                    // rows of thirty letters at sixty frames a second, each one a
                    // formatted write to stderr. That flood was the "extremely slow": tens
                    // of thousands of syscalls a second, doing nothing.
                    readonly property rect box: {
                        const _dep = glyphs.lay.width
                        // `glyphs.lay.length`, not `.text.length` — the STRING property can
                        // already report the new text for a frame before the TextEdit's own
                        // QTextDocument has finished re-laying it out (the exact staleness
                        // this guard exists for). `.length` reads the document's actual
                        // character count, which is what positionToRectangle()'s valid range
                        // is bounded by, so it can't go stale ahead of the thing it's guarding.
                        if (glyph.seq < 0 || glyph.seq >= glyphs.lay.length)
                            return Qt.rect(0, 0, 0, 0)
                        return glyphs.lay.positionToRectangle(glyph.seq)
                    }

                    x: glyph.box.x

                    // The engine says where the glyph BELONGS; the wave is an offset from
                    // there. ONE assignment — `y:` written twice is
                    // "Property value set multiple times", a hard load failure of the whole
                    // file and invisible to a parse check.
                    y: glyph.box.y
                       - word.motion.rise * glyph.waveAmp
                         * Math.sin(glyphs.wavePhase - glyph.seq * 0.32)

                    // Typed exactly as the layout was, or the positions describe a layout
                    // that is not the one on screen.
                    font: glyphs.lay.font

                    // ── Where the light is ────────────────────────────────────
                    readonly property real place:
                        word.modelData.text.length > 1
                            ? glyph.index / (word.modelData.text.length - 1)
                            : 0

                    readonly property real edge: 0.45

                    readonly property real litness: {
                        // The head runs from BEFORE the first glyph to AFTER the last.
                        // Starting it AT the first glyph lit that letter the instant the
                        // unit opened, so every word's first letter ran ahead of the vocal.
                        const head = -glyph.edge + word.sweep * (1 + 2 * glyph.edge)
                        const t = (head - glyph.place) / glyph.edge
                        return t < 0 ? 0 : (t > 1 ? 1 : t)
                    }

                    // A bright band riding the head of the sweep. `litness` alone only says
                    // a letter HAS been reached, which settles flat and reads as a fill
                    // bar; the peak is what makes a word look lit from a source passing
                    // over it.
                    readonly property real glint: {
                        if (!glyphs.live) return 0
                        const head = -glyph.edge + word.sweep * (1 + 2 * glyph.edge)
                        const dist = Math.abs(head - glyph.place)
                        if (dist >= glyphs.glintWidth) return 0
                        return 1 - dist / glyphs.glintWidth
                    }

                    // ── The accent leaves SLOWLY ──────────────────────────────
                    // Colour and opacity both used to branch hard on `live`, so the moment
                    // a line finished every letter dropped back to plain in one frame —
                    // the whole line switching off at once, right as the eye was still on
                    // it. This is the crossfade instead.
                    //
                    // It cannot simply be a Behavior on the colour: `litness` is recomputed
                    // every frame to drive the sweep, and easing that would make the
                    // travelling light lag the vocal. So the per-frame part stays
                    // un-eased and only the LIVE↔RESTING blend is animated.
                    //
                    // Asymmetric on purpose, same as the wave envelope: the accent arrives
                    // with the vocal and has to be immediate, then takes its time going.
                    readonly property int accentRelease: 1500

                    property real accentFade: glyphs.live ? 1 : 0
                    Behavior on accentFade {
                        NumberAnimation {
                            duration: glyph.accentFade > 0 ? Motion.standard
                                                           : glyph.accentRelease
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.emphasizedDecel
                        }
                    }

                    // What the letter looks like at full attention: swept colour, with the
                    // glint riding over the top of it.
                    readonly property color litColour:
                        Colors.of(QsWindow.window).mix(
                            Colors.of(QsWindow.window).mix(glyphs.fg, glyphs.accent, glyph.litness),
                            Qt.lighter(glyphs.accent, glyphs.glintLift),
                            // Pushed toward full a little sooner than linear, so the flash has a
                            // body (a triangle's tip alone is brief) without a harder peak.
                            Math.min(1, glyph.glint * 1.35))

                    color: Colors.of(QsWindow.window).mix(glyphs.fg, glyph.litColour, glyph.accentFade)

                    readonly property real liveOpacity: 0.42 + 0.58 * glyph.litness
                    readonly property real restOpacity:
                        glyphs.past ? 0.52 : glyphs._restOpacity()

                    readonly property real intendedOpacity: glyphs.dim
                           * (glyph.restOpacity
                              + (glyph.liveOpacity - glyph.restOpacity) * glyph.accentFade)
                    // Each of the two draws of an emboldened letter (see `embolden`).
                    opacity: glyphs.embolden ? 1 - Math.sqrt(Math.max(0, 1 - glyph.intendedOpacity))
                                             : glyph.intendedOpacity

                    // ── The wave, with an envelope ────────────────────────────
                    // Fades the oscillation IN as a word is sung and OUT as its line
                    // passes. Without it `y` jumped from wherever the sine happened to be
                    // straight to rest the moment the line stopped being live — a hard
                    // snap, mid-swing, on every letter at once.
                    //
                    // NOT readonly: a Behavior animates a property by WRITING to it.
                    property real waveAmp:
                        (glyphs.live && word.lit) ? word.motion.waveGain : 0

                    // Attack and release are the syllable's own. A short one must be lit
                    // almost at once or it is over before the animation arrives; a held one
                    // can afford to swell.
                    Behavior on waveAmp {
                        NumberAnimation {
                            duration: glyph.waveAmp > 0 ? word.motion.attack
                                                        : word.motion.release
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.emphasizedDecel
                        }
                    }

                    // The idle↔live STEP is eased on its own property. A Behavior on
                    // `scale` would also ease the glint and the wave — both recomputed
                    // every frame — so the flare would trail the vocal instead of landing
                    // on it.
                    property real lineScale: glyphs.live ? 1.0 : 0.95
                    Behavior on lineScale {
                        NumberAnimation { duration: Motion.standard }
                    }

                    scale: glyph.lineScale
                         + word.motion.pop * glyph.waveAmp
                         + 0.05 * glyph.glint
                    transformOrigin: Item.Bottom

                    // The second draw of an emboldened letter. A child, so it moves, scales
                    // and fades with its parent, and carries the parent's opacity as its own
                    // (the pair is what `opacity` above is computed for).
                    StyledText {
                        visible: glyphs.embolden
                        x: glyphs.emboldenOffset
                        text: glyph.text
                        font: glyph.font
                        color: glyph.color
                    }

                    // No Behaviors on colour or opacity: both are driven by `litness`,
                    // already a smooth per-frame ramp. Easing an easing curve just makes
                    // the light lag the vocal.
                }
            }
        }
    }
}
