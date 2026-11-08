import QtQuick

// ── DiscordIcons ──────────────────────────────────────────────────────────────
// The call-control iconography, as SVG path data on a 24×24 grid.
//
// Kept out of DiscordCallBar.qml because it is data, not layout — thirty lines of
// path strings in the middle of a card makes the card unreadable, and these change for
// entirely different reasons than the bar does.
//
// ── Why not Nerd Font glyphs ─────────────────────────────────────────────────
// That's what this used to use, and the shapes are simply not the same ones: Material's
// `monitor_share` for Discord's screen share, `phone_hangup` for Discord's handset.
// Each is a plausible icon for the concept and none of them is the icon on the other
// monitor, which is the whole point of a panel meant to mimic Discord.
//
// Drawn here rather than lifted from Discord's assets: these are the generic shapes
// (a microphone, headphones, a screen, a handset) drawn to match its proportions and
// weight, not copies of its files.
//
// ── Reading these ────────────────────────────────────────────────────────────
// `*Fill` is solid, `*Stroke` is outlined; most icons are both, because that's how the
// originals are built — a solid microphone capsule inside a stroked stand. Coordinates
// assume the 24-grid; VectorIcon scales them to whatever size the button asks for.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    // The slash used by the muted variants. Drawn corner to corner, so it reads at any
    // size — a short slash confined to the glyph turns into a smudge below ~20px.
    readonly property string slash: "M4.4 3.9 L20.1 19.6"

    // ── Microphone ────────────────────────────────────────────────────────────
    // Capsule body, U-shaped stand, stem. No base bar: Discord's has none, and adding
    // one is the single most common way these end up looking like Material instead.
    readonly property string micFill:
        "M12 2.75a3.3 3.3 0 0 1 3.3 3.3v5.1a3.3 3.3 0 0 1-6.6 0v-5.1a3.3 3.3 0 0 1 3.3-3.3z"
    readonly property string micStroke:
        "M6.2 10.9v0.6a5.8 5.8 0 0 0 11.6 0v-0.6 M12 17.3v3.9"

    readonly property string micMutedFill:   micFill
    readonly property string micMutedStroke: micStroke + " " + slash

    // ── Headphones ────────────────────────────────────────────────────────────
    // One filled path: band and both cups, with the cups squared off on their inner
    // edges the way Discord's are.
    readonly property string headphonesFill:
        "M12 3.1A8.9 8.9 0 0 0 3.1 12v4.3A3.6 3.6 0 0 0 6.7 19.9h1.05a1.3 1.3 0 0 0 1.3-1.3v-4.6a1.3 1.3 0 0 0-1.3-1.3H5.4V12a6.6 6.6 0 0 1 13.2 0v0.7h-2.35a1.3 1.3 0 0 0-1.3 1.3v4.6a1.3 1.3 0 0 0 1.3 1.3H17.3a3.6 3.6 0 0 0 3.6-3.6V12A8.9 8.9 0 0 0 12 3.1z"
    readonly property string headphonesStroke: ""

    readonly property string deafenedFill:   headphonesFill
    readonly property string deafenedStroke: slash

    // ── Screen share ──────────────────────────────────────────────────────────
    // A stroked screen with a solid arrow leaving it — Discord's, rather than
    // Material's monitor-with-a-share-node.
    readonly property string screenShareFill:
        "M12 8.1l3.7 3.75h-2.45v3.5h-2.5v-3.5H8.3z"
    readonly property string screenShareStroke:
        "M4 5.3h16a1.8 1.8 0 0 1 1.8 1.8v8.9a1.8 1.8 0 0 1-1.8 1.8H4a1.8 1.8 0 0 1-1.8-1.8V7.1A1.8 1.8 0 0 1 4 5.3z M9.2 20.8h5.6"

    // ── Camera ────────────────────────────────────────────────────────────────
    // Rounded body plus the wedge lens, as one fill.
    readonly property string cameraFill:
        "M4.3 6.8h9a2.3 2.3 0 0 1 2.3 2.3v5.8a2.3 2.3 0 0 1-2.3 2.3h-9A2.3 2.3 0 0 1 2 14.9V9.1a2.3 2.3 0 0 1 2.3-2.3z "
      + "M17.1 10.95l3.95-2.35a0.62 0.62 0 0 1 0.95 0.53v5.74a0.62 0.62 0 0 1-0.95 0.53l-3.95-2.35z"
    readonly property string cameraStroke: ""

    readonly property string cameraOffFill:   cameraFill
    readonly property string cameraOffStroke: slash

    // ── Hang up ───────────────────────────────────────────────────────────────
    // A handset drawn face-down, flaring at both ends — Discord's shape, and its own
    // icon rather than a rotated "call".
    //
    // The first attempt WAS a rotated call icon (the usual trick: take the handset,
    // spin it 135°). Rendered and looked at, it reads as a thin arc — a swoosh, not a
    // telephone. The call glyph's mass is in its corner, so rotating it puts the bulk
    // in the wrong place and leaves the silhouette unrecognisable at 22px. Drawn
    // directly, it's unmistakable at any size, which for the one irreversible control
    // on the bar is the whole requirement. Hence no rotation any more.
    readonly property string hangupFill:
        "M12 8.9c-3.35 0-6.45.85-8.95 2.3-1.05.6-1.7 1.75-1.7 2.98v1.42c0 .93.75 1.68 1.68 1.68h2.94c.93 0 1.68-.75 1.68-1.68v-1.15c0-.4.26-.75.64-.86a15 15 0 0 1 3.71-.46c1.3 0 2.55.16 3.71.46.38.11.64.46.64.86v1.15c0 .93.75 1.68 1.68 1.68h2.94c.93 0 1.68-.75 1.68-1.68v-1.42c0-1.23-.65-2.38-1.7-2.98C18.45 9.75 15.35 8.9 12 8.9z"
    readonly property real hangupRotation: 0
}
