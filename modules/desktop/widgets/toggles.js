.pragma library

// ── toggles.js ────────────────────────────────────────────────────────────────
// What each quick toggle LOOKS like — its name and its two icons — shared by the Quick
// toggles tile and its options in Settings › Widgets, so the list can't drift between
// the two. The icons are the bar's and the sidebar's own for the same switch
// (SideBarModule: night light bedtime / brightness_4, stay awake coffee / no_drinks,
// game mode sports_esports / videogame_asset_off), so a switch looks the same everywhere. Whether one is on, why it can't run, and what it does are not here: those are
// ShellActions' (and Bt's, for Bluetooth power) — see TogglesWidget.
// ─────────────────────────────────────────────────────────────────────────────

var TABLE = {
    wifi:       { label: "Wi-Fi",          on: "wifi",              off: "wifi_off" },
    bluetooth:  { label: "Bluetooth",      on: "bluetooth",         off: "bluetooth_disabled" },
    dnd:        { label: "Do not disturb", on: "notifications_off", off: "notifications" },
    nightlight: { label: "Night light",    on: "bedtime",           off: "brightness_4" },
    awake:      { label: "Stay awake",     on: "coffee",            off: "no_drinks" },
    gamemode:   { label: "Game mode",      on: "sports_esports",    off: "videogame_asset_off" },
    mute:       { label: "Mute",           on: "volume_off",        off: "volume_up" },
    micMute:    { label: "Mic off",        on: "mic_off",           off: "mic" },
    theme:      { label: "Light mode",     on: "light_mode",        off: "dark_mode" },
    // Momentary actions: the same orb, never lit (ShellActions.stateOf has no state for them).
    shuffle:    { label: "Next wallpaper", on: "shuffle",           off: "shuffle" },
    lock:       { label: "Lock",           on: "lock",              off: "lock" }
}

// The order Settings lists them in.
var ORDER = ["wifi", "bluetooth", "dnd", "nightlight", "awake", "gamemode", "mute", "micMute", "theme"]

// The momentary ones, offered by the hot corner and the desktop menu (not by the desktop tile's picker).
var ACTIONS = ["shuffle", "lock"]

// Every id the hot corner and the desktop menu can carry, in the order Settings lists them, and the
// table the pick-and-order list wants (label and one icon).
var ALL = ORDER.concat(ACTIONS)
var PICKABLE = (function () {
    var out = {}
    for (var i = 0; i < ALL.length; i++) out[ALL[i]] = { label: TABLE[ALL[i]].label, symbol: TABLE[ALL[i]].on }
    return out
})()
