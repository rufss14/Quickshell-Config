// ── test-sudolock.js ──────────────────────────────────────────────────────────
// Regression tests for services/sudolock.js — reading pam_faillock's lock.
//
//     bun scripts/test-sudolock.js          (or: node scripts/test-sudolock.js)
//
// Safe to run: pure functions. The tally fixture is a real `faillock --user`
// capture from this machine (2026-09-26), the lockout that prompted this file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "sudolock.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { config, failures, state, rejected } =
    new Function(src + "\nreturn { config, failures, state, rejected };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

const TALLY = `rufss:
When                Type  Source                                           Valid
2026-09-26 20:13:37 TTY   /dev/tty1                                            V
2026-09-26 20:13:40 TTY   /dev/tty1                                            V
2026-09-26 20:13:43 TTY   /dev/tty1                                            V
`;
const at = (h, m, s) => new Date(2026, 8, 26, h, m, s).getTime();

// ── config ───────────────────────────────────────────────────────────────────
check("config: Arch's shipped file is all comments → defaults",
      config("# deny = 3\n# unlock_time = 600\n"), { deny: 3, failInterval: 900, unlockTime: 600 });
check("config: set values", config("deny = 5\nunlock_time=120\nfail_interval = 60"),
      { deny: 5, failInterval: 60, unlockTime: 120 });
check("config: never", config("unlock_time = never").unlockTime, -1);
check("config: trailing comment", config("deny = 4 # four").deny, 4);
check("config: flags ignored", config("silent\naudit\ndeny = 2").deny, 2);
check("config: nothing", config(undefined).deny, 3);

// ── failures ─────────────────────────────────────────────────────────────────
check("failures: the capture", failures(TALLY), [at(20, 13, 37), at(20, 13, 40), at(20, 13, 43)]);
check("failures: invalid rows don't count",
      failures("u:\n2026-09-26 20:00:00 TTY /dev/tty1 I\n2026-09-26 20:00:01 SVC sudo V\n").length, 1);
check("failures: empty tally", failures("rufss:\nWhen Type Source Valid\n"), []);

// ── state ────────────────────────────────────────────────────────────────────
check("state: locked right after", state(TALLY, "", at(20, 16, 38)),
      { locked: true, until: at(20, 23, 43), count: 3, deny: 3 });
check("state: lifts after unlock_time", state(TALLY, "", at(20, 23, 44)).locked, false);
check("state: two strikes isn't a lock",
      state(TALLY.split("\n").slice(0, 4).join("\n"), "", at(20, 14, 0)),
      { locked: false, until: 0, count: 2, deny: 3 });
check("state: spread past fail_interval", state(TALLY, "fail_interval = 2", at(20, 14, 0)).locked, false);
check("state: never unlocks by itself", state(TALLY, "unlock_time = never", at(23, 0, 0)).until, -1);
check("state: deny = 0 disables it", state(TALLY, "deny = 0", at(20, 14, 0)).locked, false);
check("state: no faillock output", state("", "", at(20, 14, 0)).locked, false);

// ── rejected ─────────────────────────────────────────────────────────────────
check("rejected: sudo's EOF", rejected([{ text: "sudo: no password was provided", err: true }]), true);
check("rejected: a wrong one", rejected(["Sorry, try again.", "sudo: 1 incorrect password attempt"]), true);
check("rejected: pacman failing isn't a password problem",
      rejected([{ text: "error: failed to commit transaction (conflicting files)" }]), false);
check("rejected: nothing", rejected(undefined), false);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
