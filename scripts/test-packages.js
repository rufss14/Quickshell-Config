// ── test-packages.js ──────────────────────────────────────────────────────────
// services/packages.js — the launcher's `+` package search and its install script.
//
//     bun scripts/test-packages.js          (or: node scripts/test-packages.js)
//
// Safe: pure functions on canned pacman / AUR output. Nothing is searched or installed.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "packages.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + `
return { validName, escapeRegex, terms, pacmanArgs, aurTerm, aurUrl, parsePacman, parseAur,
         parseInstalled, rank, installScript };`)();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

// ── Names ─────────────────────────────────────────────────────────────────────
check("plain name", P.validName("firefox"), true);
check("plus and at", P.validName("lib32-gcc-libs@2+x"), true);
check("leading hyphen refused", P.validName("-Syu"), false);
check("leading dot refused", P.validName(".hidden"), false);
check("shell metachar refused", P.validName("foo;rm"), false);
check("space refused", P.validName("foo bar"), false);
check("uppercase refused", P.validName("Firefox"), false);

// ── Query → arguments ─────────────────────────────────────────────────────────
check("terms: short dropped, deduped", P.terms("  a Fire fire  fox "), ["fire", "fox"]);
check("regex escaped", P.pacmanArgs("c++ (beta)"), ["pacman", "-Ss", "--", "c\\+\\+", "\\(beta\\)"]);
check("nothing to search", P.pacmanArgs("a"), []);
check("aur: longest term", P.aurTerm("vs code-bin"), "code-bin");
check("aur url encoded", P.aurUrl("c++"), "https://aur.archlinux.org/rpc/v5/search/c%2B%2B?by=name-desc");
check("aur url empty", P.aurUrl("x"), "");

// ── pacman -Ss ────────────────────────────────────────────────────────────────
const SS = `extra/firefox 131.0-1 [installed]
    Fast, Private & Safe Web Browser
extra/firefox-developer-edition 132.0b5-1
    Developer Edition of the popular Firefox web browser
core/linux 6.11.1.arch1-1 (base) [installed: 6.10.9.arch1-1]
    The Linux kernel and modules
garbage line
extra/BadName 1-1
    nope`;
const repo = P.parsePacman(SS);
check("parsed count (bad name skipped)", repo.length, 3);
check("installed flag", repo.map(p => p.installed), [true, false, true]);
check("repo + version", [repo[0].repo, repo[0].version], ["extra", "131.0-1"]);
check("description", repo[1].description, "Developer Edition of the popular Firefox web browser");
check("group and installed version parsed", repo[2].name, "linux");

// ── AUR ───────────────────────────────────────────────────────────────────────
const AUR = JSON.stringify({ type: "search", resultcount: 3, results: [
    { Name: "firefox-nightly", Version: "133.0a1-1", Description: "Nightly", Popularity: 2.5, OutOfDate: null },
    { Name: "firefox", Version: "1-1", Description: "AUR copy", Popularity: 9 },
    { Name: "rm -rf", Version: "1", Description: "evil" },
]});
const aur = P.parseAur(AUR);
check("aur parsed, bad name dropped", aur.map(p => p.name), ["firefox-nightly", "firefox"]);
check("aur error is null", P.parseAur(JSON.stringify({ type: "error", error: "Too many" })), null);
check("aur junk is null", P.parseAur("<html>"), null);

// ── Ranking ───────────────────────────────────────────────────────────────────
const inst = P.parseInstalled("firefox\nfirefox-nightly\nnot valid name\n");
check("installed set", Object.keys(inst), ["firefox", "firefox-nightly"]);
const r = P.rank(repo, aur, "firefox", inst);
check("the whole order", r.map(p => p.name + ":" + p.source),
      ["firefox:repo", "firefox-developer-edition:repo", "firefox-nightly:aur"]);
check("exact first", r[0].name + ":" + r[0].source, "firefox:repo");
check("prefix class: repo before aur", r.slice(1).map(p => p.source), ["repo", "aur"]);
check("aur installed from the set", r.find(p => p.name === "firefox-nightly").installed, true);
check("all terms must match", P.rank(repo, aur, "firefox kernel", inst).length, 0);
check("description match last", P.rank(repo, [], "kernel", {}).map(p => p.name), ["linux"]);
check("empty query", P.rank(repo, aur, "", inst), []);

// ── The install script ────────────────────────────────────────────────────────
check("repo only", P.installScript(["firefox"], [], "yay"),
      'set -e\nsudo -S -v\necho ":: [1/1] Official packages"\nsudo -S pacman -S --needed --noconfirm firefox');
check("repo + aur via yay", P.installScript(["a"], ["b-bin"], "yay").split("\n").slice(-2),
      ['echo ":: [2/2] AUR packages"',
       "yay -S --needed --noconfirm b-bin --answerdiff=None --answerclean=None --answeredit=None"]);
check("paru flags", P.installScript([], ["b"], "paru").split("\n").pop(), "paru -S --needed --noconfirm b --skipreview");
check("aur without a helper: nothing", P.installScript([], ["b"], ""), "");
check("unknown helper refused", P.installScript([], ["b"], "rm -rf /;"), "");
check("bad names filtered", P.installScript(["-Syu", "ok", "a;b"], [], "yay").split("\n").pop(),
      "sudo -S pacman -S --needed --noconfirm ok");
check("nothing valid", P.installScript(["-x"], [], "yay"), "");
check("never -y (no partial upgrade)", /pacman -S\w*y/.test(P.installScript(["a"], [], "")), false);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
