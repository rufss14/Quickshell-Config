// ── test-sysstats.js ──────────────────────────────────────────────────────────
// Regression tests for services/sysstats.js, the system stats pill's logic.
//
//     bun scripts/test-sysstats.js          (or: node scripts/test-sysstats.js)
//
// Safe to run: sysstats.js is pure functions and touches nothing. The diskstats
// fixture is a real capture from this machine, trimmed.
//
// Loaded by stripping the `.pragma library` line, as test-dock.js does.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "sysstats.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { statsMetrics, netRatio, compactRate, page, move, reorder, parseDf,
        parseDiskstats, diskDelta, alertStep, fitSections, cleanCpuName, gpuName,
        kindGlyph, razerKind, parseRazer, deviceBaseName, mergeDevices, deviceLow,
        deviceLink, kindLabel, deviceRows } =
    new Function(src + "\nreturn { statsMetrics, netRatio, compactRate, page, move, reorder, " +
                 "parseDf, parseDiskstats, diskDelta, alertStep, fitSections, cleanCpuName, gpuName, " +
                 "kindGlyph, razerKind, parseRazer, deviceBaseName, mergeDevices, deviceLow, " +
                 "deviceLink, kindLabel, deviceRows };")();

let pass = 0;
let fail = 0;

function check(name, got, want) {
    const g = JSON.stringify(got);
    const w = JSON.stringify(want);
    if (g === w) {
        pass++;
    } else {
        fail++;
        console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`);
    }
}

// ── statsMetrics / netRatio / compactRate ────────────────────────────────────
check("metrics: order kept", statsMetrics(["net", "cpu"], {}), ["net", "cpu"]);
check("metrics: unknown and repeats dropped", statsMetrics(["cpu", "disco", "cpu", "ram"], {}), ["cpu", "ram"]);
check("metrics: nothing to read, no ring", statsMetrics(["cpu", "gpu", "battery"], { gpu: true, battery: true }), ["cpu"]);
check("metrics: the other rings are known", statsMetrics(["swap", "disk", "diskio", "battery"], {}).length, 4);
check("metrics: temperatures are arcs now, not rings", statsMetrics(["cpu", "cputemp", "gputemp"], {}), ["cpu"]);
check("metrics: garbage in, nothing out", statsMetrics("cpu", {}), []);
check("net: the busier direction", netRatio(1.25e6, 10, 100), 0.1);
check("net: capped at full", netRatio(1e9, 0, 100), 1);
check("net: no ceiling, no ring", netRatio(1e6, 0, 0), 0);
check("rate: idle", compactRate(300), "0");
check("rate: kilobytes", compactRate(340 * 1024), "340K");
check("rate: a few megabytes", compactRate(4.2 * 1024 * 1024), "4.2M");
check("rate: tens of megabytes", compactRate(12.4 * 1024 * 1024), "12M");
check("rate: gigabytes", compactRate(1.5 * 1024 * 1024 * 1024), "1.5G");

// ── page ─────────────────────────────────────────────────────────────────────
const six = ["a", "b", "c", "d", "e", "f"];
check("page: 0 = everything", page(six, 0, 3), { items: six, pages: 1, page: 0 });
check("page: fits on one", page(["a", "b"], 4, 1).pages, 1);
check("page: second page", page(six, 4, 1), { items: ["e", "f"], pages: 2, page: 1 });
check("page: wraps forward", page(six, 4, 2).page, 0);
check("page: wraps backward", page(six, 4, -1).page, 1);

// ── move / reorder ───────────────────────────────────────────────────────────
check("move: down", move(["a", "b", "c"], 0, 2), ["b", "c", "a"]);
check("move: up", move(["a", "b", "c"], 2, 0), ["c", "a", "b"]);
check("move: nowhere", move(["a", "b"], 1, 1), ["a", "b"]);
check("reorder: hidden entries keep their places",
      reorder(["cpu", "gpu", "ram", "net"], ["net", "cpu", "ram"]), ["net", "gpu", "cpu", "ram"]);
check("reorder: another page untouched",
      reorder(["cpu", "ram", "net", "swap"], ["ram", "cpu"]), ["ram", "cpu", "net", "swap"]);

// ── parseDf ──────────────────────────────────────────────────────────────────
check("df: size and used", parseDf("        1B-blocks          Used\n  999653638144 412318683136\n"),
      { total: 999653638144, used: 412318683136 });
check("df: garbage", parseDf("df: /nope: No such file"), null);

// ── parseDiskstats / diskDelta ───────────────────────────────────────────────
const ds1 = `   8       0 sda 100 0 2000 50 200 0 4000 60 0 1000 110 0 0 0 0 0 0
   8       1 sda1 90 0 1800 40 190 0 3800 50 0 900 90 0 0 0 0 0 0
 259       0 nvme0n1 500 0 10000 70 800 0 20000 90 0 5000 160 0 0 0 0 0 0
   7       0 loop0 5 0 10 0 0 0 0 0 0 1 0 0 0 0 0 0 0
 254       0 zram0 5 0 10 0 0 0 0 0 0 1 0 0 0 0 0 0 0`;
const d1 = parseDiskstats(ds1);
check("diskstats: whole disks only", Object.keys(d1), ["sda", "nvme0n1"]);
check("diskstats: sectors are 512 bytes", d1.sda.read, 2000 * 512);
const d2 = parseDiskstats(ds1.replace("nvme0n1 500 0 10000 70 800 0 20000 90 0 5000",
                                      "nvme0n1 600 0 12000 70 900 0 24000 90 0 5500"));
const delta = diskDelta(d1, d2, 1000);
check("disk: read and write rates", [delta.read, delta.write], [2000 * 512, 4000 * 512]);
check("disk: busiest disk's utilisation", [delta.util, delta.busiest], [0.5, "nvme0n1"]);
check("disk: no previous reading", diskDelta(null, d2, 1000), null);

// ── alertStep ────────────────────────────────────────────────────────────────
let a = alertStep(null, 0.95, 0.9, 0.85, 1000, 10000);
check("alert: a spike isn't an alarm", [a.on, a.since], [false, 1000]);
a = alertStep(a, 0.95, 0.9, 0.85, 11000, 10000);
check("alert: sustained, it fires once", [a.on, a.fired], [true, true]);
a = alertStep(a, 0.95, 0.9, 0.85, 12000, 10000);
check("alert: stays on without re-firing", [a.on, a.fired], [true, false]);
a = alertStep(a, 0.87, 0.9, 0.85, 13000, 10000);
check("alert: hovering on the line doesn't flap", a.on, true);
a = alertStep(a, 0.5, 0.9, 0.85, 14000, 10000);
check("alert: clears below release", [a.on, a.since], [false, 0]);
let b = alertStep(null, 0.95, 0.9, 0.85, 0, 10000);
b = alertStep(b, 0.87, 0.9, 0.85, 5000, 10000);
check("alert: a dip resets the clock before it fires", b.since, 0);

// ── fitSections ──────────────────────────────────────────────────────────────
check("fit: everything, with room", fitSections([30, 20, 40], 5, 200), [true, true, true]);
check("fit: the header even when it alone overflows", fitSections([300, 20], 5, 100), [true, false]);
check("fit: a big section skipped, a small one after still fits",
      fitSections([30, 20, 80, 10], 5, 80), [true, true, false, true]);
check("fit: nothing to show is never shown", fitSections([30, -1, 20], 5, 200), [true, false, true]);
check("fit: spacing counts", fitSections([30, 20], 5, 50), [true, false]);

// ── hardware names ───────────────────────────────────────────────────────────
check("cpu: AMD", cleanCpuName("AMD Ryzen 5 5600X 6-Core Processor"), "AMD Ryzen 5 5600X");
check("cpu: Intel", cleanCpuName("Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz"), "Intel Core i7-9700K");
check("cpu: nothing", cleanCpuName(undefined), "");
check("gpu: vulkan, driver suffix dropped",
      gpuName(["PHYSICAL_DEVICE_TYPE_DISCRETE_GPU|AMD Radeon RX 6700 XT (RADV NAVI22)",
               "PHYSICAL_DEVICE_TYPE_CPU|llvmpipe (LLVM 20.1.0, 256 bits)"], ""), "AMD Radeon RX 6700 XT");
check("gpu: discrete beats integrated",
      gpuName(["PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU|Intel(R) UHD Graphics 770 (ADL-S GT1)",
               "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU|NVIDIA GeForce RTX 4070"], ""), "NVIDIA GeForce RTX 4070");
check("gpu: only llvmpipe → lspci",
      gpuName(["PHYSICAL_DEVICE_TYPE_CPU|llvmpipe"],
              "Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700/6700 XT/6750 XT / 6800M/6850M XT]"),
      "AMD Radeon RX 6700/6700 XT/6750 XT / 6800M/6850M XT");
check("gpu: lspci NVIDIA", gpuName([], "NVIDIA Corporation GA104 [GeForce RTX 3070]"), "NVIDIA GeForce RTX 3070");
check("gpu: nothing at all", gpuName([], ""), "");

// ── device batteries ─────────────────────────────────────────────────────────
check("razer: a mouse, no details", parseRazer('[{"serial":"PM1","name":"Razer Viper Ultimate (Wireless)","type":"mouse","battery":84.3,"charging":false}]'),
      [{ key: "razer:PM1", name: "Razer Viper Ultimate (Wireless)", kind: "mouse", level: 0.843, charging: false,
         dpi: null, pollRate: null, firmware: null, idleTime: null, lowAt: null }]);
// A real capture (Viper Ultimate on its dongle, 2026-09-26).
const viper = parseRazer('[{"serial": "PM2215H12301537", "name": "Razer Viper Ultimate (Wireless)", "type": "mouse", "battery": 55.68627450980392, "charging": false, "dpi": [800, 800], "pollRate": 500, "firmware": "v1.6", "idleTime": 300, "lowBattery": 30}]')[0];
check("razer: details", [viper.dpi, viper.pollRate, viper.firmware, viper.idleTime, viper.lowAt], [800, 500, "v1.6", 300, 0.3]);
check("razer: nonsense details dropped",
      (d => [d.dpi, d.pollRate, d.firmware, d.idleTime, d.lowAt])(parseRazer('[{"serial":"S","battery":50,"dpi":"800","pollRate":-1,"firmware":"  ","idleTime":0,"lowBattery":255}]')[0]),
      [null, null, null, null, null]);
check("link", [deviceLink("Razer Viper Ultimate (Wireless)"), deviceLink("X (Wired)"), deviceLink("X (Receiver)"), deviceLink("MX Master")],
      ["wireless", "wired", "wireless", ""]);
check("rows: the real mouse", deviceRows(mergeDevices([[viper]])[0]).map(r => r.text),
      ["Wireless", "800 DPI · 500 Hz", "Sleeps after 5 min", "Low at 30%", "Firmware v1.6"]);
check("rows: charging on its cable", deviceRows({ charging: true, link: "wired" })[0].text, "Charging on its cable");
check("rows: a UPower device knows nothing extra", deviceRows({ charging: false, link: "" }), []);
check("rows: nothing", deviceRows(null), []);
check("kind label", [kindLabel("mouse"), kindLabel("gamepad"), kindLabel("")], ["Mouse", "Controller", "Device"]);
check("razer: asleep (0%) dropped", parseRazer('[{"serial":"PM1","name":"x","type":"mouse","battery":0}]'), []);
check("razer: junk", parseRazer("not json"), []);
check("razer: not a list", parseRazer('{"serial":"x"}'), []);
check("razer: no serial dropped", parseRazer('[{"name":"x","battery":50}]'), []);
check("razer: no name, unknown type", parseRazer('[{"serial":"S","battery":50,"type":"mousemat"}]')[0].name, "Razer device");
check("razer: over 100 clamps", parseRazer('[{"serial":"S","battery":120}]')[0].level, 1);
check("razer: kinds", [razerKind("mouse"), razerKind("Keyboard"), razerKind("headset"), razerKind("mousemat")],
      ["mouse", "keyboard", "headset", ""]);
check("base name", deviceBaseName("Razer Viper Ultimate (Wired)"), "Razer Viper Ultimate");
check("base name: untouched", deviceBaseName("MX Master 3"), "MX Master 3");
check("merge: lowest first",
      mergeDevices([[{ key: "a", name: "Mouse", kind: "mouse", level: 0.8 }],
                     [{ key: "b", name: "Pad", kind: "gamepad", level: 0.3 }]]).map(d => d.key), ["b", "a"]);
check("merge: wireless + wired copy → one, the charging one",
      mergeDevices([[{ key: "w", name: "Razer Viper Ultimate (Wireless)", level: 0.4, charging: false },
                     { key: "c", name: "Razer Viper Ultimate (Wired)",    level: 0.41, charging: true }]]),
      [{ key: "c", name: "Razer Viper Ultimate", level: 0.41, charging: true, kind: "", link: "wired" }]);
check("merge: bad entries skipped", mergeDevices([[null, { key: "x", name: "X" }], null]), []);
check("low", [deviceLow({ level: 0.1, charging: false }, 0.15), deviceLow({ level: 0.1, charging: true }, 0.15),
              deviceLow({ level: 0.5 }, 0.15), deviceLow(undefined, 0.15)], [true, false, false, false]);
check("glyph: unknown kind → battery", kindGlyph("toaster"), "\u{F0079}");
check("metrics: devices is a ring", statsMetrics(["devices"], {}), ["devices"]);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
