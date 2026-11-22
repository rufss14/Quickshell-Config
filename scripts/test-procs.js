// ── test-procs.js ─────────────────────────────────────────────────────────────
// Tests for services/procs.js: the Tasks tab's search, order, and the kill command.
//
//     bun scripts/test-procs.js      (or: node scripts/test-procs.js)
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "procs.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const T = new Function(src + "\nreturn { filterRows, sortRows, mergeRows, sections, protectedRow, killArgv };")();

let pass = 0, fail = 0;
function check(name, ok, detail) {
    if (ok) pass++; else { fail++; console.log("FAIL", name, detail === undefined ? "" : JSON.stringify(detail)); }
}
const rows = [
    { name: "spotify", cpu: 10, mb: 300, procs: 2, pids: [30, 31] },
    { name: "Discord", cpu: 25, mb: 900, procs: 1, pids: [40] },
    { name: "firefox", cpu: 10, mb: 2000, procs: 1, pids: [50] },
    { name: "Hyprland", cpu: 5, mb: 100, procs: 1, pids: [60] },
];

check("empty search keeps all", T.filterRows(rows, "  ").length === 4);
check("search is case-blind and partial", T.filterRows(rows, "FIRE").map(r => r.name).join() === "firefox");
check("search on nothing", T.filterRows(rows, "zzz").length === 0);
check("search does not change input", rows.length === 4);
check("sort by cpu, ties by memory", T.sortRows(rows, "cpu").map(r => r.name).join() === "Discord,firefox,spotify,Hyprland",
    T.sortRows(rows, "cpu").map(r => r.name));
check("sort by memory", T.sortRows(rows, "mem").map(r => r.name).join() === "firefox,Discord,spotify,Hyprland");
check("sort by disk", T.sortRows([{ name: "a", cpu: 1, mb: 1, disk: 2 }, { name: "b", cpu: 9, mb: 9, disk: 5 }], "disk").map(r => r.name).join() === "b,a");
check("sort by gpu", T.sortRows([{ name: "a", cpu: 9, mb: 9, disk: 9, gpu: 1 }, { name: "b", cpu: 1, mb: 1, disk: 1, gpu: 40 }], "gpu").map(r => r.name).join() === "b,a");
check("merge: gpu is capped at 100", T.mergeRows([{ name: "a", gpu: 250 }], [], 1)[0].gpu === 100);
check("sort by name A to Z", T.sortRows(rows, "name").map(r => r.name).join() === "Discord,firefox,Hyprland,spotify");
check("sort returns a copy", T.sortRows(rows, "cpu") !== rows);
const merged = T.mergeRows([{ name: "a", cpu: 50, mb: 10, procs: 1, pids: [7] }], [{ name: "b", cpu: 0, mb: 90, procs: 2, pids: [8, 9] }, { name: "a", cpu: 0, mb: 20, procs: 1, pids: [7] }]);
check("merge: one row per name", merged.map(r => r.name).join() === "a,b", merged);
check("merge: cpu from the cpu list, memory from the memory list", merged[0].cpu === 50 && merged[0].mb === 20 && merged[1].cpu === 0 && merged[1].mb === 90);
check("merge: pids kept", merged[1].pids.join() === "8,9" && merged[0].pids.join() === "7");
check("merge: disk and members come through", merged[1].disk === 0 && merged[0].members.length === 0);
const wide = T.mergeRows([{ name: "a", cpu: 400, mb: 1, procs: 1, pids: [7], members: [{ pid: 7, cpu: 200, mb: 1, disk: 0 }] }], [], 8);
check("merge: cpu is a share of the whole machine", wide[0].cpu === 50 && wide[0].members[0].cpu === 25, wide[0]);
check("merge: never over 100", T.mergeRows([{ name: "a", cpu: 900 }], [], 2)[0].cpu === 100);
check("merge: nothing in, nothing out", T.mergeRows(null, undefined).length === 0);
const isApp = n => n === "spotify" || n === "Hyprland";
const sec = T.sections(rows, isApp, {});
check("sections: apps first, then the rest, each under a header",
    sec.map(r => r.head ? "[" + r.key + r.count + "]" : r.name).join() === "[apps1],spotify,[procs3],Discord,firefox,Hyprland", sec.map(r => r.name));
check("sections: a protected row is never an app", !sec.some(r => r.name === "Hyprland" && sec.indexOf(r) < sec.findIndex(x => x.key === "procs")));
check("sections: a folded section keeps only its header", T.sections(rows, isApp, { apps: true }).map(r => r.name).join() === "#section:apps,#section:procs,Discord,firefox,Hyprland");
check("sections: an empty section has no header", T.sections(rows, () => false, {}).filter(r => r.head).length === 1);
check("the compositor is protected", T.protectedRow(rows[3]) && !T.protectedRow(rows[0]));
check("kill TERM by default", T.killArgv(rows[0], false).join(" ") === "kill -TERM 30 31");
check("kill KILL when forced", T.killArgv(rows[1], true).join(" ") === "kill -KILL 40");
check("protected refuses", T.killArgv(rows[3], false).length === 0);
check("init and kernel pids refused", T.killArgv({ name: "x", pids: [0, 1, 2] }, false).length === 0);
check("bad pids dropped, duplicates merged", T.killArgv({ name: "x", pids: [5, 5, 5.5, "9", -3, 6] }, false).join(" ") === "kill -TERM 5 6");
check("no pids, no command", T.killArgv({ name: "x", pids: [] }, false).length === 0 && T.killArgv(null, false).length === 0);
check("at most 64 pids", T.killArgv({ name: "x", pids: Array.from({ length: 100 }, (_, i) => i + 10) }, false).length === 2 + 64);

console.log(fail === 0 ? "ok  " + pass + " checks" : fail + " FAILED of " + (pass + fail));
process.exit(fail === 0 ? 0 : 1);
