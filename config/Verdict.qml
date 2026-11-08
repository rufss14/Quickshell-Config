pragma Singleton
import Quickshell
import QtQuick

// ── Verdict ───────────────────────────────────────────────────────────────────
// The two colours that must NOT follow the wallpaper: pass and fail.
//
// ── Why these are not in Colors ───────────────────────────────────────────────
// Every other colour in this shell is a ROLE resolved against the extracted palette,
// and that is right: a surface, an accent, a border should all wear the wallpaper.
// A pass/fail readout is the one thing that must not, because the palette is free to
// land on red — and then the "it worked" tick renders red and the indicator states
// the opposite of what it means. That was observed, not theorised.
//
// They stay out of `Colors` so that reaching for them is a deliberate import rather
// than the path of least resistance. `Colors` is the palette; this is the small set
// of colours that exist precisely because they are NOT the palette.
//
// ── Why a singleton rather than a constant per badge ──────────────────────────
// There were two copies — modules/bar/widgets/VisualizerPill.qml and
// modules/overview/OverviewNowPlaying.qml — with the same values and the same
// six-line comment explaining them. Both draw the SAME fact (`Lyrics.viaBridge`),
// and both can be on screen at once: the bar pill sits above an open overview. Two
// definitions of one green is the shape this repo already calls out elsewhere —
// two copies is two things disagreeing about what green means.
//
// ── The related rule: colorizeIcons ───────────────────────────────────────────
// `tint()` carries the opt-out both call sites had written out by hand.
// Config.colorizeIcons sends this to the GLOBAL accent (Colors.primary) — never to a
// per-track album tint, which can itself land on red or green and reintroduce exactly
// the failure above.
//
// Not to be confused with DiscordCallBar's discordRed/discordGreen: those are a
// third party's BRAND, scoped to that one card on purpose. These are semantic.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property color pass: "#3FB950"
    readonly property color fail: "#F85149"

    // `ok` → the pass colour, the fail colour, or the global accent when the user has
    // asked for accented icons. The one expression both badges need.
    function tint(ok) {
        if (Config.colorizeIcons) return Colors.primary
        return ok ? root.pass : root.fail
    }
}
