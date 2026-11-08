.pragma library

// ── volumeprofiles.js ─────────────────────────────────────────────────────────
// The four named levels of the media panel's volume — soft, medium, max, boost — as data and
// two pure functions: which one a pair of levels amounts to, and what picking one changes.
// (bun scripts/test-volumeprofiles.js)
//
// ── Whose volume ──────────────────────────────────────────────────────────────
// A profile is about ONE player's volume, never the machine's. Soft, medium and max set the
// player's own level (MPRIS `Volume`, i.e. the slider inside Spotify), which the player keeps
// across tracks; setting its PipeWire stream instead is what "failed to persist", because
// Spotify rewrites its stream on a track change.
//
// Boost is the one level past 100%, and it still only touches that player: its own volume at
// full and ITS STREAM over-amplified (PipeWire allows a stream past unity), to CEILING and not
// a step further — past that it is distortion, not volume. The stream's level from before is
// remembered and given back the moment another profile is picked. The output device is never
// touched here.
// ─────────────────────────────────────────────────────────────────────────────

// The loudest anything in the shell goes: the mixer's boost, and the Boost profile.
var CEILING = 1.30

// `player` is the player's own level; `boost` marks the one that also over-amplifies its stream.
var PROFILES = [
    { key: "soft",   label: "Soft",   icon: "volume_mute", player: 0.35, boost: false },
    { key: "medium", label: "Medium", icon: "volume_down", player: 0.65, boost: false },
    { key: "max",    label: "Max",    icon: "volume_up",   player: 1.00, boost: false },
    { key: "boost",  label: "Boost",  icon: "bolt",        player: 1.00, boost: true  }
]

// How close a level must be to a profile's to count as being on it.
var TOLERANCE = 0.04

// A stream counts as over-amplified past this: a hair over 100%, so 1.0000004 from rounding is not.
var UNITY = 1.02

function _near(a, b) { return Math.abs(a - b) < TOLERANCE }

// Which profile (an index into PROFILES) these two levels amount to, or -1.
//   player  the player's own volume, 1.0 = full
//   stream  its PipeWire stream's volume, 1.0 = unity (the same number as `player` for a
//           player that has no volume of its own of which to speak)
function detect(player, stream) {
    var lifted = stream > UNITY
    for (var i = 0; i < PROFILES.length; i++) {
        var p = PROFILES[i]
        if (!_near(player, p.player)) continue
        // Max and Boost share a player level; the stream tells them apart.
        if (p.key === "max"   && lifted)  continue
        if (p.key === "boost" && !lifted) continue
        return i
    }
    return -1
}

// What picking profile `index` changes, given the stream's level now and what it was before
// Boost lifted it (or -1 if nothing is remembered):
//   { player: level to set,
//     stream: level to set the stream to, or null to leave it,
//     remember: the stream level to keep for later, -1 to forget it, or null to leave it as is }
function plan(index, stream, remembered) {
    var p = PROFILES[index]
    if (!p) return { player: 1, stream: null, remember: null }

    if (p.boost) {
        return { player: p.player, stream: CEILING,
                 // Only a stream that is NOT already lifted is worth remembering — one that
                 // is would store the boost itself as "what it was".
                 remember: stream > UNITY ? null : stream }
    }

    // Another profile: the stream is only touched to undo a boost. Back to what it was, or to
    // unity if that was lost (a reload in between) — never to something louder.
    if (stream > UNITY)
        return { player: p.player, stream: remembered > 0 && remembered <= 1 ? remembered : 1, remember: -1 }

    return { player: p.player, stream: null, remember: null }
}
