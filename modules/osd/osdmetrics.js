.pragma library

// ── osdmetrics.js ─────────────────────────────────────────────────────────────
// The OSD column's sizes, once. OsdColumn lays itself out from these, and OsdSliders —
// a window that has to be big enough for the tallest thing the column can be, before the
// column exists — sizes itself from the same call. They used to be two copies of the same
// arithmetic with a comment saying "keep the two in step"; a window a pixel short clips
// the card, and it only shows on the tallest showing.
//
// The tokens come in as arguments because a `.pragma library` file cannot see the
// singletons: `of(Tokens.pillHeight, Tokens.spacingMd, Tokens.spacingLg, Tokens.spacingXl)`.

function of(pillHeight, spacingMd, spacingLg, spacingXl) {
    // A level: the slider is two pills wide, its track two and a half widths tall, and the
    // shape badge under it is as wide as the slider.
    var sliderW = Math.round(pillHeight * 2)
    var trackH  = Math.round(sliderW * 2.5)
    var ctrlH   = trackH + spacingMd + sliderW          // track + gap + badge
    // An announcement: a tile twice as wide as a slider, because it carries words.
    var tileW   = sliderW * 2
    return {
        sliderW: sliderW,
        trackH:  trackH,
        ctrlH:   ctrlH,
        tileW:   tileW,
        pad:     spacingXl,
        gap:     spacingLg,
        // The widest the card gets, and the tallest: all three levels at once.
        maxCardW: Math.max(sliderW, tileW) + spacingXl * 2,
        maxCardH: ctrlH * 3 + spacingLg * 2 + spacingXl * 2
    }
}
