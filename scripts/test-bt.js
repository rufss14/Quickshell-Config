// ── test-bt.js ────────────────────────────────────────────────────────────────
// Regression tests for services/bt.js — the Bluetooth logic.
//
//     bun scripts/test-bt.js          (or: node scripts/test-bt.js)
//
// Safe to run: bt.js is pure functions and touches nothing.
//
// The card fixture's SHAPE is a real `pactl -f json list cards` capture (an ALSA
// card on this machine — same schema for every driver); the bluez profile NAMES are
// PipeWire's bluez5 naming (a2dp-sink[-codec], headset-head-unit[-codec]). No
// Bluetooth audio device was connected while this was written, so re-capture one
// into BT_CARDS when one is: `pactl -f json list cards`.
//
// Loaded by stripping the `.pragma library` line, as test-sysstats.js does.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "bt.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { signalBars, compareNearby, batteryAlert, cleanAlias, codecLabel, profileKind,
        cardName, parseCard, profileFor, validAddress, transferFraction } =
    new Function(src + "\nreturn { signalBars, compareNearby, batteryAlert, cleanAlias, " +
                 "codecLabel, profileKind, cardName, parseCard, profileFor, validAddress, " +
                 "transferFraction };")();

let pass = 0;
let fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

// ── signalBars ────────────────────────────────────────────────────────────────
check("bars: no reading", signalBars(undefined), -1);
check("bars: null", signalBars(null), -1);
check("bars: NaN", signalBars(NaN), -1);
check("bars: in the room", signalBars(-45), 4);
check("bars: -60 boundary", signalBars(-60), 4);
check("bars: -61", signalBars(-61), 3);
check("bars: -80", signalBars(-80), 2);
check("bars: -90 edge", signalBars(-90), 1);
check("bars: -95 gone", signalBars(-95), 0);

// ── compareNearby ─────────────────────────────────────────────────────────────
{
    const list = [
        { name: "Zed", bars: 2 }, { name: "Alpha", bars: -1 },
        { name: "Mid", bars: 4 }, { name: "Beta", bars: 2 },
    ];
    check("nearby: closest first, unknown last, ties by name",
          list.slice().sort(compareNearby).map(d => d.name), ["Mid", "Beta", "Zed", "Alpha"]);
}

// ── batteryAlert ──────────────────────────────────────────────────────────────
{
    const low = 0.2;
    let s = { alert: "", last: 1 };
    const seq = [];
    for (const lvl of [0.5, 0.21, 0.2, 0.19, 0.2, 0.18, 0.1, 0.09, 0.3, 0.2]) {
        s = batteryAlert(lvl, s.last, low);
        seq.push(s.alert);
    }
    // 0.2 low once; wobble to 0.2/0.18 silent; 0.1 critical once; charge to 0.3
    // resets; the next 0.2 warns again.
    check("battery: one warning per threshold per discharge", seq,
          ["", "", "low", "", "", "", "critical", "", "", "low"]);

    check("battery: arrives already critical → critical only",
          batteryAlert(0.05, 1, low), { alert: "critical", last: 0.1 });
    check("battery: inside the release band keeps state",
          batteryAlert(0.23, 0.2, low), { alert: "", last: 0.2 });
    check("battery: past the release band resets",
          batteryAlert(0.26, 0.2, low), { alert: "", last: 1 });
    check("battery: no reading is a no-op",
          batteryAlert(undefined, 0.2, low), { alert: "", last: 0.2 });
}

// ── cleanAlias ────────────────────────────────────────────────────────────────
check("alias: trimmed", cleanAlias("  PS5 pad  "), "PS5 pad");
check("alias: empty resets", cleanAlias("   "), "");
check("alias: null input", cleanAlias(null), "");
check("alias: control char refused", cleanAlias("bad\nname"), null);
check("alias: 248 bytes ok", cleanAlias("a".repeat(248)), "a".repeat(248));
check("alias: 249 bytes refused", cleanAlias("a".repeat(249)), null);
check("alias: multibyte counted in bytes", cleanAlias("é".repeat(125)), null);   // 250 bytes
check("alias: emoji ok", cleanAlias("🎧 Buds"), "🎧 Buds");

// ── codecLabel / profileKind ──────────────────────────────────────────────────
check("codec: known", codecLabel("sbc_xq"), "SBC-XQ");
check("codec: case", codecLabel("LDAC"), "LDAC");
check("codec: unknown uppercased", codecLabel("newcodec"), "NEWCODEC");
check("codec: empty", codecLabel(""), "");
check("kind: a2dp best", profileKind("a2dp-sink"), { kind: "music", codec: "" });
check("kind: a2dp codec", profileKind("a2dp-sink-aac"), { kind: "music", codec: "aac" });
check("kind: hfp codec", profileKind("headset-head-unit-msbc"), { kind: "calls", codec: "msbc" });
check("kind: bap duplex", profileKind("bap-duplex"), { kind: "calls", codec: "" });
check("kind: off", profileKind("off"), { kind: "off", codec: "" });
check("kind: other", profileKind("a2dp-source"), { kind: "other", codec: "" });

// ── parseCard / profileFor ────────────────────────────────────────────────────
check("cardName", cardName("f8:5c:7e:8a:11:95"), "bluez_card.F8_5C_7E_8A_11_95");

const BT_CARDS = JSON.stringify([
    {   // an unrelated ALSA card, real shape
        name: "alsa_card.usb-SteelSeries_Arctis_Nova_3-00", driver: "alsa",
        active_profile: "output:analog-stereo+input:analog-stereo",
        profiles: { "off": { description: "Off", sinks: 0, sources: 0, priority: 0, available: true } }
    },
    {
        name: "bluez_card.F8_5C_7E_8A_11_95", driver: "module-bluez5-device.c",
        active_profile: "a2dp-sink-aac",
        profiles: {
            "off":                    { description: "Off", sinks: 0, sources: 0, priority: 0, available: true },
            "a2dp-sink-sbc":          { description: "High Fidelity Playback (A2DP Sink, codec SBC)", priority: 18, available: true },
            "a2dp-sink-sbc_xq":       { description: "High Fidelity Playback (A2DP Sink, codec SBC-XQ)", priority: 17, available: true },
            "a2dp-sink-aac":          { description: "High Fidelity Playback (A2DP Sink, codec AAC)", priority: 19, available: true },
            "a2dp-sink-ldac":         { description: "High Fidelity Playback (A2DP Sink, codec LDAC)", priority: 20, available: false },
            "a2dp-sink":              { description: "High Fidelity Playback (A2DP Sink)", priority: 40, available: true },
            "headset-head-unit-cvsd": { description: "Headset Head Unit (HSP/HFP, codec CVSD)", priority: 1, available: true },
            "headset-head-unit-msbc": { description: "Headset Head Unit (HSP/HFP, codec mSBC)", priority: 2, available: true },
            "headset-head-unit":      { description: "Headset Head Unit (HSP/HFP)", priority: 30, available: true },
        }
    }
]);

check("parseCard: music card", parseCard(BT_CARDS, "F8:5C:7E:8A:11:95"), {
    card: "bluez_card.F8_5C_7E_8A_11_95", active: "a2dp-sink-aac", kind: "music", codec: "aac",
    music: true, calls: true,
    // available only (LDAC is not), priority order, only the ACTIVE mode's codecs
    codecs: [
        { profile: "a2dp-sink-aac",    codec: "aac",    label: "AAC" },
        { profile: "a2dp-sink-sbc",    codec: "sbc",    label: "SBC" },
        { profile: "a2dp-sink-sbc_xq", codec: "sbc_xq", label: "SBC-XQ" },
    ]
});
{
    const calls = JSON.parse(BT_CARDS);
    calls[1].active_profile = "headset-head-unit";
    const r = parseCard(JSON.stringify(calls), "f8:5c:7e:8a:11:95");
    check("parseCard: calls mode lists call codecs", [r.kind, r.codec, r.codecs.map(c => c.codec)],
          ["calls", "", ["msbc", "cvsd"]]);
}
check("parseCard: no such card", parseCard(BT_CARDS, "00:11:22:33:44:55"), null);
check("parseCard: garbage", parseCard("not json", "F8:5C:7E:8A:11:95"), null);
check("parseCard: not a list", parseCard("{}", "F8:5C:7E:8A:11:95"), null);
check("parseCard: profiles missing",
      parseCard(JSON.stringify([{ name: "bluez_card.F8_5C_7E_8A_11_95" }]), "F8:5C:7E:8A:11:95"), null);

check("profileFor: music prefers the codec-less best", profileFor(BT_CARDS, "F8:5C:7E:8A:11:95", "music"), "a2dp-sink");
check("profileFor: calls", profileFor(BT_CARDS, "F8:5C:7E:8A:11:95", "calls"), "headset-head-unit");
{
    const noBest = JSON.parse(BT_CARDS);
    delete noBest[1].profiles["headset-head-unit"];
    check("profileFor: no best → highest-priority codec",
          profileFor(JSON.stringify(noBest), "F8:5C:7E:8A:11:95", "calls"), "headset-head-unit-msbc");
}
check("profileFor: garbage", profileFor("x", "F8:5C:7E:8A:11:95", "music"), "");

// ── validAddress / transferFraction ───────────────────────────────────────────
check("address: ok", validAddress("F8:5C:7E:8A:11:95"), true);
check("address: lower ok", validAddress("f8:5c:7e:8a:11:95"), true);
check("address: short", validAddress("F8:5C:7E:8A:11"), false);
check("address: injection", validAddress("F8:5C:7E:8A:11:95; rm"), false);
check("transfer: half", transferFraction({ status: "active", sent: 50, size: 100 }), 0.5);
check("transfer: unknown size", transferFraction({ status: "active", sent: 50, size: 0 }), 0);
check("transfer: complete", transferFraction({ status: "complete", sent: 0, size: 0 }), 1);
check("transfer: null", transferFraction(null), 0);

console.log(`${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
