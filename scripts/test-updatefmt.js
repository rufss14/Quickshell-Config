// ── test-updatefmt.js ─────────────────────────────────────────────────────────
// Regression tests for services/updatefmt.js — the update panel's words and judgements.
//     bun scripts/test-updatefmt.js
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "updatefmt.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const U = new Function(src + "\nreturn { bump, bumpRank, etaText, agoText, pkgUrl, matches, cleanTime, inQuiet };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

// ── bump ──────────────────────────────────────────────────────────────────────
eq("patch", U.bump("1.2.3-1", "1.2.4-1"), "patch");
eq("minor", U.bump("6.11.2.arch1-1", "6.12.1.arch1-1"), "minor");
eq("major", U.bump("1.9.9-1", "2.0.0-1"), "major");
eq("major with fewer parts", U.bump("1.4-1", "2.0-1"), "major");
eq("rebuild: only the pkgrel", U.bump("1.2.3-1", "1.2.3-2"), "rebuild");
eq("epoch is major", U.bump("1:1.0-1", "2:0.9-1"), "major");
eq("an epoch appearing is major", U.bump("1.0-1", "1:0.9-1"), "major");
eq("letters only: patch", U.bump("6.12.1.arch1-1", "6.12.1.arch2-1"), "patch");
eq("a longer version", U.bump("1.2-1", "1.2.1-1"), "patch");
eq("git revision", U.bump("r1234.abcdef0-1", "r1250.1234567-1"), "git");
eq("git, dotted", U.bump("1.2.r45.gabc123-1", "1.2.r52.gdef456-1"), "git");
eq("a date version", U.bump("20260101-1", "20261012-1"), "git");
eq("no from", U.bump("", "1.0-1"), "new");
eq("no to", U.bump("1.0-1", ""), "unknown");
eq("identical", U.bump("1.0-1", "1.0-1"), "unknown");
eq("a flatpak commit hash is not a number jump", U.bump("abc", "def"), "patch");
eq("ranks", ["major", "minor", "patch", "git", "rebuild", "x"].map(U.bumpRank), [0, 1, 2, 3, 4, 5]);

// ── eta ───────────────────────────────────────────────────────────────────────
eq("eta too early", U.etaText(10, 0.5), "");
eq("eta too little progress", U.etaText(60, 0.1), "");
eq("eta done", U.etaText(60, 1), "");
eq("eta: half way in 60 s is a minute", U.etaText(60, 0.5), "about 1 minute left");
eq("eta: a fifth in 60 s is four minutes", U.etaText(60, 0.2), "about 4 minutes left");
eq("eta: nearly there", U.etaText(100, 0.9), "under a minute left");
eq("eta: absurdly long", U.etaText(3000, 0.2), "");
eq("eta: forty minutes is fine", U.etaText(600, 0.2), "about 40 minutes left");
eq("eta: garbage", U.etaText(undefined, NaN), "");

// ── ago ───────────────────────────────────────────────────────────────────────
const NOW = 1_000_000_000_000;
eq("never", U.agoText(0, NOW), "");
eq("just now", U.agoText(NOW - 20_000, NOW), "just now");
eq("minutes", U.agoText(NOW - 3 * 60_000, NOW), "3 min ago");
eq("hours", U.agoText(NOW - 2 * 3600_000, NOW), "2 h ago");
eq("days", U.agoText(NOW - 50 * 3600_000, NOW), "2 d ago");

// ── urls ──────────────────────────────────────────────────────────────────────
eq("official", U.pkgUrl({ name: "linux", source: "official" }), "https://archlinux.org/packages/?q=linux");
eq("aur", U.pkgUrl({ name: "yay-bin", source: "aur" }), "https://aur.archlinux.org/packages/yay-bin");
eq("flatpak", U.pkgUrl({ name: "org.mozilla.firefox", source: "flatpak" }), "https://flathub.org/apps/org.mozilla.firefox");
eq("encoded", U.pkgUrl({ name: "a b&c", source: "aur" }), "https://aur.archlinux.org/packages/a%20b%26c");
eq("no package", [U.pkgUrl(null), U.pkgUrl({})], ["", ""]);

// ── search ────────────────────────────────────────────────────────────────────
eq("empty query keeps all", U.matches({ name: "x" }, ""), true);
eq("substring", U.matches({ name: "openssl" }, "ssl"), true);
eq("case", U.matches({ name: "OpenSSL" }, "OPENSS"), true);
eq("two words, any order", U.matches({ name: "openssl-libs" }, "libs open"), true);
eq("a word missing", U.matches({ name: "openssl" }, "ssl libs"), false);
eq("no match", U.matches({ name: "firefox" }, "chrome"), false);
eq("no package", U.matches(null, "x"), false);

// ── quiet hours ───────────────────────────────────────────────────────────────
const M = (h, m = 0) => h * 60 + m;
eq("clean time", ["7:05", "07:05", " 23:59 ", "7:5", "24:00", "12:60", "", "abc", null].map(U.cleanTime), ["07:05", "07:05", "23:59", "", "", "", "", "", ""]);
eq("across midnight: inside", [M(23), M(23, 30), M(0), M(3), M(6, 59)].map(t => U.inQuiet(t, "23:00", "07:00")), Array(5).fill(true));
eq("across midnight: outside", [M(7), M(12), M(22, 59)].map(t => U.inQuiet(t, "23:00", "07:00")), Array(3).fill(false));
eq("the same day: inside and the edges", [M(13), M(13, 30), M(14, 59)].map(t => U.inQuiet(t, "13:00", "15:00")), Array(3).fill(true));
eq("the same day: outside and the end is outside", [M(12, 59), M(15), M(20)].map(t => U.inQuiet(t, "13:00", "15:00")), Array(3).fill(false));
eq("equal times are no window", [U.inQuiet(M(3), "03:00", "03:00"), U.inQuiet(M(12), "00:00", "00:00")], [false, false]);
eq("bad times are no window", [U.inQuiet(M(3), "", "07:00"), U.inQuiet(M(3), "23:00", "x"), U.inQuiet(NaN, "23:00", "07:00")], [false, false, false]);

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
