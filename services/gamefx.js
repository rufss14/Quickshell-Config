.pragma library

// ── gamefx.js ─────────────────────────────────────────────────────────────────
// What Game Mode can do while it is on: one entry per switch (a Config property, `key`), how it is
// named and drawn, and what it says on and off. Read by the Game Mode panel and its island page, so
// the two list the same effects in the same order.
// ─────────────────────────────────────────────────────────────────────────────
var EFFECTS = [
    { key: "gamemodeSession",    label: "Performance",          symbol: "speed",
      on: "Governor, GPU clocks, priority",   off: "CPU and GPU left as they are",
      shape: "burst", hint: "A gamemoderun session: the CPU governor, GPU clocks and priority for games" },
    { key: "gamemodeQuiet",      label: "Silence notifications", symbol: "notifications_off",
      on: "Held until the mode ends",         off: "Notifications stay on",
      shape: "clover", hint: "Notifications are held until the mode ends" },
    { key: "gamemodeIdle",       label: "Keep screen awake",    symbol: "visibility",
      on: "The screen won't blank or lock",   off: "The screen may blank",
      shape: "sunny", hint: "Holds an idle inhibitor while the mode is on" },
    { key: "gamemodeWallpaper",  label: "Pause wallpaper",      symbol: "wallpaper",
      on: "Scene stopped, back afterwards",   off: "Scene keeps running",
      shape: "squircle", hint: "Stops the live wallpaper scene and brings it back afterwards" },
    { key: "gamemodeVisualizer", label: "Hide visualiser",      symbol: "equalizer",
      on: "The visualiser stops drawing",     off: "The visualiser keeps drawing",
      shape: "cookie7", hint: "The desktop audio visualiser stops drawing" },
    { key: "gamemodeKeys",       label: "Mute typing sounds",   symbol: "keyboard",
      on: "No key sounds from other apps",    off: "Typing sounds stay on",
      shape: "pentagon", hint: "A game's WASD isn't typing" },
    { key: "gamemodeClips",      label: "Record clips",         symbol: "videocam",
      on: "Replay buffer runs with the mode", off: "Buffer follows its own switch",
      shape: "hexagon", hint: "Keeps the Clips replay buffer running while the mode is on" },
    { key: "gamemodeCompositor", label: "Lighter desktop",      symbol: "blur_on",
      on: "Blur, shadows, animations off",    off: "Desktop untouched",
      shape: "cookie12", hint: "Blur, shadows and animations off in Hyprland, then put back as they were" },
]
