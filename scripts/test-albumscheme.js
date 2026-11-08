// ── test-albumscheme.js ───────────────────────────────────────────────────────
// Tests for services/albumscheme.js — the decision behind the album colour scheme.
// Fully pure and SAFE TO RUN: no processes, no files, no MPRIS, no palette extraction.
//
//   bun scripts/test-albumscheme.js
//
// ── Why this is a sequence test and not a table ───────────────────────────────
// The single-state cases below are the easy half and would have passed on the first
// implementation, which was still wrong. What this is actually for is the SEQUENCES:
// the gap between two tracks off one album is a couple of seconds in which the player
// stops playing, the cover url goes empty, and the pick can briefly land on a different
// player. Handled naively that is a revert and a re-apply per song — on the system-wide
// reach, two full pywal regenerations and two rounds of repainting every GTK and Qt app,
// between two tracks off the same record.
//
// The other thing only a sequence catches: the grace timer re-enters the same decision
// it started from. The first cut of that renewed itself forever and never reverted
// anything at all — a shell that kept a dead track's colours until the next song, which
// is precisely the behaviour that was NOT asked for.
// ─────────────────────────────────────────────────────────────────────────────

// albumscheme.js is loaded by stripping its `.pragma library` line (a QML directive that
// isn't valid JS) and evaluating the rest, so the tests run against the real file rather
// than a copy that can drift. Same approach as test-lyricsmotion.js and test-calc.js.
import { readFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const here = dirname(fileURLToPath(import.meta.url))
const src = readFileSync(join(here, "..", "services", "albumscheme.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")

const A = new Function(src + "\nreturn { decide };")()

let PASS = 0
let FAIL = 0

function ok(name, cond) {
    if (cond) PASS++
    else { FAIL++; console.log(`  FAIL  ${name}`) }
}

function eq(name, got, want) {
    if (got === want) PASS++
    else { FAIL++; console.log(`  FAIL  ${name}\n        want: ${want}\n        got:  ${got}`) }
}

const PALETTE = { special: {}, colors: {} }

// A player doing everything right, on a cover we have already extracted.
function good(over) {
    return Object.assign({
        enabled: true, hasPlayer: true, playing: true, eligible: true,
        hasArt: true, fullyHeld: false, cached: PALETTE,
        active: false, graceExpired: false
    }, over || {})
}

// ── One state at a time ──────────────────────────────────────────────────────
function testSingle() {
    console.log("single states")
    eq("a playing eligible track shows", A.decide(good()).action, "show")
    eq("an unseen cover extracts", A.decide(good({ cached: undefined })).action, "extract")

    // Each of these, from a cold start, clears outright — there is nothing on screen
    // to protect, so there is nothing to wait for.
    const stops = {
        enabled: "off", hasPlayer: "no-player", playing: "stopped",
        eligible: "ineligible", hasArt: "no-art"
    }
    for (const [field, reason] of Object.entries(stops)) {
        const d = A.decide(good({ [field]: false }))
        eq(`${field}=false clears`, d.action, "clear")
        eq(`${field}=false reason`, d.reason, reason)
    }
    eq("fully held clears", A.decide(good({ fullyHeld: true })).action, "clear")
    eq("fully held reason", A.decide(good({ fullyHeld: true })).reason, "held")
    eq("a declined cover clears", A.decide(good({ cached: null })).action, "clear")
    eq("a declined cover reason", A.decide(good({ cached: null })).reason, "failed")

    // Precedence. `off` outranks everything, and `held` is checked before the cache so
    // a fully-pinned palette never spawns an extraction it cannot use.
    eq("off beats everything",
       A.decide({ enabled: false, hasPlayer: false, playing: false, eligible: false,
                  hasArt: false, fullyHeld: true, cached: null,
                  active: true, graceExpired: false }).reason, "off")
    eq("held is decided before extracting",
       A.decide(good({ fullyHeld: true, cached: undefined })).action, "clear")
}

// ── Something is on screen: transient reasons are held, not acted on ─────────
function testHold() {
    console.log("holding")
    for (const field of ["hasPlayer", "playing", "eligible", "hasArt"]) {
        const d = A.decide(good({ [field]: false, active: true }))
        eq(`${field}=false holds while active`, d.action, "hold")
    }
    eq("held holds while active",
       A.decide(good({ fullyHeld: true, active: true })).action, "hold")
    eq("a declined cover holds while active",
       A.decide(good({ cached: null, active: true })).action, "hold")

    // The switch is the user, and must not be graced.
    eq("switching off is immediate even while active",
       A.decide(good({ enabled: false, active: true })).action, "clear")

    // An extraction in flight must not blank the previous album.
    eq("an unseen cover keeps the current one up",
       A.decide(good({ cached: undefined, active: true })).action, "extract")

    // Once the timer has run out, the same state finally gives way.
    for (const field of ["hasPlayer", "playing", "eligible", "hasArt"]) {
        const d = A.decide(good({ [field]: false, active: true, graceExpired: true }))
        eq(`${field}=false clears once grace expired`, d.action, "clear")
    }
}

// ── Sequences ────────────────────────────────────────────────────────────────
// A tiny driver mirroring what AlbumScheme.qml does with the answer, so the test
// exercises the loop and not just the branch.
function run(steps) {
    let active = false
    let graceArmed = false
    const log = []

    for (const step of steps) {
        if (step === "TICK") {
            // The grace timer firing: re-decide with the flag set, exactly as the
            // Timer's onTriggered does.
            if (!graceArmed) { log.push("tick-idle"); continue }
            const d = A.decide(Object.assign({}, last, { active, graceExpired: true }))
            if (d.action === "clear") { active = false; graceArmed = false; log.push("clear:" + d.reason) }
            else if (d.action === "show") { active = true; graceArmed = false; log.push("show") }
            else log.push(d.action)
            continue
        }
        var last = step
        const d = A.decide(Object.assign({}, step, { active, graceExpired: false }))
        switch (d.action) {
        case "show":    graceArmed = false; active = true;  log.push("show"); break
        case "extract": log.push("extract"); break
        case "hold":    graceArmed = true;  log.push("hold:" + d.reason); break
        default:        graceArmed = false; active = false; log.push("clear:" + d.reason)
        }
    }
    return log
}

function testSequences() {
    console.log("sequences")

    // ── The gap between two tracks ───────────────────────────────────────────
    // The whole reason the grace period exists. Playing → the player briefly reports
    // nothing → the next track's cover arrives. Nothing may be cleared anywhere in
    // there, and on the system-wide reach a single "clear" here is a pywal run.
    const gap = run([
        good(),                                     // track 1 playing
        good({ playing: false }),                   // gap: paused for a moment
        good({ playing: false, hasArt: false }),    // gap: cover url dropped
        good(),                                     // track 2, cover already known
    ])
    ok("a track gap never reverts", !gap.some(s => s.startsWith("clear")))
    eq("a track gap ends showing", gap[gap.length - 1], "show")

    // ── Actually stopping ────────────────────────────────────────────────────
    // Paused and left paused: held first, then handed back when the timer runs out.
    const stopped = run([good(), good({ playing: false }), "TICK"])
    eq("pausing holds first", stopped[1], "hold:stopped")
    eq("and reverts when the timer runs out", stopped[2], "clear:stopped")

    // ── The timer must terminate ─────────────────────────────────────────────
    // The bug this is really guarding: _hide() saw the timer idle and restarted it, so
    // grace renewed itself forever and the palette never came back.
    const many = run([good(), good({ playing: false }), "TICK", "TICK", "TICK"])
    ok("the grace timer terminates", many.includes("clear:stopped"))
    eq("and does not re-arm afterwards", many[many.length - 1], "tick-idle")

    // ── Resuming inside the grace period costs nothing ───────────────────────
    const resumed = run([good(), good({ playing: false }), good()])
    ok("resuming before the timer never reverts", !resumed.some(s => s.startsWith("clear")))

    // ── Switching to an ineligible player ────────────────────────────────────
    // Spotify pauses, a YouTube tab starts. The album palette must go — but only after
    // the grace period, since a momentary pick landing on the wrong player during a
    // track change is exactly the transient this protects.
    const toYoutube = run([
        good(),
        good({ eligible: false }),
        good({ eligible: false }),
        "TICK",
    ])
    eq("an ineligible player holds first", toYoutube[1], "hold:ineligible")
    eq("then hands the colours back", toYoutube[3], "clear:ineligible")

    // ── One unreadable cover mid-album ───────────────────────────────────────
    // A single cover that failed to download should not strobe the desktop; it holds,
    // and if the next track's cover arrives nothing visibly happened at all.
    //
    // A GREYSCALE cover is deliberately not this case any more. It used to be declined
    // by a saturation threshold, which meant a black-and-white record silently left the
    // wallpaper's palette up. Black and white are colours: it now yields a greyscale
    // palette like any other, and only a genuine read failure lands here.
    const failed = run([good(), good({ cached: null }), good()])
    ok("one unreadable cover mid-album changes nothing",
       !failed.some(s => s.startsWith("clear")))

    // ── Cold start, nothing playing ──────────────────────────────────────────
    // No hold, no timer: there is nothing on screen to protect.
    const cold = run([good({ hasPlayer: false }), good({ hasPlayer: false })])
    ok("a cold start clears immediately", cold.every(s => s === "clear:no-player"))

    // ── Turning it off mid-track ─────────────────────────────────────────────
    const off = run([good(), good({ enabled: false })])
    eq("switching off is immediate", off[1], "clear:off")

    // ── A new album ──────────────────────────────────────────────────────────
    // Unseen cover: extract, and keep the previous album up while it runs.
    const newAlbum = run([good(), good({ cached: undefined }), good()])
    eq("a new cover extracts", newAlbum[1], "extract")
    ok("without dropping the previous one", !newAlbum.some(s => s.startsWith("clear")))
}

function main() {
    testSingle()
    testHold()
    testSequences()
    console.log(`\n${PASS} passed, ${FAIL} failed`)
    if (FAIL) process.exit(1)
}

main()
