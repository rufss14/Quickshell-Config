.pragma library

// ── sudolock.js ───────────────────────────────────────────────────────────────
// Whether pam_faillock has locked the user out of sudo, from what the shell can
// read without root: `faillock --user $USER` (the user's own tally) and
// /etc/security/faillock.conf. services/SudoLock calls in;
// scripts/test-sudolock.js pins it against a real capture.
//
// ── Why the shell has to know ─────────────────────────────────────────────────
// Arch's PAM stack locks an account after `deny` (3) failures within
// `fail_interval` (15 min), for `unlock_time` (10 min). While locked, EVERY sudo
// fails — the right password included — with nothing but "incorrect password
// attempt". A panel that just says "failed" invites a retry, and the retry keeps
// the lock going. A wrong password costs more than one strike, too: `sudo -S`
// re-prompts, reads EOF from the one-line stdin, and that counts as well.
// ─────────────────────────────────────────────────────────────────────────────

// faillock.conf: `key = value` lines and bare flags, `#` comments. Only what the
// lock arithmetic needs, each defaulted as pam_faillock defaults it.
function config(text) {
    const c = { deny: 3, failInterval: 900, unlockTime: 600 }
    for (const raw of String(text ?? "").split("\n")) {
        const line = raw.replace(/#.*/, "").trim()
        const m = /^(deny|fail_interval|unlock_time)\s*=\s*(\S+)$/.exec(line)
        if (!m) continue
        const n = m[2] === "never" ? -1 : parseInt(m[2], 10)
        if (!isFinite(n)) continue
        if (m[1] === "deny") c.deny = n
        else if (m[1] === "fail_interval") c.failInterval = n
        else c.unlockTime = n
    }
    return c
}

// `faillock --user <u>`: a header, then one row per failure —
//     2026-09-26 20:13:37 TTY   /dev/tty1        V
// → the failure times (ms, local time) that are still Valid ("V"), oldest first.
function failures(text) {
    const out = []
    for (const line of String(text ?? "").split("\n")) {
        const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\s.*\s(V|I)\s*$/.exec(line)
        if (!m || m[7] !== "V") continue
        out.push(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime())
    }
    return out.sort((a, b) => a - b)
}

// → { locked, until (ms; 0 = not locked, -1 = until an admin resets it), count, deny }
// Locked when `deny` valid failures fall within `fail_interval` of the latest and
// the latest is less than `unlock_time` ago. deny = 0 disables the lock.
function state(tallyText, confText, now) {
    const c = config(confText)
    const f = failures(tallyText)
    const last = f.length > 0 ? f[f.length - 1] : 0
    const recent = f.filter(t => last - t <= c.failInterval * 1000).length
    const base = { locked: false, until: 0, count: recent, deny: c.deny }
    if (c.deny <= 0 || recent < c.deny) return base
    if (c.unlockTime < 0) return { locked: true, until: -1, count: recent, deny: c.deny }
    if (c.unlockTime === 0) return base          // 0 = the lock lifts at once
    const until = last + c.unlockTime * 1000
    return until > now ? { locked: true, until: until, count: recent, deny: c.deny } : base
}

// Did a sudo run fail on the PASSWORD (not on what it ran)? From its output lines:
// sudo's own words, whichever of them this version printed.
function rejected(lines) {
    return (Array.isArray(lines) ? lines : []).some(l =>
        /incorrect password attempt|no password was provided|Sorry, try again|Authentication failure/i
            .test(String(l && l.text !== undefined ? l.text : l)))
}
