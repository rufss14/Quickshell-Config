// Run: bun scripts/test-treemap.js   (exit 1 on any failure)
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "services", "treemap.js"), "utf8").replace(/^\.pragma.*$/m, "")
const { layout } = new Function(src + "\nreturn { layout }")()

let fails = 0, n = 0
function check(name, ok, extra) {
    n++
    if (!ok) { fails++; console.log(`FAIL ${name}${extra ? " — " + extra : ""}`) }
}
const area = t => t.w * t.h
const near = (a, b, eps = 1e-6 * Math.max(1, Math.abs(b))) => Math.abs(a - b) <= eps

for (const [values, W, H] of [
    [[40, 30, 20, 10], 400, 200],
    [[1], 100, 50],
    [[5, 5, 5, 5, 5, 5, 5], 300, 300],
    [[1000, 1, 1, 1, 1], 640, 360],
    [[3, 0, 9, -2, 4], 120, 480],
    [[7, 3, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1], 500, 240],
]) {
    const tiles = layout(values, W, H)
    const pos = values.filter(v => v > 0)
    const sum = pos.reduce((a, b) => a + b, 0)
    check(`count ${values}`, tiles.length === pos.length)
    check(`covers box ${values}`, near(tiles.reduce((a, t) => a + area(t), 0), W * H))
    for (const t of tiles) {
        check(`area share index ${t.index}`, near(area(t), values[t.index] / sum * W * H))
        check(`inside box index ${t.index}`,
            t.x >= -1e-6 && t.y >= -1e-6 && t.x + t.w <= W + 1e-6 && t.y + t.h <= H + 1e-6)
    }
    // No two tiles overlap.
    for (let a = 0; a < tiles.length; a++) for (let b = a + 1; b < tiles.length; b++) {
        const A = tiles[a], B = tiles[b]
        const ox = Math.min(A.x + A.w, B.x + B.w) - Math.max(A.x, B.x)
        const oy = Math.min(A.y + A.h, B.y + B.h) - Math.max(A.y, B.y)
        check(`no overlap ${a}/${b}`, !(ox > 1e-6 && oy > 1e-6))
    }
}
check("empty", layout([], 100, 100).length === 0)
check("all zero", layout([0, 0], 100, 100).length === 0)
check("no room", layout([1, 2], 0, 100).length === 0)
// Squarified, not sliced: equal values in a square should not be hairlines.
const sq = layout([1, 1, 1, 1], 200, 200)
check("squares", sq.every(t => near(t.w, 100) && near(t.h, 100)), JSON.stringify(sq))

console.log(fails ? `${fails} failed` : `${n} passed`)
process.exit(fails ? 1 : 0)
