.pragma library

// ── nmcli.js ──────────────────────────────────────────────────────────────────
// Reading nmcli's terse output, for the one thing Quickshell.Networking can't see: VPN
// connections (services/Net, "VPN"). Pure functions; scripts/test-nmcli.js runs them.
//
// Terse mode (`nmcli -t`) separates fields with ':' and escapes a literal ':' or '\'
// inside a field with '\', so a profile named "work: vpn" arrives as `work\: vpn`.
// Splitting on ':' alone would cut that name in two.

// One terse line → its fields, unescaped.
function splitTerse(line) {
    const out = []
    let cur = ""
    const s = String(line ?? "")
    for (let i = 0; i < s.length; i++) {
        const c = s[i]
        if (c === "\\" && i + 1 < s.length) { cur += s[++i]; continue }
        if (c === ":") { out.push(cur); cur = ""; continue }
        cur += c
    }
    out.push(cur)
    return out
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// `nmcli -t -f NAME,UUID,TYPE,STATE connection show` lines → the VPN profiles, sorted by
// name: [{ name, uuid, type, state }], state "activated" / "activating" / "deactivating" /
// "" (down). NetworkManager's plugin VPNs are type "vpn" (OpenVPN, OpenConnect, …);
// native WireGuard is "wireguard". A line with a malformed UUID is dropped: the UUID is
// what gets handed back to `nmcli connection up`.
function vpnRows(lines) {
    const out = []
    for (const line of lines ?? []) {
        const f = splitTerse(line)
        if (f.length < 4) continue
        const [name, uuid, type, state] = f
        if (type !== "vpn" && type !== "wireguard") continue
        if (!UUID.test(uuid)) continue
        out.push({ name: name, uuid: uuid, type: type, state: state })
    }
    out.sort((a, b) => a.name.localeCompare(b.name))
    return out
}

function validUuid(s) { return UUID.test(String(s ?? "")) }

// What a failed `nmcli connection up/down` says, for a person. nmcli runs with LC_ALL=C
// (Net), so the text matched here is English whatever the user's locale. Exit codes are
// nmcli's own (nmcli(1), "EXIT STATUS").
function vpnError(stderr, code) {
    const s = String(stderr ?? "").trim()
    if (/secrets were required|no secrets|secret agent/i.test(s))
        return "This VPN needs a password and nothing asked for it. Connect it once from "
             + "nm-connection-editor, or run a secret agent such as nm-applet."
    if (code === 3) return "NetworkManager gave up waiting (30 s)."
    if (code === 8) return "NetworkManager isn't running."
    if (code === 10) return "That VPN profile no longer exists."
    const last = s.split("\n").filter(l => l.trim() !== "").pop() ?? ""
    const msg = last.replace(/^Error:\s*/, "")
    return msg !== "" ? msg : "nmcli failed (exit " + code + ")."
}
