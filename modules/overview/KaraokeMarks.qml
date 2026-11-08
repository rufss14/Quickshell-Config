import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../services/karaoke.js" as KJ

// ── KaraokeMarks ──────────────────────────────────────────────────────────────
// The words you have sung, marked in the lyrics card: a thin underline beneath each one the
// recogniser heard (services/Karaoke). An OVERLAY on the line's own text layout rather than a
// change to the letters — LyricGlyphs animates every glyph per frame and is the wrong place to
// be clever — placed from the same positionToRectangle() every glyph reads, so a mark sits
// under the word whatever the wrap, the script or the font.
//
// EVERY line you have sung, not only the one being sung: the marks are read from the service's
// memory of the song (`Karaoke.sung`, keyed by line), and they STAY — through a line change, a
// seek, the clock stepping back, Karaoke being switched off — until a different song plays or a
// new run starts. Nothing here depends on Karaoke being on.
//
// ── Why they used to die at every line change (found 2026-10-17) ──────────────
// The card's rows are a window over the lyrics (`visibleRows`), a NEW array each time the current
// line changes, so the Repeater destroys and rebuilds EVERY row — and every row's marks — on each
// line switch. A mark placed itself with positionToRectangle(), a plain function call that notifies
// nothing. While you sang, a mark was created at the first hit, long after its row's layout had
// settled, so it drew. After a rebuild, marks were created already knowing their flags, in the
// same instant as the new TextEdit — before it had a width or had laid anything out — read an
// empty rectangle, and never read it again. Visible exactly as long as its line was current.
//
// So a position is read through rectAt(), which depends on what the layout is made of (its width,
// its content height, its length — the dependencies LyricGlyphs reads for the same reason) and on
// a tick that fires once after creation, so it is re-read when the layout arrives. Out-of-range
// positions are refused, as LyricGlyphs does: a stale index into a replaced text logs a
// QTextCursor error per mark per frame.
//
// A word that wraps onto the next row is left unmarked rather than drawn across two lines.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: marks

    // The line's LyricLayout (the invisible TextEdit that decides where everything goes), and
    // the text IT was given — the spans are indices into that string.
    required property var lay
    required property string text
    // Which lyric line this is (Lyrics.lines' index — the row's own).
    required property int lineIndex
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var flags: Karaoke.sung[marks.lineIndex] ?? []
    readonly property bool wanted: marks.flags.length > 0
    readonly property var spans: marks.wanted ? KJ.wordSpans(marks.text) : []

    // Re-reads every position once, after the row has had its first layout pass.
    property int tick: 0
    Component.onCompleted: Qt.callLater(function () { marks.tick++ })

    // The reads below are DEPENDENCIES, not values: they make a binding that calls this re-run when
    // the layout is given a width, finishes laying out, or has its text replaced.
    function rectAt(pos) {
        const w = marks.lay.width
        const h = marks.lay.contentHeight
        const n = marks.lay.length
        const t = marks.tick
        if (pos < 0 || pos > n || w <= 0) return Qt.rect(0, 0, 0, 0)
        return marks.lay.positionToRectangle(pos)
    }

    Repeater {
        // The recogniser's words come from the line's own text and these from the layout's: the
        // two differ only by a trailing space, so the counts agree — and if a romanised or
        // otherwise rewritten line ever makes them differ, no marks beat wrong marks.
        model: marks.wanted && marks.spans.length === marks.flags.length ? marks.spans.length : 0

        delegate: Rectangle {
            id: mark
            required property int index
            readonly property var span: marks.spans[mark.index]
            readonly property var head: marks.rectAt(mark.span.s)
            readonly property var tail: marks.rectAt(mark.span.e)
            readonly property bool sung: !!marks.flags[mark.index]
            // Same row: the end of the word is not at the start of the next line.
            readonly property bool oneRow: Math.abs(mark.tail.y - mark.head.y) < mark.head.height / 2

            // The full length of the word, and what is drawn of it: a sung word's underline WIPES in
            // from its left edge (a fade would pop, and a mark that appears all at once is a
            // label, not a light going along the line).
            readonly property real full: Math.max(0, mark.tail.x - mark.head.x)

            x: mark.head.x
            y: mark.head.y + mark.head.height
            width: mark.sung && mark.oneRow ? mark.full : 0
            height: Tokens.borderChrome
            radius: Tokens.radiusFull
            color: marks.accent
            opacity: 0.9
            visible: width > 0.5
            // Quick: the word was heard a moment ago, and a wipe is there to be seen going along the line,
            // not waited for.
            Behavior on width { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
        }
    }
}
