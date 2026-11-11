// ── test-nmcli.js ─────────────────────────────────────────────────────────────
// Pins services/nmcli.js: nmcli's terse escaping, which VPN rows survive, and the
// error text a failed up/down turns into.
//
//     bun scripts/test-nmcli.js          (or: node scripts/test-nmcli.js)
//
// Loads the real file with its `.pragma library` line stripped. Touches nothing.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "nmcli.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const N = new Function(src + "\nreturn { splitTerse, vpnRows, validUuid, vpnError };")();

let pass = 0;
const failures = [];
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, got, want) {
    if (eq(got, want)) { pass++; return; }
    failures.push(`  ${name}\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`);
}

const U1 = "3f1c2a9e-1b2c-4d5e-8f90-a1b2c3d4e5f6";
const U2 = "0a0b0c0d-1111-2222-3333-444455556666";

// ── splitTerse ────────────────────────────────────────────────────────────────
check("plain", N.splitTerse("a:b:c"), ["a", "b", "c"]);
check("escaped colon stays in the field", N.splitTerse("work\\: vpn:x"), ["work: vpn", "x"]);
check("escaped backslash", N.splitTerse("a\\\\b:c"), ["a\\b", "c"]);
check("empty trailing field", N.splitTerse("a:b:"), ["a", "b", ""]);
check("trailing lone backslash kept", N.splitTerse("a\\"), ["a\\"]);
check("null", N.splitTerse(null), [""]);

// ── vpnRows ───────────────────────────────────────────────────────────────────
const lines = [
    "Wired connection 1:" + U2 + ":802-3-ethernet:activated",
    "Zeta\\: office:" + U1 + ":vpn:",
    "home wg:" + U2 + ":wireguard:activating",
    "evil:not-a-uuid:vpn:",
    "short:line",
];
check("only vpn + wireguard, sorted, escaped name", N.vpnRows(lines), [
    { name: "home wg", uuid: U2, type: "wireguard", state: "activating" },
    { name: "Zeta: office", uuid: U1, type: "vpn", state: "" },
]);
check("no input", N.vpnRows(undefined), []);
check("uuid ok", N.validUuid(U1), true);
check("uuid with an option smuggled in", N.validUuid("--help"), false);

// ── vpnError ──────────────────────────────────────────────────────────────────
check("secrets", N.vpnError("Error: Connection activation failed: Secrets were required, but not provided.", 4).startsWith("This VPN needs a password"), true);
check("timeout", N.vpnError("", 3), "NetworkManager gave up waiting (30 s).");
check("not found", N.vpnError("Error: unknown connection 'x'.", 10), "That VPN profile no longer exists.");
check("last line, Error: dropped", N.vpnError("Warning: x\nError: Connection activation failed: plugin died.", 4),
      "Connection activation failed: plugin died.");
check("nothing on stderr", N.vpnError("", 1), "nmcli failed (exit 1).");

if (failures.length) {
    console.log(failures.join("\n"));
    console.log(`test-nmcli: ${pass} passed, ${failures.length} failed`);
    process.exit(1);
}
console.log(`test-nmcli: ${pass} passed`);
