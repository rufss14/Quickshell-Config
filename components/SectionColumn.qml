import QtQuick
import QtQuick.Layouts
import "../config"

// ── SectionColumn ─────────────────────────────────────────────────────────────
// One column of a settings page: a group of Sections that belong together and
// should stack under each other.
//
// ── Why the page groups its own columns ───────────────────────────────────────
// SettingsPage first flowed sections into a plain row-major grid and let the
// layout decide. It looked wrong, for a reason worth writing down: a grid row is
// as tall as its TALLEST cell, so a short section beside a tall one leaves a hole
// the size of the difference. On the lock page that was ~500px of nothing under
// "Automatic locking", because "What the lock shows" is nine toggles tall.
//
// Balancing that automatically means masonry — measuring every section and
// reflowing them — which in QML means reparenting declared children on every
// resize and visibility change. That is a lot of machinery to guess at something
// the page already knows.
//
// So the page says it. Sections that belong together go in one column, and a
// human puts the tall one where it does no harm. This is what the pages did
// BEFORE the restyle (Network's three hand-grouped columns still read better than
// anything the grid produced), just responsive now instead of pinned to pixels.
//
// Collapsing is free: SettingsPage's grid drops to one column on a narrow window,
// and these stack in declaration order with their reading order intact.
//
// ── Balance by HEIGHT, not by count ───────────────────────────────────────────
// The rule, because guessing it wrong is what makes a page look unfinished: a
// column that ends well above its neighbour leaves a void, and the void is the
// difference between the two columns' heights. Two sections per column is not
// balance — Sound's Output is ~490px and its Input ~400, so pairing them
// one-for-one and dealing the rest out left ~290px of nothing under the left
// column, which is exactly what "it suffers towards the end" meant.
//
// So: estimate each section's rendered height, then fill columns to roughly equal
// totals. Aim for within ~15%; past that the shorter column reads as broken
// rather than as breathing room. Semantics decide ties, not the other way round —
// a tidy grouping that leaves a 300px hole is the wrong grouping.
//
// Two things distort the estimate and both matter:
//   · A section that is usually INVISIBLE contributes 0. Sound's Recording only
//     appears while something holds the microphone, so it is stacked where its
//     appearing costs least rather than counted as permanent height.
//   · A section with a list or a chart grows. Put it where growth hurts least,
//     which is normally the bottom of the taller column.
//
// When a page genuinely cannot fit, it should overflow at the BOTTOM of the
// longest column rather than halfway down a short one — scrolling past a full
// column reads as "there is more", scrolling past a mostly-empty one reads as a
// bug.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    Layout.fillWidth: true
    // Top, not stretched: a column with less in it than its neighbour ends where
    // its content ends rather than growing a pocket of empty space underneath.
    Layout.alignment: Qt.AlignTop

    // The same rhythm SettingsPage uses between sections (its `gap`), so a page reads
    // identically whether its sections are in one column or two.
    spacing: Tokens.spacingLg
}
