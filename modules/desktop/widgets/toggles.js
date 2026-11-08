.pragma library

// ── toggles.js ────────────────────────────────────────────────────────────────
// What each quick toggle LOOKS like — its name and its two icons — shared by the Quick
// toggles tile and its options in Settings › Widgets, so the list can't drift between
// the two. Whether one is on, why it can't run, and what it does are not here: those are
// ShellActions' (and Bt's, for Bluetooth power) — see TogglesWidget.
// ─────────────────────────────────────────────────────────────────────────────

var TABLE = {
    wifi:       { label: "Wi-Fi",          on: "wifi",              off: "wifi_off" },
    bluetooth:  { label: "Bluetooth",      on: "bluetooth",         off: "bluetooth_disabled" },
    dnd:        { label: "Do not disturb", on: "notifications_off", off: "notifications" },
    nightlight: { label: "Night light",    on: "nights_stay",       off: "nights_stay" },
    awake:      { label: "Stay awake",     on: "coffee",            off: "coffee" },
    gamemode:   { label: "Game mode",      on: "sports_esports",    off: "sports_esports" },
    mute:       { label: "Mute",           on: "volume_off",        off: "volume_up" },
    micMute:    { label: "Mic off",        on: "mic_off",           off: "mic" },
    theme:      { label: "Light mode",     on: "light_mode",        off: "dark_mode" }
}

// The order Settings lists them in.
var ORDER = ["wifi", "bluetooth", "dnd", "nightlight", "awake", "gamemode", "mute", "micMute", "theme"]
