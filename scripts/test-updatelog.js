// ── test-updatelog.js ─────────────────────────────────────────────────────────
// Regression tests for services/updatelog.js. `bun scripts/test-updatelog.js`
// The log and pacman samples are real shapes from this machine (the first lines of each fixture).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "updatelog.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const L = new Function(src + "\nreturn { formatBytes, parseSizeText, signedBytes, parseSizes, flatpakSize, validName, validVersion, downgradeCmd, snapshotCommand, snapshotTool, parseHistory, recentChanges, parsePacmanInfo, splitInfo, officialLines, aurLines, flatpakLines, failureHint };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

// ── sizes ─────────────────────────────────────────────────────────────────────
eq("bytes", [0, 512, 1024, 1536, 2505466, 21490115, 5 * 1073741824].map(L.formatBytes), ["0 B", "512 B", "1 KiB", "1.5 KiB", "2.39 MiB", "20.5 MiB", "5 GiB"]);
eq("bytes, large and bad", [L.formatBytes(250 * 1048576), L.formatBytes(-1), L.formatBytes(NaN)], ["250 MiB", "", ""]);
eq("size text, binary", [L.parseSizeText("1971.53 KiB"), L.parseSizeText("5 MiB"), L.parseSizeText("512 B")], [2018847, 5242880, 512]);
eq("size text, decimal", [L.parseSizeText("12.3 MB"), L.parseSizeText("340 kB"), L.parseSizeText("1.5 GB")], [12300000, 340000, 1500000000]);
eq("size text, comma decimal", L.parseSizeText("1,5 MB"), 1500000);
eq("size text, garbage", ["", "abc", "12 parsecs", null, undefined].map(x => Number.isNaN(L.parseSizeText(x))), Array(5).fill(true));
eq("signed", [L.signedBytes(307200), L.signedBytes(-1258291), L.signedBytes(100), L.signedBytes(NaN)], ["+300 KiB", "−1.2 MiB", "about the same", ""]);
const SIZES = "sqlite|3.54.0-1|2505466|https://m/x.zst\nbpf|7.2.10-1|2018848|https://m/y.zst\n\nbroken line\nneg|1|-5|u\n";
eq("print format", L.parseSizes(SIZES), { sizes: { sqlite: 2505466, bpf: 2018848 }, total: 4524314 });
eq("print format, empty", L.parseSizes(""), { sizes: {}, total: 0 });
eq("flatpak column", L.flatpakSize("23.4 MB"), 23400000);

// ── names ─────────────────────────────────────────────────────────────────────
eq("valid names", ["linux", "python-pykakasi", "lib32-sqlite", "gtk3", "libstdc++", "a.b_c@d"].map(L.validName), Array(6).fill(true));
eq("invalid names", ["", "-rf", "a b", "a;b", "$(x)", "a/b", "x".repeat(200), null, "a`b"].map(L.validName), Array(9).fill(false));
eq("valid versions", ["6.12.1.arch1-1", "1:2.0-3", "r1234.abc-1", "1.0~rc1-1"].map(L.validVersion), Array(4).fill(true));
eq("invalid versions", ["", "1 2", "1;2", "$(x)", "1\n2"].map(L.validVersion), Array(5).fill(false));
eq("downgrade command", L.downgradeCmd("linux", "6.11.1.arch1-1"), "sudo pacman -U /var/cache/pacman/pkg/linux-*6.11.1.arch1-1-*.pkg.tar*");
eq("downgrade drops the epoch", L.downgradeCmd("qt5-base", "1:5.15.2-1"), "sudo pacman -U /var/cache/pacman/pkg/qt5-base-*5.15.2-1-*.pkg.tar*");
eq("downgrade refuses a bad name or version", [L.downgradeCmd("a;b", "1-1"), L.downgradeCmd("linux", "1 -1"), L.downgradeCmd("", "1-1")], ["", "", ""]);

// ── snapshots ─────────────────────────────────────────────────────────────────
eq("snapper command", L.snapshotCommand("snapper"), "sudo -S snapper -c root create --type single --description 'Quicktest: before system update'");
eq("timeshift command", L.snapshotCommand("timeshift"), "sudo -S timeshift --create --comments 'Quicktest: before system update' --scripted");
eq("unknown tool", [L.snapshotCommand("zfs"), L.snapshotCommand(""), L.snapshotCommand(undefined)], ["", "", ""]);
eq("tool detection", [L.snapshotTool("/usr/bin/snapper\n"), L.snapshotTool("/usr/bin/timeshift"), L.snapshotTool("/usr/bin/timeshift\n/usr/bin/snapper"), L.snapshotTool(""), L.snapshotTool("/usr/bin/snapperd")],
   ["snapper", "timeshift", "snapper", "", ""]);

// ── history ───────────────────────────────────────────────────────────────────
const LOG = [
  "[2026-10-10T12:00:00+0100] [PACMAN] Running 'pacman -Syu'",
  "[2026-10-10T12:00:01+0100] [PACMAN] starting full system upgrade",
  "[2026-10-10T12:00:09+0100] [ALPM] transaction started",
  "[2026-10-10T12:00:10+0100] [ALPM] upgraded linux (6.11.1.arch1-1 -> 6.12.1.arch1-1)",
  "[2026-10-10T12:00:10+0100] [ALPM] upgraded openssl (3.6.4-1 -> 3.6.5-1)",
  "[2026-10-10T12:00:11+0100] [ALPM] installed newlib (1.0-1)",
  "[2026-10-10T12:00:12+0100] [ALPM] removed oldlib (0.9-1)",
  "[2026-10-10T12:00:13+0100] [ALPM] transaction completed",
  "[2026-10-10T12:00:14+0100] [ALPM] running '30-systemd-update.hook'...",
  "[2026-10-11T22:58:50+0100] [PACMAN] Running 'pacman -S tesseract-data-jpn'",
  "[2026-10-11T22:58:51+0100] [ALPM] transaction started",
  "[2026-10-11T22:58:51+0100] [ALPM] installed tesseract-data-jpn (2:4.1.0-5)",
  "[2026-10-11T22:58:51+0100] [ALPM] transaction completed",
  "[2026-10-11T23:10:00+0100] [PACMAN] Running 'pacman -S broken'",
  "[2026-10-11T23:10:01+0100] [ALPM] transaction started",
  "[2026-10-11T23:10:02+0100] [ALPM] installed broken (1-1)",
  "[2026-10-11T23:10:03+0100] [ALPM] transaction failed",
  "[2026-10-12T21:00:00+0100] [PACMAN] Running 'pacman -Syu'",
  "[2026-10-12T21:00:01+0100] [ALPM] transaction started",
  "[2026-10-12T21:00:02+0100] [ALPM] transaction completed",
  "[2026-10-12T21:03:11+0100] [PACMAN] Running 'pacman -U /home/x/.cache/yay/foo/foo-1.0-1-any.pkg.tar.zst'",
  "[2026-10-12T21:03:12+0100] [ALPM] transaction started",
  "[2026-10-12T21:03:12+0100] [ALPM] downgraded foo (2.0-1 -> 1.0-1)",
  "[2026-10-12T21:03:13+0100] [ALPM] transaction completed",
  "garbage line",
].join("\n");
const H = L.parseHistory(LOG, 12);
eq("history: newest first, empty and failed transactions dropped", H.map(t => t.cmd), ["pacman -U /home/x/.cache/yay/foo/foo-1.0-1-any.pkg.tar.zst", "pacman -S tesseract-data-jpn", "pacman -Syu"]);
eq("history: the full upgrade", [H[2].upgraded, H[2].installed, H[2].removed, H[2].count, H[2].full],
   [[{ name: "linux", from: "6.11.1.arch1-1", to: "6.12.1.arch1-1" }, { name: "openssl", from: "3.6.4-1", to: "3.6.5-1" }], [{ name: "newlib", to: "1.0-1" }], [{ name: "oldlib", from: "0.9-1" }], 4, true]);
eq("history: a single install is not a full upgrade", [H[1].full, H[1].count, H[1].installed[0].to], [false, 1, "2:4.1.0-5"]);
eq("history: downgrades", H[0].downgraded, [{ name: "foo", from: "2.0-1", to: "1.0-1" }]);
eq("history: the time", H[2].when, new Date("2026-10-10T12:00:09+01:00").getTime());
eq("history: capped", L.parseHistory(LOG, 2).length, 2);
eq("history: nothing", [L.parseHistory("", 5), L.parseHistory(null, 5)], [[], []]);
// recentChanges: one row per package, newest transaction first. Dates are local days, so the
// test runs in a fixed zone (TZ is read per Date call by V8/JSC).
process.env.TZ = "Europe/Lisbon";
const R = L.recentChanges(H, 10);
eq("recent: newest transaction first, one row each", R.map(r => [r.action, r.name, r.to]),
   [["downgraded", "foo", "1.0-1"], ["installed", "tesseract-data-jpn", "2:4.1.0-5"],
    ["upgraded", "linux", "6.12.1.arch1-1"], ["upgraded", "openssl", "3.6.5-1"],
    ["installed", "newlib", "1.0-1"], ["removed", "oldlib", "0.9-1"]]);
eq("recent: the local day", R[0].date, "2026-10-12");
eq("recent: capped", L.recentChanges(H, 2).length, 2);
eq("recent: nothing", [L.recentChanges([], 5), L.recentChanges(null, 5)], [[], []]);
eq("history: a transaction still open is not listed", L.parseHistory("[2026-10-12T21:00:01+0100] [ALPM] transaction started\n[2026-10-12T21:00:02+0100] [ALPM] installed x (1-1)", 5), []);

// ── details ───────────────────────────────────────────────────────────────────
const SI = [
  "Repository      : extra", "Name            : bpf", "Version         : 7.2.10-1", "Description     : BPF tools",
  "Architecture    : x86_64", "URL             : https://www.kernel.org", "Depends On      : glibc  readline  zlib",
  "                  libelf  libcap", "Download Size   : 1971.53 KiB", "Installed Size  : 5964.44 KiB",
  "Packager        : Christian Heusel <gromit@archlinux.org>", "Build Date      : Mon 12 Oct 2026 11:07:21 AM WEST",
].join("\n");
const QI = ["Name            : bpf", "Version         : 7.2.9-1", "Installed Size  : 5640.00 KiB"].join("\n");
const P = L.parsePacmanInfo(SI);
eq("info: fields", [P["Name"], P["Description"], P["URL"], P["Download Size"]], ["bpf", "BPF tools", "https://www.kernel.org", "1971.53 KiB"]);
eq("info: a wrapped value carries on", P["Depends On"], "glibc  readline  zlib libelf  libcap");
eq("info: split", [L.splitInfo(SI + "\n__INSTALLED__\n" + QI).old["Version"], L.splitInfo(SI + "\n__INSTALLED__\n" + QI).next["Version"]], ["7.2.9-1", "7.2.10-1"]);
eq("info: nothing installed", L.splitInfo(SI).old, {});
const rows = L.officialLines(L.parsePacmanInfo(SI), L.parsePacmanInfo(QI), 2018848);
eq("official rows", rows.map(r => r.label), ["About", "Upstream", "Repository", "Download", "Installed", "Built"]);
eq("official: the download comes from the print format when it has it", rows[3].value, "1.93 MiB");
eq("official: installed with its delta", rows[4].value, "5.82 MiB  (+324 KiB)");
eq("official: the packager's e-mail is dropped", rows[2].value, "extra  ·  Christian Heusel");
eq("official: upstream is a link", rows[1].link, "https://www.kernel.org");
eq("official: without the print format, the field", L.officialLines(L.parsePacmanInfo(SI), {}, NaN)[3].value, "1.93 MiB");
eq("official: nothing at all", L.officialLines({}, {}, NaN), []);
const AUR = { Description: "A thing", URL: "https://x", Maintainer: null, NumVotes: 12, Popularity: 0.5, OutOfDate: 1760000000, LastModified: 1760100000 };
const A = L.aurLines(AUR);
eq("aur rows", A.map(r => r.label), ["About", "Upstream", "Maintainer", "Votes", "Flagged", "Updated"]);
eq("aur: orphaned and flagged are warnings", [A[2].tone, A[4].tone, A[2].value], ["warn", "warn", "none — orphaned"]);
eq("aur: votes", A[3].value, "12  ·  popularity 0.50");
eq("aur: a healthy one", L.aurLines({ Description: "x", Maintainer: "bob", NumVotes: 1 }).map(r => r.tone || ""), ["", "", ""]);
eq("aur: nothing", L.aurLines(null), []);
eq("flatpak rows", L.flatpakLines("50.1", 23400000).map(r => r.value), ["50.1", "22.3 MiB"]);

// ── failure hints ─────────────────────────────────────────────────────────────
// The first two are the real Oct 14 2026 failure: three mirrors, all 404.
const M404 = ["error: failed retrieving file 'hwloc-2.15.0-1-x86_64.pkg.tar.zst' from mirrors.up.pt : The requested URL returned error: 404",
              "warning: failed to retrieve some files", "error: failed to commit transaction (failed to retrieve some files)"];
eq("hint: mirrors 404", /out of sync/.test(L.failureHint(M404)), true);
eq("hint: a timeout is the network, not the mirror's state", /Couldn't download/.test(L.failureHint(["error: failed retrieving file 'x' from m : Connection timed out after 10001 milliseconds"])), true);
eq("hint: DNS", /Couldn't download/.test(L.failureHint(["curl: Could not resolve host: mirrors.up.pt"])), true);
eq("hint: db lock", /db\.lck/.test(L.failureHint(["error: failed to init transaction (unable to lock database)"])), true);
eq("hint: signature", /keyring/.test(L.failureHint(["error: foo: signature from \"X\" is unknown trust", ":: File /var/cache/pacman/pkg/foo is corrupted (invalid or corrupted package (PGP signature))."])), true);
eq("hint: 404 beats generic download", /out of sync/.test(L.failureHint(["error: failed retrieving file 'a' from m : Connection timed out", ...M404])), true);
eq("hint: unrecognised, empty, missing", [L.failureHint(["error: target not found: foo"]), L.failureHint([]), L.failureHint(undefined)], ["", "", ""]);

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
