// ── test-xbel.js ──────────────────────────────────────────────────────────────
// Regression tests for services/xbel.js, the recent-files reader behind the
// dock's jump lists.
//
//     bun scripts/test-xbel.js          (or: node scripts/test-xbel.js)
//
// Safe to run: pure functions over an inline fixture shaped like GLib's output.
// The case that matters most is the one that reads wrong silently: the app that
// RECORDED an entry (`name`) is not the app that opened the file (`exec`).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "xbel.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { parse, appsOf, byApp, decode } =
    new Function(src + "\nreturn { parse, appsOf, byApp, decode };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

const fixture = `<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/u/notes%20v2.txt" added="2026-09-01T10:00:00Z" modified="2026-09-01T10:00:00Z" visited="2026-09-01T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="text/plain"/>
      <bookmark:applications>
        <bookmark:application name="org.gnome.Nautilus" exec="&apos;code-oss %F&apos;" modified="2026-09-02T10:00:00Z" count="1"/>
      </bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="file:///home/u/pic.png" added="2026-09-03T10:00:00Z" modified="2026-09-03T10:00:00Z" visited="2026-09-03T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <bookmark:applications>
        <bookmark:application name="Image Viewer" exec="&apos;/usr/bin/loupe %U&apos;" modified="2026-09-03T10:00:00Z" count="2"/>
        <bookmark:application name="code-oss" exec="&apos;code-oss %F&apos;" modified="2026-09-04T10:00:00Z" count="1"/>
      </bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="https://example.com/remote" modified="2026-09-05T10:00:00Z">
    <info><metadata owner="http://freedesktop.org"><bookmark:applications>
      <bookmark:application name="firefox" exec="&apos;firefox %u&apos;" modified="2026-09-05T10:00:00Z" count="1"/>
    </bookmark:applications></metadata></info>
  </bookmark>
</xbel>`;

const entries = parse(fixture);
check("parse: every bookmark", entries.length, 3);
check("parse: href kept raw", entries[0].href, "file:///home/u/notes%20v2.txt");
check("parse: entities decoded in exec", entries[0].apps[0].exec, "'code-oss %F'");
check("parse: all applications of an entry", entries[1].apps.map(a => a.name), ["Image Viewer", "code-oss"]);

check("appsOf: exec's binary before the recorder's name",
      appsOf(entries[0].apps[0]), ["code-oss", "org.gnome.Nautilus"]);
check("appsOf: path stripped from the binary", appsOf(entries[1].apps[0])[0], "loupe");

// A fake key resolver: the first candidate the "dock" knows.
const known = { "code-oss": "code-oss", "loupe": "org.gnome.Loupe", "firefox": "firefox" };
const keyOf = names => { for (const n of names) if (known[n]) return known[n]; return ""; };
const r = byApp(entries, keyOf, 5);
check("byApp: attributed to the OPENER, not the recorder",
      r["code-oss"].map(f => f.name), ["pic.png", "notes v2.txt"]);
check("byApp: newest first", r["code-oss"][0].time > r["code-oss"][1].time, true);
check("byApp: path decoded", r["code-oss"][1].path, "/home/u/notes v2.txt");
check("byApp: remote URLs skipped", r["firefox"], undefined);
check("byApp: limit respected", byApp(entries, keyOf, 1)["code-oss"].length, 1);
check("byApp: unknown apps dropped", Object.keys(byApp(entries, () => "", 5)), []);

check("decode: numeric entities", decode("a&#38;b&#x41;"), "a&bA");
check("parse: garbage in, nothing out", parse("<not xbel>"), []);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
