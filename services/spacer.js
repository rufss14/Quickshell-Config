.pragma library

// ── spacer.js ─────────────────────────────────────────────────────────────────
// How long the spacer module is, on either surface (widgets/SpacerPill on the bar,
// SideRail.smallLengths and SideSpacer on the sidebar). Pure, so it can be tested
// (`bun scripts/test-spacer.js`) and the two surfaces can't disagree.
//
//   size       the spacer's own length, px (Config.spacerSize)
//   followLen  the length of the module it follows, 0 for none
//   fill       false: size + followLen (it grows with the module);
//              true:  size - followLen, never below 0 (the two together stay one length)
//   minLen     at least this much (while arranging, so the spacer can be picked up)
// ─────────────────────────────────────────────────────────────────────────────
function length(size, followLen, fill, minLen) {
    const s = Math.max(0, +size || 0);
    const f = Math.max(0, +followLen || 0);
    const base = fill ? Math.max(0, s - f) : s + f;
    return Math.max(base, Math.max(0, +minLen || 0));
}
