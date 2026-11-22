.pragma library

// ── procs.js ──────────────────────────────────────────────────────────────────
// The Tasks tab's logic, pure: which process rows show for a search, their order, and the one command that ends them.
// Rows are scripts/top-procs.py's ({ name, cpu, mb, procs, pids }).
//
//   filterRows   the rows whose name holds the search text (case-blind); "" keeps all.
//   sortRows     by "cpu", "mem", "disk" (busiest first) or "name".
//   protectedRow a row the shell refuses to end: the compositor, the shell itself, init.
//   sections     the rows under an Apps header and a Processes header (a header folds its section).
//   mergeRows    the CPU list and the memory list as one row per name (the Tasks tab shows every task, not two lists).
//   killArgv     the `kill` command for a row's pids (TERM, or KILL when forced). "" when there is nothing safe to end.
// ─────────────────────────────────────────────────────────────────────────────

var PROTECTED = ["Hyprland", "qs", "quickshell", "systemd", "Xwayland", "dbus-daemon", "pipewire", "wireplumber"]

function filterRows(rows, query) {
    var q = String(query || "").trim().toLowerCase()
    var list = Array.isArray(rows) ? rows : []
    if (q === "") return list.slice()
    return list.filter(function (r) { return String(r.name).toLowerCase().indexOf(q) >= 0 })
}

// by "cpu", "mem", "disk", "gpu" (the busiest first, ties by the other numbers, then name) or "name" (A to Z).
function sortRows(rows, by) {
    var list = rows.slice()
    if (by === "name") return list.sort(function (a, b) { return String(a.name).localeCompare(String(b.name)) })
    var key = by === "mem" ? "mb" : by === "disk" ? "disk" : by === "gpu" ? "gpu" : "cpu"
    var keys = ["cpu", "mb", "disk", "gpu"].filter(function (k) { return k !== key })
    return list.sort(function (a, b) {
        if (b[key] !== a[key]) return b[key] - a[key]
        if (b[keys[0]] !== a[keys[0]]) return b[keys[0]] - a[keys[0]]
        if (b[keys[1]] !== a[keys[1]]) return b[keys[1]] - a[keys[1]]
        if (b[keys[2]] !== a[keys[2]]) return b[keys[2]] - a[keys[2]]
        return String(a.name) < String(b.name) ? -1 : String(a.name) > String(b.name) ? 1 : 0
    })
}

// The rows under two headers, as Mission Center lists them: the tasks that are apps (isApp(name)), then the rest. A
// header is { name: "#section:<key>", head: true, key: "apps"|"procs", count }; a collapsed section keeps only its
// header. Protected rows are never apps. The order inside a section is the order given.
function sections(rows, isApp, collapsed) {
    var apps = [], procs = []
    var shut = collapsed || {}
    rows.forEach(function (r) { (!protectedRow(r) && isApp(r.name) ? apps : procs).push(r) })
    var out = []
    function add(key, list) {
        if (list.length === 0) return
        out.push({ name: "#section:" + key, head: true, key: key, count: list.length })
        if (!shut[key]) list.forEach(function (r) { out.push(r) })
    }
    add("apps", apps)
    add("procs", procs)
    return out
}

// One row per name; `cores` turns top-procs's percent-of-one-core into percent of the machine. CPU comes from the CPU list (0 when the task was idle, so it is not in it), memory from the memory
// list (or the CPU list's when it is not in that one). Pids and members are the memory row's, else the CPU row's.
function mergeRows(cpuRows, memRows, cores) {
    var n = Math.max(1, Math.floor(Number(cores)) || 1)
    var byName = {}, order = []
    // Percent of ONE core in, percent of the WHOLE machine out (0..100), so a busy task never reads over 100.
    function share(v) { return Math.min(100, (Number(v) || 0) / n) }
    function take(r, fromCpu) {
        if (!r || typeof r.name !== "string") return
        var o = byName[r.name]
        if (!o) { o = byName[r.name] = { name: r.name, cpu: 0, mb: 0, procs: 0, disk: 0, gpu: 0, pids: [], members: [] }; order.push(r.name) }
        o.disk = Math.max(o.disk, Number(r.disk) || 0)
        o.gpu = Math.max(o.gpu, Math.min(100, Number(r.gpu) || 0))
        if (o.members.length === 0 && Array.isArray(r.members)) o.members = r.members.map(function (m) { return { pid: m.pid, cpu: share(m.cpu), mb: m.mb, disk: m.disk, gpu: Math.min(100, Number(m.gpu) || 0) } })
        if (fromCpu) o.cpu = Math.max(o.cpu, share(r.cpu))
        o.mb = Math.max(o.mb, Number(r.mb) || 0)
        o.procs = Math.max(o.procs, Number(r.procs) || 0)
        if (o.pids.length === 0 && Array.isArray(r.pids)) o.pids = r.pids.slice()
    }
    var cl = Array.isArray(cpuRows) ? cpuRows : []
    var ml = Array.isArray(memRows) ? memRows : []
    cl.forEach(function (r) { take(r, true) })
    ml.forEach(function (r) { take(r, false) })
    return order.map(function (n) { return byName[n] })
}

function protectedRow(row) {
    return PROTECTED.indexOf(String(row && row.name)) >= 0
}

// The pids that may be ended: whole numbers above init and the kernel's 0..2, no duplicates, at most 64.
function killArgv(row, force) {
    if (!row || protectedRow(row) || !Array.isArray(row.pids)) return []
    var pids = []
    for (var i = 0; i < row.pids.length && pids.length < 64; i++) {
        var p = row.pids[i]
        if (typeof p === "number" && p > 2 && Math.floor(p) === p && pids.indexOf(p) < 0) pids.push(p)
    }
    if (pids.length === 0) return []
    return ["kill", force ? "-KILL" : "-TERM"].concat(pids.map(String))
}
