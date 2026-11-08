.pragma library

// ── albumscheme.js ────────────────────────────────────────────────────────────
// The decision behind services/AlbumScheme.qml: given everything the service knows,
// should the shell be wearing the album's colours right now, and if not, why not.
//
// Pure and separate for the standing reason in this repo — a QML expression buried in a
// service cannot be tested, and this one is a state machine with a timer in it. The
// failure it exists to prevent is not a crash: it is the desktop strobing back to the
// wallpaper and forward again in the two-second gap between two tracks off the same
// record, which on the system-wide reach is two full pywal regenerations and two rounds
// of repainting every application. That is a sequence bug, and sequence bugs are exactly
// what you cannot see by reading a chain of if-statements.
//
// `bun scripts/test-albumscheme.js`
//
// ── The vocabulary ────────────────────────────────────────────────────────────
// decide() returns one of four actions:
//
//   clear    stop showing an album palette, now. Hand the colours back.
//   hold     we would like to stop, but something is already on screen and the reason
//            may well be transient — keep showing it and start (or keep) the timer.
//   show     put `cached` on screen.
//   extract  we have no palette for this cover yet; go and derive one. Deliberately NOT
//            a reason to stop showing the previous album — the shell keeps the last
//            track's colours for the ~200ms the extraction takes, so consecutive tracks
//            cross-fade instead of blinking through the wallpaper palette between them.
//            (AlbumArt.qml keeps the previous cover's colours during its own extraction
//            for the same reason.)
// ─────────────────────────────────────────────────────────────────────────────

// `cached` is three-valued and the distinction matters:
//   undefined  never looked at this cover in this mode
//   null       looked, and could not read it (404, not an image, no Pillow)
//   object     a palette
function decide(s) {
    // The only immediate stop. Everything below is held, because everything below can
    // resolve itself within a few seconds and usually does. This one is the user
    // reaching for the switch, and they should see it take effect.
    if (!s.enabled) return { action: "clear", reason: "off" }

    if (!s.hasPlayer) return _stop(s, "no-player")
    if (!s.playing)   return _stop(s, "stopped")
    if (!s.eligible)  return _stop(s, "ineligible")
    if (!s.hasArt)    return _stop(s, "no-art")

    // Every slot pinned by hand means the album has nothing left to change. Checked
    // before the extraction, or a fully-pinned palette would still spawn a process per
    // track to compute colours that can never be seen.
    if (s.fullyHeld)  return _stop(s, "held")

    if (s.cached === undefined) return { action: "extract", reason: s.active ? "active" : "extracting" }
    if (s.cached === null)      return _stop(s, "failed")

    return { action: "show", reason: "active" }
}

// Hold if something is on screen and the timer has not run out; otherwise stop.
function _stop(s, why) {
    if (s.active && !s.graceExpired) return { action: "hold", reason: why }
    return { action: "clear", reason: why }
}
