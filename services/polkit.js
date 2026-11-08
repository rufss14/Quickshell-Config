.pragma library

// ── polkit.js ─────────────────────────────────────────────────────────────────
// Tidying the words of a polkit request before they are put in front of someone.
//
// ── Why this is a boundary ────────────────────────────────────────────────────
// The message, the prompt and the supplementary line are all written by OTHER
// processes — pkexec puts the command line you ran into the message, a PAM module
// supplies the prompt. This is the one dialog on the machine whose text decides
// whether someone types their password, so it is cleaned in one place and the
// view renders the result as PLAIN text (StyledText's default; never `rich`).
//
//   • control characters are dropped — a newline-and-spaces run can't push the real
//     action off the visible lines, and a stray ESC or NUL can't do anything odd;
//   • the length is capped, so a request can't fill the screen with its own prose.
//
// Tested (`bun scripts/test-polkit.js`): it's string surgery with a few edge cases
// (an empty prompt, a prompt that is only a colon) that a glance would miss.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_MESSAGE = 240
var MAX_PROMPT  = 60

function _flat(s) {
    // Controls (incl. \n \t) → a space, then runs of spaces → one.
    return String(s === undefined || s === null ? "" : s)
        .replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ")
        .replace(/ {2,}/g, " ")
        .trim()
}

function _cap(s, n) {
    return s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…"
}

// "Authentication is required to run X." → "Authentication is required to run X"
// (the view sets it as a sentence of its own; polkit's trailing full stop reads as noise).
function message(m) {
    var s = _flat(m)
    if (s.endsWith(".")) s = s.slice(0, -1).trimEnd()
    return _cap(s, MAX_MESSAGE)
}

// "Password: " → "Password". An empty one falls back by whether the answer is hidden —
// a prompt that is only ":" counts as empty.
function prompt(p, secret) {
    var s = _flat(p)
    if (s.endsWith(":")) s = s.slice(0, -1).trimEnd()
    return s !== "" ? _cap(s, MAX_PROMPT) : (secret ? "Password" : "Input")
}

// The machine-readable action id (org.freedesktop.policykit.exec), shown small so a
// request can be told apart from another with a similar message. Nothing but the
// characters an action id is made of survives.
function actionId(id) {
    return _cap(String(id === undefined || id === null ? "" : id).replace(/[^A-Za-z0-9._-]/g, ""), 80)
}
